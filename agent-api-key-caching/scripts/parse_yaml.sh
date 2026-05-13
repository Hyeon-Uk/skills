#!/usr/bin/env bash
# parse_yaml.sh — minimal YAML reader for the agent config.
# Only what agent-api-key-caching needs: one-level and two-level nested scalar
# fields (e.g. providers.openai.api_key). No arrays, no anchors.
#
# Sourced by cache_api_key.sh. Reason this lives in shell: the embedded
# targets an agent-daemon runs on often lack yq / python / node.

# Strip surrounding quotes, leading/trailing whitespace, trailing CR.
_yaml_clean() {
    local v="$1"
    v="${v%$'\r'}"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    if [ "${v:0:1}" = '"' ] && [ "${v: -1}" = '"' ]; then
        v="${v:1:${#v}-2}"
    elif [ "${v:0:1}" = "'" ] && [ "${v: -1}" = "'" ]; then
        v="${v:1:${#v}-2}"
    fi
    printf '%s' "$v"
}

# get_yaml_nested <section> <key> <file>
# Reads `<section>:` block, then `  <key>: value` inside it.
get_yaml_nested() {
    local section="$1" key="$2" file="$3"
    awk -v section="$section" -v key="$key" '
        BEGIN { in_section = 0 }
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        {
            if (in_section) {
                if ($0 ~ /^[^[:space:]]/) { in_section = 0 }
                else if (match($0, "^[[:space:]]+" key ":")) {
                    val = substr($0, RLENGTH + 1)
                    sub(/^[[:space:]]+/, "", val)
                    sub(/[[:space:]]+$/, "", val)
                    sub(/\r$/, "", val)
                    if (substr(val,1,1) == "\"" && substr(val,length(val),1) == "\"") {
                        val = substr(val, 2, length(val) - 2)
                    } else if (substr(val,1,1) == "'\''" && substr(val,length(val),1) == "'\''") {
                        val = substr(val, 2, length(val) - 2)
                    }
                    print val
                    exit
                }
            }
            if ($0 ~ "^" section ":[[:space:]]*$") { in_section = 1 }
        }
    ' "$file"
}

# get_yaml_nested3 <p1> <p2> <p3> <file>
# Reads a 3-level nested scalar such as providers.openai.api_key.
# Approach: extract the p1 block, normalize its indentation, then reuse
# get_yaml_nested on the trimmed content. Easier to reason about than a
# triple-nested state machine in awk.
get_yaml_nested3() {
    local p1="$1" p2="$2" p3="$3" file="$4"
    local content indent tmp rc

    content="$(awk -v section="$p1" '
        BEGIN { in_block = 0 }
        $0 ~ "^" section ":[[:space:]]*$" { in_block = 1; next }
        in_block && /^[^[:space:]]/ { in_block = 0 }
        in_block { print }
    ' "$file")"

    [ -z "$content" ] && return 1

    indent="$(printf '%s\n' "$content" | awk '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#/ { next }
        {
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c != " " && c != "\t") { print i - 1; exit }
            }
        }
    ')"
    [ -z "$indent" ] && indent=0

    tmp="$(mktemp)"
    printf '%s\n' "$content" | awk -v ind="$indent" '{ print substr($0, ind + 1) }' > "$tmp"
    get_yaml_nested "$p2" "$p3" "$tmp"
    rc=$?
    rm -f "$tmp"
    return $rc
}
