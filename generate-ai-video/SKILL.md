---
name: generate-ai-video
description: Generates an MP4 video by combining a Gemini-generated image (gemini-3.1-flash-image-preview) and Gemini-generated music (Lyria 3: lyria-3-pro-preview for --length full, lyria-3-clip-preview for --length clip) from a single text prompt. Merges via ffmpeg (-loop 1 static image over audio). Reads providers.gemini.api_key from /home/owner/.carbon/config.yaml. Requires ffmpeg. Pure shell + curl, no Python/Node required. Trigger when user asks to create, make, generate, or render a video, short film, animated clip, visual+audio combination, or slideshow with music. Always report image path, audio path, and final video path.
argument-hint: "[--length clip|full] [--size WxH] [--output PATH]"
user-invocable: true
allowed-tools: true
---

# generate-ai-video

Generates an MP4 video from a text prompt by:
1. Creating an image via Gemini (`gemini-3.1-flash-image-preview`)
2. Composing background music via Gemini Lyria 3
3. Merging both into an MP4 with `ffmpeg` (static image over audio track)

**Prerequisite:** `providers.gemini.api_key` must be set in `/home/owner/.carbon/config.yaml`, and `ffmpeg` must be installed.

## Intent-Based Workflow

| User says | Script | Example |
|---|---|---|
| "Make a video of a rainy city at night" | `generate.sh` | `bash generate.sh "rainy city at night"` |
| "Create a short video with a forest scene and relaxing music" | `generate.sh --length clip` | `bash generate.sh "forest" --length clip` |
| "Generate a full-length video for my product promo" | `generate.sh --length full` | `bash generate.sh "product promo" --length full` |
| "Save video to /tmp/promo.mp4" | `generate.sh --output` | `bash generate.sh "prompt" --output /tmp/promo.mp4` |

**Always tell the user all three output paths** — image, audio, and final video.

## CLI Usage

```bash
bash <skill-dir>/scripts/generate.sh "<prompt>" [OPTIONS]
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--length clip\|full` | `clip` | Music length: `clip` → ~30s (lyria-3-clip-preview), `full` → multi-minute (lyria-3-pro-preview) |
| `--size WxH` | `1024x1024` | Image dimensions (converted to Gemini aspect ratio) |
| `--output PATH` | `./video_<timestamp>.mp4` | Final video output path |
| `--image-output PATH` | `./image_<timestamp>.png` | Intermediate image path |
| `--audio-output PATH` | `./audio_<timestamp>.mp3` | Intermediate audio path |
| `-h`, `--help` | | Show usage |

### Pinned Models

| Step | Model |
|---|---|
| Image | `gemini-3.1-flash-image-preview` |
| Music (`--length clip`) | `lyria-3-clip-preview` (~30s) |
| Music (`--length full`) | `lyria-3-pro-preview` (multi-minute) |

## Output

### Success

Prints intermediate paths to stderr and the final video path to stdout:

```
Generating image…
Image: ./image_20260512_193000.jpg
Generating music…
Audio: ./audio_20260512_193000.mp3
Combining into video…
./video_20260512_193000.mp4
```

### Error

| Error | Description | Recovery |
|-------|-------------|----------|
| `ffmpeg is required but not found` | ffmpeg not in PATH | `apt-get install ffmpeg` or `brew install ffmpeg` |
| `providers.gemini.api_key not found` | API key missing | Add `providers.gemini.api_key` to config |
| `Lyria refused` | Copyright filter triggered | Rephrase prompt — describe mood/instruments/tempo |
| `ffmpeg failed` | ffmpeg codec/format error | Check image and audio files exist and are valid |

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
| Gemini returns JPEG instead of PNG | Extension auto-corrected; actual path printed |
| Lyria copyright filter | Surface finishReason; suggest rephrasing |
| Image has odd dimensions | ffmpeg `yuv420p` requires even dimensions — padded automatically |
| `--length full` produces multi-minute audio | Video length matches audio via `-shortest` |

## Files

- `scripts/generate.sh` — orchestrator (image → audio → video)
- `scripts/gemini_image.sh` — Gemini image generation
- `scripts/gemini_music.sh` — Lyria 3 music generation
- `scripts/combine.sh` — ffmpeg image+audio → MP4
- `scripts/parse_yaml.sh` — YAML helpers
