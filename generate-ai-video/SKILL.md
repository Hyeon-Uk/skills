---
name: generate-ai-video
description: Generates an MP4 video from a text prompt (and optionally a seed image) using Google Veo via the Gemini API (predictLongRunning + polling). Default model veo-3.0-generate-preview produces video with audio; veo-2.0-generate-001 produces video only. Supports image-to-video via --image PATH (PNG/JPEG/WebP), which Veo uses as the starting frame / reference. Reads providers.gemini.api_key from /home/owner/.carbon/config.yaml. Pure shell + curl, no Python/Node or ffmpeg required. Trigger when user asks to create, make, generate, or render a video, short film, animated clip, image-to-video, animate-this-photo, or any AI-generated video content. Always report the final video path and the model used.
argument-hint: "[--model veo-3|veo-2] [--aspect 16:9|9:16|1:1] [--duration SECS] [--output PATH] [--image PATH]"
user-invocable: true
allowed-tools: true
---

# generate-ai-video

Generates an MP4 video from a text prompt by calling the **Google Veo API** via `predictLongRunning`, polling until the operation completes, then saving the result.

**Prerequisite:** `providers.gemini.api_key` must be set in `/home/owner/.carbon/config.yaml`.

## Intent-Based Workflow

| User says | Script | Example |
|---|---|---|
| "Generate a video of waves crashing on shore" | `generate.sh` | `bash generate.sh "waves crashing on shore"` |
| "Make a short vertical clip for a reel" | `generate.sh --aspect` | `bash generate.sh "prompt" --aspect 9:16` |
| "Create a video without audio" | `generate.sh --model` | `bash generate.sh "prompt" --model veo-2` |
| "Save to /tmp/clip.mp4" | `generate.sh --output` | `bash generate.sh "prompt" --output /tmp/clip.mp4` |
| "Animate this photo of a sunset" | `generate.sh --image` | `bash generate.sh "gentle waves, slow zoom" --image ./sunset.jpg` |

**Always tell the user the final video path and which model was used.**

## CLI Usage

```bash
bash <skill-dir>/scripts/generate.sh "<prompt>" [OPTIONS]
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--model veo-3\|veo-2` | `veo-3` | Model: `veo-3` = video+audio (veo-3.0-generate-preview), `veo-2` = video only (veo-2.0-generate-001) |
| `--aspect RATIO` | `16:9` | Aspect ratio: `16:9`, `9:16`, `1:1`, `4:3`, `3:4` |
| `--duration SECS` | `8` | Video length in seconds (model-dependent; Veo 2: 5 or 8). Veo requires `8` when `--image` is set. |
| `--output PATH` | `./video_<timestamp>.mp4` | Output file path |
| `--image PATH` | (none) | Path to a seed image (PNG/JPEG/WebP). When set, the file is base64-encoded and sent as `instances[0].image.inlineData`; Veo uses it as the starting frame / reference. |
| `-h`, `--help` | | Show usage |

### Pinned Models

| `--model` | Model ID | Audio |
|---|---|---|
| `veo-3` (default) | `veo-3.0-generate-preview` | Yes (native) |
| `veo-2` | `veo-2.0-generate-001` | No |

### API Flow

1. `POST .../models/<model>:predictLongRunning` → returns `{"name": "operations/..."}`
2. `GET .../operations/<id>` every 10s until `"done": true` (max 10 min)
3. Extract video — inline base64 `"data"` field or download from `"uri"`
4. Save to output path

## Output

### Success

```
Starting video generation (model=veo-3.0-generate-preview)…
Operation started: operations/abc123
Polling (1/60)…
Polling (2/60)…
...
Video saved to: ./video_20260512_194900.mp4 (model=veo-3.0-generate-preview)
./video_20260512_194900.mp4
```

### Error

| Error | Description | Recovery |
|-------|-------------|----------|
| `providers.gemini.api_key not found` | API key missing | Add `providers.gemini.api_key` to config |
| `HTTP 403` | Key lacks Veo access | Enable Veo API or use a key with Veo access |
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
| `--duration` not supported by model | API returns 400; remove `--duration` and retry |
| Veo 3 only available in preview regions | HTTP 403 or 404; switch to `--model veo-2` |
| `--image` file unreadable / unknown extension | Caller error; fix path or convert to .png/.jpg/.webp |
| `--image` set but `--duration` != 8 | API returns 400 (Veo requires 8s with reference images); drop `--duration` to use default |

## Files

- `scripts/generate.sh` — orchestrator (arg parsing + dispatch)
- `scripts/gemini_veo.sh` — Veo API: start operation, poll, save video
- `scripts/parse_yaml.sh` — YAML helpers (reads config.yaml)
