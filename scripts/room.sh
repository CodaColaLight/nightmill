#!/usr/bin/env bash
# scripts/room.sh - does the machine have room for one more agent? Free memory and CPU load over 3 one-second samples,
# against parallel.roomMinFreeMB and parallel.roomMaxCpuPercent (nightmill). Bash twin of room.ps1; the rules and the
# texts are in docs/specs/iteration-28-machine-room.md.
#
#   room.sh                    # the first check
#   room.sh --since <seconds>  # a check while waiting: the value of the "room: call again with" line
#
# Run it from inside the project: any checkout or worktree of it. It measures with scripts/lib/load.sh and only reads:
# it writes nothing, calls no slot script and never changes the agent limit. When there is no room it prints why,
# pauses parallel.roomPauseSeconds and exits 1; the skill calls it again with --since, and the script ends the wait
# itself after parallel.roomMaxWaitMinutes.
# Exit code 0 start (room, switched off, or nothing that could be checked holds it), 1 no room yet (paused; call again
# with --since), 2 for a usage error, no checkout, no or invalid config or an unusable NIGHTMILL_LOAD_FIXTURE, 3 the
# longest wait ran out (start nothing).
set -euo pipefail

usage() { echo "usage: room.sh [--since <seconds>]" >&2; exit 2; }

since_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since)
      [ -z "$since_arg" ] || usage
      [ $# -ge 2 ] || usage
      [[ "$2" =~ ^[1-9][0-9]{0,11}$ ]] || usage
      since_arg=$2
      shift ;;
    *) usage ;;
  esac
  shift
done

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/json.sh
. "$here/lib/json.sh"
# shellcheck source=scripts/lib/load.sh
. "$here/lib/load.sh"

gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "room: run room.sh from inside a checkout of the project" >&2; exit 2; }
main=$(dirname "$gitdir")
cfg="$main/.claude/nightmill.json"
[ -f "$cfg" ] || { echo "room: no $cfg (run /nightmill:init)" >&2; exit 2; }
json_load "$cfg" || exit 2

room_settings

if [ "$ROOM_ON" = "false" ]; then
  echo "room: not checked (parallel.roomCheck is false)"
  exit 0
fi

now=$(date +%s)
since=${since_arg:-$now}
waited=$((now - since))
if [ "$waited" -lt 0 ]; then waited=0; fi

rc=0
load_measure 3 || rc=$?
[ "$rc" = 0 ] || exit 2

short=0; high=0; mem_part=""; cpu_part=""; details=""
if [ -z "$LOAD_FREE" ]; then
  echo "room: free memory not checked: unavailable ($LOAD_MEM_WHY)"
  mem_part="free memory not checked"
elif [ "$LOAD_FREE" -ge "$ROOM_MIN_FREE" ]; then
  mem_part="free memory $LOAD_FREE MB (at least $ROOM_MIN_FREE)"
else
  short=1
  details="free memory $LOAD_FREE MB, limit at least $ROOM_MIN_FREE MB"
fi
if [ -z "$LOAD_CPU" ]; then
  echo "room: CPU load not checked: unavailable ($LOAD_CPU_WHY)"
  cpu_part="CPU not checked"
elif [ "$LOAD_CPU" -le "$ROOM_MAX_CPU" ]; then
  cpu_part="CPU $LOAD_CPU% (at most $ROOM_MAX_CPU%)"
else
  high=1
  if [ -n "$details" ]; then details="$details; "; fi
  details="${details}CPU $LOAD_CPU%, limit at most $ROOM_MAX_CPU%"
fi

# room is judged before the clock: a check that finds room starts however long the wait was
if [ "$short" = 0 ] && [ "$high" = 0 ]; then
  echo "room: yes: $mem_part, $cpu_part"
  exit 0
fi

if [ "$short" = 1 ] && [ "$high" = 1 ]; then what="memory and CPU"
elif [ "$short" = 1 ]; then what="memory"
else what="CPU"; fi
w=$((waited / 60))

if [ "$waited" -ge $((ROOM_MAX_WAIT * 60)) ]; then
  echo "room: gave up after $w min: $details"
  exit 3
fi

echo "room: waiting for $what: $details (waited $w of $ROOM_MAX_WAIT min; next check in $ROOM_PAUSE s)"
echo "room: call again with --since $since"
sleep "$ROOM_PAUSE"
exit 1
