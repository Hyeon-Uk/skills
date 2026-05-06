---
name: generate-sound
description: Generates audio from text — either music (Google Gemini Lyria 3) or speech (OpenAI TTS, Gemini TTS). Reads the active provider and API key from `/home/owner/.carbon/config.yaml` (`defaults.provider` + `providers.<name>.api_key` + optional `providers.<name>.base_url`). Audio-generation models are NOT in the carbon config — the skill picks a sensible default per (provider, mode) and accepts `--model` to override. Mode is selected with `--mode music|speech` (default `speech`). Built for embedded Linux: pure shell + curl, no Python or Node required. Use this skill whenever the user asks to create a song, generate music, compose a tune, make a backing track, write a jingle; or to read text aloud, narrate, generate a voiceover, synthesize speech, make an MP3 from text — even if they don't explicitly say "use the skill". If `defaults.provider` is `anthropic`, or if `provider: openai` is paired with `--mode music` (OpenAI has no music API), the skill returns a clear error with the fix.
---

# generate-sound

Generates an audio file from a text input — either a music clip or spoken speech — using whichever provider is active in `/home/owner/.carbon/config.yaml`.

## Mode is selected via `--mode`, not the config

The carbon config tracks a chat-tier model (`defaults.model: light`/`heavy`/...) — it doesn't list audio models, and it doesn't say whether the user wants music or speech. So:

- The orchestrator takes a `--mode music|speech` flag (default: `speech`).
- It picks a sensible model per (provider, mode) when the user doesn't pass `--model`.

| `defaults.provider` | `--mode speech` default model | `--mode music` default model |
|---|---|---|
| `openai` | `tts-1-hd` | (rejected — no music API) |
| `gemini` | `gemini-2.5-flash-preview-tts` | `lyria-3-pro-preview` |
| `anthropic` | (rejected) | (rejected) |

If the user clearly wants music ("compose a song", "make a backing track", "generate a 30-second jingle"), pass `--mode music`. Otherwise default mode (speech) is correct.

## When to use this skill

Trigger on any user request that boils down to "produce an audio file from this text". Examples:
- **Music**: "Generate a 30-second cheerful acoustic folk tune with guitar and harmonica" / "Compose a tense cinematic cue for the chase scene" / "Make a jingle for my podcast intro"
- **Speech**: "Read this paragraph aloud and save it as narration.mp3" / "Generate a voiceover for the intro of my video" / "Use a calm female voice to narrate this script"

If the user names a provider explicitly ("use Gemini Lyria for..."), still defer to the active `defaults.provider` in `config.yaml` — the user's setting wins. Only mention a mismatch if the active config can't fulfill the request (e.g. `defaults.provider: anthropic`, or `defaults.provider: openai` + `--mode music`).

This skill does **not** do speech-to-text (transcription).

## How it works

Five files in `scripts/`:

- `generate.sh` — entry point. Reads `defaults.provider`, picks the (mode × provider) handler, picks a default model if `--model` wasn't given.
- `openai_tts.sh` — calls `<base_url>/v1/audio/speech` (default base: `https://api.openai.com`). Response is binary audio, written straight to disk.
- `gemini_tts.sh` — calls `<base_url>/v1beta/models/<model>:generateContent` (default base: `https://generativelanguage.googleapis.com`) with `responseModalities: ["AUDIO"]`. Response is base64 24 kHz / 16-bit / mono PCM; the script prepends a 44-byte WAV header so the file plays in standard players.
- `gemini_music.sh` — calls `<base_url>/v1beta/models/lyria-3-*-preview:generateContent`. Response is base64 MP3 (Clip and Pro) or WAV (Pro only); the script just decodes — no header wrapping needed because Lyria already emits a complete container.
- `parse_yaml.sh` — minimal YAML reader (top-level + 2-level + 3-level nesting). Shared with `generate-image`.

All five are POSIX-friendly bash. JSON parsing uses `sed` (no `jq` dependency). The TTS WAV header is emitted with `printf` octal escapes so no extra binary tools are needed.

## Invocation

```bash
bash <skill-dir>/scripts/generate.sh "<text or music prompt>" [options]
```

### Options

| Flag | Default | Modes | Notes |
|---|---|---|---|
| `--mode music\|speech` | `speech` | both | Pass `--mode music` whenever the user is asking for a song/tune/jingle. |
| `--model NAME` | per (provider, mode) — see table above | both | Use this when the user names a specific model. The carbon config does not contain audio models. |
| `--voice NAME` | `alloy` (OpenAI TTS), `Kore` (Gemini TTS) | TTS only | Ignored in music mode. |
| `--format FMT` | HD-equivalent for the active model (see below) | both | OpenAI TTS: `mp3 \| opus \| aac \| flac \| wav \| pcm`. Gemini TTS: `wav` or `pcm`. Lyria Clip: `mp3` only. Lyria Pro: `mp3` or `wav`. |
| `--speed N` | `1.0` | OpenAI TTS only | Range 0.25–4.0. Gemini TTS uses prompt phrasing; Lyria has no speed knob. |
| `--output PATH` | `./audio_<YYYYmmdd_HHMMSS>.<ext>` in cwd | both | Extension is inferred from `--format`. |
| `--input-file PATH` | (positional text used) | TTS — long passages | Read text from a file. |

### HD quality default — IMPORTANT

If the user did **not** mention audio quality, do **not** pass `--format`. The script falls back to:

- TTS (OpenAI / Gemini) → `wav` (lossless)
- `lyria-3-pro-preview` → `wav` (lossless)
- `lyria-3-clip-preview` → `mp3` (Clip emits MP3 only — there is no lossless option)

Pass `--format mp3` only when the user explicitly opts out of HD ("a quick draft is fine", "low quality is OK", "save space"). HD is the default precisely because users assume the best version unless they opt out.

The model identifier itself also carries a quality tier (Lyria Clip vs Pro, `tts-1` vs `tts-1-hd`). The defaults this skill picks are HD-tier (`tts-1-hd`, `lyria-3-pro-preview`). To downshift, pass `--model <cheaper-name>` explicitly.

### Voices (TTS only)

**OpenAI**: `alloy`, `ash`, `ballad`, `coral`, `echo`, `fable`, `onyx`, `nova`, `sage`, `shimmer`, `verse`. The user might describe a voice ("warm female", "deep male") — pick the closest match and tell them which one you chose.

**Gemini TTS**: `Kore`, `Puck`, `Zephyr`, `Charon`, `Fenrir`, `Leda`, `Orus`, `Aoede`, `Callirrhoe`, `Autonoe`, `Enceladus`, `Iapetus`, etc. Casing matters — `Kore` not `kore`.

## Config schema

`/home/owner/.carbon/config.yaml`:

```yaml
version: 1

defaults:
  provider: openai          # which provider this skill uses
  model: light              # chat-tier label — IGNORED by this skill

providers:
  openai:
    api_key: "sk-..."
    base_url: ""            # optional override; empty → api.openai.com
  gemini:
    api_key: "AIza-..."
    base_url: ""            # optional; empty → generativelanguage.googleapis.com
  anthropic:
    api_key: "sk-ant-..."
    base_url: ""
```

The skill reads `defaults.provider`, `providers.<defaults.provider>.api_key`, and `providers.<defaults.provider>.base_url`. It deliberately **does not** read `defaults.model` — that field is the chat-tier model in carbon's normal flow, not an audio model.

## Provider routing

| `defaults.provider` | `--mode` | Outcome |
|---|---|---|
| `anthropic` | any | exit 2, "no audio generation API" |
| `openai` | `music` | exit 2, "OpenAI has no music API; switch to gemini for Lyria" |
| `openai` | `speech` | dispatch to `openai_tts.sh`, default model `tts-1-hd` |
| `gemini` | `music` | dispatch to `gemini_music.sh`, default model `lyria-3-pro-preview` |
| `gemini` | `speech` | dispatch to `gemini_tts.sh`, default model `gemini-2.5-flash-preview-tts` |

## Reporting back to the user

After success, tell the user the absolute path of the saved file, the model used, and the chosen voice (TTS only). If the script failed, surface its stderr verbatim. The most common failures (missing key, bad voice name, anthropic provider, openai+music mismatch) all need a config or argument change rather than a retry.

## Edge cases worth knowing

- **Lyria response includes lyrics text alongside audio.** The script extracts only the `inlineData.data` field. The text part (lyrics, song structure) is discarded — if the user wants lyrics, that's a second turn against a chat model.
- **Long input text (TTS).** OpenAI TTS limits input to ~4096 chars per request; Gemini TTS has its own limit. For long passages, split by paragraph and concatenate — but only do this if the user asks; otherwise let the API return its error.
- **Special characters.** Quotes, newlines, apostrophes are escaped automatically.
- **`config.yaml` missing or unreadable / `providers.<name>.api_key` empty.** Script exits non-zero. Don't silently fall back to another provider.
- **`base_url` set to a custom proxy.** The script appends the standard path (e.g. `/v1/audio/speech`, `/v1beta/models/...`) to whatever `base_url` is set, after stripping any trailing slash. If the proxy uses a different path layout, the request will fail.
- **Output path's parent directory doesn't exist.** Create the parent first if the user asked for a nested path.
- **Gemini TTS output is always WAV/PCM.** If the user wants MP3 from Gemini TTS, that requires `ffmpeg`. Lyria itself returns MP3/WAV directly, so no transcoding needed for music.
- **SynthID watermark on Lyria.** All Lyria-generated audio carries an inaudible SynthID watermark. Mention this if the user is producing for distribution where provenance matters.

## Files

- `scripts/generate.sh` — orchestrator
- `scripts/openai_tts.sh` — OpenAI text-to-speech
- `scripts/gemini_tts.sh` — Gemini text-to-speech (PCM → WAV)
- `scripts/gemini_music.sh` — Google Lyria 3 music generation
- `scripts/parse_yaml.sh` — YAML helpers
