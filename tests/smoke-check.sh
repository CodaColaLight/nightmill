#!/usr/bin/env bash
# tests/smoke-check.sh - the parallel check and its quick mode (iteration 42): tests/check.sh against fixture steps
# (NIGHTMILL_CHECK_STEPS, lines <name> TAB <command> [TAB <kind> [TAB <reason>]]), the order and the verdict, the
# limit of 1, the quick mode, --only and the usage errors, the limit from the config, two checks at once, and the
# lint section that keeps the check's step list and CI in step. NIGHTMILL_CLOCK_FILE holds one fixed time, so every
# duration is 0s. Same cases and same expected text as tests/smoke-check.ps1. Needs bash, git and awk, no jq.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
unset UPDATE_STATUS_FIXTURES UPDATE_DASHBOARD_FIXTURES UPDATE_PANEL_FIXTURES NIGHTMILL_CHECK_STEPS
echo 1794038400 > "$tmp/clock"
export NIGHTMILL_CLOCK_FILE="$tmp/clock"
USAGE='usage: tests/check.sh [--quick | --only <step>[,<step>...] | --affected [--within <step>[,<step>...]]] [--jobs <1-16>] [--powershell powershell|pwsh] [--summary <file>]'

fail() { echo "FAIL: $*" >&2; exit 1; }
# barrier <file-test>: a loop of at most 300 tries, 0.1 s apart, then exit 9
barrier() { printf 'i=0; until %s; do i=$((i+1)); [ $i -gt 300 ] && exit 9; sleep 0.1; done' "$1"; }
# nrepo: a copy of tests/check.sh and scripts/lib/ with a configuration of its own that has no platform key, so the cases
# below do not read this repository's own .claude/nightmill.json (its verification.platform may be windows, unix, all or absent)
nrepo="$tmp/nrepo"
mkdir -p "$nrepo/tests" "$nrepo/scripts" "$nrepo/.claude"
cp "$here/tests/check.sh" "$here/tests/check.ps1" "$nrepo/tests/"
cp -R "$here/scripts/lib" "$nrepo/scripts/lib"
echo '{ "verification": { "check": "true" } }' > "$nrepo/.claude/nightmill.json"
# run_check <steps-file> <args...>: out, err, rc of tests/check.sh in nrepo
run_check() {
  local steps=$1; shift
  set +e
  out=$(NIGHTMILL_CHECK_STEPS="$steps" bash "$nrepo/tests/check.sh" "$@" 2>"$tmp/err.txt"); rc=$?
  set -e
  err=$(cat "$tmp/err.txt")
}
has_line() { grep -qxF -- "$2" <<<"$1"; }
# the processors, read as the check reads them
procs=""
procs=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || true)
case "$procs" in ''|*[!0-9]*) procs="" ;; esac
[ -z "$procs" ] || [ "$procs" -ge 1 ] || procs=""
# expect_header <limit> <why>: the full header after the cap
expect_header() {
  local l=$1 why=$2
  if [ -n "$procs" ] && [ "$l" -gt "$procs" ]; then l=$procs; why="$why, capped at $procs processors"; fi
  echo "check: full, $l at a time ($why)"
}

echo "== order and verdict"
steps="$tmp/steps1.txt"
{
  printf 'one\t%s; echo "out of one"\n' "$(barrier "[ -f '$tmp/two.done' ]")"
  printf 'two\techo "out of two"; touch "%s/two.done"\n' "$tmp"
  printf 'three\techo "out of three"; exit 1\n'
  printf 'four\ttrue\tbash\tfour cannot run here\n'
} > "$steps"
run_check "$steps" --jobs 3
[ "$rc" = 1 ] || fail "order: exit $rc: $out"
[ "$(head -n 1 <<<"$out")" = "check: full, 3 at a time (--jobs 3)" ] || fail "order: the header: $out"
got=$(printf '%s\n' "$out" | awk '/^== one$/ { p = 1 } p && NF { print } /^-- three:/ { p = 0 }')
want=$(printf '%s\n' '== one' 'out of one' '-- one: ok (0s)' '== two' 'out of two' '-- two: ok (0s)' '== three' 'out of three' '-- three: FAILED (0s)')
[ "$got" = "$want" ] || fail "order: the sections are not whole and in list order; got: [$got] wanted: [$want]"
names=$(printf '%s\n' "$out" | awk '/^Times:$/ { p = 1 } p && NF { print $1 } /^  total / { p = 0 }' | grep -xE 'Times:|one|two|three|total' | tr '\n' ' ')
[ "$names" = "Times: one two three total " ] || fail "order: the Times block: [$names] in: $out"
has_line "$out" 'SKIPPED: four cannot run here' || fail "order: no SKIPPED line for four: $out"
has_line "$out" 'CHECK FAILED: three' || fail "order: no CHECK FAILED: three: $out"
if grep -q 'ALL CHECKS PASSED' <<<"$out"; then fail "order: a failing check passed: $out"; fi

echo "== the limit of 1"
log="$tmp/limit.log"
mk_abc() { # mk_abc <a's wait>
  {
    printf 'a\techo "start a" >> "%s"; echo "out of a"; %s echo "end a" >> "%s"\n' "$log" "$1" "$log"
    printf 'b\techo "start b" >> "%s"; echo "b line 1"; echo "b line 2"; echo "end b" >> "%s"\n' "$log" "$log"
    printf 'c\techo "start c" >> "%s"; echo "out of c"; echo "end c" >> "%s"\n' "$log" "$log"
  } > "$tmp/abc.txt"
}
mk_abc ""
: > "$log"
run_check "$tmp/abc.txt" --jobs 1
[ "$rc" = 0 ] || fail "limit 1: exit $rc: $out"
[ "$(tr '\n' ',' < "$log")" = "start a,end a,start b,end b,start c,end c," ] || fail "limit 1: the steps did not run one after another: $(tr '\n' ',' < "$log")"
[ "$(tail -n 1 <<<"$out")" = "ALL CHECKS PASSED" ] || fail "limit 1: the last line: $out"
out1=$out
mk_abc "$(barrier "grep -q 'start c' '$log'");"
: > "$log"
run_check "$tmp/abc.txt" --jobs 3
[ "$rc" = 0 ] || fail "limit 3: exit $rc: $out"
ic=$(grep -n '^start c$' "$log" | head -n 1 | cut -d: -f1); ia=$(grep -n '^end a$' "$log" | head -n 1 | cut -d: -f1)
{ [ -n "$ic" ] && [ -n "$ia" ] && [ "$ic" -lt "$ia" ]; } || fail "limit 3: c did not start before a ended: $(tr '\n' ',' < "$log")"
[ "$(tail -n +2 <<<"$out")" = "$(tail -n +2 <<<"$out1")" ] || fail "limit 3: the output differs from --jobs 1 beyond the header: [$out] vs [$out1]"

echo "== quick"
qlog="$tmp/quick.log"
mk_quick() { # mk_quick <command of b>
  {
    printf 'l\techo l >> "%s"\tlint\n' "$qlog"
    printf 'b\techo b >> "%s"; %s\tbash\n' "$qlog" "$1"
    printf 'p\techo p >> "%s"\tps\n' "$qlog"
    printf 'c\techo c >> "%s"\tclaude\n' "$qlog"
  } > "$tmp/quick.txt"
}
mk_quick "true"
: > "$qlog"
run_check "$tmp/quick.txt" --quick
[ "$rc" = 0 ] || fail "quick: exit $rc: $out"
[ "$(sort "$qlog" | tr '\n' ',')" = "b,l," ] || fail "quick: the steps that ran: $(sort "$qlog" | tr '\n' ',')"
head -n 1 <<<"$out" | grep -E '^check: QUICK, [0-9]+ at a time \(.+\): the lint and the bash smoke tests only; the full check does not run$' >/dev/null || fail "quick: the first line: $out"
[ "$(tail -n 1 <<<"$out")" = "QUICK CHECK PASSED (the lint and the bash smoke tests only; the full check has not run)" ] || fail "quick: the last line: $out"
if grep -q 'ALL CHECKS PASSED' <<<"$out"; then fail "quick: printed ALL CHECKS PASSED: $out"; fi
if grep -q '^SKIPPED:' <<<"$out"; then fail "quick: printed a SKIPPED line: $out"; fi
mk_quick "exit 1"
: > "$qlog"
run_check "$tmp/quick.txt" --quick
[ "$rc" = 1 ] || fail "quick failing: exit $rc: $out"
[ "$(tail -n 1 <<<"$out")" = "QUICK CHECK FAILED: b (the full check has not run)" ] || fail "quick failing: the last line: $out"
if grep -q '^CHECK FAILED: ' <<<"$out"; then fail "quick failing: a line starts with CHECK FAILED: $out"; fi
if grep -q 'ALL CHECKS PASSED' <<<"$out"; then fail "quick failing: printed ALL CHECKS PASSED: $out"; fi

echo "== only and usage"
mk_quick "true"
: > "$qlog"
run_check "$tmp/quick.txt" --only b,l --jobs 1
[ "$rc" = 0 ] || fail "only: exit $rc: $out"
[ "$(tr '\n' ',' < "$qlog")" = "l,b," ] || fail "only: the steps did not run in list order: $(tr '\n' ',' < "$qlog")"
[ "$(head -n 1 <<<"$out" | cut -c1-16)" = "check: only l,b," ] || fail "only: the header: $out"
[ "$(tail -n 1 <<<"$out")" = "SELECTED CHECKS PASSED (2 of 4 steps; the full check has not run)" ] || fail "only: the last line: $out"
usage_case() { # usage_case <args...>
  : > "$qlog"
  run_check "$tmp/quick.txt" "$@"
  [ "$rc" = 2 ] || fail "usage ($*): exit $rc: $out"
  grep -qxF -- "$USAGE" <<<"$err" || fail "usage ($*): no usage line on standard error: $err"
  [ ! -s "$qlog" ] || fail "usage ($*): a step ran"
}
usage_case --only nope
grep -qxF 'check: no step named nope' <<<"$err" || fail "usage: no 'no step named nope' line: $err"
usage_case --quick --only b
usage_case --jobs 0
usage_case --jobs 17
usage_case --jobs x
usage_case --jobs
usage_case --powershell cmd
usage_case --quick --quick
usage_case extra

echo "== the limit from the config"
repo="$tmp/repo"
mkdir -p "$repo/tests" "$repo/scripts" "$repo/.claude"
cp "$here/tests/check.sh" "$here/tests/check.ps1" "$repo/tests/"
cp -R "$here/scripts/lib" "$repo/scripts/lib"
printf 'only\ttrue\n' > "$tmp/one-step.txt"
cfg_header() { # cfg_header <json for verification> [env...]: the header and the note of the check in $repo
  printf '{ "verification": { "check": "true"%s } }\n' "$1" > "$repo/.claude/nightmill.json"
  set +e
  out=$(NIGHTMILL_CHECK_STEPS="$tmp/one-step.txt" bash "$repo/tests/check.sh" 2>"$tmp/err.txt"); rc=$?
  set -e
  err=$(cat "$tmp/err.txt")
  [ "$rc" = 0 ] || fail "config ($1): exit $rc: $out $err"
}
NOTE='check: verification.checkJobs must be a whole number from 1 to 16; using 4'
cfg_header ', "checkJobs": 2'
[ "$(head -n 1 <<<"$out")" = "$(expect_header 2 'verification.checkJobs 2')" ] || fail "config 2: the header: $out"
cfg_header ', "checkJobs": 99'
[ "$(head -n 1 <<<"$out")" = "$(expect_header 4 'default 4')" ] || fail "config 99: the header: $out"
grep -qxF "$NOTE" <<<"$err" || fail "config 99: no note: $err"
cfg_header ', "checkJobs": "x"'
[ "$(head -n 1 <<<"$out")" = "$(expect_header 4 'default 4')" ] || fail "config x: the header: $out"
grep -qxF "$NOTE" <<<"$err" || fail "config x: no note: $err"
cfg_header ''
[ "$(head -n 1 <<<"$out")" = "$(expect_header 4 'default 4')" ] || fail "config none: the header: $out"
if grep -qF "$NOTE" <<<"$err"; then fail "config none: a note for a missing key: $err"; fi
printf '{ "verification": { "check": "true", "checkJobs": 2 } }\n' > "$repo/.claude/nightmill.json"
out=$(UPDATE_PANEL_FIXTURES=1 NIGHTMILL_CHECK_STEPS="$tmp/one-step.txt" bash "$repo/tests/check.sh" --jobs 3 2>/dev/null) || fail "config UPDATE: exit $?"
[ "$(head -n 1 <<<"$out")" = "check: full, 1 at a time (UPDATE_PANEL_FIXTURES is set)" ] || fail "config UPDATE: the header: $out"

echo "== the platform from the config"
# verification.platform (iteration 56): windows skips the bash steps, unix skips the ps steps, the lint and the claude steps
# always run, --only ignores the key. Four fixture steps l (lint), b (bash), p (ps), c (claude), each appending its name to one log.
plog="$tmp/platform.log"
WIN_LINE='SKIPPED: bash tests (verification.platform is windows)'
UNIX_LINE='SKIPPED: PowerShell tests (verification.platform is unix)'
PNOTE='check: verification.platform must be windows, unix or all; running both families'
mk_plat() { # mk_plat <reason of b> <reason of p>: the four steps in $tmp/plat.txt
  {
    printf 'l\techo l >> "%s"\tlint\n' "$plog"
    printf 'b\techo b >> "%s"\tbash\t%s\n' "$plog" "$1"
    printf 'p\techo p >> "%s"\tps\t%s\n' "$plog" "$2"
    printf 'c\techo c >> "%s"\tclaude\n' "$plog"
  } > "$tmp/plat.txt"
}
plat_run() { # plat_run <platform as JSON, or - for no key> <check.sh arguments...>: out, err, rc of the check in $repo; the log in $plat_log
  local val=$1; shift
  if [ "$val" = - ]; then printf '{ "verification": { "check": "true" } }\n' > "$repo/.claude/nightmill.json"
  else printf '{ "verification": { "check": "true", "platform": %s } }\n' "$val" > "$repo/.claude/nightmill.json"; fi
  : > "$plog"
  set +e
  out=$(NIGHTMILL_CHECK_STEPS="$tmp/plat.txt" bash "$repo/tests/check.sh" --jobs 1 "$@" 2>"$tmp/err.txt"); rc=$?
  set -e
  err=$(cat "$tmp/err.txt")
  plat_log=$(tr '\n' ',' < "$plog")
}
skipped_lines() { grep -c '^SKIPPED:' <<<"$1" || true; }
mk_plat "" ""
# windows: the PowerShell tests only
plat_run '"windows"'
[ "$rc" = 0 ] || fail "platform windows: exit $rc: $out $err"
[ "$plat_log" = "l,p,c," ] || fail "platform windows: the steps that ran: $plat_log"
[ "$(grep -cxF -- "$WIN_LINE" <<<"$out")" = 1 ] || fail "platform windows: not one '$WIN_LINE' line: $out"
[ "$(skipped_lines "$out")" = 1 ] || fail "platform windows: more SKIPPED lines than the platform's: $out"
if grep -qx '== b' <<<"$out"; then fail "platform windows: a section for the skipped bash step: $out"; fi
[ "$(tail -n 1 <<<"$out")" = "ALL CHECKS PASSED" ] || fail "platform windows: the last line: $out"
# unix: the bash tests only
plat_run '"unix"'
[ "$rc" = 0 ] || fail "platform unix: exit $rc: $out $err"
[ "$plat_log" = "l,b,c," ] || fail "platform unix: the steps that ran: $plat_log"
[ "$(grep -cxF -- "$UNIX_LINE" <<<"$out")" = 1 ] || fail "platform unix: not one '$UNIX_LINE' line: $out"
[ "$(skipped_lines "$out")" = 1 ] || fail "platform unix: more SKIPPED lines than the platform's: $out"
if grep -qx '== p' <<<"$out"; then fail "platform unix: a section for the skipped ps step: $out"; fi
[ "$(tail -n 1 <<<"$out")" = "ALL CHECKS PASSED" ] || fail "platform unix: the last line: $out"
# the platform's reason replaces the step's own reason
mk_plat "" "no pwsh here"
plat_run '"unix"'
[ "$rc" = 0 ] || fail "platform unix, p with a reason: exit $rc: $out $err"
[ "$plat_log" = "l,b,c," ] || fail "platform unix, p with a reason: the steps that ran: $plat_log"
has_line "$out" "$UNIX_LINE" || fail "platform unix, p with a reason: no platform line: $out"
if has_line "$out" 'SKIPPED: no pwsh here'; then fail "platform unix, p with a reason: the step's own reason was printed: $out"; fi
mk_plat "other reason" ""
plat_run '"windows"'
has_line "$out" "$WIN_LINE" || fail "platform windows, b with a reason: no platform line: $out"
if has_line "$out" 'SKIPPED: other reason'; then fail "platform windows, b with a reason: the step's own reason was printed: $out"; fi
# a skipped step of the kept family keeps its own reason, and both lines print in list order
mk_plat "" "no pwsh here"
plat_run '"windows"'
[ "$rc" = 0 ] || fail "platform windows, p with a reason: exit $rc: $out $err"
[ "$plat_log" = "l,c," ] || fail "platform windows, p with a reason: the steps that ran: $plat_log"
[ "$(grep '^SKIPPED:' <<<"$out" | tr '\n' '|')" = "$WIN_LINE|SKIPPED: no pwsh here|" ] || fail "platform windows, p with a reason: the SKIPPED lines or their order: $out"
[ "$(tail -n 1 <<<"$out")" = "ALL CHECKS PASSED" ] || fail "platform windows, p with a reason: the last line: $out"
# all and no key: today's behaviour, both families, nothing skipped, nothing on standard error
mk_plat "" ""
plat_run '"all"'
[ "$rc" = 0 ] || fail "platform all: exit $rc: $out $err"
[ "$plat_log" = "l,b,p,c," ] || fail "platform all: the steps that ran: $plat_log"
[ "$(skipped_lines "$out")" = 0 ] || fail "platform all: a SKIPPED line: $out"
[ -z "$err" ] || fail "platform all: standard error is not empty: $err"
out_all=$out
plat_run -
[ "$rc" = 0 ] || fail "platform not set: exit $rc: $out $err"
[ "$plat_log" = "l,b,p,c," ] || fail "platform not set: the steps that ran: $plat_log"
[ "$(skipped_lines "$out")" = 0 ] || fail "platform not set: a SKIPPED line: $out"
[ -z "$err" ] || fail "platform not set: standard error is not empty: $err"
[ "$out" = "$out_all" ] || fail "platform not set: the output differs from platform all: [$out] vs [$out_all]"
# any other value: the note, and both families run
for bad in '"linux"' 3; do
  plat_run "$bad"
  [ "$rc" = 0 ] || fail "platform $bad: exit $rc: $out $err"
  [ "$plat_log" = "l,b,p,c," ] || fail "platform $bad: the steps that ran: $plat_log"
  grep -qxF "$PNOTE" <<<"$err" || fail "platform $bad: no note on standard error: $err"
  [ "$(skipped_lines "$out")" = 0 ] || fail "platform $bad: a SKIPPED line: $out"
done
# --quick: the lint and the bash steps, then the key
QUICK_LAST='QUICK CHECK PASSED (the lint and the bash smoke tests only; the full check has not run)'
plat_run '"windows"' --quick
[ "$rc" = 0 ] || fail "platform windows, quick: exit $rc: $out $err"
[ "$plat_log" = "l," ] || fail "platform windows, quick: the steps that ran: $plat_log"
has_line "$out" "$WIN_LINE" || fail "platform windows, quick: no platform line: $out"
[ "$(tail -n 1 <<<"$out")" = "$QUICK_LAST" ] || fail "platform windows, quick: the last line: $out"
plat_run '"unix"' --quick
[ "$rc" = 0 ] || fail "platform unix, quick: exit $rc: $out $err"
[ "$plat_log" = "l,b," ] || fail "platform unix, quick: the steps that ran: $plat_log"
[ "$(skipped_lines "$out")" = 0 ] || fail "platform unix, quick: a SKIPPED line: $out"
[ "$(tail -n 1 <<<"$out")" = "$QUICK_LAST" ] || fail "platform unix, quick: the last line: $out"
# --only ignores the key, and does not read it either
for plat in '"windows"' '"unix"'; do
  plat_run "$plat" --only b,p
  [ "$rc" = 0 ] || fail "platform $plat, only: exit $rc: $out $err"
  [ "$plat_log" = "b,p," ] || fail "platform $plat, only: the steps that ran: $plat_log"
  [ "$(skipped_lines "$out")" = 0 ] || fail "platform $plat, only: a SKIPPED line: $out"
  [ "$(tail -n 1 <<<"$out")" = "SELECTED CHECKS PASSED (2 of 4 steps; the full check has not run)" ] || fail "platform $plat, only: the last line: $out"
done
plat_run '"linux"' --only b
[ "$rc" = 0 ] || fail "platform linux, only: exit $rc: $out $err"
[ "$plat_log" = "b," ] || fail "platform linux, only: the steps that ran: $plat_log"
if grep -qF "$PNOTE" <<<"$err"; then fail "platform linux, only: a note for a key that --only does not read: $err"; fi

echo "== affected"
# --affected (iteration 59): the lint plus the steps the changed paths map to. Six fixture steps l (lint), b1 b2 (bash), p1 p2 (ps),
# c (claude), each appending its name to one log. The map (NIGHTMILL_CHECK_MAP) and the paths (NIGHTMILL_CHECK_PATHS) are fixture files.
alog="$tmp/affected.log"
aff_map="$tmp/aff.map"
printf '%s\n' 'map scripts/foo.* b1,p1' 'map templates/t.md b2' 'shared scripts/lib/*' 'lintonly docs/*' > "$aff_map"
mk_aff() { # mk_aff <reason of b1> <reason of p1> <tail of b1's command> [<tail of b2's command>]: the six steps in $tmp/aff-steps.txt
  {
    printf 'l\techo l >> "%s"\tlint\n' "$alog"
    printf 'b1\techo b1 >> "%s"%s\tbash\t%s\n' "$alog" "$3" "$1"
    printf 'b2\techo b2 >> "%s"%s\tbash\n' "$alog" "${4:-}"
    printf 'p1\techo p1 >> "%s"\tps\t%s\n' "$alog" "$2"
    printf 'p2\techo p2 >> "%s"\tps\n' "$alog"
    printf 'c\techo c >> "%s"\tclaude\n' "$alog"
  } > "$tmp/aff-steps.txt"
}
aff_cfg() { # aff_cfg <platform as JSON, or - for no key>: the configuration of $repo
  if [ "$1" = - ]; then printf '{ "verification": { "check": "true" } }\n' > "$repo/.claude/nightmill.json"
  else printf '{ "verification": { "check": "true", "platform": %s } }\n' "$1" > "$repo/.claude/nightmill.json"; fi
}
aff_run() { # aff_run <the changed paths, one per line> <args...>: out, err, rc of tests/check.sh --affected in $repo; the log in $aff_log
  local paths=$1; shift
  printf '%s' "$paths" > "$tmp/aff.paths"
  : > "$alog"
  set +e
  out=$(NIGHTMILL_CHECK_STEPS="$tmp/aff-steps.txt" NIGHTMILL_CHECK_MAP="$aff_map" NIGHTMILL_CHECK_PATHS="$tmp/aff.paths" bash "$repo/tests/check.sh" --affected --jobs 1 "$@" 2>"$tmp/err.txt"); rc=$?
  set -e
  err=$(cat "$tmp/err.txt")
  aff_log=$(tr '\n' ',' < "$alog")
}
aff_first() { echo "check: AFFECTED, 1 at a time (--jobs 1): $1 of 6 steps, changed paths: $2 (against NIGHTMILL_CHECK_PATHS); the full check does not run"; }
mk_aff "" "" ""
aff_cfg -
# the steps the paths map to, in list order, and the lines around them
aff_run $'templates/t.md\ntests/p2\n'
[ "$rc" = 0 ] || fail "affected: exit $rc: $out $err"
[ "$aff_log" = "l,b2,p2," ] || fail "affected: the steps that ran: $aff_log"
[ "$(head -n 1 <<<"$out")" = "$(aff_first 3 2)" ] || fail "affected: the first line: $out"
has_line "$out" 'affected: templates/t.md -> b2' || fail "affected: no 'templates/t.md -> b2' line: $out"
has_line "$out" 'affected: tests/p2 -> p2' || fail "affected: no 'tests/p2 -> p2' line: $out"
[ "$(tail -n 1 <<<"$out")" = "AFFECTED CHECK PASSED (3 of 6 steps, changed paths: 2; the full check has not run)" ] || fail "affected: the last line: $out"
if grep -q 'ALL CHECKS PASSED' <<<"$out"; then fail "affected: printed ALL CHECKS PASSED: $out"; fi
# no changed path: the lint alone
aff_run ''
[ "$rc" = 0 ] || fail "affected, no path: exit $rc: $out $err"
[ "$aff_log" = "l," ] || fail "affected, no path: the steps that ran: $aff_log"
[ "$(head -n 1 <<<"$out")" = "$(aff_first 1 0)" ] || fail "affected, no path: the first line: $out"
# docs: the lint alone
aff_run $'docs/specs/x.md\n'
[ "$rc" = 0 ] || fail "affected, docs: exit $rc: $out $err"
[ "$aff_log" = "l," ] || fail "affected, docs: the steps that ran: $aff_log"
has_line "$out" 'affected: docs/specs/x.md -> the lint only' || fail "affected, docs: no 'the lint only' line: $out"
[ "$(head -n 1 <<<"$out")" = "$(aff_first 1 1)" ] || fail "affected, docs: the first line: $out"
# a shared file and an unknown path: the full check
for p in 'scripts/lib/x.sh|scripts/lib/x.sh is shared by many steps' 'other/thing|other/thing is in no line of the map'; do
  aff_run "${p%%|*}"$'\n'
  [ "$rc" = 0 ] || fail "affected, ${p%%|*}: exit $rc: $out $err"
  [ "$(head -n 1 <<<"$out")" = "check: AFFECTED: ${p##*|}; running the full check" ] || fail "affected, ${p%%|*}: the first line: $out"
  [ "$(sed -n 2p <<<"$out")" = "check: full, 1 at a time (--jobs 1)" ] || fail "affected, ${p%%|*}: the second line: $out"
  [ "$aff_log" = "l,b1,b2,p1,p2,c," ] || fail "affected, ${p%%|*}: the steps that ran: $aff_log"
  [ "$(tail -n 1 <<<"$out")" = "ALL CHECKS PASSED" ] || fail "affected, ${p%%|*}: the last line: $out"
done
# a changed script runs its tests in both shells, whatever verification.platform says
for plat in '"windows"' '"unix"' -; do
  aff_cfg "$plat"
  aff_run $'scripts/foo.ps1\n'
  [ "$rc" = 0 ] || fail "affected, script, platform $plat: exit $rc: $out $err"
  [ "$aff_log" = "l,b1,p1," ] || fail "affected, script, platform $plat: the steps that ran: $aff_log"
  if grep -q '^SKIPPED:.*verification\.platform' <<<"$out"; then fail "affected, script, platform $plat: a platform SKIPPED line: $out"; fi
done
# what the machine cannot run is listed as skipped
mk_aff "" "no pwsh here" ""
aff_cfg '"windows"'
aff_run $'scripts/foo.ps1\n'
[ "$rc" = 0 ] || fail "affected, p1 with a reason: exit $rc: $out $err"
[ "$aff_log" = "l,b1," ] || fail "affected, p1 with a reason: the steps that ran: $aff_log"
has_line "$out" 'SKIPPED: no pwsh here' || fail "affected, p1 with a reason: no SKIPPED line: $out"
mk_aff "" "" ""
# a shared file with a changed script: the full check under the platform, plus the steps the script selected
aff_run $'scripts/lib/x.sh\nscripts/foo.sh\n'
[ "$rc" = 0 ] || fail "affected, shared and script: exit $rc: $out $err"
[ "$aff_log" = "l,b1,p1,p2,c," ] || fail "affected, shared and script: the steps that ran: $aff_log"
has_line "$out" "$WIN_LINE" || fail "affected, shared and script: no platform line for b2: $out"
[ "$(head -n 1 <<<"$out")" = "check: AFFECTED: scripts/lib/x.sh is shared by many steps; running the full check" ] || fail "affected, shared and script: the first line: $out"
aff_cfg -
# a failing step: the last line and the exit code say it was not the full check
mk_aff "" "" "; exit 1"
aff_run $'scripts/foo.sh\n'
[ "$rc" = 1 ] || fail "affected failing: exit $rc: $out"
[ "$(tail -n 1 <<<"$out")" = "AFFECTED CHECK FAILED: b1 (the full check has not run)" ] || fail "affected failing: the last line: $out"
if grep -q 'ALL CHECKS PASSED' <<<"$out"; then fail "affected failing: printed ALL CHECKS PASSED: $out"; fi
if grep -q '^CHECK FAILED: ' <<<"$out"; then fail "affected failing: a line starts with CHECK FAILED: $out"; fi
mk_aff "" "" ""
# the changed paths from git: committed, unstaged and untracked, against origin/main
g="$tmp/gitrepo"
mkdir -p "$g/tests" "$g/scripts" "$g/.claude" "$g/templates"
cp "$here/tests/check.sh" "$here/tests/check.ps1" "$g/tests/"
cp -R "$here/scripts/lib" "$g/scripts/lib"
echo '{ "verification": { "check": "true" } }' > "$g/.claude/nightmill.json"
echo one > "$g/scripts/foo.sh"; echo one > "$g/templates/t.md"
gitg() { git -C "$g" -c user.email=t@example.com -c user.name=t "$@"; }
git init -q --bare "$tmp/origin.git"
git init -q "$g"
git -C "$g" symbolic-ref HEAD refs/heads/main
gitg add -A; gitg commit -q -m base
gitg remote add origin "$tmp/origin.git"
gitg push -q origin main
gitg checkout -q -b feature
echo two > "$g/templates/t.md"; gitg add -A; gitg commit -q -m "change a template"
echo two >> "$g/scripts/foo.sh"
mkdir -p "$g/docs"; echo new > "$g/docs/n.md"
git_aff() { # git_aff <args...>: out, err, rc of the check in $g, without NIGHTMILL_CHECK_PATHS; the log in $aff_log
  : > "$alog"
  set +e
  out=$(cd "$g" && NIGHTMILL_CHECK_STEPS="$tmp/aff-steps.txt" NIGHTMILL_CHECK_MAP="$aff_map" bash tests/check.sh --affected --jobs 1 "$@" 2>"$tmp/err.txt"); rc=$?
  set -e
  err=$(cat "$tmp/err.txt")
  aff_log=$(tr '\n' ',' < "$alog")
}
git_aff
[ "$rc" = 0 ] || fail "affected, git: exit $rc: $out $err"
[ "$(head -n 1 <<<"$out")" = "check: AFFECTED, 1 at a time (--jobs 1): 4 of 6 steps, changed paths: 3 (against origin/main); the full check does not run" ] || fail "affected, git: the first line: $out"
[ "$(grep '^affected:' <<<"$out" | tr '\n' '|')" = "affected: docs/n.md -> the lint only|affected: scripts/foo.sh -> b1,p1|affected: templates/t.md -> b2|" ] || fail "affected, git: the affected lines: $out"
# --within (iteration 60) with the paths from git: the steps of the list that the changed paths select
git_aff --within b1,b2
[ "$rc" = 0 ] || fail "affected within, git: exit $rc: $out $err"
[ "$aff_log" = "b1,b2," ] || fail "affected within, git: the steps that ran: $aff_log"
[ "$(head -n 1 <<<"$out")" = "check: AFFECTED, 1 at a time (--jobs 1): 2 of 2 steps, changed paths: 3 (against origin/main); the full check does not run" ] || fail "affected within, git: the first line: $out"
[ "$(grep '^affected:' <<<"$out" | tr '\n' '|')" = "affected: docs/n.md -> none of the --within steps|affected: scripts/foo.sh -> b1|affected: templates/t.md -> b2|" ] || fail "affected within, git: the affected lines: $out"
# a base branch with no origin/<branch>: the paths are unknown, so the full check
echo '{ "verification": { "check": "true" }, "git": { "baseBranch": "trunk" } }' > "$g/.claude/nightmill.json"
git_aff
[ "$(head -n 1 <<<"$out")" = "check: AFFECTED: the changed paths are unknown (no merge base with origin/trunk); running the full check" ] || fail "affected, no merge base: the first line: $out $err"
# with --within the unknown paths run every step of the list, as --only would
git_aff --within b2,p2
[ "$rc" = 0 ] || fail "affected within, no merge base: exit $rc: $out $err"
[ "$(head -n 1 <<<"$out")" = "check: AFFECTED: the changed paths are unknown (no merge base with origin/trunk); running every --within step" ] || fail "affected within, no merge base: the first line: $out $err"
[ "$(sed -n 2p <<<"$out")" = "check: only b2,p2, 1 at a time (--jobs 1)" ] || fail "affected within, no merge base: the second line: $out"
[ "$aff_log" = "b2,p2," ] || fail "affected within, no merge base: the steps that ran: $aff_log"

# --within (iteration 60): the steps of the list that the changed paths select; the lint only when the list names it, and
# verification.platform does not apply to a selected step
aff_cfg -
# a changed script and a changed doc against two bash steps: the script's step of the list, no lint
aff_run $'scripts/foo.ps1\ndocs/a.md\n' --within b1,b2
[ "$rc" = 0 ] || fail "within: exit $rc: $out $err"
[ "$aff_log" = "b1," ] || fail "within: the steps that ran: $aff_log"
[ "$(head -n 1 <<<"$out")" = "$(aff_first 1 2 | sed 's/ of 6 steps/ of 2 steps/')" ] || fail "within: the first line: $out"
[ "$(grep '^affected:' <<<"$out" | tr '\n' '|')" = "affected: docs/a.md -> none of the --within steps|affected: scripts/foo.ps1 -> b1|" ] || fail "within: the affected lines: $out"
[ "$(tail -n 1 <<<"$out")" = "AFFECTED CHECK PASSED (1 of 2 steps, changed paths: 2; the full check has not run)" ] || fail "within: the last line: $out"
if grep -q 'ALL CHECKS PASSED' <<<"$out"; then fail "within: printed ALL CHECKS PASSED: $out"; fi
# the PowerShell steps of the list: a changed script selects p1 even where verification.platform is unix
aff_cfg '"unix"'
aff_run $'scripts/foo.ps1\ndocs/a.md\n' --within p1,p2
[ "$rc" = 0 ] || fail "within, unix: exit $rc: $out $err"
[ "$aff_log" = "p1," ] || fail "within, unix: the steps that ran: $aff_log"
# the bash steps of the list: a changed script selects b1 even where verification.platform is windows
aff_cfg '"windows"'
aff_run $'scripts/foo.ps1\ndocs/a.md\n' --within b1,b2
[ "$rc" = 0 ] || fail "within, windows: exit $rc: $out $err"
[ "$aff_log" = "b1," ] || fail "within, windows: the steps that ran: $aff_log"
if grep -q '^SKIPPED:.*verification\.platform' <<<"$out"; then fail "within, windows: a platform SKIPPED line: $out"; fi
aff_cfg -
# a docs-only change: no step of a test list runs, and the run passes
aff_run $'docs/a.md\n' --within b1,p1
[ "$rc" = 0 ] || fail "within, docs only: exit $rc: $out $err"
[ -z "$aff_log" ] || fail "within, docs only: a step ran: $aff_log"
[ "$(head -n 1 <<<"$out")" = "check: AFFECTED, 1 at a time (--jobs 1): 0 of 2 steps, changed paths: 1 (against NIGHTMILL_CHECK_PATHS); the full check does not run" ] || fail "within, docs only: the first line: $out"
[ "$(tail -n 1 <<<"$out")" = "AFFECTED CHECK PASSED (0 of 2 steps, changed paths: 1; the full check has not run)" ] || fail "within, docs only: the last line: $out"
# the lint runs only when the list names it
aff_run $'docs/a.md\n' --within l,b1
[ "$rc" = 0 ] || fail "within, docs and the lint: exit $rc: $out $err"
[ "$aff_log" = "l," ] || fail "within, docs and the lint: the steps that ran: $aff_log"
# a shared path: every step of the list runs, as --only, whatever verification.platform says
aff_cfg '"windows"'
aff_run $'scripts/lib/x.sh\n' --within b2,p2
[ "$rc" = 0 ] || fail "within, shared: exit $rc: $out $err"
[ "$(head -n 1 <<<"$out")" = "check: AFFECTED: scripts/lib/x.sh is shared by many steps; running every --within step" ] || fail "within, shared: the first line: $out"
[ "$(sed -n 2p <<<"$out")" = "check: only b2,p2, 1 at a time (--jobs 1)" ] || fail "within, shared: the second line: $out"
[ "$aff_log" = "b2,p2," ] || fail "within, shared: the steps that ran: $aff_log"
[ "$(tail -n 1 <<<"$out")" = "SELECTED CHECKS PASSED (2 of 6 steps; the full check has not run)" ] || fail "within, shared: the last line: $out"
# a path in no line of the map: every step of the list runs
aff_run $'other/thing\n' --within b1,b2
[ "$rc" = 0 ] || fail "within, unknown path: exit $rc: $out $err"
[ "$(head -n 1 <<<"$out")" = "check: AFFECTED: other/thing is in no line of the map; running every --within step" ] || fail "within, unknown path: the first line: $out"
[ "$aff_log" = "b1,b2," ] || fail "within, unknown path: the steps that ran: $aff_log"
# a failing step of the fallback: the verdict is the one of --only
mk_aff "" "" "" "; exit 1"
aff_run $'scripts/lib/x.sh\n' --within b2,p2
[ "$rc" = 1 ] || fail "within, shared and failing: exit $rc: $out"
[ "$(tail -n 1 <<<"$out")" = "SELECTED CHECKS FAILED: b2 (the full check has not run)" ] || fail "within, shared and failing: the last line: $out"
mk_aff "" "" ""
aff_cfg -
# the summary: which steps ran, which were left out, and why
sumf="$tmp/aff-summary.md"
line_no() { grep -nxF -- "$1" "$sumf" | head -n 1 | cut -d: -f1; }
rm -f "$sumf"
aff_run $'scripts/foo.ps1\ndocs/a.md\n' --within b1,b2 --summary "$sumf"
[ "$rc" = 0 ] || fail "within summary: exit $rc: $out $err"
[ -f "$sumf" ] || fail "within summary: no summary file was written"
w_wall=$(grep -n '^Wall time: ' "$sumf" | head -n 1 | cut -d: -f1)
w_sel=$(line_no 'Selection: --affected against NIGHTMILL_CHECK_PATHS: 1 of 2 steps ran, 1 left out (no changed path selects them).')
w_head=$(line_no '| Changed path | Selects |')
w_r1=$(line_no '| `docs/a.md` | none of the --within steps |')
w_r2=$(line_no '| `scripts/foo.ps1` | b1 |')
w_ran=$(line_no 'Ran: `b1`')
w_left=$(line_no 'Left out: `b2`')
w_slow=$(line_no '| Slowest step | Time |')
for v in "$w_wall" "$w_sel" "$w_head" "$w_r1" "$w_r2" "$w_ran" "$w_left" "$w_slow"; do
  [ -n "$v" ] || fail "within summary: a line is missing from the summary: $(cat "$sumf")"
done
[ "$w_wall" -lt "$w_sel" ] && [ "$w_sel" -lt "$w_head" ] && [ "$w_head" -lt "$w_r1" ] && [ "$w_r1" -lt "$w_r2" ] &&
  [ "$w_r2" -lt "$w_ran" ] && [ "$w_ran" -lt "$w_left" ] && [ "$w_left" -lt "$w_slow" ] ||
  fail "within summary: the lines are not in the order wall time, selection, table in path order, ran, left out, slowest steps: $(cat "$sumf")"
# the fallback says why every step of the list ran
rm -f "$sumf"
aff_run $'scripts/lib/x.sh\n' --within b2,p2 --summary "$sumf"
[ "$rc" = 0 ] || fail "within summary, fallback: exit $rc: $out $err"
grep -qxF 'Selection: --affected ran every --within step: scripts/lib/x.sh is shared by many steps.' "$sumf" || fail "within summary, fallback: no Selection line: $(cat "$sumf")"
# more than fifty changed paths: fifty rows, then the count of the rest
many=""; for ((q = 1; q <= 51; q++)); do many="$many$(printf 'docs/p%02d.md' "$q")"$'\n'; done
rm -f "$sumf"
aff_run "$many" --within b1,b2 --summary "$sumf"
[ "$rc" = 0 ] || fail "within summary, 51 paths: exit $rc: $out $err"
[ "$(grep -c '^| `docs/p' "$sumf")" = 50 ] || fail "within summary, 51 paths: not 50 rows: $(cat "$sumf")"
grep -qxF 'And 1 more changed paths (the log lists every one).' "$sumf" || fail "within summary, 51 paths: no 'And 1 more' line: $(cat "$sumf")"
if grep -qF 'docs/p51.md' "$sumf"; then fail "within summary, 51 paths: the 51st path has a row: $(cat "$sumf")"; fi
[ "$(grep -c '^affected: ' <<<"$out")" = 51 ] || fail "within summary, 51 paths: the log does not list every path: $out"
# without --within the section is the one of --affected alone: the wall time, and no selection lines
for p in $'scripts/foo.ps1\ndocs/a.md\n' $'scripts/lib/x.sh\n'; do
  rm -f "$sumf"
  aff_run "$p" --summary "$sumf"
  [ "$rc" = 0 ] || fail "plain affected summary (${p%%$'\n'*}): exit $rc: $out $err"
  grep -q '^Wall time: ' "$sumf" || fail "plain affected summary (${p%%$'\n'*}): no Wall time line: $(cat "$sumf")"
  if grep -qE '^(Selection:|\| Changed path|Ran:|Left out:)' "$sumf"; then fail "plain affected summary (${p%%$'\n'*}): a selection line without --within: $(cat "$sumf")"; fi
done

# slow steps (iteration 62): the sixth field of a fixture line is slow or empty. A selective --affected run, with or without
# --within, leaves a slow step out and lists it; the full check, --only and the fallbacks run it as any step
mk_aff_slow() { # mk_aff_slow <reason of p1>: the six steps of mk_aff, p1 with the sixth field slow
  {
    printf 'l\techo l >> "%s"\tlint\n' "$alog"
    printf 'b1\techo b1 >> "%s"\tbash\n' "$alog"
    printf 'b2\techo b2 >> "%s"\tbash\n' "$alog"
    printf 'p1\techo p1 >> "%s"\tps\t%s\t\tslow\n' "$alog" "$1"
    printf 'p2\techo p2 >> "%s"\tps\n' "$alog"
    printf 'c\techo c >> "%s"\tclaude\n' "$alog"
  } > "$tmp/aff-steps.txt"
}
SLOW_LEFT='LEFT OUT: p1 (a slow step; the full check and CI on the base branch run it)'
times_names() { printf '%s\n' "$1" | awk '/^Times:$/ { p = 1 } p && NF { print $1 } /^  total / { p = 0 }'; }
aff_cfg -
mk_aff_slow ""
aff_run $'scripts/foo.ps1\n'
[ "$rc" = 0 ] || fail "slow, affected: exit $rc: $out $err"
[ "$aff_log" = "l,b1," ] || fail "slow, affected: the steps that ran: $aff_log"
[ "$(head -n 1 <<<"$out")" = "$(aff_first 2 1)" ] || fail "slow, affected: the first line: $out"
has_line "$out" 'affected: scripts/foo.ps1 -> b1,p1' || fail "slow, affected: no 'scripts/foo.ps1 -> b1,p1' line: $out"
has_line "$out" "$SLOW_LEFT" || fail "slow, affected: no LEFT OUT line for p1: $out"
if has_line "$out" '== p1'; then fail "slow, affected: a section for the slow step p1: $out"; fi
if grep -qx p1 <<<"$(times_names "$out")"; then fail "slow, affected: p1 is in the Times block: $out"; fi
[ "$(tail -n 1 <<<"$out")" = "AFFECTED CHECK PASSED (2 of 6 steps, changed paths: 1; the full check has not run)" ] || fail "slow, affected: the last line: $out"
# a slow step that cannot run here is listed as left out, not as skipped
mk_aff_slow "no pwsh here"
aff_run $'scripts/foo.ps1\n'
[ "$rc" = 0 ] || fail "slow, affected, with a reason: exit $rc: $out $err"
has_line "$out" "$SLOW_LEFT" || fail "slow, affected, with a reason: no LEFT OUT line for p1: $out"
if has_line "$out" 'SKIPPED: no pwsh here'; then fail "slow, affected, with a reason: a SKIPPED line for the slow step: $out"; fi
mk_aff_slow ""
# --within: the slow step of the list is left out, and the summary says so
rm -f "$sumf"
aff_run $'scripts/foo.ps1\n' --within b1,p1 --summary "$sumf"
[ "$rc" = 0 ] || fail "slow, within: exit $rc: $out $err"
[ "$aff_log" = "b1," ] || fail "slow, within: the steps that ran: $aff_log"
[ "$(head -n 1 <<<"$out")" = "$(aff_first 1 1 | sed 's/ of 6 steps/ of 2 steps/')" ] || fail "slow, within: the first line: $out"
has_line "$out" "$SLOW_LEFT" || fail "slow, within: no LEFT OUT line for p1: $out"
[ -f "$sumf" ] || fail "slow, within: no summary file was written"
grep -qxF 'Selection: --affected against NIGHTMILL_CHECK_PATHS: 1 of 2 steps ran, 1 left out (1 slow, 0 selected by no changed path).' "$sumf" || fail "slow, within: no Selection line: $(cat "$sumf")"
grep -qxF 'Slow steps left out: `p1` (a push to the base branch runs them).' "$sumf" || fail "slow, within: no 'Slow steps left out' line: $(cat "$sumf")"
# the places that still run a slow step
aff_plain() { # aff_plain <args...>: out, err, rc of the check in $repo without --affected, on the six steps; the log in $aff_log
  : > "$alog"
  set +e
  out=$(NIGHTMILL_CHECK_STEPS="$tmp/aff-steps.txt" NIGHTMILL_CHECK_MAP="$aff_map" bash "$repo/tests/check.sh" --jobs 1 "$@" 2>"$tmp/err.txt"); rc=$?
  set -e
  err=$(cat "$tmp/err.txt")
  aff_log=$(tr '\n' ',' < "$alog")
}
aff_plain --only p1
[ "$rc" = 0 ] || fail "slow, only: exit $rc: $out $err"
[ "$aff_log" = "p1," ] || fail "slow, only: the steps that ran: $aff_log"
if grep -q '^LEFT OUT:' <<<"$out"; then fail "slow, only: a LEFT OUT line: $out"; fi
aff_plain
[ "$rc" = 0 ] || fail "slow, full check: exit $rc: $out $err"
[ "$aff_log" = "l,b1,b2,p1,p2,c," ] || fail "slow, full check: the steps that ran: $aff_log"
if grep -q '^LEFT OUT:' <<<"$out"; then fail "slow, full check: a LEFT OUT line: $out"; fi
[ "$(tail -n 1 <<<"$out")" = "ALL CHECKS PASSED" ] || fail "slow, full check: the last line: $out"
aff_run $'scripts/lib/x.sh\n'
[ "$rc" = 0 ] || fail "slow, fallback: exit $rc: $out $err"
[ "$aff_log" = "l,b1,b2,p1,p2,c," ] || fail "slow, fallback: the steps that ran: $aff_log"
if grep -q '^LEFT OUT:' <<<"$out"; then fail "slow, fallback: a LEFT OUT line: $out"; fi
aff_run $'scripts/lib/x.sh\n' --within b2,p1
[ "$rc" = 0 ] || fail "slow, within fallback: exit $rc: $out $err"
[ "$aff_log" = "b2,p1," ] || fail "slow, within fallback: the steps that ran: $aff_log"
case "$(sed -n 2p <<<"$out")" in "check: only b2,p1, "*) ;; *) fail "slow, within fallback: the second line: $out" ;; esac
if grep -q '^LEFT OUT:' <<<"$out"; then fail "slow, within fallback: a LEFT OUT line: $out"; fi
# the sixth field is slow or empty
printf 'l\techo l >> "%s"\tlint\n' "$alog" > "$tmp/slow-bad.txt"
printf 'p1\techo p1 >> "%s"\tps\t\t\tfast\n' "$alog" >> "$tmp/slow-bad.txt"
: > "$alog"
run_check "$tmp/slow-bad.txt" --jobs 1
[ "$rc" = 2 ] || fail "slow, bad sixth field: exit $rc, wanted 2: $out"
grep -qxF "check: $tmp/slow-bad.txt: the sixth field is slow or empty, not fast" <<<"$err" || fail "slow, bad sixth field: no 'the sixth field is slow or empty, not fast' line: $err"
[ ! -s "$alog" ] || fail "slow, bad sixth field: a step ran: $(cat "$alog")"
mk_aff "" "" ""

# the usage errors
usage_case --affected --quick
usage_case --affected --only b
usage_case --affected --affected
usage_case --within b
usage_case --quick --within b
usage_case --only b --within b
usage_case --affected --within b --within c
usage_case --affected --within ''
usage_case --affected --within
usage_case --affected --within nope
grep -qxF 'check: no step named nope' <<<"$err" || fail "usage: no 'no step named nope' line for --within: $err"

echo "== two checks at once"
mkdir -p "$tmp/tmpA" "$tmp/tmpB"
for r in A B; do
  o=B; [ "$r" = B ] && o=A
  {
    printf 'run\techo "run %s"; touch "%s/started%s"; %s\n' "$r" "$tmp" "$r" "$(barrier "[ -f '$tmp/started$o' ]")"
    printf 'render\tbash "%s/tests/smoke-render.sh"\n' "$here"
    printf 'hook\tbash "%s/tests/smoke-hook.sh"\n' "$here"
  } > "$tmp/two$r.txt"
done
for r in A B; do
  ( TMPDIR="$tmp/tmp$r" NIGHTMILL_CHECK_STEPS="$tmp/two$r.txt" bash "$nrepo/tests/check.sh" --jobs 2 > "$tmp/out$r.txt" 2>&1; echo $? > "$tmp/rc$r.txt" ) &
done
wait
for r in A B; do
  o=B; [ "$r" = B ] && o=A
  rcr=$(cat "$tmp/rc$r.txt"); outr=$(cat "$tmp/out$r.txt")
  [ "$rcr" = 0 ] || fail "two checks: run $r exit $rcr: $outr"
  has_line "$outr" 'ALL CHECKS PASSED' || fail "two checks: run $r did not pass: $outr"
  has_line "$outr" "run $r" || fail "two checks: run $r lacks its own line: $outr"
  if grep -qxF "run $o" <<<"$outr"; then fail "two checks: run $r holds the line of run $o: $outr"; fi
  [ "$(printf '%s\n' "$outr" | grep -E '^-- (run|render|hook): ' | sed -E 's/^-- ([a-z]+):.*/\1/' | tr '\n' ' ')" = "run render hook " ] || fail "two checks: run $r sections not in list order: $outr"
  [ -z "$(ls -A "$tmp/tmp$r")" ] || fail "two checks: run $r left files in its TMPDIR: $(ls -A "$tmp/tmp$r")"
done

echo "== summary"
# --summary <file> appends the wall time and the five slowest steps (iteration 55, decision 6). The clock is moved by the steps.
sclock="$tmp/sclock"
mk_sum() { # mk_sum: six steps a to f, each advancing the clock by 5, 30, 1, 30, 12, 7 seconds; e exits 1
  local name sec extra
  : > "$tmp/sum-steps.txt"
  for pair in a:5 b:30 c:1 d:30 e:12 f:7; do
    name=${pair%%:*}; sec=${pair##*:}; extra=""
    [ "$name" != e ] || extra="; exit 1"
    printf '%s\tc=$(cat "%s"); echo $((c+%s)) > "%s"%s\n' "$name" "$sclock" "$sec" "$sclock" "$extra" >> "$tmp/sum-steps.txt"
  done
}
mk_sum
echo 1794038400 > "$sclock"
saved_clock=$NIGHTMILL_CLOCK_FILE
export NIGHTMILL_CLOCK_FILE="$sclock"
run_check "$tmp/sum-steps.txt" --jobs 1
plain_out=$out; plain_rc=$rc
echo 1794038400 > "$sclock"
rm -f "$tmp/summary.md"
run_check "$tmp/sum-steps.txt" --jobs 1 --summary "$tmp/summary.md"
[ "$rc" = 1 ] || fail "summary: exit $rc, wanted 1 (e fails): $out"
[ "$plain_rc" = 1 ] || fail "summary: the run without --summary exited $plain_rc"
[ "$out" = "$plain_out" ] || fail "summary: the standard output differs from a run without --summary: [$out] vs [$plain_out]"
[ -f "$tmp/summary.md" ] || fail "summary: no summary file was written"
want=$(printf '%s\n' '### tests/check.sh' '' 'Wall time: 1m25s for 6 steps, 1 at a time: FAILED' '' '| Slowest step | Time |' '|---|---|' \
  '| `b` | 30s |' '| `d` | 30s |' '| `e` | 12s |' '| `f` | 7s |' '| `a` | 5s |' '')
got=$(cat "$tmp/summary.md"; printf x)
[ "$got" = "$want"$'\n\n'x ] || fail "summary: the summary file is not as wanted; got: [${got%x}] wanted: [$want]"
# the summary comes before the verdict line, and the verdict is unchanged
[ "$(tail -n 1 <<<"$out")" = "CHECK FAILED: e" ] || fail "summary: the last line: $out"
# a passing run appends a second section: the file is appended to, not replaced
printf 'x\ttrue\ny\ttrue\n' > "$tmp/sum2.txt"
rm -f "$tmp/summary2.md"
run_check "$tmp/sum2.txt" --jobs 1 --summary "$tmp/summary2.md"
[ "$rc" = 0 ] || fail "summary twice: exit $rc: $out"
run_check "$tmp/sum2.txt" --jobs 1 --summary "$tmp/summary2.md"
[ "$rc" = 0 ] || fail "summary twice: the second run exit $rc: $out"
[ "$(grep -c '^### tests/check.sh$' "$tmp/summary2.md")" = 2 ] || fail "summary twice: not two sections: $(cat "$tmp/summary2.md")"
[ "$(grep -c '^Wall time: 0s for 2 steps, 1 at a time: passed$' "$tmp/summary2.md")" = 2 ] || fail "summary twice: the wall time lines: $(cat "$tmp/summary2.md")"
# usage errors
for sargs in "--summary $tmp/s1.md --summary $tmp/s2.md" "--summary"; do
  # shellcheck disable=SC2086
  run_check "$tmp/sum2.txt" $sargs
  [ "$rc" = 2 ] || fail "summary usage ($sargs): exit $rc: $out"
  grep -qxF -- "$USAGE" <<<"$err" || fail "summary usage ($sargs): no usage line: $err"
done
run_check "$tmp/sum2.txt" --summary ""
[ "$rc" = 2 ] || fail "summary usage (empty value): exit $rc: $out"
grep -qxF -- "$USAGE" <<<"$err" || fail "summary usage (empty value): no usage line: $err"
# a file that cannot be written: the note, and the exit code of the steps
mkdir -p "$tmp/sumdir"
echo 1794038400 > "$sclock"
run_check "$tmp/sum-steps.txt" --jobs 1 --summary "$tmp/sumdir"
[ "$rc" = 1 ] || fail "summary to a directory: exit $rc, wanted 1: $out"
grep -qxF "check: cannot write the summary to $tmp/sumdir" <<<"$err" || fail "summary to a directory: no 'cannot write' line: $err"
[ "$(tail -n 1 <<<"$out")" = "CHECK FAILED: e" ] || fail "summary to a directory: the last line: $out"
export NIGHTMILL_CLOCK_FILE=$saved_clock

echo "== the slowest steps of the real list start first"
# The real step list of tests/check.sh (between '# steps: begin' and '# steps: end'): the steps measured slowest in CI
# (issue 279) carry the 'first' mark. Only these are pinned; more steps may be marked later.
real_list=$(awk '/^# steps: begin$/{on=1;next} /^# steps: end$/{on=0} on' "$here/tests/check.sh")
# a step marked slow (iteration 62) ends in ' slow' after its 'first': the mark is removed before the whole-line match
real_first=$(sed 's/ slow$//' <<<"$real_list")
for want in "bash test-spec-template.sh" "bash smoke-slot.sh" "ps smoke-slot.ps1" "ps smoke-check.ps1" "ps smoke-validate.ps1" \
            "ps smoke-release.ps1" "ps smoke-drive.ps1" "ps test-lintcopy-output.ps1"; do
  has_line "$real_first" "add $want first" || fail "slowest steps: 'add $want first' is not in the step list of tests/check.sh"
done
# the slow steps are marked in the step list itself (iteration 62, decision 4)
for want in "ps smoke-drive.ps1 first slow" "ps test-lintcopy-output.ps1 first slow" "bash test-lintcopy-output.sh slow"; do
  has_line "$real_list" "add $want" || fail "slow steps: 'add $want' is not in the step list of tests/check.sh"
done

echo "== the lint: the check runs every smoke script"
# The section of tests/lint.sh is run alone on scratch copies of the files it reads, each broken once.
sec="$tmp/lint-section.sh"
awk '/^echo "== the check runs every smoke script"/ { p = 1 } /^echo "== text from issues is data"/ { p = 0 } p' "$here/tests/lint.sh" > "$sec"
[ -s "$sec" ] || fail "lint: tests/lint.sh has no section '== the check runs every smoke script'"
mkcopy() { # mkcopy <dir>: the files the section reads (every script in tests/, so a step that is not a smoke-* file exists)
  local d=$1
  mkdir -p "$d/tests" "$d/.github/workflows" "$d/schema" "$d/templates" "$d/scripts"
  cp "$here"/tests/*.sh "$here"/tests/*.ps1 "$d/tests/"
  cp "$here/.github/workflows/ci.yml" "$d/.github/workflows/"
  cp "$here/schema/nightmill.schema.json" "$d/schema/"
  cp "$here/templates/nightmill.example.json" "$d/templates/"
  cp "$here"/scripts/*.sh "$here"/scripts/*.ps1 "$d/scripts/"
  cp -R "$here/scripts/lib" "$d/scripts/lib"
  cp "$here/README.md" "$here/CONTRIBUTING.md" "$d/"
  cp -R "$here/skills" "$d/skills"
}
lint_in() { # lint_in <dir>: output and exit code of the section in <dir>
  # NIGHTMILL_CI_PARTS_RULES_ONLY: the copy checks the rules of tests/test-ci-parts.sh, its cases run once in the lint (#293)
  { printf 'set -euo pipefail\ncd "%s"\nfail=0\nexport NIGHTMILL_CI_PARTS_RULES_ONLY=1\n. scripts/lib/json.sh\n' "$1"; cat "$sec"; printf 'exit $fail\n'; } > "$tmp/run-section.sh"
  set +e; out=$(bash "$tmp/run-section.sh" 2>&1); rc=$?; set -e
}
lint_break() { # lint_break <name> <file> <sed expression> <expected text>
  local d="$tmp/lint-$1"
  mkcopy "$d"
  sed -e "$3" "$d/$2" > "$d/$2.new"; mv "$d/$2.new" "$d/$2"
  lint_in "$d"
  [ "$rc" != 0 ] || fail "lint $1: passed on a broken copy: $out"
  grep -qF -- "$4" <<<"$out" || fail "lint $1: no '$4' in: $out"
  rm -rf "$d"
}
mkcopy "$tmp/lint-ok"
lint_in "$tmp/lint-ok"
[ "$rc" = 0 ] || fail "lint: the section fails on the repository as it is: $out"
if grep -q 'FAIL' <<<"$out"; then fail "lint: FAIL on the repository as it is: $out"; fi
rm -rf "$tmp/lint-ok"
lint_break missing tests/check.sh '/^add bash smoke-hook\.sh/d' 'FAIL: tests/check.sh does not run tests/smoke-hook.sh'
lint_break twice tests/check.sh '/^add bash smoke-hook\.sh/p' 'FAIL: tests/check.sh runs tests/smoke-hook.sh more than once'
lint_break nofile tests/check.sh 's/^# steps: end/add bash smoke-nope.sh\
# steps: end/' 'FAIL: tests/check.sh runs tests/smoke-nope.sh, which does not exist'
lint_break twopassed tests/check.sh '$a\
echo "ALL CHECKS PASSED"' 'FAIL: tests/check.sh prints ALL CHECKS PASSED in more than one place'
lint_break cibash .github/workflows/ci.yml '/run: bash tests\/check\.sh --summary/s/smoke-hook\.sh,//' 'FAIL: .github/workflows/ci.yml does not run tests/smoke-hook.sh'
lint_break cips .github/workflows/ci.yml '/^ *only: smoke-hook\.ps1,/s/smoke-hook\.ps1,//' 'FAIL: .github/workflows/ci.yml: tests/smoke-hook.ps1 runs in no PowerShell part'
lint_break cijson .github/workflows/ci.yml '/run: bash tests\/check\.sh --summary.*smoke-hook\.sh/s/\$CHECK_SELECT /\$CHECK_SELECT smoke-json.sh,/' 'FAIL: .github/workflows/ci.yml: tests/smoke-json.sh is not a step of its job or is named twice'
lint_break ciswap .github/workflows/ci.yml '/run: bash tests\/check\.sh --summary/s/smoke-hook\.sh,smoke-release\.sh/smoke-release.sh,smoke-hook.sh/' 'FAIL: .github/workflows/ci.yml: the --only list is not in the order of the step list'
lint_break cidirect .github/workflows/ci.yml '$a\
\      - run: bash tests/smoke-render.sh' 'FAIL: .github/workflows/ci.yml runs tests/smoke-render.sh outside tests/check.sh'
lint_break cirename .github/workflows/ci.yml 's/name: bash scripts smoke tests/name: bash scripts smoke/' 'the required job bash scripts smoke tests is missing'
lint_break cibegins .github/workflows/ci.yml 's/name: claude plugin validate (not blocking)/name: PowerShell scripts smoke tests (1)/' "FAIL: .github/workflows/ci.yml: the job name 'PowerShell scripts smoke tests (1)' begins with the required name 'PowerShell scripts smoke tests'"
# CI selects the steps a pull request affects, and every required job runs on every event (iteration 60, decision 8)
lint_break cienv .github/workflows/ci.yml $'/CHECK_SELECT:/s/\'--only\'/\'--quick\'/' 'FAIL: .github/workflows/ci.yml: the env block is not exactly the line'
lint_break cipaths .github/workflows/ci.yml $'/^  pull_request:$/a\\\n\\    paths-ignore: [\'docs/**\']' "FAIL: .github/workflows/ci.yml: the 'on:' block is not exactly push to main and pull_request"
lint_break ciif .github/workflows/ci.yml $'/^    name: Lint (generic, JSON, skills, shell)$/a\\\n\\    if: github.event_name == \'push\'' "job lint has an 'if:'"
lint_break cidepth .github/workflows/ci.yml '/^  smoke-bash:$/,/^  smoke-powershell-part:$/{/fetch-depth: 0/d;}' 'job smoke-bash does not check out with fetch-depth: 0'
lint_break cijsondirect .github/workflows/ci.yml '/\$CHECK_SELECT smoke-json\.sh$/s/run: .*/run: bash tests\/smoke-json.sh/' 'the bash smoke job does not run tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT smoke-json.sh, then the other bash steps'
# verification.platform is wired in the schema, the example, the README, the init skill and the check (iteration 56, decision 10)
lint_break platformschema schema/nightmill.schema.json 's/"platform"/"platformx"/g' 'FAIL: schema: verification.platform is not a string'
lint_break platformexample templates/nightmill.example.json 's/"platform": "all"/"platform": "unix"/' 'FAIL: templates/nightmill.example.json does not mention verification.platform all'
lint_break platformreadme README.md 's/verification\.platform/verification-platform/g' 'FAIL: README.md does not mention verification.platform'
lint_break platforminit skills/init/SKILL.md 's/verification\.platform/verification-platform/g' 'FAIL: skills/init/SKILL.md does not mention verification.platform'
lint_break platformcheck tests/check.sh 's/verification\.platform/verification-platform/g' 'FAIL: tests/check.sh does not mention verification.platform'
# the map of tests/check.sh (iteration 59, decision 7): every test step and every script is in it
lint_break mapstep tests/check.sh '/^map [^ ]* smoke-hook\.sh$/d; /^map /{s/,smoke-hook\.sh,/,/; s/,smoke-hook\.sh$//; s/ smoke-hook\.sh,/ /;}' 'no path maps to the step smoke-hook.sh'
d="$tmp/lint-mapscript"
mkcopy "$d"
: > "$d/scripts/zz-new.sh"
lint_in "$d"
[ "$rc" != 0 ] || fail "lint mapscript: passed on a broken copy: $out"
grep -qF -- 'scripts/zz-new.sh maps to no step' <<<"$out" || fail "lint mapscript: no 'scripts/zz-new.sh maps to no step' in: $out"
rm -rf "$d"
lint_break mapname tests/check.sh 's/^# affects: end$/map README.md smoke-nope.sh\
# affects: end/' 'the map names smoke-nope.sh, which is not a step'
lint_break maptwin tests/check.sh 's/^# affects: end$/map scripts\/slot.sh smoke-hook.sh\
# affects: end/' 'scripts/slot.sh and scripts/slot.ps1 map to different steps'
lint_break mapshared tests/check.sh '/^shared scripts\/lib\/\*$/d' 'the map does not have the line shared scripts/lib/*'
lint_break cimapci tests/check.sh '/^shared \.github\/workflows\/\*$/d' 'the map does not have the line shared .github/workflows/*'
lint_break mapskill skills/check/SKILL.md 's/check: AFFECTED/check: AFFECTEX/g' 'skills/check/SKILL.md does not mention check: AFFECTED'
# the slow mark (iteration 62, decision 8): its format, the set of slow steps, the '# Time: ' notes and the release line of the map
lint_break slowformat tests/check.sh 's/^add ps smoke-drive\.ps1 first slow$/add ps smoke-drive.ps1 slow first/' "the step list between '# steps: begin' and '# steps: end' is missing or malformed"
lint_break slowset tests/check.sh 's/^\(add ps smoke-drive\.ps1 first\) slow$/\1/' 'the steps marked slow are not exactly the slow steps'
lint_break slownote tests/smoke-drive.ps1 '/^# Time: /d' "tests/smoke-drive.ps1 has no '# Time: ' note in its header"
lint_break mapplugin tests/check.sh '/^shared \.claude-plugin\/plugin\.json$/d' 'the map does not have the line shared .claude-plugin/plugin.json'

echo "smoke-check: ok"
