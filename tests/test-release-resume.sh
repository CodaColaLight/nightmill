#!/usr/bin/env bash
# tests/test-release-resume.sh - scripts/release.sh --publish can be resumed after a partial failure (#130):
# a failed tag push, a failed GitHub Release creation, a tag already on origin; it refuses only when the tag
# points at a different commit. gh is a fake on PATH (it logs, and fails when told to).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-test-release-resume.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# the fake gh
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF2'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "release view") [ -f "$GH_STATE" ] ;;
  "release create") if [ -f "$GH_FAIL" ]; then echo "gh: simulated failure" >&2; exit 1; fi; touch "$GH_STATE" ;;
  *) exit 0 ;;
esac
EOF2
chmod +x "$tmp/bin/gh"
export GH_LOG="$tmp/gh.log" GH_STATE="$tmp/gh.state" GH_FAIL="$tmp/gh.fail"

# a merged release: origin/main holds 0.2.0 in plugin.json, CHANGELOG.md and README.md
n=0; O=""; W=""
setup() {
  n=$((n + 1)); O="$tmp/origin$n.git"; W="$tmp/work$n"
  rm -f "$GH_LOG" "$GH_STATE" "$GH_FAIL"
  git init -q --bare -b main "$O"
  git init -q -b main "$W"
  (
    cd "$W"
    git config user.name t; git config user.email t@example.invalid; git config core.autocrlf false
    mkdir -p .claude-plugin scripts
    printf '{\n  "name": "demo",\n  "version": "0.2.0",\n  "description": "A demo"\n}\n' > .claude-plugin/plugin.json
    printf '# Changelog\n\n## Unreleased\n\n## 0.2.0 (2026-11-03)\n\n- A thing.\n' > CHANGELOG.md
    printf '# Demo\n\nVersion 0.2.0. Apache License 2.0.\n' > README.md
    cp "$here/scripts/release.sh" scripts/release.sh
    git add -A; git commit -q -m "Release 0.2.0"
    git remote add origin "$O"
    git push -q origin main
  )
  cand=$(git -C "$W" rev-parse HEAD)
}
publish() { ( cd "$W" && PATH="$tmp/bin:$PATH" bash scripts/release.sh --version 0.2.0 --publish "$@" ) 2>&1; }
# publish_rc <args>: sets out and rc
publish_rc() { set +e; out=$(publish "$@"); rc=$?; set -e; }
reject_tags() {
  printf '#!/bin/sh\nwhile read old new ref; do case "$ref" in refs/tags/*) echo "tags rejected" >&2; exit 1;; esac; done\nexit 0\n' > "$O/hooks/pre-receive"
  chmod +x "$O/hooks/pre-receive"
}

echo "== a failed tag push can be rerun: the local tag is pushed"
setup; reject_tags
publish_rc --no-release
[ "$rc" != 0 ] || fail "the push was expected to fail while origin rejects tags"
rm -f "$O/hooks/pre-receive"
publish_rc --no-release
[ "$rc" = 0 ] || fail "rerun after a failed push exited $rc: $out"
[ "$(git -C "$O" rev-parse 'v0.2.0^{commit}')" = "$cand" ] || fail "v0.2.0 is not on origin at the release commit after the rerun"

echo "== a failed Release creation can be rerun: the Release is created"
setup; touch "$GH_FAIL"
publish_rc
[ "$rc" != 0 ] || fail "the run was expected to fail while gh release create fails"
[ "$(git -C "$O" rev-parse 'v0.2.0^{commit}')" = "$cand" ] || fail "the tag did not reach origin before gh failed"
rm -f "$GH_FAIL"
publish_rc
[ "$rc" = 0 ] || fail "rerun after a failed Release exited $rc: $out"
[ -f "$GH_STATE" ] || fail "the rerun did not create the GitHub Release"

echo "== a tag on origin at the candidate commit, no local tag, no Release: the Release is created"
setup
git -C "$W" tag -a v0.2.0 -m x "$cand"; git -C "$W" push -q origin v0.2.0; git -C "$W" tag -d v0.2.0 >/dev/null
publish_rc
[ "$rc" = 0 ] || fail "publish with the tag already on origin exited $rc: $out"
[ -f "$GH_STATE" ] || fail "the GitHub Release was not created"

echo "== a complete release is not made twice"
setup; touch "$GH_STATE"
git -C "$W" tag -a v0.2.0 -m x "$cand"; git -C "$W" push -q origin v0.2.0
publish_rc
[ "$rc" = 0 ] || fail "publish of a complete release exited $rc: $out"
! grep -q '^release create' "$GH_LOG" 2>/dev/null || fail "gh release create ran although the Release exists"

echo "== a tag at a different commit is refused"
setup
git -C "$W" commit -q --allow-empty -m other
git -C "$W" tag -a v0.2.0 -m x HEAD
publish_rc --no-release
[ "$rc" = 1 ] || fail "expected exit code 1, got $rc: $out"
case "$out" in *"refused: "*"v0.2.0"*) ;; *) fail "wrong refusal: $out" ;; esac
[ -z "$(git -C "$O" tag --list)" ] || fail "the wrong tag was pushed"

echo "== a tag on origin at a different commit, no local tag: refused, no Release"
setup
git -C "$W" commit -q --allow-empty -m other
git -C "$W" tag -a v0.2.0 -m x HEAD; git -C "$W" push -q origin v0.2.0; git -C "$W" tag -d v0.2.0 >/dev/null
git -C "$W" reset -q --hard "$cand"
publish_rc
[ "$rc" = 1 ] || fail "expected exit code 1, got $rc: $out"
case "$out" in *"refused: "*"v0.2.0"*) ;; *) fail "wrong refusal: $out" ;; esac
[ ! -f "$GH_STATE" ] || fail "a GitHub Release was created for a tag at a different commit"
! grep -q '^release create' "$GH_LOG" 2>/dev/null || fail "gh release create ran for a tag at a different commit"
[ "$(git -C "$O" rev-parse 'v0.2.0^{commit}')" != "$cand" ] || fail "the origin tag was moved to the candidate"

echo "RELEASE RESUME OK"
