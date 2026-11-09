#!/usr/bin/env bash
# scripts/release.sh - cut a release of this repository in two steps. main only takes pull requests, so a
# release is prepared as a pull request and tagged after it has merged.
#
#   scripts/release.sh --version X.Y.Z             prepare: branch release/vX.Y.Z with one commit that bumps
#                                                  .claude-plugin/plugin.json, cuts CHANGELOG.md and updates
#                                                  the README's "Version" line; push it and open the pull request
#   scripts/release.sh --version X.Y.Z --publish   after the merge: tag the release commit vX.Y.Z, push the tag
#                                                  and create the GitHub Release from the changelog section;
#                                                  each step that is already done is skipped, so a run that
#                                                  failed half way is finished by running it again
#   --dry-run     print what would happen, change and push nothing
#   --no-pr       prepare without pushing or opening the pull request (the branch stays local)
#   --no-release  publish without creating the GitHub Release (the tag is still pushed)
#
# Exit codes: 0 done, 1 refused (one line "refused: <reason>" on stderr), 2 usage error or a missing tool.
# Needs git, and gh unless --dry-run, --no-pr or --no-release say otherwise. No jq. The repository is the one
# this script lives in.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/release.sh --version X.Y.Z [--dry-run] [--no-pr]
       scripts/release.sh --version X.Y.Z --publish [--dry-run] [--no-release]
EOF
  exit 2
}

version=""; publish=0; dry=0; nopr=0; norel=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) [ $# -ge 2 ] || usage; version=$2; shift 2 ;;
    --publish) publish=1; shift ;;
    --dry-run) dry=1; shift ;;
    --no-pr) nopr=1; shift ;;
    --no-release) norel=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done
[ -n "$version" ] || usage

refuse() { echo "refused: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1" >&2; exit 2; }; }
need git
if [ "$dry" = 0 ]; then
  if [ "$publish" = 1 ]; then [ "$norel" = 1 ] || need gh; else [ "$nopr" = 1 ] || need gh; fi
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
git rev-parse --git-dir >/dev/null 2>&1 || refuse "$root is not a git repository"

PJ=.claude-plugin/plugin.json
tag="v$version"
rbranch="release/v$version"

# --- helpers ---------------------------------------------------------------------------------------------

# gshow: git show with Git Bash's path conversion off. Without it "origin/main:.claude-plugin/plugin.json" is
# taken for a list of Windows paths.
gshow() { MSYS_NO_PATHCONV=1 git show "$@"; }

# json_version: reads plugin.json on stdin, prints its version when there is exactly one version line.
json_version() {
  local l n
  l=$(grep -E '^[[:space:]]*"version":[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"[[:space:]]*,?[[:space:]]*$' || true)
  [ -n "$l" ] || return 1
  n=$(printf '%s\n' "$l" | wc -l | tr -d ' ')
  [ "$n" = 1 ] || return 1
  printf '%s\n' "$l" | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/'
}

# gt A B: true when version A is greater than version B (number by number)
gt() {
  local IFS=.
  local -a a b
  read -r -a a <<<"$1"
  read -r -a b <<<"$2"
  local i
  for i in 0 1 2; do
    [ $((10#${a[i]})) -gt $((10#${b[i]})) ] && return 0
    [ $((10#${a[i]})) -lt $((10#${b[i]})) ] && return 1
  done
  return 1
}

# unreleased_state FILE: ok, empty (nothing under the heading) or missing (no heading)
unreleased_state() {
  awk '
    /^## Unreleased[[:space:]]*$/ { found = 1; inside = 1; next }
    inside && /^## / { exit }
    inside && /[^[:space:]]/ { content = 1 }
    END { if (!found) print "missing"; else if (!content) print "empty"; else print "ok" }' "$1"
}

# section VERSION FILE: the body of the changelog section for VERSION, without leading or trailing blank lines
section() {
  awk -v v="$1" '
    /^## / { if (p) exit; if (index($0, "## " v " (") == 1) { p = 1; next } }
    p { lines[++n] = $0 }
    END {
      s = 1; while (s <= n && lines[s] ~ /^[[:space:]]*$/) s++
      e = n; while (e >= s && lines[e] ~ /^[[:space:]]*$/) e--
      for (i = s; i <= e; i++) print lines[i]
    }' "$2"
}

tag_exists() {
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1 && return 0
  [ -n "$(git ls-remote --tags origin "refs/tags/$tag" 2>/dev/null)" ]
}

# remote_tag_commit: the commit the tag points at on origin (peeled), empty when origin has no such tag
remote_tag_commit() {
  local l c=""
  l=$(git ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}") || refuse "cannot list the tags on origin"
  c=$(printf '%s\n' "$l" | awk -v r="refs/tags/$tag^{}" '$2 == r { print $1 }')
  [ -n "$c" ] || c=$(printf '%s\n' "$l" | awk -v r="refs/tags/$tag" '$2 == r { print $1 }')
  printf '%s' "$c"
}

# --- checks both modes make --------------------------------------------------------------------------------

[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || refuse "version must be X.Y.Z with digits only, got '$version'"
[ -z "$(git status --porcelain)" ] || refuse "working tree has uncommitted changes"
git fetch -q --no-tags origin main || refuse "cannot fetch origin"

# --- publish ---------------------------------------------------------------------------------------------

if [ "$publish" = 1 ]; then
  ohold=$(gshow "origin/main:$PJ" 2>/dev/null | json_version || true)
  [ "$ohold" = "$version" ] || refuse "origin/main does not hold version $version in $PJ (is the release pull request merged?)"
  gshow origin/main:CHANGELOG.md | awk -v v="$version" 'index($0, "## " v " (") == 1 { f = 1 } END { exit !f }' \
    || refuse "CHANGELOG.md on origin/main has no heading for $version"
  gshow origin/main:README.md | awk -v v="$version" 'index($0, "Version " v ".") == 1 { f = 1 } END { exit !f }' \
    || refuse "README.md on origin/main has no 'Version $version.' line"

  # the oldest commit on origin/main's first-parent history that holds this version: the merge of the
  # release pull request, not whatever main has become since
  cand=""
  for c in $(git rev-list --first-parent origin/main); do
    v=$(gshow "$c:$PJ" 2>/dev/null | json_version || true)
    if [ "$v" = "$version" ]; then cand=$c; else break; fi
  done
  [ -n "$cand" ] || refuse "no commit on origin/main holds version $version"

  # every step is skipped when it is already done, so a run that failed half way can be run again; only a
  # tag at another commit is refused
  ltag=$(git rev-parse -q --verify "refs/tags/$tag^{commit}" 2>/dev/null || true)
  rtag=$(remote_tag_commit)
  [ -z "$ltag" ] || [ "$ltag" = "$cand" ] || refuse "tag $tag already exists at another commit ($(git rev-parse --short "$ltag"), not $(git rev-parse --short "$cand"))"
  [ -z "$rtag" ] || [ "$rtag" = "$cand" ] || refuse "tag $tag already exists on origin at another commit (${rtag:0:7}, not $(git rev-parse --short "$cand"))"

  if [ "$dry" = 1 ]; then
    echo "would tag $(git log -1 --format='%h %s' "$cand") as $tag, push the tag and create the GitHub Release (steps already done are skipped)"
    exit 0
  fi
  if [ -z "$ltag" ] && [ -z "$rtag" ]; then
    git tag -a "$tag" -m "nightmill $version" "$cand"
  fi
  if [ -z "$rtag" ]; then
    git push -q origin "refs/tags/$tag"
    echo "tagged $tag at $(git rev-parse --short "$cand")"
  else
    echo "tag $tag is already on origin at $(git rev-parse --short "$cand")"
  fi
  if [ "$norel" = 0 ] && gh release view "$tag" >/dev/null 2>&1; then
    echo "the GitHub Release $tag already exists"
  elif [ "$norel" = 0 ]; then
    tmpc=$(mktemp "${TMPDIR:-/tmp}/nightmill-release.XXXXXX"); notes=$(mktemp "${TMPDIR:-/tmp}/nightmill-release.XXXXXX")
    gshow origin/main:CHANGELOG.md > "$tmpc"
    section "$version" "$tmpc" > "$notes"
    gh release create "$tag" --title "nightmill $version" --notes-file "$notes" --verify-tag --latest
    rm -f "$tmpc" "$notes"
  fi
  exit 0
fi

# --- prepare ---------------------------------------------------------------------------------------------

branch=$(git branch --show-current)
[ "$branch" = main ] || refuse "not on main (on '${branch:-a detached HEAD}')"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || refuse "main is not equal to origin/main (pull or push first)"

cur=$(json_version < "$PJ" || true)
[ -n "$cur" ] || refuse "$PJ does not have exactly one version line"
gt "$version" "$cur" || refuse "version $version is not greater than the current $cur"

state=$(unreleased_state CHANGELOG.md)
[ "$state" != missing ] || refuse "CHANGELOG.md has no '## Unreleased' heading"
[ "$state" != empty ] || refuse "the Unreleased section of CHANGELOG.md is empty"
n_readme=$(grep -cE '^Version [0-9]+\.[0-9]+\.[0-9]+\.' README.md || true)
[ "$n_readme" = 1 ] || refuse "README.md does not have exactly one line starting with 'Version X.Y.Z.'"

tag_exists && refuse "tag $tag already exists"
if git show-ref --verify -q "refs/heads/$rbranch" || [ -n "$(git ls-remote --heads origin "$rbranch" 2>/dev/null)" ]; then
  refuse "branch $rbranch already exists"
fi

date=$(date -u +%F)
echo "release $cur -> $version ($date)"
echo "  $PJ: version $cur -> $version"
echo "  CHANGELOG.md: the Unreleased entries move under '## $version ($date)'"
echo "  README.md: 'Version $cur.' -> 'Version $version.'"
echo "  branch $rbranch, one commit 'Release $version', pull request 'Release $version'"
if [ "$dry" = 1 ]; then
  echo "(dry run: nothing was changed)"
  exit 0
fi

rollback() { git reset -q --hard HEAD >/dev/null 2>&1 || true; git switch -q main >/dev/null 2>&1 || true; git branch -D "$rbranch" >/dev/null 2>&1 || true; }
git switch -q -c "$rbranch"
trap rollback ERR

tmpf=$(mktemp "${TMPDIR:-/tmp}/nightmill-release.XXXXXX")
sed -E "s/^([[:space:]]*\"version\":[[:space:]]*\")[0-9]+\.[0-9]+\.[0-9]+(\")/\1$version\2/" "$PJ" > "$tmpf"
cat "$tmpf" > "$PJ"
awk -v v="$version" -v d="$date" '{ print } /^## Unreleased[[:space:]]*$/ && !done { print ""; print "## " v " (" d ")"; done = 1 }' CHANGELOG.md > "$tmpf"
cat "$tmpf" > CHANGELOG.md
sed -E "s/^Version [0-9]+\.[0-9]+\.[0-9]+\./Version $version./" README.md > "$tmpf"
cat "$tmpf" > README.md
rm -f "$tmpf"

git add "$PJ" CHANGELOG.md README.md
git commit -q -m "Release $version"
trap - ERR

if [ "$nopr" = 1 ]; then
  git switch -q main
  echo "prepared branch $rbranch (not pushed: --no-pr)"
  exit 0
fi

body=$(mktemp "${TMPDIR:-/tmp}/nightmill-release.XXXXXX")
{
  section "$version" CHANGELOG.md
  echo
  echo "After this merges, run \`scripts/release.sh --version $version --publish\` (or \`scripts/release.ps1 -Version $version -Publish\`) to tag it and create the GitHub Release."
} > "$body"
git push -q -u origin "$rbranch"
gh pr create --base main --head "$rbranch" --title "Release $version" --body-file "$body"
rm -f "$body"
git switch -q main
