#!/usr/bin/env bash
# tests/smoke-slot.sh - slot.sh against a throwaway repository: status, take (with warm-up and
# port hints), a full board, the lockfile-hash skip, abandon, and the automatic release of a slot whose pull
# request has merged (--reap and the first step of every take), with --release, against a fake gh, and the
# capacity command (--capacity: the slot count and the agent limit changed during a session), the reports
# (--report) and the claim of a take (iteration 34: a take claims its slot with a marker in the state "taking"
# before it fetches, switches or warms up; two takes get different slots; a failed take puts its slot back; a
# dead claim is freed only by --abandon).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-slot.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
S="$here/scripts/slot.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

# A fake gh, first on the PATH for the whole test: it answers "pr list" from $GH_FIX/merged.txt (rows of
# branch TAB number TAB head commit, then (iteration 41) TAB createdAt TAB mergedAt TAB the closing issue numbers
# joined by commas, all three optional; --state merged only, an open query gives an empty list), logs every call to
# $GH_LOG and fails when GH_FAIL is set. With -q it prints the first number, as gh does for '.[0].number'. With
# --json it prints the requested fields among number, headRefOid, createdAt, mergedAt and closingIssuesReferences.
mkdir -p "$tmp/bin" "$tmp/fix"
: > "$tmp/fix/merged.txt"
: > "$tmp/gh.log"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
if [ -n "${GH_FAIL:-}" ]; then echo "HTTP 401: bad credentials" >&2; exit 1; fi
[ "$1 $2" = "pr list" ] || { echo "unexpected gh call: $*" >&2; exit 1; }
state=""; head=""; expr=""; fields="number,headRefOid"
while [ $# -gt 0 ]; do
  case "$1" in --state) state=$2; shift ;; --head) head=$2; shift ;; -q) expr=$2; shift ;; --json) fields=$2; shift ;; esac
  shift
done
if [ "$state" != merged ]; then echo "[]"; exit 0; fi
rows=$(awk -F'\t' -v h="$head" '$1 == h' "$GH_FIX/merged.txt")
if [ -n "$expr" ]; then printf '%s\n' "$rows" | head -1 | cut -f2; exit 0; fi
out="["; sep=""
while IFS=$'\t' read -r b n o c m i; do
  [ -n "$b" ] || continue
  obj=""; osep=""
  for fld in $(printf '%s\n' "$fields" | tr ',' ' '); do
    case "$fld" in
      number) val="$n" ;;
      headRefOid) val="\"$o\"" ;;
      createdAt) val="\"${c:-}\"" ;;
      mergedAt) val="\"${m:-}\"" ;;
      closingIssuesReferences)
        val="["; isep=""
        for k in $(printf '%s\n' "${i:-}" | tr ',' ' '); do
          val="$val$isep{\"id\":\"I_$k\",\"number\":$k,\"repository\":{\"name\":\"widgets\",\"owner\":{\"login\":\"acme\"}},\"url\":\"https://example.invalid/issues/$k\"}"; isep=","
        done
        val="$val]" ;;
      *) continue ;;
    esac
    obj="$obj$osep\"$fld\":$val"; osep=","
  done
  out="$out$sep{$obj}"; sep=","
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

echo "== capacity"
# --capacity (iteration 22): the slot count and the agent limit, set during a session in <root>/.slots/capacity.json
C="$tmp/wt/.slots/capacity.json"
CFG="$tmp/work/.claude/nightmill.json"
cp "$CFG" "$tmp/cfg-before.json"
nl=$'\n'
show() { bash "$S" --capacity "$@"; }
reset_gh; rm -f "$C"

# 1 no value prints the numbers
out=$(show)
[ "$out" = "slots: 2 (config)${nl}agents: 2 (default)" ] || fail "capacity show: $out"
out=$(WORKER_SLOTS=4 bash "$S" --capacity)
[ "$out" = "slots: 4 (WORKER_SLOTS; config 2)${nl}agents: 2 (default)" ] || fail "capacity show with WORKER_SLOTS: $out"
[ ! -e "$C" ] || fail "showing wrote capacity.json"

# 2 set prints one line and keeps the file; the tracked config is not edited
out=$(show --slot-count 3 --agent-limit 3)
[ "$out" = "capacity: slots 2 -> 3, agents 2 -> 3" ] || fail "capacity set: $out"
grep -q '^  "slots": 3,$' "$C" || fail "capacity.json has no slots 3: $(cat "$C")"
grep -q '^  "maxAgents": 3,$' "$C" || fail "capacity.json has no maxAgents 3: $(cat "$C")"
grep -q '^  "since": "[0-9-]*T[0-9:]*"$' "$C" || fail "capacity.json has no since: $(cat "$C")"
cmp -s "$CFG" "$tmp/cfg-before.json" || fail "the config file was edited"
[ -z "$(git -C "$tmp/work" status --porcelain)" ] || fail "the checkout is not clean after a set"
out=$(show)
[ "$out" = "slots: 3 (live; config 2)${nl}agents: 3 (live; config 2)" ] || fail "capacity show after set: $out"
out=$(show --agent-limit 4)
[ "$out" = "capacity: agents 3 -> 4" ] || fail "capacity set agents only: $out"
[ "$(show | head -n 1)" = "slots: 3 (live; config 2)" ] || fail "setting the agent limit changed the slot count"
out=$(show --slot-count 3)
[ "$out" = "capacity: slots 3 (unchanged)" ] || fail "capacity set unchanged: $out"
show --agent-limit 3 >/dev/null

# 3 raising makes the new slot available; its worktree is created by the take
[ ! -d "$tmp/wt/slot-3" ] || fail "slot 3 exists before it was taken"
for i in 1 2 3; do
  grep -q "Slot $i is yours" <<<"$(bash "$S" --take "feat/c$i" 2>/dev/null)" || fail "raised count: take $i did not get slot $i"
done
[ -d "$tmp/wt/slot-3" ] || fail "the take did not create the worktree of slot 3"

# 4 lowering never touches a busy slot: it is retiring until released
m2=$(cat "$(marker 2)"); m3=$(cat "$(marker 3)")
h2=$(git -C "$tmp/wt/slot-2" rev-parse HEAD); h3=$(git -C "$tmp/wt/slot-3" rev-parse HEAD)
out=$(show --slot-count 1)
[ "$out" = "capacity: slots 3 -> 1" ] || fail "capacity lower: $out"
[ "$(cat "$(marker 2)")" = "$m2" ] && [ "$(cat "$(marker 3)")" = "$m3" ] || fail "lowering changed a marker"
[ "$(git -C "$tmp/wt/slot-2" rev-parse HEAD)" = "$h2" ] && [ "$(git -C "$tmp/wt/slot-3" rev-parse HEAD)" = "$h3" ] || fail "lowering changed a worktree"
[ "$(git -C "$tmp/wt/slot-3" branch --show-current)" = "feat/c3" ] || fail "lowering switched slot 3"
st=$(bash "$S" --status)
grep -q '^slots = 1  root = ' <<<"$st" || fail "status header after lowering: $st"
grep -q '^capacity: slots 1 (live; config 2), agents 3 (live; config 2)$' <<<"$st" || fail "status capacity line: $st"
grep -q '^slot 2  ready           busy: feat/c2 since .* (retiring)$' <<<"$st" || fail "status: slot 2 is not retiring: $st"
grep -q '^slot 3  ready           busy: feat/c3 since .* (retiring)$' <<<"$st" || fail "status: slot 3 is not retiring: $st"
grep -q '^slot 1 .*busy: feat/c1 since [0-9T:-]*$' <<<"$st" || fail "status: slot 1 must not be retiring: $st"
porc=$(bash "$S" --status --porcelain)
[ "$(printf '%s\n' "$porc" | wc -l | tr -d ' ')" = 3 ] || fail "porcelain after lowering: $porc"
[ "$(printf '%s\n' "$porc" | sed -n 1p | cut -f5)" = "" ] || fail "porcelain: slot 1 has a fifth field: $porc"
[ "$(printf '%s\n' "$porc" | sed -n 2p | cut -f1-3,5)" = "2${T}busy${T}feat/c2${T}retiring" ] || fail "porcelain: slot 2: $porc"
[ "$(printf '%s\n' "$porc" | sed -n 3p | cut -f1-3,5)" = "3${T}busy${T}feat/c3${T}retiring" ] || fail "porcelain: slot 3: $porc"
if bash "$S" --take feat/c9 >/dev/null 2>"$tmp/err.txt"; then fail "a take above the lowered count should fail"; fi
grep -q 'all 1 slots are busy' "$tmp/err.txt" || fail "take after lowering: wrong message: $(cat "$tmp/err.txt")"
merged feat/c3 23 "$h3"; merged feat/c2 22 "$h2"
bash "$S" --release 3 >/dev/null 2>&1 || fail "releasing the retiring slot 3 failed"
porc=$(bash "$S" --status --porcelain)
[ "$(printf '%s\n' "$porc" | cut -f1 | tr '\n' ' ')" = "1 2 " ] || fail "after releasing slot 3: $porc"
bash "$S" --release 2 >/dev/null 2>&1 || fail "releasing the retiring slot 2 failed"
porc=$(bash "$S" --status --porcelain)
[ "$(printf '%s\n' "$porc" | cut -f1 | tr '\n' ' ')" = "1 " ] || fail "after releasing slot 2: $porc"
grep -q '^slot 2' <<<"$(bash "$S" --status)" && fail "a free slot above the count is listed"
[ -d "$tmp/wt/slot-2" ] && [ -d "$tmp/wt/slot-3" ] || fail "a worktree above the count was removed"
reset_gh

# 5 a raised count brings a retired slot back, warm
show --slot-count 3 >/dev/null
porc=$(bash "$S" --status --porcelain)
[ "$(printf '%s\n' "$porc" | sed -n '2,3p')" = "2${T}free${nl}3${T}free" ] || fail "raised again: slots 2 and 3 are not free: $porc"
grep -q "Slot 2 is yours" <<<"$(bash "$S" --take feat/c4 2>/dev/null)" || fail "raised again: slot 2 not taken"
grep -q "Slot 3 is yours" <<<"$(bash "$S" --take feat/c5 2>/dev/null)" || fail "raised again: slot 3 not taken"
for n in 1 2 3; do bash "$S" --abandon "$n" >/dev/null; done

# 6 --reap frees a retiring slot whose pull request has merged
reset_gh; prepare 3 feat/r3; merged feat/r3 24 "$tip"
show --slot-count 1 >/dev/null
out=$(bash "$S" --reap 2>/dev/null)
[ "$out" = "Slot 3 is free (was feat/r3, PR #24), released automatically." ] || fail "reap of a retiring slot: $out"
[ ! -f "$(marker 3)" ] || fail "reap of a retiring slot: the marker is still there"
reset_gh

# 7 invalid values change nothing and say why
cp "$C" "$tmp/cap-before.json"
for opt in --slot-count --agent-limit; do
  for v in 0 -1 2.5 x "" 100; do
    set +e; bash "$S" --capacity "$opt" "$v" >"$tmp/out.txt" 2>"$tmp/err.txt"; rc=$?; set -e
    [ "$rc" = 1 ] || fail "invalid $opt '$v': exit $rc"
    grep -qxF "capacity: $opt must be a whole number from 1 to 99, got \"$v\"" "$tmp/err.txt" || fail "invalid $opt '$v': message: $(cat "$tmp/err.txt")"
    [ ! -s "$tmp/out.txt" ] || fail "invalid $opt '$v': printed $(cat "$tmp/out.txt")"
    cmp -s "$C" "$tmp/cap-before.json" || fail "invalid $opt '$v' changed capacity.json"
  done
done
if bash "$S" --capacity --slot-count 2 --agent-limit x >/dev/null 2>&1; then fail "a valid value with an invalid one was accepted"; fi
cmp -s "$C" "$tmp/cap-before.json" || fail "a valid value given with an invalid one was written"
rm -f "$C"
if bash "$S" --capacity --slot-count 0 >/dev/null 2>&1; then fail "invalid value without a file was accepted"; fi
[ ! -e "$C" ] || fail "an invalid value created capacity.json"

# 8 --clear
show --slot-count 3 --agent-limit 3 >/dev/null
out=$(show --clear)
[ "$out" = "capacity: cleared (slots 3 -> 2, agents 3 -> 2)" ] || fail "clear: $out"
[ ! -e "$C" ] || fail "clear left capacity.json"
out=$(show --clear)
[ "$out" = "capacity: nothing to clear" ] || fail "second clear: $out"
if bash "$S" --capacity --clear --slot-count 2 >/dev/null 2>"$tmp/err.txt"; then fail "--clear with a value is not a usage error"; fi
grep -q '^usage: ' "$tmp/err.txt" || fail "--clear with a value: no usage line: $(cat "$tmp/err.txt")"
if bash "$S" --capacity --slot-count 2 --slot-count 3 >/dev/null 2>&1; then fail "a value given twice is not a usage error"; fi
[ ! -e "$C" ] || fail "a usage error wrote capacity.json"

# 9 and 10 precedence, shown and in porcelain
[ "$(show --porcelain)" = "slots${T}2${T}config${T}2${nl}agents${T}2${T}default${T}2" ] || fail "porcelain config/default: $(show --porcelain)"
[ "$(WORKER_SLOTS=4 bash "$S" --capacity --porcelain)" = "slots${T}4${T}WORKER_SLOTS${T}2${nl}agents${T}2${T}default${T}2" ] || fail "porcelain WORKER_SLOTS"
out=$(show --porcelain --slot-count 3 --agent-limit 3)
[ "$out" = "slots${T}3${T}live${T}2${nl}agents${T}3${T}live${T}2" ] || fail "porcelain set: $out"
[ "$(WORKER_SLOTS=4 bash "$S" --capacity | head -n 1)" = "slots: 3 (live; config 2)" ] || fail "live does not win over WORKER_SLOTS"
[ "$(WORKER_SLOTS=4 bash "$S" --status --porcelain | wc -l | tr -d ' ')" = 3 ] || fail "--status does not use the live count over WORKER_SLOTS"
show --clear >/dev/null
sed 's/"git": { "baseBranch": "main" },/"git": { "baseBranch": "main" }, "parallel": { "maxAgents": 5 },/' "$tmp/cfg-before.json" > "$CFG"
grep -q '"maxAgents": 5' "$CFG" || fail "the config copy has no maxAgents"
[ "$(show | sed -n 2p)" = "agents: 5 (config)" ] || fail "config does not win over the default: $(show)"
[ "$(show --porcelain | sed -n 2p)" = "agents${T}5${T}config${T}5" ] || fail "porcelain config agents"
show --agent-limit 3 >/dev/null
[ "$(show | sed -n 2p)" = "agents: 3 (live; config 5)" ] || fail "live does not win over the config: $(show)"
[ "$(show --porcelain | sed -n 2p)" = "agents${T}3${T}live${T}5" ] || fail "porcelain live agents over config"
show --clear >/dev/null
cp "$tmp/cfg-before.json" "$CFG"

# 11 an unusable capacity.json is ignored with a note
unusable() { # unusable <content> <expected show output> <reason>
  printf '%s\n' "$1" > "$C"
  out=$(bash "$S" --capacity 2>"$tmp/err.txt")
  [ "$out" = "$2" ] || fail "unusable capacity.json '$1': $out"
  grep -qxF "slot: capacity.json: $3; using the configuration" "$tmp/err.txt" || fail "unusable capacity.json '$1': note: $(cat "$tmp/err.txt")"
}
unusable 'not json' "slots: 2 (config)${nl}agents: 2 (default)" "not valid JSON"
unusable '[1, 2]' "slots: 2 (config)${nl}agents: 2 (default)" "not an object"
unusable '{ "slots": "x" }' "slots: 2 (config)${nl}agents: 2 (default)" "slots is not a whole number from 1 to 99"
unusable '{ "slots": 0, "maxAgents": 3 }' "slots: 2 (config)${nl}agents: 3 (live; config 2)" "slots is not a whole number from 1 to 99"
printf 'not json\n' > "$C"
grep -q "Slot 1 is yours" <<<"$(bash "$S" --take feat/u 2>/dev/null)" || fail "a take with an unusable capacity.json failed"
bash "$S" --status >/dev/null 2>&1 || fail "a status with an unusable capacity.json failed"
bash "$S" --abandon 1 >/dev/null 2>&1
rm -f "$C"

# 12 nothing else changed: the marker keys, and no capacity.json without --capacity
reset_gh; prepare 1 feat/m12
[ "$(grep -o '"[a-z]*":' "$(marker 1)" | tr -d '\n')" = '"slot":"branch":"since":' ] || fail "marker keys after capacity: $(cat "$(marker 1)")"
[ ! -e "$C" ] || fail "a take wrote capacity.json"
cleanup
if bash "$S" --slot-count 3 >/dev/null 2>&1; then fail "--slot-count without --capacity is not a usage error"; fi

echo "== reports"
# --report (iteration 23): the skill, the role, the step and the time of the last report in the slot's marker, and
# --status --porcelain with the agent state (running, stalled, unknown) and the reported fields
reset_gh
S1="$tmp/wt/.slots"
mtext() { cat "$(marker "$1")"; }
mget() { ( json_load "$(marker "$1")" && json_get "$2" ); } # mget <n> <key>
# shellcheck source=../scripts/lib/json.sh
. "$here/scripts/lib/json.sh"
# rep <arguments>: run slot.sh with them; standard output in $out, standard error in $err, the exit code in $rc
rep() { set +e; out=$(bash "$S" "$@" 2>"$tmp/err.txt"); rc=$?; set -e; err=$(cat "$tmp/err.txt"); }
stamp_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$'
bash "$S" --take feat/r1 --slot 1 >/dev/null 2>&1
t_branch=$(mget 1 branch); t_since=$(mget 1 since)

# 1 a report writes the fields
rep --report tests --slot 1 --skill next --role implementer
[ "$rc" = 0 ] || fail "report: exit $rc: $err"
[ -z "$out" ] && [ -z "$err" ] || fail "report printed something: $out / $err"
[ "$(grep -o '"[a-z]*":' "$(marker 1)" | tr -d '\n')" = '"slot":"branch":"since":"skill":"role":"step":"reported":' ] || fail "report: marker keys: $(mtext 1)"
[ "$t_branch" = feat/r1 ] && [ "$(mget 1 branch)" = "$t_branch" ] && [ "$(mget 1 since)" = "$t_since" ] && [ "$(mget 1 slot)" = 1 ] || fail "report: slot, branch or since changed: $(mtext 1)"
[ "$(mget 1 skill)/$(mget 1 role)/$(mget 1 step)" = next/implementer/tests ] || fail "report: skill, role, step: $(mtext 1)"
r1=$(mget 1 reported)
[[ "$r1" =~ $stamp_re ]] || fail "report: reported has not the form YYYY-MM-DDTHH:MM:SS: $r1"
want=$(printf '{\n  "slot": 1,\n  "branch": "feat/r1",\n  "since": "%s",\n  "skill": "next",\n  "role": "implementer",\n  "step": "tests",\n  "reported": "%s"\n}' "$t_since" "$r1")
[ "$(mtext 1)" = "$want" ] || fail "report: the marker text: $(mtext 1)"
[ "$(tail -c 1 "$(marker 1)" | od -An -c | tr -d ' ')" = '\n' ] || fail "report: the marker does not end with a newline"
if grep -q $'\r' "$(marker 1)"; then fail "report: the marker is not LF"; fi
[ ! -e "$S1/slot-1.report.tmp" ] || fail "report: the temporary file is left"

# 2 a second report replaces the step and the time and keeps since
printf '{\n  "slot": 1,\n  "branch": "feat/r1",\n  "since": "%s",\n  "skill": "next",\n  "role": "implementer",\n  "step": "tests",\n  "reported": "2020-01-01T00:00:00"\n}\n' "$t_since" > "$(marker 1)"
rep --report check --slot 1 --skill next --role implementer
[ "$rc" = 0 ] || fail "second report: exit $rc: $err"
[ "$(mget 1 step)" = check ] || fail "second report: step: $(mtext 1)"
[ "$(mget 1 reported)" != "2020-01-01T00:00:00" ] && [[ "$(mget 1 reported)" =~ $stamp_re ]] || fail "second report: reported: $(mtext 1)"
[ "$(mget 1 since)" = "$t_since" ] || fail "second report: since changed: $(mtext 1)"

# 3 refusals change nothing
before=$(mtext 1)
refused() { # refused <expected standard error> <arguments...>; "usage" for the usage line
  local want=$1; shift
  rep "$@"
  [ "$rc" = 1 ] || fail "refusal ($*): exit $rc"
  if [ "$want" = usage ]; then
    [[ "$err" == "usage: "* ]] || fail "refusal ($*): no usage line: $err"
  else
    [ "$err" = "$want" ] || fail "refusal ($*): message: $err"
  fi
  [ -z "$out" ] || fail "refusal ($*): printed $out"
  [ "$(mtext 1)" = "$before" ] || fail "refusal ($*): the marker changed: $(mtext 1)"
  [ ! -e "$S1/slot-1.report.tmp" ] && [ ! -e "$S1/slot-2.report.tmp" ] || fail "refusal ($*): a temporary file is left"
  [ ! -e "$(marker 2)" ] || fail "refusal ($*): a marker of slot 2 was written"
}
long41=$(printf 'a%.0s' $(seq 41)); long40=$(printf 'b%.0s' $(seq 40))
refused "report needs a slot number" --report tests --skill next --role implementer
refused "report needs a slot number" --report tests --slot 0 --skill next --role implementer
refused "slot 2 is not in use" --report tests --slot 2 --skill next --role implementer
for v in "" "a b" "a.b" "$long41" $'a\tb'; do
  refused "report: the step must be 1 to 40 letters, digits or -, got \"$v\"" --report "$v" --slot 1 --skill next --role implementer
done
refused 'report: the skill must be 1 to 40 letters, digits or -, got ""' --report tests --slot 1 --role implementer
refused 'report: the role must be 1 to 40 letters, digits or -, got ""' --report tests --slot 1 --skill next
refused 'report: the skill must be 1 to 40 letters, digits or -, got "n/x"' --report tests --slot 1 --skill n/x --role implementer
refused usage --report tests --slot 1 --skill next --role implementer --status
refused usage --status --skill next
refused usage --role implementer --slot 1
refused usage --report tests --slot 1 --skill next --role implementer --capacity
refused usage --report
cp "$(marker 1)" "$tmp/marker-good.json"
printf 'not json\n' > "$(marker 1)"; before=$(mtext 1)
refused "slot 1: the marker is not valid JSON" --report tests --slot 1 --skill next --role implementer
cp "$tmp/marker-good.json" "$(marker 1)"
rep --report "$long40" --slot 1 --skill fix --role fixer
[ "$rc" = 0 ] && [ "$(mget 1 step)" = "$long40" ] && [ "$(mget 1 skill)/$(mget 1 role)" = fix/fixer ] || fail "a step of 40 characters was refused: $err"

# 4 porcelain carries the fields
rep --report check --slot 1 --skill next --role implementer
r1=$(mget 1 reported)
porc=$(bash "$S" --status --porcelain)
[ "$(printf '%s\n' "$porc" | sed -n 1p)" = "1${T}busy${T}feat/r1${T}${t_since}${T}${T}running${T}next${T}implementer${T}check${T}${r1}" ] || fail "porcelain with a report: $porc"
[ "$(printf '%s\n' "$porc" | sed -n 1p | awk -F '\t' '{ print NF }')" = 10 ] || fail "porcelain: not ten fields: $porc"
[ "$(printf '%s\n' "$porc" | sed -n 2p)" = "2${T}free" ] || fail "porcelain: the free line changed: $porc"

# 5 running and stalled by the default threshold (30 minutes); 2026-11-05T11:30:00 is 1793878200 on the clock of the
# scripts (local time read as UTC)
hand() { # hand <n> <step> <reported> [file]: a seven-key marker written by hand
  printf '{\n  "slot": %s,\n  "branch": "feat/r%s",\n  "since": "2026-11-05T09:00:00",\n  "skill": "next",\n  "role": "implementer",\n  "step": "%s",\n  "reported": "%s"\n}\n' "$1" "$1" "$2" "$3" > "${4:-$(marker "$1")}"
}
agent() { # agent <now> [n]: field 6 of slot n (1) in --status --porcelain with NIGHTMILL_NOW=<now>; stderr in $tmp/err.txt
  NIGHTMILL_NOW=$1 bash "$S" --status --porcelain 2>"$tmp/err.txt" | awk -F '\t' -v n="${2:-1}" '$1 == n { print $6 }'
}
B=1793878200
hand 1 check 2026-11-05T11:30:00
[ "$(agent $((B + 1800)))" = running ] || fail "1800 seconds after the report is not running"
[ "$(agent $((B + 1801)))" = stalled ] || fail "1801 seconds after the report is not stalled"
[ "$(agent $((B - 600)))" = running ] || fail "a report in the future is not running"
[ ! -s "$tmp/err.txt" ] || fail "the default threshold printed: $(cat "$tmp/err.txt")"

# 6 the threshold comes from the config
cp "$CFG" "$tmp/cfg-reports.json"
setcfg() { sed "s/\"slots\": 2,/\"slots\": 2, \"stalledAfterMinutes\": $1,/" "$tmp/cfg-reports.json" > "$CFG"; }
setcfg 5
grep -q '"stalledAfterMinutes": 5,' "$CFG" || fail "the config copy has no stalledAfterMinutes"
[ "$(agent $((B + 300)))" = running ] || fail "threshold 5: 300 seconds is not running"
[ "$(agent $((B + 301)))" = stalled ] || fail "threshold 5: 301 seconds is not stalled"

# 7 an unusable threshold falls back to 30
warn="slot: worktrees.stalledAfterMinutes must be a whole number of at least 1; using 30"
for v in 0 -5 2.5 30.0 '"30"' '"x"' true; do
  setcfg "$v"
  set +e; NIGHTMILL_NOW=$((B + 1800)) bash "$S" --status --porcelain >"$tmp/out.txt" 2>"$tmp/err.txt"; rc=$?; set -e
  [ "$rc" = 0 ] || fail "threshold $v: exit $rc"
  [ "$(cat "$tmp/err.txt")" = "$warn" ] || fail "threshold $v: standard error: $(cat "$tmp/err.txt")"
  [ "$(awk -F '\t' '$1 == 1 { print $6 }' "$tmp/out.txt")" = running ] || fail "threshold $v: 1800 seconds is not running"
  [ "$(agent $((B + 1801)))" = stalled ] || fail "threshold $v: 1801 seconds is not stalled"
done
setcfg null
[ "$(agent $((B + 1800)))" = running ] && [ "$(agent $((B + 1801)))" = stalled ] && [ ! -s "$tmp/err.txt" ] || fail "threshold null: $(cat "$tmp/err.txt")"
cp "$tmp/cfg-reports.json" "$CFG"
[ "$(agent $((B + 1800)))" = running ] && [ "$(agent $((B + 1801)))" = stalled ] && [ ! -s "$tmp/err.txt" ] || fail "no threshold key: $(cat "$tmp/err.txt")"
# without worktrees the root is ../<checkout>-wt and there are two slots
sed '/"worktrees": {/,/^  }/d; s/"git": { "baseBranch": "main" },/"git": { "baseBranch": "main" }/' "$tmp/cfg-reports.json" > "$CFG"
! grep -q worktrees "$CFG" || fail "the config copy still has worktrees"
mkdir -p "$tmp/work-wt/.slots"; hand 1 check 2026-11-05T11:30:00 "$tmp/work-wt/.slots/slot-1.json"
[ "$(agent $((B + 1800)))" = running ] && [ "$(agent $((B + 1801)))" = stalled ] && [ ! -s "$tmp/err.txt" ] || fail "no worktrees: $(cat "$tmp/err.txt")"
rm -rf "$tmp/work-wt"
cp "$tmp/cfg-reports.json" "$CFG"

# 8 the step plays no part
for s in "done" "stopped"; do
  hand 1 "$s" 2026-11-05T11:30:00
  [ "$(agent $((B + 1800)))" = running ] && [ "$(agent $((B + 1801)))" = stalled ] || fail "the step $s changes the agent state"
done

# 9 a marker of the previous version is busy with an unknown step
json_marker 1 feat/r1 2026-11-05T09:00:00 > "$(marker 1)"
line=$(NIGHTMILL_NOW=$B bash "$S" --status --porcelain | sed -n 1p)
[ "$line" = "1${T}busy${T}feat/r1${T}2026-11-05T09:00:00${T}${T}unknown${T}${T}${T}${T}" ] || fail "a three-key marker: $line"
hand 1 check yesterday
[ "$(agent "$B")" = unknown ] || fail "a reported that is not of the form is not unknown"
# a retiring slot (above the count) takes a report too
json_marker 3 feat/r3 2026-11-05T09:00:00 > "$(marker 3)"
rep --report check --slot 3 --skill fix --role fixer
[ "$rc" = 0 ] || fail "report on a retiring slot: $err"
line=$(bash "$S" --status --porcelain | sed -n 3p)
[ "$(printf '%s\n' "$line" | cut -f1-2,5-9)" = "3${T}busy${T}retiring${T}running${T}fix${T}fixer${T}check" ] || fail "a retiring slot with a report: $line"
rm -f "$(marker 3)"

# 11 the take and the human --status are unchanged
hand 1 code 2026-11-05T11:30:00
grep -q '^slot 1  ready           busy: feat/r1 since 2026-11-05T09:00:00$' <<<"$(bash "$S" --status)" || fail "status without --porcelain changed: $(bash "$S" --status)"

# 12 --status stays read-only
hand 2 check 2026-11-05T11:00:00
: > "$tmp/gh.log"; m1=$(mtext 1); m2=$(mtext 2)
bash "$S" --status --porcelain >/dev/null; bash "$S" --status >/dev/null
[ ! -s "$tmp/gh.log" ] || fail "status with reports asked gh: $(cat "$tmp/gh.log")"
[ "$(mtext 1)" = "$m1" ] && [ "$(mtext 2)" = "$m2" ] || fail "status changed a marker with a report"
rm -f "$(marker 2)"

# 10 a reported slot is abandoned, reaped and released as before
out=$(bash "$S" --abandon 1)
[ "$out" = "Slot 1 is free (was feat/r1; the local branch is kept, delete it yourself if unwanted)." ] || fail "abandon of a reported slot: $out"
[ ! -f "$(marker 1)" ] || fail "abandon left the marker of a reported slot"
reset_gh; prepare 1 feat/rm; bash "$S" --report "done" --slot 1 --skill next --role session; merged feat/rm 31 "$tip"
[ "$(mget 1 step)" = "done" ] || fail "the report before the reap"
out=$(bash "$S" --reap 2>/dev/null)
[ "$out" = "Slot 1 is free (was feat/rm, PR #31), released automatically." ] || fail "reap of a reported slot: $out"
[ ! -f "$(marker 1)" ] || fail "reap left the marker of a reported slot"
reset_gh; prepare 1 feat/rl; bash "$S" --report "done" --slot 1 --skill fix --role session; merged feat/rl 32 "$tip"
out=$(bash "$S" --release 1 2>/dev/null | tail -n 1)
[ "$out" = "Slot 1 is free (was feat/rl, PR #32)." ] || fail "release of a reported slot: $out"
[ ! -f "$(marker 1)" ] || fail "release left the marker of a reported slot"
rep --report check --slot 1 --skill next --role implementer
[ "$rc" = 1 ] && [ "$err" = "slot 1 is not in use" ] && [ ! -e "$(marker 1)" ] || fail "a report after the release brought the marker back: $err"
reset_gh

echo "== claim (iteration 34)"
# claim (iteration 34): a take claims its slot, a marker with "state": "taking" and its process id, before it fetches,
# switches or warms up. Seven cases: (1) two takes at the same time get different slots, also when origin has moved;
# (2) a take still working is shown as taken and kept; (3) a failed fetch, switch or warm-up puts the slot back and
# frees the claim; (4) a dead claim is freed only by --abandon; (5) markers across versions; (6) git itself sees the
# claim at the fetch, the worktree add and the switch; (7) the publish is exclusive, in one shell and across the two.
# A gate warm-up holds a take at its warm-up until <tmp>/go exists, and NIGHTMILL_CLAIM_GATE holds it at the publish.
reset_gh
cp "$CFG" "$tmp/cfg-claim.json"
bg_pids=()
claim_stop() { # opens both gates and waits for the background takes, so that none outlives the test
  local p
  : > "$tmp/go"; : > "$tmp/claim-go"
  for p in ${bg_pids[@]+"${bg_pids[@]}"}; do wait "$p" 2>/dev/null || true; done
  bg_pids=()
}
fail() { claim_stop; echo "FAIL: $*" >&2; exit 1; }
claim_root=$(bash "$S" --status | sed -n '1s/^slots = [0-9]*  root = //p')
[ -n "$claim_root" ] || fail "claim: no root in the status header"
gate_cmd="i=0; while [ ! -e '$tmp/go' ]; do i=\$((i+1)); [ \$i -lt 1200 ] || exit 9; sleep 0.1; done"
gate_json="[ { \"command\": \"$gate_cmd\" } ]"
exit7_json='[ { "command": "exit 7" } ]'
write_cfg() { # write_cfg <worktrees.warmup as JSON>: the test config with that warm-up
  cat > "$CFG" <<EOF
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "git": { "baseBranch": "main" },
  "worktrees": {
    "root": "../wt",
    "slots": 2,
    "ports": { "server": 8100 },
    "warmup": $1,
    "runHints": [ "PORT={port.server} slot {slot}" ]
  }
}
EOF
}
# bg_take <name> <arguments>: slot.sh in the background; standard output and error go to $tmp/<name>.out and .err, the
# process id is left in $bg_pid. bg_wait <pid> <name> then leaves $rc, $out and $err (without carriage returns).
bg_take() { local name=$1; shift; bash "$S" "$@" >"$tmp/$name.out" 2>"$tmp/$name.err" & bg_pid=$!; bg_pids+=("$bg_pid"); }
bg_ps() { local name=$1; shift; powershell -NoProfile -ExecutionPolicy Bypass -File "$ps_slot" "$@" >"$tmp/$name.out" 2>"$tmp/$name.err" & bg_pid=$!; bg_pids+=("$bg_pid"); }
bg_wait() { rc=0; wait "$1" || rc=$?; out=$(tr -d '\r' < "$tmp/$2.out"); err=$(tr -d '\r' < "$tmp/$2.err"); }
bg_alive() { local p; for p in ${bg_pids[@]+"${bg_pids[@]}"}; do if kill -0 "$p" 2>/dev/null; then return 0; fi; done; return 1; }
bg_winpid() { if [ -r "/proc/$1/winpid" ]; then cat "/proc/$1/winpid"; else echo "$1"; fi; } # the id the script records for that process
mypid() { if [ -r "/proc/$$/winpid" ]; then cat "/proc/$$/winpid"; else echo "$$"; fi; }
dead_pid() { bash -c 'if [ -r /proc/$$/winpid ]; then cat /proc/$$/winpid; else echo $$; fi'; }
c_porc9() { bash "$S" --status --porcelain 2>/dev/null | awk -F '\t' -v n="$1" '$1 == n { print $9 }' || true; }
waitfor() { # waitfor <n> <state>: until field 9 of slot n in --status --porcelain is <state> (60 s at most)
  local end=$((SECONDS + 60)) got
  while :; do
    got=$(c_porc9 "$1")
    if [ "$got" = "$2" ]; then return 0; fi
    [ "$SECONDS" -lt "$end" ] || fail "waitfor: slot $1 did not show the step '$2' within 60 s (field 9: '$got'): $(bash "$S" --status --porcelain 2>&1)"
    bg_alive || fail "waitfor: every background take ended and slot $1 never showed the step '$2' (field 9: '$got'): $(cat "$tmp"/*.err 2>/dev/null | tail -n 5)"
    sleep 0.1
  done
}
wait_claims() { # wait_claims <n> <count>: until .slots holds that many slot-<n>.claim.*.tmp files (60 s at most)
  local end=$((SECONDS + 60)) c
  while :; do
    c=$(n=0; for f in "$S1"/slot-"$1".claim.*.tmp; do if [ -e "$f" ]; then n=$((n + 1)); fi; done; echo "$n")
    if [ "$c" -ge "$2" ]; then return 0; fi
    [ "$SECONDS" -lt "$end" ] || fail "wait_claims: slot $1 has $c claim files, not $2, after 60 s"
    bg_alive || fail "wait_claims: every background take ended with $c claim files of slot $1, not $2: $(cat "$tmp"/*.err 2>/dev/null | tail -n 5)"
    sleep 0.1
  done
}
taking_text() { # taking_text <slot> <branch> <since> [pid]: the text of a taking marker (without the pid line when no pid is given)
  if [ $# -ge 4 ]; then
    printf '{\n  "slot": %s,\n  "branch": "%s",\n  "since": "%s",\n  "state": "taking",\n  "pid": %s\n}\n' "$1" "$2" "$3" "$4"
  else
    printf '{\n  "slot": %s,\n  "branch": "%s",\n  "since": "%s",\n  "state": "taking"\n}\n' "$1" "$2" "$3"
  fi
}
c_keys() { grep -o '"[a-z]*":' "$(marker "$1")" | tr -d '\n'; }
c_finished() { [ "$(c_keys "$1")" = '"slot":"branch":"since":' ]; }
c_leftovers() { local f; for f in "$S1"/slot-"$1".claim.*.tmp "$S1"/slot-"$1".left.*.tmp "$S1"/slot-"$1".take.tmp; do if [ -e "$f" ]; then printf '%s\n' "${f##*/}"; fi; done | sort; }
c_head() { git -C "$tmp/wt/slot-$1" rev-parse HEAD; }
c_branch() { git -C "$tmp/wt/slot-$1" branch --show-current; }
c_ref() { git -C "$tmp/work" rev-parse --verify -q "refs/heads/$1" || true; }
c_other() { [ -d "$tmp/other/.git" ] || git clone -q -b main "$tmp/origin.git" "$tmp/other"; }
c_mkbranch() { # c_mkbranch <branch> <file>: a branch with one commit that adds the file, checked out nowhere
  c_other
  git -C "$tmp/other" fetch -q origin
  G "$tmp/other" switch -q -C "$1" origin/main
  echo "$1" > "$tmp/other/$2"
  G "$tmp/other" add -A
  G "$tmp/other" commit -qm "$1"
  git -C "$tmp/other" push -q -f origin "$1" 2>/dev/null
  git -C "$tmp/work" fetch -q origin "+$1:refs/heads/$1" 2>/dev/null
}
claim_reset() { # every slot free and detached at origin/main, the original config, both gates open, nothing left over
  local n d
  claim_stop; rm -f "$tmp/go" "$tmp/claim-go" "$tmp/barrier" "$S1/capacity.json"
  cp "$tmp/cfg-claim.json" "$CFG"
  git -C "$tmp/work" config --unset remote.origin.uploadpack 2>/dev/null || true
  git -C "$tmp/work" config --unset core.hooksPath 2>/dev/null || true
  git -C "$tmp/work" remote set-url origin "$tmp/origin.git"
  for n in 1 2 3 4; do
    d="$tmp/wt/slot-$n"
    if [ "$n" = 4 ] && [ -d "$d" ]; then git -C "$tmp/work" worktree remove --force "$d" >/dev/null 2>&1 || true; continue; fi
    if [ -d "$d" ]; then
      git -C "$d" switch -q -f --detach origin/main >/dev/null 2>&1 || true
      git -C "$d" clean -fdq >/dev/null 2>&1 || true
    fi
    rm -f "$(marker "$n")" "$S1"/slot-"$n".claim.*.tmp "$S1"/slot-"$n".left.*.tmp "$S1/slot-$n.take.tmp"
    if [ -d "$S1/slot-$n.warmup-1" ]; then rmdir "$S1/slot-$n.warmup-1"; fi
  done
  reset_gh
}
c_same() { cmp -s "$1" "$2" || fail "$3: the marker changed: $(cat "$2")"; } # c_same <expected file> <marker file> <what>
c_refused() { # c_refused <n> <expected marker file> <expected standard error> <arguments...>: exit 1, that line only, marker unchanged
  local n=$1 want=$2 line=$3; shift 3
  rep "$@"
  [ "$rc" = 1 ] || fail "claim refusal ($*): exit $rc, wanted 1: $out / $err"
  [ "$err" = "$line" ] || fail "claim refusal ($*): standard error [$err], wanted [$line]"
  [ -z "$out" ] || fail "claim refusal ($*): printed $out"
  c_same "$want" "$(marker "$n")" "claim refusal ($*)"
}

# 1 two takes at the same time get different slots, also when origin has moved
claim_case1() {
  claim_reset
  local N p1 p2 r1 r2 o1 o2 e1 e2 n1 n2 pair
  write_cfg "$gate_json"
  c_other
  echo "moved $SECONDS$RANDOM" > "$tmp/other/moved.txt"
  G "$tmp/other" add -A
  G "$tmp/other" commit -qm "origin moves"
  git -C "$tmp/other" push -q origin main
  N=$(git -C "$tmp/other" rev-parse HEAD)
  [ "$(git -C "$tmp/work" rev-parse origin/main)" != "$N" ] || fail "claim 1: setup: origin/main of the main checkout is already at the moved commit"
  mkdir -p "$tmp/hooks"; rm -f "$tmp/barrier"
  sed "s|@TMP@|$tmp|g" > "$tmp/hooks/upload-pack-barrier" <<'EOF'
echo x >> '@TMP@/barrier'; i=0; while [ "$(wc -l < '@TMP@/barrier')" -lt 2 ]; do i=$((i+1)); [ $i -lt 300 ] || break; sleep 0.1; done; exec git upload-pack "$@"
EOF
  git -C "$tmp/work" config remote.origin.uploadpack "sh '$tmp/hooks/upload-pack-barrier'"
  bg_pids=()
  bg_take t1 --take feat/p1; p1=$bg_pid
  bg_take t2 --take feat/p2; p2=$bg_pid
  waitfor 1 taking
  waitfor 2 taking
  : > "$tmp/go"
  bg_wait "$p1" t1; r1=$rc; o1=$out; e1=$err
  bg_wait "$p2" t2; r2=$rc; o2=$out; e2=$err
  bg_pids=()
  [ "$(wc -l < "$tmp/barrier" | tr -d ' ')" -ge 2 ] || fail "claim 1: the two fetches did not overlap (barrier: $(cat "$tmp/barrier"))"
  [ "$r1" = 0 ] || fail "claim 1: take feat/p1 exited $r1: $o1 / $e1"
  [ "$r2" = 0 ] || fail "claim 1: take feat/p2 exited $r2: $o2 / $e2"
  n1=$(sed -n 's/^Slot \([0-9]*\) is yours.*/\1/p' <<<"$o1" | head -n 1)
  n2=$(sed -n 's/^Slot \([0-9]*\) is yours.*/\1/p' <<<"$o2" | head -n 1)
  { [ "$n1,$n2" = "1,2" ] || [ "$n1,$n2" = "2,1" ]; } || fail "claim 1: the takes were given slots '$n1' and '$n2', not one each of 1 and 2: $o1 / $o2"
  for pair in "$n1 feat/p1" "$n2 feat/p2"; do
    set -- $pair
    [ "$(c_branch "$1")" = "$2" ] || fail "claim 1: slot $1 is on '$(c_branch "$1")', not on $2"
    [ "$(mget "$1" branch)" = "$2" ] || fail "claim 1: the marker of slot $1 names '$(mget "$1" branch)', not $2"
    git -C "$tmp/work" merge-base --is-ancestor "$N" "$2" || fail "claim 1: $2 does not start at the moved origin commit $N"
    c_finished "$1" || fail "claim 1: the marker of slot $1 is not a finished marker: $(cat "$(marker "$1")")"
  done
  git -C "$tmp/work" config --unset remote.origin.uploadpack
  rm -f "$tmp/go" "$tmp/barrier"
  bash "$S" --abandon 1 >/dev/null; bash "$S" --abandon 2 >/dev/null
}

# 2 a take still working is shown as taken and kept
claim_case2() {
  claim_reset
  local pid since live p st
  write_cfg "$gate_json"
  rm -f "$tmp/go"
  bg_pids=()
  bg_take c2 --take feat/s2 --slot 2; p=$bg_pid
  waitfor 2 taking
  pid=$(bg_winpid "$p")
  since=$(mget 2 since)
  taking_text 2 feat/s2 "$since" "$pid" > "$tmp/want2.json"
  c_same "$tmp/want2.json" "$(marker 2)" "claim 2: the marker of a take that is working"
  cp "$(marker 2)" "$tmp/taking-s2.json"
  st=$(bash "$S" --status)
  grep -qxF "slot 2  ready           taking: feat/s2 since $since (process $pid)" <<<"$st" || fail "claim 2: status does not show slot 2 as taking: $st"
  if grep -q '^slot 2 .*free' <<<"$st"; then fail "claim 2: status shows slot 2 free: $st"; fi
  [ "$(bash "$S" --status --porcelain | sed -n 2p)" = "2${T}busy${T}feat/s2${T}${since}${T}${T}unknown${T}${T}${T}taking${T}" ] || fail "claim 2: porcelain line of slot 2: $(bash "$S" --status --porcelain)"
  c_same "$tmp/want2.json" "$(marker 2)" "claim 2 after the status"
  rep --take feat/s1 --skip-warmup
  [ "$rc" = 0 ] && grep -q 'Slot 1 is yours' <<<"$out" || fail "claim 2: a second take did not get slot 1 (exit $rc): $out / $err"
  bash "$S" --abandon 1 >/dev/null
  c_same "$tmp/want2.json" "$(marker 2)" "claim 2 after a second take"
  rep --take feat/s9 --slot 2 --skip-warmup
  [ "$rc" = 1 ] && [ "${err##*$'\n'}" = "slot 2 is busy" ] || fail "claim 2: a take on slot 2 was not refused as busy (exit $rc): $out / $err"
  c_same "$tmp/want2.json" "$(marker 2)" "claim 2 after --take --slot 2"
  live="slot 2 is being taken (process $pid is still running); wait for the take to end"
  reset_gh
  c_refused 2 "$tmp/want2.json" "$live" --release 2
  [ ! -s "$tmp/gh.log" ] || fail "claim 2: --release asked gh about a slot that is being taken: $(cat "$tmp/gh.log")"
  c_refused 2 "$tmp/want2.json" "$live" --abandon 2
  c_refused 2 "$tmp/want2.json" "$live" --report check --slot 2 --skill next --role implementer
  reset_gh; merged feat/s2 41 "$(git -C "$tmp/work" rev-parse origin/main)"
  rep --reap
  [ "$rc" = 0 ] && [ "$out" = "No slot freed." ] || fail "claim 2: --reap of a slot that is being taken (exit $rc): $out / $err"
  [ ! -s "$tmp/gh.log" ] || fail "claim 2: --reap asked gh about a slot that is being taken: $(cat "$tmp/gh.log")"
  c_same "$tmp/want2.json" "$(marker 2)" "claim 2 after --reap"
  reset_gh
  bash "$S" --capacity --slot-count 1 >/dev/null
  st=$(bash "$S" --status)
  grep -q "^slot 2  ready           taking: feat/s2 since $since (process $pid) (retiring)" <<<"$st" || fail "claim 2: a retiring slot that is being taken: $st"
  [ "$(bash "$S" --status --porcelain | sed -n 2p | cut -f5)" = retiring ] || fail "claim 2: porcelain field 5 of the retiring slot: $(bash "$S" --status --porcelain)"
  c_same "$tmp/want2.json" "$(marker 2)" "claim 2 after --capacity"
  : > "$tmp/go"
  bg_wait "$p" c2
  bg_pids=()
  [ "$rc" = 0 ] && grep -q 'Slot 2 is yours' <<<"$out" || fail "claim 2: the take did not finish (exit $rc): $out / $err"
  c_finished 2 || fail "claim 2: the finished marker has other keys: $(cat "$(marker 2)")"
  [ "$(mget 2 branch)" = feat/s2 ] || fail "claim 2: the finished marker names '$(mget 2 branch)'"
  [ "$(bash "$S" --status --porcelain | sed -n 2p | cut -f1-3,5)" = "2${T}busy${T}feat/s2${T}retiring" ] || fail "claim 2: slot 2 after the take is not a retiring busy slot: $(bash "$S" --status --porcelain)"
  bash "$S" --capacity --clear >/dev/null
  reset_gh
  bash "$S" --abandon 2 >/dev/null
  rm -f "$tmp/go"
}

# 3 a failed step puts the slot back and frees the claim
c_restored() { # c_restored <n> <count> <last line of standard error> [where]: after rep, the take failed and the slot is as before
  local n=$1 cnt=$2 want=$3 where=${4:-ready}
  [ "$rc" = 1 ] || fail "claim 3 ($want): exit $rc, wanted 1: $out / $err"
  [ "$(tail -n 1 "$tmp/err.txt")" = "$want" ] || fail "claim 3: standard error does not end with [$want]: $err"
  [ "$(tail -c 1 "$tmp/err.txt" | od -An -c | tr -d ' ')" = '\n' ] || fail "claim 3 ($want): standard error does not end with a newline"
  [ ! -e "$(marker "$n")" ] || fail "claim 3 ($want): the marker of slot $n is still there: $(cat "$(marker "$n")")"
  [ -z "$(c_leftovers "$n")" ] || fail "claim 3 ($want): temporary files are left: $(c_leftovers "$n")"
  st=$(WORKER_SLOTS=$cnt bash "$S" --status)
  grep -qxF "$(printf 'slot %s  %-15s free' "$n" "$where")" <<<"$st" || fail "claim 3 ($want): status does not show slot $n free: $st"
  [ "$(WORKER_SLOTS=$cnt bash "$S" --status --porcelain | awk -F '\t' -v n="$n" '$1 == n')" = "${n}${T}free" ] || fail "claim 3 ($want): porcelain does not show slot $n free"
}
claim_case3() {
  claim_reset
  local X Y dir since
  dir="$claim_root/slot-1"
  X=$(c_head 1)
  [ -z "$(c_branch 1)" ] || fail "claim 3: setup: slot 1 is not detached"
  # warm-up, existing slot, new branch
  write_cfg "$exit7_json"
  rep --take feat/f1
  c_restored 1 2 "warm-up 1 failed (exit 7); slot 1 is free again"
  [ -z "$(c_branch 1)" ] && [ "$(c_head 1)" = "$X" ] || fail "claim 3: slot 1 is not detached at $X after the failed warm-up (branch '$(c_branch 1)', head $(c_head 1))"
  [ -z "$(c_ref feat/f1)" ] || fail "claim 3: the new branch feat/f1 was left behind"
  # warm-up, existing branch
  c_mkbranch feat/f2 f2.txt
  Y=$(c_ref feat/f2)
  rep --take feat/f2 --slot 1
  c_restored 1 2 "warm-up 1 failed (exit 7); slot 1 is free again"
  [ -z "$(c_branch 1)" ] && [ "$(c_head 1)" = "$X" ] || fail "claim 3: slot 1 is not detached at $X after the failed warm-up on an existing branch"
  [ "$(c_ref feat/f2)" = "$Y" ] || fail "claim 3: feat/f2 is not at $Y any more: $(c_ref feat/f2)"
  # warm-up, slot not created yet
  [ ! -d "$tmp/wt/slot-4" ] || fail "claim 3: setup: slot-4 exists"
  WORKER_SLOTS=4 rep --take feat/f4 --slot 4
  c_restored 4 4 "warm-up 1 failed (exit 7); slot 4 is free again" "not created yet"
  [ ! -d "$tmp/wt/slot-4" ] || fail "claim 3: the directory slot-4 is left"
  if git -C "$tmp/work" worktree list | grep 'slot-4' >/dev/null; then fail "claim 3: git still lists the worktree slot-4"; fi
  [ -z "$(c_ref feat/f4)" ] || fail "claim 3: the branch feat/f4 was left behind"
  # switch
  cp "$tmp/cfg-claim.json" "$CFG"
  rep --take feat/f5 --slot 1 --base origin/nope
  c_restored 1 2 "git switch failed (exit 128); slot 1 is free again"
  [ -z "$(c_branch 1)" ] && [ "$(c_head 1)" = "$X" ] || fail "claim 3: slot 1 is not detached at $X after the failed switch"
  [ -z "$(c_ref feat/f5)" ] || fail "claim 3: the branch feat/f5 was left behind"
  # switch, step 5: the branch exists and is checked out in slot 2, so step 4 passes and the real git switch fails
  [ -d "$tmp/wt/slot-2" ] || fail "claim 3: setup: slot-2 does not exist"
  c_mkbranch feat/f12 f12.txt
  Y=$(c_ref feat/f12)
  git -C "$tmp/wt/slot-2" switch -q feat/f12
  rep --take feat/f12 --slot 1
  c_restored 1 2 "git switch failed (exit 128); slot 1 is free again"
  grep -Eq "already (used by worktree|checked out) at" <<<"$err" || fail "claim 3: the take did not reach the real git switch (no git refusal on standard error): $err"
  [ -z "$(c_branch 1)" ] && [ "$(c_head 1)" = "$X" ] || fail "claim 3: slot 1 is not detached at $X after the failed git switch (branch '$(c_branch 1)', head $(c_head 1))"
  [ "$(c_ref feat/f12)" = "$Y" ] || fail "claim 3: feat/f12 is not at $Y any more: $(c_ref feat/f12)"
  [ "$(c_branch 2)" = feat/f12 ] || fail "claim 3: slot 2 left feat/f12 (branch '$(c_branch 2)')"
  git -C "$tmp/wt/slot-2" switch -q --detach origin/main
  git -C "$tmp/work" branch -D feat/f12 >/dev/null
  # fetch
  git -C "$tmp/work" remote set-url origin "$tmp/no-such.git"
  rep --take feat/f6
  c_restored 1 2 "git fetch failed (exit 128); slot 1 is free again"
  [ -z "$(c_branch 1)" ] && [ "$(c_head 1)" = "$X" ] || fail "claim 3: slot 1 is not detached at $X after the failed fetch"
  [ "$(grep -c 'Could not read from remote repository' "$tmp/err.txt" || true)" = 3 ] || fail "claim 3: git's fetch error is not on standard error three times (three attempts): $err"
  git -C "$tmp/work" remote set-url origin "$tmp/origin.git"
  # the stamp cannot be written
  rm -rf "$S1/slot-1.warmup-1"; mkdir "$S1/slot-1.warmup-1"
  rep --take feat/f11 --slot 1
  c_restored 1 2 "warm-up 1 failed (exit 1); slot 1 is free again"
  [ -z "$(c_branch 1)" ] && [ "$(c_head 1)" = "$X" ] || fail "claim 3: slot 1 is not detached at $X after the failed stamp write"
  [ -z "$(c_ref feat/f11)" ] || fail "claim 3: the branch feat/f11 was left behind"
  rmdir "$S1/slot-1.warmup-1"
  # uncommitted files
  echo x > "$tmp/wt/slot-1/untracked.txt"
  rep --take feat/f7 --slot 1
  [ "$rc" = 1 ] && [ "$(tail -n 1 "$tmp/err.txt")" = "slot 1 has uncommitted files; deal with them first: $dir" ] || fail "claim 3: a take on a slot with uncommitted files (exit $rc): $err"
  [ ! -e "$(marker 1)" ] || fail "claim 3: a take refused for uncommitted files left a marker: $(cat "$(marker 1)")"
  [ -z "$(c_leftovers 1)" ] || fail "claim 3: a refused take left temporary files: $(c_leftovers 1)"
  rm -f "$tmp/wt/slot-1/untracked.txt"
  # a changed file keeps a dead claim
  c_mkbranch feat/f8 f8.txt
  write_cfg '[ { "command": "echo changed > f8.txt; exit 7" } ]'
  rep --take feat/f8 --slot 1
  [ "$rc" = 1 ] || fail "claim 3: a failed warm-up that changed a file exited $rc: $out / $err"
  [ "$(tail -n 2 "$tmp/err.txt")" = "slot 1 has uncommitted files: $dir (commit, stash or discard them first)
warm-up 1 failed (exit 7); slot 1 could not be put back and stays claimed: free it with --abandon 1" ] || fail "claim 3: the last two lines of standard error: $err"
  [ "$(c_branch 1)" = feat/f8 ] && [ "$(cat "$tmp/wt/slot-1/f8.txt")" = changed ] || fail "claim 3: slot 1 was switched back or lost the changed file (branch '$(c_branch 1)')"
  since=$(mget 1 since)
  taking_text 1 feat/f8 "$since" > "$tmp/want1.json"
  c_same "$tmp/want1.json" "$(marker 1)" "claim 3: the claim left behind"
  [ -z "$(c_leftovers 1)" ] || fail "claim 3: temporary files are left: $(c_leftovers 1)"
  [ "$(c_porc9 1)" = take-died ] || fail "claim 3: porcelain field 9 of the claim left behind is '$(c_porc9 1)'"
  grep -qF "slot 1  ready           taking: feat/f8 since $since (no process recorded; free it with --abandon 1)" <<<"$(bash "$S" --status)" || fail "claim 3: status of the claim left behind: $(bash "$S" --status)"
  rep --abandon 1
  [ "$rc" = 1 ] && [[ "$err" == *"slot 1 has uncommitted files:"* ]] || fail "claim 3: --abandon on a changed file (exit $rc): $out / $err"
  c_same "$tmp/want1.json" "$(marker 1)" "claim 3: --abandon on a changed file"
  git -C "$tmp/wt/slot-1" checkout -q -- f8.txt
  rep --abandon 1
  [ "$rc" = 0 ] && [ "$out" = "Slot 1 is free (was feat/f8, a take that did not finish; the local branch is kept, delete it yourself if unwanted)." ] || fail "claim 3: --abandon after the file was restored (exit $rc): $out / $err"
  git -C "$tmp/work" branch -D feat/f8 >/dev/null
  # an untracked file keeps a dead claim
  write_cfg '[ { "command": "echo x > junk.txt; exit 7" } ]'
  rep --take feat/f9 --slot 1
  [ "$rc" = 1 ] || fail "claim 3: a failed warm-up that created a file exited $rc: $out / $err"
  [ "$(tail -n 2 "$tmp/err.txt")" = "slot 1 has uncommitted files: $dir (commit, stash or discard them first)
warm-up 1 failed (exit 7); slot 1 could not be put back and stays claimed: free it with --abandon 1" ] || fail "claim 3: the last two lines of standard error (untracked file): $err"
  [ "$(c_branch 1)" = feat/f9 ] && [ -f "$tmp/wt/slot-1/junk.txt" ] || fail "claim 3: slot 1 was switched back or lost junk.txt (branch '$(c_branch 1)')"
  since=$(mget 1 since)
  taking_text 1 feat/f9 "$since" > "$tmp/want1.json"
  c_same "$tmp/want1.json" "$(marker 1)" "claim 3: the claim left behind (untracked file)"
  [ "$(c_porc9 1)" = take-died ] || fail "claim 3: porcelain field 9 of the claim left behind (untracked file) is '$(c_porc9 1)'"
  rep --take feat/f10 --slot 1 --skip-warmup
  [ "$rc" = 1 ] && [ "${err##*$'\n'}" = "slot 1 is busy" ] || fail "claim 3: a take on the claim left behind (exit $rc): $out / $err"
  rep --abandon 1
  [ "$rc" = 1 ] && [[ "$err" == *"slot 1 has uncommitted files:"* ]] || fail "claim 3: --abandon with junk.txt (exit $rc): $out / $err"
  rm -f "$tmp/wt/slot-1/junk.txt"
  rep --abandon 1
  [ "$rc" = 0 ] && [ "$out" = "Slot 1 is free (was feat/f9, a take that did not finish; the local branch is kept, delete it yourself if unwanted)." ] || fail "claim 3: --abandon after junk.txt was removed (exit $rc): $out / $err"
  [ -z "$(c_branch 1)" ] && [ -z "$(git -C "$tmp/wt/slot-1" status --porcelain)" ] || fail "claim 3: slot 1 is not detached and clean after --abandon"
  git -C "$tmp/work" branch -D feat/f9 >/dev/null
  cp "$tmp/cfg-claim.json" "$CFG"
}

# 4 a dead claim is recognised and freed only by --abandon, without losing work
claim_case4() {
  claim_reset
  local since dead live dline nline lline tip p
  dead=$(dead_pid); live=$(mypid)
  bash "$S" --take feat/d1 --slot 1 --skip-warmup >/dev/null 2>&1 || fail "claim 4: setup: take feat/d1 failed"
  since=$(mget 1 since)
  taking_text 1 feat/d1 "$since" "$dead" > "$(marker 1)"
  cp "$(marker 1)" "$tmp/want1.json"
  st=$(bash "$S" --status)
  grep -qF "taking: feat/d1 since $since (process $dead has ended; free it with --abandon 1)" <<<"$st" || fail "claim 4: status of a dead claim: $st"
  [ "$(c_porc9 1)" = take-died ] || fail "claim 4: porcelain field 9 of a dead claim is '$(c_porc9 1)'"
  [ "$(bash "$S" --status --porcelain | sed -n 1p | cut -f6)" = unknown ] || fail "claim 4: porcelain field 6 of a dead claim: $(bash "$S" --status --porcelain)"
  rep --take feat/d2 --skip-warmup
  [ "$rc" = 0 ] && grep -q 'Slot 2 is yours' <<<"$out" || fail "claim 4: a take did not get slot 2 beside a dead claim (exit $rc): $out / $err"
  bash "$S" --abandon 2 >/dev/null
  dline="slot 1 has a take that did not finish (process $dead has ended); free it with --abandon 1"
  c_refused 1 "$tmp/want1.json" "$dline" --release 1
  c_refused 1 "$tmp/want1.json" "$dline" --report check --slot 1 --skill next --role implementer
  tip=$(git -C "$tmp/work" rev-parse refs/heads/feat/d1)
  reset_gh; merged feat/d1 42 "$tip"
  rep --reap
  [ "$rc" = 0 ] && [ "$out" = "No slot freed." ] || fail "claim 4: --reap of a dead claim (exit $rc): $out / $err"
  [ ! -s "$tmp/gh.log" ] || fail "claim 4: --reap asked gh about a dead claim: $(cat "$tmp/gh.log")"
  c_same "$tmp/want1.json" "$(marker 1)" "claim 4 after --reap"
  reset_gh
  echo x > "$tmp/wt/slot-1/untracked.txt"
  rep --abandon 1
  [ "$rc" = 1 ] && [[ "$err" == *"slot 1 has uncommitted files:"* ]] || fail "claim 4: --abandon with an untracked file (exit $rc): $out / $err"
  c_same "$tmp/want1.json" "$(marker 1)" "claim 4: --abandon with an untracked file"
  [ -f "$tmp/wt/slot-1/untracked.txt" ] || fail "claim 4: --abandon removed the untracked file"
  rm -f "$tmp/wt/slot-1/untracked.txt"
  rep --abandon 1
  [ "$rc" = 0 ] && [ "$out" = "Slot 1 is free (was feat/d1, a take that did not finish; the local branch is kept, delete it yourself if unwanted)." ] || fail "claim 4: --abandon of a dead claim (exit $rc): $out / $err"
  [ ! -e "$(marker 1)" ] || fail "claim 4: the marker of the dead claim is still there"
  [ "$(c_head 1)" = "$(git -C "$tmp/work" rev-parse origin/main)" ] && [ -z "$(c_branch 1)" ] || fail "claim 4: slot 1 is not detached at origin/main after --abandon"
  [ "$(c_ref feat/d1)" = "$tip" ] || fail "claim 4: feat/d1 is not at its tip any more: $(c_ref feat/d1)"
  # a live pid, then no pid, then a pid out of range
  taking_text 1 feat/d1 "$since" "$live" > "$(marker 1)"; cp "$(marker 1)" "$tmp/want1.json"
  lline="slot 1 is being taken (process $live is still running); wait for the take to end"
  c_refused 1 "$tmp/want1.json" "$lline" --abandon 1
  nline="slot 1 has a take that did not finish (no process recorded); free it with --abandon 1"
  for p in "" 2147483648 0; do
    if [ -z "$p" ]; then taking_text 1 feat/d1 "$since" > "$(marker 1)"; else taking_text 1 feat/d1 "$since" "$p" > "$(marker 1)"; fi
    cp "$(marker 1)" "$tmp/want1.json"
    [ "$(c_porc9 1)" = take-died ] || fail "claim 4: porcelain field 9 of a claim with pid '$p' is '$(c_porc9 1)'"
    grep -qF "taking: feat/d1 since $since (no process recorded; free it with --abandon 1)" <<<"$(bash "$S" --status)" || fail "claim 4: status of a claim with pid '$p': $(bash "$S" --status)"
    c_refused 1 "$tmp/want1.json" "$nline" --release 1
  done
  rm -f "$(marker 1)"
  # a dead claim on a slot that was never created
  [ ! -d "$tmp/wt/slot-4" ] || fail "claim 4: setup: slot-4 exists"
  taking_text 4 feat/d4 "$since" "$dead" > "$(marker 4)"
  WORKER_SLOTS=4 rep --abandon 4
  [ "$rc" = 0 ] && [ "$out" = "Slot 4 is free (was feat/d4, a take that did not finish; the local branch is kept, delete it yourself if unwanted)." ] || fail "claim 4: --abandon of a dead claim without a directory (exit $rc): $out / $err"
  [ ! -e "$(marker 4)" ] || fail "claim 4: the marker of slot 4 is still there"
}

# 5 markers across versions
claim_case5() {
  claim_reset
  local tag f p
  # the taking marker of a take that works, read the way the previous version reads it
  write_cfg "$gate_json"
  rm -f "$tmp/go"
  bg_pids=()
  bg_take c5 --take feat/s2 --slot 2; p=$bg_pid
  waitfor 2 taking
  cp "$(marker 2)" "$tmp/taking-prev.json"
  ( json_load "$tmp/taking-prev.json" || exit 1
    [ "$(json_get slot)" = 2 ] && [ "$(json_get branch)" = feat/s2 ] && [ -n "$(json_get since)" ] ) || fail "claim 5: the taking marker is not read by key as slot 2, feat/s2 and a since: $(cat "$tmp/taking-prev.json")"
  [ "$(bash "$S" --status --porcelain | sed -n 2p | cut -f2)" = busy ] || fail "claim 5: the taking marker is not a busy line: $(bash "$S" --status --porcelain)"
  : > "$tmp/go"; bg_wait "$p" c5; bg_pids=()
  [ "$rc" = 0 ] || fail "claim 5: the take did not finish (exit $rc): $out / $err"
  claim_reset
  # markers of the previous version are not claims (their branches exist, so that the reap can look at them)
  git -C "$tmp/work" branch -f feat/v1 origin/main
  git -C "$tmp/work" branch -f feat/r1 origin/main
  json_marker 1 feat/v1 2026-11-05T09:00:00 > "$(marker 1)"
  [ "$(c_porc9 1)" = "" ] || fail "claim 5: a three-key marker has the step '$(c_porc9 1)'"
  rep --take feat/v3 --skip-warmup
  [ "$rc" = 0 ] && grep -q 'Slot 2 is yours' <<<"$out" || fail "claim 5: a take did not skip a three-key marker (exit $rc): $out / $err"
  bash "$S" --abandon 2 >/dev/null
  rep --abandon 1
  [ "$rc" = 0 ] && [ "$out" = "Slot 1 is free (was feat/v1; the local branch is kept, delete it yourself if unwanted)." ] || fail "claim 5: --abandon of a three-key marker (exit $rc): $out / $err"
  hand 1 check 2026-11-05T11:30:00
  [ "$(c_porc9 1)" = check ] || fail "claim 5: a seven-key marker has the step '$(c_porc9 1)'"
  rep --take feat/v3 --skip-warmup
  [ "$rc" = 0 ] && grep -q 'Slot 2 is yours' <<<"$out" || fail "claim 5: a take did not skip a seven-key marker (exit $rc): $out / $err"
  bash "$S" --abandon 2 >/dev/null
  rep --abandon 1
  [ "$rc" = 0 ] && [ "$out" = "Slot 1 is free (was feat/r1; the local branch is kept, delete it yourself if unwanted)." ] || fail "claim 5: --abandon of a seven-key marker (exit $rc): $out / $err"
  printf '{\n  "slot": 1,\n  "branch": "feat/v1",\n  "since": "2026-11-05T09:00:00",\n  "state": "done"\n}\n' > "$(marker 1)"
  [ "$(c_porc9 1)" = "" ] || fail "claim 5: a marker with the state done has the step '$(c_porc9 1)'"
  grep -q '^slot 1  ready           busy: feat/v1 since 2026-11-05T09:00:00' <<<"$(bash "$S" --status)" || fail "claim 5: a marker with the state done is not a finished busy slot: $(bash "$S" --status)"
  rep --abandon 1
  [ "$rc" = 0 ] && [ "$out" = "Slot 1 is free (was feat/v1; the local branch is kept, delete it yourself if unwanted)." ] || fail "claim 5: --abandon of a marker with the state done (exit $rc): $out / $err"
  # the previous version against a take that is working
  tag=$(git -C "$here" tag --list 'v*' --sort=-v:refname | head -n 1)
  if [ -z "$tag" ]; then
    echo "skipped: no release tag to run the previous version"
  else
    # a release that knows the taking state shows it as taking, an older one as busy; both are not free
    # a complete copy of the scripts/ folder at the tag, whatever library files it sources
    mkdir -p "$tmp/prev"
    git -C "$here" archive --format=tar "$tag" scripts | tar -x -C "$tmp/prev" --strip-components=1
    write_cfg "$gate_json"
    rm -f "$tmp/go"
    bg_pids=()
    bg_take c5b --take feat/v1 --slot 1; p=$bg_pid
    waitfor 1 taking
    set +e; out=$(bash "$tmp/prev/slot.sh" --status 2>&1); rc=$?; set -e
    [ "$rc" = 0 ] && grep -Eq '(busy|taking): feat/v1 since' <<<"$out" || fail "claim 5: the previous version ($tag) does not show the taking slot as busy (exit $rc): $out"
    set +e; out=$(bash "$tmp/prev/slot.sh" --take feat/v2 --skip-warmup 2>&1); rc=$?; set -e
    [ "$rc" = 0 ] && grep -q 'Slot 2 is yours' <<<"$out" || fail "claim 5: the previous version ($tag) did not skip the taking slot (exit $rc): $out"
    bash "$S" --abandon 2 >/dev/null
    : > "$tmp/go"; bg_wait "$p" c5b; bg_pids=()
    [ "$rc" = 0 ] || fail "claim 5: the take did not finish (exit $rc): $out / $err"
  fi
  claim_reset
}

# 6 the claim exists before the fetch, the worktree add and the switch
claim_case6() {
  claim_reset
  local m
  [ ! -d "$tmp/wt/slot-4" ] || fail "claim 6: setup: slot-4 exists"
  mkdir -p "$tmp/hooks"
  m="$claim_root/.slots/slot-4.json"
  printf '%s\n' "m='$m'; if [ -e \"\$m\" ] && grep -q '\"state\": \"taking\"' \"\$m\"; then c=claimed; else c=unclaimed; fi; echo \"\$1 \$c\" >> '$tmp/spy.log'" > "$tmp/hooks/record"
  printf '%s\n' '#!/bin/sh' "sh '$tmp/hooks/record' checkout" > "$tmp/hooks/post-checkout"
  printf '%s\n' '#!/bin/sh' "sh '$tmp/hooks/record' fetch" 'exec git upload-pack "$@"' > "$tmp/hooks/upload-pack"
  chmod +x "$tmp/hooks/post-checkout" "$tmp/hooks/upload-pack"
  git -C "$tmp/work" config core.hooksPath "$tmp/hooks"
  git -C "$tmp/work" config remote.origin.uploadpack "sh '$tmp/hooks/upload-pack'"
  : > "$tmp/spy.log"
  WORKER_SLOTS=4 rep --take feat/c6 --slot 4 --skip-warmup
  [ "$rc" = 0 ] && grep -q 'Slot 4 is yours' <<<"$out" || fail "claim 6: the take failed (exit $rc): $out / $err"
  [ "$(cat "$tmp/spy.log")" = "fetch claimed
checkout claimed
checkout claimed" ] || fail "claim 6: git did not see the claim at the fetch, the worktree add and the switch; the log is: $(tr '\n' '|' < "$tmp/spy.log")"
  # control: with a finished marker the same probe says unclaimed
  c_finished 4 || fail "claim 6: the marker of slot 4 is not finished: $(cat "$(marker 4)")"
  git -C "$tmp/work" fetch -q origin
  git -C "$tmp/wt/slot-4" switch -q -c feat/c6b
  [ "$(cat "$tmp/spy.log")" = "fetch claimed
checkout claimed
checkout claimed
fetch unclaimed
checkout unclaimed" ] || fail "claim 6: the probe cannot tell a claim from a finished marker; the log is: $(tr '\n' '|' < "$tmp/spy.log")"
  git -C "$tmp/work" config --unset core.hooksPath
  git -C "$tmp/work" config --unset remote.origin.uploadpack
  WORKER_SLOTS=4 bash "$S" --abandon 4 >/dev/null
  git -C "$tmp/work" branch -D feat/c6 feat/c6b >/dev/null
}

# 7 the publish is exclusive, in one shell and across the two
c_check_race() { # c_check_race <branch of take 1> <branch of take 2>: checks the results of the two takes ($r1 $o1 $e1, $r2 $o2 $e2); the winner's branch is left in $c_winner
  local wb lb
  { [ "$r1" = 0 ] && [ "$r2" = 1 ]; } || { [ "$r1" = 1 ] && [ "$r2" = 0 ]; } || fail "claim 7: the exits of the two takes are $r1 and $r2, not one 0 and one 1: $o1 / $e1 / $o2 / $e2"
  if [ "$r1" = 0 ]; then wb=$1; lb=$2; else wb=$2; lb=$1; fi
  if [ "$r1" = 0 ]; then
    grep -q 'Slot 1 is yours' <<<"$o1" || fail "claim 7: the winner did not print Slot 1 is yours: $o1"
    [ "${e2##*$'\n'}" = "slot 1 is busy" ] || fail "claim 7: the loser's standard error does not end with 'slot 1 is busy': $e2"
  else
    grep -q 'Slot 1 is yours' <<<"$o2" || fail "claim 7: the winner did not print Slot 1 is yours: $o2"
    [ "${e1##*$'\n'}" = "slot 1 is busy" ] || fail "claim 7: the loser's standard error does not end with 'slot 1 is busy': $e1"
  fi
  [ "$(mget 1 branch)" = "$wb" ] || fail "claim 7: the marker of slot 1 names '$(mget 1 branch)', not the winner $wb"
  if grep -q '"state"\|"pid"' "$(marker 1)"; then fail "claim 7: the marker of slot 1 is not finished: $(cat "$(marker 1)")"; fi
  [ "$(c_branch 1)" = "$wb" ] || fail "claim 7: slot 1 is on '$(c_branch 1)', not on the winner $wb"
  [ -z "$(c_ref "$lb")" ] || fail "claim 7: the loser's branch $lb exists (it fetched or switched)"
  [ -z "$(c_leftovers 1)" ] || fail "claim 7: temporary files are left: $(c_leftovers 1)"
  c_winner=$wb
}
claim_case7() {
  claim_reset
  local p1 p2 gate
  # same shell
  bg_pids=()
  NIGHTMILL_CLAIM_GATE="$tmp/claim-go" bg_take x1 --take feat/x1 --slot 1 --skip-warmup; p1=$bg_pid
  NIGHTMILL_CLAIM_GATE="$tmp/claim-go" bg_take x2 --take feat/x2 --slot 1 --skip-warmup; p2=$bg_pid
  wait_claims 1 2
  : > "$tmp/claim-go"
  bg_wait "$p1" x1; r1=$rc; o1=$out; e1=$err
  bg_wait "$p2" x2; r2=$rc; o2=$out; e2=$err
  bg_pids=()
  c_check_race feat/x1 feat/x2
  c_finished 1 || fail "claim 7: the winner's marker has other keys than slot, branch, since: $(cat "$(marker 1)")"
  claim_reset
  git -C "$tmp/work" branch -D "$c_winner" >/dev/null
  # across the shells
  if command -v powershell >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
    ps_slot=$(cygpath -w "$here/scripts/slot.ps1")
    gate=$(cygpath -m "$tmp/claim-go")
    rm -f "$tmp/claim-go"
    bg_pids=()
    NIGHTMILL_CLAIM_GATE="$gate" bg_take y1 --take feat/y1 --slot 1 --skip-warmup; p1=$bg_pid
    NIGHTMILL_CLAIM_GATE="$gate" bg_ps y2 -Take feat/y2 -Slot 1 -SkipWarmup; p2=$bg_pid
    wait_claims 1 2
    : > "$tmp/claim-go"
    bg_wait "$p1" y1; r1=$rc; o1=$out; e1=$err
    bg_wait "$p2" y2; r2=$rc; o2=$out; e2=$err
    bg_pids=()
    c_check_race feat/y1 feat/y2
    if [ "$c_winner" = feat/y1 ]; then
      c_finished 1 || fail "claim 7: the bash winner's marker has other keys than slot, branch, since in that order: $(cat "$(marker 1)")"
    else
      [ "$(grep -o '"[a-z]*":' "$(marker 1)" | tr -d '":' | sort | paste -sd, -)" = "branch,since,slot" ] || fail "claim 7: the PowerShell winner's marker has other keys than branch, since, slot: $(cat "$(marker 1)")"
    fi
    claim_reset
    git -C "$tmp/work" branch -D "$c_winner" >/dev/null
  else
    echo "skipped: no PowerShell for the cross-shell claim"
  fi
}

claim_case1
claim_case2
claim_case3
claim_case4
claim_case5
claim_case6
claim_case7
claim_reset

echo "== 13 a slot is freed once its branch is pushed, and a dirty slot is held"
# 13 (iteration 33, /fix all): the skill frees a bug's slot with --abandon once the bug's branch is on its open pull
# request, and holds a slot with uncommitted files. The slot scripts already do both, and this case pins it: takes run
# one after the other get different slots; --abandon frees a clean slot at once, keeps the local branch and the pushed
# commits, and asks gh for nothing; a freed slot is reused by the next take; --abandon refuses a slot with an untracked
# file and changes nothing; no gh call but the reap's merged query is made.
claim_reset
for b in feat/p1 feat/p2 feat/p3; do
  git -C "$tmp/work" branch -D "$b" >/dev/null 2>&1 || true
  git -C "$tmp/origin.git" update-ref -d "refs/heads/$b" >/dev/null 2>&1 || true
done
reset_gh
d1="$tmp/wt/slot-1"
# 1 two takes one after the other get slots 1 and 2; a third fails and changes no marker
rep --take feat/p1
[ "$rc" = 0 ] && grep -q 'Slot 1 is yours' <<<"$out" || fail "13.1: take feat/p1 did not get slot 1 (exit $rc): $out / $err"
rep --take feat/p2
[ "$rc" = 0 ] && grep -q 'Slot 2 is yours' <<<"$out" || fail "13.1: take feat/p2 did not get slot 2 (exit $rc): $out / $err"
cp "$(marker 1)" "$tmp/p13-m1.txt"; cp "$(marker 2)" "$tmp/p13-m2.txt"
rep --take feat/p3
[ "$rc" != 0 ] || fail "13.1: a third take with two slots should fail: $out"
grep -q 'all 2 slots are busy' <<<"$err" || fail "13.1: the third take did not say 'all 2 slots are busy': $err"
c_same "$tmp/p13-m1.txt" "$(marker 1)" "13.1 the third take"
c_same "$tmp/p13-m2.txt" "$(marker 2)" "13.1 the third take"
# 2 slot 1 commits one file and pushes; --abandon frees it, keeps the branch and the pushed tip, and asks gh for nothing
echo p1 > "$d1/p1.txt"
G "$d1" add -A
G "$d1" commit -qm "work on feat/p1"
git -C "$d1" push -q origin feat/p1 2>/dev/null
tip=$(git -C "$d1" rev-parse HEAD)
glog=$(cat "$tmp/gh.log")
rep --abandon 1
[ "$rc" = 0 ] || fail "13.2: --abandon 1 exited $rc: $out / $err"
[ "$out" = "Slot 1 is free (was feat/p1; the local branch is kept, delete it yourself if unwanted)." ] || fail "13.2: wrong --abandon output: $out"
[ "$(cat "$tmp/gh.log")" = "$glog" ] || fail "13.2: --abandon asked gh: $(cat "$tmp/gh.log")"
[ ! -f "$(marker 1)" ] || fail "13.2: the marker of slot 1 is still there"
[ "$(git -C "$tmp/work" rev-parse --verify -q refs/heads/feat/p1 || true)" = "$tip" ] || fail "13.2: the local branch feat/p1 is not the tip $tip"
[ "$(git -C "$tmp/origin.git" rev-parse --verify -q refs/heads/feat/p1 || true)" = "$tip" ] || fail "13.2: the origin branch feat/p1 is not the tip $tip"
[ -z "$(git -C "$d1" branch --show-current)" ] || fail "13.2: slot 1 is not detached: $(git -C "$d1" branch --show-current)"
# 3 the freed slot is reused
rep --take feat/p3
[ "$rc" = 0 ] && grep -q 'Slot 1 is yours' <<<"$out" || fail "13.3: take feat/p3 did not reuse slot 1 (exit $rc): $out / $err"
# 4 an untracked file holds the slot: --abandon refuses and changes nothing
echo x > "$d1/untracked.txt"
cp "$(marker 1)" "$tmp/p13-m1.txt"
glog=$(cat "$tmp/gh.log")
rep --abandon 1
[ "$rc" != 0 ] || fail "13.4: --abandon of a slot with an untracked file should fail: $out"
grep -qF 'slot 1 has uncommitted files:' <<<"$err" || fail "13.4: wrong refusal on standard error: $err"
c_same "$tmp/p13-m1.txt" "$(marker 1)" "13.4 the refused --abandon"
[ -f "$d1/untracked.txt" ] || fail "13.4: the untracked file is gone"
[ "$(git -C "$d1" branch --show-current)" = feat/p3 ] || fail "13.4: slot 1 is not on feat/p3 any more: $(git -C "$d1" branch --show-current)"
[ "$(cat "$tmp/gh.log")" = "$glog" ] || fail "13.4: the refused --abandon asked gh: $(cat "$tmp/gh.log")"
# 5 no gh call but the reap's merged query (the takes ask it for slots with a clean tree; it finds nothing)
other=$(grep -vxE 'pr list --state merged --head feat/p[0-9] --json number,headRefOid,createdAt,mergedAt,closingIssuesReferences' "$tmp/gh.log" || true)
[ -z "$other" ] || fail "13.5: gh was asked something but the reap's merged query: $other"
# clean up: every slot free, the local and the remote branches gone, the fake gh as it was
rm -f "$d1/untracked.txt"
bash "$S" --abandon 1 >/dev/null || fail "13.5: clean-up: --abandon 1 failed"
bash "$S" --abandon 2 >/dev/null || fail "13.5: clean-up: --abandon 2 failed"
for b in feat/p1 feat/p2 feat/p3; do
  git -C "$tmp/work" branch -D "$b" >/dev/null 2>&1 || true
  git -C "$tmp/origin.git" update-ref -d "refs/heads/$b" >/dev/null 2>&1 || true
done
rm -f "$tmp/p13-m1.txt" "$tmp/p13-m2.txt"
claim_reset

echo "== the record (iteration 41)"
# The take, every report and every freeing append one line to <root>/.slots/ledger.tsv (eleven tab-separated fields:
# kind, UTC stamp, slot, branch, name, skill, role, pr, from, to, issues); scripts/stages.sh prints the table from it.
# The clock is the file NIGHTMILL_CLOCK_FILE (test only): seconds since 1970, UTC; T0 = 2026-11-07T08:00:00Z = 1794038400.
# The warm-up of the test config copies <tmp>/warm-clock over the clock, so that a take lasts as long as the test says.
reset_gh; claim_reset
RL="$S1/ledger.tsv"
RT0=1794038400
RC="$tmp/clock"; RW="$tmp/warm-clock"
export NIGHTMILL_CLOCK_FILE="$RC"
rm -f "$RL"
write_cfg "[ { \"command\": \"cat '$RW' > '$RC'\" } ]"
rclock() { echo $((RT0 + $1)) > "$RC"; } # rclock <seconds after T0>
rtake() { # rtake <start> <finish> <take arguments...>: a take that starts at T0+start and ends at T0+finish
  local s=$1 f=$2; shift 2
  rclock "$s"; echo $((RT0 + f)) > "$RW"
  bash "$S" "$@" >"$tmp/rtake.out" 2>"$tmp/rtake.err" || fail "record: the take '$*' failed: $(cat "$tmp/rtake.out" "$tmp/rtake.err")"
}
rlines() { if [ -f "$RL" ]; then wc -l < "$RL" | tr -d ' '; else echo 0; fi; }
rline() { sed -n "$1p" "$RL"; } # rline <n>: line n of the record
rmerged() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$tmp/fix/merged.txt"; } # branch number commit createdAt mergedAt issues
rstages() { ( cd "$tmp/work" && bash "$here/scripts/stages.sh" "$@" 2>&1 ); }
rrow() { printf '  %-20s %4s %8s %6s\n' "$@"; }

# 1 a take appends one take line: from the claim to the finish of the take (the warm-up moved the clock by 30 s)
rtake 0 30 --take feat/st1 --slot 1
[ "$(rlines)" = 1 ] || fail "record: a take wrote $(rlines) lines: $(cat "$RL")"
[ "$(rline 1)" = "take${T}2026-11-07T08:00:30Z${T}1${T}feat/st1${T}take${T}${T}${T}${T}2026-11-07T08:00:00Z${T}2026-11-07T08:00:30Z${T}" ] || fail "record: the take line: $(rline 1)"

# 2 every report appends one step line with its stamp; the marker keeps the seven keys of iteration 23
rclock 35; rep --report slot-taken --slot 1 --skill next --role session
[ "$rc" = 0 ] && [ -z "$out$err" ] || fail "record: report 1: exit $rc: $out / $err"
rclock 100; rep --report implement --slot 1 --skill next --role implementer
[ "$rc" = 0 ] && [ -z "$out$err" ] || fail "record: report 2: exit $rc: $out / $err"
[ "$(rlines)" = 3 ] || fail "record: two reports gave $(rlines) lines in all: $(cat "$RL")"
[ "$(rline 2)" = "step${T}2026-11-07T08:00:35Z${T}1${T}feat/st1${T}slot-taken${T}next${T}session${T}${T}${T}${T}" ] || fail "record: the step line of the first report: $(rline 2)"
[ "$(rline 3)" = "step${T}2026-11-07T08:01:40Z${T}1${T}feat/st1${T}implement${T}next${T}implementer${T}${T}${T}${T}" ] || fail "record: the step line of the second report: $(rline 3)"
[ "$(grep -o '"[a-z]*":' "$(marker 1)" | tr -d '\n')" = '"slot":"branch":"since":"skill":"role":"step":"reported":' ] || fail "record: marker keys: $(mtext 1)"
[ "$(mget 1 step)/$(mget 1 skill)/$(mget 1 role)/$(mget 1 branch)" = "implement/next/implementer/feat/st1" ] || fail "record: the marker is read by key: $(mtext 1)"

# 3 a refused report appends nothing
rep --report check --slot 2 --skill next --role implementer
[ "$rc" = 1 ] && [ "$err" = "slot 2 is not in use" ] || fail "record: the refused report: exit $rc: $err"
rep --report "bad name" --slot 1 --skill next --role implementer
[ "$rc" = 1 ] || fail "record: a report with a bad step name: exit $rc"
[ "$(rlines)" = 3 ] || fail "record: a refused report appended a line: $(cat "$RL")"

# 4 --release with a merged PR appends the free line with the PR's times and issue; the branch is gone, the table is not
reset_gh; rmerged feat/st1 7 "$(git -C "$tmp/wt/slot-1" rev-parse HEAD)" 2026-11-07T08:02:40Z 2026-11-07T08:06:40Z 41
rclock 500
out=$(bash "$S" --release 1 2>/dev/null | tail -n 1)
[ "$out" = "Slot 1 is free (was feat/st1, PR #7)." ] || fail "record: release: wrong output: $out"
[ ! -f "$(marker 1)" ] || fail "record: release left the marker"
if git -C "$tmp/work" show-ref --verify --quiet refs/heads/feat/st1; then fail "record: release left the branch"; fi
[ "$(rlines)" = 4 ] || fail "record: the release wrote $(rlines) lines in all: $(cat "$RL")"
[ "$(rline 4)" = "free${T}2026-11-07T08:08:20Z${T}1${T}feat/st1${T}released${T}${T}${T}7${T}2026-11-07T08:02:40Z${T}2026-11-07T08:06:40Z${T}41" ] || fail "record: the free line of the release: $(rline 4)"
want=$(
  echo "#41  feat/st1  slot 1  merged 2026-11-07T08:06:40Z"
  rrow stage runs time share
  rrow take 1 30s 8%
  rrow not-reported 1 5s 1%
  rrow slot-taken 1 1m05s 16%
  rrow implement 1 1m00s 15%
  rrow ci-and-merge 1 4m00s 60%
  rrow total "" 6m40s 100%
)
got=$(rstages --issue 41)
[ "$got" = "$want" ] || fail "record: stages --issue 41 after the release; got: [$got] wanted: [$want]"
# a report after the slot is freed appends nothing and does not bring the marker back
rep --report check --slot 1 --skill next --role implementer
[ "$rc" = 1 ] && [ "$err" = "slot 1 is not in use" ] && [ ! -e "$(marker 1)" ] || fail "record: a report after the release: exit $rc: $err"
[ "$(rlines)" = 4 ] || fail "record: a report after the release appended a line: $(cat "$RL")"

# 5 --abandon of a finished take appends a take line and a free line with empty PR fields
reset_gh
rtake 1000 1020 --take feat/st2 --slot 1
rclock 1100
bash "$S" --abandon 1 >/dev/null 2>&1 || fail "record: --abandon failed"
[ "$(rlines)" = 6 ] || fail "record: a take and an abandon gave $(rlines) lines in all: $(cat "$RL")"
[ "$(rline 5)" = "take${T}2026-11-07T08:17:00Z${T}1${T}feat/st2${T}take${T}${T}${T}${T}2026-11-07T08:16:40Z${T}2026-11-07T08:17:00Z${T}" ] || fail "record: the take line before the abandon: $(rline 5)"
[ "$(rline 6)" = "free${T}2026-11-07T08:18:20Z${T}1${T}feat/st2${T}abandoned${T}${T}${T}${T}${T}${T}" ] || fail "record: the free line of the abandon: $(rline 6)"
git -C "$tmp/work" branch -D feat/st2 >/dev/null

# 6 a take, a merged PR and a second take: the reap appends a free line with the name reaped
rtake 2000 2020 --take feat/st3 --slot 1
rmerged feat/st3 9 "$(git -C "$tmp/wt/slot-1" rev-parse refs/heads/feat/st3)" 2026-11-07T08:35:00Z 2026-11-07T08:40:00Z 55
rtake 3000 3030 --take feat/st4
[ "$(rlines)" = 9 ] || fail "record: take, reap and take gave $(rlines) lines in all: $(cat "$RL")"
[ "$(rline 8)" = "free${T}2026-11-07T08:50:00Z${T}1${T}feat/st3${T}reaped${T}${T}${T}9${T}2026-11-07T08:35:00Z${T}2026-11-07T08:40:00Z${T}55" ] || fail "record: the free line of the reap: $(rline 8)"
[ "$(rline 9)" = "take${T}2026-11-07T08:50:30Z${T}1${T}feat/st4${T}take${T}${T}${T}${T}2026-11-07T08:50:00Z${T}2026-11-07T08:50:30Z${T}" ] || fail "record: the take line after the reap: $(rline 9)"
reset_gh
rclock 3100
bash "$S" --abandon 1 >/dev/null 2>&1 || fail "record: --abandon of the second take failed"
git -C "$tmp/work" branch -D feat/st3 feat/st4 >/dev/null 2>&1 || true
[ "$(rlines)" = 10 ] || fail "record: the abandon of the second take gave $(rlines) lines in all"

# 7 a dead claim freed with --abandon appends nothing, because that take wrote no line
dead=$(dead_pid)
taking_text 1 feat/st6 2026-11-05T09:00:00 "$dead" > "$(marker 1)"
rep --abandon 1
[ "$rc" = 0 ] && grep -q 'a take that did not finish' <<<"$out" || fail "record: --abandon of a dead claim: exit $rc: $out / $err"
[ "$(rlines)" = 10 ] || fail "record: the abandon of a dead claim appended a line: $(tail -n 1 "$RL")"

# 8 a record that cannot be written changes nothing else: one note on standard error, after the retries
cp "$RL" "$tmp/ledger.saved"
rm -f "$RL"; mkdir "$RL"
json_marker 1 feat/st5 2026-11-05T09:00:00 > "$(marker 1)"
rep --report check --slot 1 --skill next --role implementer
[ "$rc" = 0 ] || fail "record: a report with an unwritable record exited $rc: $err"
[ "$(mget 1 step)/$(mget 1 skill)/$(mget 1 role)" = "check/next/implementer" ] || fail "record: the marker was not updated: $(mtext 1)"
[ -z "$out" ] || fail "record: a report with an unwritable record printed $out"
[ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" = 1 ] && [[ "$err" == "slot: the record was not written ("*")" ]] || fail "record: the note about the unwritable record: [$err]"
rmdir "$RL"; cp "$tmp/ledger.saved" "$RL"
rm -f "$(marker 1)"

# 9 an unusable clock file gives one note and a stamp from the system clock
json_marker 1 feat/st7 2026-11-05T09:00:00 > "$(marker 1)"
note='ledger: NIGHTMILL_CLOCK_FILE is not usable; using the system clock'
for bad in missing text; do
  if [ "$bad" = text ]; then echo "later" > "$tmp/badclock"; else rm -f "$tmp/badclock"; fi
  n0=$(rlines)
  NIGHTMILL_CLOCK_FILE="$tmp/badclock" rep --report check --slot 1 --skill next --role implementer
  [ "$rc" = 0 ] || fail "record: unusable clock ($bad): exit $rc: $err"
  grep -qxF "$note" <<<"$err" || fail "record: unusable clock ($bad): no note: [$err]"
  [ "$(rlines)" = $((n0 + 1)) ] || fail "record: unusable clock ($bad): the report wrote $(( $(rlines) - n0 )) lines"
  stamp=$(tail -n 1 "$RL" | cut -f2)
  [[ "$stamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || fail "record: unusable clock ($bad): the stamp is not UTC YYYY-MM-DDTHH:MM:SSZ: $stamp"
  d=$(( $(date -u +%s) - $(date -u -d "$stamp" +%s) )); if [ "$d" -lt 0 ]; then d=$((-d)); fi
  [ "$d" -le 300 ] || fail "record: unusable clock ($bad): the stamp $stamp is $d s from the system clock"
done
rm -f "$(marker 1)"

# 10 every line has exactly eleven tab-separated fields
bad=$(awk -F '\t' 'NF != 11 { print NR ": " $0 }' "$RL")
[ -z "$bad" ] || fail "record: lines without eleven fields: $bad"
[ -s "$RL" ] || fail "record: the record is empty"
if grep -q $'\r' "$RL"; then fail "record: the record has carriage returns"; fi
# the record is no marker: the slot status does not see it
[ "$(bash "$S" --status --porcelain)" = "$(printf '1\tfree\n2\tfree')" ] || fail "record: the status changed with a record: $(bash "$S" --status --porcelain)"
unset NIGHTMILL_CLOCK_FILE
claim_reset

echo "== slot numbers take only digits (bug 128)"
# --slot, --release and --abandon accept only digits and normalise them (02 is slot 2); anything else prints the
# usage line, exits 1 and changes nothing
reset_gh
rep --take feat/n1 --slot 02
[ "$rc" = 0 ] && grep -q "Slot 2 is yours" <<<"$out" || fail "number: --take --slot 02: exit $rc: $out / $err"
[ ! -e "$tmp/wt/slot-02" ] && [ ! -e "$tmp/wt/.slots/slot-02.json" ] || fail "number: --take --slot 02 made slot-02"
grep -q '"slot": 2,' "$(marker 2)" || fail "number: the marker of --slot 02: $(mtext 2)"
rep --abandon 02
[ "$rc" = 0 ] && [ ! -f "$(marker 2)" ] || fail "number: --abandon 02: exit $rc: $out / $err"
reset_gh; bash "$S" --take feat/n2 --slot 2 >/dev/null 2>&1
echo n2 > "$tmp/wt/slot-2/number-n2.txt"; G "$tmp/wt/slot-2" add -A; G "$tmp/wt/slot-2" commit -qm "work on feat/n2"
git -C "$tmp/wt/slot-2" push -q origin feat/n2 2>/dev/null; merged feat/n2 28 "$(git -C "$tmp/wt/slot-2" rev-parse HEAD)"
rep --release 02
[ "$rc" = 0 ] && grep -q "Slot 2 is free (was feat/n2, PR #28)." <<<"$out" || fail "number: --release 02: exit $rc: $out / $err"
[ ! -f "$(marker 2)" ] || fail "number: --release 02 left the marker"
reset_gh; bash "$S" --take feat/n3 --slot 2 >/dev/null 2>&1
mlist() { ls "$tmp/wt/.slots" | { grep -v '^ledger' || true; } | tr '\n' ' '; }
before=$(mlist); m2=$(mtext 2)
for v in 1x -1 ""; do
  for args in "--take feat/n4 --slot" "--release" "--abandon"; do
    # shellcheck disable=SC2086
    rep $args "$v"
    [ "$rc" = 1 ] || fail "number: $args '$v': exit $rc"
    [[ "$err" == "usage: "* ]] || fail "number: $args '$v': no usage line: $err"
    [ -z "$out" ] || fail "number: $args '$v': printed $out"
    [ "$(mlist)" = "$before" ] && [ "$(mtext 2)" = "$m2" ] || fail "number: $args '$v' changed the markers: $(mlist)"
  done
done
[ ! -e "$tmp/wt/slot-1x" ] || fail "number: a slot directory was made for 1x"
bash "$S" --abandon 2 >/dev/null
git -C "$tmp/work" branch -D feat/n1 feat/n3 >/dev/null 2>&1 || true

echo "SMOKE OK"
