#!/usr/bin/env bash
# openai_tts.sh — OpenAI text-to-speech.
# Called by generate.sh; not meant to be invoked directly.
#
# Endpoint and model are STATIC. The skill targets OpenAI's
# /v1/audio/speech REST endpoint with model `gpt-4o-mini-tts`, the newest
# TTS model. Speed control is not exposed because gpt-4o-mini-tts does
# not accept the `speed` field (that knob exists only on tts-1 /
# tts-1-hd); the parent script warns "unsupported option" if a user
# passes --speed.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

# --- Static endpoint and model (do not parameterize) ---
OPENAI_TTS_MODEL="gpt-4o-mini-tts"
OPENAI_TTS_ENDPOINT="https://api.openai.com/v1/audio/speech"

CONFIG_FILE=""
VOICE=""
FORMAT="wav"
OUTPUT=""
TEXT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --voice)  VOICE="$2";       shift 2 ;;
        --format) FORMAT="$2";      shift 2 ;;
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

[ -z "$VOICE" ] && VOICE="alloy"

ESCAPED_TEXT="$(json_escape "$TEXT")"

REQUEST_FILE="$(mktemp)"
ERROR_FILE="$(mktemp)"
trap 'rm -f "$REQUEST_FILE" "$ERROR_FILE"' EXIT

cat > "$REQUEST_FILE" <<EOF
{"model":"$OPENAI_TTS_MODEL","input":"$ESCAPED_TEXT","voice":"$VOICE","response_format":"$FORMAT"}
EOF

# OpenAI returns binary audio on success and a JSON error on failure.
# Stream the body to OUTPUT directly; if HTTP isn't 200, the file we wrote
# is actually the JSON error — move it aside for diagnostics.
HTTP_CODE="$(curl -sS -w '%{http_code}' -o "$OUTPUT" \
    "$OPENAI_TTS_ENDPOINT" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary @"$REQUEST_FILE")" || {
    echo "openai_tts.sh: curl failed talking to $OPENAI_TTS_ENDPOINT" >&2
    exit 1
}

if [ "$HTTP_CODE" != "200" ]; then
    mv "$OUTPUT" "$ERROR_FILE" 2>/dev/null || true
    echo "openai_tts.sh: OpenAI API returned HTTP $HTTP_CODE" >&2
    [ -s "$ERROR_FILE" ] && cat "$ERROR_FILE" >&2
    echo >&2
    exit 1
fi

echo "Audio saved to: $OUTPUT (voice=$VOICE, model=$OPENAI_TTS_MODEL, format=$FORMAT)"
