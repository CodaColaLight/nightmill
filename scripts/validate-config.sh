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
# error or an unreadable file. Same behaviour and output as validate-config.ps1.
#
# Needs bash and awk, no jq: the work is done by lib/json.awk (a JSON parser) and lib/validate.awk (the walk
# of the schema). The validator supports type, properties, required, items, minimum, minItems,
# additionalProperties (a schema, true or false) and enum. tests/lint.sh fails if the schema uses a keyword
# that is not on that list.
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

[ -f "$config" ] && [ -r "$config" ] || { echo "cannot read config: $config" >&2; exit 2; }
[ -f "$schema" ] && [ -r "$schema" ] || { echo "cannot read schema: $schema" >&2; exit 2; }

echo "validating $config against $schema"

# One record per finding, "path TAB rank TAB line"; a schema that cannot be parsed is a usage error (exit 2).
records=$(VAL_CONFIG="$config" VAL_SCHEMA="$schema" LC_ALL=C awk -f "$root/scripts/lib/json.awk" -f "$root/scripts/lib/validate.awk") || exit 2
if [ -n "$records" ]; then records=$(printf '%s\n' "$records" | LC_ALL=C sort); fi

e=0; w=0
if [ -n "$records" ]; then
  printf '%s\n' "$records" | cut -f3-
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
