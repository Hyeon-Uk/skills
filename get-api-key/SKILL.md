---
name: get-api-key
description: Extracts an AI provider's API key from a YAML config file. Pass the absolute path to the YAML config and a provider name (anthropic | openai | gemini), and the script parses the file in pure bash — no jq, yq, awk, sed, or python — and prints the matching API key on stdout. Use this skill whenever a caller skill, tool, or agent needs to read an API key from a project-local YAML config, mentions "get API key", "load API key from config", "API_KEY", "provider key", "anthropic key", "openai key", "gemini key", or fails because a key is missing and a config file path is available. Prefer this over hand-rolling another YAML lookup in each caller; the whole point is one drop-in shell tool with no external-tool dependencies.
argument-hint: "<config_file_path> <provider>"
user-invocable: true
allowed-tools: true
---

# get-api-key

A small, self-contained shell tool that reads a YAML config file and
prints the API key for one of three AI providers (`anthropic`,
`openai`, `gemini`) on stdout.

## Why this exists

Callers that need an API key shouldn't each invent their own YAML
reader. On embedded / constrained targets `jq` and `yq` aren't
available; even on full systems pulling in a parser dependency per
caller is overkill for a 3-level scalar lookup. This script is **pure
bash builtins** — no external parsing tools — so it drops into any
environment that already has bash.

## CLI

```bash
bash <skill-dir>/scripts/get_api_key.sh <config_file_path> <provider>
```

| Arg | Required | Description |
|---|---|---|
| `config_file_path` | yes | Path (absolute or relative) to the YAML config file. |
| `provider` | yes | One of `anthropic`, `openai`, `gemini`. |

Stdout: the raw API key value, one line, no trailing whitespace beyond
a single newline.

Stderr: error messages on failure (the key value is never printed to
stderr).

### Example

```bash
KEY="$(bash get_api_key.sh /opt/myagent/config.yaml openai)" || {
    echo "could not resolve openai key" >&2
    exit 1
}
```

## Assumed YAML structure

The bundled script expects the config to look like:

```yaml
providers:
  anthropic:
    api_key: "sk-ant-..."
  openai:
    api_key: "sk-..."
  gemini:
    api_key: "AIza..."
```

That is, a 3-level nested scalar at `providers.<provider>.api_key`.

If your real config differs, edit `scripts/get_api_key.sh` — see the
"Customization" section below.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Key resolved (stdout has the value). |
| 1 | Usage error — wrong arg count, unknown provider. |
| 2 | Config file unreadable, or `providers.<provider>.api_key` missing/empty. |

## Parsing limits

The parser is intentionally minimal. It handles:

- Indentation-based nesting (any consistent indent width).
- `#` line comments, blank lines.
- Optional surrounding `"..."` or `'...'` on the value.
- CRLF line endings.

It does **not** handle:

- YAML anchors / aliases (`&foo`, `*foo`).
- Flow style (`{key: value}` or `[a, b]`).
- Multi-line scalars (`|`, `>`).
- Arrays.

For an API key string this is fine; if your config grows fancier the
parser will need to be extended (or replaced with a real YAML lib).

## Customization

Edit the two constants near the bottom of `scripts/get_api_key.sh` to
match your config schema:

```bash
SECTION="providers"   # top-level key
FIELD="api_key"       # leaf key under each provider
```

The middle key is always the `provider` argument (one of `anthropic`,
`openai`, `gemini`), so the lookup path is `${SECTION}.${PROVIDER}.${FIELD}`.

If your schema is **not** 3 levels deep (e.g. flat `anthropic_api_key:
...` at the top, or 4-level nested), the `yaml_get_3level` function
itself needs to change — replace its body or call a different helper.
Tell the maintainer of this skill which structure you actually use and
they'll adjust.

## Files

- `scripts/get_api_key.sh` — the entire tool. No siblings, no
  sourced helpers, no dependencies beyond `bash`.
