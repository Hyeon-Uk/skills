#!/usr/bin/env bash
# gemini_tts.sh — Google Gemini text-to-speech.
# Called by generate.sh; not meant to be invoked directly.
#
# Endpoint and model are STATIC. Per the official REST docs at
# https://ai.google.dev/gemini-api/docs/speech-generation this skill is
# pinned to gemini-3.1-flash-tts-preview, the recommended primary model.
#
# Gemini TTS returns 24 kHz / 16-bit / mono PCM as base64 inside JSON.
# We decode the base64 and prepend a 44-byte WAV/RIFF header so the file
# plays in any standard audio player without depending on ffmpeg or sox
# (which the embedded target may not have).

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

# --- Static endpoint and model (do not parameterize) ---
GEMINI_TTS_MODEL="gemini-3.1-flash-tts-preview"
GEMINI_TTS_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-tts-preview:generateContent"

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
        *)  echo "gemini_tts.sh: unexpected arg: $1" >&2; exit 1 ;;
    esac
done

API_KEY="$(get_yaml_nested3 providers gemini api_key "$CONFIG_FILE")"
if [ -z "$API_KEY" ]; then
    echo "gemini_tts.sh: providers.gemini.api_key not found in $CONFIG_FILE" >&2
    echo "Set providers.gemini.api_key in $CONFIG_FILE before invoking this skill." >&2
    exit 1
fi

[ -z "$VOICE" ] && VOICE="Kore"

# Gemini emits PCM only; transcoding to mp3/etc would require ffmpeg, which
# we don't assume on embedded targets. Surface the limit early.
if [ "$FORMAT" != "wav" ] && [ "$FORMAT" != "pcm" ]; then
    echo "gemini_tts.sh: format '$FORMAT' not supported for Gemini TTS." >&2
    echo "Gemini emits raw PCM; this script wraps it as WAV. Use --format wav (default) or --format pcm." >&2
    echo "If you need mp3/opus/aac, install ffmpeg and transcode after generation, or switch provider to openai." >&2
    exit 1
fi

ESCAPED_TEXT="$(json_escape "$TEXT")"

REQUEST_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"
PCM_FILE="$(mktemp)"
trap 'rm -f "$REQUEST_FILE" "$RESPONSE_FILE" "$PCM_FILE"' EXIT

cat > "$REQUEST_FILE" <<EOF
{"contents":[{"parts":[{"text":"$ESCAPED_TEXT"}]}],"generationConfig":{"responseModalities":["AUDIO"],"speechConfig":{"voiceConfig":{"prebuiltVoiceConfig":{"voiceName":"$VOICE"}}}}}
EOF

HTTP_CODE="$(curl -sS -w '%{http_code}' -o "$RESPONSE_FILE" \
    "$GEMINI_TTS_ENDPOINT" \
    -H "x-goog-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary @"$REQUEST_FILE")" || {
    echo "gemini_tts.sh: curl failed talking to $GEMINI_TTS_ENDPOINT" >&2
    exit 1
}

if [ "$HTTP_CODE" != "200" ]; then
    echo "gemini_tts.sh: Gemini API returned HTTP $HTTP_CODE" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    exit 1
fi

# Pull the inlineData.data base64 string. Audio base64 is on a single line in the
# response (no internal double-quotes), so a non-greedy regex is safe.
B64="$(tr -d '\n\r' < "$RESPONSE_FILE" \
    | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"

if [ -z "$B64" ]; then
    echo "gemini_tts.sh: could not extract audio data from response" >&2
    cat "$RESPONSE_FILE" >&2
    exit 1
fi

printf '%s' "$B64" | base64 -d > "$PCM_FILE" || {
    echo "gemini_tts.sh: base64 decode failed" >&2
    exit 1
}

# If user asked for raw PCM, write straight through and stop.
if [ "$FORMAT" = "pcm" ]; then
    cp "$PCM_FILE" "$OUTPUT"
    echo "Audio saved to: $OUTPUT (voice=$VOICE, model=$GEMINI_TTS_MODEL, format=pcm, 24kHz/16-bit/mono)"
    exit 0
fi

# Wrap PCM in a 44-byte canonical WAV header.
# Gemini TTS spec: sampleRate=24000, channels=1, bitsPerSample=16.
SAMPLE_RATE=24000
CHANNELS=1
BITS=16
PCM_SIZE="$(wc -c < "$PCM_FILE")"
PCM_SIZE=$((PCM_SIZE))   # strip any whitespace
BYTE_RATE=$((SAMPLE_RATE * CHANNELS * BITS / 8))
BLOCK_ALIGN=$((CHANNELS * BITS / 8))
RIFF_SIZE=$((PCM_SIZE + 36))

# Emit a little-endian integer of N bytes via printf octal escapes.
# Octal works on every POSIX printf; \xNN does not.
emit_le() {
    local val=$1 nbytes=$2 i=0
    while [ $i -lt $nbytes ]; do
        printf "\\$(printf '%03o' $((val & 0xff)))"
        val=$((val >> 8))
        i=$((i+1))
    done
}

{
    printf 'RIFF'
    emit_le "$RIFF_SIZE" 4
    printf 'WAVE'
    printf 'fmt '
    emit_le 16 4              # fmt chunk size
    emit_le 1 2               # audio format = PCM
    emit_le "$CHANNELS" 2
    emit_le "$SAMPLE_RATE" 4
    emit_le "$BYTE_RATE" 4
    emit_le "$BLOCK_ALIGN" 2
    emit_le "$BITS" 2
    printf 'data'
    emit_le "$PCM_SIZE" 4
    cat "$PCM_FILE"
} > "$OUTPUT"

echo "Audio saved to: $OUTPUT (voice=$VOICE, model=$GEMINI_TTS_MODEL, format=wav, 24kHz/16-bit/mono)"
