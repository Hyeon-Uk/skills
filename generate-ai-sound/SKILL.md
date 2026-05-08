---
name: generate-ai-sound
description: Generates audio from text — music (Google Gemini Lyria 3) or speech (OpenAI TTS, Gemini TTS). Reads API keys from /home/owner/.carbon/config.yaml. Provider is chosen by request type: music always routes to gemini (only Lyria supports music); speech prefers defaults.provider but auto-falls back to gemini or openai if the active provider is anthropic. Accepts --model to override the default model. Pure shell + curl, no Python/Node required. Trigger when the user asks to compose music, generate a song/jingle/tune/backing track, read text aloud, narrate, generate a voiceover, or synthesize speech. Always tell the user which provider was selected.
argument-hint: "[--mode music|speech] [--model NAME] [--voice NAME] [--output PATH]"
user-invocable: true
allowed-tools: true
---

# generate-ai-sound

Generates an audio file from a text input — either a music clip or spoken speech — choosing the **most appropriate provider for the request**, regardless of `defaults.provider` in `/home/owner/.carbon/config.yaml`.

**Prerequisite:** API keys must be configured in `config.yaml`:
- **Music** requests always use `gemini` → `providers.gemini.api_key` must be a valid Google AI Studio key (`AIza...`)
- **Speech** requests use `defaults.provider`; if that's `anthropic`, the skill falls back to `gemini` first, then `openai`

Have both `providers.openai.api_key` and `providers.gemini.api_key` set for full coverage. If the required key is missing or empty, the provider script exits non-zero with a message naming the missing field. Do not retry — ask the user to set the key first.

## Intent-Based Workflow

| User says | Mode | Example |
|---|---|---|
| "Generate a 30-second cheerful acoustic folk tune" | `music` | `bash generate.sh "cheerful acoustic folk" --mode music` |
| "Compose a tense cinematic cue for the chase scene" | `music` | `bash generate.sh "tense cinematic chase" --mode music` |
| "Make a jingle for my podcast intro" | `music` | `bash generate.sh "podcast intro jingle" --mode music` |
| "Read this paragraph aloud" | `speech` | `bash generate.sh "paragraph text" --mode speech` |
| "Generate a voiceover with a calm female voice" | `speech` | `bash generate.sh "script" --mode speech --voice nova` |
| "Narrate this story" | `speech` | `bash generate.sh "story text" --mode speech` |

**When to use `--mode music` vs `--mode speech`:**
- **`--mode music`**: When the user asks to compose, make, or generate a song, tune, jingle, backing track, or any musical content. Always routes to `gemini` (Lyria).
- **`--mode speech`** (default): When the user asks to read aloud, narrate, generate a voiceover, or synthesize speech. Honors `defaults.provider` with fallback from `anthropic`.

**Always tell the user which provider was selected**, especially when it differs from `defaults.provider`.

## CLI Usage

```bash
bash <skill-dir>/scripts/generate.sh "<text or music prompt>" [OPTIONS]
```

### Options

| Option | Default | Modes | Description |
|--------|---------|-------|-------------|
| `--mode music\|speech` | `speech` | both | Select music or speech generation |
| `--model NAME` | per (provider, mode) | both | Override the default model |
| `--voice NAME` | `alloy` (OpenAI), `Kore` (Gemini) | TTS only | Voice for speech synthesis |
| `--format FMT` | `wav` (TTS), `mp3` (Lyria) | both | Output audio format |
| `--speed N` | `1.0` | OpenAI TTS only | Speech speed (0.25–4.0) |
| `--output PATH` | `./audio_<timestamp>.<ext>` | both | Output file path |
| `--input-file PATH` | (positional text used) | TTS only | Read text from a file |
| `-h`, `--help` | | | Show help message |

### Default Models per Provider and Mode

| Provider | `--mode speech` default | `--mode music` default |
|---|---|---|
| `openai` | `tts-1-hd` | N/A |
| `gemini` | `gemini-2.5-flash-preview-tts` | `lyria-3-pro-preview` |

### Voices (TTS only)

**OpenAI:** `alloy`, `ash`, `ballad`, `coral`, `echo`, `fable`, `onyx`, `nova`, `sage`, `shimmer`, `verse`

**Gemini TTS:** `Kore`, `Puck`, `Zephyr`, `Charon`, `Fenrir`, `Leda`, `Orus`, `Aoede`, `Callirrhoe`, `Autonoe`, `Enceladus`, `Iapetus`

### Format Options

**OpenAI TTS:** `mp3`, `opus`, `aac`, `flac`, `wav`, `pcm`
**Gemini TTS:** `wav`, `pcm`
**Lyria (music):** `mp3` only (WAV not supported by live API)

## Output

### Success

The script outputs the absolute path of the saved audio file on stdout:

```
/tmp/audio_20260325_143025.wav
```

### Error

Error messages are written to stderr. Common errors:

| Error | Description | Recovery Action |
|-------|-------------|-----------------|
| `cannot read config` | `config.yaml` missing or unreadable | Create config file at `/home/owner/.carbon/config.yaml` |
| `api_key missing` | Provider key not set | Add `providers.<name>.api_key` to config |
| `Lyria copyright filter` | Prompt too close to copyrighted material | Rephrase using abstract mood/instruments/tempo |
| `invalid voice` | Voice name not recognized | Use a valid voice from the list above |
| `WAV not supported for Lyria` | `--format wav` with music mode | Use `--format mp3` for music |

## Provider Routing

| `--mode` | `defaults.provider` | Effective Provider | Notes |
|---|---|---|---|
| `music` | any | `gemini` | Only Lyria supports music |
| `speech` | `openai` | `openai` | Honored as configured |
| `speech` | `gemini` | `gemini` | Honored as configured |
| `speech` | `anthropic` | `gemini` → `openai` fallback | Auto-switch; tell user |

## Config Schema

`/home/owner/.carbon/config.yaml`:

```yaml
version: 1

defaults:
  provider: openai          # which provider this skill uses
  model: light              # chat-tier label — IGNORED by this skill

providers:
  openai:
    api_key: "sk-..."       # REQUIRED for speech via OpenAI
  gemini:
    api_key: "AIza-..."     # REQUIRED for music and speech via Gemini
  anthropic:
    api_key: "sk-ant-..."   # not used (anthropic has no audio API)
```

The skill reads `defaults.provider` and `providers.<defaults.provider>.api_key`. It deliberately **does not** read `defaults.model` (that's the chat tier in carbon's normal flow) and it deliberately **does not** read any `base_url` field — each provider script targets that provider's official endpoint only.

## Edge Cases

| Case | Handling |
|------|----------|
| Lyria response includes lyrics text | Discarded; extract audio only |
| Lyria copyright filter (`finishReason: OTHER`) | Surface message verbatim; suggest rephrasing |
| Long input text (TTS) | OpenAI limits ~4096 chars; split if needed |
| Special characters in prompt | Escaped automatically |
| `config.yaml` missing | Exit non-zero with path tried |
| `providers.<name>.api_key` empty | Exit non-zero with field name |
| Custom proxy / gateway | Not supported; scripts hit official endpoints only |
| Output path's parent directory doesn't exist | Create directory first |
| Gemini TTS output format | Always WAV/PCM; use ffmpeg for MP3 |
| SynthID watermark on Lyria | All Lyria audio carries inaudible watermark |

## Examples

```bash
# Generate music (always uses Gemini/Lyria)
bash generate.sh "upbeat electronic dance track with synth leads" --mode music

# Generate speech with default provider
bash generate.sh "Hello, welcome to our podcast." --mode speech

# Specify voice for TTS
bash generate.sh "Welcome to the show!" --mode speech --voice nova

# Use Gemini TTS explicitly
# First set defaults.provider: gemini in config.yaml
bash generate.sh "This is a test narration." --mode speech

# Custom output path and format
bash generate.sh "Background music for video" --mode music --output /tmp/bgm.mp3

# Read from file for long passages
bash generate.sh --mode speech --input-file /tmp/script.txt --output /tmp/narration.wav

# Adjust speech speed (OpenAI only)
bash generate.sh "Slow down this text" --mode speech --speed 0.75
```

## Files

- `scripts/generate.sh` — orchestrator
- `scripts/openai_tts.sh` — OpenAI text-to-speech
- `scripts/gemini_tts.sh` — Gemini text-to-speech (PCM → WAV)
- `scripts/gemini_music.sh` — Google Lyria 3 music generation
- `scripts/parse_yaml.sh` — YAML helpers