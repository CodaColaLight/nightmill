#!/usr/bin/env bash
# scripts/slot.sh - permanent worktrees, one per worker slot (nightmill). Bash twin of slot.ps1.
#   slot.sh --status [--porcelain]      # --porcelain: one tab separated line per slot, for scripts
#   slot.sh --take feat/foo [--slot 2] [--base origin/main] [--skip-warmup]
#   slot.sh --release 1                 # after the PR merged
#   slot.sh --abandon 1                 # free a slot whose task was dropped (no merged PR)
#   slot.sh --reap                      # free every busy slot whose PR has merged (--take does this first)
#   slot.sh --capacity [--slot-count N] [--agent-limit M] [--porcelain]   # show or set the numbers for the session
#   slot.sh --capacity --clear          # back to the configuration's numbers
# Needs git and (for --release and --reap) gh. Run it from inside the project: any checkout or worktree of
# it. Configuration comes from .claude/nightmill.json in the main checkout, keys under "worktrees"
# (see schema/nightmill.schema.json); WORKER_SLOTS overrides worktrees.slots. A slot is never removed:
# a new task only switches it to a new branch from the base branch, so build output stays warm.
# A slot is busy from --take to --release, --abandon or an automatic release (a marker file in
# <root>/.slots). Slot N gets port base + N.
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
set -euo pipefail

usage() {
  echo "usage: slot.sh --status | --take <branch> [--slot N] [--base <ref>] [--skip-warmup] | --release N | --abandon N | --reap | --capacity [--slot-count N] [--agent-limit M] [--clear] [--porcelain]" >&2
  exit 1
}

take=""; release=0; abandon=0; status=0; slot=0; base=""; skip=0; porcelain=0; reap=0
capacity=0; clear=0; set_slots=""; set_agents=""; has_slots=0; has_agents=0
while [ $# -gt 0 ]; do
  case "$1" in
    --reap) reap=1 ;;
    --capacity) capacity=1 ;;
    --clear) clear=1 ;;
    --slot-count) { [ $# -ge 2 ] && [ "$has_slots" = 0 ]; } || usage; set_slots=$2; has_slots=1; shift ;;
    --agent-limit) { [ $# -ge 2 ] && [ "$has_agents" = 0 ]; } || usage; set_agents=$2; has_agents=1; shift ;;
    --status) status=1 ;;
    --porcelain) porcelain=1 ;;
    --take) take=${2:?--take needs a branch}; shift ;;
    --slot) slot=${2:?}; shift ;;
    --base) base=${2:?}; shift ;;
    --skip-warmup) skip=1 ;;
    --release) release=${2:?}; shift ;;
    --abandon) abandon=${2:?}; shift ;;
    *) usage ;;
  esac
  shift
done

. "$(dirname "${BASH_SOURCE[0]}")/lib/json.sh"

gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "run slot.sh from inside a git checkout of the project" >&2; exit 1; }
main=$(dirname "$gitdir")
cfg="$main/.claude/nightmill.json"
[ -f "$cfg" ] || { echo "no $cfg (run /nightmill:init)" >&2; exit 1; }
json_load "$cfg" || exit 1

q() { json_get "$1"; }

base_branch=$(q git.baseBranch); base_branch=${base_branch:-main}
[ -n "$base" ] || base="origin/$base_branch"
root_rel=$(q worktrees.root); root_rel=${root_rel:-"../$(basename "$main")-wt"}
mkdir -p "$main/$root_rel"
root=$(cd "$main/$root_rel" && pwd)
state="$root/.slots"

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
dirty_count() { git -C "$1" status --porcelain | wc -l | tr -d ' '; }
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

freed=0
# reap_all: free every busy slot whose PR has merged (see the header); prints one line per freed slot
reap_all() {
  local n dir branch tip tmpf errf flat pr fetched=0 freason ferr top
  top=$(last_slot)
  for ((n = 1; n <= top; n++)); do
    has_marker "$n" || continue
    dir=$(slot_dir "$n")
    [ -d "$dir" ] || continue
    [ "$(dirty_count "$dir")" -eq 0 ] || continue
    branch=$(marker_field "$n" branch)
    [ -n "$branch" ] || continue
    tip=$(git -C "$dir" rev-parse "refs/heads/$branch" 2>/dev/null) || continue
    if ! command -v gh >/dev/null 2>&1; then
      echo "slot $n: not checked for a merged PR (gh is not on the PATH)" >&2; continue
    fi
    tmpf=$(mktemp); errf=$(mktemp)
    if ! gh pr list --state merged --head "$branch" --json number,headRefOid > "$tmpf" 2> "$errf"; then
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
      END { for (i = 1; i <= cnt; i++) if (oid[order[i]] == tip) { print num[order[i]]; exit } }')
    [ -n "$pr" ] || continue
    if [ "$fetched" = 0 ]; then
      if ferr=$(git fetch origin "$base_branch" 2>&1); then fetched=1; else fetched=-1; freason=$(printf '%s\n' "$ferr" | head -n 1); fi
    fi
    if [ "$fetched" != 1 ]; then
      echo "slot $n: not checked for a merged PR (git fetch origin $base_branch failed: $freason)" >&2; continue
    fi
    git -C "$dir" switch --detach "origin/$base_branch" >/dev/null 2>&1 || continue
    git branch -D "$branch" >/dev/null 2>&1 || true
    rm -f "$(marker "$n")"
    echo "Slot $n is free (was $branch, PR #$pr), released automatically."
    freed=$((freed + 1))
  done
}

warmup() { # slot dir
  local n=$1 dir=$2 i=0 idx count where d cmd lf stamp hash have
  [ "$skip" = 1 ] && return 0
  count=$(json_len worktrees.warmup)
  for ((idx = 0; idx < count; idx++)); do
    i=$((i + 1))
    where="$dir"
    d=$(json_get "worktrees.warmup[$idx].dir")
    if [ -n "$d" ]; then where="$dir/$d"; fi
    cmd=$(json_get "worktrees.warmup[$idx].command")
    lf=$(json_get "worktrees.warmup[$idx].lockfile")
    stamp="$state/slot-$n.warmup-$i"
    hash=""
    if [ -n "$lf" ] && [ -f "$dir/$lf" ]; then
      hash=$(sha256 "$dir/$lf")
      have=""
      if [ -f "$stamp" ]; then have=$(cat "$stamp"); fi
      if [ "$have" = "$hash" ]; then continue; fi
    fi
    echo "warm-up $i in $where: $cmd"
    (cd "$where" && bash -c "$cmd")
    if [ -n "$hash" ]; then echo "$hash" > "$stamp"; fi
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

if [ "$status" = 1 ] && [ "$porcelain" = 1 ]; then
  # <n> TAB busy TAB <branch> TAB <since>, or <n> TAB free; a busy slot above the count gets a fifth field, retiring
  top=$(last_slot)
  for ((i = 1; i <= top; i++)); do
    if has_marker "$i"; then
      if [ "$i" -gt "$count" ]; then
        printf '%s\tbusy\t%s\t%s\tretiring\n' "$i" "$(marker_field "$i" branch)" "$(marker_field "$i" since)"
      else
        printf '%s\tbusy\t%s\t%s\n' "$i" "$(marker_field "$i" branch)" "$(marker_field "$i" since)"
      fi
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
    if has_marker "$i"; then busy="busy: $(marker_field "$i" branch) since $(marker_field "$i" since)"; fi
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

if [ -n "$take" ]; then
  mkdir -p "$state"
  reap_all
  n=$slot
  if [ "$n" = 0 ]; then
    for ((i = 1; i <= count; i++)); do
      if ! has_marker "$i"; then n=$i; break; fi
    done
    [ "$n" != 0 ] || { echo "all $count slots are busy; see slot.sh --status" >&2; exit 1; }
  fi
  { [ "$n" -ge 1 ] && [ "$n" -le "$count" ]; } || { echo "slot must be 1..$count" >&2; exit 1; }
  if has_marker "$n"; then echo "slot $n is busy" >&2; exit 1; fi

  git fetch origin "$base_branch"
  dir=$(slot_dir "$n")
  if [ ! -d "$dir" ]; then
    git worktree add --detach "$dir" "$base"
  elif [ "$(dirty_count "$dir")" -gt 0 ]; then
    echo "slot $n has uncommitted files; deal with them first: $dir" >&2; exit 1
  fi

  if git -C "$dir" show-ref --verify --quiet "refs/heads/$take"; then
    git -C "$dir" switch "$take"
  else
    git -C "$dir" switch -c "$take" --no-track "$base"
  fi

  warmup "$n" "$dir"

  json_marker "$n" "$take" "$(date +%Y-%m-%dT%H:%M:%S)" > "$(marker "$n")"
  hints "$n" "$dir" "$take"
  exit 0
fi

if [ "$release" != 0 ]; then
  n=$release
  has_marker "$n" || { echo "slot $n is not in use" >&2; exit 1; }
  dir=$(slot_dir "$n")
  branch=$(marker_field "$n" branch)
  [ "$(dirty_count "$dir")" -eq 0 ] || { echo "slot $n has uncommitted files: $dir" >&2; exit 1; }
  git fetch origin "$base_branch"
  merged=$(gh pr list --state merged --head "$branch" --json number -q '.[0].number')
  [ -n "$merged" ] || { echo "no merged PR for $branch. Merge it first, or free the slot with --abandon $n." >&2; exit 1; }
  git -C "$dir" switch --detach "origin/$base_branch"
  git branch -D "$branch"
  rm -f "$(marker "$n")"
  echo "Slot $n is free (was $branch, PR #$merged)."
  exit 0
fi

if [ "$abandon" != 0 ]; then
  n=$abandon
  has_marker "$n" || { echo "slot $n is not in use" >&2; exit 1; }
  dir=$(slot_dir "$n")
  branch=$(marker_field "$n" branch)
  [ "$(dirty_count "$dir")" -eq 0 ] || { echo "slot $n has uncommitted files: $dir (commit, stash or discard them first)" >&2; exit 1; }
  git -C "$dir" switch --detach "$base"
  rm -f "$(marker "$n")"
  echo "Slot $n is free (was $branch; the local branch is kept, delete it yourself if unwanted)."
  exit 0
fi

usage
