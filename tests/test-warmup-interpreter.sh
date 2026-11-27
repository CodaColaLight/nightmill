#!/usr/bin/env bash
# tests/test-warmup-interpreter.sh - regression for bug #133: a warm-up command is one string, and one interpreter runs it
# (bash -c). A warm-up of `echo a && echo b` must work in slot.sh --take and new-worktree.sh, and the schema description of warmup[].command must name
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
    "warmup": [
      { "dir": "client", "command": "echo a && echo b > warmed.txt" },
      { "dir": "client", "command": "X=1; echo \"a b\" \"$X\" 'c $d' > quoted.txt; echo \"it's\" >> quoted.txt" }
    ]
  }
}
EOF2
echo x > client/keep.txt
# what bash -c makes of the quoting warm-up: the expected content of quoted.txt, taken from bash itself
mkdir -p "$tmp/expect"
(cd "$tmp/expect" && bash -c "X=1; echo \"a b\" \"\$X\" 'c \$d' > quoted.txt; echo \"it's\" >> quoted.txt")
expect_quoted=$(tr -d '\r' < "$tmp/expect/quoted.txt")
[ "$expect_quoted" = "$(printf '%s\n%s' 'a b 1 c $d' "it's")" ] || fail "setup: bash -c made '$expect_quoted' of the quoting warm-up"
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

echo "== a warm-up with double quotes, single quotes, a \$VAR and a ; gives the same file as bash -c"
for f in "$tmp/wt/slot-1/client/quoted.txt" "$tmp/wt/feat-extra/client/quoted.txt"; do
  got=$(tr -d '\r' < "$f" 2>/dev/null || true)
  [ "$got" = "$expect_quoted" ] || fail "quoted.txt in ${f#"$tmp/wt/"} holds '$got', not what bash -c makes of the quoting warm-up: '$expect_quoted'"
done

echo "== the schema says which interpreter runs warmup[].command"
flat=$(tr -d '\r\n' < "$here/schema/nightmill.schema.json")
# the object of the "command" property of warmup items: from its key to the closing brace of that property
cmdobj=$(printf '%s' "$flat" | grep -o '"warmup": *{.*' | grep -o '"command": *{[^}]*}' | head -1 || true)
[ -n "$cmdobj" ] || fail "the schema has no object for worktrees.warmup[].command"
grep -q '"description"' <<<"$cmdobj" || fail "the schema has no description for worktrees.warmup[].command"
grep -qi 'bash' <<<"$cmdobj" || fail "the schema description of worktrees.warmup[].command does not name the interpreter (bash): $cmdobj"

echo "WARMUP INTERPRETER OK"
