---
name: generate-ai-video
description: Generates an MP4 video (with native audio — dialogue, SFX, ambience) from a text prompt and optionally a seed image, using Google Veo 3.1 (veo-3.1-generate-preview) via the Gemini API (predictLongRunning + polling). Supports image-to-video via --image PATH (PNG/JPEG/WebP), which Veo uses as the starting frame. Reads providers.gemini.api_key from /home/owner/.carbon/config.yaml. Pure shell + curl — no Python, Node, or ffmpeg required. Trigger when the user asks to create, make, generate, or render a video, short film, animated clip, image-to-video, animate-this-photo, talking-character clip, or any AI-generated video content. Always report the final video path.
argument-hint: "[--aspect 16:9|9:16] [--resolution 720p|1080p|4k] [--duration 4|6|8] [--output PATH] [--image PATH]"
user-invocable: true
allowed-tools: true
---

# generate-ai-video

Generates an MP4 video (with native audio) from a text prompt by calling the **Google Veo 3.1 API** (`veo-3.1-generate-preview`) via Gemini `predictLongRunning`, polling until the operation completes, then saving the result.

**Prerequisite:** `providers.gemini.api_key` must be set in `/home/owner/.carbon/config.yaml`.

## Intent-Based Workflow

| User says | Script | Example |
|---|---|---|
| "Generate a video of waves crashing on shore" | `generate.sh` | `bash generate.sh "waves crashing on shore"` |
| "Make a short vertical clip for a reel" | `generate.sh --aspect` | `bash generate.sh "prompt" --aspect 9:16` |
| "I want it in 1080p" | `generate.sh --resolution` | `bash generate.sh "prompt" --resolution 1080p` |
| "Just 4 seconds is fine" | `generate.sh --duration` | `bash generate.sh "prompt" --duration 4` |
| "Save to /tmp/clip.mp4" | `generate.sh --output` | `bash generate.sh "prompt" --output /tmp/clip.mp4` |
| "Animate this photo of a sunset" | `generate.sh --image` | `bash generate.sh "gentle waves, slow zoom" --image ./sunset.jpg` |

**Always tell the user the final video path.** The model (`veo-3.1-generate-preview`) is pinned — there is no model option.

## CLI Usage

```bash
bash <skill-dir>/scripts/generate.sh "<prompt>" [OPTIONS]
```

### Options

| Option | Default | Allowed values | Description |
|--------|---------|----------------|-------------|
| `--aspect RATIO` | `16:9` | `16:9`, `9:16` | Veo 3.1 supports landscape and portrait only. |
| `--resolution RES` | `720p` | `720p`, `1080p`, `4k` | `1080p` and `4k` require `--duration 8`. |
| `--duration SECS` | `8` | `4`, `6`, `8` | Sent as a string. Use `8` for the highest fidelity, for `1080p`/`4k`, or when `--image` is set. |
| `--output PATH` | `./video_<timestamp>.mp4` | path | Output file path. |
| `--image PATH` | (none) | `.png` / `.jpg` / `.webp` | Seed image, base64-encoded into `instances[0].image.inlineData`. Veo uses it as the starting frame. |
| `-h`, `--help` |  |  | Show usage. |

### Pinned Model

| Model ID | Audio | Notes |
|---|---|---|
| `veo-3.1-generate-preview` | Native (dialogue, SFX, ambience) | The only Veo model this skill calls. To use a different Veo variant, edit `scripts/gemini_veo.sh`. |

Audio is generated natively from the prompt — include speech in quotes (e.g. `she whispers "we made it"`) and ambient cues directly in the prompt.

### API Flow

1. `POST .../models/veo-3.1-generate-preview:predictLongRunning` → returns `{"name": "operations/..."}`
2. `GET .../operations/<id>` every 10s until `"done": true` (max 10 min)
3. Extract video — inline base64 `"data"` field or download from `"uri"`
4. Save to output path

### Request Parameters (Veo 3.1)

The script sends:

```json
{
  "instances": [{"prompt": "...", "image": { ... optional ... }}],
  "parameters": {
    "aspectRatio": "16:9",
    "resolution": "720p",
    "sampleCount": 1,
    "durationSeconds": "8"
  }
}
```

`durationSeconds` is a **string** in Veo 3.1, not an integer.

## Output

### Success

```
Starting video generation (model=veo-3.1-generate-preview)…
Operation started: operations/abc123
Polling (1/60)…
Polling (2/60)…
...
Video saved to: ./video_20260512_194900.mp4 (model=veo-3.1-generate-preview)
./video_20260512_194900.mp4
```

### Error

| Error | Description | Recovery |
|-------|-------------|----------|
| `providers.gemini.api_key not found` | API key missing | Add `providers.gemini.api_key` to config |
| `HTTP 403` | Key lacks Veo access | Enable Veo on the project or use a key with Veo access |
| `HTTP 400` w/ resolution + duration | `1080p`/`4k` requested with duration < 8 | Use `--duration 8` |
| `HTTP 400` w/ personGeneration | Region (EU/UK/CH/MENA) restricts person generation | Reword the prompt to avoid recognizable people |
| `timed out waiting` | Generation exceeded 10 min | Retry or simplify the prompt |
| `could not extract video` | Unexpected response format | Check raw response in stderr |

## Config Schema

`/home/owner/.carbon/config.yaml`:

```yaml
version: 1
defaults:
  provider: gemini
providers:
  gemini:
    api_key: "AIza-..."   # REQUIRED
```

## Edge Cases

| Case | Handling |
|------|----------|
| Response has inline base64 `"data"` | Decoded directly to output file |
| Response has `"uri"` instead of `"data"` | Downloaded via curl with API key header |
| `--resolution 1080p` or `4k` with `--duration` < 8 | API returns 400; use default `--duration 8` |
| `--image` set with `--duration` ≠ 8 | API may return 400; drop `--duration` to use default 8 |
| `--image` file unreadable / unknown extension | Caller error; fix path or convert to .png/.jpg/.webp |
| `--aspect` other than `16:9`/`9:16` | Veo 3.1 does not support 1:1, 4:3, or 3:4 — API returns 400 |
| Generated videos are stored server-side for 2 days | Download promptly; URI is short-lived |

## Files

- `scripts/generate.sh` — orchestrator (arg parsing + dispatch)
- `scripts/gemini_veo.sh` — Veo 3.1 API: start operation, poll, save video
- `scripts/parse_yaml.sh` — YAML helpers (reads config.yaml)
