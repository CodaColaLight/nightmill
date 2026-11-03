#!/usr/bin/env bash
# scripts/new-worktree.sh - an ad-hoc extra checkout, outside the slot system (nightmill). Bash twin
# of new-worktree.ps1.
#   new-worktree.sh fix/123-short-name
#   new-worktree.sh feat/foo --base main --skip-warmup
# Creates <worktrees.root>/<branch with / as -> as a new branch from the base branch (or the branch
# itself if it already exists) and runs the configured warm-up commands. For day-to-day tasks use
# slot.sh instead. Remove this one when done:  git worktree remove <dir>  (then git branch -d <branch>)
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: new-worktree.sh <branch> [--base <ref>] [--skip-warmup]" >&2; exit 1; }
branch=$1; shift
base=""; skip=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base=${2:?}; shift ;;
    --skip-warmup) skip=1 ;;
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "new-worktree.sh needs jq" >&2; exit 1; }
gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "run new-worktree.sh from inside a git checkout of the project" >&2; exit 1; }
main=$(dirname "$gitdir")
cfg="$main/.claude/nightmill.json"
[ -f "$cfg" ] || { echo "no $cfg (run /nightmill:init)" >&2; exit 1; }
q() { jq -r "$1 // empty" "$cfg"; }

base_branch=$(q '.git.baseBranch'); base_branch=${base_branch:-main}
[ -n "$base" ] || base="origin/$base_branch"
root_rel=$(q '.worktrees.root'); root_rel=${root_rel:-"../$(basename "$main")-wt"}
mkdir -p "$main/$root_rel"
root=$(cd "$main/$root_rel" && pwd)

slug=${branch//[\/\\]/-}
dir="$root/$slug"
[ ! -e "$dir" ] || { echo "$dir already exists" >&2; exit 1; }

git fetch origin "$base_branch"
if git show-ref --verify --quiet "refs/heads/$branch"; then
  git worktree add "$dir" "$branch"
else
  git worktree add --no-track -b "$branch" "$dir" "$base"
fi

if [ "$skip" = 0 ]; then
  while IFS= read -r w; do
    where="$dir"
    d=$(jq -r '.dir // empty' <<<"$w")
    if [ -n "$d" ]; then where="$dir/$d"; fi
    cmd=$(jq -r '.command' <<<"$w")
    echo "warm-up in $where: $cmd"
    (cd "$where" && bash -c "$cmd")
  done < <(jq -c '.worktrees.warmup // [] | .[]' "$cfg")
fi

# A port offset per worktree, from the name, so two servers can run at once.
sum=0
for ((i = 0; i < ${#slug}; i++)); do sum=$((sum + $(printf '%d' "'${slug:i:1}"))); done
offset=$((sum % 100))

ports() { jq -r '.worktrees.ports // {} | to_entries[] | "\(.key)=\(.value)"' "$cfg"; }
echo
echo "Worktree ready: $dir"
echo "  cd '$dir'"
while IFS='=' read -r name p; do
  [ -n "$name" ] && echo "  port $name: $((p + offset))"
done < <(ports)
if [ "$(jq -r '.worktrees.runHints // [] | length' "$cfg")" -gt 0 ]; then
  echo "Run it next to other checkouts:"
  while IFS= read -r line; do
    line=${line//\{slot\}/$offset}
    while IFS='=' read -r name p; do
      [ -n "$name" ] && line=${line//\{port.$name\}/$((p + offset))}
    done < <(ports)
    echo "  $line"
  done < <(jq -r '.worktrees.runHints // [] | .[]' "$cfg")
fi
