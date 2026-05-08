#!/usr/bin/env bash
# gemini_generate.sh — Google Gemini image generation.
# Called by generate.sh; not meant to be invoked directly.
#
# Endpoint and model are STATIC. The official REST docs at
# https://ai.google.dev/gemini-api/docs/image-generation pin this skill to
# gemini-3.1-flash-image-preview, the recommended default. The full URL is
# hardcoded so callers cannot redirect this script at a different model.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

# --- Static endpoint and model (do not parameterize) ---
GEMINI_IMAGE_MODEL="gemini-3.1-flash-image-preview"
GEMINI_IMAGE_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image-preview:generateContent"

CONFIG_FILE=""
SIZE="1024x1024"
OUTPUT=""
PROMPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config)  CONFIG_FILE="$2"; shift 2 ;;
        --size)    SIZE="$2";        shift 2 ;;
        --output)  OUTPUT="$2";      shift 2 ;;
        --) shift; PROMPT="$*"; break ;;
        *)  echo "gemini_generate.sh: unexpected arg: $1" >&2; exit 1 ;;
    esac
done

API_KEY="$(get_yaml_nested3 providers gemini api_key "$CONFIG_FILE")"
if [ -z "$API_KEY" ]; then
    echo "gemini_generate.sh: providers.gemini.api_key not found in $CONFIG_FILE" >&2
    echo "Set providers.gemini.api_key in $CONFIG_FILE before invoking this skill." >&2
    exit 1
fi

# Map WxH to a Gemini imageConfig.aspectRatio. Pixel dims are otherwise ignored.
ASPECT="1:1"
case "$SIZE" in
    *x*)
        W="${SIZE%x*}"; H="${SIZE#*x}"
        if [ "$W" -gt 0 ] && [ "$H" -gt 0 ] 2>/dev/null; then
            if   [ "$W" -eq "$H" ]; then ASPECT="1:1"
            elif [ $((W * 9)) -gt $((H * 16)) ]; then ASPECT="16:9"
            elif [ $((W * 4)) -gt $((H * 3)) ]; then ASPECT="4:3"
            elif [ $((H * 9)) -gt $((W * 16)) ]; then ASPECT="9:16"
            else ASPECT="3:4"
            fi
        fi
        ;;
esac

ESCAPED_PROMPT="$(json_escape "$PROMPT")"

REQUEST_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$REQUEST_FILE" "$RESPONSE_FILE"' EXIT

# Per the official docs, send ["TEXT","IMAGE"] — some image models reject ["IMAGE"] alone.
cat > "$REQUEST_FILE" <<EOF
{"contents":[{"parts":[{"text":"$ESCAPED_PROMPT"}]}],"generationConfig":{"responseModalities":["TEXT","IMAGE"],"imageConfig":{"aspectRatio":"$ASPECT"}}}
EOF

HTTP_CODE="$(curl -sS -w '%{http_code}' -o "$RESPONSE_FILE" \
    "$GEMINI_IMAGE_ENDPOINT" \
    -H "x-goog-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary @"$REQUEST_FILE")" || {
    echo "gemini_generate.sh: curl failed talking to $GEMINI_IMAGE_ENDPOINT" >&2
    exit 1
}

if [ "$HTTP_CODE" != "200" ]; then
    echo "gemini_generate.sh: Gemini API returned HTTP $HTTP_CODE" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    exit 1
fi

B64="$(tr -d '\n\r' < "$RESPONSE_FILE" \
    | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"

if [ -z "$B64" ]; then
    echo "gemini_generate.sh: could not extract image data from response" >&2
    cat "$RESPONSE_FILE" >&2
    exit 1
fi

printf '%s' "$B64" | base64 -d > "$OUTPUT" || {
    echo "gemini_generate.sh: base64 decode failed" >&2
    exit 1
}

echo "Image saved to: $OUTPUT (model=$GEMINI_IMAGE_MODEL)"
