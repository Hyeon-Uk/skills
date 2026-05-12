#!/usr/bin/env bash
# generate.sh — entry point for generate-ai-video skill.
# Calls the Google Veo API via Gemini predictLongRunning to generate an MP4.
#
# Usage:
#   generate.sh "<prompt>" [--model veo-3|veo-2] [--aspect RATIO]
#               [--duration SECS] [--output PATH]
#
# Exit codes:
#   0  success — final line of stdout is the absolute output path
#   1  usage error / config missing / API failure / timeout

set -eu

CONFIG_FILE="${CARBON_CONFIG:-/home/owner/.carbon/config.yaml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

PROMPT=""
MODEL="veo-3"
ASPECT="16:9"
DURATION="8"
OUTPUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --model)    MODEL="${2:-}";    shift 2 ;;
        --aspect)   ASPECT="${2:-}";   shift 2 ;;
        --duration) DURATION="${2:-}"; shift 2 ;;
        --output)   OUTPUT="${2:-}";   shift 2 ;;
        --help|-h)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --) shift; PROMPT="${1:-$PROMPT}"; shift || true ;;
        -*) echo "generate.sh: unknown flag: $1" >&2; exit 1 ;;
        *)  PROMPT="$1"; shift ;;
    esac
done

if [ -z "$PROMPT" ]; then
    echo "generate.sh: prompt is required" >&2
    echo "Usage: generate.sh \"<prompt>\" [--model veo-3|veo-2] [--aspect RATIO] [--duration SECS] [--output PATH]" >&2
    exit 1
fi

if [ ! -r "$CONFIG_FILE" ]; then
    echo "generate.sh: cannot read config at $CONFIG_FILE" >&2
    echo "Set CARBON_CONFIG to override the path, or create the file." >&2
    exit 1
fi

if [ -z "$OUTPUT" ]; then
    OUTPUT="./video_$(date +%Y%m%d_%H%M%S).mp4"
fi

exec bash "$SCRIPT_DIR/gemini_veo.sh" \
    --config   "$CONFIG_FILE" \
    --model    "$MODEL" \
    --aspect   "$ASPECT" \
    --duration "$DURATION" \
    --output   "$OUTPUT" \
    -- "$PROMPT"
