#!/usr/bin/env bash
# tests/smoke-check.sh - the parallel check and its quick mode (iteration 42): tests/check.sh against fixture steps
# (NIGHTMILL_CHECK_STEPS, lines <name> TAB <command> [TAB <kind> [TAB <reason>]]), the order and the verdict, the
# limit of 1, the quick mode, --only and the usage errors, the limit from the config, two checks at once, and the
# lint section that keeps the check's step list and CI in step. NIGHTMILL_CLOCK_FILE holds one fixed time, so every
# duration is 0s. Same cases and same expected text as tests/smoke-check.ps1. Needs bash, git and awk, no jq.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset UPDATE_STATUS_FIXTURES UPDATE_DASHBOARD_FIXTURES UPDATE_PANEL_FIXTURES NIGHTMILL_CHECK_STEPS
echo 1794038400 > "$tmp/clock"
export NIGHTMILL_CLOCK_FILE="$tmp/clock"
USAGE='usage: tests/check.sh [--quick | --only <step>[,<step>...]] [--jobs <1-16>] [--powershell powershell|pwsh]'

fail() { echo "FAIL: $*" >&2; exit 1; }
# barrier <file-test>: a loop of at most 300 tries, 0.1 s apart, then exit 9
barrier() { printf 'i=0; until %s; do i=$((i+1)); [ $i -gt 300 ] && exit 9; sleep 0.1; done' "$1"; }
# run_check <steps-file> <args...>: out, err, rc of tests/check.sh in this checkout
run_check() {
  local steps=$1; shift
  set +e
  out=$(NIGHTMILL_CHECK_STEPS="$steps" bash "$here/tests/check.sh" "$@" 2>"$tmp/err.txt"); rc=$?
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
head -n 1 <<<"$out" | grep -qE '^check: QUICK, [0-9]+ at a time \(.+\): the lint and the bash smoke tests only; the full check does not run$' || fail "quick: the first line: $out"
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

echo "== two checks at once"
mkdir -p "$tmp/tmpA" "$tmp/tmpB"
for r in A B; do
  o=B; [ "$r" = B ] && o=A
  {
    printf 'run\techo "run %s"; touch "%s/started%s"; %s\n' "$r" "$tmp" "$r" "$(barrier "[ -f '$tmp/started$o' ]")"
    printf 'render\tbash tests/smoke-render.sh\n'
    printf 'hook\tbash tests/smoke-hook.sh\n'
  } > "$tmp/two$r.txt"
done
for r in A B; do
  ( TMPDIR="$tmp/tmp$r" NIGHTMILL_CHECK_STEPS="$tmp/two$r.txt" bash "$here/tests/check.sh" --jobs 2 > "$tmp/out$r.txt" 2>&1; echo $? > "$tmp/rc$r.txt" ) &
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

echo "== the lint: the check runs every smoke script"
# The section of tests/lint.sh is run alone on scratch copies of the files it reads, each broken once.
sec="$tmp/lint-section.sh"
awk '/^echo "== the check runs every smoke script"/ { p = 1 } /^echo "== text from issues is data"/ { p = 0 } p' "$here/tests/lint.sh" > "$sec"
[ -s "$sec" ] || fail "lint: tests/lint.sh has no section '== the check runs every smoke script'"
mkcopy() { # mkcopy <dir>: the files the section reads
  local d=$1
  mkdir -p "$d/tests" "$d/.github/workflows" "$d/schema" "$d/templates" "$d/scripts"
  cp "$here"/tests/check.sh "$here"/tests/check.ps1 "$here"/tests/smoke-* "$d/tests/"
  cp "$here/.github/workflows/ci.yml" "$d/.github/workflows/"
  cp "$here/schema/nightmill.schema.json" "$d/schema/"
  cp "$here/templates/nightmill.example.json" "$d/templates/"
  cp -R "$here/scripts/lib" "$d/scripts/lib"
  cp "$here/README.md" "$here/CONTRIBUTING.md" "$d/"
  cp -R "$here/skills" "$d/skills"
}
lint_in() { # lint_in <dir>: output and exit code of the section in <dir>
  { printf 'set -euo pipefail\ncd "%s"\nfail=0\n. scripts/lib/json.sh\n' "$1"; cat "$sec"; printf 'exit $fail\n'; } > "$tmp/run-section.sh"
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
lint_break cibash .github/workflows/ci.yml '/run: bash tests\/check\.sh --only/s/smoke-hook\.sh,//' 'FAIL: .github/workflows/ci.yml does not run tests/smoke-hook.sh'
lint_break cips .github/workflows/ci.yml '/--powershell powershell --only/s/smoke-hook\.ps1,//' 'FAIL: .github/workflows/ci.yml does not run tests/smoke-hook.ps1'
lint_break cijson .github/workflows/ci.yml '/run: bash tests\/check\.sh --only/s/--only /--only smoke-json.sh,/' 'FAIL: .github/workflows/ci.yml: tests/smoke-json.sh is not a step of its job or is named twice'
lint_break ciswap .github/workflows/ci.yml '/run: bash tests\/check\.sh --only/s/smoke-hook\.sh,smoke-release\.sh/smoke-release.sh,smoke-hook.sh/' 'FAIL: .github/workflows/ci.yml: the --only list is not in the order of the step list'
lint_break cidirect .github/workflows/ci.yml '$a\
\      - run: bash tests/smoke-render.sh' 'FAIL: .github/workflows/ci.yml runs tests/smoke-render.sh outside tests/check.sh'
lint_break cirename .github/workflows/ci.yml 's/name: bash scripts smoke tests/name: bash scripts smoke/' 'the required job bash scripts smoke tests is missing'

echo "smoke-check: ok"
