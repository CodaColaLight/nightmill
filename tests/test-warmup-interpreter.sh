#!/usr/bin/env bash
# tests/test-warmup-interpreter.sh - regression for bug #133: a warm-up command is one string, and one interpreter runs it
# in both shells (bash -c). A warm-up of `echo a && echo b` must work in slot.sh --take and new-worktree.sh (it did; the
# PowerShell twins did not, see test-warmup-interpreter.ps1), and the schema description of warmup[].command must name
# the interpreter.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-test-warmup-interp.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "== a warm-up of 'echo a && echo b' works in slot.sh --take and new-worktree.sh"
git init -q --bare "$tmp/origin.git"
git init -q -b main "$tmp/work"
cd "$tmp/work"
git config core.autocrlf false
mkdir -p .claude client
cat > .claude/nightmill.json <<'EOF2'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "git": { "baseBranch": "main" },
  "worktrees": {
    "root": "../wt",
    "slots": 2,
    "warmup": [ { "dir": "client", "command": "echo a && echo b > warmed.txt" } ]
  }
}
EOF2
echo x > client/keep.txt
git add -A
git -c user.name=t -c user.email=t@example.invalid commit -qm init
git remote add origin "$tmp/origin.git"
git push -q origin main
git remote set-head origin main

set +e; out=$(bash "$here/scripts/slot.sh" --take feat/warm 2>&1); rc=$?; set -e
[ "$rc" = 0 ] || fail "slot.sh --take with the warm-up 'echo a && echo b > warmed.txt' exited $rc: $out"
[ "$(tr -d '\r\n' < "$tmp/wt/slot-1/client/warmed.txt" 2>/dev/null)" = b ] || fail "slot.sh --take: the warm-up did not run to its end (warmed.txt is not b)"

set +e; out=$(bash "$here/scripts/new-worktree.sh" feat/extra 2>&1); rc=$?; set -e
[ "$rc" = 0 ] || fail "new-worktree.sh with the warm-up 'echo a && echo b > warmed.txt' exited $rc: $out"
[ "$(tr -d '\r\n' < "$tmp/wt/feat-extra/client/warmed.txt" 2>/dev/null)" = b ] || fail "new-worktree.sh: the warm-up did not run to its end (warmed.txt is not b)"

echo "== the schema says which interpreter runs warmup[].command"
flat=$(tr -d '\r\n' < "$here/schema/nightmill.schema.json")
# the object of the "command" property of warmup items: from its key to the closing brace of that property
cmdobj=$(printf '%s' "$flat" | grep -o '"warmup": *{.*' | grep -o '"command": *{[^}]*}' | head -1 || true)
[ -n "$cmdobj" ] || fail "the schema has no object for worktrees.warmup[].command"
printf '%s' "$cmdobj" | grep -q '"description"' || fail "the schema has no description for worktrees.warmup[].command"
printf '%s' "$cmdobj" | grep -qi 'bash' || fail "the schema description of worktrees.warmup[].command does not name the interpreter (bash): $cmdobj"

echo "WARMUP INTERPRETER OK"
