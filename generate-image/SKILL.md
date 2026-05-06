---
name: generate-image
description: Generates images via OpenAI (DALL-E, gpt-image-1) or Google Gemini (Imagen, Gemini image models) by reading the active provider/model and API key from `/home/owner/.carbon/config.yaml`. Built for embedded Linux — pure shell + curl, no Python or Node required. Use this skill whenever the user asks to create, generate, draw, render, or make an image; whenever they mention DALL-E, Imagen, gpt-image, or text-to-image; whenever they reference the Carbon config or want to use their currently configured image model — even if they don't explicitly say "use the skill". If the active provider in the config is `anthropic`, this skill will return a clear error explaining that Anthropic does not offer an image generation API.
---

# generate-image

Generates an image from a text prompt using whichever provider is configured as active in `/home/owner/.carbon/config.yaml`.

## When to use this skill

Trigger on any user request that boils down to "make me a picture of X". Examples:
- "Generate an image of a sunset over mountains"
- "Draw a logo for my coffee shop"
- "Create a 16:9 banner of a futuristic city, save it to /tmp/banner.png"
- "Use my carbon config to render a watercolor of a cat"

If the user names a provider explicitly ("use OpenAI to..."), still defer to the active provider in `config.yaml` — the user's setting wins. Only mention the mismatch if the active provider can't fulfill the request (e.g., active provider is `anthropic`).

## How it works

The skill is a thin wrapper around three shell scripts in `scripts/`:

- `generate.sh` — entry point. Reads the config, dispatches to the right provider script, returns the saved file path.
- `openai_generate.sh` — calls `https://api.openai.com/v1/images/generations`.
- `gemini_generate.sh` — calls `generativelanguage.googleapis.com` (Imagen `:predict` or Gemini `:generateContent`).
- `parse_yaml.sh` — minimal YAML reader (top-level fields and one level of nesting). Used because the embedded environment lacks `yq`/`python`/`node`.

All three are POSIX-friendly bash. JSON parsing uses `sed` rather than `jq` so the skill works on stripped-down embedded systems where `jq` is not installed.

## Invocation

The skill scripts live next to this `SKILL.md`. Run from anywhere:

```bash
bash <skill-dir>/scripts/generate.sh "<prompt>" [options]
```

### Options

| Flag | Default | Notes |
|---|---|---|
| `--quality LEVEL` | HD-equivalent for the active model | Pass through only if the user mentioned quality. See "Quality default" below. |
| `--output PATH` | `./image_<YYYYmmdd_HHMMSS>.png` in the cwd | Honor exactly what the user asked for. |
| `--size WxH` | `1024x1024` | OpenAI accepts `1024x1024`, `1024x1536`, `1536x1024`, `auto`. Imagen converts this to an aspect ratio. |

### Quality default — IMPORTANT

If the user did **not** mention image quality in their request, do **not** pass `--quality`. The provider script will then fall back to HD-equivalent for the active model:

- `dall-e-3` → `hd`
- `gpt-image-1` → `high`
- `dall-e-2` → no quality field (model has no quality option)
- `imagen-4-*` → `imageSize: 2K`
- `imagen-3-*` → no parameter (Imagen 3 has no size/quality knob beyond aspect ratio)
- Gemini image models (`gemini-2.x-*-image-generation`) → no quality knob

Only pass `--quality low|medium|high|standard` if the user explicitly asked for a non-HD level — for example "make a quick draft", "low-res is fine", "save credits". HD is the default precisely because users assume the best version unless they opt out.

## Provider routing

The script reads two top-level keys from `/home/owner/.carbon/config.yaml`:

```yaml
provider: openai      # required: openai | gemini | anthropic
model: gpt-image-1    # required: model identifier the API expects
openai:
  api_key: sk-...
gemini:
  api_key: AIza...
anthropic:
  api_key: sk-ant-...
```

- `provider: openai` → dispatch to `openai_generate.sh`. Reads `openai.api_key`.
- `provider: gemini` → dispatch to `gemini_generate.sh`. Reads `gemini.api_key`. Endpoint differs by model family (Imagen uses `:predict`, Gemini image models use `:generateContent`).
- `provider: anthropic` → exit code `2` with a clear message: Anthropic does not provide an image generation API. The script suggests editing the config to use `openai` or `gemini`. Surface this verbatim to the user and ask which provider they'd like to switch to.

## Reporting back to the user

After the script succeeds, tell the user the absolute path of the saved image and the model that produced it. Don't paraphrase the file contents — there's nothing to add. If the script failed, surface its stderr verbatim; don't try to retry blindly, since the most common failures (missing API key, expired key, bad model name, anthropic provider) need a config change the user has to make.

## Edge cases worth knowing

- **Prompt contains quotes or newlines.** Pass the prompt as a single argument; the scripts JSON-escape it internally. Don't pre-escape it yourself.
- **`config.yaml` missing or unreadable.** The script exits non-zero with the path it tried. Tell the user where to put the file rather than assuming a different location.
- **API key field empty.** Same — script exits non-zero. Don't try other providers as a fallback unless the user asks.
- **Model name doesn't match the provider.** E.g., `provider: openai` but `model: imagen-3.0-generate-002`. The skill trusts the config and sends the request as-is; the API will reject it. If the user reports this kind of error, suggest fixing one of the two fields rather than guessing.
- **Output path's parent directory doesn't exist.** The script will fail when writing. Create the directory first if the user asked for a nested path.

## Files

- `scripts/generate.sh` — orchestrator
- `scripts/openai_generate.sh` — OpenAI implementation
- `scripts/gemini_generate.sh` — Gemini/Imagen implementation
- `scripts/parse_yaml.sh` — YAML helpers (sourced by the others)
