# generate.sh (generate-ai-video)

**Description**: Orchestrator for AI video generation. Calls `gemini_image.sh` → `gemini_music.sh` → `combine.sh` in sequence, then prints the final MP4 path to stdout.

**Depends on**: `curl`, `ffmpeg`, `base64`

## Usage

```bash
bash generate.sh "<prompt>" [OPTIONS]
```

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `--length clip\|full` | `clip` | Music duration: `clip` ~30s, `full` multi-minute |
| `--size WxH` | `1024x1024` | Image dimensions (mapped to Gemini aspect ratio) |
| `--output PATH` | `./video_<timestamp>.mp4` | Final video output path |
| `--image-output PATH` | `./image_<timestamp>.png` | Intermediate image path |
| `--audio-output PATH` | `./audio_<timestamp>.mp3` | Intermediate audio path |
| `-h`, `--help` | | Show usage |

## Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success — stdout last line is the video path |
| `1` | Usage error, config missing, API failure, or ffmpeg error |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CARBON_CONFIG` | `/home/owner/.carbon/config.yaml` | Path to config file |

## Related Scripts

- `gemini_image.sh` — Gemini image generation (gemini-3.1-flash-image-preview)
- `gemini_music.sh` — Lyria 3 music generation
- `combine.sh` — ffmpeg combiner
- `parse_yaml.sh` — YAML parsing utilities
