#!/usr/bin/env bash
# scripts/slot.sh - permanent worktrees, one per worker slot (nightmill). Bash twin of slot.ps1.
#   slot.sh --status [--porcelain]      # --porcelain: one tab separated line per slot, for scripts
#   slot.sh --take feat/foo [--slot 2] [--base origin/main] [--skip-warmup]
#   slot.sh --release 1                 # after the PR merged
#   slot.sh --abandon 1                 # free a slot whose task was dropped (no merged PR)
#   slot.sh --reap                      # free every busy slot whose PR has merged (--take does this first)
#   slot.sh --capacity [--slot-count N] [--agent-limit M] [--porcelain]   # show or set the numbers for the session
#   slot.sh --capacity --clear          # back to the configuration's numbers
#   slot.sh --report <step> --slot N --skill <skill> --role <role>   # record what the slot's agent is doing
# Needs git and (for --release and --reap) gh. Run it from inside the project: any checkout or worktree of
# it. Configuration comes from .claude/nightmill.json on the base branch (origin/HEAD, then git.baseBranch; lib/baseconfig.sh,
# iteration 48), the working tree's file of the main checkout only without a remote branch, keys under "worktrees"
# (see schema/nightmill.schema.json); WORKER_SLOTS overrides worktrees.slots. A slot is never removed:
# a new task only switches it to a new branch from the base branch, so build output stays warm.
# A slot is busy from --take to --release, --abandon or an automatic release (a marker file in
# <root>/.slots) (a take's claim counts as busy). Slot N gets port base + N.
# Automatic release (--reap, and the first step of every --take; iteration 17): a busy slot is freed when its
# worktree is clean and gh lists a merged PR for its branch whose last commit is the tip of the local branch
# (so a reused branch name or work after the merge keeps the slot busy and nothing is deleted). A slot that
# cannot be judged (gh missing or failing, no fetch) stays busy and a note goes to standard error; the freeing
# never makes a take fail. Same behaviour as slot.ps1 (-Reap).
# Capacity (--capacity; iteration 22): the slot count and the agent limit can be set during a session. The set
# values are kept in <root>/.slots/capacity.json (untracked, shared by every worktree) until --capacity --clear
# or until set again; the tracked config is never edited. Slot count: the live value, then WORKER_SLOTS, then
# worktrees.slots, then 2. Agent limit: the live value, then parallel.maxAgents, then 2. A busy slot above a
# lowered count is retiring: it is no longer handed out, is never touched, and is no longer listed once released.
# Same behaviour as slot.ps1 (-Capacity).
# Reports (--report; iteration 23): a skill that works in a slot writes its skill, its role, the current step and the
# time of the report into the slot's marker (the keys skill, role, step, reported after slot, branch, since).
# --status --porcelain prints them with the agent state: running while the last report is at most
# worktrees.stalledAfterMinutes (default 30) old, stalled after that, unknown without a report. The take does not
# report. Same behaviour as slot.ps1 (-Report).
# Claim (iteration 34): a take claims its slot before it fetches, switches or warms up: it writes a marker with
# "state": "taking" and its process id ("pid") and gives it the marker's name only if no marker exists (bash ln,
# PowerShell File.Move), so two takes never get the same slot; the finished take replaces it with the marker above.
# A failed fetch, switch or warm-up puts the slot back, removes the claim and prints "<step> failed (exit N)". A
# claim whose process has ended is dead: --status shows take-died, and only --abandon frees it. Same behaviour as
# slot.ps1.
# Retries (iteration 35): the take's own marker changes (the move of the finished marker over its claim, the
# rewrite of a claim it leaves behind and the removal of its claim) are tried up to 21 times, 0.25 s apart (at most
# 5 s of waiting), because on Windows a reader that holds the marker open makes them fail for a moment. Nothing is
# printed between tries; only the last try's error is. The publish of the claim is tried once. Same behaviour as
# slot.ps1.
# Interruption (iteration 36): a take stopped by INT (Ctrl+C) or TERM after it has claimed its slot runs the same
# restore as a failed step, prints "<step> interrupted (INT)" or "(TERM)" with the outcome and exits 130 or 143.
# Stopped while it writes its finished marker, it leaves its claim without the process id; --abandon frees it. A
# second signal does not stop a restore. A signal sent with kill to the take alone waits for the running command. A
# take killed without a chance to clean up (KILL, a closed window) leaves a claim that is dead once its process has
# ended. Same behaviour as slot.ps1, which prints "<step> stopped" and cannot set the exit code.
# Record (iteration 41): the take, every report and every freeing append one line to <root>/.slots/ledger.tsv (see
# scripts/stages.sh); a failed append prints one note and changes nothing else. Same behaviour as slot.ps1.
set -euo pipefail

usage() {
  echo "usage: slot.sh --status | --take <branch> [--slot N] [--base <ref>] [--skip-warmup] | --release N | --abandon N | --reap | --capacity [--slot-count N] [--agent-limit M] [--clear] [--porcelain] | --report <step> --slot N --skill <s> --role <r>" >&2
  exit 1
}

take=""; release=0; abandon=0; status=0; slot=0; base=""; skip=0; porcelain=0; reap=0
capacity=0; clear=0; set_slots=""; set_agents=""; has_slots=0; has_agents=0
report=""; has_report=0; skill=""; has_skill=0; role=""; has_role=0
while [ $# -gt 0 ]; do
  case "$1" in
    --report) [ $# -ge 2 ] || usage; report=$2; has_report=1; shift ;;
    --skill) [ $# -ge 2 ] || usage; skill=$2; has_skill=1; shift ;;
    --role) [ $# -ge 2 ] || usage; role=$2; has_role=1; shift ;;
    --reap) reap=1 ;;
    --capacity) capacity=1 ;;
    --clear) clear=1 ;;
    --slot-count) { [ $# -ge 2 ] && [ "$has_slots" = 0 ]; } || usage; set_slots=$2; has_slots=1; shift ;;
    --agent-limit) { [ $# -ge 2 ] && [ "$has_agents" = 0 ]; } || usage; set_agents=$2; has_agents=1; shift ;;
    --status) status=1 ;;
    --porcelain) porcelain=1 ;;
    --take) take=${2:?--take needs a branch}; shift ;;
    --slot) [[ "${2:-}" =~ ^[0-9]+$ ]] || usage; slot=$((10#$2)); shift ;;
    --base) base=${2:?}; shift ;;
    --skip-warmup) skip=1 ;;
    --release) [[ "${2:-}" =~ ^[0-9]+$ ]] || usage; release=$((10#$2)); shift ;;
    --abandon) [[ "${2:-}" =~ ^[0-9]+$ ]] || usage; abandon=$((10#$2)); shift ;;
    *) usage ;;
  esac
  shift
done
if [ "$has_report" = 1 ]; then
  { [ -z "$take" ] && [ "$release" = 0 ] && [ "$abandon" = 0 ] && [ "$reap" = 0 ] && [ "$status" = 0 ] && [ "$capacity" = 0 ]; } || usage
elif [ "$has_skill" = 1 ] || [ "$has_role" = 1 ]; then
  usage
fi

. "$(dirname "${BASH_SOURCE[0]}")/lib/json.sh"
. "$(dirname "${BASH_SOURCE[0]}")/lib/ledger.sh"
. "$(dirname "${BASH_SOURCE[0]}")/lib/baseconfig.sh"

gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "run slot.sh from inside a git checkout of the project" >&2; exit 1; }
main=$(dirname "$gitdir")
# The configuration is the one on the base branch (iteration 48, lib/baseconfig.sh): origin/HEAD, then git.baseBranch;
# the working tree's file only without a remote-tracking branch or before the base branch has one.
# base_cfg_* are set by base_config (lib/baseconfig.sh)
# shellcheck disable=SC2154
{
  base_config "$main" || { echo "$base_cfg_stop" >&2; exit 1; }
  [ -z "$base_cfg_note" ] || echo "$base_cfg_note" >&2
  cfg=$base_cfg_file
  [ -f "$cfg" ] || { echo "no $cfg (run /nightmill:init)" >&2; exit 1; }
  if [ -n "$base_cfg_tmp" ]; then
    json_load "$cfg" || { rm -f "$base_cfg_tmp"; exit 1; }
    rm -f "$base_cfg_tmp"
  else
    json_load "$cfg" || exit 1
  fi
}

q() { json_get "$1"; }

base_branch=$(q git.baseBranch); base_branch=${base_branch:-main}
[ -n "$base" ] || base="origin/$base_branch"
root_rel=$(q worktrees.root); root_rel=${root_rel:-"../$(basename "$main")-wt"}
mkdir -p "$main/$root_rel"
root=$(cd "$main/$root_rel" && pwd)
state="$root/.slots"
ledger="$state/ledger.tsv"
# record <kind> <slot> <branch> <name> <skill> <role> <pr> <from> <to> <issues>: one line of the record, stamped now
record() {
  ledger_clock
  # ledger_s is set by ledger_clock (lib/ledger.sh)
  # shellcheck disable=SC2154
  ledger_append "$ledger" "$1" "$(ledger_stamp "$ledger_s")" "${@:2}"
}
# pr_times FLAT PREFIX: the createdAt, mergedAt and closing issue numbers (joined by ,) of the PR at PREFIX ([0]) of
# gh's flat JSON, separated by the unit separator (\037, so that empty fields stay); empty fields when absent
pr_times() {
  printf '%s\n' "$1" | LC_ALL=C awk -F '\t' -v p="$2" '
    $1 == p ".createdAt" && $2 == "string" { c = $3 }
    $1 == p ".mergedAt" && $2 == "string" { m = $3 }
    index($1, p ".closingIssuesReferences[") == 1 && $1 ~ /\]\.number$/ && $2 == "number" {
      rest = substr($1, length(p ".closingIssuesReferences[") + 1)
      if (rest ~ /^[0-9]+\]\.number$/) i = i (i == "" ? "" : ",") $3
    }
    END { printf "%s\037%s\037%s", c, m, i }'
}

if [ -n "${WORKER_SLOTS:-}" ]; then
  [[ "$WORKER_SLOTS" =~ ^[1-9][0-9]?$ ]] || { echo "WORKER_SLOTS must be a number from 1 to 99" >&2; exit 1; }
fi

# The numbers: what the configuration alone gives, and the effective ones (see the header)
cap="$state/capacity.json"
cfg_slots=$(q worktrees.slots); cfg_slots_from=config
if [ -z "$cfg_slots" ]; then cfg_slots=2; cfg_slots_from=default; fi
cfg_agents=$(q parallel.maxAgents); cfg_agents_from=config
if [ -z "$cfg_agents" ]; then cfg_agents=2; cfg_agents_from=default; fi
valid_n() { [[ "$1" =~ ^[1-9][0-9]?$ ]]; }

# read_capacity: the usable values of capacity.json in live_slots and live_agents (empty when not set); an unusable
# file or value is ignored, with one note on standard error
read_capacity() {
  local flat k rec kind val reason=""
  live_slots=""; live_agents=""
  [ -f "$cap" ] || return 0
  if ! flat=$(JSON_MODE=flat JSON_FILE="$cap" LC_ALL=C awk -f "$JSON_LIB_DIR/json.awk" 2>/dev/null); then
    echo "slot: capacity.json: not valid JSON; using the configuration" >&2; return 0
  fi
  rec=${flat%%$'\n'*}
  if [ "$(printf '%s\n' "$rec" | cut -f2)" != object ]; then
    echo "slot: capacity.json: not an object; using the configuration" >&2; return 0
  fi
  for k in slots maxAgents; do
    rec=$(printf '%s\n' "$flat" | K=$k LC_ALL=C awk -F '\t' '$1 == ENVIRON["K"] { print $2 "\t" $3 }')
    [ -n "$rec" ] || continue
    kind=${rec%%$'\t'*}; val=${rec#*$'\t'}
    if [ "$kind" = number ] && valid_n "$val"; then
      if [ "$k" = slots ]; then live_slots=$val; else live_agents=$val; fi
    else
      reason="${reason:+$reason, }$k is not a whole number from 1 to 99"
    fi
  done
  if [ -n "$reason" ]; then echo "slot: capacity.json: $reason; using the configuration" >&2; fi
  return 0
}

# resolve: count and slots_from, agents and agents_from, from the live values, WORKER_SLOTS and the configuration
resolve() {
  if [ -n "$live_slots" ]; then count=$live_slots; slots_from=live
  elif [ -n "${WORKER_SLOTS:-}" ]; then count=$WORKER_SLOTS; slots_from=WORKER_SLOTS
  else count=$cfg_slots; slots_from=$cfg_slots_from; fi
  if [ -n "$live_agents" ]; then agents=$live_agents; agents_from=live
  else agents=$cfg_agents; agents_from=$cfg_agents_from; fi
}
# from <source> <value of the configuration alone>: the text in brackets
from() { case "$1" in live|WORKER_SLOTS) echo "$1; config $2" ;; *) echo "$1" ;; esac; }

read_capacity
resolve

# last_slot: the last slot to list or reap: the count, or a higher slot that is busy (retiring)
last_slot() {
  local f n top=$count
  for f in "$state"/slot-*.json; do
    [ -e "$f" ] || continue
    n=${f##*/slot-}; n=${n%.json}
    if [[ "$n" =~ ^[1-9][0-9]*$ ]] && [ "$n" -gt "$top" ]; then top=$n; fi
  done
  echo "$top"
}

slot_dir() { echo "$root/slot-$1"; }
marker() { echo "$state/slot-$1.json"; }
has_marker() { [ -f "$(marker "$1")" ]; }
marker_field() { ( json_load "$(marker "$1")" && json_get "$2" ); }
# marker_fields N: branch, since, skill, role, step, reported, state and pid of the marker, separated by the unit
# separator (\037, not whitespace, so that empty fields stay); empty when absent
marker_fields() {
  ( json_load "$(marker "$1")" || exit 0
    printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s' "$(json_get branch)" "$(json_get since)" "$(json_get skill)" "$(json_get role)" \
      "$(json_get step)" "$(json_get reported)" "$(json_get state)" "$(json_get pid)" )
}
# my_pid: the process id a claim records: the Windows id where there is one (Git for Windows, MSYS2, Cygwin), else $$
my_pid() { if [ -r "/proc/$$/winpid" ]; then cat "/proc/$$/winpid"; else echo "$$"; fi; }
# pid_alive PID: exit 0 while a process with that id runs on this machine; live when nothing can tell
pid_alive() {
  if [ -r "/proc/$$/winpid" ]; then /usr/bin/kill -0 -W "$1" >/dev/null 2>&1; return; fi
  if [ -d /proc/self ]; then [ -d "/proc/$1" ]; return; fi
  if command -v ps >/dev/null 2>&1; then ps -p "$1" >/dev/null 2>&1; return; fi
  return 0
}
# claim_from STATE PID: sets claim (none for a finished marker, live or dead for a taking one) and claim_pid (the
# usable pid, 1 to 2147483647, or empty)
claim_from() {
  claim=none; claim_pid=""
  [ "$1" = taking ] || return 0
  if [[ "$2" =~ ^[1-9][0-9]{0,9}$ ]] && [ "$2" -le 2147483647 ]; then claim_pid=$2; fi
  if [ -n "$claim_pid" ] && pid_alive "$claim_pid"; then claim=live; else claim=dead; fi
}
# claim_of N: claim and claim_pid of slot N's marker (none without a marker)
claim_of() {
  local f st="" p=""
  claim=none; claim_pid=""
  has_marker "$1" || return 0
  f=$(marker_fields "$1" 2>/dev/null)
  IFS=$'\037' read -r _ _ _ _ _ _ st p <<<"$f" || true
  claim_from "$st" "$p"
}
# claim_line N: the refusal of a command on a taking slot (decision 7 of iteration 34)
claim_line() {
  if [ "$claim" = live ]; then echo "slot $1 is being taken (process $claim_pid is still running); wait for the take to end"
  elif [ -n "$claim_pid" ]; then echo "slot $1 has a take that did not finish (process $claim_pid has ended); free it with --abandon $1"
  else echo "slot $1 has a take that did not finish (no process recorded); free it with --abandon $1"; fi
}
is_stamp() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; }
# epoch_of YYYY-MM-DDTHH:MM:SS: seconds since 1970 with the time read as UTC, the arithmetic of stamp in lib/status.awk
epoch_of() {
  local s=$1 y m d era yoe doy doe
  y=$((10#${s:0:4})); m=$((10#${s:5:2})); d=$((10#${s:8:2}))
  if [ "$m" -le 2 ]; then y=$((y - 1)); fi
  era=$(( (y >= 0 ? y : y - 399) / 400 ))
  yoe=$((y - era * 400))
  doy=$(( (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1 ))
  doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  echo $(( (era * 146097 + doe - 719468) * 86400 + 10#${s:11:2} * 3600 + 10#${s:14:2} * 60 + 10#${s:17:2} ))
}
# stalled_after: the threshold in minutes, worktrees.stalledAfterMinutes or 30 (an unusable value with one note)
stalled_after() {
  local rec kind val
  rec=$(printf '%s\n' "$JSON_FLAT" | LC_ALL=C awk -F '\t' '$1 == "worktrees.stalledAfterMinutes" { print $2 "\t" $3 }')
  kind=${rec%%$'\t'*}; val=${rec#*$'\t'}
  if [ -z "$rec" ] || [ "$kind" = null ]; then echo 30; return 0; fi
  if [ "$kind" = number ] && [[ "$val" =~ ^[1-9][0-9]{0,5}$ ]]; then echo "$val"; return 0; fi
  echo "slot: worktrees.stalledAfterMinutes must be a whole number of at least 1; using 30" >&2
  echo 30
}
dirty_count() { git -C "$1" status --porcelain | wc -l | tr -d ' '; }
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

freed=0
# reap_all: free every busy slot whose PR has merged (see the header); prints one line per freed slot
reap_all() {
  local n dir branch tip tmpf errf flat pr prkey pr_from pr_to pr_issues fetched=0 freason ferr top
  top=$(last_slot)
  for ((n = 1; n <= top; n++)); do
    has_marker "$n" || continue
    # a take's claim (live or dead) is never judged, freed or switched
    if [ "$(marker_field "$n" state 2>/dev/null)" = taking ]; then continue; fi
    dir=$(slot_dir "$n")
    [ -d "$dir" ] || continue
    [ "$(dirty_count "$dir")" -eq 0 ] || continue
    branch=$(marker_field "$n" branch)
    [ -n "$branch" ] || continue
    tip=$(git -C "$dir" rev-parse "refs/heads/$branch" 2>/dev/null) || continue
    if ! command -v gh >/dev/null 2>&1; then
      echo "slot $n: not checked for a merged PR (gh is not on the PATH)" >&2; continue
    fi
    tmpf=$(mktemp "${TMPDIR:-/tmp}/nightmill-slot.XXXXXX"); errf=$(mktemp "${TMPDIR:-/tmp}/nightmill-slot.XXXXXX")
    if ! gh pr list --state merged --head "$branch" --json number,headRefOid,createdAt,mergedAt,closingIssuesReferences > "$tmpf" 2> "$errf"; then
      echo "slot $n: not checked for a merged PR ($(head -n 1 "$errf"))" >&2
      rm -f "$tmpf" "$errf"; continue
    fi
    if ! flat=$(JSON_MODE=flat JSON_FILE="$tmpf" LC_ALL=C awk -f "$JSON_LIB_DIR/json.awk" 2>/dev/null); then
      echo "slot $n: not checked for a merged PR (gh did not answer with JSON)" >&2
      rm -f "$tmpf" "$errf"; continue
    fi
    rm -f "$tmpf" "$errf"
    # the first merged PR, in the order gh printed them, whose head commit is the tip of the local branch
    pr=$(printf '%s\n' "$flat" | LC_ALL=C awk -F '\t' -v tip="$tip" '
      $1 ~ /^\[[0-9]+\]\.number$/ { k = $1; sub(/\]\.number$/, "", k); num[k] = $3 }
      $1 ~ /^\[[0-9]+\]\.headRefOid$/ { k = $1; sub(/\]\.headRefOid$/, "", k); oid[k] = $3; order[++cnt] = k }
      END { for (i = 1; i <= cnt; i++) if (oid[order[i]] == tip) { print order[i] "]\t" num[order[i]]; exit } }')
    [ -n "$pr" ] || continue
    prkey=${pr%%$'\t'*}; pr=${pr#*$'\t'}
    if [ "$fetched" = 0 ]; then
      if ferr=$(git fetch origin "$base_branch" 2>&1); then fetched=1; else fetched=-1; freason=$(printf '%s\n' "$ferr" | head -n 1); fi
    fi
    if [ "$fetched" != 1 ]; then
      echo "slot $n: not checked for a merged PR (git fetch origin $base_branch failed: $freason)" >&2; continue
    fi
    git -C "$dir" switch --detach "origin/$base_branch" >/dev/null 2>&1 || continue
    git branch -D "$branch" >/dev/null 2>&1 || true
    rm -f "$(marker "$n")"
    IFS=$'\037' read -r pr_from pr_to pr_issues <<<"$(pr_times "$flat" "$prkey")" || true
    record free "$n" "$branch" reaped "" "" "$pr" "$pr_from" "$pr_to" "$pr_issues"
    echo "Slot $n is free (was $branch, PR #$pr), released automatically."
    freed=$((freed + 1))
  done
}

# warmup <slot> <dir>: runs the warm-up commands; on a failure returns 1 with the failing command's number in
# warm_idx and its exit code in warm_code (the hash of the lockfile, the read and the write of the stamp belong to
# the command)
warmup() {
  local n=$1 dir=$2 i=0 idx count where d cmd lf stamp hash have c
  warm_idx=0; warm_code=0
  [ "$skip" = 1 ] && return 0
  count=$(json_len worktrees.warmup)
  for ((idx = 0; idx < count; idx++)); do
    i=$((i + 1))
    take_step="warm-up $i"
    where="$dir"
    d=$(json_get "worktrees.warmup[$idx].dir")
    if [ -n "$d" ]; then where="$dir/$d"; fi
    cmd=$(json_get "worktrees.warmup[$idx].command")
    lf=$(json_get "worktrees.warmup[$idx].lockfile")
    stamp="$state/slot-$n.warmup-$i"
    hash=""
    if [ -n "$lf" ] && [ -f "$dir/$lf" ]; then
      c=0; hash=$(sha256 "$dir/$lf") || c=$?
      if [ "$c" != 0 ]; then warm_idx=$i; warm_code=$c; return 1; fi
      have=""
      if [ -f "$stamp" ]; then
        c=0; have=$(cat "$stamp") || c=$?
        if [ "$c" != 0 ]; then warm_idx=$i; warm_code=$c; return 1; fi
      fi
      if [ "$have" = "$hash" ]; then continue; fi
    fi
    echo "warm-up $i in $where: $cmd"
    c=0; (cd "$where" && bash -c "$cmd") || c=$?
    if [ "$c" != 0 ]; then warm_idx=$i; warm_code=$c; return 1; fi
    if [ -n "$hash" ]; then
      c=0; echo "$hash" > "$stamp" || c=1
      if [ "$c" != 0 ]; then warm_idx=$i; warm_code=$c; return 1; fi
    fi
  done
}

ports() { # key=value lines, in file order
  local k
  while IFS= read -r k; do
    if [ -n "$k" ]; then printf '%s=%s\n' "$k" "$(json_get "worktrees.ports.$k")"; fi
  done < <(json_keys worktrees.ports)
}

hints() { # slot dir branch
  local n=$1 dir=$2 branch=$3 line name p idx count
  echo
  echo "Slot $n is yours: $dir  (branch $branch)"
  echo "  cd '$dir'"
  while IFS='=' read -r name p; do
    [ -n "$name" ] && echo "  port $name: $((p + n))"
  done < <(ports)
  count=$(json_len worktrees.runHints)
  if [ "$count" -gt 0 ]; then
    echo "Run it next to other slots:"
    for ((idx = 0; idx < count; idx++)); do
      line=$(json_get "worktrees.runHints[$idx]")
      line=${line//\{slot\}/$n}
      while IFS='=' read -r name p; do
        [ -n "$name" ] && line=${line//\{port.$name\}/$((p + n))}
      done < <(ports)
      echo "  $line"
    done
  fi
}

if [ "$capacity" = 1 ]; then
  { [ -z "$take" ] && [ "$release" = 0 ] && [ "$abandon" = 0 ] && [ "$status" = 0 ] && [ "$reap" = 0 ]; } || usage
  if [ "$clear" = 1 ] && { [ "$has_slots" = 1 ] || [ "$has_agents" = 1 ]; }; then usage; fi
  bad=0
  if [ "$has_slots" = 1 ] && ! valid_n "$set_slots"; then
    echo "capacity: --slot-count must be a whole number from 1 to 99, got \"$set_slots\"" >&2; bad=1
  fi
  if [ "$has_agents" = 1 ] && ! valid_n "$set_agents"; then
    echo "capacity: --agent-limit must be a whole number from 1 to 99, got \"$set_agents\"" >&2; bad=1
  fi
  [ "$bad" = 0 ] || exit 1
  was_slots=$count; was_agents=$agents; msg=""
  if [ "$clear" = 1 ]; then
    if [ -f "$cap" ]; then
      rm -f "$cap"
      live_slots=""; live_agents=""; resolve
      msg="capacity: cleared (slots $was_slots -> $count, agents $was_agents -> $agents)"
    else
      msg="capacity: nothing to clear"
    fi
  elif [ "$has_slots" = 1 ] || [ "$has_agents" = 1 ]; then
    if [ "$has_slots" = 1 ]; then live_slots=$set_slots; fi
    if [ "$has_agents" = 1 ]; then live_agents=$set_agents; fi
    # written to a temporary file in the same folder and moved over the old one: a reader never sees half a file
    mkdir -p "$state"
    tmpf=$(mktemp "$state/capacity.json.XXXXXX")
    {
      printf '{\n'
      if [ -n "$live_slots" ]; then printf '  "slots": %s,\n' "$live_slots"; fi
      if [ -n "$live_agents" ]; then printf '  "maxAgents": %s,\n' "$live_agents"; fi
      printf '  "since": %s\n}\n' "$(json_quote "$(date +%Y-%m-%dT%H:%M:%S)")"
    } > "$tmpf"
    mv -f "$tmpf" "$cap"
    resolve
    change() { if [ "$2" = "$3" ]; then echo "$1 $3 (unchanged)"; else echo "$1 $2 -> $3"; fi; }
    msg="capacity: "
    if [ "$has_slots" = 1 ]; then msg="$msg$(change slots "$was_slots" "$count")"; fi
    if [ "$has_slots" = 1 ] && [ "$has_agents" = 1 ]; then msg="$msg, "; fi
    if [ "$has_agents" = 1 ]; then msg="$msg$(change agents "$was_agents" "$agents")"; fi
  fi
  if [ "$porcelain" = 1 ]; then
    printf 'slots\t%s\t%s\t%s\n' "$count" "$slots_from" "$cfg_slots"
    printf 'agents\t%s\t%s\t%s\n' "$agents" "$agents_from" "$cfg_agents"
  elif [ -n "$msg" ]; then
    echo "$msg"
  else
    echo "slots: $count ($(from "$slots_from" "$cfg_slots"))"
    echo "agents: $agents ($(from "$agents_from" "$cfg_agents"))"
  fi
  exit 0
fi
if [ "$clear" = 1 ] || [ "$has_slots" = 1 ] || [ "$has_agents" = 1 ]; then usage; fi

if [ "$has_report" = 1 ]; then
  # --report <step> --slot N --skill <skill> --role <role>: rewrite the marker of slot N with the report
  if ! [[ "$slot" =~ ^[0-9]+$ ]] || [ $((10#$slot)) = 0 ]; then echo "report needs a slot number" >&2; exit 1; fi
  n=$((10#$slot))
  has_marker "$n" || { echo "slot $n is not in use" >&2; exit 1; }
  claim_of "$n"
  if [ "$claim" != none ]; then claim_line "$n" >&2; exit 1; fi
  name_ok() { [[ "$1" =~ ^[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-]{0,39}$ ]]; }
  for what in step skill role; do
    case "$what" in step) v=$report ;; skill) v=$skill ;; role) v=$role ;; esac
    name_ok "$v" || { echo "report: the $what must be 1 to 40 letters, digits or -, got \"$v\"" >&2; exit 1; }
  done
  mk=$(marker "$n")
  json_load "$mk" 2>/dev/null || { echo "slot $n: the marker is not valid JSON" >&2; exit 1; }
  tmpr="$state/slot-$n.report.tmp"
  json_marker_report "$n" "$(json_get branch)" "$(json_get since)" "$skill" "$role" "$report" "$(date +%Y-%m-%dT%H:%M:%S)" > "$tmpr"
  # moved over the marker only while it still exists: a report never brings back a released slot
  if [ -f "$mk" ]; then
    mv -f "$tmpr" "$mk"
    record step "$n" "$(json_get branch)" "$report" "$skill" "$role" "" "" "" ""
  else
    rm -f "$tmpr"
  fi
  exit 0
fi

if [ "$status" = 1 ] && [ "$porcelain" = 1 ]; then
  # A free slot: <n> TAB free. A busy slot, ten fields: <n> TAB busy TAB <branch> TAB <since> TAB <retiring> TAB
  # <agent> TAB <skill> TAB <role> TAB <step> TAB <reported>; retiring for a busy slot above the count, else empty;
  # agent: running, stalled or unknown (see the header). A take's claim (iteration 34) is a busy line with the agent
  # unknown, empty skill, role and reported, and the step taking while its take runs or take-died once it has ended
  threshold=$(( $(stalled_after) * 60 ))
  if [ -n "${NIGHTMILL_NOW:-}" ]; then now=$NIGHTMILL_NOW; else now=$(epoch_of "$(date +%Y-%m-%dT%H:%M:%S)"); fi
  top=$(last_slot)
  for ((i = 1; i <= top; i++)); do
    if has_marker "$i"; then
      m_branch=""; m_since=""; m_skill=""; m_role=""; m_step=""; m_reported=""; m_state=""; m_pid=""
      IFS=$'\037' read -r m_branch m_since m_skill m_role m_step m_reported m_state m_pid <<<"$(marker_fields "$i")" || true
      claim_from "${m_state:-}" "${m_pid:-}"
      if [ "$claim" != none ]; then
        m_skill=""; m_role=""; m_reported=""
        if [ "$claim" = live ]; then m_step="taking"; else m_step="take-died"; fi
      fi
      retiring=""; if [ "$i" -gt "$count" ]; then retiring=retiring; fi
      agent=unknown
      if is_stamp "${m_reported:-}"; then
        age=$((now - $(epoch_of "$m_reported"))); if [ "$age" -lt 0 ]; then age=0; fi
        if [ "$age" -le "$threshold" ]; then agent=running; else agent=stalled; fi
      fi
      printf '%s\tbusy\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$i" "${m_branch:-}" "${m_since:-}" "$retiring" "$agent" \
        "${m_skill:-}" "${m_role:-}" "${m_step:-}" "${m_reported:-}"
    elif [ "$i" -le "$count" ]; then
      printf '%s\tfree\n' "$i"
    fi
  done
  exit 0
fi

if [ "$status" = 1 ]; then
  echo "slots = $count  root = $root"
  echo "capacity: slots $count ($(from "$slots_from" "$cfg_slots")), agents $agents ($(from "$agents_from" "$cfg_agents"))"
  top=$(last_slot)
  for ((i = 1; i <= top; i++)); do
    if [ "$i" -gt "$count" ] && ! has_marker "$i"; then continue; fi
    dir=$(slot_dir "$i")
    where="not created yet"; [ -d "$dir" ] && where="ready"
    busy="free"
    if has_marker "$i"; then
      claim_of "$i"
      case "$claim" in
        none) busy="busy: $(marker_field "$i" branch) since $(marker_field "$i" since)" ;;
        live) busy="taking: $(marker_field "$i" branch) since $(marker_field "$i" since) (process $claim_pid)" ;;
        *) if [ -n "$claim_pid" ]; then what="process $claim_pid has ended"; else what="no process recorded"; fi
           busy="taking: $(marker_field "$i" branch) since $(marker_field "$i" since) ($what; free it with --abandon $i)" ;;
      esac
    fi
    if [ "$i" -gt "$count" ]; then busy="$busy (retiring)"; fi
    dirty=""
    if [ -d "$dir" ]; then
      n=$(dirty_count "$dir")
      [ "$n" -gt 0 ] && dirty="  ($n uncommitted files)"
    fi
    printf 'slot %s  %-15s %s%s\n' "$i" "$where" "$busy" "$dirty"
  done
  exit 0
fi

if [ "$reap" = 1 ]; then
  mkdir -p "$state"
  reap_all
  [ "$freed" -gt 0 ] || echo "No slot freed."
  exit 0
fi

# claim_slot N: claims slot N for the take (see Claim in the header): the complete taking marker is written to a
# temporary file and given the marker's name only if no marker exists. Returns 1 when another take has the slot;
# exits 1 when the claim cannot be written or published.
claim_slot() {
  local n=$1 tmpc mk c=0 lerr g=0
  tmpc="$state/slot-$n.claim.$me.tmp"; mk=$(marker "$n")
  claim_since=$(date +%Y-%m-%dT%H:%M:%S)
  ledger_clock; claim_at=$ledger_s
  # what the interruption handler needs: the slot, the temporary file and the claim's text (decision 3 of iteration 36)
  claim_n=$n; claim_mk=$mk; claim_tmp=$tmpc
  claim_text=$(json_marker_taking "$n" "$take" "$claim_since" "$me")
  ( set -C; json_marker_taking "$n" "$take" "$claim_since" "$me" > "$tmpc" ) || c=$?
  if [ "$c" != 0 ]; then
    trap ':' INT TERM
    rm -f "$tmpc"
    echo "claim failed (exit $c); slot $n was not claimed" >&2; exit 1
  fi
  # for the tests only: hold every take here until the file exists (60 s at most)
  if [ -n "${NIGHTMILL_CLAIM_GATE:-}" ]; then
    while [ ! -e "$NIGHTMILL_CLAIM_GATE" ] && [ "$g" -lt 600 ]; do g=$((g + 1)); sleep 0.1; done
  fi
  if lerr=$(ln "$tmpc" "$mk" 2>&1); then
    # the second name may stay while a reader holds the marker open on Windows; no command reads it
    rm -f "$tmpc" || true
    return 0
  fi
  if [ -e "$mk" ]; then rm -f "$tmpc"; return 1; fi
  trap ':' INT TERM
  rm -f "$tmpc"
  echo "slot $n: could not claim ($(printf '%s\n' "$lerr" | head -n 1))" >&2; exit 1
}
# the take's own marker changes are tried this often, this many seconds apart (see Retries in the header)
marker_tries=21
marker_pause=0.25
# retry_marker <command> <args...>: runs the command until it succeeds, at most marker_tries times, marker_pause
# apart, printing nothing for a failed try; returns the last try's status and, on failure, writes its text to
# standard error
retry_marker() {
  local t=1 rc out
  while :; do
    rc=0; out=$("$@" 2>&1) || rc=$?
    [ "$rc" != 0 ] || return 0
    [ "$t" -lt "$marker_tries" ] || break
    t=$((t + 1)); sleep "$marker_pause"
  done
  [ -z "$out" ] || printf '%s\n' "$out" >&2
  return "$rc"
}
# leave_claim: the claim stays, rewritten without its pid, so that it is dead at once and --abandon frees it
leave_claim() {
  local tmpl="$state/slot-$n.left.$me.tmp"
  if ( set -C; json_marker_taking "$n" "$take" "$claim_since" > "$tmpl" ); then
    retry_marker mv -f "$tmpl" "$mk" || rm -f "$tmpl"
  else
    rm -f "$tmpl"
  fi
}
# restore_take <step> <code> [<signal>]: after a failed step, or with the signal after an interruption (iteration 36),
# put the slot back as it was and remove the claim; exits 1, or 130 for INT and 143 for TERM
restore_take() {
  trap ':' INT TERM
  local step=$1 code=$2 sig=${3:-} ok=1 cur_head cur_branch tip what rc=1
  what="failed (exit $code)"
  if [ -n "$sig" ]; then
    what="interrupted ($sig)"
    if [ "$sig" = TERM ]; then rc=143; else rc=130; fi
  fi
  if [ "$created" = 1 ]; then
    git worktree remove --force "$dir" || ok=0
  elif [ "$recorded" = 1 ]; then
    if [ "$(dirty_count "$dir")" -gt 0 ]; then
      echo "slot $n has uncommitted files: $dir (commit, stash or discard them first)" >&2; ok=0
    else
      cur_head=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || cur_head=""
      cur_branch=$(git -C "$dir" symbolic-ref -q --short HEAD 2>/dev/null) || cur_branch=""
      if [ "$cur_head" != "$old_head" ] || [ "$cur_branch" != "$old_branch" ]; then
        if [ -n "$old_branch" ]; then git -C "$dir" switch "$old_branch" || ok=0
        else git -C "$dir" switch --detach "$old_head" || ok=0; fi
      fi
    fi
  fi
  if [ "$ok" = 1 ] && [ "$recorded" = 1 ] && [ "$had_branch" = 0 ]; then
    tip=$(git -C "$main" rev-parse --verify -q "refs/heads/$take" 2>/dev/null) || tip=""
    if [ -n "$tip" ] && [ "$tip" = "$base_commit" ]; then git -C "$main" branch -D "$take" || ok=0; fi
  fi
  if [ "$ok" = 1 ]; then retry_marker rm -f "$mk" || ok=0; fi
  if [ "$ok" = 1 ]; then echo "$step $what; slot $n is free again" >&2; exit "$rc"; fi
  leave_claim
  echo "$step $what; slot $n could not be put back and stays claimed: free it with --abandon $n" >&2
  exit "$rc"
}
# own_claim: slot claim_n's marker holds byte for byte the claim this take wrote (decision 3 of iteration 36)
own_claim() {
  local cur
  [ -n "$claim_text" ] && [ -f "$claim_mk" ] || return 1
  cur=$(cat "$claim_mk" 2>/dev/null) || return 1
  [ "$cur" = "$claim_text" ]
}
# on_signal <INT|TERM>: the take was interrupted after the trap was set (see Interruption in the header)
on_signal() {
  trap ':' INT TERM
  local sig=$1 rc=130 what
  if [ "$sig" = TERM ]; then rc=143; fi
  what="interrupted ($sig)"
  if [ "$take_step" = "write marker" ]; then
    if own_claim; then
      rm -f "$state/slot-$n.take.tmp" || true
      leave_claim
      echo "write marker $what; slot $n stays claimed: free it with --abandon $n" >&2
    else
      echo "write marker $what; slot $n is taken (branch $take): free it with --abandon $n if it is not used" >&2
    fi
    exit "$rc"
  fi
  if ! own_claim; then
    if [ -n "$claim_tmp" ]; then rm -f "$claim_tmp" || true; fi
    echo "claim $what; no slot was claimed" >&2
    exit "$rc"
  fi
  n=$claim_n; mk=$claim_mk; dir=$(slot_dir "$n")
  # a worktree counts as created by the take when it did not exist before step 3 and exists now
  if [ "$had_dir" = 0 ] && [ -d "$dir" ]; then created=1; fi
  restore_take "$take_step" "" "$sig"
}
# finish_take: the finished marker over the claim, then the hints
finish_take() {
  local tmpt="$state/slot-$n.take.tmp" c=0
  json_marker "$n" "$take" "$(date +%Y-%m-%dT%H:%M:%S)" > "$tmpt" || c=$?
  if [ "$c" = 0 ]; then retry_marker mv -f "$tmpt" "$mk" || c=$?; fi
  if [ "$c" = 0 ]; then trap - INT TERM; fi
  if [ "$c" != 0 ]; then
    trap ':' INT TERM
    rm -f "$tmpt"
    leave_claim
    echo "write marker failed (exit $c); slot $n stays claimed: free it with --abandon $n" >&2; exit 1
  fi
  ledger_clock
  ledger_append "$ledger" take "$(ledger_stamp "$ledger_s")" "$n" "$take" take "" "" "" "$(ledger_stamp "$claim_at")" "$(ledger_stamp "$ledger_s")" ""
  hints "$n" "$dir" "$take"
}

if [ -n "$take" ]; then
  mkdir -p "$state"
  reap_all
  me=$(my_pid)
  claim_since=""
  n=$slot
  mk=""; dir=""
  created=0; recorded=0; old_head=""; old_branch=""; had_branch=1; base_commit=""
  # the interruption handler (iteration 36): armed from the first claim attempt to the finished marker
  claim_n=0; claim_mk=""; claim_tmp=""; claim_text=""; had_dir=""; take_step=claim
  trap 'on_signal INT' INT
  trap 'on_signal TERM' TERM
  # 1 pick and claim
  if [ "$n" = 0 ]; then
    for ((i = 1; i <= count; i++)); do
      has_marker "$i" && continue
      if claim_slot "$i"; then n=$i; break; fi
    done
    [ "$n" != 0 ] || { trap ':' INT TERM; echo "all $count slots are busy; see slot.sh --status" >&2; exit 1; }
  else
    { [ "$n" -ge 1 ] && [ "$n" -le "$count" ]; } || { trap ':' INT TERM; echo "slot must be 1..$count" >&2; exit 1; }
    if has_marker "$n"; then trap ':' INT TERM; echo "slot $n is busy" >&2; exit 1; fi
    claim_slot "$n" || { trap ':' INT TERM; echo "slot $n is busy" >&2; exit 1; }
  fi
  mk=$(marker "$n"); dir=$(slot_dir "$n")

  # 2 fetch, at most 3 attempts, 1 s apart
  take_step="git fetch"
  for attempt in 1 2 3; do
    c=0; git fetch origin "$base_branch" || c=$?
    if [ "$c" = 0 ]; then break; fi
    if [ "$attempt" -lt 3 ]; then sleep 1; fi
  done
  [ "$c" = 0 ] || restore_take "git fetch" "$c"

  # 3 the worktree
  take_step="git worktree add"
  if [ -d "$dir" ]; then had_dir=1; else had_dir=0; fi
  if [ ! -d "$dir" ]; then
    c=0; git worktree add --detach "$dir" "$base" || c=$?
    [ "$c" = 0 ] || restore_take "git worktree add" "$c"
    created=1
  elif [ "$(dirty_count "$dir")" -gt 0 ]; then
    trap ':' INT TERM
    retry_marker rm -f "$mk" || leave_claim
    echo "slot $n has uncommitted files; deal with them first: $dir" >&2; exit 1
  fi

  # 4 what the restore puts back
  take_step="git switch"
  c=0; old_head=$(git -C "$dir" rev-parse HEAD) || c=$?
  [ "$c" = 0 ] || restore_take "git switch" "$c"
  c=0; old_branch=$(git -C "$dir" symbolic-ref -q --short HEAD) || c=$?
  case "$c" in 0) ;; 1) old_branch="" ;; *) restore_take "git switch" "$c" ;; esac
  c=0; git -C "$dir" show-ref --verify --quiet "refs/heads/$take" || c=$?
  case "$c" in 0) had_branch=1 ;; 1) had_branch=0 ;; *) restore_take "git switch" "$c" ;; esac
  if [ "$had_branch" = 0 ]; then
    c=0; base_commit=$(git -C "$dir" rev-parse "$base^{commit}") || c=$?
    [ "$c" = 0 ] || restore_take "git switch" "$c"
  fi
  recorded=1

  # 5 switch
  c=0
  if [ "$had_branch" = 1 ]; then
    git -C "$dir" switch "$take" || c=$?
  else
    git -C "$dir" switch -c "$take" --no-track "$base" || c=$?
  fi
  [ "$c" = 0 ] || restore_take "git switch" "$c"

  # 6 warm-up
  warmup "$n" "$dir" || restore_take "warm-up $warm_idx" "$warm_code"

  # 7 finish
  take_step="write marker"
  finish_take
  exit 0
fi

if [ "$release" != 0 ]; then
  n=$release
  has_marker "$n" || { echo "slot $n is not in use" >&2; exit 1; }
  claim_of "$n"
  if [ "$claim" != none ]; then claim_line "$n" >&2; exit 1; fi
  dir=$(slot_dir "$n")
  branch=$(marker_field "$n" branch)
  [ "$(dirty_count "$dir")" -eq 0 ] || { echo "slot $n has uncommitted files: $dir" >&2; exit 1; }
  git fetch origin "$base_branch"
  prjson=$(gh pr list --state merged --head "$branch" --json number,createdAt,mergedAt,closingIssuesReferences)
  tmpf=$(mktemp "${TMPDIR:-/tmp}/nightmill-slot.XXXXXX"); printf '%s\n' "$prjson" > "$tmpf"
  flat=$(JSON_MODE=flat JSON_FILE="$tmpf" LC_ALL=C awk -f "$JSON_LIB_DIR/json.awk" 2>/dev/null) || flat=""
  rm -f "$tmpf"
  merged=$(printf '%s\n' "$flat" | LC_ALL=C awk -F '\t' '$1 == "[0].number" && $2 == "number" { print $3 }')
  [ -n "$merged" ] || { echo "no merged PR for $branch. Merge it first, or free the slot with --abandon $n." >&2; exit 1; }
  git -C "$dir" switch --detach "origin/$base_branch"
  git branch -D "$branch"
  rm -f "$(marker "$n")"
  IFS=$'\037' read -r pr_from pr_to pr_issues <<<"$(pr_times "$flat" "[0]")" || true
  record free "$n" "$branch" released "" "" "$merged" "$pr_from" "$pr_to" "$pr_issues"
  echo "Slot $n is free (was $branch, PR #$merged)."
  exit 0
fi

if [ "$abandon" != 0 ]; then
  n=$abandon
  has_marker "$n" || { echo "slot $n is not in use" >&2; exit 1; }
  claim_of "$n"
  if [ "$claim" = live ]; then claim_line "$n" >&2; exit 1; fi
  dir=$(slot_dir "$n")
  branch=$(marker_field "$n" branch)
  if [ "$claim" = dead ]; then
    # a take that did not finish: freed after the same checks, the local branch is kept
    if [ -d "$dir" ]; then
      [ "$(dirty_count "$dir")" -eq 0 ] || { echo "slot $n has uncommitted files: $dir (commit, stash or discard them first)" >&2; exit 1; }
      git -C "$dir" switch --detach "$base"
    fi
    rm -f "$(marker "$n")"
    echo "Slot $n is free (was $branch, a take that did not finish; the local branch is kept, delete it yourself if unwanted)."
    exit 0
  fi
  [ "$(dirty_count "$dir")" -eq 0 ] || { echo "slot $n has uncommitted files: $dir (commit, stash or discard them first)" >&2; exit 1; }
  git -C "$dir" switch --detach "$base"
  rm -f "$(marker "$n")"
  record free "$n" "$branch" abandoned "" "" "" "" "" ""
  echo "Slot $n is free (was $branch; the local branch is kept, delete it yourself if unwanted)."
  exit 0
fi

usage
