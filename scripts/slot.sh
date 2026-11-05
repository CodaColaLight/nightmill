#!/usr/bin/env bash
# scripts/slot.sh - permanent worktrees, one per worker slot (nightmill). Bash twin of slot.ps1.
#   slot.sh --status [--porcelain]      # --porcelain: one tab separated line per slot, for scripts
#   slot.sh --take feat/foo [--slot 2] [--base origin/main] [--skip-warmup]
#   slot.sh --release 1                 # after the PR merged
#   slot.sh --abandon 1                 # free a slot whose task was dropped (no merged PR)
# Needs git and (for --release) gh. Run it from inside the project: any checkout or worktree of
# it. Configuration comes from .claude/nightmill.json in the main checkout, keys under "worktrees"
# (see schema/nightmill.schema.json); WORKER_SLOTS overrides worktrees.slots. A slot is never removed:
# a new task only switches it to a new branch from the base branch, so build output stays warm.
# A slot is busy from --take to --release or --abandon (a marker file in <root>/.slots). Slot N gets
# port base + N.
set -euo pipefail

usage() {
  echo "usage: slot.sh --status | --take <branch> [--slot N] [--base <ref>] [--skip-warmup] | --release N | --abandon N" >&2
  exit 1
}

take=""; release=0; abandon=0; status=0; slot=0; base=""; skip=0; porcelain=0
while [ $# -gt 0 ]; do
  case "$1" in
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

count=$(q worktrees.slots); count=${count:-2}
if [ -n "${WORKER_SLOTS:-}" ]; then
  [[ "$WORKER_SLOTS" =~ ^[1-9][0-9]?$ ]] || { echo "WORKER_SLOTS must be a number from 1 to 99" >&2; exit 1; }
  count=$WORKER_SLOTS
fi

slot_dir() { echo "$root/slot-$1"; }
marker() { echo "$state/slot-$1.json"; }
has_marker() { [ -f "$(marker "$1")" ]; }
marker_field() { ( json_load "$(marker "$1")" && json_get "$2" ); }
dirty_count() { git -C "$1" status --porcelain | wc -l | tr -d ' '; }
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
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

if [ "$status" = 1 ] && [ "$porcelain" = 1 ]; then
  # <n> TAB busy TAB <branch> TAB <since>, or <n> TAB free
  for ((i = 1; i <= count; i++)); do
    if has_marker "$i"; then
      printf '%s\tbusy\t%s\t%s\n' "$i" "$(marker_field "$i" branch)" "$(marker_field "$i" since)"
    else
      printf '%s\tfree\n' "$i"
    fi
  done
  exit 0
fi

if [ "$status" = 1 ]; then
  echo "slots = $count  root = $root"
  for ((i = 1; i <= count; i++)); do
    dir=$(slot_dir "$i")
    where="not created yet"; [ -d "$dir" ] && where="ready"
    busy="free"
    if has_marker "$i"; then busy="busy: $(marker_field "$i" branch) since $(marker_field "$i" since)"; fi
    dirty=""
    if [ -d "$dir" ]; then
      n=$(dirty_count "$dir")
      [ "$n" -gt 0 ] && dirty="  ($n uncommitted files)"
    fi
    printf 'slot %s  %-15s %s%s\n' "$i" "$where" "$busy" "$dirty"
  done
  exit 0
fi

if [ -n "$take" ]; then
  mkdir -p "$state"
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
