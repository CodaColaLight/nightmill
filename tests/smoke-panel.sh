#!/usr/bin/env bash
# tests/smoke-panel.sh - panel.sh against fixtures (iteration 32): the slot markers of
# tests/fixtures/panel/run-stall-old-free/ are written into a throwaway project, the clock is fixed
# (NIGHTMILL_NOW = 2026-11-05T12:00:00) and every case runs panel.sh in a child process. The output of the first case
# must equal expected.txt, which smoke-panel.ps1 compares with too; UPDATE_PANEL_FIXTURES=1 rewrites it (read the diff
# before committing). A fake gh that logs its calls is first on the PATH: the panel never calls it. Needs bash and awk,
# no jq, no network. Nothing sleeps.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-panel.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
P="$here/scripts/panel.sh"
FIX="$here/tests/fixtures/panel/run-stall-old-free"
NOW=1793880000
TAB=$(printf '\t')
NOTE_INTERVAL="note${TAB}worktrees.panelRefreshSeconds must be a whole number from 5 to 3600; using 15"

fail() { echo "FAIL: $*" >&2; exit 1; }

# The project: one config with four slots and no panelRefreshSeconds, in a throwaway repository.
git init -q -b main "$tmp/work"
cd "$tmp/work" || exit 1
mkdir -p .claude
cat > "$tmp/with-slots.json" <<'EOF'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "labels": { "epic": "epic" },
  "git": { "baseBranch": "main", "specPrefix": "spec/" },
  "worktrees": { "root": "../wt", "slots": 4 }
}
EOF
cp "$tmp/with-slots.json" .claude/nightmill.json
sed '/"worktrees"/d; s/"specPrefix": "spec\/" },/"specPrefix": "spec\/" }/' "$tmp/with-slots.json" > "$tmp/no-slots.json"
grep -q worktrees "$tmp/no-slots.json" && fail "the config copy without worktrees still has it"
with_worktrees_key() { # with_worktrees_key <json fragment>: the config with one more key in worktrees
  sed "s|\"slots\": 4 }|\"slots\": 4, $1 }|" "$tmp/with-slots.json" > .claude/nightmill.json
  grep -qF -- "$1" .claude/nightmill.json || fail "the config copy has no $1"
}
mkdir "$tmp/plain" && git init -q -b main "$tmp/plain"
mkdir "$tmp/nogit"
mkdir "$tmp/tdir"

# A fake gh: it logs every call to $GH_LOG and fails. The panel never calls it.
mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
echo "gh must not be called by the panel" >&2
exit 1
EOF
chmod +x "$tmp/bin/gh"
: > "$tmp/gh.log"

# shellcheck source=../scripts/lib/json.sh
. "$here/scripts/lib/json.sh"
markers() { # markers: set the busy slots of the fixture; a line with the four report columns is a seven-key marker
  rm -rf "$tmp/wt"; mkdir -p "$tmp/wt/.slots"
  local n branch since skill role step reported
  while IFS=$'\t' read -r n branch since skill role step reported; do
    [ -n "$n" ] || continue
    if [ -n "$skill" ]; then
      json_marker_report "$n" "$branch" "$since" "$skill" "$role" "$step" "$reported" > "$tmp/wt/.slots/slot-$n.json"
    else
      json_marker "$n" "$branch" "$since" > "$tmp/wt/.slots/slot-$n.json"
    fi
  done < "$FIX/markers.txt"
}

run_p() { # run_p <dir> [args]: the output in out.txt and err.txt, the exit code in $code
  local dir=$1
  shift
  set +e
  (cd "$dir" && PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" NIGHTMILL_NOW=$NOW TMPDIR="$tmp/tdir" bash "$P" "$@") > "$tmp/out.txt" 2> "$tmp/err.txt"
  code=$?
  set -e
}

same() { # same <name> <expected file>: the last output equals the file
  if ! cmp -s "$2" "$tmp/out.txt"; then
    diff "$2" "$tmp/out.txt" >&2 || true
    fail "$1: the output differs from $2"
  fi
}

markers
cp -R "$tmp/wt/.slots" "$tmp/markers-written"
before=$(git status --porcelain --untracked-files=all)

echo "== the records of the slots"
run_p "$tmp/work"
[ "$code" = 0 ] || fail "exit code $code: $(cat "$tmp/err.txt")"
if [ "${UPDATE_PANEL_FIXTURES:-}" = 1 ]; then cp "$tmp/out.txt" "$FIX/expected.txt"; fi
same "records" "$FIX/expected.txt"
[ ! -s "$tmp/err.txt" ] || fail "the panel printed on standard error: $(cat "$tmp/err.txt")"
cp "$tmp/out.txt" "$tmp/good.txt"
if LC_ALL=C grep -q "$(printf '\r')" "$tmp/out.txt"; then fail "a carriage return in the output"; fi
[ "$(sed -n 1p "$tmp/out.txt")" = "time${TAB}12:00:00" ] || fail "the first record is not the time of NIGHTMILL_NOW"
[ "$(sed -n 2p "$tmp/out.txt")" = "every${TAB}15" ] || fail "the second record is not every 15"

echo "== field counts"
awk -F '\t' '$1 == "slot" && NF != 8 { bad = 1; print "  " $0 } END { exit bad }' "$tmp/out.txt" >&2 || fail "a slot record without eight fields"
[ "$(grep -c '^slot' "$tmp/out.txt")" = 4 ] || fail "not four slot records"
grep -qxF "slot${TAB}4${TAB}free${TAB}${TAB}${TAB}${TAB}${TAB}" "$tmp/out.txt" || fail "the free slot is not slot, 4, free and five empty fields"

echo "== the interval is a config value"
with_worktrees_key '"panelRefreshSeconds": 30'
run_p "$tmp/work"
[ "$code" = 0 ] || fail "30: exit code $code: $(cat "$tmp/err.txt")"
awk -F '\t' -v OFS='\t' '$1 == "every" { $2 = 30 } { print }' "$tmp/good.txt" > "$tmp/want.txt"
same "panelRefreshSeconds 30" "$tmp/want.txt"
for v in 5 3600; do
  with_worktrees_key "\"panelRefreshSeconds\": $v"
  run_p "$tmp/work"
  [ "$code" = 0 ] || fail "$v: exit code $code"
  grep -qxF "every${TAB}$v" "$tmp/out.txt" || fail "the bounds: $v is a usable interval"
  grep -q '^note' "$tmp/out.txt" && fail "$v: a note for a usable interval"
done
{ cat "$tmp/good.txt"; printf '%s\n' "$NOTE_INTERVAL"; } > "$tmp/want.txt"
for v in 0 4 3601 2.5 15.0 '"15"' true; do
  with_worktrees_key "\"panelRefreshSeconds\": $v"
  run_p "$tmp/work"
  [ "$code" = 0 ] || fail "$v: exit code $code: $(cat "$tmp/err.txt")"
  same "panelRefreshSeconds $v" "$tmp/want.txt"
done
v=null
with_worktrees_key "\"panelRefreshSeconds\": $v"
run_p "$tmp/work"
[ "$code" = 0 ] || fail "$v: exit code $code: $(cat "$tmp/err.txt")"
same "panelRefreshSeconds $v" "$tmp/good.txt"
cp "$tmp/with-slots.json" .claude/nightmill.json
run_p "$tmp/work"
same "no panelRefreshSeconds" "$tmp/good.txt"

echo "== the slot script's notes pass"
with_worktrees_key '"stalledAfterMinutes": 0'
run_p "$tmp/work"
[ "$code" = 0 ] || fail "stalledAfterMinutes 0: exit code $code: $(cat "$tmp/err.txt")"
{ cat "$tmp/good.txt"; printf 'note\tslot: worktrees.stalledAfterMinutes must be a whole number of at least 1; using 30\n'; } > "$tmp/want.txt"
same "stalledAfterMinutes 0" "$tmp/want.txt"
cp "$tmp/with-slots.json" .claude/nightmill.json

echo "== an unreadable marker is never free"
printf '{ not json' > "$tmp/wt/.slots/slot-2.json"
run_p "$tmp/work"
[ "$code" = 0 ] || fail "unreadable marker: exit code $code: $(cat "$tmp/err.txt")"
grep -qxF "slot${TAB}2${TAB}free${TAB}${TAB}${TAB}${TAB}${TAB}" "$tmp/out.txt" && fail "a slot with an unreadable marker is listed free"
grep -q "^slot${TAB}2${TAB}free" "$tmp/out.txt" && fail "a slot with an unreadable marker starts with slot, 2, free"
grep -qxF "slot${TAB}2${TAB}busy${TAB}unknown${TAB}${TAB}?${TAB}?${TAB}-" "$tmp/out.txt" || fail "slot 2 is not busy and unknown: $(cat "$tmp/out.txt")"
cp "$tmp/markers-written/slot-2.json" "$tmp/wt/.slots/slot-2.json"

echo "== a failing slot script is unknown"
WORKER_SLOTS=abc run_p "$tmp/work"
[ "$code" = 0 ] || fail "WORKER_SLOTS=abc: exit code $code: $(cat "$tmp/err.txt")"
printf 'time\t12:00:00\nevery\t15\nunknown\tWORKER_SLOTS must be a number from 1 to 99\n' > "$tmp/want.txt"
same "WORKER_SLOTS=abc" "$tmp/want.txt"
grep -q '^slot' "$tmp/out.txt" && fail "a slot record after a failed slot script"
run_p "$tmp/work"
same "after WORKER_SLOTS" "$tmp/good.txt"

echo "== without worktrees"
cp "$tmp/no-slots.json" .claude/nightmill.json
run_p "$tmp/work"
[ "$code" = 0 ] || fail "no worktrees: exit code $code: $(cat "$tmp/err.txt")"
printf 'time\t12:00:00\nevery\t15\nnoslots\n' > "$tmp/want.txt"
same "no worktrees" "$tmp/want.txt"
cp "$tmp/with-slots.json" .claude/nightmill.json

echo "== errors"
for a in --help x; do
  run_p "$tmp/work" "$a"
  [ "$code" = 2 ] || fail "argument $a: exit code $code, expected 2"
  grep -qF 'usage: panel.sh' "$tmp/err.txt" || fail "argument $a: no usage line: $(cat "$tmp/err.txt")"
  [ ! -s "$tmp/out.txt" ] || fail "argument $a: output on standard output"
done
run_p "$tmp/nogit"
[ "$code" = 2 ] || fail "outside a checkout: exit code $code, expected 2"
grep -qF 'run panel.sh from inside a checkout of the project' "$tmp/err.txt" || fail "outside a checkout: $(cat "$tmp/err.txt")"
[ ! -s "$tmp/out.txt" ] || fail "outside a checkout: output on standard output"
run_p "$tmp/plain"
[ "$code" = 2 ] || fail "no config: exit code $code, expected 2"
grep -qF 'run /nightmill:init' "$tmp/err.txt" || fail "no config: $(cat "$tmp/err.txt")"
[ ! -s "$tmp/out.txt" ] || fail "no config: output on standard output"
printf '{ not json' > .claude/nightmill.json
run_p "$tmp/work"
[ "$code" = 2 ] || fail "a config that is not valid JSON: exit code $code, expected 2"
grep -qF 'is not valid JSON' "$tmp/err.txt" || fail "a config that is not valid JSON: $(cat "$tmp/err.txt")"
[ ! -s "$tmp/out.txt" ] || fail "a config that is not valid JSON: output on standard output"
cp "$tmp/with-slots.json" .claude/nightmill.json

echo "== nothing is changed"
[ "$(git status --porcelain --untracked-files=all)" = "$before" ] || fail "git status of the project changed"
diff -r "$tmp/markers-written" "$tmp/wt/.slots" > /dev/null || fail "a marker or the slot folder changed: $(diff -r "$tmp/markers-written" "$tmp/wt/.slots" 2>&1 | head -5)"
[ "$(ls -A "$tmp/wt" | tr '\n' ' ')" = ".slots " ] || fail "the slot root holds more than .slots: $(ls -A "$tmp/wt")"
[ ! -s "$tmp/gh.log" ] || fail "the panel called gh: $(cat "$tmp/gh.log")"
[ -z "$(ls -A "$tmp/tdir")" ] || fail "the panel left files in its temporary folder: $(ls -A "$tmp/tdir")"

echo "PANEL OK"
