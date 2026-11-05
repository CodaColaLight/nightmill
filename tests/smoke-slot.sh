#!/usr/bin/env bash
# tests/smoke-slot.sh - slot.sh against a throwaway repository: status, take (with warm-up and
# port hints), a full board, the lockfile-hash skip, abandon, and the automatic release of a slot whose pull
# request has merged (--reap and the first step of every take), with --release, against a fake gh.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
S="$here/scripts/slot.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

# A fake gh, first on the PATH for the whole test: it answers "pr list" from $GH_FIX/merged.txt (rows of
# branch TAB number TAB head commit; --state merged only, an open query gives an empty list), logs every call to
# $GH_LOG and fails when GH_FAIL is set. With -q it prints the first number, as gh does for '.[0].number'.
mkdir -p "$tmp/bin" "$tmp/fix"
: > "$tmp/fix/merged.txt"
: > "$tmp/gh.log"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
if [ -n "${GH_FAIL:-}" ]; then echo "HTTP 401: bad credentials" >&2; exit 1; fi
[ "$1 $2" = "pr list" ] || { echo "unexpected gh call: $*" >&2; exit 1; }
state=""; head=""; expr=""
while [ $# -gt 0 ]; do
  case "$1" in --state) state=$2; shift ;; --head) head=$2; shift ;; -q) expr=$2; shift ;; esac
  shift
done
if [ "$state" != merged ]; then echo "[]"; exit 0; fi
rows=$(awk -F'\t' -v h="$head" '$1 == h' "$GH_FIX/merged.txt")
if [ -n "$expr" ]; then printf '%s\n' "$rows" | head -1 | cut -f2; exit 0; fi
out="["; sep=""
while IFS=$'\t' read -r b n o; do
  [ -n "$b" ] || continue
  out="$out$sep{\"number\":$n,\"headRefOid\":\"$o\"}"; sep=","
done <<<"$rows"
echo "$out]"
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" GH_FIX="$tmp/fix" GH_LOG="$tmp/gh.log"

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

echo "== automatic release"
G() { git -C "$1" -c user.name=t -c user.email=t@example.invalid "${@:2}"; }
# prepare <n> <branch>: take slot n on the branch, commit one file there and push it; the tip is left in $tip
prepare() {
  local n=$1 b=$2 d="$tmp/wt/slot-$1"
  bash "$S" --take "$b" --slot "$n" >/dev/null 2>&1
  echo "$b" > "$d/work.txt"
  G "$d" add -A
  G "$d" commit -qm "work on $b"
  git -C "$d" push -q origin "$b" 2>/dev/null
  tip=$(git -C "$d" rev-parse HEAD)
}
merged() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$tmp/fix/merged.txt"; } # branch number commit
reset_gh() { : > "$tmp/fix/merged.txt"; : > "$tmp/gh.log"; }
marker() { echo "$tmp/wt/.slots/slot-$1.json"; }
cleanup() { local n; for n in 1 2; do if [ -f "$(marker "$n")" ]; then bash "$S" --abandon "$n" >/dev/null; fi; done; }
freed1="Slot 1 is free (was feat/m1, PR #12), released automatically."

# 1 merged and clean is freed by --reap
reset_gh; prepare 1 feat/m1; merged feat/m1 12 "$tip"
out=$(bash "$S" --reap 2>/dev/null)
[ "$out" = "$freed1" ] || fail "reap: wrong output: $out"
[ ! -f "$(marker 1)" ] || fail "reap: the marker is still there"
[ -z "$(git -C "$tmp/wt/slot-1" branch --show-current)" ] || fail "reap: the slot is not detached"
[ "$(git -C "$tmp/wt/slot-1" rev-parse HEAD)" = "$(git -C "$tmp/work" rev-parse origin/main)" ] || fail "reap: the slot is not on origin/main"
if git -C "$tmp/work" show-ref --verify --quiet refs/heads/feat/m1; then fail "reap: the local branch is still there"; fi
git -C "$tmp/origin.git" show-ref --verify --quiet refs/heads/feat/m1 || fail "reap: the remote branch is gone"
grep -q 'slot 1  ready           free' <<<"$(bash "$S" --status)" || fail "reap: status does not show slot 1 free"

# 2 a take frees it first; without a freeable slot the same take still fails
# (the pull request only counts as merged after both slots are prepared: every take, preparing included, frees
# merged slots first)
reset_gh; prepare 1 feat/m2; tip1=$tip; prepare 2 feat/live; merged feat/m2 13 "$tip1"
out=$(bash "$S" --take feat/x 2>/dev/null)
a=$(printf '%s\n' "$out" | { grep -n 'released automatically' || true; } | head -1 | cut -d: -f1)
b=$(printf '%s\n' "$out" | { grep -n 'Slot 1 is yours' || true; } | head -1 | cut -d: -f1)
{ [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; } || fail "take: the freed line has to come before the take's own output: $out"
grep -qF 'Slot 1 is free (was feat/m2, PR #13), released automatically.' <<<"$out" || fail "take: wrong freed line: $out"
[ "$(git -C "$tmp/wt/slot-1" branch --show-current)" = "feat/x" ] || fail "take: slot 1 is not on feat/x"
cleanup
reset_gh; prepare 1 feat/n1; prepare 2 feat/n2
if bash "$S" --take feat/y >/dev/null 2>"$tmp/err.txt"; then fail "take with nothing freeable should fail"; fi
grep -q 'all 2 slots are busy' "$tmp/err.txt" || fail "take with nothing freeable: wrong message: $(cat "$tmp/err.txt")"
cleanup

# 3 uncommitted files keep it busy, and gh is not asked about that slot
reset_gh; prepare 1 feat/m3; merged feat/m3 14 "$tip"; echo x > "$tmp/wt/slot-1/untracked.txt"
out=$(bash "$S" --reap 2>/dev/null)
[ "$out" = "No slot freed." ] || fail "dirty: wrong output: $out"
[ -f "$(marker 1)" ] || fail "dirty: the marker is gone"
git -C "$tmp/work" show-ref --verify --quiet refs/heads/feat/m3 || fail "dirty: the branch is gone"
if grep -q 'feat/m3' "$tmp/gh.log"; then fail "dirty: gh was asked about a slot with uncommitted files"; fi
rm "$tmp/wt/slot-1/untracked.txt"; cleanup

# 4 no merged pull request (an open or closed-unmerged one looks the same to the merged query)
reset_gh; prepare 1 feat/m4
out=$(bash "$S" --reap 2>/dev/null)
[ "$out" = "No slot freed." ] || fail "no merged PR: wrong output: $out"
[ -f "$(marker 1)" ] || fail "no merged PR: the marker is gone"
cleanup

# 5 work after the merge keeps it busy, the newer commit is not lost
reset_gh; prepare 1 feat/m5; merged feat/m5 15 "$tip"
echo more > "$tmp/wt/slot-1/more.txt"; G "$tmp/wt/slot-1" add -A; G "$tmp/wt/slot-1" commit -qm "after the merge"
newer=$(git -C "$tmp/wt/slot-1" rev-parse HEAD)
out=$(bash "$S" --reap 2>/dev/null)
[ "$out" = "No slot freed." ] || fail "work after the merge: wrong output: $out"
[ -f "$(marker 1)" ] || fail "work after the merge: the marker is gone"
[ "$(git -C "$tmp/work" rev-parse refs/heads/feat/m5)" = "$newer" ] || fail "work after the merge: the branch lost its newer commit"
cleanup

# 6 a reused branch name: the merged pull request's head is not on this branch at all
reset_gh; prepare 1 feat/m6; merged feat/m6 16 "$(git -C "$tmp/work" rev-parse origin/main)"
out=$(bash "$S" --reap 2>/dev/null)
[ "$out" = "No slot freed." ] || fail "reused branch name: wrong output: $out"
[ -f "$(marker 1)" ] || fail "reused branch name: the marker is gone"
cleanup

# 7 gh failing keeps it busy, says so on standard error and does not break a take
reset_gh; prepare 1 feat/m7; merged feat/m7 17 "$tip"
set +e; out=$(GH_FAIL=1 bash "$S" --reap 2>"$tmp/err.txt"); rc=$?; set -e
[ "$rc" = 0 ] || fail "gh failing: --reap exited $rc"
[ "$out" = "No slot freed." ] || fail "gh failing: wrong output: $out"
grep -q '^slot 1: not checked for a merged PR (' "$tmp/err.txt" || fail "gh failing: no note on standard error: $(cat "$tmp/err.txt")"
[ -f "$(marker 1)" ] || fail "gh failing: the marker is gone"
GH_FAIL=1 bash "$S" --take feat/z >/dev/null 2>&1 || fail "gh failing: a take with a free slot failed"
[ "$(git -C "$tmp/wt/slot-2" branch --show-current)" = "feat/z" ] || fail "gh failing: the take did not use slot 2"
cleanup

# 8 --status is read-only: no gh call, no marker change
reset_gh; prepare 1 feat/m8; merged feat/m8 18 "$tip"; : > "$tmp/gh.log"
before=$(cat "$(marker 1)")
bash "$S" --status >/dev/null; bash "$S" --status --porcelain >/dev/null
[ ! -s "$tmp/gh.log" ] || fail "status asked gh: $(cat "$tmp/gh.log")"
[ "$(cat "$(marker 1)")" = "$before" ] || fail "status changed the marker"
cleanup

# 9 --release and --abandon are unchanged
reset_gh; prepare 1 feat/m9; merged feat/m9 19 "$tip"
out=$(bash "$S" --release 1 2>/dev/null | tail -n 1) # the line before it is git's own "Deleted branch" message
[ "$out" = "Slot 1 is free (was feat/m9, PR #19)." ] || fail "release: wrong output: $out"
prepare 1 feat/m9b
if bash "$S" --release 1 >/dev/null 2>"$tmp/err.txt"; then fail "release without a merged PR should fail"; fi
grep -q 'no merged PR for feat/m9b. Merge it first, or free the slot with --abandon 1.' "$tmp/err.txt" || fail "release: wrong refusal: $(cat "$tmp/err.txt")"
out=$(bash "$S" --abandon 1)
[ "$out" = "Slot 1 is free (was feat/m9b; the local branch is kept, delete it yourself if unwanted)." ] || fail "abandon: wrong output: $out"

# 10 the marker format is unchanged: the keys slot, branch and since, in that order
reset_gh; prepare 1 feat/m10
[ "$(grep -o '"[a-z]*":' "$(marker 1)" | tr -d '\n')" = '"slot":"branch":"since":' ] || fail "marker keys: $(cat "$(marker 1)")"
cleanup

# 11 a marker without a worktree is left alone and does not stop the run
reset_gh
printf '{\n  "slot": 3,\n  "branch": "feat/ghost",\n  "since": "2026-01-01T00:00:00"\n}\n' > "$tmp/wt/.slots/slot-3.json"
set +e; out=$(WORKER_SLOTS=3 bash "$S" --reap 2>/dev/null); rc=$?; set -e
[ "$rc" = 0 ] && [ "$out" = "No slot freed." ] || fail "marker without a worktree: exit $rc, output: $out"
[ -f "$tmp/wt/.slots/slot-3.json" ] || fail "marker without a worktree: the marker was removed"
rm -f "$tmp/wt/.slots/slot-3.json"

# 12 nothing to free
reset_gh
out=$(bash "$S" --reap 2>/dev/null)
[ "$out" = "No slot freed." ] || fail "nothing to free: wrong output: $out"
[ ! -s "$tmp/gh.log" ] || fail "nothing to free: gh was asked: $(cat "$tmp/gh.log")"

echo "SMOKE OK"
