#!/usr/bin/env bash
# scripts/validate-config.sh - check a nightmill config against the schema.
#
#   validate-config.sh [--schema path] [--strict] [config]
#   validate-config.sh [--schema path] [--strict] --base
#
# config    the file to check (default: .claude/nightmill.json in the repository this script lives in)
# --base    check the configuration on the base branch of the current directory's repository instead of a file
#           (iteration 48, lib/baseconfig.sh): origin/HEAD, then git.baseBranch; the working tree's file only without
#           a remote-tracking branch or before the base branch has one (the fallback's line goes to standard error).
#           The header names the ref: validating origin/HEAD:.claude/nightmill.json against <schema>. A stop of the
#           rule (no origin/HEAD, no file on origin/<git.baseBranch>, not valid JSON) and a config argument exit 2.
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
# additionalProperties (a schema, true or false), enum, pattern and not (only as { "pattern": ... }; a search,
# case-sensitive, on string values; iteration 48). tests/lint.sh fails if the schema uses a keyword
# that is not on that list. After the walk it also checks that a reviewer role is not ranked below the role it
# reviews, by models.ranking (iteration 15; vpairs() in lib/validate.awk).
set -euo pipefail

usage() { echo "usage: validate-config.sh [--schema path] [--strict] [config | --base]" >&2; exit 2; }

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
config=""; schema=""; strict=0; base=0
while [ $# -gt 0 ]; do
  case "$1" in
    --schema) [ $# -ge 2 ] || usage; schema=$2; shift 2 ;;
    --strict) strict=1; shift ;;
    --base) base=1; shift ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *) [ -z "$config" ] || usage; config=$1; shift ;;
  esac
done
[ -n "$schema" ] || schema="$root/schema/nightmill.schema.json"
shown=""
# base_cfg_* are set by base_config (lib/baseconfig.sh)
# shellcheck disable=SC2154
if [ "$base" = 1 ]; then
  [ -z "$config" ] || usage
  top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "run validate-config.sh --base from inside a git checkout" >&2; exit 2; }
  # shellcheck source=scripts/lib/json.sh
  . "$root/scripts/lib/json.sh"
  # shellcheck source=scripts/lib/baseconfig.sh
  . "$root/scripts/lib/baseconfig.sh"
  base_config "$top" || { echo "$base_cfg_stop" >&2; exit 2; }
  [ -z "$base_cfg_note" ] || echo "$base_cfg_note" >&2
  config=$base_cfg_file
  if [ -n "$base_cfg_tmp" ]; then
    shown=$base_cfg_from
    trap 'rm -f "$base_cfg_tmp"' EXIT
  fi
fi
[ -n "$config" ] || config="$root/.claude/nightmill.json"
[ -n "$shown" ] || shown=$config

[ -f "$config" ] && [ -r "$config" ] || { echo "cannot read config: $config" >&2; exit 2; }
[ -f "$schema" ] && [ -r "$schema" ] || { echo "cannot read schema: $schema" >&2; exit 2; }

echo "validating $shown against $schema"

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
