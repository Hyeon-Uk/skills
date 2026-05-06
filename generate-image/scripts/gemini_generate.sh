#!/usr/bin/env bash
# gemini_generate.sh — Google Gemini / Imagen image generation.
# Called by generate.sh; not meant to be invoked directly.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

CONFIG_FILE=""
MODEL=""
QUALITY=""
SIZE="1024x1024"
OUTPUT=""
PROMPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config)  CONFIG_FILE="$2"; shift 2 ;;
        --model)   MODEL="$2";       shift 2 ;;
        --quality) QUALITY="$2";     shift 2 ;;
        --size)    SIZE="$2";        shift 2 ;;
        --output)  OUTPUT="$2";      shift 2 ;;
        --) shift; PROMPT="$*"; break ;;
        *)  echo "gemini_generate.sh: unexpected arg: $1" >&2; exit 1 ;;
    esac
done

API_KEY="$(get_yaml_nested3 providers gemini api_key "$CONFIG_FILE")"
if [ -z "$API_KEY" ]; then
    echo "gemini_generate.sh: providers.gemini.api_key not found in $CONFIG_FILE" >&2
    exit 1
fi

BASE_URL="$(get_yaml_nested3 providers gemini base_url "$CONFIG_FILE" || true)"
[ -z "$BASE_URL" ] && BASE_URL="https://generativelanguage.googleapis.com"
BASE_URL="${BASE_URL%/}"

# Map WxH to Imagen aspect ratio. Only the ratio matters; pixel dims are ignored.
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

# Imagen 4 supports imageSize ("1K"|"2K"); Imagen 3 does not.
# HD default for Imagen 4 = "2K"; user-supplied --quality maps high->2K, others->1K.
IMAGE_SIZE_FIELD=""
case "$MODEL" in
    imagen-4*|imagen-4.0-*)
        case "${QUALITY:-}" in
            ""|high|hd) IMAGE_SIZE_FIELD=',"imageSize":"2K"' ;;
            *)          IMAGE_SIZE_FIELD=',"imageSize":"1K"' ;;
        esac
        ;;
esac

case "$MODEL" in
    imagen-*)
        cat > "$REQUEST_FILE" <<EOF
{"instances":[{"prompt":"$ESCAPED_PROMPT"}],"parameters":{"sampleCount":1,"aspectRatio":"$ASPECT"$IMAGE_SIZE_FIELD}}
EOF
        ENDPOINT="$BASE_URL/v1beta/models/${MODEL}:predict"
        RESPONSE_KEY="bytesBase64Encoded"
        ;;
    *)
        # Gemini image-generation models (e.g. gemini-2.0-flash-preview-image-generation,
        # gemini-2.5-flash-image-preview). They use generateContent with responseModalities.
        cat > "$REQUEST_FILE" <<EOF
{"contents":[{"parts":[{"text":"$ESCAPED_PROMPT"}]}],"generationConfig":{"responseModalities":["IMAGE"]}}
EOF
        ENDPOINT="$BASE_URL/v1beta/models/${MODEL}:generateContent"
        RESPONSE_KEY="data"
        ;;
esac

HTTP_CODE="$(curl -sS -w '%{http_code}' -o "$RESPONSE_FILE" \
    "$ENDPOINT" \
    -H "x-goog-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary @"$REQUEST_FILE")" || {
    echo "gemini_generate.sh: curl failed talking to $BASE_URL" >&2
    exit 1
}

if [ "$HTTP_CODE" != "200" ]; then
    echo "gemini_generate.sh: Gemini API returned HTTP $HTTP_CODE" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    exit 1
fi

B64="$(tr -d '\n\r' < "$RESPONSE_FILE" \
    | sed -n "s/.*\"${RESPONSE_KEY}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
    | head -1)"

# Fallback: try the other key in case the model family was misclassified.
if [ -z "$B64" ]; then
    for alt in bytesBase64Encoded data; do
        [ "$alt" = "$RESPONSE_KEY" ] && continue
        B64="$(tr -d '\n\r' < "$RESPONSE_FILE" \
            | sed -n "s/.*\"${alt}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
            | head -1)"
        [ -n "$B64" ] && break
    done
fi

if [ -z "$B64" ]; then
    echo "gemini_generate.sh: could not extract image data from response" >&2
    cat "$RESPONSE_FILE" >&2
    exit 1
fi

printf '%s' "$B64" | base64 -d > "$OUTPUT" || {
    echo "gemini_generate.sh: base64 decode failed" >&2
    exit 1
}

echo "Image saved to: $OUTPUT"
