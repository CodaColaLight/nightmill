#!/usr/bin/env bash
# tests/smoke-control.sh - control.sh against fixtures of readings (NIGHTMILL_LOAD_FIXTURE is set in every call that
# measures, so the real measurement never runs) and a fixed clock (NIGHTMILL_NOW), in a throwaway repository whose slot
# markers and capacity.json are written by hand. The cases 1 to 14 are those of "Tests" in
# docs/specs/iteration-30-load-controller.md; smoke-control.ps1 runs the same cases. Needs bash and awk, no jq.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
C="$here/scripts/control.sh"
unset WORKER_SLOTS NIGHTMILL_LOAD_FIXTURE NIGHTMILL_NOW
TAB=$'\t'
B=1793966400 # 2026-11-06T12:00:00 read as UTC

fail() { echo "FAIL: $*" >&2; exit 1; }

# The project: two slots under ../wt, the controller in apply mode unless a case says otherwise.
work="$tmp/work"
git init -q -b main "$work"
mkdir -p "$work/.claude" "$tmp/wt/.slots" "$tmp/fx"
cfg="$work/.claude/nightmill.json"
slots="$tmp/wt/.slots"
capf="$slots/capacity.json"
base_cfg='{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "worktrees": { "root": "../wt", "slots": 2 }
}'
# set_parallel <json members>: the config with a parallel object
set_parallel() { printf '%s\n' "$base_cfg" | sed "s|\"worktrees\"|\"parallel\": { $1 }, \"worktrees\"|" > "$cfg"; }
apply_cfg() { set_parallel "\"controlMode\": \"apply\"${1:+, $1}"; }
report_cfg() { set_parallel "\"controlMode\": \"report\"${1:+, $1}"; }
apply_cfg
mkdir "$tmp/plain" && git init -q -b main "$tmp/plain"
mkdir "$tmp/outside"
git_before=$(git -C "$work" status --porcelain --untracked-files=all)

marker() { printf '{\n  "slot": %s,\n  "branch": "feat/s%s",\n  "since": "2026-11-05T10:00:00"\n}\n' "$1" "$1" > "$slots/slot-$1.json"; }
markers_snap=""
busy() { # busy <n>: slots 1..n busy, the rest free
  rm -f "$slots"/slot-*.json
  local i
  for ((i = 1; i <= $1; i++)); do marker "$i"; done
  markers_snap=$(cat "$slots"/slot-*.json 2>/dev/null || true)
}
cap() { # cap <agents> <slots> [since, or - for none]: capacity.json written by hand
  local since="${3:-2026-11-06T12:00:00}"
  if [ "$since" = "-" ]; then
    printf '{\n  "slots": %s,\n  "maxAgents": %s\n}\n' "$2" "$1" > "$capf"
  else
    printf '{\n  "slots": %s,\n  "maxAgents": %s,\n  "since": "%s"\n}\n' "$2" "$1" "$since" > "$capf"
  fi
}
nocap() { rm -f "$capf"; }
cap_text() { if [ -f "$capf" ]; then cat "$capf"; else echo "absent"; fi; }
snap() { cap_snap=$(cap_text); }
cap_same() { [ "$(cap_text)" = "$cap_snap" ] || { cap_text; fail "$1: capacity.json changed"; }; }
cap_has() { grep -qF -- "\"$2\": $3," "$capf" || { cap_text; fail "$1: capacity.json has no $2 $3"; }; }
fixture() { # fixture <name> <line>...
  local name=$1
  shift
  printf '%s\n' "$@" > "$tmp/fx/$name"
}
same() { fixture "$1" "$2 $3 $4" "$2 $3 $4" "$2 $3 $4"; }

# the slot markers and the files under .slots are what the test wrote
check_slots() {
  [ "$(cat "$slots"/slot-*.json 2>/dev/null || true)" = "$markers_snap" ] || fail "$1: a slot marker changed"
  local f
  for f in "$slots"/* "$slots"/.[!.]*; do
    [ -e "$f" ] || continue
    case "${f##*/}" in
      capacity.json) ;;
      slot-[0-9]*.json) ;;
      *) fail "$1: .slots holds another file: ${f##*/}" ;;
    esac
  done
}

run_in() { # run_in <dir> <now or -> <fixture> [args]: the output in out.txt and err.txt, the exit code in $code
  local dir=$1 now=$2 fx=$3 before
  shift 3
  before=$(cat "$cfg")
  set +e
  (
    cd "$dir" || exit 99
    if [ "$now" != "-" ]; then export NIGHTMILL_NOW="$now"; fi
    NIGHTMILL_LOAD_FIXTURE="$tmp/fx/$fx" bash "$C" "$@"
  ) > "$tmp/out.txt" 2> "$tmp/err.txt"
  code=$?
  set -e
  [ "$(cat "$cfg")" = "$before" ] || fail "the config changed"
  check_slots "run"
}
run() { run_in "$work" "$@"; }

expect_out() { # expect_out <name> <expected text>
  if [ "$(cat "$tmp/out.txt")" != "$2" ]; then
    echo "--- expected"; printf '%s\n' "$2"; echo "--- got"; cat "$tmp/out.txt"; echo "--- stderr"; cat "$tmp/err.txt"
    fail "$1: the output differs"
  fi
}
first_is() { # first_is <name> <line>: the first line of the output
  if [ "$(head -n 1 "$tmp/out.txt")" != "$2" ]; then
    echo "--- expected"; printf '%s\n' "$2"; echo "--- got"; cat "$tmp/out.txt"; echo "--- stderr"; cat "$tmp/err.txt"
    fail "$1: the first line differs"
  fi
}
has_err() { grep -qxF -- "$2" "$tmp/err.txt" || { cat "$tmp/err.txt"; fail "$1: standard error has no line '$2'"; }; }
code_is() { [ "$code" = "$2" ] || { cat "$tmp/out.txt" "$tmp/err.txt"; fail "$1: exit code $code, expected $2"; }; }
no_err() { [ ! -s "$tmp/err.txt" ] || { cat "$tmp/err.txt"; fail "$1: something on standard error"; }; }
no_out() { [ ! -s "$tmp/out.txt" ] || { cat "$tmp/out.txt"; fail "$1: something on standard output"; }; }
err_lines() { [ "$(grep -c . "$tmp/err.txt" || true)" = "$2" ] || { cat "$tmp/err.txt"; fail "$1: not $2 line(s) on standard error"; }; }

# the fixtures
fixture roomy "5 61000 64000" "10 60000 64000" "15 62000 64000"
same steady 20 9000 16000
same short 30 1000 16000
same cpu-high 90 50000 64000
fixture cpu-gone "5 61000 64000" "- 60000 64000" "15 62000 64000"
fixture mem-gone "5 - 64000" "10 60000 64000" "15 62000 64000"
fixture all-gone "5 - 64000" "- 60000 64000" "15 62000 64000"
fixture one "10 60000 64000"

NEXT="control: next pass in 5 min (parallel.controlIntervalMinutes)"
OFF="control: off (parallel.controlMode is off); nothing measured or changed"
M_ROOMY="CPU 10%, free memory 60000 of 64000 MB, busy slots 1, suggested 4: the ceiling is the limit (parallel.maxSuggestedAgents = 4); CPU and memory have room for more"
M_STEADY="CPU 20%, free memory 9000 of 16000 MB, busy slots 1, suggested 2: memory is the limit: 16000 MB in all holds 2 agents at 8 GB each"
M_SHORT="CPU 30%, free memory 1000 of 16000 MB, busy slots 2, suggested 1: memory is short: 1000 MB free is under 10% of 16000 MB, one agent fewer than the 2 in the slots"
M_CPU="CPU 90%, free memory 50000 of 64000 MB, busy slots 2, suggested 1: CPU is the limit: 90% busy with 2 agents in the slots, aiming at 80%"

echo "== 1. off by default"
busy 0
printf '%s\n' "$base_cfg" > "$cfg"
run - missing
code_is "no parallel" 0
expect_out "no parallel" "$OFF"
no_err "no parallel"
set_parallel '"maxAgents": 2'
run - missing
code_is "no controlMode" 0
expect_out "no controlMode" "$OFF"
no_err "no controlMode"
set_parallel '"controlMode": "off"'
run - missing
code_is "off" 0
expect_out "off" "$OFF"
no_err "off"
# no slot script ran: a worktrees root that does not exist is still not there
off="$tmp/offrepo"
git init -q -b main "$off"
mkdir "$off/.claude"
printf '%s\n' "$base_cfg" | sed 's|"\.\./wt"|"../offwt"|' > "$off/.claude/nightmill.json"
run_in "$off" - missing
code_is "off, no root" 0
expect_out "off, no root" "$OFF"
[ ! -e "$tmp/offwt" ] || fail "off: the worktrees root was created"
apply_cfg

echo "== 2. raise one step, the slot count keeps up"
busy 1
nocap
run - roomy
code_is "raise" 0
expect_out "raise" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)
$NEXT"
(cd "$work" && bash "$here/scripts/slot.sh" --capacity --porcelain) > "$tmp/cap.txt"
grep -qxF "slots${TAB}3${TAB}live${TAB}2" "$tmp/cap.txt" || { cat "$tmp/cap.txt"; fail "raise: slots not 3 live"; }
grep -qxF "agents${TAB}3${TAB}live${TAB}2" "$tmp/cap.txt" || { cat "$tmp/cap.txt"; fail "raise: agents not 3 live"; }

echo "== 3. hold in the cooldown"
snap
run - roomy
code_is "right after" 0
expect_out "right after" "control: agent limit 3 kept (cooldown 15 of 15 min left; $M_ROOMY)
$NEXT"
cap_same "right after"
cap 2 2
snap
run $((B + 60)) roomy
first_is "B+60" "control: agent limit 2 kept (cooldown 14 of 15 min left; $M_ROOMY)"
cap_same "B+60"
run $((B + 899)) roomy
first_is "B+899" "control: agent limit 2 kept (cooldown 1 of 15 min left; $M_ROOMY)"
run $((B - 60)) roomy
first_is "since in the future" "control: agent limit 2 kept (cooldown 15 of 15 min left; $M_ROOMY)"
cap_same "since in the future"
run $((B + 900)) roomy
code_is "B+900" 0
first_is "B+900" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"
cap 2 2
run $((B + 3600)) roomy
first_is "one step per pass" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"
cap_has "one step per pass" maxAgents 3
apply_cfg '"controlCooldownMinutes": 1'
cap 2 2
run $((B + 60)) roomy
first_is "cooldown 1 min" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"
apply_cfg

echo "== 4. lower at once when memory is short"
busy 2
cap 3 3
run $((B + 60)) short
code_is "memory short" 0
expect_out "memory short" "control: agent limit 3 -> 1 (memory; $M_SHORT)
$NEXT"
cap_has "memory short" slots 3
cap_has "memory short" maxAgents 1
busy 1
cap 3 3
run $((B + 60)) steady
first_is "memory total" "control: agent limit 3 -> 2 (memory; $M_STEADY)"

echo "== 5. lower slowly for the CPU"
busy 2
cap 3 3
snap
run $((B + 60)) cpu-high
code_is "cpu in the cooldown" 0
first_is "cpu in the cooldown" "control: agent limit 3 kept (cooldown 14 of 15 min left; $M_CPU)"
cap_same "cpu in the cooldown"
run $((B + 900)) cpu-high
first_is "cpu after the cooldown" "control: agent limit 3 -> 2 (cpu; $M_CPU)"
cap_has "cpu after the cooldown" maxAgents 2
busy 1
apply_cfg '"controlMaxAgents": 6'
cap 5 5
run $((B + 3600)) roomy
first_is "ceiling" "control: agent limit 5 -> 4 (ceiling; $M_ROOMY)"
apply_cfg

echo "== 6. bounds"
apply_cfg '"controlMaxAgents": 3'
cap 3 3
snap
run $((B + 3600)) roomy
first_is "at the maximum" "control: agent limit 3 kept (at the maximum; $M_ROOMY)"
cap_same "at the maximum"
apply_cfg
cap 5 5
run $((B + 60)) steady
first_is "above the maximum, memory" "control: agent limit 5 -> 2 (memory; $M_STEADY)"
cap 5 5
run $((B + 60)) roomy
first_is "above the maximum" "control: agent limit 5 -> 4 (maximum; $M_ROOMY)"
cap_has "above the maximum" slots 5
apply_cfg '"controlMinAgents": 2'
busy 2
cap 3 3
run $((B + 60)) short
first_is "memory to the minimum" "control: agent limit 3 -> 2 (memory; $M_SHORT)"
cap 2 3
snap
run $((B + 60)) short
first_is "at the minimum" "control: agent limit 2 kept (at the minimum; $M_SHORT)"
cap_same "at the minimum"
busy 1
cap 1 1
run $((B + 60)) steady
first_is "below the minimum" "control: agent limit 1 -> 2, slots 1 -> 2 (minimum; $M_STEADY)"
apply_cfg '"controlMinAgents": 5, "controlMaxAgents": 3'
nocap
run - roomy
code_is "minimum above maximum" 0
has_err "minimum above maximum" "control: parallel.controlMinAgents 5 is above parallel.controlMaxAgents 3; using 3 for both"
first_is "minimum above maximum" "control: agent limit 2 -> 3, slots 2 -> 3 (minimum; $M_ROOMY)"
apply_cfg

echo "== 7. steady, and the slot count is raised only by a new limit above it"
busy 1
nocap
run - steady
code_is "steady" 0
expect_out "steady" "control: agent limit 2 kept (steady; $M_STEADY)
$NEXT"
[ ! -e "$capf" ] || fail "steady: capacity.json was created"
cap 2 1
snap
run $((B + 3600)) steady
first_is "kept with L > S" "control: agent limit 2 kept (steady; $M_STEADY)"
cap_same "kept with L > S"
cap 3 2
snap
run $((B + 60)) roomy
first_is "cooldown with L > S" "control: agent limit 3 kept (cooldown 14 of 15 min left; $M_ROOMY)"
cap_same "cooldown with L > S"
cap 2 1
run $((B + 3600)) roomy
first_is "raise above S" "control: agent limit 2 -> 3, slots 1 -> 3 (room; $M_ROOMY)"
cap_has "raise above S" slots 3
cap_has "raise above S" maxAgents 3
cap 2 3
run $((B + 3600)) roomy
first_is "raise within S" "control: agent limit 2 -> 3 (room; $M_ROOMY)"
cap_has "raise within S" slots 3
busy 2
cap 3 2
run $((B + 60)) short
first_is "lower below S" "control: agent limit 3 -> 1 (memory; $M_SHORT)"
cap_has "lower below S" slots 2
busy 4
cap 5 2
run $((B + 60)) short
first_is "lower, still above S" "control: agent limit 5 -> 3, slots 2 -> 3 (memory; CPU 30%, free memory 1000 of 16000 MB, busy slots 4, suggested 3: memory is short: 1000 MB free is under 10% of 16000 MB, one agent fewer than the 4 in the slots)"
cap_has "lower, still above S" slots 3
cap_has "lower, still above S" maxAgents 3

echo "== 8. a pass that cannot measure changes nothing and says so"
busy 1
nocap
run - cpu-gone
code_is "cpu gone" 1
expect_out "cpu gone" "control: agent limit 2 kept (unavailable; the CPU load is unavailable (sample 2 has no CPU reading))
$NEXT"
[ ! -e "$capf" ] || fail "cpu gone: capacity.json was created"
run - mem-gone
code_is "memory gone" 1
first_is "memory gone" "control: agent limit 2 kept (unavailable; the free memory is unavailable (sample 1 has no memory reading))"
run - all-gone
code_is "both gone" 1
first_is "both gone" "control: agent limit 2 kept (unavailable; the CPU load (sample 2 has no CPU reading) and the free memory (sample 1 has no memory reading) are unavailable)"
cap 6 6
snap
run $((B + 60)) cpu-gone
code_is "above the maximum, unavailable" 1
first_is "above the maximum, unavailable" "control: agent limit 6 kept (unavailable; the CPU load is unavailable (sample 2 has no CPU reading))"
cap_same "above the maximum, unavailable"

echo "== 9. report only decides the same and changes nothing"
# report_same <name> <extra members> <busy> <cap agents|-> <cap slots> <now|-> <fixture>: the apply pass and the report
# pass from the same state give the same exit code and the same lines but the prefix; report leaves capacity.json
report_state() { busy "$1"; if [ "$2" = "-" ]; then nocap; else cap "$2" "$3"; fi; }
report_same() {
  local name=$1 extra=$2 nb=$3 ca=$4 cs=$5 now=$6 fx=$7 acode aout want
  apply_cfg "$extra"
  report_state "$nb" "$ca" "$cs"
  run "$now" "$fx"
  acode=$code; aout=$(cat "$tmp/out.txt")
  report_state "$nb" "$ca" "$cs"
  snap
  report_cfg "$extra"
  run "$now" "$fx"
  code_is "report $name" "$acode"
  want="control (report only, nothing changed): ${aout#control: }"
  expect_out "report $name" "$want"
  cap_same "report $name"
  [ "$(sed -n 2p "$tmp/out.txt")" = "$NEXT" ] || fail "report $name: no next-pass line"
  apply_cfg
}
report_same "raise" "" 1 - - - roomy
report_same "memory" "" 2 3 3 $((B + 60)) short
report_same "cpu" "" 2 3 3 $((B + 900)) cpu-high
report_same "maximum" "" 1 5 5 $((B + 60)) roomy
report_same "minimum" '"controlMinAgents": 2' 1 1 1 $((B + 60)) steady
report_same "unavailable" "" 1 - - - cpu-gone
report_cfg
busy 1
nocap
run - roomy
first_is "report line" "control (report only, nothing changed): agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"
apply_cfg

echo "== 10. the last change unknown"
busy 1
cap 2 2 -
run $((B + 60)) roomy
first_is "no since" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"
cap 2 2 yesterday
run $((B + 60)) roomy
first_is "since yesterday" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"
printf 'not json\n' > "$capf"
run $((B + 60)) roomy
code_is "not JSON" 0
has_err "not JSON" "slot: capacity.json: not valid JSON; using the configuration"
first_is "not JSON" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"

echo "== 11. the interval"
apply_cfg '"controlIntervalMinutes": 10'
nocap
run - steady
expect_out "interval" "control: agent limit 2 kept (steady; $M_STEADY)
control: next pass in 10 min (parallel.controlIntervalMinutes)"
apply_cfg

echo "== 12. unusable config values fall back"
busy 1
nocap
for v in '"Apply"' '"on"' 1 true; do
  set_parallel "\"controlMode\": $v"
  run - steady
  code_is "controlMode $v" 0
  has_err "controlMode $v" 'control: parallel.controlMode must be "off", "report" or "apply"; using "off"'
  err_lines "controlMode $v" 1
  expect_out "controlMode $v" "$OFF"
done
# bad_value <key> <value> <default> <high>
bad_value() {
  apply_cfg "\"$1\": $2"
  run - steady
  code_is "$1 = $2" 0
  has_err "$1 = $2" "control: parallel.$1 must be a whole number from 1 to $4; using $3"
  err_lines "$1 = $2" 1
  expect_out "$1 = $2" "control: agent limit 2 kept (steady; $M_STEADY)
$NEXT"
}
for v in 0 100; do
  bad_value controlMinAgents "$v" 1 99
  bad_value controlMaxAgents "$v" 4 99
done
for v in 0 1441 1.5 '"15"'; do bad_value controlCooldownMinutes "$v" 15 1440; done
for v in 0 1441 '"5"'; do bad_value controlIntervalMinutes "$v" 5 1440; done
apply_cfg '"controlCooldownMinutes": 0'
cap 2 2
run $((B + 60)) roomy
first_is "cooldown default" "control: agent limit 2 kept (cooldown 14 of 15 min left; $M_ROOMY)"
nocap
apply_cfg '"controlMinAgents": null, "controlMaxAgents": null, "controlCooldownMinutes": null, "controlIntervalMinutes": null'
run - steady
code_is "null values" 0
no_err "null values"
set_parallel '"controlMode": null'
run - steady
no_err "null mode"
expect_out "null mode" "$OFF"
apply_cfg
run - steady
no_err "absent keys"

echo "== 13. errors"
cap 2 2
snap
run - roomy --apply
code_is "--apply" 2
has_err "--apply" "usage: control.sh"
run - roomy -h
code_is "-h" 2
has_err "-h" "usage: control.sh"
set +e
(cd "$tmp/outside" && GIT_CEILING_DIRECTORIES="$tmp" NIGHTMILL_LOAD_FIXTURE="$tmp/fx/roomy" bash "$C") > "$tmp/out.txt" 2> "$tmp/err.txt"
code=$?
set -e
code_is "outside a checkout" 2
has_err "outside a checkout" "control: run control.sh from inside a checkout of the project"
run_in "$tmp/plain" - roomy
code_is "no config" 2
grep -qF 'run /nightmill:init' "$tmp/err.txt" || fail "no config: the message does not say run /nightmill:init"
run - missing
code_is "missing fixture" 2
no_out "missing fixture"
has_err "missing fixture" "load: cannot read NIGHTMILL_LOAD_FIXTURE: $tmp/fx/missing"
run - one
code_is "one sample" 2
no_out "one sample"
has_err "one sample" "load: NIGHTMILL_LOAD_FIXTURE needs at least 2 samples"
set +e
(cd "$work" && WORKER_SLOTS=x NIGHTMILL_LOAD_FIXTURE="$tmp/fx/roomy" bash "$C") > "$tmp/out.txt" 2> "$tmp/err.txt"
code=$?
set -e
code_is "WORKER_SLOTS" 2
no_out "WORKER_SLOTS"
has_err "WORKER_SLOTS" "control: slot.sh failed: WORKER_SLOTS must be a number from 1 to 99"
cap_same "errors"

echo "== 14. nothing else is changed"
check_slots "at the end"
[ "$(git -C "$work" status --porcelain --untracked-files=all)" = "$git_before" ] || fail "the throwaway repository's git status changed"

echo "CONTROL OK"
