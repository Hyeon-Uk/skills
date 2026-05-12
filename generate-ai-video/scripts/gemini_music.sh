#!/usr/bin/env bash
# gemini_music.sh — Lyria 3 music generation for generate-ai-video.
# Adapted from generate-ai-sound/scripts/gemini_music.sh.
#
# Endpoint and model are STATIC, selected by --length:
#   --length full  → lyria-3-pro-preview   (multi-minute; default)
#   --length clip  → lyria-3-clip-preview  (~30 seconds)
#
# Called by generate.sh; not meant to be invoked directly.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

LYRIA_PRO_MODEL="lyria-3-pro-preview"
LYRIA_PRO_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/lyria-3-pro-preview:generateContent"
LYRIA_CLIP_MODEL="lyria-3-clip-preview"
LYRIA_CLIP_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/lyria-3-clip-preview:generateContent"

CONFIG_FILE=""
LENGTH="clip"
OUTPUT=""
PROMPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --length) LENGTH="$2";      shift 2 ;;
        --output) OUTPUT="$2";      shift 2 ;;
        --) shift; PROMPT="$*"; break ;;
        *)  echo "gemini_music.sh: unexpected arg: $1" >&2; exit 1 ;;
    esac
done

case "$LENGTH" in
    full|pro|long|song)
        MODEL="$LYRIA_PRO_MODEL"
        ENDPOINT="$LYRIA_PRO_ENDPOINT"
        ;;
    clip|short|preview)
        MODEL="$LYRIA_CLIP_MODEL"
        ENDPOINT="$LYRIA_CLIP_ENDPOINT"
        ;;
    *)
        echo "gemini_music.sh: --length must be 'full' (multi-minute) or 'clip' (~30s); got '$LENGTH'" >&2
        exit 1
        ;;
esac

API_KEY="$(get_yaml_nested3 providers gemini api_key "$CONFIG_FILE")"
if [ -z "$API_KEY" ]; then
    echo "gemini_music.sh: providers.gemini.api_key not found in $CONFIG_FILE" >&2
    echo "Set providers.gemini.api_key in $CONFIG_FILE before invoking this skill." >&2
    exit 1
fi

ESCAPED_PROMPT="$(json_escape "$PROMPT")"

REQUEST_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$REQUEST_FILE" "$RESPONSE_FILE"' EXIT

cat > "$REQUEST_FILE" <<EOF
{"contents":[{"parts":[{"text":"$ESCAPED_PROMPT"}]}],"generationConfig":{"responseModalities":["AUDIO"]}}
EOF

HTTP_CODE=$(curl -sS \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    -X POST "$ENDPOINT" \
    -H "x-goog-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    --data @"$REQUEST_FILE"
) || {
    echo "gemini_music.sh: curl failed talking to $ENDPOINT" >&2
    exit 1
}

if [ "$HTTP_CODE" != "200" ]; then
    echo "gemini_music.sh: Gemini API returned HTTP $HTTP_CODE" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    exit 1
fi

B64="$(tr -d '\n\r' < "$RESPONSE_FILE" \
    | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"

if [ -z "$B64" ]; then
    FINISH_REASON="$(tr -d '\n\r' < "$RESPONSE_FILE" \
        | sed -n 's/.*"finishReason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -1)"
    if [ -n "$FINISH_REASON" ] && [ "$FINISH_REASON" != "STOP" ]; then
        FINISH_MSG="$(tr -d '\n\r' < "$RESPONSE_FILE" \
            | sed -n 's/.*"finishMessage"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            | head -1)"
        echo "gemini_music.sh: Lyria refused to generate audio (finishReason=$FINISH_REASON)." >&2
        [ -n "$FINISH_MSG" ] && echo "  $FINISH_MSG" >&2
        echo "Rephrase the prompt — describe mood/instruments/tempo without referencing real songs or artists." >&2
        exit 1
    fi
    echo "gemini_music.sh: could not extract audio data from response" >&2
    cat "$RESPONSE_FILE" >&2
    exit 1
fi

printf '%s' "$B64" | base64 -d > "$OUTPUT" || {
    echo "gemini_music.sh: base64 decode failed" >&2
    exit 1
}

RETURNED_MIME="$(tr -d '\n\r' < "$RESPONSE_FILE" \
    | sed -n 's/.*"mimeType"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"
[ -z "$RETURNED_MIME" ] && RETURNED_MIME="audio/mp3"

echo "Music saved to: $OUTPUT (length=$LENGTH, model=$MODEL, mime=$RETURNED_MIME)"
