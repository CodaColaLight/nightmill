#!/usr/bin/env bash
# scripts/control.sh - one pass of the opt-in load controller (nightmill). Bash twin of control.ps1; the rules and the
# texts are in docs/specs/iteration-30-load-controller.md.
#
#   control.sh                 # no arguments: the mode comes from parallel.controlMode (off, report or apply)
#
# Run it from inside the project: any checkout or worktree of it. When the mode is off it prints one line and ends.
# Otherwise it reads the agent limit, the slot count and the busy slots from the slot script of the same plugin, the
# time of the last change from "since" of <worktrees root>/.slots/capacity.json, measures like scripts/load.sh
# (parallel.loadWindowSeconds samples, scripts/lib/load.sh), takes the suggested agent limit as its target and applies
# its rules: the bounds parallel.controlMinAgents and controlMaxAgents, one step up per parallel.controlCooldownMinutes,
# straight down when memory is short, one step down per cooldown for the CPU or the ceiling. In apply mode it changes
# the live agent limit (and raises the slot count when the new limit is above it) only with slot.sh --capacity; in
# report mode it only says what it would change. It never writes a file of the project itself, never lowers the slot
# count, and never stops an agent. One pass is one call: nothing waits or keeps running.
# Exit code 0 a pass that decided or the controller is off, 1 the CPU load or the free memory is unavailable (nothing
# changed), 2 a usage error, no checkout, no or invalid config, an unusable NIGHTMILL_LOAD_FIXTURE or a failed slot
# script.
set -euo pipefail

if [ $# -gt 0 ]; then echo "usage: control.sh" >&2; exit 2; fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/json.sh
. "$here/lib/json.sh"
# shellcheck source=scripts/lib/load.sh
. "$here/lib/load.sh"

gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "control: run control.sh from inside a checkout of the project" >&2; exit 2; }
main=$(dirname "$gitdir")
cfg="$main/.claude/nightmill.json"
[ -f "$cfg" ] || { echo "control: no $cfg (run /nightmill:init)" >&2; exit 2; }
json_load "$cfg" || exit 2

control_settings

if [ "$CONTROL_MODE" = "off" ]; then
  echo "control: off (parallel.controlMode is off); nothing measured or changed"
  exit 0
fi

load_settings

# The numbers, from the slot script of the same plugin (its standard error passes through)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
slot_call() { # slot_call <output file> <arguments...>
  local out=$1
  shift
  if ! bash "$here/slot.sh" "$@" > "$out" 2> "$tmp/err"; then
    echo "control: slot.sh failed: $(tr '\n' ' ' < "$tmp/err" | sed 's/ *$//')" >&2; exit 2
  fi
  cat "$tmp/err" >&2
}
slot_call "$tmp/capacity" --capacity --porcelain
slot_call "$tmp/status" --status --porcelain
limit=$(awk -F '\t' '$1 == "agents" { print $2 }' "$tmp/capacity")
slot_count=$(awk -F '\t' '$1 == "slots" { print $2 }' "$tmp/capacity")
busy=$(awk -F '\t' '$2 == "busy" { n++ } END { print n + 0 }' "$tmp/status")

# The last change: "since" of capacity.json, where the slot scripts keep the live numbers
# epoch_of YYYY-MM-DDTHH:MM:SS: seconds since 1970 with the time read as UTC (epoch_of of slot.sh)
epoch_of() {
  local s=$1 y m d era yoe doy doe
  y=$((10#${s:0:4})); m=$((10#${s:5:2})); d=$((10#${s:8:2}))
  if [ "$m" -le 2 ]; then y=$((y - 1)); fi
  era=$(( (y >= 0 ? y : y - 399) / 400 ))
  yoe=$((y - era * 400))
  doy=$(( (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1 ))
  doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  echo $(( (era * 146097 + doe - 719468) * 86400 + 10#${s:11:2} * 3600 + 10#${s:14:2} * 60 + 10#${s:17:2} ))
}
root_rel=$(json_get worktrees.root); root_rel=${root_rel:-"../$(basename "$main")-wt"}
cap="$main/$root_rel/.slots/capacity.json"
since=""
if [ -f "$cap" ]; then
  since=$( ( json_load "$cap" && json_get since ) 2>/dev/null || true )
fi
if [[ "${NIGHTMILL_NOW:-}" =~ ^[0-9]{1,12}$ ]]; then now=$NIGHTMILL_NOW; else now=$(epoch_of "$(date +%Y-%m-%dT%H:%M:%S)"); fi
age=""
if [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
  age=$((now - $(epoch_of "$since")))
  if [ "$age" -lt 0 ]; then age=0; fi
fi

# The measurement and the suggestion
rc=0
load_measure "$LOAD_WINDOW" || rc=$?
[ "$rc" = 0 ] || exit 2
load_suggest "$busy"

if [ "$CONTROL_MODE" = "apply" ]; then pre="control: "; else pre="control (report only, nothing changed): "; fi
next="control: next pass in $CONTROL_INTERVAL min (parallel.controlIntervalMinutes)"

if [ -z "$LOAD_SUGGEST" ]; then
  if [ -z "$LOAD_CPU" ] && [ -z "$LOAD_FREE" ]; then
    what="the CPU load ($LOAD_CPU_WHY) and the free memory ($LOAD_MEM_WHY) are unavailable"
  elif [ -z "$LOAD_CPU" ]; then
    what="the CPU load is unavailable ($LOAD_CPU_WHY)"
  else
    what="the free memory is unavailable ($LOAD_MEM_WHY)"
  fi
  echo "${pre}agent limit $limit kept (unavailable; $what)"
  echo "$next"
  exit 1
fi

# The rule (the first row that applies)
lo=$CONTROL_MIN; hi=$CONTROL_MAX; p=$LOAD_SUGGEST
target=$p
if [ "$target" -lt "$lo" ]; then target=$lo; fi
if [ "$target" -gt "$hi" ]; then target=$hi; fi
memory=0
case "$LOAD_REASON" in memory-short|memory-total|memory-free) memory=1 ;; esac
cooling=0
if [ -n "$age" ] && [ "$age" -lt $((CONTROL_COOLDOWN * 60)) ]; then cooling=1; fi

if [ "$limit" -lt "$lo" ]; then
  new=$lo; rule="minimum"
elif [ "$memory" = 1 ] && [ "$target" -lt "$limit" ]; then
  new=$target; rule="memory"
elif [ "$limit" -gt "$hi" ]; then
  new=$hi; rule="maximum"
elif [ "$target" = "$limit" ]; then
  new=$limit
  if [ "$limit" = "$hi" ] && [ "$p" -gt "$hi" ]; then rule="at the maximum"
  elif [ "$limit" = "$lo" ] && [ "$p" -lt "$lo" ]; then rule="at the minimum"
  else rule="steady"; fi
elif [ "$cooling" = 1 ]; then
  new=$limit; rule="cooldown $(( (CONTROL_COOLDOWN * 60 - age + 59) / 60 )) of $CONTROL_COOLDOWN min left"
elif [ "$target" -gt "$limit" ]; then
  new=$((limit + 1)); rule="room"
else
  new=$((limit - 1))
  if [ "$LOAD_REASON" = "ceiling" ]; then rule="ceiling"; else rule="cpu"; fi
fi

measure="CPU $LOAD_CPU%, free memory $LOAD_FREE of $LOAD_TOTAL MB, busy slots $busy, suggested $p: $LOAD_WHY"

if [ "$new" = "$limit" ]; then
  echo "${pre}agent limit $limit kept ($rule; $measure)"
  echo "$next"
  exit 0
fi

slots_part=""
set_args=(--capacity --agent-limit "$new")
if [ "$new" -gt "$slot_count" ]; then
  slots_part=", slots $slot_count -> $new"
  set_args+=(--slot-count "$new")
fi
if [ "$CONTROL_MODE" = "apply" ]; then
  slot_call "$tmp/set" "${set_args[@]}"
fi
echo "${pre}agent limit $limit -> $new$slots_part ($rule; $measure)"
echo "$next"
exit 0
