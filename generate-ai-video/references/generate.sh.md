# generate.sh (generate-ai-video)

**Description**: Entry point for AI video generation. Parses CLI args and dispatches to `gemini_veo.sh`.

**Depends on**: `curl`, `base64`

## Usage

```bash
bash generate.sh "<prompt>" [OPTIONS]
```

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `--model veo-3\|veo-2` | `veo-3` | Veo model selection |
| `--aspect RATIO` | `16:9` | Aspect ratio |
| `--duration SECS` | `8` | Duration in seconds (must be `8` when `--image` is set) |
| `--output PATH` | `./video_<timestamp>.mp4` | Output file path |
| `--image PATH` | (none) | Seed image (PNG/JPEG/WebP) — base64-encoded and sent as `instances[0].image.inlineData` to drive image-to-video |
| `-h`, `--help` | | Show usage |

## Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success — stdout last line is the video path |
| `1` | Usage error, config missing, API failure, or timeout |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CARBON_CONFIG` | `/home/owner/.carbon/config.yaml` | Path to config file |

## Related Scripts

- `gemini_veo.sh` — Veo API: predictLongRunning + polling + video extraction
- `parse_yaml.sh` — YAML parsing utilities
