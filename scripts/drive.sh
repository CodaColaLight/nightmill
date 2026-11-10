#!/usr/bin/env bash
# scripts/drive.sh - the unattended driver (nightmill): runs /nightmill:fix all and /nightmill:next <N> headless, round
# after round, until no Ready bug and no Approved story is left, its time limit is reached or its kill switch is set,
# then prints and posts one summary. Bash twin of drive.ps1; the rules and the texts are in
# docs/specs/iteration-52-unattended-driver.md.
#
#   drive.sh            # no arguments; -h or --help prints the usage line
#
# Run it from inside any checkout of the project. It reads the base branch's .claude/nightmill.json
# (scripts/lib/baseconfig.sh; github, board, labels, git.baseBranch, worktrees, unattended.maxMinutes and
# unattended.summaryIssue), and calls only: gh auth status, gh project item-list, gh pr list, gh issue comment (the
# summary), git rev-parse / fetch origin / symbolic-ref / status, slot.sh --reap, slot.sh --status --porcelain,
# room.sh and claude -p "<prompt>" --permission-mode manual --output-format json in the main checkout. It sets no
# board status and adds none. The lock is <git common dir>/nightmill-drive.lock (one driver per repository), the kill
# switch <git common dir>/nightmill-stop (only its existence counts; the driver never creates or removes it).
# Each step runs as its own process group; whatever is left of it after the step is sent TERM, after 5 seconds KILL.
# The run's files (each step's .json and .err, summary.md) are kept in a mktemp folder named on the last line.
# Exit code 0 the run ended for a reason of the loop (nothing to pick, a tie, the time limit, the kill switch after
# the start, no slot or no room after a step), 1 it could not start, a step's claude exited non-zero, a board read
# failed or the summary could not be posted, 2 a usage error or an unusable configuration, 130 / 143 after SIGINT /
# SIGTERM.
set -uo pipefail

usage_line="usage: drive.sh"
case "${1:-}" in
  -h|--help) echo "$usage_line"; exit 0 ;;
esac
if [ $# -gt 0 ]; then echo "$usage_line" >&2; exit 2; fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/json.sh
. "$here/lib/json.sh"
# shellcheck source=scripts/lib/baseconfig.sh
. "$here/lib/baseconfig.sh"
# shellcheck source=scripts/lib/ledger.sh
. "$here/lib/ledger.sh"

stop2() { echo "drive: $*" >&2; exit 2; }
one_line() { tr '\r\n' '  ' < "$1" | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//'; }

# --- the configuration (a failure here: stderr only, exit 2, no summary) ---
gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || stop2 "run drive.sh from inside a git checkout of the project"
main=$(dirname "$gitdir")
base_config "$main" || stop2 "$base_cfg_stop"
[ -z "$base_cfg_note" ] || echo "$base_cfg_note" >&2
cfg=$base_cfg_file
if [ ! -f "$cfg" ]; then stop2 "no $cfg (run /nightmill:init)"; fi
if ! json_load "$cfg"; then [ -z "$base_cfg_tmp" ] || rm -f "$base_cfg_tmp"; exit 2; fi
[ -z "$base_cfg_tmp" ] || rm -f "$base_cfg_tmp"

# raw_of <path>: the kind and the value of a node, tab separated ("" when absent)
raw_of() {
  printf '%s\n' "$JSON_FLAT" | JSON_P=$1 LC_ALL=C awk -F '\t' '$1 == ENVIRON["JSON_P"] { r = $2 "\t" $3 } END { print r }'
}
# whole <key> <lo> <hi or ""> <default or "">: the value of unattended.<key>, or the stop of decision 6
whole() {
  local key=$1 lo=$2 hi=$3 def=$4 r kind val shown range
  r=$(raw_of "unattended.$key")
  if [ -z "$r" ]; then printf '%s' "$def"; return 0; fi
  kind=${r%%$'\t'*}; val=${r#*$'\t'}
  if [ "$kind" = number ] && [[ "$val" =~ ^[0-9]{1,9}$ ]]; then
    val=$((10#$val))
    if [ "$val" -ge "$lo" ] && { [ -z "$hi" ] || [ "$val" -le "$hi" ]; }; then printf '%s' "$val"; return 0; fi
  fi
  case "$kind" in
    string) shown=$(json_quote "$(printf '%b' "$val")") ;;
    null) shown=null ;;
    object) shown="{...}" ;;
    array) shown="[...]" ;;
    *) shown=$val ;;
  esac
  if [ -n "$hi" ]; then range="from $lo to $hi"; else range="of at least $lo"; fi
  echo "drive: unattended.$key must be a whole number $range, got $shown" >&2
  return 1
}
max_minutes=$(whole maxMinutes 1 1440 240) || exit 2
summary_issue=$(whole summaryIssue 1 "" "") || exit 2

owner=$(json_get github.owner); repo=$(json_get github.repo); project=$(json_get github.projectNumber)
{ [ -n "$owner" ] && [ -n "$repo" ] && [ -n "$project" ]; } || stop2 "github.owner, github.repo and github.projectNumber are needed in $base_cfg_from"
base=$(json_get git.baseBranch main); [ -n "$base" ] || base=main
status_key=$(json_get board.statusField Status | tr '[:upper:]' '[:lower:]')
prio_key=$(json_get board.priorityField Priority | tr '[:upper:]' '[:lower:]')
st_ready=$(json_get board.statuses.ready Ready)
st_approved=$(json_get board.statuses.approved Approved)
lb_bug=$(json_get labels.bug bug)
lb_epic=$(json_get labels.epic epic)
prios=""
if json_has board.priorities; then
  np=$(json_len board.priorities)
  for ((i = 0; i < np; i++)); do prios="$prios$(json_get "board.priorities[$i]")"$'\n'; done
else
  prios=$'Critical\nHigh\nMedium\nLow\n'
fi
has_slots=0; if json_has worktrees; then has_slots=1; fi

# --- the run ---
lock="$gitdir/nightmill-drive.lock"
stopfile="$gitdir/nightmill-stop"
ledger_clock; start_s=$ledger_s
run=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-drive.XXXXXX") || stop2 "cannot make the run folder"
own_lock=0
step_pg=""
steps=0
gh_ok=""           # "", yes or no: gh auth status was run
gh_why=""
left_total=0
not_ended=""
cleaning=0
: > "$run/tried.tsv"
step_prompt=(); step_rc=(); step_dur=(); step_cost=(); step_turns=()

on_exit() {
  if [ -n "$step_pg" ]; then end_group "$step_pg" >/dev/null 2>&1 || true; fi
  if [ "$own_lock" = 1 ]; then rm -f "$lock"; fi
}
trap on_exit EXIT

alive_in() { ps -A -o pid= -o pgid= 2>/dev/null | LC_ALL=C awk -v g="$1" '$2 == g { print $1 }'; }
# end_group <pgid>: TERM to what is left of a step's group, KILL after 5 seconds; adds to left_total and not_ended
end_group() {
  local g=$1 pids n i
  pids=$(alive_in "$g")
  [ -n "$pids" ] || return 0
  n=$(printf '%s\n' "$pids" | wc -l | tr -d ' ')
  left_total=$((left_total + n))
  kill -TERM -- "-$g" 2>/dev/null || true
  for ((i = 0; i < 25; i++)); do
    [ -n "$(alive_in "$g")" ] || return 0
    sleep 0.2
  done
  kill -KILL -- "-$g" 2>/dev/null || true
  sleep 0.2
  pids=$(alive_in "$g")
  if [ -n "$pids" ]; then not_ended="$not_ended $(printf '%s' "$pids" | tr '\n' ' ')"; fi
  return 0
}

gh_auth() {
  [ -z "$gh_ok" ] || return 0
  if gh auth status > "$run/auth.out" 2> "$run/auth.err"; then gh_ok=yes; else
    gh_ok=no
    gh_why=$(one_line "$run/auth.err")
    [ -n "$gh_why" ] || gh_why=$(one_line "$run/auth.out")
  fi
}

# read_board <file>: gh project item-list into <file>.tsv: number, type, status, priority, labels (,a,b,), title
read_board() {
  local f=$1
  if ! gh project item-list "$project" --owner "$owner" --limit 200 --format json > "$f.json" 2> "$f.err"; then
    board_why=$(one_line "$f.err"); return 1
  fi
  if ! JSON_MODE=flat JSON_FILE="$f.json" LC_ALL=C awk -f "$JSON_LIB_DIR/json.awk" > "$f.flat" 2> "$f.err"; then
    board_why="gh project item-list gave no valid JSON"; return 1
  fi
  LC_ALL=C awk -F '\t' -v sk=".$status_key" -v pk=".$prio_key" '
    match($1, /^items\[[0-9]+\]/) {
      i = substr($1, 7, RLENGTH - 7) + 0; rest = substr($1, RLENGTH + 1); if (i + 1 > n) n = i + 1
      if (rest == ".content.number") num[i] = $3
      else if (rest == ".content.type") ty[i] = $3
      else if (rest == ".content.title") ct[i] = $3
      else if (rest == ".title") t[i] = $3
      else if (rest == sk) st[i] = $3
      else if (rest == pk) pr[i] = $3
      else if (rest ~ /^\.labels\[[0-9]+\]$/) lb[i] = lb[i] "," $3 ","
    }
    END {
      for (i = 0; i < n; i++) {
        if (num[i] == "") continue
        tt = (ct[i] != "") ? ct[i] : t[i]
        print num[i] "\t" ty[i] "\t" st[i] "\t" pr[i] "\t" (lb[i] == "" ? "," : lb[i]) "\t" tt
      }
      print n > "/dev/stderr"
    }' "$f.flat" > "$f.tsv" 2> "$f.count"
  board_count=$(tr -d ' \n' < "$f.count")
  if [ "${board_count:-0}" -ge 200 ]; then
    board_full=1
    echo "drive: the board listing returned 200 items, its limit; items past it may be missing"
  fi
  return 0
}
board_full=0

# --- the summary ---
title_of() { # title_of <title>: without a leading [Bug] or [Story], at most 80 characters, no pipe
  local t=$1
  t=${t#\[Bug\] }; t=${t#\[Story\] }
  t=${t//|/\\|}
  printf '%.80s' "$t"
}
money() { LC_ALL=C awk -v x="$1" 'BEGIN { printf "%.2f", x }'; }

build_summary() { # build_summary <start|end> <reason>
  local kind=$1 reason=$2 end_s head prs_ok=0 rows="" p=0 m=0 o=0 b=0 s=0 k sum="0" nocost=0 text n step kk before title after pr state outcome why line rest avail block cut more c rf len used
  ledger_clock; end_s=$ledger_s
  head="**nightmill driver run** $(ledger_stamp "$start_s") to $(ledger_stamp "$end_s") UTC ($(ledger_duration $((end_s - start_s))))."
  if [ "$kind" = start ]; then head="$head Did not start: $reason."; else head="$head Ended: $reason."; fi
  text="$head"$'\n'
  if [ "$kind" != start ]; then
    : > "$run/after.tsv"; : > "$run/prs.tsv"
    if [ "$steps" -gt 0 ]; then
      if read_board "$run/board-after" >/dev/null 2>&1; then cp "$run/board-after.tsv" "$run/after.tsv"; fi
      if gh pr list --repo "$owner/$repo" --state all --limit 100 --json number,state,closingIssuesReferences > "$run/prs.json" 2> "$run/prs.err" \
        && JSON_MODE=flat JSON_FILE="$run/prs.json" LC_ALL=C awk -f "$JSON_LIB_DIR/json.awk" > "$run/prs.flat" 2>/dev/null; then
        # issue TAB newest pr TAB its state
        LC_ALL=C awk -F '\t' '
          match($1, /^\[[0-9]+\]/) {
            i = substr($1, 2, RLENGTH - 2) + 0; rest = substr($1, RLENGTH + 1)
            if (rest == ".number") num[i] = $3
            else if (rest == ".state") st[i] = $3
            else if (rest ~ /^\.closingIssuesReferences\[[0-9]+\]\.number$/) refs[i] = refs[i] " " $3
            if (i + 1 > n) n = i + 1
          }
          END {
            for (i = 0; i < n; i++) {
              c = split(refs[i], r, " ")
              for (j = 1; j <= c; j++) if (!(r[j] in best) || num[i] + 0 > best[r[j]] + 0) { best[r[j]] = num[i]; bs[r[j]] = st[i] }
            }
            for (x in best) print x "\t" best[x] "\t" bs[x]
          }' "$run/prs.flat" > "$run/prs.tsv"
        prs_ok=1
      fi
    fi
    text="$text"$'\n''| Item | Step | Before | After | Outcome | PR |'$'\n''|---|---|---|---|---|---|'$'\n'
    while IFS=$'\037' read -r n step kk before title; do
      [ -n "$n" ] || continue
      p=$((p + 1))
      after=$(LC_ALL=C awk -F '\t' -v n="$n" '$1 == n { print $3; exit }' "$run/after.tsv")
      [ -n "$after" ] || after="?"
      pr=""; state=""
      if [ "$prs_ok" = 1 ]; then
        line=$(LC_ALL=C awk -F '\t' -v n="$n" '$1 == n { print $2 "\037" $3; exit }' "$run/prs.tsv")
        if [ -n "$line" ]; then pr=${line%%$'\037'*}; state=${line#*$'\037'}; fi
      fi
      why="-"
      if [ -f "$run/step-$kk.result" ]; then
        if [ "$step" = "/next" ]; then
          rest=$(grep -m 1 '^Stopped:' "$run/step-$kk.result" || true)
          [ -z "$rest" ] || why=$(printf '%.200s' "$rest")
        else
          rest=$(LC_ALL=C awk -F '|' -v n="$n" 'index($0, "| #" n " ") == 1 { c = $6; gsub(/^ +| +$/, "", c); print c; exit }' "$run/step-$kk.result")
          [ -z "$rest" ] || why=$rest
        fi
      fi
      if [ "$state" = MERGED ]; then outcome="merged"; m=$((m + 1))
      elif [ "$state" = OPEN ]; then outcome="pull request open"; o=$((o + 1))
      elif [ "$after" = "$before" ]; then outcome="not started: $why"; s=$((s + 1))
      else outcome="blocked: $why"; b=$((b + 1)); fi
      if [ -n "$pr" ] && { [ "$state" = MERGED ] || [ "$state" = OPEN ]; }; then pr="#$pr"; else pr="-"; fi
      rows="$rows| #$n $(title_of "$title") | $step | $before | $after | $outcome | $pr |"$'\n'
    done < "$run/tried.tsv"
    text="$text$rows"$'\n'"Picked $p, merged $m, pull request open $o, blocked $b, not started $s."$'\n\n'
    for ((k = 1; k <= steps; k++)); do
      if [ "${step_cost[$k]}" = "?" ]; then nocost=$((nocost + 1)); c="?"; else
        c="\$$(money "${step_cost[$k]}")"; sum=$(LC_ALL=C awk -v a="$sum" -v b="${step_cost[$k]}" 'BEGIN { print a + b }'); fi
      text="$text$k. ${step_prompt[$k]}: exit ${step_rc[$k]}, ${step_dur[$k]}, $c, ${step_turns[$k]} turns."$'\n'
    done
    if [ "$nocost" = 0 ]; then text="${text}Cost: \$$(money "$sum") in all, as Claude Code reports it (total_cost_usd)."$'\n'
    else text="${text}Cost: at least \$$(money "$sum") ($nocost steps without a cost)."$'\n'; fi
    rest=$(LC_ALL=C awk -F '\t' -v r="$st_ready" -v bug=",$lb_bug," -v epic=",$lb_epic," \
      '$2 == "Issue" && $3 == r && index($5, bug) == 0 && index($5, epic) == 0 { printf "%s#%s", (c++ ? ", " : ""), $1 }' "$run/last.tsv" 2>/dev/null)
    if [ -n "$rest" ]; then text="$text"$'\n'"Not run by the driver: Ready stories wait for /spec: $rest."$'\n'
    else text="$text"$'\n'"Not run by the driver: none."$'\n'; fi
    if [ "$board_full" = 1 ]; then text="${text}The board listing returned 200 items, its limit; items past it may be missing."$'\n'; fi
  fi
  text="$text"$'\n'"$(processes_line)"$'\n'
  more=0
  printf '%s' "$text" > "$run/summary.md"
  for ((k = 1; k <= steps; k++)); do
    rf="$run/step-$k.result"; [ -f "$rf" ] || : > "$rf"
    len=$(wc -c < "$rf" | tr -d ' ')
    if [ "$more" = 1 ]; then
      printf '\n[cut: %s more characters in the run files]\n' "$len" >> "$run/summary.md"
      continue
    fi
    block=$'\n'"<details><summary>Final message of ${step_prompt[$k]}</summary>"$'\n\n'
    used=$(wc -c < "$run/summary.md" | tr -d ' ')
    avail=$((60000 - used - $(printf '%s' "$block" | wc -c) - 16 - 64 * (steps - k)))
    if [ "$len" -le "$avail" ]; then
      { printf '%s' "$block"; cat "$rf"; printf '\n\n</details>\n'; } >> "$run/summary.md"
    else
      cut=$((avail - 80)); [ "$cut" -ge 0 ] || cut=0
      { printf '%s' "$block"; head -c "$cut" "$rf"; printf '\n[cut: %s more characters in the run files]\n\n</details>\n' "$((len - cut))"; } >> "$run/summary.md"
      more=1
    fi
  done
}

processes_line() {
  if [ -n "$not_ended" ]; then
    echo "Processes:$(printf '%s' "$not_ended" | sed 's/ *$//') could not be ended."
  elif [ "$left_total" -gt 0 ]; then
    echo "Processes: $left_total left behind by a step were ended; none left running."
  else
    echo "Processes: none left running."
  fi
}

# finish <start|end> <reason> <exit code>: the summary, printed and posted; the exit
finish() {
  local kind=$1 reason=$2 code=$3 err
  build_summary "$kind" "$reason"
  cat "$run/summary.md"
  echo
  if [ -z "$summary_issue" ]; then
    echo "drive: summary not posted: unattended.summaryIssue is not set"
  else
    gh_auth
    if [ "$gh_ok" != yes ]; then
      echo "drive: summary not posted: gh is not signed in"
      [ "$code" != 0 ] || code=1
    elif gh issue comment "$summary_issue" --repo "$owner/$repo" --body-file "$run/summary.md" > "$run/comment.out" 2> "$run/comment.err"; then
      echo "drive: summary posted to #$summary_issue"
    else
      err=$(one_line "$run/comment.err")
      echo "drive: summary not posted: ${err:-gh issue comment failed}"
      [ "$code" != 0 ] || code=1
    fi
  fi
  if [ -n "$not_ended" ]; then code=1; fi
  echo "drive: run files in $run"
  exit "$code"
}
cannot() { echo "drive: cannot start: $1" >&2; finish start "$1" 1; }
# ended <reason> <code>: a stop before a later step (or at a reason of the loop)
ended() { echo "drive: ended: $1"; finish end "$1" "$2"; }
# stop_at <reason> <code if a step ran>: before the first step a slot, room or board stop is "cannot start"
stop_at() { if [ "$steps" = 0 ]; then cannot "$1"; else ended "$1" "$2"; fi; }

on_signal() {
  local sig=$1
  [ "$cleaning" = 0 ] || return 0
  cleaning=1
  trap '' INT TERM
  if [ -n "$step_pg" ]; then
    end_group "$step_pg"
    step_rc[$steps]="stopped"
    ledger_clock; step_dur[$steps]=$(ledger_duration $((ledger_s - step_t0)))
    step_pg=""
  fi
  echo "drive: ended: stopped by SIG$sig"
  build_code=130; [ "$sig" = TERM ] && build_code=143
  finish end "stopped by SIG$sig" "$build_code"
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

# --- start checks ---
take_lock() {
  ( set -C; printf '%s\n%s\n' "$$" "$(ledger_stamp "$start_s")" > "$lock" ) 2>/dev/null
}
if ! take_lock; then
  lpid=$(sed -n 1p "$lock" 2>/dev/null | tr -d '\r '); lstamp=$(sed -n 2p "$lock" 2>/dev/null | tr -d '\r')
  if [[ "$lpid" =~ ^[0-9]+$ ]] && ps -p "$lpid" >/dev/null 2>&1; then
    cannot "another driver runs for this repository (pid $lpid, since ${lstamp:-?})"
  fi
  rm -f "$lock"
  echo "drive: removed a stale lock of pid ${lpid:-?}"
  take_lock || cannot "another driver runs for this repository (the lock $lock could not be taken)"
fi
own_lock=1

if [ -e "$stopfile" ]; then cannot "the kill switch is set (.git/nightmill-stop)"; fi
gh_auth
if [ "$gh_ok" != yes ]; then cannot "gh is not signed in: $gh_why"; fi
command -v claude >/dev/null 2>&1 || cannot "claude is not on the PATH"
if ! git -C "$main" fetch origin > "$run/fetch.out" 2> "$run/fetch.err"; then cannot "git fetch origin failed: $(one_line "$run/fetch.err")"; fi

clean_main() {
  local b
  b=$(git -C "$main" symbolic-ref -q --short HEAD 2>/dev/null) || return 1
  [ "$b" = "$base" ] || return 1
  [ -z "$(git -C "$main" status --porcelain --untracked-files=all 2>/dev/null)" ] || return 1
  return 0
}
clean_main || cannot "the main checkout is not on $base with a clean tree"

# before_step: the kill switch, the time limit, the clean main checkout (decision 3 step 1)
before_step() {
  if [ -e "$stopfile" ]; then stop_at "the kill switch is set (.git/nightmill-stop)" 0; fi
  ledger_clock
  if [ $((ledger_s - start_s)) -ge $((max_minutes * 60)) ]; then stop_at "the time limit of $max_minutes minutes (unattended.maxMinutes) is reached" 0; fi
  clean_main || stop_at "the main checkout is not on $base with a clean tree" 0
}

# slot_room: a free slot (with worktrees) and room on the machine, before a step
slot_room() {
  local since="" rc line busy
  if [ "$has_slots" = 1 ]; then
    if ! (cd "$main" && bash "$here/slot.sh" --reap) > "$run/reap.out" 2> "$run/reap.err"; then
      echo "drive: slot --reap failed: $(one_line "$run/reap.err")" >&2
    fi
    if ! (cd "$main" && bash "$here/slot.sh" --status --porcelain) > "$run/slots.tsv" 2> "$run/slots.err"; then
      echo "drive: slot --status failed: $(one_line "$run/slots.err")" >&2
    elif ! LC_ALL=C awk -F '\t' '$2 == "free" { f = 1 } END { exit !f }' "$run/slots.tsv"; then
      busy=$(LC_ALL=C awk -F '\t' '$2 == "busy" { printf "%s%s: %s", (c++ ? ", " : ""), $1, $3 } END { printf "\t%d", c }' "$run/slots.tsv")
      stop_at "no free slot: all ${busy##*$'\t'} slots are busy (${busy%$'\t'*})" 0
    fi
  fi
  while :; do
    rc=0
    if [ -z "$since" ]; then (cd "$main" && bash "$here/room.sh") > "$run/room.out" 2> "$run/room.err" || rc=$?
    else (cd "$main" && bash "$here/room.sh" --since "$since") > "$run/room.out" 2> "$run/room.err" || rc=$?; fi
    case "$rc" in
      0) return 0 ;;
      1)
        grep '^room: waiting' "$run/room.out" | sed 's/^/drive: /' || true
        since=$(sed -n 's/^room: call again with --since \([0-9][0-9]*\).*/\1/p' "$run/room.out" | head -n 1)
        [ -n "$since" ] || { echo "drive: room: no --since value; the step starts" >&2; return 0; } ;;
      3)
        line=$(grep -m 1 '^room: gave up' "$run/room.out" || tail -n 1 "$run/room.out")
        stop_at "no room on this machine: ${line#room: }" 0 ;;
      *)
        echo "drive: room: not checked ($(one_line "$run/room.err")); the step starts" >&2
        return 0 ;;
    esac
  done
}

# run_step <prompt>: one headless step in the main checkout, as its own process group
run_step() {
  local prompt=$1 k rc
  steps=$((steps + 1)); k=$steps
  step_prompt[$k]=$prompt; step_rc[$k]="?"; step_cost[$k]="?"; step_turns[$k]="?"; step_dur[$k]="0s"
  ledger_clock; step_t0=$ledger_s
  set -m
  (cd "$main" && exec claude -p "$prompt" --permission-mode manual --output-format json) < /dev/null > "$run/step-$k.json" 2> "$run/step-$k.err" &
  step_pg=$!
  set +m
  rc=0
  wait "$step_pg" || rc=$?
  end_group "$step_pg"
  step_pg=""
  ledger_clock; step_dur[$k]=$(ledger_duration $((ledger_s - step_t0)))
  step_rc[$k]=$rc
  if json_load "$run/step-$k.json" 2>/dev/null; then
    json_get result > "$run/step-$k.result"
    local c t
    c=$(json_get total_cost_usd); t=$(json_get num_turns)
    [[ "$c" =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]] && step_cost[$k]=$c
    [[ "$t" =~ ^[0-9]+$ ]] && step_turns[$k]=$t
  else
    : > "$run/step-$k.result"
  fi
  if [ "$rc" != 0 ]; then ended "claude exited $rc in $prompt" 1; fi
}

# --- the loop ---
round=0
while :; do
  round=$((round + 1))
  before_step
  if ! read_board "$run/board-$round"; then stop_at "the board could not be read: $board_why" 1; fi
  cp "$run/board-$round.tsv" "$run/last.tsv"
  # R <num> <status> <title> | A ... | P <num> | T <nums> <prio> | X <ready bugs and approved stories, tried or not>
  PICK_PRIOS=$prios LC_ALL=C awk -F '\t' -v r="$st_ready" -v a="$st_approved" -v bug=",$lb_bug," -v epic=",$lb_epic," -v tried="$run/tried.tsv" '
    BEGIN {
      while ((getline l < tried) > 0) { split(l, f, "\037"); t[f[1]] = 1 }
      np = split(ENVIRON["PICK_PRIOS"], pl, "\n"); for (i = 1; i <= np; i++) if (pl[i] != "" && !(pl[i] in rank)) rank[pl[i]] = i
      best = 1000000
    }
    $2 != "Issue" || index($5, epic) > 0 { next }
    {
      isbug = index($5, bug) > 0
      if (isbug && $3 == r) { x++; if (!($1 in t)) print "R\t" $1 "\t" $3 "\t" $6 }
      if (!isbug && $3 == a) {
        x++
        if (!($1 in t)) {
          print "A\t" $1 "\t" $3 "\t" $6
          k = ($4 in rank) ? rank[$4] : 999999
          if (k < best) { best = k; bn = $1; cnt = 1; bp = $4 } else if (k == best) { bn = bn " " $1; cnt++ }
        }
      }
    }
    END {
      if (cnt == 1) print "P\t" bn
      else if (cnt > 1) {
        m = split(bn, z, " ")
        for (i = 1; i <= m; i++) for (j = i + 1; j <= m; j++) if (z[j] + 0 < z[i] + 0) { s = z[i]; z[i] = z[j]; z[j] = s }
        o = ""; for (i = 1; i <= m; i++) o = o (i > 1 ? ", " : "") "#" z[i]
        print "T\t" o "\t" (best == 999999 ? "no priority" : bp)
      }
      print "X\t" x + 0
    }' "$run/board-$round.tsv" > "$run/pick-$round.tsv"
  pf="$run/pick-$round.tsv"
  if grep -q '^R' "$pf"; then
    slot_room
    while IFS=$'\t' read -r _ n s t; do
      printf '%s\037%s\037%s\037%s\037%s\n' "$n" "/fix all" "$((steps + 1))" "$s" "$t" >> "$run/tried.tsv"
    done < <(grep '^R' "$pf")
    run_step "/nightmill:fix all"
    continue
  fi
  if grep -q '^A' "$pf"; then
    tie=$(LC_ALL=C awk -F '\t' '$1 == "T" { print $2 "\t" $3 }' "$pf")
    if [ -n "$tie" ]; then
      ended "a tie of priorities among the Approved stories ${tie%%$'\t'*} (${tie#*$'\t'}); the maintainer sets one higher" 0
    fi
    pick=$(LC_ALL=C awk -F '\t' '$1 == "P" { print $2 }' "$pf")
    slot_room
    while IFS=$'\t' read -r _ n s t; do
      [ "$n" = "$pick" ] || continue
      printf '%s\037%s\037%s\037%s\037%s\n' "$n" "/next" "$((steps + 1))" "$s" "$t" >> "$run/tried.tsv"
    done < <(grep '^A' "$pf")
    run_step "/nightmill:next $pick"
    continue
  fi
  x=$(LC_ALL=C awk -F '\t' '$1 == "X" { print $2 }' "$pf")
  if [ "${x:-0}" = 0 ]; then ended "nothing Ready or Approved" 0; fi
  ended "nothing new to pick: every Ready bug and Approved story left was tried in this run" 0
done
