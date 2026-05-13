#!/usr/bin/env bash
# gemini_veo.sh — Google Veo 3.1 video generation via Gemini predictLongRunning API.
# Called by generate.sh; not meant to be invoked directly.
#
# Model is pinned to veo-3.1-generate-preview (audio is generated natively).
#
# Request shape (matches the Gemini API reference scripts):
#
#   POST .../models/veo-3.1-generate-preview:predictLongRunning
#   {
#     "instances": [{
#       "prompt": "...",
#       "referenceImages": [           # only when --image is set
#         {
#           "image": {"bytesBase64Encoded": "<base64>", "mimeType": "..."},
#           "referenceType": "asset"
#         }
#       ]
#     }],
#     "parameters": {                  # only when --aspect or --resolution is set
#       "aspectRatio": "16:9",
#       "resolution":  "720p"
#     }
#   }
#
# Flow:
#   1. POST :predictLongRunning  → {"name": "operations/..."}
#   2. GET  operations/<id>      → poll until "done": true  (10s interval, 60 attempts)
#   3. Extract video from response (inline base64 "data" or downloadable "uri")
#   4. Save to output file

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

MODEL="veo-3.1-generate-preview"
ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:predictLongRunning"
OPERATIONS_BASE="https://generativelanguage.googleapis.com/v1beta"

CONFIG_FILE=""
ASPECT=""
RESOLUTION=""
OUTPUT=""
IMAGE=""
PROMPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config)     CONFIG_FILE="$2";   shift 2 ;;
        --aspect)     ASPECT="$2";        shift 2 ;;
        --resolution) RESOLUTION="$2";    shift 2 ;;
        --output)     OUTPUT="$2";        shift 2 ;;
        --image)      IMAGE="$2";         shift 2 ;;
        --) shift; PROMPT="$*"; break ;;
        *)  echo "gemini_veo.sh: unexpected arg: $1" >&2; exit 1 ;;
    esac
done

API_KEY="$(get_yaml_nested3 providers gemini api_key "$CONFIG_FILE")"
if [ -z "$API_KEY" ]; then
    echo "gemini_veo.sh: providers.gemini.api_key not found in $CONFIG_FILE" >&2
    echo "Set providers.gemini.api_key in $CONFIG_FILE before invoking this skill." >&2
    exit 1
fi

ESCAPED_PROMPT="$(json_escape "$PROMPT")"

REQUEST_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$REQUEST_FILE" "$RESPONSE_FILE"' EXIT

# Detect MIME type for the image (if any). Try `file` first, then fall
# back to the file extension — embedded targets sometimes lack `file`.
detect_mime() {
    local path="$1" mime=""
    if command -v file >/dev/null 2>&1; then
        mime="$(file --mime-type -b "$path" 2>/dev/null || true)"
    fi
    case "$mime" in
        image/*) printf '%s' "$mime"; return 0 ;;
    esac
    case "$path" in
        *.png|*.PNG)                 printf 'image/png' ;;
        *.jpg|*.JPG|*.jpeg|*.JPEG)   printf 'image/jpeg' ;;
        *.webp|*.WEBP)               printf 'image/webp' ;;
        *) return 1 ;;
    esac
}

# Build the optional "parameters" block. The reference scripts only send
# this when the user actually overrides a parameter, so omit it when
# both --aspect and --resolution are unset to keep the request minimal.
build_parameters_block() {
    local has_aspect=0 has_res=0 first=1
    [ -n "$ASPECT" ]     && has_aspect=1
    [ -n "$RESOLUTION" ] && has_res=1
    if [ $has_aspect -eq 0 ] && [ $has_res -eq 0 ]; then
        return
    fi
    printf ',\n  "parameters": {'
    if [ $has_aspect -eq 1 ]; then
        printf '\n    "aspectRatio": "%s"' "$ASPECT"
        first=0
    fi
    if [ $has_res -eq 1 ]; then
        [ $first -eq 0 ] && printf ','
        printf '\n    "resolution": "%s"' "$RESOLUTION"
    fi
    printf '\n  }'
}

if [ -n "$IMAGE" ]; then
    if ! IMAGE_MIME="$(detect_mime "$IMAGE")"; then
        echo "gemini_veo.sh: could not determine image MIME type for $IMAGE (expected .png/.jpg/.jpeg/.webp)" >&2
        exit 1
    fi

    # Stream the base64 directly into the request file so very large
    # images don't have to live in a shell variable. `base64` wraps
    # output by default on some platforms — strip whitespace so the
    # JSON string stays on one line.
    #
    # Wire format: referenceImages[] with image.{bytesBase64Encoded,mimeType}
    # and referenceType: "asset". The public docs show inlineData here, but
    # the predictLongRunning endpoint rejects it with "'inlineData' isn't
    # supported by this model" — Veo uses the Vertex-AI image shape.
    {
        printf '{\n  "instances": [{\n    "prompt": "%s",\n    "referenceImages": [\n      {\n        "image": {"bytesBase64Encoded": "' \
            "$ESCAPED_PROMPT"
        base64 < "$IMAGE" | tr -d '\n\r '
        printf '", "mimeType": "%s"},\n        "referenceType": "asset"\n      }\n    ]\n  }]' "$IMAGE_MIME"
        build_parameters_block
        printf '\n}\n'
    } > "$REQUEST_FILE"
else
    {
        printf '{\n  "instances": [{"prompt": "%s"}]' "$ESCAPED_PROMPT"
        build_parameters_block
        printf '\n}\n'
    } > "$REQUEST_FILE"
fi

if [ -n "$IMAGE" ]; then
    echo "Starting video generation (model=$MODEL, image=$IMAGE)…" >&2
else
    echo "Starting video generation (model=$MODEL)…" >&2
fi

HTTP_CODE="$(curl -sS -w '%{http_code}' -o "$RESPONSE_FILE" \
    -X POST "$ENDPOINT" \
    -H "x-goog-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary @"$REQUEST_FILE")" || {
    echo "gemini_veo.sh: curl failed talking to $ENDPOINT" >&2
    exit 1
}

if [ "$HTTP_CODE" != "200" ]; then
    echo "gemini_veo.sh: Gemini API returned HTTP $HTTP_CODE" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    exit 1
fi

# Pull the operation name out of the response. A greedy sed match
# (`.*"name"`) would latch onto the LAST "name" key, which is wrong
# when the body has nested objects (metadata, errors) that also use
# that key — that bug surfaced in practice and broke polling with a
# malformed URL. `grep -o` emits one match per occurrence; `head -1`
# picks the first, i.e. the top-level operation name.
OP_NAME="$(tr -d '\n\r' < "$RESPONSE_FILE" \
    | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 \
    | sed 's/.*"\([^"]*\)"$/\1/')"

if [ -z "$OP_NAME" ]; then
    echo "gemini_veo.sh: could not extract operation name from response" >&2
    cat "$RESPONSE_FILE" >&2
    exit 1
fi

echo "Operation started: $OP_NAME" >&2

MAX_POLLS=60
POLL_INTERVAL=10
DONE=""

i=0
while [ $i -lt $MAX_POLLS ]; do
    sleep $POLL_INTERVAL
    i=$((i + 1))
    echo "Polling ($i/$MAX_POLLS)…" >&2

    HTTP_CODE="$(curl -sS -w '%{http_code}' -o "$RESPONSE_FILE" \
        "${OPERATIONS_BASE}/${OP_NAME}" \
        -H "x-goog-api-key: $API_KEY")" || {
        echo "gemini_veo.sh: curl failed during poll" >&2
        exit 1
    }

    if [ "$HTTP_CODE" != "200" ]; then
        echo "gemini_veo.sh: poll returned HTTP $HTTP_CODE" >&2
        cat "$RESPONSE_FILE" >&2
        exit 1
    fi

    DONE="$(tr -d '\n\r' < "$RESPONSE_FILE" \
        | sed -n 's/.*"done"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' \
        | head -1)"

    [ "$DONE" = "true" ] && break
done

if [ "$DONE" != "true" ]; then
    echo "gemini_veo.sh: timed out waiting for video generation (${MAX_POLLS} × ${POLL_INTERVAL}s)" >&2
    exit 1
fi

# Extract video — try inline base64 first, then URI
B64="$(tr -d '\n\r' < "$RESPONSE_FILE" \
    | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"

if [ -n "$B64" ]; then
    printf '%s' "$B64" | base64 -d > "$OUTPUT" || {
        echo "gemini_veo.sh: base64 decode failed" >&2
        exit 1
    }
else
    VIDEO_URI="$(tr -d '\n\r' < "$RESPONSE_FILE" \
        | sed -n 's/.*"uri"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -1)"

    if [ -z "$VIDEO_URI" ]; then
        # When `done: true` but neither data nor uri is present, the
        # operation typically finished with the RAI safety filter
        # blocking the output (e.g. celebrity-likeness or violence).
        # Surface the filter reason verbatim so the user knows to
        # adjust the prompt or reference image rather than just seeing
        # a generic "could not extract" error.
        RAI_REASON="$(tr -d '\n\r' < "$RESPONSE_FILE" \
            | sed -n 's/.*"raiMediaFilteredReasons"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p' \
            | head -1)"
        if [ -n "$RAI_REASON" ]; then
            echo "gemini_veo.sh: video generation blocked by safety filter: $RAI_REASON" >&2
            exit 1
        fi

        echo "gemini_veo.sh: could not extract video data or URI from response" >&2
        cat "$RESPONSE_FILE" >&2
        exit 1
    fi

    echo "Downloading video from URI…" >&2
    HTTP_CODE="$(curl -sSL -w '%{http_code}' -o "$OUTPUT" \
        "$VIDEO_URI" \
        -H "x-goog-api-key: $API_KEY")" || {
        echo "gemini_veo.sh: curl failed downloading video" >&2
        exit 1
    }

    if [ "$HTTP_CODE" != "200" ]; then
        echo "gemini_veo.sh: video download returned HTTP $HTTP_CODE" >&2
        exit 1
    fi
fi

echo "Video saved to: $OUTPUT (model=$MODEL)"
