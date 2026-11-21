#!/usr/bin/env bash
# tests/test-release-low-defects.sh - the low-severity defects in scripts/release.sh (#321, split from #140):
# the exit codes of the header, a rollback after a failed push or gh pr create, versions with leading zeros,
# temporary files removed when a step fails, --dry-run (no fetch, gh auth checked), GH_PROMPT_DISABLED set for
# gh, and an exported CDPATH. gh is a fake on PATH (it logs, and fails when told to).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-test-release-low.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF2'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
echo "prompt=${GH_PROMPT_DISABLED:-}" >> "$GH_ENV"
case "$1 $2" in
  "auth status") [ ! -f "$GH_AUTH_FAIL" ] ;;
  "pr create") if [ -f "$GH_FAIL" ]; then echo "gh: simulated failure" >&2; exit 1; fi ;;
  *) exit 0 ;;
esac
EOF2
chmod +x "$tmp/bin/gh"
export GH_LOG="$tmp/gh.log" GH_ENV="$tmp/gh.env" GH_FAIL="$tmp/gh.fail" GH_AUTH_FAIL="$tmp/gh.authfail"
unset GH_PROMPT_DISABLED CDPATH || true

# main holds 0.2.0 with an entry under Unreleased: 0.3.0 can be prepared
n=0; O=""; W=""
setup() {
  n=$((n + 1)); O="$tmp/origin$n.git"; W="$tmp/work$n"
  rm -rf "$O" "$W" "$tmp/tmpdir$n"; rm -f "$GH_LOG" "$GH_ENV" "$GH_FAIL" "$GH_AUTH_FAIL"
  git init -q --bare -b main "$O"
  git init -q -b main "$W"
  (
    cd "$W"
    git config user.name t; git config user.email t@example.invalid; git config core.autocrlf false
    mkdir -p .claude-plugin scripts
    printf '{\n  "name": "demo",\n  "version": "0.2.0",\n  "description": "A demo"\n}\n' > .claude-plugin/plugin.json
    printf '# Changelog\n\n## Unreleased\n\n- A new thing.\n\n## 0.2.0 (2026-11-03)\n\n- A thing.\n' > CHANGELOG.md
    printf '# Demo\n\nVersion 0.2.0. Apache License 2.0.\n' > README.md
    cp "$here/scripts/release.sh" scripts/release.sh
    git add -A; git commit -q -m "Release 0.2.0"
    git remote add origin "$O"
    git push -q origin HEAD:refs/heads/main
  )
}
# rel <args>: runs release.sh --version 0.3.0 <args> in the work repo; sets out and rc
rel() {
  set +e
  out=$(cd "$W" && PATH="$tmp/bin:$PATH" bash scripts/release.sh --version "${VER:-0.3.0}" "$@" 2>&1)
  rc=$?
  set -e
}
reject_branches() {
  printf '#!/bin/sh\nwhile read old new ref; do case "$ref" in refs/heads/release/*) echo "branch rejected" >&2; exit 1;; esac; done\nexit 0\n' > "$O/hooks/pre-receive"
  chmod +x "$O/hooks/pre-receive"
}
# a state a rerun can start from: on main, no release branch here or on origin
assert_rolled_back() {
  [ "$(git -C "$W" branch --show-current)" = main ] || fail "$1: not back on main (on '$(git -C "$W" branch --show-current)')"
  [ -z "$(git -C "$W" branch --list 'release/v0.3.0')" ] || fail "$1: the local branch release/v0.3.0 is still there"
  [ -z "$(git -C "$O" branch --list 'release/v0.3.0')" ] || fail "$1: the branch release/v0.3.0 is still on origin"
  [ -z "$(git -C "$W" status --porcelain)" ] || fail "$1: the working tree is not clean"
}

case1() {
  echo "== an unexpected failure exits 2, as the header says"
setup
printf '#!/bin/sh\necho "hook says no" >&2\nexit 1\n' > "$W/.git/hooks/pre-commit"; chmod +x "$W/.git/hooks/pre-commit"
rel
[ "$rc" = 2 ] || fail "a failed commit exited $rc, expected 2: $out"

}
case2() {
  echo "== a failed push after the release commit is rolled back; a rerun works"
setup; reject_branches
rel
[ "$rc" != 0 ] || fail "the push was expected to fail while origin rejects branches"
assert_rolled_back "failed push"
rm -f "$O/hooks/pre-receive"
rel
[ "$rc" = 0 ] || fail "rerun after a failed push exited $rc: $out"

}
case3() {
  echo "== a failed gh pr create after the push is rolled back; a rerun works"
setup; touch "$GH_FAIL"
rel
[ "$rc" != 0 ] || fail "the run was expected to fail while gh pr create fails"
assert_rolled_back "failed gh pr create"
rm -f "$GH_FAIL"
rel
[ "$rc" = 0 ] || fail "rerun after a failed gh pr create exited $rc: $out"

}
case4() {
  echo "== versions with leading zeros are refused"
setup
for v in 0.03.0 1.0.01 00.3.0; do
  VER=$v rel --dry-run
  [ "$rc" = 1 ] || fail "version $v exited $rc, expected 1: $out"
  case "$out" in *"refused: "*) ;; *) fail "version $v: no refused line: $out" ;; esac
done
unset VER

}
case5() {
  echo "== temporary files are removed when a step fails"
setup; reject_branches
mkdir -p "$tmp/tmpdir$n"
TMPDIR="$tmp/tmpdir$n" rel
[ "$rc" != 0 ] || fail "the push was expected to fail while origin rejects branches"
left=0
for f in "$tmp/tmpdir$n"/nightmill-release*; do
  [ -e "$f" ] && left=$((left + 1))
done
[ "$left" = 0 ] || fail "$left temporary file(s) left behind: $(ls "$tmp/tmpdir$n")"

}
case6() {
  echo "== --dry-run does not fetch and checks gh auth"
setup
GIT_TRACE=1 rel --dry-run
[ "$rc" = 0 ] || fail "dry run exited $rc: $out"
case "$out" in *"git fetch"*) fail "--dry-run ran git fetch: $out" ;; esac
grep -q '^auth status' "$GH_LOG" 2>/dev/null || fail "--dry-run did not run gh auth status"
touch "$GH_AUTH_FAIL"
rel --dry-run
[ "$rc" != 0 ] || fail "--dry-run succeeded although gh is not authenticated: $out"

}
case7() {
  echo "== gh is called with GH_PROMPT_DISABLED set"
setup
rel
[ "$rc" = 0 ] || fail "prepare exited $rc: $out"
grep -q '^pr create' "$GH_LOG" || fail "gh pr create was not called"
! grep -qx 'prompt=' "$GH_ENV" || fail "a gh call ran without GH_PROMPT_DISABLED: $(cat "$GH_ENV")"

}
case8() {
  echo "== an exported CDPATH does not break the library path"
setup
mkdir -p "$tmp/decoy/scripts"
CDPATH="$tmp/decoy" rel --dry-run --no-pr
[ "$rc" = 0 ] || fail "dry run with CDPATH exited $rc: $out"
case "$out" in *"release 0.2.0 -> 0.3.0"*) ;; *) fail "dry run with CDPATH did not plan the release: $out" ;; esac

}
bad=0
( set -e; case1 ) || bad=1
( set -e; case2 ) || bad=1
( set -e; case3 ) || bad=1
( set -e; case4 ) || bad=1
( set -e; case5 ) || bad=1
( set -e; case6 ) || bad=1
( set -e; case7 ) || bad=1
( set -e; case8 ) || bad=1
[ "$bad" = 0 ] || exit 1
echo "RELEASE LOW DEFECTS OK"
