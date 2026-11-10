#!/usr/bin/env bash
# tests/test-slot-number.sh - bug 128: --slot, --release and --abandon take only digits and normalise them
# (02 is slot 2); anything else prints the usage line and changes nothing. bash only: the PowerShell twin binds
# -Slot, -Release and -Abandon as integers, so it needs no test of its own.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-slotnum.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
S="$here/scripts/slot.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

# A fake gh: every merged query answers with the rows of $GH_FIX/merged.txt (branch TAB number TAB head commit).
mkdir -p "$tmp/bin" "$tmp/fix"
: > "$tmp/fix/merged.txt"
cat > "$tmp/bin/gh" <<'EOF2'
#!/usr/bin/env bash
[ "$1 $2" = "pr list" ] || { echo "unexpected gh call: $*" >&2; exit 1; }
state=""; head=""; expr=""
while [ $# -gt 0 ]; do
  case "$1" in --state) state=$2; shift ;; --head) head=$2; shift ;; -q) expr=$2; shift ;; esac
  shift
done
if [ "$state" != merged ]; then echo "[]"; exit 0; fi
rows=$(awk -F'\t' -v h="$head" '$1 == h' "$GH_FIX/merged.txt")
if [ -n "$expr" ]; then printf '%s\n' "$rows" | head -1 | cut -f2; exit 0; fi
n=$(printf '%s\n' "$rows" | head -1 | cut -f2); o=$(printf '%s\n' "$rows" | head -1 | cut -f3)
if [ -z "$n" ]; then echo "[]"; else echo "[{\"number\":$n,\"headRefOid\":\"$o\",\"createdAt\":\"\",\"mergedAt\":\"\",\"closingIssuesReferences\":[]}]"; fi
EOF2
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" GH_FIX="$tmp/fix"

git init -q --bare "$tmp/origin.git"
git init -q -b main "$tmp/work"
cd "$tmp/work"
git config core.autocrlf false
mkdir -p .claude
cat > .claude/nightmill.json <<'EOF2'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "git": { "baseBranch": "main" },
  "worktrees": { "root": "../wt", "slots": 3 }
}
EOF2
git add -A
git -c user.name=t -c user.email=t@example.invalid commit -qm init
git remote add origin "$tmp/origin.git"
git push -q origin main
# iteration 48: the config comes from the base branch (origin/HEAD)
git remote set-head origin main

slots="$tmp/wt/.slots"
rep() { set +e; out=$(bash "$S" "$@" 2>"$tmp/err.txt"); rc=$?; set -e; err=$(cat "$tmp/err.txt"); }
markers() { ls "$slots" 2>/dev/null | tr '\n' ' ' || true; }

echo "== --take --slot 02 ends in slot 2"
rep --take feat/z --slot 02
[ "$rc" = 0 ] || fail "take --slot 02: exit $rc: $err"
case "$out" in *"Slot 2 is yours"*) ;; *) fail "take --slot 02: not slot 2: $out" ;; esac
[ ! -e "$tmp/wt/slot-02" ] || fail "take --slot 02 created the directory slot-02"
[ ! -e "$slots/slot-02.json" ] || fail "take --slot 02 wrote the marker slot-02.json"
[ -f "$slots/slot-2.json" ] || fail "take --slot 02: no marker for slot 2 ($(markers))"
if grep -q '"slot": 0' "$slots/slot-2.json"; then fail "marker has a leading zero: $(cat "$slots/slot-2.json")"; fi
grep -q '"slot": 2,' "$slots/slot-2.json" || fail "marker does not say slot 2: $(cat "$slots/slot-2.json")"

echo "== --status lists slot 2 as busy"
rep --status
grep -q '^slot 2 .*busy: feat/z' <<<"$out" || fail "status does not show slot 2 busy: $out"

echo "== --abandon 02 frees slot 2"
rep --abandon 02
[ "$rc" = 0 ] || fail "abandon 02: exit $rc: $err"
case "$out" in "Slot 2 is free (was feat/z;"*) ;; *) fail "abandon 02: wrong output: $out / $err" ;; esac
[ ! -e "$slots/slot-2.json" ] || fail "abandon 02 left the marker"

echo "== --release 02 frees slot 2 after a merge"
bash "$S" --take feat/r --slot 2 >/dev/null 2>&1
d="$tmp/wt/slot-2"
echo r > "$d/work.txt"
git -C "$d" add -A
git -C "$d" -c user.name=t -c user.email=t@example.invalid commit -qm work
git -C "$d" push -q origin feat/r 2>/dev/null
printf '%s\t%s\t%s\n' feat/r 7 "$(git -C "$d" rev-parse HEAD)" > "$tmp/fix/merged.txt"
rep --release 02
[ "$rc" = 0 ] || fail "release 02: exit $rc: $err"
case "$out" in *"Slot 2 is free (was feat/r, PR #7)."*) ;; *) fail "release 02: wrong output: $out / $err" ;; esac
[ ! -e "$slots/slot-2.json" ] || fail "release 02 left the marker"

echo "== a value that is not digits prints the usage line and changes nothing"
bash "$S" --take feat/keep --slot 1 >/dev/null 2>&1
before=$(markers); m1=$(cat "$slots/slot-1.json")
for args in "--take feat/q --slot x" "--take feat/q --slot 1x" "--take feat/q --slot -1" "--abandon 1x" "--abandon x" "--abandon -1" "--release 1x" "--release x"; do
  # shellcheck disable=SC2086
  rep $args
  [ "$rc" != 0 ] || fail "'$args' was accepted"
  [[ "$err" == "usage: "* ]] || fail "'$args': no usage line: $err"
  [ -z "$out" ] || fail "'$args': printed $out"
  [ "$(markers)" = "$before" ] || fail "'$args' changed the markers: $(markers)"
  [ "$(cat "$slots/slot-1.json")" = "$m1" ] || fail "'$args' changed the marker of slot 1"
done
rep --abandon ""
[ "$rc" != 0 ] && [[ "$err" == "usage: "* ]] || fail "empty --abandon: no usage line: $err"
[ ! -e "$tmp/wt/slot-x" ] || fail "a slot directory was created for a bad value"
echo "ok"
