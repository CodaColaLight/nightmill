#!/usr/bin/env bash
# scripts/lib/ledger.sh - the stage record (iteration 41): the clock, the UTC stamp, the duration text and the append
# of one line to <worktrees.root>/.slots/ledger.tsv. Source it:  . "$(dirname "$0")/lib/ledger.sh"
# Bash twin of lib/ledger.ps1. Used by slot.sh (it writes the record), stages.sh (it reads it) and tests/check.sh
# (the step times).
#
#   ledger_clock              the time in ledger_s: seconds since 1970, UTC
#   ledger_stamp SECONDS      YYYY-MM-DDTHH:MM:SSZ (UTC), by arithmetic (no date -d or date -r)
#   ledger_epoch STAMP        the inverse: seconds since 1970 of YYYY-MM-DDTHH:MM:SS[Z], read as UTC
#   ledger_duration SECONDS   0s, 42s, 1m05s, 39m00s, 1h40m, 26h03m
#   ledger_append PATH FIELD...   one line, the fields joined by a tab; a failed write is tried again (21 tries in
#                             all, 0.25 s apart), then one note on standard error; never fails
#
# NIGHTMILL_CLOCK_FILE is for the tests only: when it is set, the clock is the first line of that file (seconds since
# 1970, 1 to 12 digits), read again at every reading, so a test moves the clock by writing the file. A set but unusable
# file gives one note on standard error and the system clock.

LEDGER_NOTED=0

ledger_clock() {
  local f=${NIGHTMILL_CLOCK_FILE:-} v=""
  if [ -n "$f" ]; then
    if [ -f "$f" ] && [ -r "$f" ]; then IFS= read -r v < "$f" 2>/dev/null || true; fi
    v=${v%$'\r'}
    if [[ "$v" =~ ^[0-9]{1,12}$ ]]; then ledger_s=$((10#$v)); return 0; fi
    if [ "$LEDGER_NOTED" = 0 ]; then
      echo "ledger: NIGHTMILL_CLOCK_FILE is not usable; using the system clock" >&2
      LEDGER_NOTED=1
    fi
  fi
  ledger_s=$(date +%s)
}

ledger_stamp() {
  local s=$1 z sod era doe yoe y doy mp d m
  z=$((s / 86400)); sod=$((s % 86400))
  if [ "$sod" -lt 0 ]; then sod=$((sod + 86400)); z=$((z - 1)); fi
  z=$((z + 719468))
  era=$(( (z >= 0 ? z : z - 146096) / 146097 ))
  doe=$((z - era * 146097))
  yoe=$(( (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 ))
  y=$((yoe + era * 400))
  doy=$((doe - (365 * yoe + yoe / 4 - yoe / 100)))
  mp=$(( (5 * doy + 2) / 153 ))
  d=$((doy - (153 * mp + 2) / 5 + 1))
  m=$(( mp < 10 ? mp + 3 : mp - 9 ))
  if [ "$m" -le 2 ]; then y=$((y + 1)); fi
  printf '%04d-%02d-%02dT%02d:%02d:%02dZ' "$y" "$m" "$d" $((sod / 3600)) $((sod % 3600 / 60)) $((sod % 60))
}

ledger_epoch() {
  local s=$1 y m d era yoe doy doe
  y=$((10#${s:0:4})); m=$((10#${s:5:2})); d=$((10#${s:8:2}))
  if [ "$m" -le 2 ]; then y=$((y - 1)); fi
  era=$(( (y >= 0 ? y : y - 399) / 400 ))
  yoe=$((y - era * 400))
  doy=$(( (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1 ))
  doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  echo $(( (era * 146097 + doe - 719468) * 86400 + 10#${s:11:2} * 3600 + 10#${s:14:2} * 60 + 10#${s:17:2} ))
}

ledger_duration() {
  local t=$1
  if [ "$t" -lt 0 ]; then t=0; fi
  if [ "$t" -lt 60 ]; then printf '%ds' "$t"
  elif [ "$t" -lt 3600 ]; then printf '%dm%02ds' $((t / 60)) $((t % 60))
  else printf '%dh%02dm' $((t / 3600)) $((t % 3600 / 60)); fi
}

ledger_append() {
  local path=$1 line err="" i=0
  shift
  line=$(IFS=$'\t'; printf '%s' "$*")
  while :; do
    i=$((i + 1))
    if err=$( { printf '%s\n' "$line" >> "$path"; } 2>&1 ); then return 0; fi
    [ "$i" -lt 21 ] || break
    sleep 0.25
  done
  echo "slot: the record was not written ($(printf '%s\n' "$err" | head -n 1))" >&2
  return 0
}
