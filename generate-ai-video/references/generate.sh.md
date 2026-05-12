# generate.sh (generate-ai-video)

**Description**: Entry point for AI video generation. Parses CLI args and dispatches to `gemini_veo.sh`, which calls Google Veo 3.1 (`veo-3.1-generate-preview`).

**Depends on**: `curl`, `base64`

## Usage

```bash
bash generate.sh "<prompt>" [OPTIONS]
```

## Options

| Option | Default | Allowed values | Description |
|--------|---------|----------------|-------------|
| `--aspect RATIO` | `16:9` | `16:9`, `9:16` | Veo 3.1 supports landscape and portrait only |
| `--resolution RES` | `720p` | `720p`, `1080p`, `4k` | `1080p`/`4k` require `--duration 8` |
| `--duration SECS` | `8` | `4`, `6`, `8` | Sent to the API as a string |
| `--output PATH` | `./video_<timestamp>.mp4` | path | Output file path |
| `--image PATH` | (none) | `.png`/`.jpg`/`.webp` | Seed image — base64-encoded and sent as `instances[0].image.inlineData` for image-to-video |
| `-h`, `--help` |  |  | Show usage |

There is no `--model` option — Veo 3.1 is pinned in `gemini_veo.sh`.

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

- `gemini_veo.sh` — Veo 3.1 API: predictLongRunning + polling + video extraction
- `parse_yaml.sh` — YAML parsing utilities
