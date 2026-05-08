---
name: generate-ai-image
description: Generates images via OpenAI (gpt-image-1) or Google Gemini (gemini-3.1-flash-image-preview). Reads provider and API key from /home/owner/.carbon/config.yaml. Both providers are pinned to static endpoint+model — --model is accepted but ignored with a warning. Pure shell + curl, no Python/Node required. Requires providers.<active-provider>.api_key in config.yaml. Trigger when the user asks to create, generate, draw, render, or make an image; mentions gpt-image, Gemini image, or text-to-image; or references their Carbon config provider. Returns an error if defaults.provider is anthropic (Anthropic has no image API).
argument-hint: "[--model NAME] [--quality LEVEL] [--output PATH] [--size WxH]"
user-invocable: true
allowed-tools: true
---

# generate-ai-image

Generates an image from a text prompt using whichever provider is active in `/home/owner/.carbon/config.yaml`.

**Prerequisite:** The active provider's API key MUST exist in `config.yaml`:
- `defaults.provider: openai` → `providers.openai.api_key` must be a valid OpenAI key (`sk-...`)
- `defaults.provider: gemini` → `providers.gemini.api_key` must be a valid Google AI Studio key (`AIza...`)

If the key is missing or empty, the provider script exits non-zero with a message naming the missing field and the path of the config file. Do not retry — ask the user to set the key first. The skill never falls back to another provider's key.

## Intent-Based Workflow

| User says | Script | Example |
|---|---|---|
| "Generate an image of a sunset over mountains" | `generate.sh` | `bash generate.sh "sunset over mountains"` |
| "Draw a logo for my coffee shop" | `generate.sh` | `bash generate.sh "coffee shop logo"` |
| "Create a 16:9 banner of a futuristic city" | `generate.sh --size` | `bash generate.sh "futuristic city" --size 1536x1024` |
| "Use DALL-E 3 to make a watercolor of a cat" | `generate.sh --model` | `bash generate.sh "watercolor cat" --model dall-e-3` |
| "Save the image to /tmp/banner.png" | `generate.sh --output` | `bash generate.sh "prompt" --output /tmp/banner.png` |

**When to use `--quality`:**
- **Default (no flag)**: HD-equivalent (`high` for gpt-image-1)
- **OpenAI/`gpt-image-1`** accepts: `low | medium | high | auto`. Aliases `hd`→`high`, `standard`→`medium` are mapped automatically.
- **Gemini**: `--quality` is accepted but ignored — the pinned model has no quality knob

## CLI Usage

```bash
bash <skill-dir>/scripts/generate.sh "<prompt>" [OPTIONS]
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--model NAME` | (pinned per provider) | Accepted but ignored with a warning |
| `--quality LEVEL` | `high` (gpt-image-1) | Quality level — see "When to use `--quality`" above |
| `--output PATH` | `./image_<timestamp>.png` | Output file path |
| `--size WxH` | `1024x1024` | Image dimensions |
| `-h`, `--help` | | Show help message |

### Pinned Models per Provider

| `defaults.provider` | Model (pinned at static endpoint) | `--model` override? |
|---|---|---|
| `openai` | `gpt-image-1` | no — ignored with a warning |
| `gemini` | `gemini-3.1-flash-image-preview` | no — ignored with a warning |
| `anthropic` | (rejected — no image API) | n/a |

### Size Options by Provider

**OpenAI:** `1024x1024`, `1024x1536`, `1536x1024`, `auto`
**Gemini:** Converted to aspect ratio automatically (1:1, 16:9, 4:3, 9:16, 3:4)

## Output

### Success

The script outputs the absolute path of the saved image on stdout:

```
/tmp/image_20260325_143025.png
```

### Error

Error messages are written to stderr. Common errors:

| Error | Description | Recovery Action |
|-------|-------------|-----------------|
| `cannot read config` | `config.yaml` missing or unreadable | Create config file at `/home/owner/.carbon/config.yaml` |
| `defaults.provider missing` | No provider configured | Add `defaults.provider: openai\|gemini` to config |
| `api_key missing` | Provider key not set | Add `providers.<name>.api_key` to config |
| `provider 'anthropic' does not support image` | Anthropic has no image API | Switch to `openai` or `gemini` in config |
| `API error` | Invalid key, rate limit, or API failure | Check key validity, wait and retry |

## Config Schema

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
    api_key: "sk-ant-..."   # not used (anthropic has no image API)
```

The skill reads:
- `defaults.provider` — for routing
- `providers.<defaults.provider>.api_key` — for auth (mandatory)

It deliberately **does not** read `defaults.model` (that's the chat tier in carbon's normal flow) and it deliberately **does not** read any `base_url` field — each provider script targets that provider's official endpoint only.

## Provider Routing

| `defaults.provider` | Behavior |
|---|---|
| `openai` | dispatch to `openai_generate.sh`; static endpoint+model `gpt-image-1` |
| `gemini` | dispatch to `gemini_generate.sh`; static endpoint+model `gemini-3.1-flash-image-preview` |
| `anthropic` | exit code 2 with error message — Anthropic does not provide an image generation API |

## Edge Cases

| Case | Handling |
|------|----------|
| Prompt contains quotes or newlines | Pass as single argument; scripts JSON-escape internally |
| `config.yaml` missing | Exit non-zero with path tried |
| `providers.<name>.api_key` empty | Exit non-zero with field name |
| `--model` doesn't match provider | API will reject; suggest fixing one or the other |
| Output path's parent directory doesn't exist | Script fails when writing; create directory first |
| Custom proxy / gateway | Not supported; scripts hit official endpoints only |

## Examples

```bash
# Basic usage with default model
bash generate.sh "a serene mountain landscape at sunset"

# --model is accepted but ignored (model is pinned per-provider)
bash generate.sh "cyberpunk city"

# Custom size and output path
bash generate.sh "panoramic ocean view" --size 1536x1024 --output /tmp/panorama.png

# Lower quality to save credits
bash generate.sh "quick sketch of a cat" --quality low

# Use Gemini (pinned to gemini-3.1-flash-image-preview; --model is ignored)
# First set defaults.provider: gemini in config.yaml
bash generate.sh "abstract art in blue tones"
```

## Files

- `scripts/generate.sh` — orchestrator
- `scripts/openai_generate.sh` — OpenAI image implementation (static endpoint + model)
- `scripts/gemini_generate.sh` — Gemini image implementation (static endpoint + model)
- `scripts/parse_yaml.sh` — YAML helpers (sourced by the others)