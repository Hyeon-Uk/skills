#!/usr/bin/env bash
# cache_api_key.sh — resolve an AI provider's API key and *cache* it as an
# environment variable for the agent-daemon, so future requests in this
# process (and in future daemon restarts) skip the YAML parse entirely.
#
# Cache hierarchy (cheapest first):
#
#   L1  in-process env var      AGENT_<P>_API_KEY       (current shell)
#   L1' standard SDK env var    <P>_API_KEY             (e.g. OPENAI_API_KEY)
#   L2  persistent env file     $AGENT_DAEMON_ENV       (sourced by daemon)
#   L3  agent config file       providers.<p>.api_key in $AGENT_CONFIG
#
# A miss at L1/L1' falls through to L2 (auto-sourced if present), then to L3.
# Whenever L3 is the source, the key is written back to L2 *and* re-exported
# into the current process — so the very next call in the same shell hits L1.
#
# Path resolution:
#   - $AGENT_CONFIG     wins if set (full path to config.yaml).
#   - Otherwise         $AGENT_CONFIG_PATH/config.yaml         (directory mode).
#   - $AGENT_DAEMON_ENV wins if set; otherwise $AGENT_CONFIG_PATH/daemon.env.
#   - If neither AGENT_CONFIG nor AGENT_CONFIG_PATH is set, the script errors
#     out — there is no hardcoded default because this skill is meant to be
#     reused across agents with different config locations.
#
# Usage:
#   bash cache_api_key.sh <provider>             # prints raw key on stdout
#   bash cache_api_key.sh <provider> --export    # prints `export AGENT_<P>_API_KEY='...'`
#                                                # so callers can `eval` it
#   eval "$(bash cache_api_key.sh openai --export)"
#
# Providers: openai | gemini (alias: google) | anthropic
#
# Exit codes:
#   0 = key resolved (stdout has it / has the export line)
#   1 = usage error (also: AGENT_CONFIG / AGENT_CONFIG_PATH both unset)
#   2 = key not in env, config unreadable or providers.<p>.api_key missing

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse_yaml.sh
. "$SCRIPT_DIR/parse_yaml.sh"

# Resolve config + daemon-env paths from the agent_config_path template.
if [ -n "${AGENT_CONFIG:-}" ]; then
    :  # explicit override, use as-is
elif [ -n "${AGENT_CONFIG_PATH:-}" ]; then
    AGENT_CONFIG="${AGENT_CONFIG_PATH%/}/config.yaml"
else
    echo "cache_api_key.sh: AGENT_CONFIG_PATH is not set (and AGENT_CONFIG not given)" >&2
    echo "Set AGENT_CONFIG_PATH to the directory holding config.yaml, e.g.:" >&2
    echo "  export AGENT_CONFIG_PATH=/opt/usr/home/owner/.myagent" >&2
    exit 1
fi

if [ -z "${AGENT_DAEMON_ENV:-}" ]; then
    if [ -n "${AGENT_CONFIG_PATH:-}" ]; then
        AGENT_DAEMON_ENV="${AGENT_CONFIG_PATH%/}/daemon.env"
    else
        # AGENT_CONFIG was given but no path root; sit daemon.env next to it.
        AGENT_DAEMON_ENV="$(dirname "$AGENT_CONFIG")/daemon.env"
    fi
fi

PROVIDER=""
MODE="value"

while [ $# -gt 0 ]; do
    case "$1" in
        --export) MODE="export"; shift ;;
        --help|-h)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*) echo "cache_api_key.sh: unknown flag: $1" >&2; exit 1 ;;
        *)
            if [ -z "$PROVIDER" ]; then PROVIDER="$1"
            else echo "cache_api_key.sh: unexpected arg: $1" >&2; exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$PROVIDER" ]; then
    echo "cache_api_key.sh: provider is required (openai | gemini | anthropic)" >&2
    exit 1
fi

case "$PROVIDER" in
    openai|gemini|anthropic) ;;
    google) PROVIDER="gemini" ;;
    *)
        echo "cache_api_key.sh: unknown provider '$PROVIDER' (expected openai | gemini | anthropic)" >&2
        exit 1
        ;;
esac

UPPER="$(printf '%s' "$PROVIDER" | tr '[:lower:]' '[:upper:]')"
AGENT_VAR="AGENT_${UPPER}_API_KEY"
STANDARD_VAR="${UPPER}_API_KEY"

# ---- L1: already in this process? ----
# eval is used to dereference dynamic names without bash >=4.3 namerefs,
# which are not guaranteed on the embedded targets agent-daemon runs on.
VALUE=""
eval "VALUE=\${$AGENT_VAR:-}"
if [ -z "$VALUE" ]; then
    eval "VALUE=\${$STANDARD_VAR:-}"
fi
SOURCE="env"

# ---- L2: persistent daemon.env — fold it into L1 if it has our key ----
# We intentionally source only the line for this provider, not the whole file,
# so a stray syntax error elsewhere in daemon.env can't kill the resolver.
if [ -z "$VALUE" ] && [ -r "$AGENT_DAEMON_ENV" ]; then
    LINE="$(grep -E "^export ${AGENT_VAR}=" "$AGENT_DAEMON_ENV" | tail -n1 || true)"
    if [ -n "$LINE" ]; then
        eval "$LINE"
        eval "VALUE=\${$AGENT_VAR:-}"
        SOURCE="daemon.env"
    fi
fi

# ---- L3: config.yaml fallback, then write-through cache to L1 + L2 ----
if [ -z "$VALUE" ]; then
    if [ ! -r "$AGENT_CONFIG" ]; then
        echo "cache_api_key.sh: cannot read $AGENT_CONFIG" >&2
        echo "Set AGENT_CONFIG or AGENT_CONFIG_PATH to override the path, or create the file." >&2
        exit 2
    fi

    VALUE="$(get_yaml_nested3 providers "$PROVIDER" api_key "$AGENT_CONFIG" || true)"
    if [ -z "$VALUE" ]; then
        echo "cache_api_key.sh: providers.$PROVIDER.api_key missing or empty in $AGENT_CONFIG" >&2
        exit 2
    fi
    SOURCE="config"

    # Write-through to L2. Rewrite atomically rather than append so a rotated
    # key never leaves a stale shadow above the fresh one.
    mkdir -p "$(dirname "$AGENT_DAEMON_ENV")" 2>/dev/null || true
    TMP_ENV="$(mktemp)"
    trap 'rm -f "$TMP_ENV"' EXIT
    if [ -f "$AGENT_DAEMON_ENV" ]; then
        grep -v "^export ${AGENT_VAR}=" "$AGENT_DAEMON_ENV" > "$TMP_ENV" || true
    fi
    ESCAPED="${VALUE//\'/\'\\\'\'}"
    printf "export %s='%s'\n" "$AGENT_VAR" "$ESCAPED" >> "$TMP_ENV"
    mv "$TMP_ENV" "$AGENT_DAEMON_ENV"
    trap - EXIT
    chmod 600 "$AGENT_DAEMON_ENV" 2>/dev/null || true

    # Also reflect into the current process. This only affects the current
    # shell; calling shells that want it must use --export + eval.
    export "$AGENT_VAR=$VALUE"
fi

case "$MODE" in
    value)
        printf '%s\n' "$VALUE"
        ;;
    export)
        ESCAPED="${VALUE//\'/\'\\\'\'}"
        printf "export %s='%s'\n" "$AGENT_VAR" "$ESCAPED"
        ;;
esac

echo "cache_api_key.sh: $PROVIDER key resolved from $SOURCE" >&2
