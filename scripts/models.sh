#!/usr/bin/env bash
# scripts/models.sh - one table of the model of every agent role (nightmill).
#
#   models.sh [--config path] [--schema path]
#
# Prints one row per role: what it does, the model it runs on, whether that model comes from the config or from the
# default of the schema, its rank in models.ranking and whether its pairing holds (a reviewer must rank at least as
# high as each role it reviews), then the ranking, a summary line and, when the config sets nothing, a line that
# says so. It only reads. The texts and the rules are in docs/specs/iteration-16-models-command.md; models.ps1
# prints the same.
# --config  the file to read (default: .claude/nightmill.json of the main checkout, found with
#           git rev-parse --git-common-dir, so it works from any worktree of the project)
# --schema  the schema for the defaults (default: schema/nightmill.schema.json of this plugin)
# Needs bash and awk, no jq: the work is done by lib/json.awk (a JSON parser) and lib/models.awk. Git is needed only
# to find the default config. Exit code 0 when the table was printed (a flag in it does not change that), 2 for a
# usage error, an unknown option, a missing or unreadable config or schema, a config that is not a JSON object, or a
# call outside a git checkout without --config.
set -euo pipefail

usage() { echo "usage: models.sh [--config path] [--schema path]" >&2; exit 2; }
die() { echo "models.sh: $*" >&2; exit 2; }

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
config=""; schema=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config) [ $# -ge 2 ] || usage; config=$2; shift 2 ;;
    --schema) [ $# -ge 2 ] || usage; schema=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done

if [ -z "$config" ]; then
  gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "run models.sh from inside a checkout of the project (or pass --config)"
  config="$(dirname "$gitdir")/.claude/nightmill.json"
  [ -f "$config" ] || die "no $config (run /nightmill:init)"
fi
[ -n "$schema" ] || schema="$here/../schema/nightmill.schema.json"

[ -f "$config" ] && [ -r "$config" ] || die "cannot read config: $config"
[ -f "$schema" ] && [ -r "$schema" ] || die "cannot read schema: $schema"

MOD_CONFIG="$config" MOD_SCHEMA="$schema" LC_ALL=C awk -f "$here/lib/json.awk" -f "$here/lib/models.awk" || exit 2
