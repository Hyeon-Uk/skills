#!/usr/bin/env bash
# get_api_key.sh — extract an AI provider's API key from a YAML config file.
#
# Usage:
#   bash get_api_key.sh <config_file_path> <provider>
#
# Arguments:
#   config_file_path  Absolute or relative path to the YAML config file.
#   provider          One of: anthropic | openai | gemini
#
# Output:
#   stdout  The API key value (single line, no trailing whitespace).
#   stderr  Error messages on failure.
#
# Exit codes:
#   0  Key resolved.
#   1  Usage error (bad/missing args, unknown provider).
#   2  Config file unreadable, malformed, or key not found / empty.
#
# Assumed YAML structure (edit this script + the parser call below to match
# your actual config layout):
#
#   providers:
#     anthropic:
#       api_key: "sk-ant-..."
#     openai:
#       api_key: "sk-..."
#     gemini:
#       api_key: "AIza..."
#
# Implementation note: this parser is intentionally minimal — only what's
# needed to read a 3-level nested scalar (section -> provider -> field).
# No anchors, no flow style, no multi-line scalars, no arrays. Pure bash
# builtins; no jq / yq / awk / sed / python required.

set -eu

usage() {
    cat >&2 <<'EOF'
Usage: get_api_key.sh <config_file_path> <provider>

  provider: anthropic | openai | gemini

Prints the API key on stdout. Errors go to stderr.
EOF
}

if [ $# -ne 2 ]; then
    usage
    exit 1
fi

CONFIG_FILE="$1"
PROVIDER="$2"

case "$PROVIDER" in
    anthropic|openai|gemini) ;;
    *)
        printf 'get_api_key.sh: unknown provider %q (expected: anthropic | openai | gemini)\n' "$PROVIDER" >&2
        exit 1
        ;;
esac

if [ ! -r "$CONFIG_FILE" ]; then
    printf 'get_api_key.sh: cannot read config file: %s\n' "$CONFIG_FILE" >&2
    exit 2
fi

# ----------------------------------------------------------------------
# Pure-bash YAML reader for one 3-level nested scalar:
#     <p1>:
#       <p2>:
#         <p3>: <value>
#
# Indentation-based scope tracking. Lines starting with '#' are comments.
# Blank lines are ignored. Quoted values ("..." or '...') are unquoted.
# ----------------------------------------------------------------------
yaml_get_3level() {
    local file="$1" p1="$2" p2="$3" p3="$4"
    local line stripped indent
    local in_p1=0 in_p2=0
    local p1_indent=-1 p2_indent=-1

    while IFS= read -r line || [ -n "$line" ]; do
        # Strip trailing CR (CRLF files).
        line="${line%$'\r'}"

        # Skip blank lines.
        case "$line" in
            ''|*[!\ \	]*) ;;
            *) continue ;;
        esac
        [ -z "${line//[[:space:]]/}" ] && continue

        # Compute leading-whitespace count and stripped body.
        stripped="${line#"${line%%[![:space:]]*}"}"
        indent=$(( ${#line} - ${#stripped} ))

        # Skip comment lines.
        [ "${stripped:0:1}" = "#" ] && continue

        # Strip inline trailing whitespace on stripped (rare but safe).
        stripped="${stripped%"${stripped##*[![:space:]]}"}"

        if [ $in_p1 -eq 0 ]; then
            # Look for top-level "<p1>:" (indent 0, no value on same line).
            if [ $indent -eq 0 ] && [ "$stripped" = "${p1}:" ]; then
                in_p1=1
                p1_indent=0
                continue
            fi
            # Anything else at indent 0 that isn't p1 — keep scanning.
            continue
        fi

        # We're inside the p1 block. If we hit a sibling at the same indent
        # (or lower), the p1 block is over.
        if [ $indent -le $p1_indent ]; then
            in_p1=0
            in_p2=0
            # Re-check this same line as a potential new p1 start.
            if [ $indent -eq 0 ] && [ "$stripped" = "${p1}:" ]; then
                in_p1=1
                p1_indent=0
            fi
            continue
        fi

        if [ $in_p2 -eq 0 ]; then
            # Look for the p2 key (must be a bare "key:" — no inline value).
            if [ "$stripped" = "${p2}:" ]; then
                in_p2=1
                p2_indent=$indent
                continue
            fi
            # Some other p2-sibling — skip until we find ours or leave p1.
            continue
        fi

        # We're inside p2. Out of p2 block?
        if [ $indent -le $p2_indent ]; then
            in_p2=0
            # Re-check this line as a possible new p2 candidate or end of p1.
            if [ $indent -le $p1_indent ]; then
                in_p1=0
                if [ $indent -eq 0 ] && [ "$stripped" = "${p1}:" ]; then
                    in_p1=1
                    p1_indent=0
                fi
            elif [ "$stripped" = "${p2}:" ]; then
                in_p2=1
                p2_indent=$indent
            fi
            continue
        fi

        # Look for "<p3>: <value>".
        local prefix="${p3}:"
        if [ "${stripped#"$prefix"}" != "$stripped" ]; then
            local val="${stripped#"$prefix"}"
            # Trim leading whitespace from value.
            val="${val#"${val%%[![:space:]]*}"}"
            # Trim trailing whitespace.
            val="${val%"${val##*[![:space:]]}"}"
            # Strip inline comment ( ` # ...` outside of quotes — best-effort).
            case "$val" in
                \"*\"|\'*\') ;;  # quoted; leave as-is
                *' #'*) val="${val%% #*}" ;;
            esac
            val="${val%"${val##*[![:space:]]}"}"
            # Unquote.
            if [ "${val:0:1}" = '"' ] && [ "${val: -1}" = '"' ]; then
                val="${val:1:${#val}-2}"
            elif [ "${val:0:1}" = "'" ] && [ "${val: -1}" = "'" ]; then
                val="${val:1:${#val}-2}"
            fi
            printf '%s' "$val"
            return 0
        fi
    done < "$file"

    return 1
}

# Edit these three constants if your YAML structure differs from
# providers.<provider>.api_key.
SECTION="providers"
FIELD="api_key"

VALUE="$(yaml_get_3level "$CONFIG_FILE" "$SECTION" "$PROVIDER" "$FIELD" || true)"

if [ -z "$VALUE" ]; then
    printf 'get_api_key.sh: %s.%s.%s missing or empty in %s\n' \
        "$SECTION" "$PROVIDER" "$FIELD" "$CONFIG_FILE" >&2
    exit 2
fi

printf '%s\n' "$VALUE"
