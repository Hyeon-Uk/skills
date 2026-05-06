#!/usr/bin/env bash
# openai_generate.sh — OpenAI image generation.
# Called by generate.sh; not meant to be invoked directly by users.

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
        *)  echo "openai_generate.sh: unexpected arg: $1" >&2; exit 1 ;;
    esac
done

API_KEY="$(get_yaml_nested3 providers openai api_key "$CONFIG_FILE")"
if [ -z "$API_KEY" ]; then
    echo "openai_generate.sh: providers.openai.api_key not found in $CONFIG_FILE" >&2
    exit 1
fi

# Optional base_url override (LiteLLM proxies, internal gateways, etc.)
BASE_URL="$(get_yaml_nested3 providers openai base_url "$CONFIG_FILE" || true)"
[ -z "$BASE_URL" ] && BASE_URL="https://api.openai.com"
BASE_URL="${BASE_URL%/}"

# HD-equivalent default per model when caller did not specify quality.
# dall-e-2 has no quality knob; we send no field at all.
if [ -z "$QUALITY" ]; then
    case "$MODEL" in
        dall-e-3)     QUALITY="hd" ;;
        gpt-image-1)  QUALITY="high" ;;
        dall-e-2)     QUALITY="" ;;
        *)            QUALITY="high" ;;  # safe modern default
    esac
fi

ESCAPED_PROMPT="$(json_escape "$PROMPT")"

REQUEST_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$REQUEST_FILE" "$RESPONSE_FILE"' EXIT

# dall-e-3 returns URLs by default; ask for b64 so we don't need a second curl.
# gpt-image-1 always returns b64_json regardless of response_format.
# dall-e-2 supports b64_json too.
case "$MODEL" in
    dall-e-2)
        cat > "$REQUEST_FILE" <<EOF
{"model":"$MODEL","prompt":"$ESCAPED_PROMPT","n":1,"size":"$SIZE","response_format":"b64_json"}
EOF
        ;;
    dall-e-3)
        cat > "$REQUEST_FILE" <<EOF
{"model":"$MODEL","prompt":"$ESCAPED_PROMPT","n":1,"size":"$SIZE","quality":"$QUALITY","response_format":"b64_json"}
EOF
        ;;
    *)
        # gpt-image-1 and successors: no response_format field accepted.
        if [ -n "$QUALITY" ]; then
            cat > "$REQUEST_FILE" <<EOF
{"model":"$MODEL","prompt":"$ESCAPED_PROMPT","n":1,"size":"$SIZE","quality":"$QUALITY"}
EOF
        else
            cat > "$REQUEST_FILE" <<EOF
{"model":"$MODEL","prompt":"$ESCAPED_PROMPT","n":1,"size":"$SIZE"}
EOF
        fi
        ;;
esac

HTTP_CODE="$(curl -sS -w '%{http_code}' -o "$RESPONSE_FILE" \
    "$BASE_URL/v1/images/generations" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary @"$REQUEST_FILE")" || {
    echo "openai_generate.sh: curl failed talking to $BASE_URL" >&2
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
    URL="$(tr -d '\n\r' < "$RESPONSE_FILE" \
        | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -1)"
    if [ -n "$URL" ]; then
        curl -sS -o "$OUTPUT" "$URL" || {
            echo "openai_generate.sh: failed to download image from $URL" >&2
            exit 1
        }
        echo "Image saved to: $OUTPUT"
        exit 0
    fi
    echo "openai_generate.sh: could not extract image data from response" >&2
    cat "$RESPONSE_FILE" >&2
    exit 1
fi

printf '%s' "$B64" | base64 -d > "$OUTPUT" || {
    echo "openai_generate.sh: base64 decode failed" >&2
    exit 1
}

echo "Image saved to: $OUTPUT"
