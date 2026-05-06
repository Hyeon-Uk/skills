#!/usr/bin/env bash
# parse_yaml.sh — minimal YAML reader for the carbon config.
# Handles only what generate-image needs: top-level scalar fields and
# one level of nesting (e.g. openai.api_key). No arrays, no anchors.
#
# Sourced by generate.sh / openai_generate.sh / gemini_generate.sh.
# Reason it exists: embedded targets often lack yq/python/node.

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

# get_yaml_field <field> <file>
# Reads a top-level `field: value` line. Comments and indented lines are skipped.
get_yaml_field() {
    local field="$1" file="$2" line raw
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "${field}:"*) raw="${line#${field}:}"; _yaml_clean "$raw"; return 0 ;;
        esac
    done < "$file"
    return 1
}

# get_yaml_nested <section> <key> <file>
# Reads `<section>:` block, then the first `  <key>: value` inside it.
# Block ends at the next non-indented, non-blank, non-comment line.
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

# json_escape <string>
# Escape a string for embedding inside JSON double quotes.
# We do this in shell because the target lacks jq/python/node.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}
