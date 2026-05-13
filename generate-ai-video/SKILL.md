---
name: generate-ai-video
description: Generates an MP4 video (with native audio — dialogue, SFX, ambience) from a text prompt and optionally a seed image, using Google Veo 3.1 (veo-3.1-generate-preview) via the Gemini API (predictLongRunning + polling). Supports image-to-video via --image PATH (PNG/JPEG/WebP), which Veo uses as a reference asset frame. Reads providers.gemini.api_key from {agent_config_path}/config.yaml. Pure shell + curl — no Python, Node, or ffmpeg required. Trigger when the user asks to create, make, generate, or render a video, short film, animated clip, image-to-video, animate-this-photo, talking-character clip, or any AI-generated video content. Always report the final video path.
argument-hint: "[--aspect 16:9|9:16] [--resolution 720p|1080p|4k] [--output PATH] [--image PATH]"
user-invocable: true
allowed-tools: true
---

# generate-ai-video

Generates an MP4 video (with native audio) from a text prompt by calling the **Google Veo 3.1 API** (`veo-3.1-generate-preview`) via Gemini `predictLongRunning`, polling until the operation completes, then saving the result.

**Prerequisite:** `providers.gemini.api_key` must be set in `{agent_config_path}/config.yaml`.

## Intent-Based Workflow

| User says | Script | Example |
|---|---|---|
| "Generate a video of waves crashing on shore" | `generate.sh` | `bash generate.sh "waves crashing on shore"` |
| "Make a short vertical clip for a reel" | `generate.sh --aspect` | `bash generate.sh "prompt" --aspect 9:16` |
| "I want it in 1080p" | `generate.sh --resolution` | `bash generate.sh "prompt" --resolution 1080p` |
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
| `--aspect RATIO` | API default (`16:9`) | `16:9`, `9:16` | Sent as `parameters.aspectRatio` when provided. |
| `--resolution RES` | API default (`720p`) | `720p`, `1080p`, `4k` | Sent as `parameters.resolution` when provided. |
| `--output PATH` | `./video_<timestamp>.mp4` | path | Output file path. |
| `--image PATH` | (none) | `.png` / `.jpg` / `.webp` | Reference image. Base64-encoded and sent inside `instances[0].referenceImages[]` with `referenceType: "asset"`. |
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

### Request Body (Veo 3.1)

Plain text-to-video (no options set) — minimal body, matches the reference scripts:

```json
{
  "instances": [{"prompt": "..."}]
}
```

With `--aspect` and/or `--resolution`:

```json
{
  "instances": [{"prompt": "..."}],
  "parameters": {
    "aspectRatio": "9:16",
    "resolution": "1080p"
  }
}
```

With `--image` (image-to-video):

```json
{
  "instances": [{
    "prompt": "...",
    "referenceImages": [
      {
        "image": {"bytesBase64Encoded": "<base64>", "mimeType": "image/png"},
        "referenceType": "asset"
      }
    ]
  }]
}
```

> **Note on wire format:** the public Veo REST docs show `image.inlineData.{mimeType,data}` for reference images, but `predictLongRunning` actually rejects that shape with `"inlineData" isn't supported by this model`. Veo uses the Vertex-AI image shape (`bytesBase64Encoded` + `mimeType` directly on `image`); the official `google-genai` SDK does the same. Don't "fix" this back to `inlineData`.

The `parameters` block is omitted when the user doesn't override defaults — this matches the reference scripts and avoids sending redundant fields.

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
| `HTTP 400` w/ personGeneration | Region (EU/UK/CH/MENA) restricts person generation | Reword the prompt to avoid recognizable people |
| `timed out waiting` | Generation exceeded 10 min | Retry or simplify the prompt |
| `blocked by safety filter: ...` | RAI rejected the prompt or reference image (e.g. celebrity likeness, violence) | Reword the prompt or swap out the reference image |
| `could not extract video` | Unexpected response format (no `data`/`uri`/`raiMediaFilteredReasons`) | Check raw response in stderr |

## Config Schema

`{agent_config_path}/config.yaml`:

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
| Response has `"uri"` instead of `"data"` | Downloaded via curl with API key header (follows redirects) |
| `--image` file unreadable / unknown extension | Caller error; fix path or convert to .png/.jpg/.webp |
| `--aspect` other than `16:9`/`9:16` | Veo 3.1 does not support 1:1, 4:3, or 3:4 — API returns 400 |
| Generated videos are stored server-side for 2 days | Download promptly; URI is short-lived |

## Files

- `scripts/generate.sh` — orchestrator (arg parsing + dispatch)
- `scripts/gemini_veo.sh` — Veo 3.1 API: start operation, poll, save video
- `scripts/parse_yaml.sh` — YAML helpers (reads config.yaml)
