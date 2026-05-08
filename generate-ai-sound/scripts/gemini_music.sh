#!/usr/bin/env bash
# gemini_music.sh — Google Lyria 3 music generation.
# Called by generate.sh; not meant to be invoked directly.
#
# Endpoint and model are STATIC. Per the official REST docs at
# https://ai.google.dev/gemini-api/docs/music-generation this skill targets
# one of two pinned URLs, selected by --length:
#   --length full  → lyria-3-pro-preview   (multi-minute songs; default)
#   --length clip  → lyria-3-clip-preview  (~30-second clips)
#
# Lyria returns a complete MP3 (Clip + Pro) or WAV (Pro) container as
# base64 inside JSON. We base64-decode straight to the output file.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

# --- Static endpoints and models (do not parameterize by URL) ---
LYRIA_PRO_MODEL="lyria-3-pro-preview"
LYRIA_PRO_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/lyria-3-pro-preview:generateContent"
LYRIA_CLIP_MODEL="lyria-3-clip-preview"
LYRIA_CLIP_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/lyria-3-clip-preview:generateContent"

CONFIG_FILE=""
LENGTH="full"
FORMAT="mp3"
OUTPUT=""
PROMPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --length) LENGTH="$2";      shift 2 ;;
        --format) FORMAT="$2";      shift 2 ;;
        --output) OUTPUT="$2";      shift 2 ;;
        --model)  shift 2 ;;   # accepted for parent compat; ignored — model is fixed via --length
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
        echo "gemini_music.sh: --length must be 'full' (multi-minute song) or 'clip' (~30s); got '$LENGTH'" >&2
        exit 1
        ;;
esac

API_KEY="$(get_yaml_nested3 providers gemini api_key "$CONFIG_FILE")"
if [ -z "$API_KEY" ]; then
    echo "gemini_music.sh: providers.gemini.api_key not found in $CONFIG_FILE" >&2
    echo "Set providers.gemini.api_key in $CONFIG_FILE before invoking this skill." >&2
    exit 1
fi

# Lyria via the Gemini :generateContent endpoint currently emits MP3 only.
# The documented responseMimeType="audio/wav" override is rejected by the live
# API; until that mismatch is fixed upstream, only --format mp3 is supported.
if [ "$FORMAT" != "mp3" ]; then
    echo "gemini_music.sh: only --format mp3 is supported for Lyria via the Gemini API." >&2
    echo "The documented WAV path (responseMimeType=audio/wav) is rejected by the live :generateContent endpoint." >&2
    exit 1
fi
MIME="audio/mp3"

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

# Lyria responses contain two parts: a {"text": "..."} with lyrics/structure,
# and an {"inlineData": {"data": "..."}} with the audio.
B64="$(tr -d '\n\r' < "$RESPONSE_FILE" \
    | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"

if [ -z "$B64" ]; then
    # Lyria sometimes returns 200 OK with no audio because a safety filter
    # tripped (copyright similarity, profanity, etc.). Surface finishMessage.
    FINISH_REASON="$(tr -d '\n\r' < "$RESPONSE_FILE" \
        | sed -n 's/.*"finishReason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -1)"
    if [ -n "$FINISH_REASON" ] && [ "$FINISH_REASON" != "STOP" ]; then
        FINISH_MSG="$(tr -d '\n\r' < "$RESPONSE_FILE" \
            | sed -n 's/.*"finishMessage"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            | head -1)"
        echo "gemini_music.sh: Lyria refused to generate audio (finishReason=$FINISH_REASON)." >&2
        [ -n "$FINISH_MSG" ] && echo "  $FINISH_MSG" >&2
        echo "Try rephrasing the prompt — describe mood/instruments/tempo without referencing real songs or artists." >&2
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

# Pull the mimeType the API actually returned for an honest report line.
RETURNED_MIME="$(tr -d '\n\r' < "$RESPONSE_FILE" \
    | sed -n 's/.*"mimeType"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"
[ -z "$RETURNED_MIME" ] && RETURNED_MIME="$MIME"

echo "Music saved to: $OUTPUT (length=$LENGTH, model=$MODEL, format=$FORMAT, mime=$RETURNED_MIME, 44.1kHz stereo, SynthID watermarked)"
