#!/usr/bin/env bash
# generate.sh — entry point for the generate-sound skill.
# Reads /home/owner/.carbon/config.yaml, picks the provider from
# defaults.provider, and dispatches to the right (mode × provider) handler.
#
# The carbon config does NOT carry an audio model — it tracks the user's
# chat-tier choice (e.g. defaults.model: light). Audio model defaults are
# baked into this script per (provider, mode); the user can override with
# --model.
#
# Usage:
#   generate.sh "<text or music prompt>"
#               [--mode music|speech]   (default: speech)
#               [--model NAME]
#               [--voice NAME]          (TTS only)
#               [--format FMT]
#               [--speed N]             (OpenAI TTS only)
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
MODEL=""
VOICE=""
FORMAT=""
SPEED=""
OUTPUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)       MODE="${2:-}";       shift 2 ;;
        --model)      MODEL="${2:-}";      shift 2 ;;
        --voice)      VOICE="${2:-}";      shift 2 ;;
        --format)     FORMAT="${2:-}";     shift 2 ;;
        --speed)      SPEED="${2:-}";      shift 2 ;;
        --output)     OUTPUT="${2:-}";     shift 2 ;;
        --input-file) INPUT_FILE="${2:-}"; shift 2 ;;
        --help|-h)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
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

# Pick a sensible audio model when the user did not pass --model.
# These are not in the config; the config tracks the chat-tier model only.
if [ -z "$MODEL" ]; then
    case "$PROVIDER:$MODE" in
        openai:speech)  MODEL="tts-1-hd" ;;
        gemini:speech)  MODEL="gemini-2.5-flash-preview-tts" ;;
        gemini:music)   MODEL="lyria-3-pro-preview" ;;
        google:speech)  MODEL="gemini-2.5-flash-preview-tts" ;;
        google:music)   MODEL="lyria-3-pro-preview" ;;
        openai:music)   MODEL="" ;;       # unsupported; rejected below
        anthropic:*)    MODEL="" ;;       # unsupported; rejected below
        *)              MODEL="" ;;
    esac
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
Audio-capable defaults this skill will pick:
  - speech: tts-1-hd (openai), gemini-2.5-flash-preview-tts (gemini)
  - music:  lyria-3-pro-preview (gemini only — OpenAI has no music API)
EOF
        exit 2
        ;;
    openai)
        if [ "$MODE" = "music" ]; then
            cat >&2 <<EOF
generate.sh: OpenAI does not have a music generation API.
Run with --mode speech (or omit --mode), or switch defaults.provider to 'gemini'
to use Lyria 3 (default model: lyria-3-pro-preview).
EOF
            exit 2
        fi
        exec bash "$SCRIPT_DIR/openai_tts.sh" \
            --config "$CONFIG_FILE" \
            --model  "$MODEL" \
            --voice  "$VOICE" \
            --format "$FORMAT" \
            --speed  "$SPEED" \
            --output "$OUTPUT" \
            -- "$TEXT"
        ;;
    gemini|google)
        if [ "$MODE" = "music" ]; then
            exec bash "$SCRIPT_DIR/gemini_music.sh" \
                --config "$CONFIG_FILE" \
                --model  "$MODEL" \
                --format "$FORMAT" \
                --output "$OUTPUT" \
                -- "$TEXT"
        else
            exec bash "$SCRIPT_DIR/gemini_tts.sh" \
                --config "$CONFIG_FILE" \
                --model  "$MODEL" \
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
