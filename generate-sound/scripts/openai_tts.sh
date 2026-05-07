#!/usr/bin/env bash
# openai_tts.sh — OpenAI text-to-speech.
# Called by generate.sh; not meant to be invoked directly.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

CONFIG_FILE=""
MODEL=""
VOICE=""
FORMAT="wav"
SPEED=""
OUTPUT=""
TEXT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --model)  MODEL="$2";       shift 2 ;;
        --voice)  VOICE="$2";       shift 2 ;;
        --format) FORMAT="$2";      shift 2 ;;
        --speed)  SPEED="$2";       shift 2 ;;
        --output) OUTPUT="$2";      shift 2 ;;
        --) shift; TEXT="$*"; break ;;
        *)  echo "openai_tts.sh: unexpected arg: $1" >&2; exit 1 ;;
    esac
done

API_KEY="$(get_yaml_nested3 providers openai api_key "$CONFIG_FILE")"
if [ -z "$API_KEY" ]; then
    echo "openai_tts.sh: providers.openai.api_key not found in $CONFIG_FILE" >&2
    echo "Set providers.openai.api_key in $CONFIG_FILE before invoking this skill." >&2
    exit 1
fi

# OpenAI TTS always uses the official endpoint.
# https://platform.openai.com/docs/api-reference/audio/createSpeech
BASE_URL="https://api.openai.com"

[ -z "$VOICE" ] && VOICE="alloy"

ESCAPED_TEXT="$(json_escape "$TEXT")"

REQUEST_FILE="$(mktemp)"
ERROR_FILE="$(mktemp)"
trap 'rm -f "$REQUEST_FILE" "$ERROR_FILE"' EXIT

# Build request body. `speed` is optional; only include if caller passed it.
if [ -n "$SPEED" ]; then
    cat > "$REQUEST_FILE" <<EOF
{"model":"$MODEL","input":"$ESCAPED_TEXT","voice":"$VOICE","response_format":"$FORMAT","speed":$SPEED}
EOF
else
    cat > "$REQUEST_FILE" <<EOF
{"model":"$MODEL","input":"$ESCAPED_TEXT","voice":"$VOICE","response_format":"$FORMAT"}
EOF
fi

# OpenAI returns binary audio on success and a JSON error on failure.
# Stream the body to OUTPUT directly; if HTTP isn't 200, the file we wrote
# is actually the JSON error — move it aside for diagnostics.
HTTP_CODE="$(curl -sS -w '%{http_code}' -o "$OUTPUT" \
    "$BASE_URL/v1/audio/speech" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary @"$REQUEST_FILE")" || {
    echo "openai_tts.sh: curl failed talking to $BASE_URL" >&2
    exit 1
}

if [ "$HTTP_CODE" != "200" ]; then
    mv "$OUTPUT" "$ERROR_FILE" 2>/dev/null || true
    echo "openai_tts.sh: OpenAI API returned HTTP $HTTP_CODE" >&2
    [ -s "$ERROR_FILE" ] && cat "$ERROR_FILE" >&2
    echo >&2
    exit 1
fi

echo "Audio saved to: $OUTPUT (voice=$VOICE, model=$MODEL, format=$FORMAT)"
