#!/usr/bin/env bash
# gemini_veo.sh — Google Veo video generation via Gemini predictLongRunning API.
# Called by generate.sh; not meant to be invoked directly.
#
# Pinned models (do not parameterize the endpoints):
#   --model veo-3  → veo-3.0-generate-preview  (video + audio)
#   --model veo-2  → veo-2.0-generate-001       (video only)
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

VEO3_MODEL="veo-3.0-generate-preview"
VEO3_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/veo-3.0-generate-preview:predictLongRunning"
VEO2_MODEL="veo-2.0-generate-001"
VEO2_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/veo-2.0-generate-001:predictLongRunning"
OPERATIONS_BASE="https://generativelanguage.googleapis.com/v1beta"

CONFIG_FILE=""
MODEL_CHOICE="veo-3"
ASPECT="16:9"
DURATION="8"
OUTPUT=""
PROMPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config)   CONFIG_FILE="$2";   shift 2 ;;
        --model)    MODEL_CHOICE="$2";  shift 2 ;;
        --aspect)   ASPECT="$2";        shift 2 ;;
        --duration) DURATION="$2";      shift 2 ;;
        --output)   OUTPUT="$2";        shift 2 ;;
        --) shift; PROMPT="$*"; break ;;
        *)  echo "gemini_veo.sh: unexpected arg: $1" >&2; exit 1 ;;
    esac
done

case "$MODEL_CHOICE" in
    veo-3|veo3|3) MODEL="$VEO3_MODEL"; ENDPOINT="$VEO3_ENDPOINT" ;;
    veo-2|veo2|2) MODEL="$VEO2_MODEL"; ENDPOINT="$VEO2_ENDPOINT" ;;
    *)
        echo "gemini_veo.sh: --model must be 'veo-3' or 'veo-2'; got '$MODEL_CHOICE'" >&2
        exit 1
        ;;
esac

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

cat > "$REQUEST_FILE" <<EOF
{
  "instances": [{"prompt": "$ESCAPED_PROMPT"}],
  "parameters": {
    "aspectRatio": "$ASPECT",
    "sampleCount": 1,
    "durationSeconds": $DURATION
  }
}
EOF

echo "Starting video generation (model=$MODEL)…" >&2

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

OP_NAME="$(tr -d '\n\r' < "$RESPONSE_FILE" \
    | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"

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
        echo "gemini_veo.sh: could not extract video data or URI from response" >&2
        cat "$RESPONSE_FILE" >&2
        exit 1
    fi

    echo "Downloading video from URI…" >&2
    HTTP_CODE="$(curl -sS -w '%{http_code}' -o "$OUTPUT" \
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
