#!/usr/bin/env bash
# scripts/lib/json.sh - read JSON from bash without jq. Source it:  . "$(dirname "$0")/lib/json.sh"
# The parsing is done by json.awk (POSIX awk, run with LC_ALL=C); the functions below query the records it
# prints. Paths are keys joined with dots and [i] for an array item: worktrees.warmup[0].command.
# A key that contains a dot, a bracket, a tab or a newline cannot be addressed by path.
#
#   json_load FILE            parse FILE and keep the records in JSON_FLAT; prints the error and returns 1
#                             for an unreadable or invalid file
#   json_check FILE           like json_load but keeps nothing (is the file valid JSON?)
#   json_get PATH [DEFAULT]   the string value at PATH, decoded; DEFAULT (empty when not given) when the
#                             path is absent, null, an object or an array
#   json_len PATH             the number of items of the array or object at PATH; 0 when absent
#   json_keys PATH            the keys of the object at PATH, one per line, in file order (PATH "" = root)
#   json_has PATH             exit code 0 when PATH exists, also when its value is null
#   json_quote STRING         STRING as a JSON string literal, like jq's tojson
#   json_marker SLOT BRANCH SINCE   the slot marker text, byte for byte what jq -n printed before

JSON_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
JSON_FLAT=""

_json_awk() { LC_ALL=C awk -f "$JSON_LIB_DIR/json.awk"; }

json_load() {
  local out
  out=$(JSON_MODE=flat JSON_FILE="$1" _json_awk) || return 1
  JSON_FLAT=$out
}

json_check() {
  JSON_MODE=check JSON_FILE="$1" _json_awk
}

json_get() {
  local p=$1 def=${2-} res val
  res=$(printf '%s\n' "$JSON_FLAT" | JSON_P=$p LC_ALL=C awk -F '\t' '
    $1 == ENVIRON["JSON_P"] { kind = $2; val = $3; found = 1 }
    END {
      if (found && (kind == "string" || kind == "number" || kind == "boolean")) print kind "\t" val
      else print "-"
    }')
  if [ "$res" = "-" ]; then printf '%s' "$def"; return 0; fi
  val=${res#*$'\t'}
  printf '%b' "$val"
}

json_len() {
  printf '%s\n' "$JSON_FLAT" | JSON_P=$1 LC_ALL=C awk -F '\t' '
    $1 == ENVIRON["JSON_P"] && ($2 == "array" || $2 == "object") { n = $3 }
    END { print n + 0 }'
}

json_keys() {
  printf '%s\n' "$JSON_FLAT" | JSON_P=$1 LC_ALL=C awk -F '\t' '
    BEGIN { p = ENVIRON["JSON_P"]; pl = length(p); if (pl > 0) { p = p "."; pl++ } }
    $1 != "" && (pl == 0 || substr($1, 1, pl) == p) {
      rest = substr($1, pl + 1)
      if (rest != "" && index(rest, ".") == 0 && index(rest, "[") == 0) print rest
    }'
}

json_has() {
  printf '%s\n' "$JSON_FLAT" | JSON_P=$1 LC_ALL=C awk -F '\t' '
    $1 == ENVIRON["JSON_P"] { f = 1 }
    END { exit !f }'
}

json_quote() {
  JSON_MODE=quote JSON_S=$1 _json_awk
}

json_marker() {
  printf '{\n  "slot": %s,\n  "branch": %s,\n  "since": %s\n}\n' "$1" "$(json_quote "$2")" "$(json_quote "$3")"
}
