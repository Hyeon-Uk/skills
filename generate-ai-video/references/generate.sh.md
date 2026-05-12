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
| `--aspect RATIO` | API default (`16:9`) | `16:9`, `9:16` | Sent as `parameters.aspectRatio` when provided |
| `--resolution RES` | API default (`720p`) | `720p`, `1080p`, `4k` | Sent as `parameters.resolution` when provided |
| `--output PATH` | `./video_<timestamp>.mp4` | path | Output file path |
| `--image PATH` | (none) | `.png`/`.jpg`/`.webp` | Reference image — base64-encoded and sent inside `instances[0].referenceImages[]` with `referenceType: "asset"` |
| `-h`, `--help` |  |  | Show usage |

There is no `--model` option — Veo 3.1 is pinned in `gemini_veo.sh`.

When `--aspect` and `--resolution` are both omitted, the `parameters` object is omitted from the request body (matches the reference scripts).

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
