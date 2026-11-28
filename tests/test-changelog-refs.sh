#!/usr/bin/env bash
# Regression test for #139: the entries for iterations 1 to 3 in CHANGELOG.md cited other items. Only the contract is
# checked: CHANGELOG.md keeps the version headings `## X.Y.Z (` that scripts/release.sh reads; the issue numbers of the
# bullets are CHANGELOG wording, the reviewers' (iteration 76). Offline: a text check only.
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0

# The version headings `## X.Y.Z (` stay (scripts/release.sh reads them).
grep -E '^## [0-9]+\.[0-9]+\.[0-9]+ \(' CHANGELOG.md >/dev/null || { echo "FAIL: no version heading '## X.Y.Z ('"; fail=1; }

[ "$fail" -eq 0 ] && echo "OK: changelog version headings"
exit "$fail"
