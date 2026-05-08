#!/usr/bin/env bash
# generate.sh — entry point for the generate-image skill.
# Reads /home/owner/.carbon/config.yaml, picks the provider from
# defaults.provider, and dispatches.
#
# The carbon config does NOT carry an image model — it tracks the user's
# chat-tier choice (e.g. defaults.model: light). Image model defaults are
# baked into the provider scripts. Both providers now pin their endpoint+model
# at static URLs:
#   openai → gpt-image-1
#   gemini → gemini-3.1-flash-image-preview
# `--model` is accepted on the CLI but logged as ignored.
#
# Usage:
#   generate.sh "<prompt>" [--model NAME] [--quality LEVEL]
#                          [--output PATH] [--size WxH]
#
# Exit codes:
#   0  success — final line of stdout is the absolute output path
#   1  usage error / config missing / API failure
#   2  active provider is anthropic (no image generation API)

set -eu

CONFIG_FILE="${CARBON_CONFIG:-/home/owner/.carbon/config.yaml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

PROMPT=""
MODEL=""
QUALITY=""
OUTPUT=""
SIZE="1024x1024"

while [ $# -gt 0 ]; do
    case "$1" in
        --model)   MODEL="${2:-}";   shift 2 ;;
        --quality) QUALITY="${2:-}"; shift 2 ;;
        --output)  OUTPUT="${2:-}";  shift 2 ;;
        --size)    SIZE="${2:-}";    shift 2 ;;
        --help|-h)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --) shift; PROMPT="${1:-$PROMPT}"; shift || true ;;
        -*) echo "generate.sh: unknown flag: $1" >&2; exit 1 ;;
        *)  PROMPT="$1"; shift ;;
    esac
done

if [ -z "$PROMPT" ]; then
    echo "generate.sh: prompt is required" >&2
    echo "Usage: generate.sh \"<prompt>\" [--model NAME] [--quality LEVEL] [--output PATH] [--size WxH]" >&2
    exit 1
fi

if [ ! -r "$CONFIG_FILE" ]; then
    echo "generate.sh: cannot read config at $CONFIG_FILE" >&2
    echo "Set CARBON_CONFIG to override the path, or create the file." >&2
    exit 1
fi

PROVIDER="$(get_yaml_nested defaults provider "$CONFIG_FILE" || true)"
if [ -z "$PROVIDER" ]; then
    echo "generate.sh: 'defaults.provider' missing from $CONFIG_FILE" >&2
    exit 1
fi

# Both provider scripts now pin their endpoint+model. Warn once if the user
# explicitly passed --model so they understand it has no effect, then clear
# the variable so we don't bother passing it through.
case "$PROVIDER" in
    gemini|google)
        if [ -n "$MODEL" ]; then
            echo "generate.sh: --model is ignored for gemini; this skill is pinned to gemini-3.1-flash-image-preview." >&2
        fi
        MODEL=""
        ;;
    openai)
        if [ -n "$MODEL" ]; then
            echo "generate.sh: --model is ignored for openai; this skill is pinned to gpt-image-1." >&2
        fi
        MODEL=""
        ;;
esac

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
Both endpoints and models are pinned (--model is ignored).
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
