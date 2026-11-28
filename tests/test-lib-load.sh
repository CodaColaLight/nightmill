#!/usr/bin/env bash
# tests/test-lib-load.sh - scripts/lib/load.sh tested in-process (iteration 72, #346): it sources scripts/lib/json.sh and
# scripts/lib/load.sh and calls load_settings, room_settings, control_settings, load_measure (on a fixture) and
# load_suggest directly. No script is started, no git is run, no repository is made. The last section checks the wiring:
# the step and map lines of tests/check.sh and the comments in the smoke tests that name this file. Needs bash and awk.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-test-lib-load.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
unset NIGHTMILL_LOAD_FIXTURE

# shellcheck source=/dev/null
. "$here/scripts/lib/json.sh"
# shellcheck source=/dev/null
. "$here/scripts/lib/load.sh"

section=""
fail() { echo "FAIL: $section: $*" >&2; exit 1; }
heading() { section=$1; echo "== $1"; }

# cfg <members>: a config with a parallel object holding the members, loaded into JSON_FLAT
cfg() {
  printf '{ "parallel": { %s } }\n' "$1" > "$tmp/cfg.json"
  json_load "$tmp/cfg.json" || fail "the config does not load: $1"
}
# eq <name> <got> <expected>
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', expected '$3'"; }
# err_is <name> <expected text, or empty for nothing>: standard error of the last call is exactly that
err_is() {
  local got
  got=$(cat "$tmp/err.txt")
  [ "$got" = "$2" ] || fail "$1: standard error is '$got', expected '$2'"
}

heading "load settings"
cfg '"maxAgents": 2'
load_settings 2> "$tmp/err.txt"
eq "absent ceiling" "$LOAD_CEILING" 4
eq "absent gb" "$LOAD_GB" 8
eq "absent window" "$LOAD_WINDOW" 10
err_is "absent keys" ""
cfg '"maxSuggestedAgents": 6, "memoryPerAgentGB": 4, "loadWindowSeconds": 30'
load_settings 2> "$tmp/err.txt"
eq "ceiling taken" "$LOAD_CEILING" 6
eq "gb taken" "$LOAD_GB" 4
eq "window taken" "$LOAD_WINDOW" 30
err_is "in-range values" ""
# load_bad <key> <value> <default> <low> <high> <variable>
load_bad() {
  cfg "\"$1\": $2"
  load_settings 2> "$tmp/err.txt"
  err_is "$1 = $2" "load: parallel.$1 must be a whole number from $4 to $5; using $3"
  eq "$1 = $2" "${!6}" "$3"
}
for v in 0 -1 8.5 8.0 '"8"' true; do load_bad memoryPerAgentGB "$v" 8 1 1024 LOAD_GB; done
for v in 0 100; do load_bad maxSuggestedAgents "$v" 4 1 99 LOAD_CEILING; done
for v in 1 61; do load_bad loadWindowSeconds "$v" 10 2 60 LOAD_WINDOW; done
cfg '"memoryPerAgentGB": null, "maxSuggestedAgents": null, "loadWindowSeconds": null'
load_settings 2> "$tmp/err.txt"
eq "null ceiling" "$LOAD_CEILING" 4
eq "null gb" "$LOAD_GB" 8
eq "null window" "$LOAD_WINDOW" 10
err_is "null values" ""

heading "room settings"
# room_bad <key> <value> <default> <low> <high> <variable>
room_bad() {
  cfg "\"$1\": $2"
  room_settings 2> "$tmp/err.txt"
  err_is "$1 = $2" "room: parallel.$1 must be a whole number from $4 to $5; using $3"
  eq "$1 = $2" "${!6}" "$3"
}
for v in 0 -1 8.5 '"60"' true 91; do room_bad roomPauseSeconds "$v" 60 1 90 ROOM_PAUSE; done
for v in 0 101; do room_bad roomMaxCpuPercent "$v" 90 1 100 ROOM_MAX_CPU; done
for v in 0 1000000; do room_bad roomMinFreeMB "$v" 2000 1 999999 ROOM_MIN_FREE; done
for v in 0 1441; do room_bad roomMaxWaitMinutes "$v" 30 1 1440 ROOM_MAX_WAIT; done
for v in '"false"' 0 1; do
  cfg "\"roomCheck\": $v"
  room_settings 2> "$tmp/err.txt"
  err_is "roomCheck = $v" "room: parallel.roomCheck must be true or false; using true"
  eq "roomCheck = $v" "$ROOM_ON" true
done
cfg '"roomCheck": false, "roomMinFreeMB": 3000, "roomMaxCpuPercent": 80, "roomPauseSeconds": 5, "roomMaxWaitMinutes": 10'
room_settings 2> "$tmp/err.txt"
err_is "good values" ""
eq "roomCheck false" "$ROOM_ON" false
eq "roomMinFreeMB taken" "$ROOM_MIN_FREE" 3000
eq "roomMaxCpuPercent taken" "$ROOM_MAX_CPU" 80
eq "roomPauseSeconds taken" "$ROOM_PAUSE" 5
eq "roomMaxWaitMinutes taken" "$ROOM_MAX_WAIT" 10
cfg '"roomCheck": null, "roomMinFreeMB": null, "roomMaxCpuPercent": null, "roomPauseSeconds": null, "roomMaxWaitMinutes": null'
room_settings 2> "$tmp/err.txt"
err_is "null values" ""
eq "null roomCheck" "$ROOM_ON" true
eq "null min free" "$ROOM_MIN_FREE" 2000
eq "null max cpu" "$ROOM_MAX_CPU" 90
eq "null pause" "$ROOM_PAUSE" 60
eq "null max wait" "$ROOM_MAX_WAIT" 30
cfg '"maxAgents": 2'
room_settings 2> "$tmp/err.txt"
err_is "absent keys" ""
eq "absent roomCheck" "$ROOM_ON" true
eq "absent min free" "$ROOM_MIN_FREE" 2000
eq "absent max wait" "$ROOM_MAX_WAIT" 30

heading "control settings"
for v in '"Apply"' '"on"' 1 true; do
  cfg "\"controlMode\": $v"
  control_settings 2> "$tmp/err.txt"
  err_is "controlMode $v" 'control: parallel.controlMode must be "off", "report" or "apply"; using "off"'
  eq "controlMode $v" "$CONTROL_MODE" off
done
for v in '"report"' '"apply"'; do
  cfg "\"controlMode\": $v"
  control_settings 2> "$tmp/err.txt"
  err_is "controlMode $v ok" ""
  eq "controlMode $v ok" "\"$CONTROL_MODE\"" "$v"
done
# control_bad <key> <value> <default> <high> <variable>
control_bad() {
  cfg "\"$1\": $2"
  control_settings 2> "$tmp/err.txt"
  err_is "$1 = $2" "control: parallel.$1 must be a whole number from 1 to $4; using $3"
  eq "$1 = $2" "${!5}" "$3"
}
for v in 0 100; do
  control_bad controlMinAgents "$v" 1 99 CONTROL_MIN
  control_bad controlMaxAgents "$v" 4 99 CONTROL_MAX
done
for v in 0 1441 1.5 '"15"'; do control_bad controlCooldownMinutes "$v" 15 1440 CONTROL_COOLDOWN; done
for v in 0 1441 '"5"'; do control_bad controlIntervalMinutes "$v" 5 1440 CONTROL_INTERVAL; done
cfg '"controlMinAgents": null, "controlMaxAgents": null, "controlCooldownMinutes": null, "controlIntervalMinutes": null'
control_settings 2> "$tmp/err.txt"
err_is "null values" ""
eq "null min" "$CONTROL_MIN" 1
eq "null max" "$CONTROL_MAX" 4
eq "null cooldown" "$CONTROL_COOLDOWN" 15
eq "null interval" "$CONTROL_INTERVAL" 5
cfg '"controlMode": null'
control_settings 2> "$tmp/err.txt"
err_is "null mode" ""
eq "null mode" "$CONTROL_MODE" off
cfg '"maxAgents": 2'
control_settings 2> "$tmp/err.txt"
err_is "absent keys" ""
eq "absent mode" "$CONTROL_MODE" off
eq "absent cooldown" "$CONTROL_COOLDOWN" 15
cfg '"controlMinAgents": 5, "controlMaxAgents": 3'
control_settings 2> "$tmp/err.txt"
err_is "min above max" "control: parallel.controlMinAgents 5 is above parallel.controlMaxAgents 3; using 3 for both"
eq "min above max, min" "$CONTROL_MIN" 3
eq "min above max, max" "$CONTROL_MAX" 3

heading "measure"
mkdir "$tmp/fx"
fixture() { local name=$1; shift; printf '%s\n' "$@" > "$tmp/fx/$name"; }
# measure <name>: load_measure 3 on the fixture; the exit code in $rc, standard error in err.txt
measure() {
  rc=0
  NIGHTMILL_LOAD_FIXTURE="$tmp/fx/$1"
  export NIGHTMILL_LOAD_FIXTURE
  load_measure 3 2> "$tmp/err.txt" || rc=$?
  unset NIGHTMILL_LOAD_FIXTURE
}
fixture a "5 61000 64000" "10 60000 64000" "15 62000 64000"
measure a
eq "a exit" "$rc" 0
eq "a samples" "$LOAD_SAMPLES" 3
eq "a cpu" "$LOAD_CPU" 10
eq "a free" "$LOAD_FREE" 60000
eq "a total" "$LOAD_TOTAL" 64000
eq "a from" "$LOAD_FROM" fixture
err_is "a" ""
fixture half "10 61000 64000" "11 60000 64000"
measure half
eq "half rounds up" "$LOAD_CPU" 11
fixture comments "# readings" "" "5 61000 64000" "# between" "10 60000 64000" "15 62000 64000"
measure comments
eq "comments exit" "$rc" 0
eq "comments samples" "$LOAD_SAMPLES" 3
fixture nocpu "10 61000 64000" "- 60000 64000" "15 62000 64000"
measure nocpu
eq "nocpu cpu" "$LOAD_CPU" ""
eq "nocpu why" "$LOAD_CPU_WHY" "sample 2 has no CPU reading"
eq "nocpu free" "$LOAD_FREE" 60000
fixture nomem "10 - 64000" "10 60000 64000" "15 62000 -"
measure nomem
eq "nomem why" "$LOAD_MEM_WHY" "sample 1 has no memory reading"
eq "nomem free" "$LOAD_FREE" ""
eq "nomem cpu" "$LOAD_CPU" 12
# unusable <name> <message>: returns 2 with the message alone on standard error
unusable() {
  measure "$1"
  eq "fixture $1 exit" "$rc" 2
  err_is "fixture $1" "$2"
}
unusable missing "load: cannot read NIGHTMILL_LOAD_FIXTURE: $tmp/fx/missing"
fixture one "10 60000 64000"
unusable one "load: NIGHTMILL_LOAD_FIXTURE needs at least 2 samples"
fixture two "# a comment" "" "10 60000 64000" "10 60000"
unusable two 'load: NIGHTMILL_LOAD_FIXTURE line 4 is not "<cpu> <free MB> <total MB>"'
fixture cpux "10 60000 64000" "x 60000 64000"
unusable cpux 'load: NIGHTMILL_LOAD_FIXTURE line 2 is not "<cpu> <free MB> <total MB>"'
fixture cpu101 "101 60000 64000" "10 60000 64000"
unusable cpu101 'load: NIGHTMILL_LOAD_FIXTURE line 1 is not "<cpu> <free MB> <total MB>"'
fixture freeneg "10 60000 64000" "10 -5 64000"
unusable freeneg 'load: NIGHTMILL_LOAD_FIXTURE line 2 is not "<cpu> <free MB> <total MB>"'
fixture total0 "10 60000 64000" "10 60000 0"
unusable total0 'load: NIGHTMILL_LOAD_FIXTURE line 2 is not "<cpu> <free MB> <total MB>"'

heading "suggest"
# scenario <name> <busy> <cpu> <free> <total> <suggest> <reason> <why>
scenario() {
  LOAD_CEILING=4; LOAD_GB=8
  LOAD_CPU=$3; LOAD_FREE=$4; LOAD_TOTAL=$5
  load_suggest "$2"
  eq "scenario $1 suggest" "$LOAD_SUGGEST" "$6"
  eq "scenario $1 reason" "$LOAD_REASON" "$7"
  eq "scenario $1 why" "$LOAD_WHY" "$8"
}
scenario a 1 10 60000 64000 4 ceiling "the ceiling is the limit (parallel.maxSuggestedAgents = 4); CPU and memory have room for more"
scenario b 1 20 9000 16000 2 memory-total "memory is the limit: 16000 MB in all holds 2 agents at 8 GB each"
scenario c 1 20 9000 32000 2 memory-free "memory is the limit: 9000 MB free holds 1 more agents at 8 GB each beside the 1 in the slots"
scenario d 2 30 1000 16000 1 memory-short "memory is short: 1000 MB free is under 10% of 16000 MB, one agent fewer than the 2 in the slots"
scenario e 2 90 50000 64000 1 cpu "CPU is the limit: 90% busy with 2 agents in the slots, aiming at 80%"
scenario f 0 85 50000 64000 1 cpu-other "CPU is the limit: 85% busy with no slot in use"
scenario g 1 100 50000 64000 1 cpu "CPU is the limit: 100% busy with 1 agents in the slots, aiming at 80%"
scenario i 0 5 12000 16000 1 memory-free "memory is the limit: 12000 MB free holds 1 more agents at 8 GB each beside the 0 in the slots"
LOAD_GB=4; LOAD_CEILING=6; LOAD_CPU=10; LOAD_FREE=60000; LOAD_TOTAL=64000
load_suggest 1
eq "scenario h suggest" "$LOAD_SUGGEST" 6
eq "scenario h reason" "$LOAD_REASON" ceiling
eq "scenario h why" "$LOAD_WHY" "the ceiling is the limit (parallel.maxSuggestedAgents = 6); CPU and memory have room for more"
LOAD_CEILING=4; LOAD_GB=8; LOAD_CPU=""; LOAD_FREE=60000; LOAD_TOTAL=64000
LOAD_SUGGEST=x; LOAD_REASON=x; LOAD_WHY=x
load_suggest 1
eq "no CPU suggest" "$LOAD_SUGGEST" ""
eq "no CPU reason" "$LOAD_REASON" ""
eq "no CPU why" "$LOAD_WHY" ""

heading "wiring"
# the step and the map line of tests/check.sh
grep -qxF 'add bash test-lib-load.sh' "$here/tests/check.sh" || fail "tests/check.sh has no line 'add bash test-lib-load.sh'"
want='map scripts/lib/load.sh smoke-load.sh,smoke-room.sh,smoke-control.sh,test-lib-load.sh'
n=$(awk '$0 == "map scripts/lib/ledger.sh" || index($0, "map scripts/lib/ledger.sh ") == 1 { print NR }' "$here/tests/check.sh" | head -1)
[ -n "$n" ] || fail "tests/check.sh has no map line for scripts/lib/ledger.sh"
next=$(awk -v n="$((n + 1))" 'NR == n' "$here/tests/check.sh")
[ "$next" = "$want" ] || fail "the line after the ledger map line is '$next', expected '$want'"
# each smoke test names the section that replaces what it lost
for f in smoke-load.sh smoke-room.sh smoke-control.sh; do
  awk '/^# In-process \(iteration 72\): .+ is tested in tests\/test-lib-load\.sh, section (load settings|room settings|control settings|measure|suggest)\.$/ { found = 1 } END { exit !found }' "$here/tests/$f" \
    || fail "tests/$f has no '# In-process (iteration 72): ... is tested in tests/test-lib-load.sh, section <name>.' line"
done

echo "LIB LOAD OK"
