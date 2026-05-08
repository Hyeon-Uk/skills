#!/usr/bin/env bash
# generate.sh — entry point for the generate-sound skill.
# Reads /home/owner/.carbon/config.yaml, picks the provider from
# defaults.provider, and dispatches to the right (mode × provider) handler.
#
# The carbon config does NOT carry an audio model — it tracks the user's
# chat-tier choice (e.g. defaults.model: light). Models are pinned inside
# the provider scripts. Music selects between two static endpoints via
# --length clip|full. `--model` and `--speed` are no longer real options;
# passing either prints an "unsupported option" warning and continues.
#
# Usage:
#   generate.sh "<text or music prompt>"
#               [--mode music|speech]   (default: speech)
#               [--length clip|full]    (music only; default: full)
#               [--voice NAME]          (TTS only)
#               [--format FMT]
#               [--output PATH]
#               [--input-file PATH]
#
# Exit codes:
#   0  success — final line of stdout is the absolute output path
#   1  usage error / config missing / API failure
#   2  unsupported provider × mode combination

set -eu

CONFIG_FILE="${CARBON_CONFIG:-/home/owner/.carbon/config.yaml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

TEXT=""
INPUT_FILE=""
MODE="speech"
LENGTH=""
VOICE=""
FORMAT=""
OUTPUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)       MODE="${2:-}";       shift 2 ;;
        --length)     LENGTH="${2:-}";     shift 2 ;;
        --voice)      VOICE="${2:-}";      shift 2 ;;
        --format)     FORMAT="${2:-}";     shift 2 ;;
        --output)     OUTPUT="${2:-}";     shift 2 ;;
        --input-file) INPUT_FILE="${2:-}"; shift 2 ;;
        --model)
            echo "generate.sh: unsupported option '--model' — models are pinned per provider×mode; ignoring." >&2
            shift 2
            ;;
        --speed)
            echo "generate.sh: unsupported option '--speed' — no pinned TTS model accepts speed; ignoring." >&2
            shift 2
            ;;
        --help|-h)
            sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --) shift; TEXT="${1:-$TEXT}"; shift || true ;;
        -*) echo "generate.sh: unknown flag: $1" >&2; exit 1 ;;
        *)  TEXT="$1"; shift ;;
    esac
done

case "$MODE" in
    speech|tts)    MODE="speech" ;;
    music|song)    MODE="music"  ;;
    *) echo "generate.sh: --mode must be 'speech' or 'music' (got '$MODE')" >&2; exit 1 ;;
esac

if [ -n "$INPUT_FILE" ]; then
    if [ ! -r "$INPUT_FILE" ]; then
        echo "generate.sh: cannot read --input-file $INPUT_FILE" >&2
        exit 1
    fi
    TEXT="$(cat "$INPUT_FILE")"
fi

if [ -z "$TEXT" ]; then
    echo "generate.sh: text is required (positional arg or --input-file)" >&2
    echo "Usage: generate.sh \"<text or music prompt>\" [--mode music|speech] [options]" >&2
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

# Default --length for music mode.
if [ "$MODE" = "music" ] && [ -z "$LENGTH" ]; then
    LENGTH="full"
fi

# Format default (HD-equivalent per mode + model).
# Lyria via the Gemini :generateContent endpoint currently emits MP3 only —
# the documented responseMimeType="audio/wav" override is rejected by the live
# API (HTTP 400, "allowed mimetypes are text/plain, application/json, ..."),
# so we default to MP3 for both Lyria variants instead of advertising WAV.
if [ -z "$FORMAT" ]; then
    if [ "$MODE" = "music" ]; then
        FORMAT="mp3"
    else
        FORMAT="wav"
    fi
fi

if [ -z "$OUTPUT" ]; then
    OUTPUT="./audio_$(date +%Y%m%d_%H%M%S).${FORMAT}"
fi

case "$PROVIDER" in
    anthropic)
        cat >&2 <<EOF
generate.sh: provider 'anthropic' does not support audio generation.
Anthropic's Claude models can analyze audio but cannot produce it.
Edit $CONFIG_FILE and set 'defaults.provider:' to 'openai' or 'gemini'.
Audio-capable models (all pinned at static endpoints):
  - speech: gpt-4o-mini-tts (openai), gemini-3.1-flash-tts-preview (gemini)
  - music:  lyria-3-pro-preview (--length full) or lyria-3-clip-preview
            (--length clip); gemini only — OpenAI has no music API
EOF
        exit 2
        ;;
    openai)
        if [ "$MODE" = "music" ]; then
            cat >&2 <<EOF
generate.sh: OpenAI does not have a music generation API.
Run with --mode speech (or omit --mode) — pinned to gpt-4o-mini-tts — or
switch defaults.provider to 'gemini' to use Lyria 3 (--length full pins
to lyria-3-pro-preview, --length clip pins to lyria-3-clip-preview).
EOF
            exit 2
        fi
        # Endpoint + model are pinned inside openai_tts.sh (gpt-4o-mini-tts).
        exec bash "$SCRIPT_DIR/openai_tts.sh" \
            --config "$CONFIG_FILE" \
            --voice  "$VOICE" \
            --format "$FORMAT" \
            --output "$OUTPUT" \
            -- "$TEXT"
        ;;
    gemini|google)
        if [ "$MODE" = "music" ]; then
            # Endpoint + model are pinned inside gemini_music.sh (static URLs).
            exec bash "$SCRIPT_DIR/gemini_music.sh" \
                --config "$CONFIG_FILE" \
                --length "$LENGTH" \
                --format "$FORMAT" \
                --output "$OUTPUT" \
                -- "$TEXT"
        else
            # Endpoint + model are pinned inside gemini_tts.sh (static URL).
            exec bash "$SCRIPT_DIR/gemini_tts.sh" \
                --config "$CONFIG_FILE" \
                --voice  "$VOICE" \
                --format "$FORMAT" \
                --output "$OUTPUT" \
                -- "$TEXT"
        fi
        ;;
    *)
        echo "generate.sh: unknown provider '$PROVIDER' (expected openai, gemini, or anthropic)" >&2
        exit 1
        ;;
esac
