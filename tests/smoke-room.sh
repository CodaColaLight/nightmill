#!/usr/bin/env bash
# tests/smoke-room.sh - room.sh against fixtures of readings (NIGHTMILL_LOAD_FIXTURE is set in every call that measures,
# so the real measurement never runs and the result does not depend on this machine), in a throwaway repository. The
# cases 1 to 11 are those of "Tests" in docs/specs/iteration-28-machine-room.md; smoke-room.ps1 runs the same cases.
# The pause is parallel.roomPauseSeconds 1 unless a case says otherwise, so nothing sleeps long. Needs bash and awk, no jq.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
R="$here/scripts/room.sh"
unset NIGHTMILL_LOAD_FIXTURE

fail() { echo "FAIL: $*" >&2; exit 1; }

# The project: a config with parallel.roomPauseSeconds 1, in a throwaway repository.
git init -q -b main "$tmp/work"
mkdir -p "$tmp/work/.claude" "$tmp/fx"
cfg="$tmp/work/.claude/nightmill.json"
written=""
# set_parallel <json members>: the config with exactly these members in parallel
set_parallel() {
  written=$(printf '{\n  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },\n  "maintainer": { "name": "Alex" },\n  "verification": { "check": "true" },\n  "parallel": { %s }\n}' "$1")
  printf '%s\n' "$written" > "$cfg"
}
# par <json members>: roomPauseSeconds 1 and the members given
par() {
  if [ -n "${1:-}" ]; then set_parallel "\"roomPauseSeconds\": 1, $1"; else set_parallel '"roomPauseSeconds": 1'; fi
}
par
mkdir "$tmp/plain" && git init -q -b main "$tmp/plain"
mkdir "$tmp/outside"

fixture() { # fixture <name> <line>...: write a fixture file
  local name=$1
  shift
  printf '%s\n' "$@" > "$tmp/fx/$name"
}
fixture ok "30 6000 16000" "40 6500 16000" "50 7000 16000"
fixture short "40 2500 16000" "40 1500 16000" "40 3000 16000"
fixture high "95 6000 16000" "95 6000 16000" "95 6000 16000"
fixture both "95 1500 16000" "95 1500 16000" "95 1500 16000"
fixture cpu-gone "30 6000 16000" "- 6500 16000" "50 7000 16000"
fixture mem-gone "30 - 16000" "40 6500 16000" "50 7000 16000"
fixture mem-gone-high "95 - 16000" "95 6000 16000" "95 6000 16000"
fixture all-gone "30 - 16000" "- 6500 16000" "50 7000 16000"
fixture one "30 6000 16000"

status_before=$(git -C "$tmp/work" status --porcelain --untracked-files=all)

run_in() { # run_in <dir> <fixture path> [args]: the output in out.txt and err.txt, the exit code in $code, the seconds in $took
  local dir=$1 fx=$2 t0 t1
  shift 2
  t0=$(date +%s)
  set +e
  (cd "$dir" && NIGHTMILL_LOAD_FIXTURE="$fx" bash "$R" "$@") > "$tmp/out.txt" 2> "$tmp/err.txt"
  code=$?
  set -e
  t1=$(date +%s)
  took=$((t1 - t0))
}
run() { # run <fixture name> [args]
  local fx=$1
  shift
  run_in "$tmp/work" "$tmp/fx/$fx" "$@"
}

expect_out() { # expect_out <name> <expected text>
  if [ "$(cat "$tmp/out.txt")" != "$2" ]; then
    echo "--- expected"; printf '%s\n' "$2"; echo "--- got"; cat "$tmp/out.txt"; echo "--- stderr"; cat "$tmp/err.txt"
    fail "$1: the output differs"
  fi
}
has_line() { # has_line <name> <line>: the output has the line
  grep -qxF -- "$2" "$tmp/out.txt" || { cat "$tmp/out.txt" "$tmp/err.txt"; fail "$1: no line '$2'"; }
}
has_err() { # has_err <name> <line>: standard error has the line
  grep -qxF -- "$2" "$tmp/err.txt" || { cat "$tmp/err.txt"; fail "$1: standard error has no line '$2'"; }
}
code_is() { [ "$code" = "$2" ] || { cat "$tmp/out.txt" "$tmp/err.txt"; fail "$1: exit code $code, expected $2"; }; }
no_err() { [ ! -s "$tmp/err.txt" ] || { cat "$tmp/err.txt"; fail "$1: something on standard error"; }; }
no_out() { [ ! -s "$tmp/out.txt" ] || { cat "$tmp/out.txt"; fail "$1: something on standard output"; }; }
quick() { [ "$took" -lt 30 ] || fail "$1: took $took s (it paused)"; }
# since_of: the <n> of the line "room: call again with --since <n>"
since_of() { sed -n 's/^room: call again with --since \([0-9]*\)$/\1/p' "$tmp/out.txt"; }

room_ok="room: yes: free memory 6000 MB (at least 2000), CPU 40% (at most 90%)"

echo "== 1. room"
run ok
code_is "room" 0
no_err "room"
expect_out "room" "$room_ok"

echo "== 2. no room, memory"
before=$(date +%s)
run short
code_is "no room, memory" 1
has_line "no room, memory" "room: waiting for memory: free memory 1500 MB, limit at least 2000 MB (waited 0 of 30 min; next check in 1 s)"
n=$(since_of)
[ -n "$n" ] || { cat "$tmp/out.txt"; fail "no room, memory: no line 'room: call again with --since <n>'"; }
if [ "$n" -lt "$before" ] || [ "$n" -gt "$((before + 5))" ]; then fail "no room, memory: --since $n is not within 5 of the clock $before"; fi
[ "$(wc -l < "$tmp/out.txt" | tr -d ' ')" = 2 ] || { cat "$tmp/out.txt"; fail "no room, memory: not two lines"; }
[ "$took" -ge 1 ] || fail "no room, memory: the call did not pause"

echo "== 3. no room, CPU and both"
run high
code_is "no room, CPU" 1
has_line "no room, CPU" "room: waiting for CPU: CPU 95%, limit at most 90% (waited 0 of 30 min; next check in 1 s)"
run both
code_is "no room, both" 1
has_line "no room, both" "room: waiting for memory and CPU: free memory 1500 MB, limit at least 2000 MB; CPU 95%, limit at most 90% (waited 0 of 30 min; next check in 1 s)"

echo "== 4. the limits are config values"
par '"roomMinFreeMB": 1000'
run short
code_is "roomMinFreeMB 1000" 0
expect_out "roomMinFreeMB 1000" "room: yes: free memory 1500 MB (at least 1000), CPU 40% (at most 90%)"
par '"roomMaxCpuPercent": 100'
run high
code_is "roomMaxCpuPercent 100" 0
expect_out "roomMaxCpuPercent 100" "room: yes: free memory 6000 MB (at least 2000), CPU 95% (at most 100%)"
par '"roomMinFreeMB": 999999'
run ok
code_is "roomMinFreeMB 999999" 1
has_line "roomMinFreeMB 999999" "room: waiting for memory: free memory 6000 MB, limit at least 999999 MB (waited 0 of 30 min; next check in 1 s)"
par

echo "== 5. wait, then room"
run short
code_is "wait" 1
n=$(since_of)
[ -n "$n" ] || fail "wait: no --since line"
run ok --since "$n"
code_is "then room" 0
expect_out "then room" "$room_ok"

echo "== 6. the longest wait"
now=$(date +%s)
run short --since "$((now - 1700))"
code_is "waited 28" 1
grep -qF '(waited 28 of 30 min; next check in 1 s)' "$tmp/out.txt" || { cat "$tmp/out.txt"; fail "waited 28: no 'waited 28 of 30 min'"; }
has_line "waited 28" "room: call again with --since $((now - 1700))"
set_parallel '"roomPauseSeconds": 90'
now=$(date +%s)
run short --since "$((now - 1800))"
code_is "gave up" 3
expect_out "gave up" "room: gave up after 30 min: free memory 1500 MB, limit at least 2000 MB"
quick "gave up"
par '"roomMaxWaitMinutes": 1'
now=$(date +%s)
run short --since "$((now - 60))"
code_is "gave up after 1 min" 3
expect_out "gave up after 1 min" "room: gave up after 1 min: free memory 1500 MB, limit at least 2000 MB"
par
now=$(date +%s)
run ok --since "$((now - 3600))"
code_is "room comes first" 0
expect_out "room comes first" "$room_ok"
now=$(date +%s)
run short --since "$((now + 1000))"
code_is "since in the future" 1
grep -qF '(waited 0 of 30 min;' "$tmp/out.txt" || { cat "$tmp/out.txt"; fail "since in the future: not waited 0"; }

echo "== 7. unavailable is not checked and said"
run cpu-gone
code_is "cpu-gone" 0
no_err "cpu-gone"
expect_out "cpu-gone" "room: CPU load not checked: unavailable (sample 2 has no CPU reading)
room: yes: free memory 6000 MB (at least 2000), CPU not checked"
run mem-gone
code_is "mem-gone" 0
expect_out "mem-gone" "room: free memory not checked: unavailable (sample 1 has no memory reading)
room: yes: free memory not checked, CPU 40% (at most 90%)"
run mem-gone-high
code_is "mem-gone, CPU high" 1
has_line "mem-gone, CPU high" "room: free memory not checked: unavailable (sample 1 has no memory reading)"
has_line "mem-gone, CPU high" "room: waiting for CPU: CPU 95%, limit at most 90% (waited 0 of 30 min; next check in 1 s)"
run all-gone
code_is "all-gone" 0
expect_out "all-gone" "room: free memory not checked: unavailable (sample 1 has no memory reading)
room: CPU load not checked: unavailable (sample 2 has no CPU reading)
room: yes: free memory not checked, CPU not checked"

echo "== 8. switched off"
set_parallel '"roomCheck": false, "roomPauseSeconds": 90'
run short
code_is "off" 0
no_err "off"
expect_out "off" "room: not checked (parallel.roomCheck is false)"
quick "off"
run missing
code_is "off, missing fixture" 0
expect_out "off, missing fixture" "room: not checked (parallel.roomCheck is false)"
quick "off, missing fixture"
set_parallel '"roomCheck": true, "roomPauseSeconds": 1'
run ok
code_is "on" 0
no_err "on"
expect_out "on" "$room_ok"

echo "== 9. unusable config values fall back"
# bad_value <key> <value> <warning>: on ok, the warning alone on standard error, exit 0, the room line with the defaults
bad_value() {
  set_parallel "\"$1\": $2"
  run ok
  code_is "$1 = $2" 0
  has_err "$1 = $2" "$3"
  [ "$(wc -l < "$tmp/err.txt" | tr -d ' ')" = 1 ] || { cat "$tmp/err.txt"; fail "$1 = $2: not one line on standard error"; }
  expect_out "$1 = $2" "$room_ok"
}
for v in 0 -1 8.5 '"60"' true 91; do
  bad_value roomPauseSeconds "$v" "room: parallel.roomPauseSeconds must be a whole number from 1 to 90; using 60"
done
for v in 0 101; do
  bad_value roomMaxCpuPercent "$v" "room: parallel.roomMaxCpuPercent must be a whole number from 1 to 100; using 90"
done
for v in 0 1000000; do
  bad_value roomMinFreeMB "$v" "room: parallel.roomMinFreeMB must be a whole number from 1 to 999999; using 2000"
done
for v in 0 1441; do
  bad_value roomMaxWaitMinutes "$v" "room: parallel.roomMaxWaitMinutes must be a whole number from 1 to 1440; using 30"
  set_parallel "\"roomMaxWaitMinutes\": $v"
  now=$(date +%s)
  run short --since "$((now - 1800))"
  code_is "roomMaxWaitMinutes = $v, gave up" 3
  expect_out "roomMaxWaitMinutes = $v, gave up" "room: gave up after 30 min: free memory 1500 MB, limit at least 2000 MB"
  quick "roomMaxWaitMinutes = $v, gave up"
done
for v in '"false"' 0 1; do
  bad_value roomCheck "$v" "room: parallel.roomCheck must be true or false; using true"
done
set_parallel '"roomCheck": null, "roomMinFreeMB": null, "roomMaxCpuPercent": null, "roomPauseSeconds": null, "roomMaxWaitMinutes": null'
run ok
code_is "null values" 0
no_err "null values"
expect_out "null values" "$room_ok"
set_parallel '"maxAgents": 2'
run ok
code_is "absent keys" 0
no_err "absent keys"
expect_out "absent keys" "$room_ok"
par

echo "== 10. errors"
# usage <name> <args...>: exit 2 with the usage line
usage_case() {
  local name=$1
  shift
  run ok "$@"
  code_is "$name" 2
  has_err "$name" "usage: room.sh [--since <seconds>]"
  no_out "$name"
}
usage_case "unknown option" --nope
usage_case "-h" -h
usage_case "--since x" --since x
usage_case "--since 0" --since 0
usage_case "--since 0123" --since 0123
usage_case "13 digits" --since 1234567890123
usage_case "--since without a value" --since
usage_case "--since twice" --since 1 --since 2
set +e
(cd "$tmp/outside" && GIT_CEILING_DIRECTORIES="$tmp" NIGHTMILL_LOAD_FIXTURE="$tmp/fx/ok" bash "$R") > "$tmp/out.txt" 2> "$tmp/err.txt"
code=$?
set -e
code_is "outside a checkout" 2
has_err "outside a checkout" "room: run room.sh from inside a checkout of the project"
run_in "$tmp/plain" "$tmp/fx/ok"
code_is "no config" 2
grep -qF 'run /nightmill:init' "$tmp/err.txt" || fail "no config: the message does not say run /nightmill:init"
run missing
code_is "missing fixture" 2
no_out "missing fixture"
has_err "missing fixture" "load: cannot read NIGHTMILL_LOAD_FIXTURE: $tmp/fx/missing"
run one
code_is "one sample" 2
no_out "one sample"
has_err "one sample" "load: NIGHTMILL_LOAD_FIXTURE needs at least 2 samples"

echo "== 11. nothing is changed"
[ "$(cat "$cfg")" = "$written" ] || fail "the config changed"
[ "$(git -C "$tmp/work" status --porcelain --untracked-files=all)" = "$status_before" ] || { git -C "$tmp/work" status --porcelain --untracked-files=all; fail "the repository changed"; }
[ -z "$(find "$tmp" -name .slots)" ] || fail "a .slots folder was created"

echo "ROOM OK"
