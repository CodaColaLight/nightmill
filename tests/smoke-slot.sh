#!/usr/bin/env bash
# tests/smoke-slot.sh - slot.sh against a throwaway repository: status, take (with warm-up and
# port hints), a full board, the lockfile-hash skip, abandon. --release is not covered (it needs gh
# and a merged PR).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
S="$here/scripts/slot.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

git init -q --bare "$tmp/origin.git"
git init -q -b main "$tmp/work"
cd "$tmp/work"
git config core.autocrlf false
mkdir -p .claude client
cat > .claude/nightmill.json <<'EOF'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "git": { "baseBranch": "main" },
  "worktrees": {
    "root": "../wt",
    "slots": 2,
    "ports": { "server": 8100 },
    "warmup": [ { "dir": "client", "command": "echo warm > warmed.txt", "lockfile": "client/lock.txt" } ],
    "runHints": [ "PORT={port.server} slot {slot}" ]
  }
}
EOF
echo v1 > client/lock.txt
echo warmed.txt > .gitignore
git add -A
git -c user.name=t -c user.email=t@example.invalid commit -qm init
git remote add origin "$tmp/origin.git"
git push -q origin main

echo "== status before anything"
# Output is captured first: with pipefail, grep -q closing the pipe early would fail the pipeline.
grep -q 'slot 1  not created yet free' <<<"$(bash "$S" --status)" || fail "initial status"

echo "== take slot 1"
out=$(bash "$S" --take feat/a)
grep -q "Slot 1 is yours" <<<"$out" || fail "take did not report slot 1"
grep -q "port server: 8101" <<<"$out" || fail "port hint"
grep -q "PORT=8101 slot 1" <<<"$out" || fail "run hint placeholders"
[ -f "$tmp/wt/slot-1/client/warmed.txt" ] || fail "warm-up did not run"
[ "$(git -C "$tmp/wt/slot-1" branch --show-current)" = "feat/a" ] || fail "branch in slot 1"
[ -f "$tmp/wt/.slots/slot-1.json" ] || fail "marker"

echo "== take slot 2, third take fails"
grep -q "Slot 2 is yours" <<<"$(bash "$S" --take feat/b)" || fail "take slot 2"
if bash "$S" --take feat/c 2>/dev/null; then fail "third take should fail"; fi
grep -q 'busy: feat/a' <<<"$(bash "$S" --status)" || fail "status shows slot 1 busy"

echo "== --porcelain: one tab separated line per slot"
T=$'\t'
porc=$(bash "$S" --status --porcelain)
case "$porc" in
  "1${T}busy${T}feat/a${T}"*) ;;
  *) fail "porcelain line for slot 1: $porc" ;;
esac
[ "$(printf '%s\n' "$porc" | sed -n 2p | cut -f1-3)" = "2${T}busy${T}feat/b" ] || fail "porcelain line for slot 2: $porc"
[ "$(printf '%s\n' "$porc" | wc -l | tr -d ' ')" = 2 ] || fail "porcelain line count: $porc"
grep -q 'slots = 2' <<<"$(bash "$S" --status)" || fail "status without --porcelain changed"

echo "== warm-up skipped while the lockfile is unchanged"
bash "$S" --abandon 1 >/dev/null
rm "$tmp/wt/slot-1/client/warmed.txt"
bash "$S" --take feat/d >/dev/null
[ ! -f "$tmp/wt/slot-1/client/warmed.txt" ] || fail "warm-up ran again although the lockfile hash is unchanged"

echo "== WORKER_SLOTS overrides the count"
grep -q 'slot 3' <<<"$(WORKER_SLOTS=3 bash "$S" --status)" || fail "WORKER_SLOTS override"

echo "== abandon both"
bash "$S" --abandon 1 >/dev/null
bash "$S" --abandon 2 >/dev/null
grep -q 'slot 2  ready           free' <<<"$(bash "$S" --status)" || fail "slot 2 free after abandon"
[ "$(bash "$S" --status --porcelain)" = "$(printf '1\tfree\n2\tfree')" ] || fail "porcelain after abandon"

echo "SMOKE OK"
