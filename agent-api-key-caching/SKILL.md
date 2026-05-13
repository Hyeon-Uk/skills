---
name: agent-api-key-caching
description: Dynamically resolves AND caches an AI provider's API key (openai, gemini, anthropic) for an agent-daemon. Three-tier lookup, cheapest first — (1) current-process env var AGENT_<PROVIDER>_API_KEY (or the standard <PROVIDER>_API_KEY), (2) persistent daemon env file {agent_config_path}/daemon.env, (3) providers.<provider>.api_key in {agent_config_path}/config.yaml. On a config-tier hit the value is written *through* the cache — into daemon.env (so the next daemon restart finds it) and exported into the current process (so the next call in this shell finds it) — meaning subsequent requests never touch the YAML again. Use this skill whenever an agent skill/tool needs an API key, mentions API_KEY / api key / provider key / OpenAI / Gemini / Anthropic credentials, fails with "missing key", or whenever you want the daemon to dynamically pick up a rotated key without a restart. Prefer this over re-parsing config.yaml in every caller; the whole point of this skill is so that lookup happens once and is cached.
argument-hint: "<provider> [--export]"
user-invocable: true
allowed-tools: true
---

# agent-api-key-caching

A caching API-key resolver used by an agent-daemon and the agent's
provider-using skills. One call resolves a provider's key from the
cheapest available tier and write-through-caches it into every higher
tier, so the next call — whether from the same shell, the same daemon
process, or a fresh daemon restart — pays nothing for the lookup.

## Why this exists

Before this skill, every AI-using skill parsed `config.yaml` on every
invocation. On the embedded targets an agent-daemon runs on that is
both slow (no `yq`, no `python`, so it's awk + sed every time) and
awkward to override — you had to edit YAML to rotate a key. Funneling
every key lookup through one cache lets us:

- Read the YAML at most **once** per daemon lifetime per provider.
- Override a key for a single skill invocation with one shell `export`.
- Pick up a rotated key on the next call without restarting the daemon,
  because the config tier is consulted again when both env tiers miss.

## Cache hierarchy

For provider `<p>` (e.g. `openai`) the script checks, in order:

| Tier | Where | Why it's first |
|---|---|---|
| **L1**  | `AGENT_<P>_API_KEY` in the current process | Free — already in memory, picks up `eval`'d exports from earlier in this shell |
| **L1′** | `<P>_API_KEY` (standard SDK name, e.g. `OPENAI_API_KEY`) | Free, and lets devs reuse the env var they already have set for the official SDK |
| **L2**  | `{agent_config_path}/daemon.env` | One `grep` + `eval` of a single line — survives daemon restarts but not reboots-without-source |
| **L3**  | `providers.<p>.api_key` in `{agent_config_path}/config.yaml` | Slow (awk parse), but the source of truth |

The agent-prefixed name wins over the standard SDK name at L1 so a
deliberate agent override is never silently shadowed by an unrelated
shell export the dev forgot about.

### Write-through

When L3 fires, the resolved key is written to both higher tiers before
returning:

1. **L2 (persistent)** — atomically rewrites `daemon.env`, replacing
   any prior line for the same provider. The agent-daemon is expected
   to `source` this file on (re)start, so the next process resolves at
   L2.
2. **L1 (in-process)** — `export AGENT_<P>_API_KEY=...` so the very
   next call inside *this* shell resolves at L1. Note this only sticks
   in the current shell; calling shells that want it must use
   `--export` + `eval` (see below).

### Override / rotation

A rotated key in `config.yaml` will **not** be picked up while a stale
value is still cached at L1 or L2. To force a re-read, clear the
relevant tier(s):

```sh
unset AGENT_OPENAI_API_KEY                   # clear L1
rm  "${AGENT_CONFIG_PATH}/daemon.env"        # clear L2
bash cache_api_key.sh openai                 # re-resolves from L3, re-caches
```

This is intentional — silently re-reading YAML on every call would
defeat the whole point of caching.

## CLI

```bash
bash <skill-dir>/scripts/cache_api_key.sh <provider> [--export]
```

The script reads its paths from environment variables. **Set
`AGENT_CONFIG_PATH` to the directory holding `config.yaml` before
invoking** — there is no hardcoded default, so this skill can be reused
across agents with different config locations.

| Provider arg | Resolves |
|---|---|
| `openai` | OpenAI API key |
| `gemini` (alias `google`) | Google Gemini / AI Studio key |
| `anthropic` | Anthropic API key |

### Modes

| Flag | Stdout | When to use |
|---|---|---|
| *(none)* | The raw key value, one line | Capture into a variable: `KEY="$(cache_api_key.sh openai)"` |
| `--export` | `export AGENT_OPENAI_API_KEY='...'` | Source into the caller's shell: `eval "$(cache_api_key.sh openai --export)"` — required if you want the **calling** shell to also benefit from L1 caching on subsequent calls |

Either mode prints a one-line audit note on stderr stating which tier
served the key (`env` / `daemon.env` / `config`), so callers can log
the resolution path without ever printing the key itself.

### Environment overrides

| Variable | Default | Purpose |
|---|---|---|
| `AGENT_CONFIG_PATH` | *(required)* | Directory that holds `config.yaml` and `daemon.env`. Templated as `{agent_config_path}` in this doc |
| `AGENT_CONFIG` | `${AGENT_CONFIG_PATH}/config.yaml` | Override the full path to the config file (L3). Takes precedence over `AGENT_CONFIG_PATH` for the config file location |
| `AGENT_DAEMON_ENV` | `${AGENT_CONFIG_PATH}/daemon.env` | Override the full path to the daemon env file the script reads at L2 and writes through to on an L3 hit |

## How an agent-daemon should integrate

On daemon startup (or restart), source the cache file so any
previously-resolved key is restored at L1:

```sh
[ -r "${AGENT_CONFIG_PATH}/daemon.env" ] && . "${AGENT_CONFIG_PATH}/daemon.env"
```

Then call this skill the first time a request needs a particular
provider's key. The script will:

- Find it at L1 (free) if a previous request already cached it.
- Find it at L2 if the daemon restarted but `daemon.env` is intact.
- Fall through to L3 and write back to L1+L2 if neither env tier has
  it — at which point all future requests in this daemon lifetime
  resolve at L1.

## How other skills should call this

Inside a sibling skill's script:

```bash
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SKILL_DIR/../../agent-api-key-caching/scripts/cache_api_key.sh"

# AGENT_CONFIG_PATH must already be exported by the agent-daemon environment.

# Option A: just need the value
API_KEY="$(bash "$RESOLVER" openai)" || {
    echo "myskill: could not resolve OpenAI key — see message above" >&2
    exit 1
}

# Option B: also want subsequent calls in this shell to hit L1
eval "$(bash "$RESOLVER" openai --export)" || exit 1
# now $AGENT_OPENAI_API_KEY is set; future cache_api_key.sh openai
# calls in this shell return instantly from L1.
```

The resolver prints its own error to stderr on failure, so callers
should propagate the non-zero exit code rather than re-wrapping the
message.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Key resolved (stdout contains it / the export line) |
| 1 | Usage error — unknown flag, missing/extra args, unknown provider, or neither `AGENT_CONFIG_PATH` nor `AGENT_CONFIG` is set |
| 2 | Every tier missed: no env var set, and config unreadable or `providers.<p>.api_key` missing/empty |

## Edge cases

| Case | Handling |
|---|---|
| Both `AGENT_OPENAI_API_KEY` and `OPENAI_API_KEY` are set | Agent-prefixed wins — a deliberate agent override is never silently shadowed |
| `AGENT_OPENAI_API_KEY=""` (empty) | Treated as unset, falls through to the next tier |
| Key contains single quotes | Properly escaped when written to `daemon.env`, so sourcing the file is safe |
| `daemon.env` has a syntax error elsewhere | Only the matching `export AGENT_<P>_API_KEY=…` line is `eval`'d — unrelated breakage in the file can't kill the resolver |
| `daemon.env` has a stale entry for the same provider | The old entry is dropped and replaced atomically (`mv`) so a rotated key doesn't sit behind the new one |
| Config file missing AND no env var set | Exit 2 with the config path on stderr — caller is expected to ask the user to set the key |
| `--export` mode + L1 hit | Still prints `export AGENT_<P>_API_KEY='…'` — harmless to `eval` a no-op assignment |
| `anthropic` requested by an image-only skill | Out of scope for this skill — it only resolves keys. Image-only callers must keep their own provider-capability checks |
| `AGENT_CONFIG_PATH` unset and `AGENT_CONFIG` unset | Exit 1 with a hint to set `AGENT_CONFIG_PATH` — no hardcoded default by design |

## Files

- `scripts/cache_api_key.sh` — main resolver with L1/L2/L3 + write-through
- `scripts/parse_yaml.sh` — minimal YAML helpers (sourced)
