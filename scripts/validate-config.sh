#!/usr/bin/env bash
# scripts/validate-config.sh - check a nightmill config against the schema.
#
#   validate-config.sh [--schema path] [--strict] [config]
#
# config    the file to check (default: .claude/nightmill.json in the repository this script lives in)
# --schema  the schema to check against (default: schema/nightmill.schema.json in that repository)
# --strict  warnings (unknown keys) fail too
#
# Prints one finding per line, sorted by path, then a summary:
#   error: worktrees.slots: expected integer, got string
#   warning: worktree: unknown key (did you mean "worktrees"?)
#   1 error, 1 warning
# Exit codes: 0 no error (and with --strict no warning), 1 an error or, with --strict, a warning, 2 a usage
# error, an unreadable file or a missing tool. Same behaviour and output as validate-config.ps1.
#
# Needs jq (like the other bash scripts until they lose that dependency). The validator walks the schema; it
# supports type, properties, required, items, minimum, minItems, additionalProperties (a schema, true or
# false) and enum. tests/lint.sh fails if the schema uses a keyword that is not on that list.
set -euo pipefail

usage() { echo "usage: validate-config.sh [--schema path] [--strict] [config]" >&2; exit 2; }

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
config=""; schema=""; strict=0
while [ $# -gt 0 ]; do
  case "$1" in
    --schema) [ $# -ge 2 ] || usage; schema=$2; shift 2 ;;
    --strict) strict=1; shift ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *) [ -z "$config" ] || usage; config=$1; shift ;;
  esac
done
[ -n "$config" ] || config="$root/.claude/nightmill.json"
[ -n "$schema" ] || schema="$root/schema/nightmill.schema.json"

command -v jq >/dev/null 2>&1 || { echo "missing tool: jq" >&2; exit 2; }
[ -f "$config" ] && [ -r "$config" ] || { echo "cannot read config: $config" >&2; exit 2; }
[ -f "$schema" ] && [ -r "$schema" ] || { echo "cannot read schema: $schema" >&2; exit 2; }

# The jq program: walks the schema and prints one record per finding, "path TAB rank TAB line".
read -r -d '' PROG <<'EOF' || true
def kind: if . == null then "null" elif type == "number" then (if . == floor then "integer" else "number" end) else type end;
def join_key($p; $k): if $p == "" then $k else $p + "." + $k end;
def typeok($t): kind as $a | if $t == "number" then ($a == "integer" or $a == "number") else $a == $t end;
def hint($key; $known):
  [ $known[] as $k
    | select( ($k | ascii_downcase) == ($key | ascii_downcase)
           or (($k | length) == ($key | length) + 1 and ($k | startswith($key)))
           or (($key | length) == ($k | length) + 1 and ($key | startswith($k))) )
    | $k ][0];
def finding($p; $sev; $msg): {path: $p, sev: $sev, msg: $msg};
def v($s; $p):
  . as $val
  | ($val | kind) as $kind
  | if ($s | has("type")) and (($val | typeok($s.type)) | not) then
      finding($p; "error"; "expected \($s.type), got \($kind)")
    else
      ( if ($s | has("enum")) and (($s.enum | map(. == $val) | any) | not) then
          finding($p; "error"; "must be one of: \($s.enum | map(if type == "string" then . else tojson end) | join(", ")), got \($val | tojson)")
        else empty end ),
      ( if ($s | has("minimum")) and ($kind == "integer" or $kind == "number") and ($val < $s.minimum) then
          finding($p; "error"; "must be at least \($s.minimum), got \($val)")
        else empty end ),
      ( if $kind == "array" then
          ( if ($s | has("minItems")) and (($val | length) < $s.minItems) then
              finding($p; "error"; "needs at least \($s.minItems) items, got \($val | length)")
            else empty end ),
          ( if ($s | has("items")) then
              ( range(0; $val | length) as $i | $val[$i] | v($s.items; $p + "[" + ($i | tostring) + "]") )
            else empty end )
        else empty end ),
      ( if $kind == "object" then
          ( ($s.required // [])[] as $k | select(($val | has($k)) | not) | finding(join_key($p; $k); "error"; "required key is missing") ),
          ( ($s.properties // {}) as $props
            | ($props | keys_unsorted) as $known
            | ($val | keys_unsorted[]) as $k
            | join_key($p; $k) as $cp
            | if ($known | map(. == $k) | any) then $val[$k] | v($props[$k]; $cp)
              elif $k == "$schema" then empty
              elif ($s | has("additionalProperties")) then
                ( $s.additionalProperties as $ap
                  | if ($ap | type) == "boolean" then ( if $ap then empty else finding($cp; "error"; "unknown key is not allowed") end )
                    else $val[$k] | v($ap; $cp) end )
              else
                ( hint($k; $known) as $h
                  | finding($cp; "warning"; "unknown key" + (if $h == null then "" else " (did you mean \"" + $h + "\"?)" end)) )
              end )
        else empty end )
    end;
$schema[0] as $s
| v($s; "")
| (.path | if . == "" then "." else . end) as $shown
| "\($shown)\t\(if .sev == "error" then 0 else 1 end)\t\(.sev): \($shown): \(.msg)"
EOF

echo "validating $config against $schema"

if [ ! -s "$config" ] || ! jq empty "$config" >/dev/null 2>&1; then
  echo "error: .: not valid JSON"
  echo "1 error, 0 warnings"
  exit 1
fi

records=$(jq -r --slurpfile schema "$schema" "$PROG" "$config" | LC_ALL=C sort)
if [ -n "$records" ]; then printf '%s\n' "$records" | cut -f3-; fi

e=0; w=0
if [ -n "$records" ]; then
  ranks=$(printf '%s\n' "$records" | cut -f2)
  e=$(printf '%s\n' "$ranks" | grep -c '^0$' || true)
  w=$(printf '%s\n' "$ranks" | grep -c '^1$' || true)
fi
if [ "$e" = 1 ]; then et="1 error"; else et="$e errors"; fi
if [ "$w" = 1 ]; then wt="1 warning"; else wt="$w warnings"; fi
echo "$et, $wt"

[ "$e" = 0 ] || exit 1
[ "$w" = 0 ] || [ "$strict" = 0 ] || exit 1
exit 0
