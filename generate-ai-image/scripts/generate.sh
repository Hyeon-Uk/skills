#!/usr/bin/env bash
# generate.sh — entry point for the generate-image skill.
# Reads {agent_config_path}/config.yaml, picks the provider from
# defaults.provider, and dispatches.
#
# The agent config does NOT carry an image model — it tracks the user's
# chat-tier choice (e.g. defaults.model: light). Both provider scripts pin
# their endpoint+model at static URLs:
#   openai → gpt-image-1
#   gemini → gemini-3.1-flash-image-preview
# `--model` is no longer a real option; passing it prints an
# "unsupported option" warning and continues.
#
# Usage:
#   generate.sh "<prompt>" [--quality LEVEL] [--output PATH] [--size WxH]
#
# Exit codes:
#   0  success — final line of stdout is the absolute output path
#   1  usage error / config missing / API failure
#   2  active provider is anthropic (no image generation API)

set -eu

CONFIG_FILE="${AGENT_CONFIG:-${AGENT_CONFIG_PATH:+${AGENT_CONFIG_PATH%/}/config.yaml}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

PROMPT=""
QUALITY=""
OUTPUT=""
SIZE="1024x1024"

while [ $# -gt 0 ]; do
    case "$1" in
        --model)
            echo "generate.sh: unsupported option '--model' — models are pinned per provider; ignoring." >&2
            shift 2
            ;;
        --quality) QUALITY="${2:-}"; shift 2 ;;
        --output)  OUTPUT="${2:-}";  shift 2 ;;
        --size)    SIZE="${2:-}";    shift 2 ;;
        --help|-h)
            sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --) shift; PROMPT="${1:-$PROMPT}"; shift || true ;;
        -*) echo "generate.sh: unknown flag: $1" >&2; exit 1 ;;
        *)  PROMPT="$1"; shift ;;
    esac
done

if [ -z "$PROMPT" ]; then
    echo "generate.sh: prompt is required" >&2
    echo "Usage: generate.sh \"<prompt>\" [--quality LEVEL] [--output PATH] [--size WxH]" >&2
    exit 1
fi

if [ ! -r "$CONFIG_FILE" ]; then
    echo "generate.sh: cannot read config at $CONFIG_FILE" >&2
    echo "Set AGENT_CONFIG or AGENT_CONFIG_PATH to override the path, or create the file." >&2
    exit 1
fi

PROVIDER="$(get_yaml_nested defaults provider "$CONFIG_FILE" || true)"
if [ -z "$PROVIDER" ]; then
    echo "generate.sh: 'defaults.provider' missing from $CONFIG_FILE" >&2
    exit 1
fi

if [ -z "$OUTPUT" ]; then
    OUTPUT="./image_$(date +%Y%m%d_%H%M%S).png"
fi

case "$PROVIDER" in
    anthropic)
        cat >&2 <<EOF
generate.sh: provider 'anthropic' does not support image generation.
Anthropic's Claude models can analyze images but cannot create them.
Edit $CONFIG_FILE and set 'defaults.provider:' to 'openai' or 'gemini'.
Image-capable defaults: gpt-image-1 (openai), gemini-3.1-flash-image-preview (gemini).
Both endpoints and models are pinned.
EOF
        exit 2
        ;;
    openai)
        # Endpoint + model are pinned inside openai_generate.sh (gpt-image-1).
        exec bash "$SCRIPT_DIR/openai_generate.sh" \
            --config "$CONFIG_FILE" \
            --quality "$QUALITY" \
            --size   "$SIZE" \
            --output "$OUTPUT" \
            -- "$PROMPT"
        ;;
    gemini|google)
        # Endpoint + model are pinned inside gemini_generate.sh (static URL).
        exec bash "$SCRIPT_DIR/gemini_generate.sh" \
            --config "$CONFIG_FILE" \
            --size   "$SIZE" \
            --output "$OUTPUT" \
            -- "$PROMPT"
        ;;
    *)
        echo "generate.sh: unknown provider '$PROVIDER' (expected openai, gemini, or anthropic)" >&2
        exit 1
        ;;
esac
