#!/usr/bin/env bash
# combine.sh — combines a static image and audio file into an MP4 using ffmpeg.
# Called by generate.sh; not meant to be invoked directly.
#
# ffmpeg flags:
#   -loop 1           treat the single image as an infinite loop
#   -tune stillimage  codec tuning for still-image video sources
#   -pix_fmt yuv420p  broadest player compatibility (requires even dimensions)
#   -shortest         cut video when the audio track ends

set -eu

IMAGE_FILE=""
AUDIO_FILE=""
OUTPUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --image)  IMAGE_FILE="$2"; shift 2 ;;
        --audio)  AUDIO_FILE="$2"; shift 2 ;;
        --output) OUTPUT="$2";     shift 2 ;;
        *)  echo "combine.sh: unexpected arg: $1" >&2; exit 1 ;;
    esac
done

[ -z "$IMAGE_FILE" ] && { echo "combine.sh: --image is required" >&2; exit 1; }
[ -z "$AUDIO_FILE" ] && { echo "combine.sh: --audio is required" >&2; exit 1; }
[ -z "$OUTPUT" ]     && { echo "combine.sh: --output is required" >&2; exit 1; }

if [ ! -f "$IMAGE_FILE" ]; then
    echo "combine.sh: image file not found: $IMAGE_FILE" >&2; exit 1
fi
if [ ! -f "$AUDIO_FILE" ]; then
    echo "combine.sh: audio file not found: $AUDIO_FILE" >&2; exit 1
fi

# vf scale: pad to even pixel dimensions required by yuv420p
if ! ffmpeg -y -loglevel error \
    -loop 1 -i "$IMAGE_FILE" \
    -i "$AUDIO_FILE" \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
    -c:v libx264 -tune stillimage \
    -c:a aac -b:a 192k \
    -pix_fmt yuv420p \
    -shortest \
    "$OUTPUT"; then
    echo "combine.sh: ffmpeg failed — check that image and audio files are valid" >&2
    exit 1
fi

echo "Video saved to: $OUTPUT"
