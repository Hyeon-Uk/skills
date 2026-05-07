---
name: generate-image
description: Generates images via OpenAI (DALL-E, gpt-image-1) or Google Gemini (Imagen, Gemini image models). Reads the active provider and API key from `/home/owner/.carbon/config.yaml` (`defaults.provider` + `providers.<name>.api_key`). Each provider script talks to the official endpoint for that provider — `https://api.openai.com` for OpenAI, `https://generativelanguage.googleapis.com` for Gemini — and does NOT honor a `base_url` override. Image-generation models are NOT in the carbon config — the skill picks a sensible default per provider (`gpt-image-1` for openai, `imagen-4.0-generate-001` for gemini) and accepts `--model` to override. Built for embedded Linux — pure shell + curl, no Python or Node required. **Prerequisite**: `providers.<active-provider>.api_key` MUST be set in `config.yaml` before this skill is invoked; the script exits non-zero with a clear message otherwise. Use this skill whenever the user asks to create, generate, draw, render, or make an image; whenever they mention DALL-E, Imagen, gpt-image, or text-to-image; whenever they reference the Carbon config or want to use their currently configured provider — even if they don't explicitly say "use the skill". If the active provider is `anthropic`, this skill returns a clear error explaining that Anthropic does not offer an image generation API.
---

# generate-image

Generates an image from a text prompt using whichever provider is active in `/home/owner/.carbon/config.yaml`.

## Prerequisite — API key must be configured

Before this skill can run, the active provider's API key MUST exist in `config.yaml`:

- `defaults.provider: openai` → `providers.openai.api_key` must be a valid OpenAI key (`sk-...`)
- `defaults.provider: gemini` → `providers.gemini.api_key` must be a valid Google AI Studio key (`AIza...`)

If the key is missing or empty, the provider script exits non-zero with a message naming the missing field and the path of the config file. Do not retry — ask the user to set the key first. The skill never falls back to another provider's key.

## When to use this skill

Trigger on any user request that boils down to "make me a picture of X". Examples:
- "Generate an image of a sunset over mountains"
- "Draw a logo for my coffee shop"
- "Create a 16:9 banner of a futuristic city, save it to /tmp/banner.png"
- "Use my carbon config to render a watercolor of a cat"

If the user names a provider explicitly ("use OpenAI to..."), still defer to the active `defaults.provider` in `config.yaml` — the user's setting wins. Only mention the mismatch if the active provider can't fulfill the request (e.g., active provider is `anthropic`).

## How it works

The skill is a thin wrapper around three shell scripts in `scripts/`:

- `generate.sh` — entry point. Reads the config, picks the model default for the active provider, dispatches.
- `openai_generate.sh` — calls `https://api.openai.com/v1/images/generations` (endpoint is hardcoded; no override).
- `gemini_generate.sh` — calls `https://generativelanguage.googleapis.com/v1beta/models/...` on Imagen `:predict` or Gemini `:generateContent` (endpoint is hardcoded; no override).
- `parse_yaml.sh` — minimal YAML reader (top-level + 2-level + 3-level nesting). Used because the embedded environment lacks `yq` / `python` / `node`.

All three are POSIX-friendly bash. JSON parsing uses `sed` rather than `jq` so the skill works on stripped-down embedded systems where `jq` is not installed.

## Invocation

```bash
bash <skill-dir>/scripts/generate.sh "<prompt>" [options]
```

### Options

| Flag | Default | Notes |
|---|---|---|
| `--model NAME` | per-provider default (see below) | Use this when the user names a specific image model. Image models are not in `config.yaml`; this flag is the only way to override. |
| `--quality LEVEL` | HD-equivalent for the active model | Pass through only if the user mentioned quality. See "Quality default" below. |
| `--output PATH` | `./image_<YYYYmmdd_HHMMSS>.png` in the cwd | Honor exactly what the user asked for. |
| `--size WxH` | `1024x1024` | OpenAI accepts `1024x1024`, `1024x1536`, `1536x1024`, `auto`. Imagen converts this to an aspect ratio. |

### Default models per provider

The carbon config tracks a chat-tier (`defaults.model: light`/`heavy`/...) — it does not list an image model. So this skill picks one when the user doesn't pass `--model`:

| `defaults.provider` | Default `--model` |
|---|---|
| `openai` | `gpt-image-1` |
| `gemini` | `imagen-4.0-generate-001` |
| `anthropic` | (rejected — see below) |

These defaults are HD-class models. If the user wants something cheaper/older (e.g. `dall-e-2`, `imagen-3.0-generate-002`), pass `--model <name>` explicitly.

### Quality default — IMPORTANT

If the user did **not** mention image quality, do **not** pass `--quality`. The provider script falls back to HD-equivalent for the active model:

- `dall-e-3` → `hd`
- `gpt-image-1` → `high`
- `dall-e-2` → no quality field (model has none)
- `imagen-4-*` → `imageSize: 2K`
- `imagen-3-*` → no parameter (Imagen 3 has no size/quality knob beyond aspect ratio)
- Gemini image-generation models → no quality knob

Pass `--quality low|medium|high|standard` only if the user opted out — "make a quick draft", "low-res is fine", "save credits". HD is the default precisely because users assume the best version unless they opt out.

## Config schema

`/home/owner/.carbon/config.yaml` (carbon's actual structure):

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

It deliberately **does not** read `defaults.model` (that's the chat tier in carbon's normal flow) and it deliberately **does not** read any `base_url` field — each provider script targets that provider's official endpoint and that endpoint only.

## Provider routing

| `defaults.provider` | Behavior |
|---|---|
| `openai` | dispatch to `openai_generate.sh`; default model `gpt-image-1` |
| `gemini` | dispatch to `gemini_generate.sh`; default model `imagen-4.0-generate-001`. Endpoint differs by model family — Imagen uses `:predict`, Gemini image models use `:generateContent`. |
| `anthropic` | exit code 2 with a clear message: Anthropic does not provide an image generation API. Surface this verbatim and ask the user which provider they'd like to switch to. |

## Reporting back to the user

After success, tell the user the absolute path of the saved image and the model that produced it. If the script failed, surface its stderr verbatim. The most common failures (missing API key, expired key, bad model name, anthropic provider) all need a config change the user has to make — don't retry blindly.

## Edge cases worth knowing

- **Prompt contains quotes or newlines.** Pass the prompt as a single argument; the scripts JSON-escape it internally. Don't pre-escape.
- **`config.yaml` missing or unreadable.** Script exits non-zero with the path it tried. Tell the user where to put the file.
- **`providers.<name>.api_key` empty.** Script exits non-zero with the field name. This is the single most common failure — surface the message verbatim and stop. Don't fall back to a different provider unless the user asks.
- **Custom proxy / gateway.** Not supported. Each provider script hits the official endpoint (`api.openai.com`, `generativelanguage.googleapis.com`) and ignores any `base_url` field in `config.yaml`. If the user needs a proxy, they have to fork the script and change the URL.
- **`--model` doesn't match the active provider.** E.g., `defaults.provider: openai` with `--model imagen-3.0-generate-002`. The script trusts the inputs and sends the request; the API will reject it. Suggest fixing one or the other rather than guessing.
- **Output path's parent directory doesn't exist.** The script will fail when writing. Create the directory first if the user asked for a nested path.

## Files

- `scripts/generate.sh` — orchestrator
- `scripts/openai_generate.sh` — OpenAI implementation
- `scripts/gemini_generate.sh` — Gemini/Imagen implementation
- `scripts/parse_yaml.sh` — YAML helpers (sourced by the others)
