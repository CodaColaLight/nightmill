#!/usr/bin/env bash
# tests/smoke-load.sh - load.sh against fixtures of readings (NIGHTMILL_LOAD_FIXTURE is set in every call, so the
# real measurement never runs and the result does not depend on this machine), in a throwaway repository whose slot
# markers and capacity.json are written by hand. The scenarios a to i are those of "The suggestion" in
# docs/specs/iteration-24-machine-load.md; smoke-load.ps1 runs the same cases. Needs bash and awk, no jq.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
L="$here/scripts/load.sh"
unset WORKER_SLOTS NIGHTMILL_LOAD_FIXTURE
TAB=$'\t'

fail() { echo "FAIL: $*" >&2; exit 1; }

# The project: a config without parallel keys, two slots, in a throwaway repository.
git init -q -b main "$tmp/work"
mkdir -p "$tmp/work/.claude" "$tmp/wt/.slots" "$tmp/fx"
cfg="$tmp/work/.claude/nightmill.json"
base_cfg='{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "worktrees": { "root": "../wt", "slots": 2 }
}'
printf '%s\n' "$base_cfg" > "$cfg"
mkdir "$tmp/plain" && git init -q -b main "$tmp/plain"
mkdir "$tmp/outside"

# with_parallel <json members>: the config with a parallel object
with_parallel() { printf '%s\n' "$base_cfg" | sed "s|\"worktrees\"|\"parallel\": { $1 }, \"worktrees\"|" > "$cfg"; }

marker() { printf '{\n  "slot": %s,\n  "branch": "feat/s%s",\n  "since": "2026-11-05T10:00:00"\n}\n' "$1" "$1" > "$tmp/wt/.slots/slot-$1.json"; }
busy() { # busy <n>: slots 1..n busy, the rest free
  rm -f "$tmp/wt/.slots"/slot-*.json
  local i
  for ((i = 1; i <= $1; i++)); do marker "$i"; done
}
fixture() { # fixture <name> <line>...: write a fixture file
  local name=$1
  shift
  printf '%s\n' "$@" > "$tmp/fx/$name"
}
same() { # same <name> <cpu> <free> <total>: three equal samples
  fixture "$1" "$2 $3 $4" "$2 $3 $4" "$2 $3 $4"
}

run_in() { # run_in <dir> <fixture name> [args]: the output in out.txt and err.txt, the exit code in $code
  local dir=$1 fx=$2
  shift 2
  set +e
  (cd "$dir" && NIGHTMILL_LOAD_FIXTURE="$tmp/fx/$fx" bash "$L" "$@") > "$tmp/out.txt" 2> "$tmp/err.txt"
  code=$?
  set -e
}
run() { run_in "$tmp/work" "$@"; }

expect_out() { # expect_out <name> <expected text>
  if [ "$(cat "$tmp/out.txt")" != "$2" ]; then
    echo "--- expected"; printf '%s\n' "$2"; echo "--- got"; cat "$tmp/out.txt"; echo "--- stderr"; cat "$tmp/err.txt"
    fail "$1: the output differs"
  fi
}
has_line() { # has_line <name> <line>: the output has the line
  grep -qxF -- "$2" "$tmp/out.txt" || { cat "$tmp/out.txt"; fail "$1: no line '$2'"; }
}
has_err() { # has_err <name> <line>: standard error has the line
  grep -qxF -- "$2" "$tmp/err.txt" || { cat "$tmp/err.txt"; fail "$1: standard error has no line '$2'"; }
}
code_is() { [ "$code" = "$2" ] || { cat "$tmp/out.txt" "$tmp/err.txt"; fail "$1: exit code $code, expected $2"; }; }
no_err() { [ ! -s "$tmp/err.txt" ] || { cat "$tmp/err.txt"; fail "$1: something on standard error"; }; }

# the fixtures of the scenarios
fixture a "5 61000 64000" "10 60000 64000" "15 62000 64000"
same b 20 9000 16000
same c 20 9000 32000
same d 30 1000 16000
same e 90 50000 64000
same f 85 50000 64000
same g 100 50000 64000
same i 5 12000 16000

echo "== every value is printed (scenario a)"
busy 1
run a
code_is "human form" 0
expect_out "human form" "cpu: 10% busy (mean of 3 samples from NIGHTMILL_LOAD_FIXTURE)
memory: 60000 MB free of 64000 MB (lowest of 3 samples)
agent limit: 2 (default)
slots: 1 of 2 in use
agents running: 1 (counted from the busy slots)
suggested agent limit: 4 (now 2: raise)
why: the ceiling is the limit (parallel.maxSuggestedAgents = 4); CPU and memory have room for more"

echo "== porcelain (scenario a)"
run a --porcelain
code_is "porcelain" 0
no_err "porcelain"
expect_out "porcelain" "cpu${TAB}10
memory-free${TAB}60000
memory-total${TAB}64000
window${TAB}3${TAB}fixture
agent-limit${TAB}2${TAB}default
slot-count${TAB}2
slots-busy${TAB}1
agents-running${TAB}1
memory-per-agent${TAB}8
ceiling${TAB}4
suggested${TAB}4${TAB}raise${TAB}ceiling"

echo "== the window is used, not one reading"
# the last sample alone (CPU 100) would give 1; the mean of the window (40) gives 2
fixture window "10 61000 64000" "10 60000 64000" "100 62000 64000"
run window
code_is "window" 0
has_line "window" "cpu: 40% busy (mean of 3 samples from NIGHTMILL_LOAD_FIXTURE)"
has_line "window" "memory: 60000 MB free of 64000 MB (lowest of 3 samples)"
has_line "window" "suggested agent limit: 2 (now 2: keep)"
has_line "window" "why: CPU is the limit: 40% busy with 1 agents in the slots, aiming at 80%"
# the mean is rounded half up
fixture half "10 61000 64000" "11 60000 64000"
run half --porcelain
has_line "rounding" "cpu${TAB}11"

echo "== the suggestion and its reason (scenarios b to g and i)"
# scenario <name> <busy> <P> <direction> <reason key> <why text>
scenario() {
  busy "$2"
  run "$1"
  code_is "scenario $1" 0
  has_line "scenario $1" "suggested agent limit: $3 (now 2: $4)"
  has_line "scenario $1" "why: $6"
  run "$1" --porcelain
  code_is "scenario $1 porcelain" 0
  has_line "scenario $1 porcelain" "suggested${TAB}$3${TAB}$4${TAB}$5"
}
scenario b 1 2 keep memory-total "memory is the limit: 16000 MB in all holds 2 agents at 8 GB each"
scenario c 1 2 keep memory-free "memory is the limit: 9000 MB free holds 1 more agents at 8 GB each beside the 1 in the slots"
scenario d 2 1 lower memory-short "memory is short: 1000 MB free is under 10% of 16000 MB, one agent fewer than the 2 in the slots"
scenario e 2 1 lower cpu "CPU is the limit: 90% busy with 2 agents in the slots, aiming at 80%"
scenario f 0 1 lower cpu-other "CPU is the limit: 85% busy with no slot in use"
scenario g 1 1 lower cpu "CPU is the limit: 100% busy with 1 agents in the slots, aiming at 80%"
scenario i 0 1 lower memory-free "memory is the limit: 12000 MB free holds 1 more agents at 8 GB each beside the 0 in the slots"

echo "== floor and ceiling"
# g: raw 0 gives 1 (above); a: raw 8 gives the ceiling 4 (above); h: memoryPerAgentGB 4 and maxSuggestedAgents 6
busy 1
with_parallel '"memoryPerAgentGB": 4, "maxSuggestedAgents": 6'
run a
code_is "scenario h" 0
no_err "scenario h"
has_line "scenario h" "suggested agent limit: 6 (now 2: raise)"
has_line "scenario h" "why: the ceiling is the limit (parallel.maxSuggestedAgents = 6); CPU and memory have room for more"
run a --porcelain
has_line "scenario h porcelain" "memory-per-agent${TAB}4"
has_line "scenario h porcelain" "ceiling${TAB}6"
has_line "scenario h porcelain" "suggested${TAB}6${TAB}raise${TAB}ceiling"

echo "== unusable config values fall back to the default"
# bad_value <key> <value> <default> <low> <high>
bad_value() {
  with_parallel "\"$1\": $2"
  run a --porcelain
  code_is "$1 = $2" 0
  has_err "$1 = $2" "load: parallel.$1 must be a whole number from $4 to $5; using $3"
  [ "$(wc -l < "$tmp/err.txt" | tr -d ' ')" = 1 ] || fail "$1 = $2: more than one line on standard error"
}
for v in 0 -1 8.5 8.0 '"8"' true; do
  bad_value memoryPerAgentGB "$v" 8 1 1024
  has_line "memoryPerAgentGB = $v" "memory-per-agent${TAB}8"
done
for v in 0 100; do
  bad_value maxSuggestedAgents "$v" 4 1 99
  has_line "maxSuggestedAgents = $v" "ceiling${TAB}4"
done
for v in 1 61; do
  bad_value loadWindowSeconds "$v" 10 2 60
done
with_parallel '"memoryPerAgentGB": null, "maxSuggestedAgents": null, "loadWindowSeconds": null'
run a --porcelain
code_is "null values" 0
no_err "null values"
has_line "null values" "memory-per-agent${TAB}8"
with_parallel '"maxAgents": 2'
run a --porcelain
no_err "absent keys"
printf '%s\n' "$base_cfg" > "$cfg"

echo "== the agent limit and the slots come from the slot script"
busy 1
printf '{\n  "maxAgents": 3,\n  "since": "2026-11-05T11:00:00"\n}\n' > "$tmp/wt/.slots/capacity.json"
run a
has_line "live limit" "agent limit: 3 (live; config 2)"
has_line "live limit" "suggested agent limit: 4 (now 3: raise)"
run a --porcelain
has_line "live limit porcelain" "agent-limit${TAB}3${TAB}live"
rm -f "$tmp/wt/.slots/capacity.json"
with_parallel '"maxAgents": 5'
run a
has_line "config limit" "agent limit: 5 (config)"
has_line "config limit" "suggested agent limit: 4 (now 5: lower)"
printf '%s\n' "$base_cfg" > "$cfg"
busy 2
printf '{\n  "slots": 1,\n  "since": "2026-11-05T11:00:00"\n}\n' > "$tmp/wt/.slots/capacity.json"
run a
has_line "retiring slot" "slots: 2 of 1 in use"
has_line "retiring slot" "agents running: 2 (counted from the busy slots)"
run a --porcelain
has_line "retiring slot porcelain" "slot-count${TAB}1"
has_line "retiring slot porcelain" "slots-busy${TAB}2"
has_line "retiring slot porcelain" "agents-running${TAB}2"

echo "== nothing is changed"
before=$( (cat "$cfg"; for f in "$tmp/wt/.slots"/*; do echo "== $f"; cat "$f"; done) )
run a
run a --porcelain
run nope
after=$( (cat "$cfg"; for f in "$tmp/wt/.slots"/*; do echo "== $f"; cat "$f"; done) )
[ "$before" = "$after" ] || fail "a file of the project changed"
[ "$(cd "$tmp/wt/.slots" && ls -A | sort | tr '\n' ' ')" = "capacity.json slot-1.json slot-2.json " ] || fail ".slots holds other files: $(ls -A "$tmp/wt/.slots")"
rm -f "$tmp/wt/.slots/capacity.json"

echo "== an unavailable CPU is reported, never guessed"
busy 1
fixture nocpu "10 61000 64000" "- 60000 64000" "15 62000 64000"
run nocpu
code_is "no CPU" 1
expect_out "no CPU" "cpu: unavailable (sample 2 has no CPU reading)
memory: 60000 MB free of 64000 MB (lowest of 3 samples)
agent limit: 2 (default)
slots: 1 of 2 in use
agents running: 1 (counted from the busy slots)
suggested agent limit: none (the CPU load is unavailable)"
run nocpu --porcelain
code_is "no CPU porcelain" 1
expect_out "no CPU porcelain" "cpu${TAB}unavailable${TAB}sample 2 has no CPU reading
memory-free${TAB}60000
memory-total${TAB}64000
window${TAB}3${TAB}fixture
agent-limit${TAB}2${TAB}default
slot-count${TAB}2
slots-busy${TAB}1
agents-running${TAB}1
memory-per-agent${TAB}8
ceiling${TAB}4
suggested${TAB}none${TAB}unavailable"

echo "== an unavailable memory reading, and both"
fixture nomem "10 - 64000" "10 60000 64000" "15 62000 -"
run nomem
code_is "no memory" 1
has_line "no memory" "cpu: 12% busy (mean of 3 samples from NIGHTMILL_LOAD_FIXTURE)"
has_line "no memory" "memory: unavailable (sample 1 has no memory reading)"
has_line "no memory" "suggested agent limit: none (the free memory is unavailable)"
grep -q '^why:' "$tmp/out.txt" && fail "no memory: a why line without a suggestion"
run nomem --porcelain
code_is "no memory porcelain" 1
has_line "no memory porcelain" "memory-free${TAB}unavailable${TAB}sample 1 has no memory reading"
has_line "no memory porcelain" "memory-total${TAB}unavailable${TAB}sample 1 has no memory reading"
has_line "no memory porcelain" "suggested${TAB}none${TAB}unavailable"
[ "$(wc -l < "$tmp/out.txt" | tr -d ' ')" = 11 ] || fail "no memory porcelain: not eleven lines"
fixture neither "10 60000 64000" "- 60000 -" "- - 64000"
run neither
code_is "neither" 1
has_line "neither" "cpu: unavailable (sample 2 has no CPU reading)"
has_line "neither" "memory: unavailable (sample 2 has no memory reading)"
has_line "neither" "suggested agent limit: none (the CPU load and the free memory are unavailable)"

echo "== an unusable fixture stops the command"
# unusable <name> <message>
unusable() {
  run "$1"
  code_is "fixture $1" 2
  [ ! -s "$tmp/out.txt" ] || { cat "$tmp/out.txt"; fail "fixture $1: something on standard output"; }
  has_err "fixture $1" "$2"
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
fixture comments "# readings" "" "5 61000 64000" "# between" "10 60000 64000" "15 62000 64000"
run comments --porcelain
code_is "comment and empty lines" 0
has_line "comment and empty lines" "window${TAB}3${TAB}fixture"

echo "== usage and project errors"
run a --nope
code_is "unknown option" 2
has_err "unknown option" "usage: load.sh [--porcelain]"
run a -h
code_is "-h" 2
set +e
(cd "$tmp/outside" && GIT_CEILING_DIRECTORIES="$tmp" NIGHTMILL_LOAD_FIXTURE="$tmp/fx/a" bash "$L") > "$tmp/out.txt" 2> "$tmp/err.txt"
code=$?
set -e
code_is "outside a checkout" 2
has_err "outside a checkout" "load: run load.sh from inside a checkout of the project"
run_in "$tmp/plain" a
code_is "no config" 2
grep -qF 'run /nightmill:init' "$tmp/err.txt" || fail "no config: the message does not say run /nightmill:init"

echo "LOAD OK"
