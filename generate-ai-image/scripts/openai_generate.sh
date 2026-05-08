#!/usr/bin/env bash
# openai_generate.sh — OpenAI image generation.
# Called by generate.sh; not meant to be invoked directly by users.
#
# Endpoint and model are STATIC. The skill targets OpenAI's
# /v1/images/generations REST endpoint with model `gpt-image-1`, the most
# capable image model in the OpenAI API. The full URL is hardcoded so
# callers cannot redirect this script at a different model.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

# --- Static endpoint and model (do not parameterize) ---
OPENAI_IMAGE_MODEL="gpt-image-1"
OPENAI_IMAGE_ENDPOINT="https://api.openai.com/v1/images/generations"

CONFIG_FILE=""
QUALITY=""
SIZE="1024x1024"
OUTPUT=""
PROMPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config)  CONFIG_FILE="$2"; shift 2 ;;
        --quality) QUALITY="$2";     shift 2 ;;
        --size)    SIZE="$2";        shift 2 ;;
        --output)  OUTPUT="$2";      shift 2 ;;
        --model)   shift 2 ;;   # accepted for parent compat; ignored — model is fixed
        --) shift; PROMPT="$*"; break ;;
        *)  echo "openai_generate.sh: unexpected arg: $1" >&2; exit 1 ;;
    esac
done

API_KEY="$(get_yaml_nested3 providers openai api_key "$CONFIG_FILE")"
if [ -z "$API_KEY" ]; then
    echo "openai_generate.sh: providers.openai.api_key not found in $CONFIG_FILE" >&2
    echo "Set providers.openai.api_key in $CONFIG_FILE before invoking this skill." >&2
    exit 1
fi

# gpt-image-1 quality vocabulary: low | medium | high | auto.
# Map common HD-equivalent aliases so the parent's --quality survives.
case "${QUALITY:-}" in
    ""|hd|HD)   QUALITY="high" ;;
    standard)   QUALITY="medium" ;;
    low|medium|high|auto) ;;
    *) echo "openai_generate.sh: --quality '$QUALITY' not recognized for gpt-image-1; using 'high'." >&2
       QUALITY="high" ;;
esac

ESCAPED_PROMPT="$(json_escape "$PROMPT")"

REQUEST_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$REQUEST_FILE" "$RESPONSE_FILE"' EXIT

# gpt-image-1 always returns b64_json; no response_format field accepted.
cat > "$REQUEST_FILE" <<EOF
{"model":"$OPENAI_IMAGE_MODEL","prompt":"$ESCAPED_PROMPT","n":1,"size":"$SIZE","quality":"$QUALITY"}
EOF

HTTP_CODE="$(curl -sS -w '%{http_code}' -o "$RESPONSE_FILE" \
    "$OPENAI_IMAGE_ENDPOINT" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary @"$REQUEST_FILE")" || {
    echo "openai_generate.sh: curl failed talking to $OPENAI_IMAGE_ENDPOINT" >&2
    exit 1
}

if [ "$HTTP_CODE" != "200" ]; then
    echo "openai_generate.sh: OpenAI API returned HTTP $HTTP_CODE" >&2
    cat "$RESPONSE_FILE" >&2
    echo >&2
    exit 1
fi

# Pull the first b64_json. The base64 payload contains no double-quotes,
# so a non-greedy single-line match is safe.
B64="$(tr -d '\n\r' < "$RESPONSE_FILE" \
    | sed -n 's/.*"b64_json"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"

if [ -z "$B64" ]; then
    echo "openai_generate.sh: could not extract image data from response" >&2
    cat "$RESPONSE_FILE" >&2
    exit 1
fi

printf '%s' "$B64" | base64 -d > "$OUTPUT" || {
    echo "openai_generate.sh: base64 decode failed" >&2
    exit 1
}

echo "Image saved to: $OUTPUT (model=$OPENAI_IMAGE_MODEL, quality=$QUALITY)"
