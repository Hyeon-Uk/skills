#!/usr/bin/env bash
# generate.sh — entry point for generate-ai-video skill.
# Generates an image and music from the same prompt via Gemini APIs,
# then combines them into an MP4 with ffmpeg.
#
# Usage:
#   generate.sh "<prompt>" [--length clip|full] [--size WxH] [--output PATH]
#               [--image-output PATH] [--audio-output PATH]
#
# Exit codes:
#   0  success — final line of stdout is the absolute output path
#   1  usage error / config missing / API failure / ffmpeg missing

set -eu

CONFIG_FILE="${CARBON_CONFIG:-/home/owner/.carbon/config.yaml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

PROMPT=""
LENGTH="clip"
SIZE="1024x1024"
OUTPUT=""
IMAGE_OUTPUT=""
AUDIO_OUTPUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --length)       LENGTH="${2:-}";       shift 2 ;;
        --size)         SIZE="${2:-}";         shift 2 ;;
        --output)       OUTPUT="${2:-}";       shift 2 ;;
        --image-output) IMAGE_OUTPUT="${2:-}"; shift 2 ;;
        --audio-output) AUDIO_OUTPUT="${2:-}"; shift 2 ;;
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
    echo "Usage: generate.sh \"<prompt>\" [--length clip|full] [--size WxH] [--output PATH]" >&2
    exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "generate.sh: ffmpeg is required but not found in PATH" >&2
    echo "Install: apt-get install ffmpeg  OR  brew install ffmpeg" >&2
    exit 1
fi

if [ ! -r "$CONFIG_FILE" ]; then
    echo "generate.sh: cannot read config at $CONFIG_FILE" >&2
    echo "Set CARBON_CONFIG to override the path, or create the file." >&2
    exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
[ -z "$OUTPUT" ]       && OUTPUT="./video_${TS}.mp4"
[ -z "$IMAGE_OUTPUT" ] && IMAGE_OUTPUT="./image_${TS}.png"
[ -z "$AUDIO_OUTPUT" ] && AUDIO_OUTPUT="./audio_${TS}.mp3"

# Step 1: Generate image
echo "Generating image…" >&2
IMAGE_LINE="$(bash "$SCRIPT_DIR/gemini_image.sh" \
    --config "$CONFIG_FILE" \
    --size   "$SIZE" \
    --output "$IMAGE_OUTPUT" \
    -- "$PROMPT")"
echo "$IMAGE_LINE" >&2
IMAGE_FILE="$(printf '%s\n' "$IMAGE_LINE" | grep '^Image saved to:' | sed 's/^Image saved to: //; s/ (.*//')"
[ -z "$IMAGE_FILE" ] && IMAGE_FILE="$IMAGE_OUTPUT"

# Step 2: Generate music
echo "Generating music…" >&2
AUDIO_LINE="$(bash "$SCRIPT_DIR/gemini_music.sh" \
    --config "$CONFIG_FILE" \
    --length "$LENGTH" \
    --output "$AUDIO_OUTPUT" \
    -- "$PROMPT")"
echo "$AUDIO_LINE" >&2
AUDIO_FILE="$(printf '%s\n' "$AUDIO_LINE" | grep '^Music saved to:' | sed 's/^Music saved to: //; s/ (.*//')"
[ -z "$AUDIO_FILE" ] && AUDIO_FILE="$AUDIO_OUTPUT"

# Step 3: Combine into video
echo "Combining into video…" >&2
bash "$SCRIPT_DIR/combine.sh" \
    --image  "$IMAGE_FILE" \
    --audio  "$AUDIO_FILE" \
    --output "$OUTPUT" || exit 1

echo "$OUTPUT"
