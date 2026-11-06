#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# (the LOAD_ variables are read by the script that sources this file; JSON_FLAT is set by scripts/lib/json.sh)
# scripts/lib/load.sh - the machine's CPU load and free memory over a short window, and a suggested agent limit
# (nightmill). Bash twin of scripts/lib/load.ps1; the rules and the texts are in
# docs/specs/iteration-24-machine-load.md. Source it after scripts/lib/json.sh, with the config loaded (json_load).
# Loading it runs nothing.
#
#   load_settings          LOAD_CEILING, LOAD_GB, LOAD_WINDOW from parallel.maxSuggestedAgents, memoryPerAgentGB and
#                          loadWindowSeconds (a wrong value: one warning on standard error and the default)
#   load_measure SAMPLES   LOAD_CPU, LOAD_CPU_WHY, LOAD_FREE, LOAD_TOTAL, LOAD_MEM_WHY, LOAD_SAMPLES, LOAD_FROM (measured
#                          or fixture); a value is empty when unavailable and its _WHY holds the reason. Returns 2 (the
#                          message on standard error) for an unusable NIGHTMILL_LOAD_FIXTURE, else 0
#   load_suggest BUSY      LOAD_SUGGEST, LOAD_REASON (the key), LOAD_WHY (the text); empty when a value is unavailable
#   room_settings          ROOM_ON (true or false), ROOM_MIN_FREE, ROOM_MAX_CPU, ROOM_PAUSE, ROOM_MAX_WAIT from
#                          parallel.roomCheck, roomMinFreeMB, roomMaxCpuPercent, roomPauseSeconds and roomMaxWaitMinutes
#                          (warnings on standard error with the prefix room; docs/specs/iteration-28-machine-room.md)
#   control_settings       CONTROL_MODE (off, report or apply), CONTROL_MIN, CONTROL_MAX, CONTROL_COOLDOWN,
#                          CONTROL_INTERVAL from parallel.controlMode, controlMinAgents, controlMaxAgents,
#                          controlCooldownMinutes and controlIntervalMinutes (warnings on standard error with the prefix
#                          control; docs/specs/iteration-30-load-controller.md)
#
# Readers (by uname -s): Linux reads /proc/stat and /proc/meminfo (MemAvailable); Git Bash (MINGW, MSYS, CYGWIN) the
# same files (MemFree, which carries Windows' available memory); macOS (Darwin) top, vm_stat and sysctl hw.memsize.
# NIGHTMILL_LOAD_FIXTURE names a file of samples "<cpu percent> <free MB> <total MB>" read instead (no sleep).
# No jq, no bc: the arithmetic runs in bash integers and in awk.

# _load_setting KEY LOW HIGH DEFAULT [PREFIX]: the value of parallel.KEY when it is a whole number from LOW to HIGH, else
# DEFAULT (with one warning on standard error, beginning PREFIX: (default load), unless the key is absent or null)
_load_setting() {
  local key=$1 lo=$2 hi=$3 def=$4 prefix=${5:-load} rec kind val
  rec=$(printf '%s\n' "$JSON_FLAT" | K="parallel.$key" LC_ALL=C awk -F '\t' '$1 == ENVIRON["K"] { r = $2 "\t" $3 } END { if (r != "") print r }')
  if [ -z "$rec" ]; then echo "$def"; return 0; fi
  kind=${rec%%$'\t'*}; val=${rec#*$'\t'}
  if [ "$kind" = null ]; then echo "$def"; return 0; fi
  if [ "$kind" = number ] && [[ "$val" =~ ^[1-9][0-9]{0,5}$ ]] && [ "$val" -ge "$lo" ] && [ "$val" -le "$hi" ]; then
    echo "$val"; return 0
  fi
  echo "$prefix: parallel.$key must be a whole number from $lo to $hi; using $def" >&2
  echo "$def"
}

load_settings() {
  LOAD_CEILING=$(_load_setting maxSuggestedAgents 1 99 4)
  LOAD_GB=$(_load_setting memoryPerAgentGB 1 1024 8)
  LOAD_WINDOW=$(_load_setting loadWindowSeconds 2 60 10)
}

room_settings() {
  local rec kind val
  ROOM_ON="true"
  rec=$(printf '%s\n' "$JSON_FLAT" | K="parallel.roomCheck" LC_ALL=C awk -F '\t' '$1 == ENVIRON["K"] { r = $2 "\t" $3 } END { if (r != "") print r }')
  if [ -n "$rec" ]; then
    kind=${rec%%$'\t'*}; val=${rec#*$'\t'}
    if [ "$kind" = boolean ] && { [ "$val" = "true" ] || [ "$val" = "false" ]; }; then
      ROOM_ON=$val
    elif [ "$kind" != null ]; then
      echo "room: parallel.roomCheck must be true or false; using true" >&2
    fi
  fi
  ROOM_MIN_FREE=$(_load_setting roomMinFreeMB 1 999999 2000 room)
  ROOM_MAX_CPU=$(_load_setting roomMaxCpuPercent 1 100 90 room)
  ROOM_PAUSE=$(_load_setting roomPauseSeconds 1 90 60 room)
  ROOM_MAX_WAIT=$(_load_setting roomMaxWaitMinutes 1 1440 30 room)
}

control_settings() {
  local rec kind val
  CONTROL_MODE="off"
  rec=$(printf '%s\n' "$JSON_FLAT" | K="parallel.controlMode" LC_ALL=C awk -F '\t' '$1 == ENVIRON["K"] { r = $2 "\t" $3 } END { if (r != "") print r }')
  if [ -n "$rec" ]; then
    kind=${rec%%$'\t'*}; val=${rec#*$'\t'}
    if [ "$kind" = string ] && { [ "$val" = "off" ] || [ "$val" = "report" ] || [ "$val" = "apply" ]; }; then
      CONTROL_MODE=$val
    elif [ "$kind" != null ]; then
      echo 'control: parallel.controlMode must be "off", "report" or "apply"; using "off"' >&2
    fi
  fi
  CONTROL_MIN=$(_load_setting controlMinAgents 1 99 1 control)
  CONTROL_MAX=$(_load_setting controlMaxAgents 1 99 4 control)
  CONTROL_COOLDOWN=$(_load_setting controlCooldownMinutes 1 1440 15 control)
  CONTROL_INTERVAL=$(_load_setting controlIntervalMinutes 1 1440 5 control)
  if [ "$CONTROL_MIN" -gt "$CONTROL_MAX" ]; then
    echo "control: parallel.controlMinAgents $CONTROL_MIN is above parallel.controlMaxAgents $CONTROL_MAX; using $CONTROL_MAX for both" >&2
    CONTROL_MIN=$CONTROL_MAX
  fi
}

# _load_aggregate MODE: reads samples "<cpu> <free> <total>" ("-" for a failed reading) on standard input and prints
# seven lines: the number of samples, the CPU mean (empty when a sample has none), the first sample without a CPU
# reading (0 when none), the lowest free MB, the total MB of the first sample (both empty when a sample has no memory
# reading), the first sample without a memory reading (0 when none), and an error. MODE fixture checks every line and
# counts the lines of the file; the error is then the message of an unusable fixture.
_load_aggregate() {
  LC_ALL=C awk -v mode="$1" '
    function bad(n) { err = "load: NIGHTMILL_LOAD_FIXTURE line " n " is not \"<cpu> <free MB> <total MB>\""; exit }
    mode == "fixture" && (NF == 0 || $0 ~ /^#/) { next }
    {
      if (mode == "fixture") {
        if (NF != 3) bad(NR)
        if ($1 != "-" && ($1 !~ /^[0-9]+(\.[0-9]+)?$/ || $1 + 0 > 100)) bad(NR)
        if ($2 != "-" && $2 !~ /^[0-9]+$/) bad(NR)
        if ($3 != "-" && ($3 !~ /^[0-9]+$/ || $3 + 0 < 1)) bad(NR)
      }
      s++
      if ($1 == "-") { if (!cpufail) cpufail = s } else { v = $1 + 0; if (v < 0) v = 0; if (v > 100) v = 100; sum += v }
      if ($2 == "-" || $3 == "-") { if (!memfail) memfail = s }
      else {
        if (s == 1 || !havefree || $2 + 0 < free) { free = $2 + 0; havefree = 1 }
        if (total == "") total = $3
      }
    }
    END {
      if (err == "" && mode == "fixture" && s < 2) err = "load: NIGHTMILL_LOAD_FIXTURE needs at least 2 samples"
      print s + 0
      if (!cpufail && s > 0) printf "%d\n", int(sum / s + 0.5); else print ""
      print cpufail + 0
      if (!memfail && s > 0) { printf "%.0f\n", free; print total } else { print ""; print "" }
      print memfail + 0
      print err
    }'
}

# _load_stat: "<total> <idle>" of the first line of /proc/stat (the first eight counters; idle + iowait), or return 1
_load_stat() {
  local line
  { IFS= read -r line < /proc/stat; } 2>/dev/null || return 1
  printf '%s\n' "$line" | LC_ALL=C awk '
    $1 == "cpu" {
      n = 0; t = 0
      for (i = 2; i <= NF && n < 8; i++) { if ($i !~ /^[0-9]+$/) break; t += $i; n++ }
      if (n < 4) exit
      idle = $5 + 0; if (n >= 5) idle += $6
      printf "%.0f %.0f\n", t, idle; ok = 1
    }
    END { exit !ok }'
}

# _load_cpu_sample "<total> <idle>" "<total> <idle>": the busy percentage between two reads, or return 1 when the
# counters did not move
_load_cpu_sample() {
  LC_ALL=C awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, x, " "); split(b, y, " ")
    dt = y[1] - x[1]; di = y[2] - x[2]
    if (dt <= 0) exit 1
    v = 100 * (dt - di) / dt; if (v < 0) v = 0; if (v > 100) v = 100
    printf "%.4f\n", v
  }'
}

# _load_meminfo FREEKEY: "<free MB> <total MB>" from /proc/meminfo, or the reason and return 1
_load_meminfo() {
  local out
  if ! out=$(LC_ALL=C awk -v want="$1" '
      $1 == "MemTotal:" { t = $2 }
      $1 == want ":" { f = $2; hf = 1 }
      END {
        if (t == "") { print "/proc/meminfo cannot be read"; exit 1 }
        if (!hf) { if (want == "MemAvailable") print "/proc/meminfo has no MemAvailable"; else print "/proc/meminfo cannot be read"; exit 1 }
        printf "%d %d\n", int(f * 1024 / 1000000), int(t * 1024 / 1000000)
      }' /proc/meminfo 2>/dev/null); then
    printf '%s\n' "${out:-/proc/meminfo cannot be read}"; return 1
  fi
  printf '%s\n' "$out"
}

# _load_top: the busy percentage of one top sample (top -l 2 -s 1 -n 0, the second CPU usage line), or return 1
_load_top() {
  local out
  out=$(top -l 2 -s 1 -n 0 2>/dev/null) || return 1
  printf '%s\n' "$out" | LC_ALL=C awk '
    /CPU usage:/ { c++; if (c == 2) { for (i = 1; i <= NF; i++) if ($i ~ /^idle/ && i > 1) { v = $(i - 1); sub(/%.*/, "", v); if (v ~ /^[0-9]+(\.[0-9]+)?$/) { u = 100 - v; ok = 1 } } } }
    END { if (!ok) exit 1; if (u < 0) u = 0; if (u > 100) u = 100; printf "%.4f\n", u }'
}

# _load_vm: "<free MB> <total MB>" from vm_stat and sysctl -n hw.memsize, or return 1
_load_vm() {
  local vm mem
  vm=$(vm_stat 2>/dev/null) || return 1
  mem=$(sysctl -n hw.memsize 2>/dev/null) || return 1
  [[ "$mem" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$vm" | LC_ALL=C awk -v mem="$mem" '
    NR == 1 { if (match($0, /page size of [0-9]+ bytes/)) { p = substr($0, RSTART + 13, RLENGTH - 19) + 0 } }
    /^Pages free:/ || /^Pages inactive:/ || /^Pages speculative:/ { v = $NF; sub(/\.$/, "", v); if (v ~ /^[0-9]+$/) { pages += v; n++ } }
    END { if (p <= 0 || n < 3) exit 1; printf "%d %d\n", int(pages * p / 1000000), int(mem / 1000000) }'
}

load_measure() {
  local samples=$1 out agg i cpu_why="" mem_why="" prev cur v m lines="" sys reader
  LOAD_CPU=""; LOAD_CPU_WHY=""; LOAD_FREE=""; LOAD_TOTAL=""; LOAD_MEM_WHY=""; LOAD_SAMPLES=""; LOAD_FROM=""
  if [ -n "${NIGHTMILL_LOAD_FIXTURE:-}" ]; then
    if [ ! -f "$NIGHTMILL_LOAD_FIXTURE" ] || [ ! -r "$NIGHTMILL_LOAD_FIXTURE" ]; then
      echo "load: cannot read NIGHTMILL_LOAD_FIXTURE: $NIGHTMILL_LOAD_FIXTURE" >&2; return 2
    fi
    agg=$(_load_aggregate fixture < "$NIGHTMILL_LOAD_FIXTURE") || { echo "load: cannot read NIGHTMILL_LOAD_FIXTURE: $NIGHTMILL_LOAD_FIXTURE" >&2; return 2; }
    LOAD_FROM=fixture
  else
    LOAD_FROM=measured
    sys=$(uname -s 2>/dev/null || echo unknown)
    case "$sys" in
      Linux) reader=linux ;;
      Darwin) reader=macos ;;
      MINGW*|MSYS*|CYGWIN*) reader=gitbash ;;
      *) reader="" ;;
    esac
    if [ -z "$reader" ]; then
      cpu_why="no reading for this system ($sys)"; mem_why=$cpu_why
      for ((i = 1; i <= samples; i++)); do lines="$lines- - -"$'\n'; done
    elif [ "$reader" = macos ]; then
      for ((i = 1; i <= samples; i++)); do
        v="-"; m="- -"
        if [ -z "$cpu_why" ]; then
          # top takes the second of the sample itself
          if ! v=$(_load_top); then v="-"; cpu_why="top gave no CPU usage"; fi
        elif [ -z "$mem_why" ]; then
          sleep 1
        fi
        if [ -z "$mem_why" ]; then
          if ! m=$(_load_vm); then m="- -"; mem_why="vm_stat or sysctl hw.memsize gave no reading"; fi
        fi
        lines="$lines$v $m"$'\n'
      done
    else
      local freekey=MemAvailable
      if [ "$reader" = gitbash ]; then freekey=MemFree; fi
      if ! prev=$(_load_stat); then cpu_why="/proc/stat cannot be read"; fi
      for ((i = 1; i <= samples; i++)); do
        if [ -z "$cpu_why" ] || [ -z "$mem_why" ]; then sleep 1; fi
        v="-"; m="- -"
        if [ -z "$cpu_why" ]; then
          if ! cur=$(_load_stat); then cpu_why="/proc/stat cannot be read"
          elif ! v=$(_load_cpu_sample "$prev" "$cur"); then v="-"; cpu_why="the CPU counters did not move"
          else prev=$cur; fi
        fi
        if [ -z "$mem_why" ]; then
          if ! m=$(_load_meminfo "$freekey"); then mem_why=$m; m="- -"; fi
        fi
        lines="$lines$v $m"$'\n'
      done
    fi
    agg=$(printf '%s' "$lines" | _load_aggregate measured)
  fi
  {
    IFS= read -r LOAD_SAMPLES; IFS= read -r LOAD_CPU; IFS= read -r i
    if [ "$i" != 0 ]; then
      if [ "$LOAD_FROM" = fixture ]; then LOAD_CPU_WHY="sample $i has no CPU reading"; else LOAD_CPU_WHY=$cpu_why; fi
    fi
    IFS= read -r LOAD_FREE; IFS= read -r LOAD_TOTAL; IFS= read -r i
    if [ "$i" != 0 ]; then
      if [ "$LOAD_FROM" = fixture ]; then LOAD_MEM_WHY="sample $i has no memory reading"; else LOAD_MEM_WHY=$mem_why; fi
    fi
    IFS= read -r out || true
  } <<< "$agg"
  if [ -n "$out" ]; then
    echo "$out" >&2
    LOAD_CPU=""; LOAD_FREE=""; LOAD_TOTAL=""
    return 2
  fi
  return 0
}

load_suggest() {
  local a=$1 m short bytotal byfree more mem cpu raw
  LOAD_SUGGEST=""; LOAD_REASON=""; LOAD_WHY=""
  { [ -n "$LOAD_CPU" ] && [ -n "$LOAD_FREE" ] && [ -n "$LOAD_TOTAL" ]; } || return 0
  m=$((LOAD_GB * 1000))
  short=0; if [ $((LOAD_FREE * 10)) -lt "$LOAD_TOTAL" ]; then short=1; fi
  bytotal=$((LOAD_TOTAL / m))
  more=$((LOAD_FREE / m))
  byfree=$((a + more))
  if [ "$short" = 1 ]; then mem=$((a - 1))
  elif [ "$bytotal" -le "$byfree" ]; then mem=$bytotal
  else mem=$byfree; fi
  if [ "$a" = 0 ]; then
    if [ "$LOAD_CPU" -lt 80 ]; then cpu=$LOAD_CEILING; else cpu=1; fi
  elif [ "$LOAD_CPU" = 0 ]; then cpu=$LOAD_CEILING
  else cpu=$((a * 80 / LOAD_CPU)); fi
  if [ "$mem" -le "$cpu" ]; then raw=$mem; else raw=$cpu; fi
  LOAD_SUGGEST=$raw
  if [ "$LOAD_SUGGEST" -gt "$LOAD_CEILING" ]; then LOAD_SUGGEST=$LOAD_CEILING; fi
  if [ "$LOAD_SUGGEST" -lt 1 ]; then LOAD_SUGGEST=1; fi
  if [ "$raw" -gt "$LOAD_CEILING" ]; then
    LOAD_REASON="ceiling"
    LOAD_WHY="the ceiling is the limit (parallel.maxSuggestedAgents = $LOAD_CEILING); CPU and memory have room for more"
  elif [ "$mem" -le "$cpu" ]; then
    if [ "$short" = 1 ]; then
      LOAD_REASON="memory-short"
      LOAD_WHY="memory is short: $LOAD_FREE MB free is under 10% of $LOAD_TOTAL MB, one agent fewer than the $a in the slots"
    elif [ "$bytotal" -le "$byfree" ]; then
      LOAD_REASON="memory-total"
      LOAD_WHY="memory is the limit: $LOAD_TOTAL MB in all holds $bytotal agents at $LOAD_GB GB each"
    else
      LOAD_REASON="memory-free"
      LOAD_WHY="memory is the limit: $LOAD_FREE MB free holds $more more agents at $LOAD_GB GB each beside the $a in the slots"
    fi
  elif [ "$a" = 0 ]; then
    LOAD_REASON="cpu-other"
    LOAD_WHY="CPU is the limit: $LOAD_CPU% busy with no slot in use"
  else
    LOAD_REASON="cpu"
    LOAD_WHY="CPU is the limit: $LOAD_CPU% busy with $a agents in the slots, aiming at 80%"
  fi
}
