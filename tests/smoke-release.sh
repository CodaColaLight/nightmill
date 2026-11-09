#!/usr/bin/env bash
# tests/smoke-release.sh - scripts/release.sh against throwaway repositories with a bare origin: every
# refusal leaves the repository untouched, the dry run changes nothing, prepare makes one commit on a
# release branch, publish tags the release commit and not what came after. Needs git only (no jq, no gh:
# --no-pr and --no-release). Also checks that the lint notices versions that disagree.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-release.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
# gshow: git show with Git Bash's path conversion off ("rev:path" is taken for a path list otherwise)
gshow() { MSYS_NO_PATHCONV=1 git show "$@"; }

n=0
O=""; W=""
tpl_o="$tmp/template-origin.git"; tpl_w="$tmp/template-work"

# The template: a bare origin and a working clone on main holding plugin.json, CHANGELOG.md, README.md and the
# script. Built once; every case gets a copy (building a repository per case is slow on Windows).
git init -q --bare -b main "$tpl_o"
git init -q -b main "$tpl_w"
(
  cd "$tpl_w"
  git config user.name t; git config user.email t@example.invalid; git config core.autocrlf false
  mkdir -p .claude-plugin scripts
  cat > .claude-plugin/plugin.json <<'EOF'
{
  "name": "demo",
  "version": "0.1.1",
  "description": "A demo"
}
EOF
  cat > CHANGELOG.md <<'EOF'
# Changelog

## Unreleased

- A new thing.
- Another thing.

## 0.1.1 (2026-11-03)

- Older.
EOF
  printf '# Demo\n\nVersion 0.1.1. Apache License 2.0, see `LICENSE`.\n' > README.md
  cp "$here/scripts/release.sh" scripts/release.sh
  git add -A; git commit -q -m init
  git remote add origin "$tpl_o"
  git push -q origin main
)

# setup: copy the template into a fresh origin and working clone
setup() {
  n=$((n + 1))
  O="$tmp/origin$n.git"; W="$tmp/work$n"
  cp -r "$tpl_o" "$O"
  cp -r "$tpl_w" "$W"
  git -C "$W" remote set-url origin "$O"
}

# commit_in <message> <shell command>: run the command in $W, commit everything, push main
commit_in() {
  local msg=$1 cmd=$2
  ( cd "$W"; bash -c "$cmd"; git add -A; git commit -q -m "$msg"; git push -q origin main )
}

snap() { ( cd "$W" && { git status --porcelain; git branch --list | sort; git tag --list | sort; git rev-parse HEAD; } ); }

# refuses <name> <reason fragment> <args...>: exit 1, "refused: ...<fragment>..." on stderr, nothing changed
refuses() {
  local name=$1 want=$2; shift 2
  local before after err rc
  before=$(snap)
  set +e
  err=$(cd "$W" && bash scripts/release.sh "$@" 2>&1 >/dev/null)
  rc=$?
  set -e
  after=$(snap)
  [ "$rc" = 1 ] || fail "$name: expected exit code 1, got $rc: $err"
  case "$err" in *"refused: "*"$want"*) ;; *) fail "$name: wrong reason (wanted '$want'): $err" ;; esac
  [ "$before" = "$after" ] || fail "$name: the repository changed"
}

today=$(date -u +%F)

echo "== refusals leave the repository untouched"
setup; refuses "invalid version" "X.Y.Z" --version 1.2
setup; echo junk > "$W/junk.txt"; refuses "dirty tree" "uncommitted" --version 0.2.0
setup; git -C "$W" switch -q -c other; refuses "not on main" "not on main" --version 0.2.0
setup; git clone -q "$O" "$tmp/other$n"
( cd "$tmp/other$n"; git config user.name t; git config user.email t@example.invalid; git commit -q --allow-empty -m ahead; git push -q origin main )
refuses "main behind origin" "origin/main" --version 0.2.0
setup; refuses "equal version" "not greater" --version 0.1.1
setup; refuses "lower version" "not greater" --version 0.1.0
setup; refuses "lower major" "not greater" --version 0.0.9
setup; commit_in "empty" "grep -v '^- ' CHANGELOG.md > c.tmp && mv c.tmp CHANGELOG.md"
refuses "empty Unreleased" "Unreleased" --version 0.2.0
setup; commit_in "no heading" "sed 's/^## Unreleased\$/## Next/' CHANGELOG.md > c.tmp && mv c.tmp CHANGELOG.md"
refuses "missing Unreleased heading" "Unreleased" --version 0.2.0
setup; git -C "$W" tag v0.2.0; refuses "tag exists locally" "tag v0.2.0 already exists" --version 0.2.0
setup; git -C "$W" tag v0.2.0; git -C "$W" push -q origin v0.2.0; git -C "$W" tag -d v0.2.0 >/dev/null
refuses "tag exists on origin only" "tag v0.2.0 already exists" --version 0.2.0
setup; git -C "$W" branch release/v0.2.0; refuses "release branch exists" "release/v0.2.0 already exists" --version 0.2.0
setup; commit_in "no version line" "grep -v '^Version ' README.md > r.tmp && mv r.tmp README.md"
refuses "README without a Version line" "README.md" --version 0.2.0

echo "== dry run prints the plan and changes nothing"
setup
before=$(snap)
out=$(cd "$W" && bash scripts/release.sh --version 0.2.0 --dry-run) || fail "dry run exited non-zero"
for w in "release/v0.2.0" "0.1.1" "0.2.0" "$today"; do
  case "$out" in *"$w"*) ;; *) fail "dry run output lacks '$w': $out" ;; esac
done
[ "$before" = "$(snap)" ] || fail "dry run changed the repository"

echo "== prepare: one commit on release/v0.2.0, three files, main untouched"
setup
( cd "$W" && bash scripts/release.sh --version 0.2.0 --no-pr ) >/dev/null || fail "prepare exited non-zero"
(
  cd "$W"
  [ "$(git branch --show-current)" = main ] || fail "prepare did not switch back to main"
  [ -z "$(git status --porcelain)" ] || fail "working tree not clean after prepare"
  [ "$(git rev-list --count main..release/v0.2.0)" = 1 ] || fail "expected exactly one commit on the release branch"
  [ "$(git log -1 --format=%s release/v0.2.0)" = "Release 0.2.0" ] || fail "wrong commit subject"
  changed=$(git diff --name-only main release/v0.2.0 | sort | tr '\n' ' ')
  [ "$changed" = ".claude-plugin/plugin.json CHANGELOG.md README.md " ] || fail "unexpected files changed: $changed"
  pj=$(gshow release/v0.2.0:.claude-plugin/plugin.json)
  case "$pj" in *'"version": "0.2.0",'*) ;; *) fail "plugin.json lacks the new version" ;; esac
  [ "$(git diff -U0 main release/v0.2.0 -- .claude-plugin/plugin.json | grep -c '^[+-][^+-]')" = 2 ] || fail "plugin.json changed by more than the version line"
  cl=$(gshow release/v0.2.0:CHANGELOG.md)
  expect=$'## Unreleased\n\n## 0.2.0 ('"$today"$')\n\n- A new thing.\n- Another thing.\n\n## 0.1.1 (2026-11-03)\n\n- Older.'
  case "$cl" in *"$expect"*) ;; *) fail "CHANGELOG not cut as expected: $cl" ;; esac
  rd=$(gshow release/v0.2.0:README.md)
  case "$rd" in *'Version 0.2.0. Apache License 2.0, see `LICENSE`.'*) ;; *) fail "README line not updated: $rd" ;; esac
)

echo "== publish: tags the release commit, not what came after"
setup
( cd "$W" && bash scripts/release.sh --version 0.2.0 --no-pr ) >/dev/null
refuses "publish before the merge" "origin/main" --version 0.2.0 --publish
( cd "$W" && git merge -q --ff-only release/v0.2.0 && git push -q origin main )
release_commit=$(git -C "$W" rev-parse HEAD)
commit_in "later work" "echo later >> README.md"
( cd "$W" && bash scripts/release.sh --version 0.2.0 --publish --no-release ) >/dev/null || fail "publish exited non-zero"
[ "$(git -C "$W" cat-file -t v0.2.0)" = tag ] || fail "v0.2.0 is not an annotated tag"
[ "$(git -C "$W" rev-parse 'v0.2.0^{commit}')" = "$release_commit" ] || fail "v0.2.0 does not point at the release commit"
[ "$(git -C "$O" rev-parse 'v0.2.0^{commit}')" = "$release_commit" ] || fail "v0.2.0 is not on origin at the release commit"
( cd "$W" && bash scripts/release.sh --version 0.2.0 --publish --no-release ) >/dev/null || fail "publish twice exited non-zero"
[ "$(git -C "$O" rev-parse 'v0.2.0^{commit}')" = "$release_commit" ] || fail "publish twice moved v0.2.0"

echo "== publish: a failed tag push is finished by a rerun; a tag at another commit is refused (#130)"
setup
( cd "$W" && bash scripts/release.sh --version 0.2.0 --no-pr ) >/dev/null
( cd "$W" && git merge -q --ff-only release/v0.2.0 && git push -q origin main )
release_commit=$(git -C "$W" rev-parse HEAD)
printf '#!/bin/sh\nwhile read old new ref; do case "$ref" in refs/tags/*) exit 1;; esac; done\nexit 0\n' > "$O/hooks/pre-receive"
chmod +x "$O/hooks/pre-receive"
if ( cd "$W" && bash scripts/release.sh --version 0.2.0 --publish --no-release ) >/dev/null 2>&1; then fail "publish succeeded although origin rejects tags"; fi
rm -f "$O/hooks/pre-receive"
( cd "$W" && bash scripts/release.sh --version 0.2.0 --publish --no-release ) >/dev/null || fail "the rerun after a failed push exited non-zero"
[ "$(git -C "$O" rev-parse 'v0.2.0^{commit}')" = "$release_commit" ] || fail "the rerun did not push v0.2.0 at the release commit"
git -C "$W" tag -d v0.2.0 >/dev/null; git -C "$W" tag -a v0.2.0 -m x "$release_commit^"
refuses "tag at another commit" "tag v0.2.0 already exists at another commit" --version 0.2.0 --publish --no-release

echo "== the lint notices versions that disagree"
cp_dir="$tmp/repocopy"; mkdir -p "$cp_dir"
( cd "$here" && tar -cf - --exclude=.git . ) | ( cd "$cp_dir" && tar -xf - )
# On a failure the lint's FAIL: lines (else its whole output) follow, so a CI log names the rule (#217).
if ! out=$(cd "$cp_dir" && bash tests/lint.sh 2>&1); then
  fail "the lint fails on an unchanged copy of the repository
$(printf '%s\n' "$out" | grep 'FAIL:' || printf '%s\n' "$out")"
fi
sed 's/^\(  "version": "\)[0-9.]*"/\19.9.9"/' "$cp_dir/.claude-plugin/plugin.json" > "$cp_dir/pj.tmp" && mv "$cp_dir/pj.tmp" "$cp_dir/.claude-plugin/plugin.json"
if out=$(cd "$cp_dir" && bash tests/lint.sh 2>&1); then fail "the lint accepted a plugin.json version that disagrees"; fi
case "$out" in *"FAIL: versions disagree"*"9.9.9"*) ;; *) fail "the lint did not report the disagreement: $out" ;; esac

echo "RELEASE OK"
