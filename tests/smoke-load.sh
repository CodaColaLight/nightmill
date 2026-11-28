#!/usr/bin/env bash
# tests/smoke-load.sh - load.sh against fixtures of readings (NIGHTMILL_LOAD_FIXTURE is set in every call, so the
# real measurement never runs and the result does not depend on this machine), in a throwaway repository whose slot
# markers and capacity.json are written by hand. The scenarios a to i are those of "The suggestion" in
# docs/specs/iteration-24-machine-load.md. Needs bash and awk, no jq.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-load.XXXXXX")
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

# base_sync <dir> (iteration 48): slot.sh reads the config on origin/HEAD, not the working tree's file, so before a run
# origin/HEAD of the test repository is made to hold the working tree's config: a commit of that one file, with no
# remote needed (refs/remotes/origin/main and origin/HEAD are set directly). Without the file nothing changes.
base_sync() {
  local d=$1 blob tree commit
  [ -f "$d/.claude/nightmill.json" ] || return 0
  blob=$(git -C "$d" hash-object -w -- "$d/.claude/nightmill.json")
  tree=$(printf '100644 blob %s\tnightmill.json\n' "$blob" | git -C "$d" mktree)
  tree=$(printf '040000 tree %s\t.claude\n' "$tree" | git -C "$d" mktree)
  commit=$(git -C "$d" -c user.name=t -c user.email=t@example.invalid commit-tree -m base "$tree")
  git -C "$d" update-ref refs/remotes/origin/main "$commit"
  git -C "$d" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
run_in() { # run_in <dir> <fixture name> [args]: the output in out.txt and err.txt, the exit code in $code
  local dir=$1 fx=$2
  shift 2
  base_sync "$dir"
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

# the fixture of scenario a
fixture a "5 61000 64000" "10 60000 64000" "15 62000 64000"

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
# In-process (iteration 72): the mean rounded half up (fixture half) is tested in tests/test-lib-load.sh, section measure.

echo "== the suggestion and its reason (scenarios b to g and i)"
# In-process (iteration 72): what scenarios b to g and i suggest, with its reason and its why text, is tested in tests/test-lib-load.sh, section suggest.

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
bad_value memoryPerAgentGB 0 8 1 1024
has_line "memoryPerAgentGB = 0" "memory-per-agent${TAB}8"
# In-process (iteration 72): the fallback of memoryPerAgentGB -1, 8.5, 8.0, "8" and true is tested in tests/test-lib-load.sh, section load settings.
# In-process (iteration 72): the fallback of maxSuggestedAgents 0 and 100 is tested in tests/test-lib-load.sh, section load settings.
# In-process (iteration 72): the fallback of loadWindowSeconds 1 and 61 is tested in tests/test-lib-load.sh, section load settings.
# In-process (iteration 72): the case of null values (the defaults, nothing on standard error) is tested in tests/test-lib-load.sh, section load settings.
# In-process (iteration 72): the case of absent keys (nothing on standard error) is tested in tests/test-lib-load.sh, section load settings.
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
# In-process (iteration 72): each of the unusable fixtures one, two, cpux, cpu101, freeneg and total0 is tested in tests/test-lib-load.sh, section measure.
# In-process (iteration 72): a fixture with comment and empty lines (fixture comments) is tested in tests/test-lib-load.sh, section measure.

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

echo "== a failed slot script stops the command with its standard error on one line"
# a copy of load.sh and its lib beside a stub slot.sh that writes two lines to standard error and exits 3
mkdir "$tmp/stub"
cp "$L" "$tmp/stub/load.sh"
cp -R "$here/scripts/lib" "$tmp/stub/lib"
printf '%s\n' "echo 'stub: the slots are unreadable' >&2" "echo 'stub: second line' >&2" "exit 3" > "$tmp/stub/slot.sh"
real_L=$L
L="$tmp/stub/load.sh"
run a
L=$real_L
code_is "failed slot script" 2
[ ! -s "$tmp/out.txt" ] || { cat "$tmp/out.txt"; fail "failed slot script: something on standard output"; }
[ "$(cat "$tmp/err.txt")" = "load: slot.sh failed: stub: the slots are unreadable stub: second line" ] || fail "failed slot script: standard error is '$(cat "$tmp/err.txt")'"
[ "$(wc -l < "$tmp/err.txt" | tr -d ' ')" = 1 ] || fail "failed slot script: more than one line on standard error"

echo "LOAD OK"
