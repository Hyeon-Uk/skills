#!/usr/bin/env bash
# gemini_music.sh — Google Lyria 3 music generation.
# Called by generate.sh; not meant to be invoked directly.
#
# Lyria 3 returns a complete MP3 (Clip + Pro) or WAV (Pro) container as
# base64 inside JSON. Unlike Gemini TTS, no header wrapping is needed —
# we just base64-decode straight to the output file.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

CONFIG_FILE=""
MODEL=""
FORMAT="mp3"
OUTPUT=""
PROMPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --model)  MODEL="$2";       shift 2 ;;
        --format) FORMAT="$2";      shift 2 ;;
        --output) OUTPUT="$2";      shift 2 ;;
        --) shift; PROMPT="$*"; break ;;
        *)  echo "gemini_music.sh: unexpected arg: $1" >&2; exit 1 ;;
    esac
done

API_KEY="$(get_yaml_nested3 providers gemini api_key "$CONFIG_FILE")"
if [ -z "$API_KEY" ]; then
    echo "gemini_music.sh: providers.gemini.api_key not found in $CONFIG_FILE" >&2
    echo "Set providers.gemini.api_key in $CONFIG_FILE before invoking this skill." >&2
    exit 1
fi

# Google Lyria 3 always uses the official endpoint.
# https://ai.google.dev/gemini-api/docs/music-generation
BASE_URL="https://generativelanguage.googleapis.com"

# Lyria via the Gemini :generateContent endpoint currently emits MP3 only.
# The documented responseMimeType="audio/wav" override is rejected by the live
# API; until that mismatch is fixed upstream, only --format mp3 is supported.
# Vertex AI's lyria-002 returns WAV but uses a different endpoint and request
# shape (instances/parameters via :predict) — out of scope for this skill.
if [ "$FORMAT" != "mp3" ]; then
    echo "gemini_music.sh: only --format mp3 is supported for Lyria via the Gemini API." >&2
    echo "The documented WAV path (responseMimeType=audio/wav) is rejected by the live :generateContent endpoint." >&2
    echo "For WAV, use Vertex AI's lyria-002 directly (different endpoint, not handled by this skill)." >&2
    exit 1
fi

# Pick the right MIME type for responseMimeType.
case "$FORMAT" in
    mp3) MIME="audio/mp3" ;;
    wav) MIME="audio/wav" ;;
    *)   echo "gemini_music.sh: unsupported format '$FORMAT'" >&2; exit 1 ;;
esac

ESCAPED_PROMPT="$(json_escape "$PROMPT")"

REQUEST_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$REQUEST_FILE" "$RESPONSE_FILE"' EXIT

# NOTE: per ai.google.dev/gemini-api/docs/music-generation the request should
# accept generationConfig.responseMimeType="audio/wav" to switch from MP3 to WAV,
# but the live :generateContent endpoint rejects that field with HTTP 400
# ("response_mime_type: allowed mimetypes are text/plain, application/json, ...").
# Until Google fixes that mismatch, Lyria via Gemini API emits MP3 only.
# WAV via :predict requires Vertex AI's lyria-002 (different endpoint+shape).
cat > "$REQUEST_FILE" <<EOF
{"contents":[{"parts":[{"text":"$ESCAPED_PROMPT"}]}],"generationConfig":{"responseModalities":["AUDIO"]}}
EOF

ENDPOINT="$BASE_URL/v1beta/models/${MODEL}:generateContent"

# HTTP_CODE="$(curl -sS -w '%{http_code}' -o "$RESPONSE_FILE" \
#     "$ENDPOINT" \
#     -H "x-goog-api-key: $API_KEY" \
#     -H "Content-Type: application/json" \
#     --data-binary @"$REQUEST_FILE")" || {
#     echo "gemini_music.sh: curl failed talking to $BASE_URL" >&2
#     exit 1
# }

HTTP_CODE=$(curl -sS \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    -X POST "$ENDPOINT" \
    -H "x-goog-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    --data @"$REQUEST_FILE"
) || {
    echo "gemini_music.sh: curl failed talking to $BASE_URL" >&2
    exit 1    
}

if [ "$HTTP_CODE" != "200" ]; then
    echo "gemini_music.sh: Gemini API returned HTTP $HTTP_CODE" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    exit 1
fi

# Lyria responses contain two parts: a {"text": "..."} with lyrics/structure,
# and an {"inlineData": {"data": "..."}} with the audio. The audio base64
# string contains no double-quotes, so a non-greedy match for "data":"..."
# safely picks it (the lyrics field is "text":"..." and won't collide).
B64="$(tr -d '\n\r' < "$RESPONSE_FILE" \
    | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"

if [ -z "$B64" ]; then
    # Lyria sometimes returns 200 OK with no audio because a safety filter
    # tripped (copyright similarity, profanity, etc.). Detect finishReason
    # and surface its finishMessage cleanly instead of dumping the raw JSON.
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

echo "Music saved to: $OUTPUT (model=$MODEL, format=$FORMAT, mime=$RETURNED_MIME, 44.1kHz stereo, SynthID watermarked)"
