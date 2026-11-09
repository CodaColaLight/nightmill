#!/usr/bin/env bash
# scripts/panel.sh - the slot lines the slots pane beside the Claude chat draws (nightmill).
#
#   panel.sh                print the records once and exit
#
# Read-only. It runs slot.sh --status --porcelain once (no gh, no network) and prints, one per line, tab separated:
# time (HH:MM:SS of the read), every (worktrees.panelRefreshSeconds, default 15), then noslots (no worktrees
# section), or one slot record per slot (<n>, free or busy, agent, branch, skill, step and report cells as /status
# shows them), or one unknown record with the reason the slots could not be read; then the notes. The pane of
# hooks/panel.tsx (/nightmill-slots) calls it on every read; panel.ps1 prints the same bytes. The rules are in
# docs/specs/iteration-32-panel.md. Run it from inside the project: any checkout or worktree of it.
# Exit code 0 when the records were printed (also with an unknown record), 2 for a usage error, no checkout, no or
# invalid config. It writes nothing but two temporary files, removed on every exit. Needs git, bash and awk, no jq.
# NIGHTMILL_NOW (seconds since 1970, local time taken as UTC) fixes the clock here and in slot.sh; the smoke test uses it.
set -euo pipefail

usage() { echo "usage: panel.sh" >&2; exit 2; }
die() { echo "panel: $*" >&2; exit 2; }

[ "$#" -eq 0 ] || usage

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/json.sh
. "$here/lib/json.sh"

gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "run panel.sh from inside a checkout of the project"
[ -n "$gitdir" ] || die "run panel.sh from inside a checkout of the project"
main=$(dirname "$gitdir")
cfg="$main/.claude/nightmill.json"
[ -f "$cfg" ] || die "no $cfg (run /nightmill:init)"
json_load "$cfg" > /dev/null 2>&1 || die "$cfg is not valid JSON"

# the interval: worktrees.panelRefreshSeconds, a whole number from 5 to 3600, else 15 (with a note unless absent or null)
every="15"
note_every=""
rec=$(printf '%s\n' "$JSON_FLAT" | LC_ALL=C awk -F '\t' '$1 == "worktrees.panelRefreshSeconds" { r = $2 "\t" $3 } END { if (r != "") print r }')
if [ -n "$rec" ]; then
  kind="${rec%%$'\t'*}"
  val="${rec#*$'\t'}"
  if [ "$kind" != "null" ]; then
    if [ "$kind" = "number" ] && [[ "$val" =~ ^[1-9][0-9]{0,5}$ ]] && [ "$val" -ge 5 ] && [ "$val" -le 3600 ]; then
      every="$val"
    else
      note_every="worktrees.panelRefreshSeconds must be a whole number from 5 to 3600; using 15"
    fi
  fi
fi

# the clock: NIGHTMILL_NOW, else the local clock read as UTC
epoch=""
nowlocal=""
if [ -n "${NIGHTMILL_NOW:-}" ]; then
  epoch="$NIGHTMILL_NOW"
  [[ "$epoch" =~ ^[0-9]+$ ]] || epoch="0"
  sod=$(( epoch % 86400 ))
  clock=$(printf '%02d:%02d:%02d' "$(( sod / 3600 ))" "$(( sod % 3600 / 60 ))" "$(( sod % 60 ))")
else
  nowlocal=$(date +%Y-%m-%dT%H:%M:%S)
  clock=$(date +%H:%M:%S)
fi

printf 'time\t%s\n' "$clock"
printf 'every\t%s\n' "$every"

if ! json_has worktrees; then
  echo "noslots"
  if [ -n "$note_every" ]; then printf 'note\t%s\n' "$note_every"; fi
  exit 0
fi

out=""
err=""
trap 'if [ -n "$out" ]; then rm -f "$out"; fi; if [ -n "$err" ]; then rm -f "$err"; fi' EXIT
out=$(mktemp)
err=$(mktemp)
code="0"
bash "$here/slot.sh" --status --porcelain > "$out" 2> "$err" || code="$?"

PN_CODE="$code" PN_EPOCH="$epoch" PN_LOCAL="$nowlocal" PN_NOTE="$note_every" PN_ERR="$err" LC_ALL=C awk -F '\t' '
  function days(y, m, d,   era, yoe, doy, doe) {
    if (m <= 2) y--
    era = int((y >= 0 ? y : y - 399) / 400)
    yoe = y - era * 400
    doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
    return era * 146097 + doe - 719468
  }
  function stamp(s,   a) {
    split(s, a, /[-T:]/)
    return days(a[1] + 0, a[2] + 0, a[3] + 0) * 86400 + a[4] * 3600 + a[5] * 60 + a[6]
  }
  function span(sec) {
    if (sec < 0) sec = 0
    if (sec < 3600) return int(sec / 60) "m"
    if (sec < 86400) return int(sec / 3600) "h"
    return int(sec / 86400) "d"
  }
  function clean(s) { gsub(/[\t\r\n]/, " ", s); return s }
  function isstamp(s) { return s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ }
  BEGIN {
    if (ENVIRON["PN_EPOCH"] != "") now = ENVIRON["PN_EPOCH"] + 0
    else now = stamp(ENVIRON["PN_LOCAL"])
    n = 0; bad = 0
  }
  {
    sub(/\r$/, "")
    if (NF == 2 && $1 ~ /^[0-9]+$/ && $2 == "free") {
      rows[++n] = "slot\t" $1 "\tfree\t\t\t\t\t"
    } else if (NF == 10 && $1 ~ /^[0-9]+$/ && $2 == "busy") {
      if ($7 == "" && $8 == "") who = "?"
      else who = ($7 == "" ? "?" : $7) "/" ($8 == "" ? "?" : $8)
      step = ($9 == "" ? "?" : $9)
      rep = (isstamp($10) ? span(now - stamp($10)) : "-")
      rows[++n] = "slot\t" $1 "\tbusy\t" clean($6) "\t" clean($3) "\t" clean(who) "\t" clean(step) "\t" rep
    } else bad = 1
  }
  END {
    code = ENVIRON["PN_CODE"]; ef = ENVIRON["PN_ERR"]
    ne = 0
    while ((getline line < ef) > 0) { sub(/\r$/, "", line); errs[++ne] = line }
    close(ef)
    if (code != "0") {
      reason = ""
      for (i = 1; i <= ne; i++) { t = errs[i]; sub(/ +$/, "", t); if (t != "") { reason = t; break } }
      if (reason == "") reason = "slot.sh exited with code " code
      print "unknown\t" clean(reason)
    } else if (bad) {
      print "unknown\tslot.sh printed a line the panel cannot read"
    } else {
      for (i = 1; i <= n; i++) print rows[i]
    }
    if (ENVIRON["PN_NOTE"] != "") print "note\t" clean(ENVIRON["PN_NOTE"])
    if (code == "0") for (i = 1; i <= ne; i++) if (errs[i] != "") print "note\t" clean(errs[i])
  }' "$out"
exit 0
