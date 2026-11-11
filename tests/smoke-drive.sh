#!/usr/bin/env bash
# tests/smoke-drive.sh - scripts/drive.sh against a fake claude, a fake gh and throwaway slots (iteration 52, #164;
# docs/specs/iteration-52-unattended-driver.md, "Tests"; iteration 53, #165, docs/specs/iteration-53-run-limits.md: the
# flags, the run ledger, the pause flag and the limits). smoke-drive.ps1 runs the same cases. Needs bash and awk, no network.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
D="$here/scripts/drive.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-drive.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp/runs"
mkdir -p "$TMPDIR" "$tmp/bin"
fx="$here/tests/fixtures/drive"

fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$D" ] || fail "scripts/drive.sh does not exist"

# --- the fake gh ---
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "${GH_LOG:-/dev/null}"
case "${1:-} ${2:-}" in
  "auth status")
    if [ -n "${GH_AUTH_FAIL:-}" ]; then echo "fake gh: not logged in" >&2; exit 1; fi
    exit 0 ;;
  "project item-list")
    awk -F'\t' 'BEGIN { printf "{\"items\": ["; n = 0 }
      { if (n++) printf ","
        printf "{\"id\":\"PVTI_%s\",\"content\":{\"number\":%s,\"title\":\"%s\",\"type\":\"Issue\"},\"labels\":[\"%s\"],\"status\":\"%s\"", $1, $1, $5, $4, $2
        if ($3 != "") printf ",\"priority\":\"%s\"", $3
        printf ",\"title\":\"%s\"}", $5 }
      END { print "], \"totalCount\": " n "}" }' "$BOARD"
    exit 0 ;;
  "pr list")
    awk -F'\t' 'BEGIN { printf "["; n = 0 }
      { if (n++) printf ","
        printf "{\"number\":%s,\"state\":\"%s\",\"headRefName\":\"b%s\",\"closingIssuesReferences\":[{\"number\":%s}]}", $1, $2, $1, $3 }
      END { print "]" }' "$PRS"
    exit 0 ;;
  "issue comment")
    if [ -n "${GH_COMMENT_FAIL:-}" ]; then echo "fake gh: comment refused" >&2; exit 1; fi
    prev=""
    for a in "$@"; do
      if [ "$prev" = "--body-file" ]; then cp "$a" "$COMMENT"; cp "$a" "$COMMENT.${3:-0}"; fi
      prev=$a
    done
    exit 0 ;;
  "issue edit") exit 0 ;;
  "issue view")
    if [ -f "${ISSUE_COMMENTS:-/nonexistent}" ]; then cat "$ISSUE_COMMENTS"; else echo '{"comments":[]}'; fi
    exit 0 ;;
  "api user") echo agent; exit 0 ;;
  "api graphql")
    if [ -n "${EPIC_FOR:-}" ] && case "$*" in *"issue(number: $EPIC_FOR)"*) true ;; *) false ;; esac; then
      cat "$EPIC_FILE"
    else
      echo '{"data":{"repository":{"issue":{"parent":null}}}}'
    fi
    exit 0 ;;
esac
echo "fake gh: unexpected call" >&2
exit 1
GH
# --- the fake claude: one line of $SCRIPT per step; actions separated by spaces ---
#   status:N:Name  pr:P:STATE:N  stop  clock:+S  bg  hang  exit:C  stopped:Text_with_underscores  cost:X  turns:T  long
#   dur:MS  subtype:S (the result's subtype, default success)  pause (commit limits.paused true and push it from the main checkout)
cat > "$tmp/bin/claude" <<'CL'
#!/usr/bin/env bash
echo "$*" >> "$CLAUDE_LOG"
echo "left=${NIGHTMILL_ISSUES_LEFT:-} started=${NIGHTMILL_RUN_STARTED:-}" >> "$ENV_LOG"
k=0
[ -f "$STEPFILE" ] && k=$(cat "$STEPFILE")
k=$((k + 1))
echo "$k" > "$STEPFILE"
line=$(sed -n "${k}p" "$SCRIPT")
cost=0.10; turns=3; code=0; stopped=""; long=""; dur=1500; subtype=success
for a in $line; do
  case "$a" in
    status:*) IFS=: read -r _ n s <<<"$a"; awk -F'\t' -v OFS='\t' -v n="$n" -v s="${s//_/ }" '$1 == n { $2 = s } { print }' "$BOARD" > "$BOARD.new"; mv "$BOARD.new" "$BOARD" ;;
    pr:*) IFS=: read -r _ p st n <<<"$a"; printf '%s\t%s\t%s\n' "$p" "$st" "$n" >> "$PRS" ;;
    stop) touch "$STOPFILE" ;;
    clock:*) v=$(cat "$NIGHTMILL_CLOCK_FILE"); echo $((v + ${a#clock:+})) > "$NIGHTMILL_CLOCK_FILE" ;;
    bg) sleep 300 >/dev/null 2>&1 & echo $! > "$BGPID" ;;
    hang) echo $$ > "$STEPPID"; sleep 60 & echo $! > "$BGPID"; wait ;;
    exit:*) code=${a#exit:} ;;
    stopped:*) stopped=${a#stopped:}; stopped=${stopped//_/ } ;;
    cost:*) cost=${a#cost:} ;;
    turns:*) turns=${a#turns:} ;;
    long) long=1 ;;
    dur:*) dur=${a#dur:} ;;
    subtype:*) subtype=${a#subtype:} ;;
    pause)
      awk '{ l[NR] = $0 } END { for (i = 1; i < NR; i++) print l[i]; print "  ,\"limits\": { \"paused\": true }"; print l[NR] }' "$MAIN/.claude/nightmill.json" > "$MAIN/.claude/nightmill.json.new"
      mv "$MAIN/.claude/nightmill.json.new" "$MAIN/.claude/nightmill.json"
      git -C "$MAIN" commit -q -am "pause" && git -C "$MAIN" push -q origin main ;;
  esac
done
if [ -n "$long" ]; then
  msg=$(head -c 70000 /dev/zero | tr '\0' 'x')
else
  msg="Done with step $k."
  [ -z "$stopped" ] || msg="$msg\\nStopped: $stopped"
  [ -n "$stopped" ] || msg="$msg\\nAll good."
fi
printf '{"type":"result","subtype":"%s","result":"%s","duration_ms":%s,"total_cost_usd":%s,"num_turns":%s}\n' "$subtype" "$msg" "$dur" "$cost" "$turns"
exit "$code"
CL
chmod +x "$tmp/bin/gh" "$tmp/bin/claude"

# new_case <name> [config members after the github block]: a fresh origin, main checkout and config
case_n=0
new_case() {
  case_n=$((case_n + 1))
  c="$tmp/case$case_n"
  mkdir -p "$c"
  git init -q --bare -b main "$c/origin.git"
  git clone -q "$c/origin.git" "$c/main" 2>/dev/null
  main="$c/main"
  git -C "$main" config user.email t@example.com
  git -C "$main" config user.name t
  git -C "$main" checkout -q -b main 2>/dev/null || true
  mkdir -p "$main/.claude"
  local extra=${1-'"unattended": { "summaryIssue": 9, "maxMinutes": 60 }'}
  local slots=${2:-2} room=${3:-false}
  printf '{\n  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },\n  "maintainer": { "name": "Alex" },\n  "verification": { "check": "true" },\n  "worktrees": { "root": "../wt", "slots": %s },\n  "parallel": { "roomCheck": %s }%s\n}\n' "$slots" "$room" "${extra:+,$'\n'  $extra}" > "$main/.claude/nightmill.json"
  git -C "$main" add -A
  git -C "$main" commit -q -m init
  git -C "$main" push -q origin main 2>/dev/null
  git -C "$main" remote set-head origin main >/dev/null 2>&1
  git -C "$main" fetch -q origin
  export BOARD="$c/board.tsv" PRS="$c/prs.tsv" SCRIPT="$c/script.txt" GH_LOG="$c/gh.log" CLAUDE_LOG="$c/claude.log"
  export ENV_LOG="$c/env.log" MAIN="$main" EPIC_FILE="$fx/../gate/epic-paused.json" LEDGER="$c/wt/.slots/ledger.tsv"
  export COMMENT="$c/comment.md" STEPFILE="$c/step.n" BGPID="$c/bg.pid" STEPPID="$c/step.pid"
  export NIGHTMILL_CLOCK_FILE="$c/clock" STOPFILE="$main/.git/nightmill-stop"
  : > "$PRS"; : > "$SCRIPT"; echo 1800000000 > "$NIGHTMILL_CLOCK_FILE"
  unset GH_AUTH_FAIL GH_COMMENT_FAIL EPIC_FOR ISSUE_COMMENTS
}
board() { cp "$fx/$1" "$BOARD"; }
script() { printf '%s\n' "$@" > "$SCRIPT"; }
# drive [script path]: run the driver in the main checkout; out.txt, err.txt, $code
drive() {
  local d=${1:-$D}
  (cd "$main" && PATH="$tmp/bin:$PATH" bash "$d") > "$c/out.txt" 2> "$c/err.txt"
  code=$?
}
calls() { [ -f "$CLAUDE_LOG" ] && wc -l < "$CLAUDE_LOG" | tr -d ' ' || echo 0; }
has() { grep -qF -- "$2" "$1" || fail "$3: '$2' not found in $(basename "$1")"; }
hasnt() { if [ -f "$1" ] && grep -qF -- "$2" "$1"; then fail "$3: '$2' found in $(basename "$1")"; fi; }
want_code() { [ "$code" = "$1" ] || fail "$2: exit $code, $1 expected ($(cat "$c/err.txt" "$c/out.txt" | head -5))"; }
# every gh call is one of the driver's reads and writes (iteration 52 decision 9 and iteration 53 decision 8): the only
# edit is the label blocked; no status, no field, no item
audit() {
  if [ -f "$GH_LOG" ]; then
    while IFS= read -r l; do
      case "$l" in
        "auth status"*|"project item-list"*|"pr list"*|"issue comment"*|"api graphql"*|"api user"*|"issue view"*) ;;
        "issue edit "*) [[ "$l" =~ ^issue\ edit\ [0-9]+\ --add-label\ blocked$ ]] || fail "$1: an issue edit other than the label blocked: $l" ;;
        *) fail "$1: a gh call the driver may not make: $l" ;;
      esac
    done < "$GH_LOG"
  fi
  [ ! -e "$main/.git/nightmill-drive.lock" ] || fail "$1: the lock is left"
}

FLAGS='--permission-mode manual --output-format json --max-turns 200 --max-budget-usd 25.00'
FIX="-p /nightmill:fix all $FLAGS"

# nothing
new_case; board board-nothing.tsv; drive
want_code 0 nothing; [ "$(calls)" = 0 ] || fail "nothing: claude was called"
has "$COMMENT" "Ended: nothing Ready or Approved." nothing
has "$COMMENT" "Ready stories wait for /spec: #31" nothing
audit nothing

# loop
new_case; board board-loop.tsv
script "status:11:Review pr:101:OPEN:11 cost:0.50 turns:4 dur:1234" "status:21:Done pr:121:MERGED:21 cost:1.25 turns:5 dur:2345" "status:22:Done pr:122:MERGED:22 cost:1.25 turns:6 dur:3456"
drive
want_code 0 loop
[ "$(sed -n 1p "$CLAUDE_LOG")" = "$FIX" ] || fail "loop: first call: $(sed -n 1p "$CLAUDE_LOG")"
[ "$(sed -n 2p "$CLAUDE_LOG")" = "-p /nightmill:next 21 $FLAGS" ] || fail "loop: second call: $(sed -n 2p "$CLAUDE_LOG")"
[ "$(sed -n 3p "$CLAUDE_LOG")" = "-p /nightmill:next 22 $FLAGS" ] || fail "loop: third call: $(sed -n 3p "$CLAUDE_LOG")"
[ "$(calls)" = 3 ] || fail "loop: $(calls) claude calls, 3 expected"
has "$COMMENT" "| #11 Crash on start | /fix all | Ready | Review | pull request open | #101 |" loop
has "$COMMENT" "| #21 Add export | /next | Approved | Done | merged | #121 |" loop
has "$COMMENT" "| #22 Add import | /next | Approved | Done | merged | #122 |" loop
has "$COMMENT" "Picked 3, merged 2, pull request open 1, blocked 0, not started 0." loop
has "$COMMENT" 'Cost: $3.00 in all' loop
has "$COMMENT" '1. /nightmill:fix all: exit 0, ' loop
has "$COMMENT" '$0.50, 4 turns.' loop
n=$(grep -c '<details><summary>Final message of ' "$COMMENT" || true)
[ "$n" = 3 ] || fail "loop: $n details blocks, 3 expected"
has "$COMMENT" "Processes: none left running." loop
has "$c/out.txt" "drive: summary posted to #9" loop
has "$c/out.txt" "drive: run files in " loop
hasnt "$COMMENT" "$tmp" "loop: the comment names a local path"
audit loop

# blocked
new_case; board board-loop.tsv
script "status:11:Review pr:101:OPEN:11" "status:21:In_progress stopped:the_check_is_red" "status:22:Done pr:122:MERGED:22"
drive
want_code 0 blocked
has "$COMMENT" "| #21 Add export | /next | Approved | In progress | blocked: Stopped: the check is red | - |" blocked
[ "$(sed -n 3p "$CLAUDE_LOG")" = "-p /nightmill:next 22 $FLAGS" ] || fail "blocked: #22 was not tried"
audit blocked

# tie
new_case; board board-tie.tsv; drive
want_code 0 tie
if [ -f "$CLAUDE_LOG" ] && grep -qF 'nightmill:next' "$CLAUDE_LOG"; then fail "tie: /next was called"; fi
has "$c/out.txt" "a tie of priorities among the Approved stories #21, #23 (High); the maintainer sets one higher" tie
has "$COMMENT" "a tie of priorities among the Approved stories #21, #23 (High); the maintainer sets one higher" tie
audit tie

# tried once
new_case; board board-loop.tsv; script "cost:0.10"; drive
want_code 0 "tried once"
n=$(grep -cF 'nightmill:fix all' "$CLAUDE_LOG" || true)
[ "$n" = 1 ] || fail "tried once: /fix all ran $n times"
has "$COMMENT" "nothing new to pick: every Ready bug and Approved story left was tried in this run" "tried once"
has "$COMMENT" "| /fix all | Ready | Ready | not started" "tried once"
audit "tried once"

# time limit
new_case '"unattended": { "summaryIssue": 9, "maxMinutes": 1 }'; board board-loop.tsv; script "clock:+61"; drive
want_code 0 "time limit"; [ "$(calls)" = 1 ] || fail "time limit: $(calls) claude calls, 1 expected"
has "$COMMENT" "the time limit of 1 minutes (unattended.maxMinutes) is reached" "time limit"
audit "time limit"

# kill switch
new_case; board board-loop.tsv; touch "$main/.git/nightmill-stop"; drive
want_code 1 "kill switch"; [ "$(calls)" = 0 ] || fail "kill switch: claude was called"
has "$c/err.txt" "drive: cannot start: the kill switch is set (.git/nightmill-stop)" "kill switch"
has "$COMMENT" "Did not start: " "kill switch"
audit "kill switch"

# kill switch later
new_case; board board-loop.tsv; script "stop"; drive
want_code 0 "kill switch later"; [ "$(calls)" = 1 ] || fail "kill switch later: $(calls) claude calls, 1 expected"
has "$COMMENT" "the kill switch is set (.git/nightmill-stop)" "kill switch later"
rm -f "$main/.git/nightmill-stop"
audit "kill switch later"

# no slot
new_case "" 1; board board-loop.tsv
(cd "$main" && PATH="$tmp/bin:$PATH" GH_LOG=/dev/null bash "$here/scripts/slot.sh" --take feat/held --skip-warmup >/dev/null 2>&1) || fail "no slot: the setup take failed"
drive
want_code 1 "no slot"; [ "$(calls)" = 0 ] || fail "no slot: claude was called"
has "$c/err.txt" "drive: cannot start: no free slot: all 1 slots are busy (1: " "no slot"
audit "no slot"

# no room: a copy of scripts/ whose room.sh exits 3
new_case "" 2 true; board board-loop.tsv
cp -R "$here/scripts" "$c/scripts"
printf '#!/usr/bin/env bash\necho "room: gave up after 1 minutes (stub)"\nexit 3\n' > "$c/scripts/room.sh"
chmod +x "$c/scripts/room.sh"
drive "$c/scripts/drive.sh"
want_code 1 "no room"; [ "$(calls)" = 0 ] || fail "no room: claude was called"
has "$c/err.txt" "drive: cannot start: no room on this machine: " "no room"
audit "no room"

# lock
new_case; board board-loop.tsv
printf '%s\n2026-11-10T00:00:00Z\n' "$$" > "$main/.git/nightmill-drive.lock"
drive
want_code 1 lock; [ "$(calls)" = 0 ] || fail "lock: claude was called"
has "$c/err.txt" "drive: cannot start: another driver runs for this repository (pid $$, since " lock
[ -f "$main/.git/nightmill-drive.lock" ] || fail "lock: the other driver's lock was removed"
rm -f "$main/.git/nightmill-drive.lock"

# stale lock
new_case; board board-nothing.tsv
sleep 0.1 & dead=$!; wait "$dead"
printf '%s\n2026-11-10T00:00:00Z\n' "$dead" > "$main/.git/nightmill-drive.lock"
drive
want_code 0 "stale lock"
has "$c/out.txt" "drive: removed a stale lock of pid $dead" "stale lock"
audit "stale lock"

# bad limit
bad_limit() { # bad_limit <unattended members> <message>
  new_case "\"unattended\": { $1 }"; board board-loop.tsv; drive
  want_code 2 "bad limit ($1)"
  has "$c/err.txt" "$2" "bad limit ($1)"
  [ ! -s "$GH_LOG" ] || fail "bad limit ($1): gh was called"
  [ ! -e "$COMMENT" ] || fail "bad limit ($1): a comment was posted"
}
bad_limit '"maxMinutes": 0' "drive: unattended.maxMinutes must be a whole number from 1 to 1440, got 0"
bad_limit '"maxMinutes": "60"' 'drive: unattended.maxMinutes must be a whole number from 1 to 1440, got "60"'
bad_limit '"summaryIssue": 0' "drive: unattended.summaryIssue must be a whole number of at least 1, got 0"

# dirty
new_case; board board-loop.tsv; : > "$main/stray.txt"; drive
want_code 1 dirty; [ "$(calls)" = 0 ] || fail "dirty: claude was called"
has "$c/err.txt" "drive: cannot start: the main checkout is not on main with a clean tree" dirty

# gh
new_case; board board-loop.tsv; export GH_AUTH_FAIL=1; drive
want_code 1 gh; [ "$(calls)" = 0 ] || fail "gh: claude was called"
has "$c/out.txt" "drive: summary not posted: gh is not signed in" gh
hasnt "$GH_LOG" "issue comment" gh

# claude fails
new_case; board board-loop.tsv; script "exit:3"; drive
want_code 1 "claude fails"
has "$c/out.txt" "claude exited 3 in /nightmill:fix all" "claude fails"
has "$COMMENT" "claude exited 3 in /nightmill:fix all" "claude fails"
audit "claude fails"

# no issue
new_case '"unattended": { "maxMinutes": 60 }'; board board-nothing.tsv; drive
want_code 0 "no issue"
has "$c/out.txt" "drive: summary not posted: unattended.summaryIssue is not set" "no issue"
has "$c/out.txt" "nightmill driver run" "no issue: the summary is on stdout"
hasnt "$GH_LOG" "issue comment" "no issue"

# comment fails
new_case; board board-nothing.tsv; export GH_COMMENT_FAIL=1; drive
want_code 1 "comment fails"
has "$c/out.txt" "drive: summary not posted: fake gh: comment refused" "comment fails"

# left behind
new_case; board board-loop.tsv; script "bg status:11:Review pr:101:OPEN:11"; drive
want_code 0 "left behind"
bgpid=$(cat "$BGPID")
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$bgpid" 2>/dev/null || break; sleep 0.5; done
if kill -0 "$bgpid" 2>/dev/null; then kill "$bgpid" 2>/dev/null; fail "left behind: the step's background process is still alive"; fi
has "$COMMENT" "Processes: 1 left behind by a step were ended; none left running." "left behind"
audit "left behind"

# signal: TERM to the driver while the step sleeps
new_case; board board-loop.tsv; script "hang"
(cd "$main" && PATH="$tmp/bin:$PATH" exec bash "$D") > "$c/out.txt" 2> "$c/err.txt" &
dpid=$!
for _ in $(seq 1 40); do [ -s "$BGPID" ] && break; sleep 0.25; done
[ -s "$BGPID" ] || { kill "$dpid" 2>/dev/null; fail "signal: the step never started"; }
kill -TERM "$dpid"
wait "$dpid"; code=$?
want_code 143 signal
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do kill -0 "$(cat "$BGPID")" 2>/dev/null || break; sleep 0.5; done
if kill -0 "$(cat "$BGPID")" 2>/dev/null; then kill "$(cat "$BGPID")"; fail "signal: the step's process is still alive"; fi
has "$COMMENT" "Ended: stopped by SIGTERM." signal
audit signal

# long
new_case; board board-loop.tsv; script "long status:11:Review pr:101:OPEN:11"; drive
want_code 0 long
sz=$(wc -c < "$COMMENT" | tr -d ' ')
[ "$sz" -le 60000 ] || fail "long: the comment has $sz characters, 60000 at most"
has "$COMMENT" "[cut: " long

# ---------- iteration 53 (#165): the flags, the run ledger, the pause flag and the limits ----------

# run_lines: the run lines of the ledger of this case
run_lines() { awk -F'\t' '$1 == "run"' "$LEDGER" 2>/dev/null; }
# field <line> <n>
field() { printf '%s\n' "$1" | awk -F'\t' -v n="$2" '{ print $n }'; }
# loop_flags: the loop of iteration 52 (bug #11, stories #21, #22) with the numbers of each step
loop_script() { script "status:11:Review pr:101:OPEN:11 cost:0.50 turns:4 dur:1234" "status:21:Done pr:121:MERGED:21 cost:1.25 turns:5 dur:2345" "status:22:Done pr:122:MERGED:22 cost:1.25 turns:6 dur:3456"; }

# flags
new_case; board board-loop.tsv; loop_script; drive
want_code 0 flags
[ "$(sed -n 1p "$CLAUDE_LOG")" = "-p /nightmill:fix all $FLAGS" ] || fail "flags: first call: $(sed -n 1p "$CLAUDE_LOG")"
[ "$(sed -n 2p "$CLAUDE_LOG")" = "-p /nightmill:next 21 $FLAGS" ] || fail "flags: second call: $(sed -n 2p "$CLAUDE_LOG")"
[ "$(sed -n 3p "$CLAUDE_LOG")" = "-p /nightmill:next 22 $FLAGS" ] || fail "flags: third call: $(sed -n 3p "$CLAUDE_LOG")"
[ "$(sed -n 1p "$ENV_LOG" | sed 's/ started=.*//')" = "left=10" ] || fail "flags: step 1 left: $(sed -n 1p "$ENV_LOG")"
[ "$(sed -n 2p "$ENV_LOG" | sed 's/ started=.*//')" = "left=9" ] || fail "flags: step 2 left: $(sed -n 2p "$ENV_LOG")"
[ "$(sed -n 3p "$ENV_LOG" | sed 's/ started=.*//')" = "left=8" ] || fail "flags: step 3 left: $(sed -n 3p "$ENV_LOG")"
while IFS= read -r l; do
  case "$l" in *" started=") fail "flags: NIGHTMILL_RUN_STARTED not set: $l" ;; esac
  v=${l##*started=}
  case "$v" in ''|*[!0-9]*) fail "flags: NIGHTMILL_RUN_STARTED is not seconds: $l" ;; esac
done < "$ENV_LOG"
audit flags

# ledger
new_case; board board-loop.tsv; loop_script; drive
want_code 0 ledger
[ -f "$LEDGER" ] || fail "ledger: $LEDGER was not written"
[ "$(run_lines | wc -l | tr -d ' ')" = 3 ] || fail "ledger: $(run_lines | wc -l | tr -d ' ') run lines, 3 expected"
n=1
for want in "1|/nightmill:fix all|11|1234|0.5|4" "2|/nightmill:next 21|21|2345|1.25|5" "3|/nightmill:next 22|22|3456|1.25|6"; do
  l=$(run_lines | sed -n "${n}p")
  [ "$(printf '%s\n' "$l" | awk -F'\t' '{ print NF }')" = 11 ] || fail "ledger: line $n has not 11 fields: $l"
  IFS='|' read -r w4 w5 w6 w9 w10 w11 <<<"$want"
  [ "$(field "$l" 4)" = "$w4" ] || fail "ledger: line $n field 4: $(field "$l" 4), $w4 expected"
  [ "$(field "$l" 5)" = "$w5" ] || fail "ledger: line $n field 5: $(field "$l" 5), $w5 expected"
  [ "$(field "$l" 6)" = "$w6" ] || fail "ledger: line $n field 6: $(field "$l" 6), $w6 expected"
  [ "$(field "$l" 7)" = ok ] || fail "ledger: line $n field 7: $(field "$l" 7), ok expected"
  [ "$(field "$l" 9)" = "$w9" ] || fail "ledger: line $n field 9: $(field "$l" 9), $w9 expected"
  awk -v a="$(field "$l" 10)" -v b="$w10" 'BEGIN { exit !(a != "" && a + 0 == b + 0) }' || fail "ledger: line $n field 10: $(field "$l" 10), $w10 expected"
  [ "$(field "$l" 11)" = "$w11" ] || fail "ledger: line $n field 11: $(field "$l" 11), $w11 expected"
  for f in 2 3 8; do
    [[ "$(field "$l" $f)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || fail "ledger: line $n field $f is not a UTC stamp: $(field "$l" $f)"
  done
  n=$((n + 1))
done
[ "$(run_lines | awk -F'\t' '{ print $3 }' | sort -u | wc -l | tr -d ' ')" = 1 ] || fail "ledger: field 3 differs between the lines of one driver run"
audit ledger

# ledger when claude fails: a line is written for the failed step too
new_case; board board-loop.tsv; script "exit:3"; drive
want_code 1 "ledger on failure"
[ "$(run_lines | wc -l | tr -d ' ')" = 1 ] || fail "ledger on failure: $(run_lines | wc -l | tr -d ' ') run lines, 1 expected"
[ "$(field "$(run_lines)" 7)" = "exit 3" ] || fail "ledger on failure: field 7 is $(field "$(run_lines)" 7), 'exit 3' expected"

# paused: the first step commits and pushes the pause
new_case; board board-loop.tsv; script "pause"; drive
want_code 0 paused
[ "$(calls)" = 1 ] || fail "paused: $(calls) claude calls, 1 expected"
has "$COMMENT" "paused: limits.paused is true on origin/HEAD:.claude/nightmill.json" paused
audit paused

# paused at start
new_case '"unattended": { "summaryIssue": 9, "maxMinutes": 60 }, "limits": { "paused": true }'; board board-loop.tsv; drive
want_code 1 "paused at start"; [ "$(calls)" = 0 ] || fail "paused at start: claude was called"
has "$c/err.txt" "drive: cannot start: paused: " "paused at start"
audit "paused at start"

# issue limit
new_case '"unattended": { "summaryIssue": 9, "maxMinutes": 60 }, "limits": { "issuesPerRun": 2 }'; board board-loop.tsv; loop_script; drive
want_code 0 "issue limit"; [ "$(calls)" = 2 ] || fail "issue limit: $(calls) claude calls, 2 expected"
has "$COMMENT" "the issue limit of 2 per run (limits.issuesPerRun) is reached" "issue limit"
audit "issue limit"

# breach_case <name> <step 2 tokens>: a breach of #21 ends one issue and not the run
breach_check() { # breach_check <name> <reason start> <ledger ended>
  want_code 0 "$1"
  has "$COMMENT.21" "Stopped by a limit: $2" "$1"
  has "$GH_LOG" "issue edit 21 --add-label blocked" "$1"
  has "$COMMENT" "| #21 Add export | /next | Approved | In progress | blocked: $2" "$1"
  [ "$(sed -n 3p "$CLAUDE_LOG")" = "-p /nightmill:next 22 $FLAGS" ] || fail "$1: #22 was not tried"
  hasnt "$COMMENT" "claude exited" "$1"
  [ "$(field "$(run_lines | sed -n 2p)" 7)" = "$3" ] || fail "$1: ledger field 7 of step 2 is $(field "$(run_lines | sed -n 2p)" 7), $3 expected"
  audit "$1"
}
for code in 0 1; do
  new_case; board board-loop.tsv
  script "status:11:Review pr:101:OPEN:11" "status:21:In_progress subtype:error_max_turns exit:$code" "status:22:Done pr:122:MERGED:22"
  drive
  breach_check "max turns (exit $code)" "the headless run reached its turn limit of 200" max-turns
  has "$COMMENT" "(limits.turnsPerRole.session" "max turns (exit $code)"
  has "$COMMENT" "2. /nightmill:next 21: exit $code, " "max turns (exit $code): the step line shows the exit code"
  has "$COMMENT" "Picked 3, merged 1, pull request open 1, blocked 1" "max turns (exit $code)"
done

# budget
for code in 0 1; do
  new_case; board board-loop.tsv
  script "status:11:Review pr:101:OPEN:11" "status:21:In_progress subtype:error_max_budget_usd exit:$code" "status:22:Done pr:122:MERGED:22"
  drive
  breach_check "budget (exit $code)" 'the headless run reached its budget of $25.00' max-budget
  has "$COMMENT" "(limits.costPerIssueUsd" "budget (exit $code)"
done

# limit at Review: a step ended by a limit labels an item that is at Review too
new_case; board board-loop.tsv
script "status:11:Review pr:101:OPEN:11 subtype:error_max_budget_usd exit:1" "status:21:Review pr:121:OPEN:21 subtype:error_max_turns exit:1" "status:22:Done pr:122:MERGED:22"
drive
want_code 0 "limit at Review"
has "$COMMENT.11" "Stopped by a limit: the headless run reached its budget of" "limit at Review"
has "$GH_LOG" "issue edit 11 --add-label blocked" "limit at Review"
has "$COMMENT.21" "Stopped by a limit: the headless run reached its turn limit of 200" "limit at Review"
has "$GH_LOG" "issue edit 21 --add-label blocked" "limit at Review"
has "$COMMENT" "| #11 Crash on start | /fix all | Ready | Review | blocked: " "limit at Review"
has "$COMMENT" "| #21 Add export | /next | Approved | Review | blocked: " "limit at Review"
audit "limit at Review"

# spent: the ledger already holds $25.00 for #21 (20.00, and half of 10.00)
spent_ledger() {
  mkdir -p "$c/wt/.slots"
  printf 'run\t2026-11-09T06:30:00Z\t2026-11-09T06:00:00Z\t1\t/nightmill:next 21\t21\tok\t2026-11-09T06:00:10Z\t1800000\t20.00\t30\n' > "$LEDGER"
  printf 'run\t2026-11-09T06:50:00Z\t2026-11-09T06:00:00Z\t2\t/nightmill:fix all\t21,22\tok\t2026-11-09T06:31:00Z\t1200000\t10.00\t45\n' >> "$LEDGER"
}
new_case; board board-loop.tsv; spent_ledger
script "status:11:Review pr:101:OPEN:11" "status:22:Done pr:122:MERGED:22"
drive
want_code 0 spent
if grep -qF 'nightmill:next 21' "$CLAUDE_LOG"; then fail "spent: /next 21 was called"; fi
has "$COMMENT.21" 'Stopped by a limit: #21 has spent $25.00' spent
has "$GH_LOG" "issue edit 21 --add-label blocked" spent
has "$COMMENT" '| blocked: limit: #21 has spent $25.00' spent
# #22 had $5.00 of the shared run: its budget is what is left of the 25.00
[ "$(sed -n 2p "$CLAUDE_LOG")" = "-p /nightmill:next 22 --permission-mode manual --output-format json --max-turns 200 --max-budget-usd 20.00" ] || fail "spent: the call of #22: $(sed -n 2p "$CLAUDE_LOG")"
audit spent

# comment once
new_case; board board-loop.tsv; spent_ledger
printf '{"comments":[{"author":{"login":"agent"},"body":"Stopped by a limit: #21 has spent $25.00 in headless runs; the limit is $25.00 (limits.costPerIssueUsd). Labelled blocked; the board status (Approved) and the work (nothing) are left as they are for the maintainer."}]}\n' > "$c/comments.json"
export ISSUE_COMMENTS="$c/comments.json"
script "status:11:Review pr:101:OPEN:11" "status:22:Done pr:122:MERGED:22"
drive
want_code 0 "comment once"
[ ! -e "$COMMENT.21" ] || fail "comment once: a second comment was posted on #21"
has "$GH_LOG" "issue edit 21 --add-label blocked" "comment once"
audit "comment once"

# epic paused
new_case; board board-loop.tsv; export EPIC_FOR=21
script "status:11:Review pr:101:OPEN:11" "status:22:Done pr:122:MERGED:22"
drive
want_code 0 "epic paused"
if grep -qF 'nightmill:next 21' "$CLAUDE_LOG"; then fail "epic paused: /next 21 was called"; fi
[ ! -e "$COMMENT.21" ] || fail "epic paused: a comment was posted on #21"
hasnt "$GH_LOG" "issue edit" "epic paused"
has "$COMMENT" "not started: paused: epic #5 has the label paused" "epic paused"
audit "epic paused"
unset EPIC_FOR

echo "smoke-drive.sh: ok"
