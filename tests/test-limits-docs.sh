#!/usr/bin/env bash
# tests/test-limits-docs.sh - the pause flag and the limits are wired (iteration 53, #165;
# docs/specs/iteration-53-run-limits.md, "Tests"). Parts K (the keys), G (the gate in the skills), D (the driver),
# R (the README).
#   tests/test-limits-docs.sh [<root>]   # root: the checkout to read (default: this one)
set -euo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
bad=0
fail() { echo "FAIL: $*" >&2; bad=1; }
readme="$root/README.md"
schema="$root/schema/nightmill.schema.json"
example="$root/templates/nightmill.example.json"

# entry <file> <key>: the lines of the first object "<key>": { ... } of the file, closed by brace counting (quoted
# strings are not counted). awk reads the whole input (no early exit).
entry() {
  awk -v k="$2" '
    !s && index($0, "\"" k "\": {") { s = 1 }
    s && !d {
      print
      t = $0; gsub(/"([^"\\]|\\.)*"/, "", t)
      o = gsub(/\{/, "{", t); c = gsub(/\}/, "}", t)
      depth += o - c
      if (depth <= 0) d = 1
    }' "$1"
}
# sub_entry <text> <key>: the same on a text held in a variable
sub_entry() {
  local f
  f=$(mktemp "${TMPDIR:-/tmp}/nightmill-limits-docs.XXXXXX")
  printf '%s\n' "$1" > "$f"
  entry "$f" "$2"
  rm -f "$f"
}
flat() { tr '\n' ' ' | sed -E 's/ +/ /g'; }
# kv <flat text> <key> <value regex>
kv() { [[ "$1" =~ \"$2\":\ *$3([,\ \}]|$) ]]; }

# --- Part K ---
lim=""
if [ ! -f "$schema" ]; then
  fail "schema/nightmill.schema.json: missing"
else
  lim=$(entry "$schema" limits)
  [ -n "$lim" ] || fail "schema: no object limits"
fi
if [ -n "$lim" ]; then
  # a key's entry: type, optional minimum and maximum, default and a description
  check_key() { # check_key <block text> <label> <type> <min> <max> <default>
    local f
    f=$(printf '%s\n' "$1" | flat)
    [ -n "$f" ] || { fail "schema: $2 is missing"; return; }
    kv "$f" type "\"$3\"" || fail "schema: $2 is not of type $3"
    if [ -n "$4" ]; then kv "$f" minimum "$4" || fail "schema: $2 has no minimum $4"; fi
    if [ -n "$5" ]; then kv "$f" maximum "$5" || fail "schema: $2 has no maximum $5"; fi
    kv "$f" default "$6" || fail "schema: $2 has no default $6"
    [[ "$f" == *'"description":'* ]] || fail "schema: $2 has no description"
  }
  check_key "$(sub_entry "$lim" paused)" limits.paused boolean "" "" false
  check_key "$(sub_entry "$lim" minutesPerIssue)" limits.minutesPerIssue integer 1 1440 180
  check_key "$(sub_entry "$lim" issuesPerRun)" limits.issuesPerRun integer 1 100 10
  check_key "$(sub_entry "$lim" costPerIssueUsd)" limits.costPerIssueUsd number 0.01 10000 25
  tpr=$(sub_entry "$lim" turnsPerRole)
  [ -n "$tpr" ] || fail "schema: limits.turnsPerRole is missing"
  n=$(printf '%s\n' "$tpr" | grep -o '"type": *"integer"' | wc -l | tr -d ' ')
  [ "$n" = 8 ] || fail "schema: limits.turnsPerRole has $n integer keys, 8 expected"
  for pair in session=200 specWriter=150 specReviewer=80 tester=150 implementer=300 codeReviewer=80 fixer=200 worker=40; do
    k=${pair%=*}
    check_key "$(sub_entry "$tpr" "$k")" "limits.turnsPerRole.$k" integer 1 10000 "${pair#*=}"
  done
  f=$(printf '%s\n' "$lim" | flat)
  [[ "$f" == *'"description":'* ]] || fail "schema: limits has no description"
fi
if [ -f "$example" ]; then
  el=$(entry "$example" limits)
  if [ -z "$el" ]; then
    fail "templates/nightmill.example.json: no \"limits\""
  else
    ef=$(printf '%s\n' "$el" | flat)
    kv "$ef" paused false || fail "templates/nightmill.example.json: limits.paused is not false"
    kv "$ef" minutesPerIssue 180 || fail "templates/nightmill.example.json: limits.minutesPerIssue is not 180"
    kv "$ef" issuesPerRun 10 || fail "templates/nightmill.example.json: limits.issuesPerRun is not 10"
    kv "$ef" costPerIssueUsd 25 || fail "templates/nightmill.example.json: limits.costPerIssueUsd is not 25"
    for pair in session=200 specWriter=150 specReviewer=80 tester=150 implementer=300 codeReviewer=80 fixer=200 worker=40; do
      kv "$ef" "${pair%=*}" "${pair#*=}" || fail "templates/nightmill.example.json: limits.turnsPerRole.${pair%=*} is not ${pair#*=}"
    done
  fi
else
  fail "templates/nightmill.example.json: missing"
fi
row=$(grep -F '| `limits` |' "$readme" | head -1 || true)
if [ -z "$row" ]; then
  fail "README.md: no configuration table row starting | \`limits\` |"
else
  for k in paused minutesPerIssue turnsPerRole issuesPerRun costPerIssueUsd; do
    case "$row" in *"$k"*) ;; *) fail "README.md: the limits row lacks $k" ;; esac
  done
  # the defaults are the schema's
  for pair in minutesPerIssue=180 issuesPerRun=10 costPerIssueUsd=25; do
    k=${pair%=*}
    d=$(sub_entry "$lim" "$k" | flat | sed -n 's/.*"default": *\([0-9.]*\).*/\1/p')
    d=${d:-${pair#*=}}
    [[ "$row" =~ \`$k\`,\ default\ $d([^0-9]|$) ]] || fail "README.md: the limits row lacks '\`$k\`, default $d'"
  done
  d=$(sub_entry "$(sub_entry "$lim" turnsPerRole)" session | flat | sed -n 's/.*"default": *\([0-9]*\).*/\1/p')
  d=${d:-200}
  [[ "$row" =~ \`session\`\ $d([^0-9]|$) || "$row" =~ session\`?,\ default\ $d([^0-9]|$) ]] || fail "README.md: the limits row lacks the session default $d"
fi

# --- Part G ---
wf="$root/skills/workflow/SKILL.md"
if [ ! -f "$wf" ]; then
  fail "skills/workflow/SKILL.md: missing"
else
  grep -qF '**The pause and the limits**' "$wf" || fail "skills/workflow/SKILL.md: no heading **The pause and the limits**"
  for w in 'scripts/gate.sh' 'scripts/gate.ps1' 'Stopped: paused: ' 'Stopped: limit: ' 'Stopped by a limit: ' '--add-label blocked' 'tool_uses' 'limits.turnsPerRole is not checked'; do
    grep -qF -- "$w" "$wf" || fail "skills/workflow/SKILL.md: does not contain '$w'"
  done
  para=$(awk '/\*\*The pause and the limits\*\*/ { s = 1 } s { print }' "$wf")
  for n in 0 1 2 3 4; do
    if ! grep -qE "(exit( code)? ${n}([^0-9]|\$))|(\*\*${n}\*\*)|(\`${n}\`)|(^\| ${n} )|(^- ${n}[: ])" <<< "$para"; then
      fail "skills/workflow/SKILL.md: the paragraph does not name the exit code $n"
    fi
  done
fi
for sk in next fix spec check story control; do
  f="$root/skills/$sk/SKILL.md"
  if [ ! -f "$f" ]; then fail "skills/$sk/SKILL.md: missing"; continue; fi
  grep -qF '**The pause and the limits**' "$f" || fail "skills/$sk/SKILL.md: no **The pause and the limits**"
  grep -qF 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh"' "$f" || fail "skills/$sk/SKILL.md: no call bash \"\${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh\""
  grep -qF '${CLAUDE_PLUGIN_ROOT}/scripts/gate.ps1' "$f" || fail "skills/$sk/SKILL.md: no PowerShell call of gate.ps1"
done
if grep -qF 'once they exist' "$root/skills/fix/SKILL.md"; then fail "skills/fix/SKILL.md: still says 'once they exist'"; fi
for sk in status models; do
  if grep -qF 'gate.sh' "$root/skills/$sk/SKILL.md"; then fail "skills/$sk/SKILL.md: contains gate.sh (it does not gate)"; fi
done
ini="$root/skills/init/SKILL.md"
grep -qF '| `paused` | `FBCA04` |' "$ini" || fail "skills/init/SKILL.md: no label row for paused (FBCA04)"
grep -qF '`gate`' "$ini" || fail "skills/init/SKILL.md: group D does not name gate"
grep -qF '26 + 21' "$ini" || fail "skills/init/SKILL.md: the count is not 26 + 21"
if grep -qF '24 + 21' "$ini"; then fail "skills/init/SKILL.md: still says 24 + 21"; fi

# --- Part D ---
for f in scripts/drive.sh scripts/drive.ps1; do
  p="$root/$f"
  if [ ! -f "$p" ]; then fail "$f: missing"; continue; fi
  for w in '--max-turns' '--max-budget-usd' NIGHTMILL_RUN_STARTED NIGHTMILL_ISSUES_LEFT 'gate.' run; do
    grep -qF -- "$w" "$p" || fail "$f: does not contain '$w'"
  done
  case "$f" in
    *.sh) grep -qF ledger_append "$p" || fail "$f: does not contain ledger_append" ;;
    *.ps1) grep -qiE 'ledger.*append|append.*ledger|Ledger-Append|ledger\.ps1' "$p" || fail "$f: does not use the append of ledger.ps1" ;;
  esac
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    [[ "$l" == *"issue edit"*"--add-label blocked"* ]] || fail "$f: an 'issue edit' without --add-label blocked on its line: $l"
  done < <(grep -F 'issue edit' "$p" || true)
done

# --- Part R ---
sec=$(awk '/^### Limits and the kill switch$/ { s = 1; print; next } s && /^##/ { exit } s { print }' "$readme")
for w in '.git/nightmill-stop' 'limits.paused' 'ledger.tsv' 'paused'; do
  case "$sec" in *"$w"*) ;; *) fail "README.md: '### Limits and the kill switch' lacks '$w'" ;; esac
done
if [[ "$sec" == *'are not there yet'* ]]; then fail "README.md: '### Limits and the kill switch' still says the limits are not there yet"; fi
grep -qF '| `scripts/gate.ps1`, `scripts/gate.sh` |' "$readme" || fail "README.md: no row of scripts/gate.ps1, scripts/gate.sh in the plugin table"
grep -qF 'bash tests/smoke-gate.sh' "$readme" || fail "README.md: no line of bash tests/smoke-gate.sh in Developing nightmill"
grep -qF 'tests/smoke-gate.ps1' "$readme" || fail "README.md: no line of tests/smoke-gate.ps1 in Developing nightmill"
sm=$(awk '/^## Security model$/ { s = 1; print; next } s && /^## / { exit } s { print }' "$readme" | flat)
[[ "$sm" == *'enforced by scripts/gate.*'* ]] || fail "README.md: the Security model row of the limits is not 'enforced by scripts/gate.*'"
if grep -qF 'not enforced yet | [#165]' "$readme"; then fail "README.md: the #165 row of the Security model still says 'not enforced yet'"; fi
flatreadme=$(flat < "$readme")
[[ "$flatreadme" == *'a pause flag for every run comes with'* ]] && fail "README.md: When a run is stopped still says 'a pause flag for every run comes with'"
[[ "$flatreadme" == *'`paused`'* ]] || fail "README.md: the label paused is not mentioned"
[[ "$flatreadme" == *'ledger.tsv'*'run'* ]] || true

exit "$bad"
