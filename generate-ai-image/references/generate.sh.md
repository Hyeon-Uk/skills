# generate.sh (generate-ai-image)
**Description**: Entry point script for AI image generation. Reads `/home/owner/.carbon/config.yaml`, picks the provider from `defaults.provider`, and dispatches to the appropriate provider script.
**Depends on**: `curl` — for HTTP requests to OpenAI/Gemini APIs.

## Usage

```bash
bash generate.sh "<prompt>" [OPTIONS]
```

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `--model NAME` | per-provider default | Override the default image model |
| `--quality LEVEL` | HD-equivalent | Quality level (hd, high, low, medium, standard) |
| `--output PATH` | `./image_<timestamp>.png` | Output file path |
| `--size WxH` | `1024x1024` | Image dimensions |
| `-h`, `--help` | | Show help message |

## Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success — outputs absolute path of saved image |
| `1` | Usage error, config missing, or API failure |
| `2` | Active provider is `anthropic` (no image API) |

## Default Models

| Provider | Default Model |
|----------|---------------|
| `openai` | `gpt-image-1` |
| `gemini` | `imagen-4.0-generate-001` |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CARBON_CONFIG` | `/home/owner/.carbon/config.yaml` | Path to config file |

## Examples

```bash
# Basic usage
bash generate.sh "a sunset over mountains"

# Custom model and size
bash generate.sh "cyberpunk city" --model dall-e-3 --size 1536x1024

# Custom output path
bash generate.sh "logo design" --output /tmp/logo.png

# Lower quality
bash generate.sh "quick sketch" --quality low
```

## Related Scripts

- `openai_generate.sh` — OpenAI implementation
- `gemini_generate.sh` — Gemini/Imagen implementation
- `parse_yaml.sh` — YAML parsing utilities