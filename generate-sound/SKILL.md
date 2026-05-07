---
name: generate-sound
description: Generates audio from text — music (Google Gemini Lyria 3) or speech (OpenAI TTS, Gemini TTS). Reads API keys from `/home/owner/.carbon/config.yaml`. Provider is chosen by request type: music always routes to gemini (only Lyria supports music); speech prefers `defaults.provider` but auto-falls back to gemini or openai if the active provider is `anthropic`. Accepts `--model` to override the default model. Pure shell + curl, no Python/Node required. Trigger when the user asks to compose music, generate a song/jingle/tune/backing track, read text aloud, narrate, generate a voiceover, or synthesize speech. Always tell the user which provider was selected.
---

# generate-sound

Generates an audio file from a text input — either a music clip or spoken speech — choosing the **most appropriate provider for the request**, regardless of `defaults.provider` in `/home/owner/.carbon/config.yaml`.

## Prerequisite — API key must be configured

The skill picks the provider based on the request type, so the required key depends on what the user asked for:

- **Music** requests always use `gemini` → `providers.gemini.api_key` must be a valid Google AI Studio key (`AIza...`)
- **Speech** requests use `defaults.provider`; if that's `anthropic`, the skill falls back to `gemini` first, then `openai`

Have both `providers.openai.api_key` and `providers.gemini.api_key` set for full coverage. If the required key is missing or empty, the provider script exits non-zero with a message naming the missing field. Do not retry — ask the user to set the key first.

## Provider selection — smart routing by request type

The carbon config's `defaults.provider` is a chat-tier setting, not an audio setting. This skill overrides it when the request type demands a specific provider:

| Request type | Provider used | Reason |
|---|---|---|
| `--mode music` | always `gemini` | Only Gemini/Lyria supports music generation; OpenAI has no music API |
| `--mode speech` + `defaults.provider: openai` | `openai` | Honored as configured |
| `--mode speech` + `defaults.provider: gemini` | `gemini` | Honored as configured |
| `--mode speech` + `defaults.provider: anthropic` | `gemini` → `openai` fallback | Anthropic has no audio API; fall back automatically |

**Always tell the user which provider was selected** and why, especially when it differs from `defaults.provider`.

The skill picks a sensible model per (provider, mode) when the user doesn't pass `--model`:

| Provider | `--mode speech` default | `--mode music` default |
|---|---|---|
| `openai` | `tts-1-hd` | N/A |
| `gemini` | `gemini-2.5-flash-preview-tts` | `lyria-3-pro-preview` |

If the user clearly wants music ("compose a song", "make a backing track", "generate a 30-second jingle"), pass `--mode music`. Otherwise default mode (speech) is correct.

## When to use this skill

Trigger on any user request that boils down to "produce an audio file from this text". Examples:
- **Music**: "Generate a 30-second cheerful acoustic folk tune with guitar and harmonica" / "Compose a tense cinematic cue for the chase scene" / "Make a jingle for my podcast intro"
- **Speech**: "Read this paragraph aloud and save it as narration.mp3" / "Generate a voiceover for the intro of my video" / "Use a calm female voice to narrate this script"

If the user names a provider explicitly ("use OpenAI for this"), honor that request — but if it can't fulfill the mode (e.g. "use OpenAI" + music), explain why and switch to the capable provider instead.

This skill does **not** do speech-to-text (transcription).

## How it works

Five files in `scripts/`:

- `generate.sh` — entry point. Determines the effective provider via smart routing (see above), picks the (mode × provider) handler, picks a default model if `--model` wasn't given.
- `openai_tts.sh` — calls `https://api.openai.com/v1/audio/speech` (endpoint hardcoded; no override). Response is binary audio, written straight to disk.
- `gemini_tts.sh` — calls `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent` (endpoint hardcoded; no override) with `responseModalities: ["AUDIO"]`. Response is base64 24 kHz / 16-bit / mono PCM; the script prepends a 44-byte WAV header so the file plays in standard players.
- `gemini_music.sh` — calls `https://generativelanguage.googleapis.com/v1beta/models/lyria-3-*-preview:generateContent` (endpoint hardcoded; no override). Response is base64 MP3 (Clip and Pro) or WAV (Pro only); the script just decodes — no header wrapping needed because Lyria already emits a complete container.
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
| `--format FMT` | HD-equivalent for the active model (see below) | both | OpenAI TTS: `mp3 \| opus \| aac \| flac \| wav \| pcm`. Gemini TTS: `wav` or `pcm`. Lyria (both Clip and Pro): `mp3` only — see "Lyria WAV limitation" below. |
| `--speed N` | `1.0` | OpenAI TTS only | Range 0.25–4.0. Gemini TTS uses prompt phrasing; Lyria has no speed knob. |
| `--output PATH` | `./audio_<YYYYmmdd_HHMMSS>.<ext>` in cwd | both | Extension is inferred from `--format`. |
| `--input-file PATH` | (positional text used) | TTS — long passages | Read text from a file. |

### HD quality default — IMPORTANT

If the user did **not** mention audio quality, do **not** pass `--format`. The script falls back to:

- TTS (OpenAI / Gemini) → `wav` (lossless)
- Lyria (Clip and Pro) → `mp3` (see "Lyria WAV limitation" below)

Pass `--format mp3` only when the user explicitly opts out of HD ("a quick draft is fine", "low quality is OK", "save space"). HD is the default for TTS precisely because users assume the best version unless they opt out.

### Lyria WAV limitation

The official docs (`ai.google.dev/gemini-api/docs/music-generation`) say WAV output is selected by setting `responseMimeType: "audio/wav"` in `generationConfig`. In practice the live `:generateContent` endpoint **rejects** that field with HTTP 400 ("`response_mime_type`: allowed mimetypes are `text/plain`, `application/json`, …"). Until Google reconciles this, Lyria via the Gemini API emits MP3 only.

If the user passes `--format wav` for music mode, the script exits non-zero with a clear message rather than silently saving an MP3 with a `.wav` extension. WAV-quality Lyria is available through Vertex AI's `lyria-002` model (`:predict` endpoint, `instances`/`parameters` shape) — that's a different API and not handled by this skill.

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
    api_key: "sk-..."       # REQUIRED — skill refuses to run without it
  gemini:
    api_key: "AIza-..."     # REQUIRED — skill refuses to run without it
  anthropic:
    api_key: "sk-ant-..."   # not used (anthropic has no audio API)
```

The skill reads `defaults.provider` and `providers.<defaults.provider>.api_key`. It deliberately **does not** read `defaults.model` (that's the chat tier in carbon's normal flow) and it deliberately **does not** read any `base_url` field — each provider script targets that provider's official endpoint and that endpoint only.

## Provider routing

Routing now ignores `defaults.provider` for music and applies automatic fallback for speech when `anthropic` is set:

| `--mode` | effective provider | Outcome |
|---|---|---|
| `music` | always `gemini` | dispatch to `gemini_music.sh`, default model `lyria-3-pro-preview` |
| `speech` | `openai` (if configured) | dispatch to `openai_tts.sh`, default model `tts-1-hd` |
| `speech` | `gemini` (if configured) | dispatch to `gemini_tts.sh`, default model `gemini-2.5-flash-preview-tts` |
| `speech` | `anthropic` → fallback `gemini` | auto-switch; tell user "anthropic has no audio API, using gemini" |
| `speech` | `anthropic` → no gemini key → fallback `openai` | auto-switch; tell user which fallback was used |

## Reporting back to the user

After success, tell the user:
1. The **effective provider** chosen (especially if it differs from `defaults.provider`)
2. The absolute path of the saved file
3. The model used
4. The chosen voice (TTS only)

If the script failed, surface its stderr verbatim. The most common failures (missing key, bad voice name) require a config change — don't retry blindly.

## Edge cases worth knowing

- **Lyria response includes lyrics text alongside audio.** The script extracts only the `inlineData.data` field. The text part (lyrics, song structure) is discarded — if the user wants lyrics, that's a second turn against a chat model.
- **Lyria copyright filter (`finishReason: OTHER`).** Lyria sometimes returns 200 OK with no audio and `finishReason: "OTHER"` plus a `finishMessage` saying the prompt looked too close to existing copyrighted material. The script detects this and surfaces the message verbatim with a hint to rephrase. Tell the user to describe the mood/instruments/tempo abstractly, not by reference to specific songs or artists.
- **Long input text (TTS).** OpenAI TTS limits input to ~4096 chars per request; Gemini TTS has its own limit. For long passages, split by paragraph and concatenate — but only do this if the user asks; otherwise let the API return its error.
- **Special characters.** Quotes, newlines, apostrophes are escaped automatically.
- **`config.yaml` missing or unreadable / `providers.<name>.api_key` empty.** Script exits non-zero with the missing field name. This is the single most common failure — surface the message verbatim and stop. Don't silently fall back to another provider.
- **Custom proxy / gateway.** Not supported. Each provider script hits the official endpoint (`api.openai.com`, `generativelanguage.googleapis.com`) and ignores any `base_url` field in `config.yaml`. If the user needs a proxy, they have to fork the script and change the URL.
- **Output path's parent directory doesn't exist.** Create the parent first if the user asked for a nested path.
- **Gemini TTS output is always WAV/PCM.** If the user wants MP3 from Gemini TTS, that requires `ffmpeg`. Lyria itself returns MP3/WAV directly, so no transcoding needed for music.
- **SynthID watermark on Lyria.** All Lyria-generated audio carries an inaudible SynthID watermark. Mention this if the user is producing for distribution where provenance matters.

## Files

- `scripts/generate.sh` — orchestrator
- `scripts/openai_tts.sh` — OpenAI text-to-speech
- `scripts/gemini_tts.sh` — Gemini text-to-speech (PCM → WAV)
- `scripts/gemini_music.sh` — Google Lyria 3 music generation
- `scripts/parse_yaml.sh` — YAML helpers
