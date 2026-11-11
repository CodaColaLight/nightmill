#!/usr/bin/env bash
# scripts/gate.sh - may the next step start? The pause flag and the limits of a run (nightmill, iteration 53, #165).
# Bash twin of gate.ps1; the rules and the texts are in docs/specs/iteration-53-run-limits.md (decision 3).
#
#   gate.sh [--issue <n>] [--slot <s>] [--role <role> --turns <t>]
#   gate.sh -h | --help
#
# Run it from inside any checkout of the project. It reads the base branch's .claude/nightmill.json
# (scripts/lib/baseconfig.sh; limits, github.owner, github.repo, worktrees.root), the record
# <worktrees.root>/.slots/ledger.tsv, the clock (lib/ledger.sh; NIGHTMILL_CLOCK_FILE moves it in the tests), the
# environment variables NIGHTMILL_RUN_STARTED (seconds since 1970: the start of the driver's step) and
# NIGHTMILL_ISSUES_LEFT (the issues the driver run may still start), and with --issue one gh api graphql query (the
# issue's epic and its labels). It writes nothing, fetches nothing and changes nothing on GitHub.
# The checks, in this order; the first that holds prints its line and exits:
#   the config and its limits values (exit 2), limits.paused (exit 1), with --issue the label paused on the epic
#   (exit 4), the cost of the issue over the run lines of the ledger, its minutes in this run (exit 3), with --role
#   the turns of the role (exit 3); else the lines "gate: issues per run: <k>", with --issue
#   "gate: spent on #<n>: $<x> of $<l>", and "gate: go".
# Exit code 0 go, 1 the project is paused, 2 cannot check (also a usage error), 3 a limit is breached, 4 the issue's
# epic is paused.
set -uo pipefail

usage_line="usage: gate.sh [--issue <n>] [--slot <s>] [--role <role> --turns <t>]"
usage() { echo "$usage_line" >&2; exit 2; }

issue=""; slot=""; role=""; turns=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) echo "$usage_line"; exit 0 ;;
    --issue|--slot|--turns)
      [ $# -ge 2 ] || usage
      [[ "$2" =~ ^[1-9][0-9]{0,9}$ ]] || usage
      case "$1" in
        --issue) [ -z "$issue" ] || usage; issue=$2 ;;
        --slot) [ -z "$slot" ] || usage; slot=$2 ;;
        --turns) [ -z "$turns" ] || usage; turns=$2 ;;
      esac
      shift ;;
    --role)
      [ $# -ge 2 ] || usage
      [[ "$2" =~ ^[A-Za-z][A-Za-z0-9]{0,39}$ ]] || usage
      [ -z "$role" ] || usage
      role=$2
      shift ;;
    *) usage ;;
  esac
  shift
done
if [ -n "$role" ] && [ -z "$turns" ]; then usage; fi
if [ -z "$role" ] && [ -n "$turns" ]; then usage; fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/json.sh
. "$here/lib/json.sh"
# shellcheck source=scripts/lib/baseconfig.sh
. "$here/lib/baseconfig.sh"
# shellcheck source=scripts/lib/ledger.sh
. "$here/lib/ledger.sh"

tmpfiles=()
cleanup() { [ ${#tmpfiles[@]} -eq 0 ] || rm -f "${tmpfiles[@]}"; }
trap cleanup EXIT
cannot() { echo "gate: cannot check: $*" >&2; exit 2; }

# --- 1. the config ---
gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || cannot "run gate.sh from inside a git checkout of the project"
main=$(dirname "$gitdir")
base_config "$main" || cannot "$base_cfg_stop"
[ -z "$base_cfg_tmp" ] || tmpfiles+=("$base_cfg_tmp")
[ -z "$base_cfg_note" ] || echo "$base_cfg_note" >&2
[ -f "$base_cfg_file" ] || cannot "no $base_cfg_file (run /nightmill:init)"
if ! err=$(json_load "$base_cfg_file" 2>&1); then cannot "$err"; fi
json_load "$base_cfg_file"

# raw_of <path>: the kind and the value of a node, tab separated ("" when absent)
raw_of() {
  printf '%s\n' "$JSON_FLAT" | JSON_P=$1 LC_ALL=C awk -F '\t' '$1 == ENVIRON["JSON_P"] { r = $2 "\t" $3 } END { print r }'
}
# shown <kind> <value>: the value as JSON, for the line of a bad value
shown() {
  case "$1" in
    string) json_quote "$(printf '%b' "$2")" ;;
    null) printf 'null' ;;
    object) printf '{...}' ;;
    array) printf '[...]' ;;
    *) printf '%s' "$2" ;;
  esac
}
# whole <key> <lo> <hi> <default>: limits.<key> as a whole number in range, or the stop of decision 2
whole() {
  local r kind val
  r=$(raw_of "limits.$1")
  if [ -z "$r" ]; then printf '%s' "$4"; return 0; fi
  kind=${r%%$'\t'*}; val=${r#*$'\t'}
  if [ "$kind" = number ] && [[ "$val" =~ ^[0-9]{1,9}$ ]]; then
    val=$((10#$val))
    if [ "$val" -ge "$2" ] && [ "$val" -le "$3" ]; then printf '%s' "$val"; return 0; fi
  fi
  echo "gate: cannot check: limits.$1 must be a whole number from $2 to $3, got $(shown "$kind" "$val")" >&2
  return 1
}

r=$(raw_of limits.paused)
paused=false
if [ -n "$r" ]; then
  kind=${r%%$'\t'*}; val=${r#*$'\t'}
  [ "$kind" = boolean ] || cannot "limits.paused must be true or false, got $(shown "$kind" "$val")"
  paused=$val
fi
minutes=$(whole minutesPerIssue 1 1440 180) || exit 2
roles="session specWriter specReviewer tester implementer codeReviewer fixer worker"
role_limit=""
for rl in $roles; do
  case $rl in
    session) d=200 ;; specWriter) d=150 ;; specReviewer) d=80 ;; tester) d=150 ;;
    implementer) d=300 ;; codeReviewer) d=80 ;; fixer) d=200 ;; *) d=40 ;;
  esac
  v=$(whole "turnsPerRole.$rl" 1 10000 "$d") || exit 2
  [ "$rl" != "$role" ] || role_limit=$v
done
per_run=$(whole issuesPerRun 1 100 10) || exit 2
cost=25
r=$(raw_of limits.costPerIssueUsd)
if [ -n "$r" ]; then
  kind=${r%%$'\t'*}; val=${r#*$'\t'}
  if [ "$kind" = number ] && LC_ALL=C awk -v x="$val" 'BEGIN { exit !(x + 0 >= 0.01 && x + 0 <= 10000) }'; then cost=$val
  else cannot "limits.costPerIssueUsd must be a number from 0.01 to 10000, got $(shown "$kind" "$val")"; fi
fi
money() { LC_ALL=C awk -v x="$1" 'BEGIN { printf "%.2f", x }'; }

# --- 3. the project pause ---
if [ "$paused" = true ]; then echo "gate: paused: limits.paused is true on $base_cfg_from"; exit 1; fi

owner=$(json_get github.owner); repo=$(json_get github.repo)
root_rel=$(json_get worktrees.root); root_rel=${root_rel:-"../$(basename "$main")-wt"}
if [ -d "$main/$root_rel" ]; then root=$(cd "$main/$root_rel" && pwd); else root="$main/$root_rel"; fi
record="$root/.slots/ledger.tsv"
[ -f "$record" ] && [ -r "$record" ] || record=""

if [ -n "$issue" ]; then
  # --- 4. the epic pause ---
  { [ -n "$owner" ] && [ -n "$repo" ]; } || cannot "the epic of #$issue could not be read: github.owner and github.repo are needed in $base_cfg_from"
  out=$(mktemp "${TMPDIR:-/tmp}/nightmill-gate.XXXXXX") || cannot "cannot make a temporary file"
  tmpfiles+=("$out")
  q="query { repository(owner: \"$owner\", name: \"$repo\") { issue(number: $issue) { parent { number labels(first: 100) { nodes { name } } } } } }"
  if ! gh api graphql -f query="$q" > "$out" 2> "$out.err"; then
    tmpfiles+=("$out.err")
    why=$(tr '\r\n' '  ' < "$out.err" | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//')
    cannot "the epic of #$issue could not be read: ${why:-gh api graphql failed}"
  fi
  tmpfiles+=("$out.err")
  if ! flat=$(JSON_MODE=flat JSON_FILE="$out" LC_ALL=C awk -f "$JSON_LIB_DIR/json.awk" 2>/dev/null); then
    cannot "the epic of #$issue could not be read: gh api graphql gave no valid JSON"
  fi
  epic=$(printf '%s\n' "$flat" | LC_ALL=C awk -F '\t' '
    $1 == "data.repository.issue.parent.number" { n = $3 }
    $1 ~ /^data\.repository\.issue\.parent\.labels\.nodes\[[0-9]+\]\.name$/ && $3 == "paused" { p = 1 }
    END { if (n != "" && p) print n }')
  if [ -n "$epic" ]; then echo "gate: paused: epic #$epic has the label paused"; exit 4; fi

  # --- 5. the cost per issue ---
  spent=0
  if [ -n "$record" ]; then
    spent=$(LC_ALL=C awk -F '\t' -v n="$issue" '
      $1 == "run" && $6 != "" {
        c = split($6, l, ",")
        for (i = 1; i <= c; i++) if (l[i] == n) { s += ($10 + 0) / c; break }
      }
      END { printf "%.6f", s + 0 }' "$record")
  fi
  if LC_ALL=C awk -v s="$spent" -v l="$cost" 'BEGIN { exit !(s + 0 >= l - 0.0000001) }'; then
    echo "gate: limit: #$issue has spent \$$(money "$spent") in headless runs; the limit is \$$(money "$cost") (limits.costPerIssueUsd)"
    exit 3
  fi

  # --- 6. the minutes per issue ---
  start=""
  if [ -n "$slot" ] && [ -n "$record" ]; then
    claim=$(LC_ALL=C awk -F '\t' -v s="$slot" '$1 == "take" && $3 == s && $9 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/ { c = $9 } END { print c }' "$record")
    [ -z "$claim" ] || start=$(ledger_epoch "$claim")
  fi
  rs=${NIGHTMILL_RUN_STARTED:-}
  if [[ "$rs" =~ ^[0-9]{1,12}$ ]]; then
    rs=$((10#$rs))
    if [ -z "$start" ] || [ "$rs" -gt "$start" ]; then start=$rs; fi
  fi
  if [ -z "$start" ]; then
    echo "gate: minutes per issue not measured (no slot and no driver run)" >&2
  else
    ledger_clock
    # ledger_s is set by ledger_clock (lib/ledger.sh)
    # shellcheck disable=SC2154
    el=$(( (ledger_s - start) / 60 )); [ "$el" -ge 0 ] || el=0
    if [ "$el" -ge "$minutes" ]; then
      echo "gate: limit: #$issue has been worked on for $el minutes in this run; the limit is $minutes (limits.minutesPerIssue)"
      exit 3
    fi
  fi
fi

# --- 7. the turns per role ---
if [ -n "$role" ]; then
  [ -n "$role_limit" ] || cannot "unknown role $role"
  if [ "$turns" -gt "$role_limit" ]; then
    echo "gate: limit: the $role role took $turns turns; the limit is $role_limit (limits.turnsPerRole.$role)"
    exit 3
  fi
fi

# --- 8. go ---
k=$per_run
left=${NIGHTMILL_ISSUES_LEFT:-}
if [[ "$left" =~ ^[0-9]{1,9}$ ]] && [ "$((10#$left))" -lt "$per_run" ]; then k=$((10#$left)); fi
echo "gate: issues per run: $k"
[ -z "$issue" ] || echo "gate: spent on #$issue: \$$(money "$spent") of \$$(money "$cost")"
echo "gate: go"
exit 0
