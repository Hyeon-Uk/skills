#!/usr/bin/env bash
# generate.sh — entry point for generate-ai-video skill.
# Calls the Google Veo 3.1 API via Gemini predictLongRunning to generate an MP4.
#
# Model is pinned to veo-3.1-generate-preview (audio is generated natively).
#
# Usage:
#   generate.sh "<prompt>" [--aspect 16:9|9:16]
#               [--resolution 720p|1080p|4k]
#               [--output PATH] [--image PATH]
#
# --image PATH turns this into an image-to-video request: the file is
# base64-encoded and sent as a reference asset frame.
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
ASPECT=""
RESOLUTION=""
OUTPUT=""
IMAGE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --aspect)     ASPECT="${2:-}";     shift 2 ;;
        --resolution) RESOLUTION="${2:-}"; shift 2 ;;
        --output)     OUTPUT="${2:-}";     shift 2 ;;
        --image)      IMAGE="${2:-}";      shift 2 ;;
        --help|-h)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --) shift; PROMPT="${1:-$PROMPT}"; shift || true ;;
        -*) echo "generate.sh: unknown flag: $1" >&2; exit 1 ;;
        *)  PROMPT="$1"; shift ;;
    esac
done

if [ -z "$PROMPT" ]; then
    echo "generate.sh: prompt is required" >&2
    echo "Usage: generate.sh \"<prompt>\" [--aspect 16:9|9:16] [--resolution 720p|1080p|4k] [--output PATH] [--image PATH]" >&2
    exit 1
fi

if [ ! -r "$CONFIG_FILE" ]; then
    echo "generate.sh: cannot read config at $CONFIG_FILE" >&2
    echo "Set CARBON_CONFIG to override the path, or create the file." >&2
    exit 1
fi

if [ -n "$IMAGE" ] && [ ! -r "$IMAGE" ]; then
    echo "generate.sh: cannot read image at $IMAGE" >&2
    exit 1
fi

if [ -z "$OUTPUT" ]; then
    OUTPUT="./video_$(date +%Y%m%d_%H%M%S).mp4"
fi

exec bash "$SCRIPT_DIR/gemini_veo.sh" \
    --config     "$CONFIG_FILE" \
    ${ASPECT:+--aspect "$ASPECT"} \
    ${RESOLUTION:+--resolution "$RESOLUTION"} \
    --output     "$OUTPUT" \
    ${IMAGE:+--image "$IMAGE"} \
    -- "$PROMPT"
