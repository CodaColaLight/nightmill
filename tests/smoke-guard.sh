#!/usr/bin/env bash
# tests/smoke-guard.sh - scripts/guard.sh (the PreToolUse guard hook, iteration 47, #110): refuses a board status
# edit to Ready or Approved, any merge without --auto, --admin, a force push and a push to the base branch; exit 2
# and one line on stderr for a refusal, exit 0 and no output for everything else. A stub gh is first on the PATH.
# Needs no jq and no network.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
G="$here/scripts/guard.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-guard.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$G" ] || fail "scripts/guard.sh does not exist"

TAB=$(printf '\t')
mkdir -p "$tmp/bin" "$tmp/proj/.claude" "$tmp/trunk/.claude" "$tmp/bare"
cat > "$tmp/proj/.claude/nightmill.json" <<'JSON'
{ "github": { "owner": "o", "projectNumber": 7 } }
JSON
cat > "$tmp/trunk/.claude/nightmill.json" <<'JSON'
{ "github": { "owner": "o", "projectNumber": 7 }, "git": { "baseBranch": "trunk" } }
JSON
cat > "$tmp/bin/gh" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$tmp/gh.log"
if [ "\${1:-}" = project ] && [ "\${2:-}" = field-list ]; then
  [ -e "$tmp/gh.fail" ] && { echo "stub failure" >&2; exit 1; }
  printf 'Ready\tRID1\n'
  printf 'Approved\tAID2\n'
  exit 0
fi
exit 0
STUB
chmod +x "$tmp/bin/gh"
: > "$tmp/gh.log"

# jstr <text>: the text as a JSON string body (backslash, quote, newline, tab)
jstr() {
  local s=$1
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# run_guard <project dir> <stdin text>: sets code and err
run_guard() {
  local errf="$tmp/err.txt"
  CLAUDE_PROJECT_DIR=$1 PATH="$tmp/bin:$PATH" bash "$G" <<< "$2" > "$tmp/out.txt" 2> "$errf"
  code=$?
  err=$(cat "$errf")
  out=$(cat "$tmp/out.txt")
}

# check <name> <tool> <command> <exit code> [stderr text] (project dir: $proj)
proj="$tmp/proj"
check() {
  local ev
  ev='{"tool_name":"'$2'","tool_input":{"command":"'$(jstr "$3")'"},"cwd":"'$tmp'"}'
  run_guard "$proj" "$ev"
  [ "$code" = "$4" ] || fail "$1: expected exit $4, got $code (stderr: $err)"
  if [ "$4" = 0 ]; then
    [ -z "$err" ] || fail "$1: expected no stderr, got: $err"
    [ -z "$out" ] || fail "$1: expected no output, got: $out"
  else
    case "$err" in "nightmill guard: refused: "*) ;; *) fail "$1: not a guard line: $err";; esac
    [ "$(printf '%s\n' "$err" | grep -c .)" = 1 ] || fail "$1: expected one stderr line, got: $err"
    [ -z "${5:-}" ] || case "$err" in *"$5"*) ;; *) fail "$1: stderr lacks '$5': $err";; esac
  fi
}
B() { check "$1" Bash "$2" "$3" "${4:-}"; }

NOAUTO="a merge without --auto."
echo "== a merge needs --auto"
B "merge auto" 'gh pr merge 5 --auto --squash' 0
B "merge squash" 'gh pr merge 5 --squash' 2 "$NOAUTO"
B "merge bare" 'gh pr merge 5' 2 "$NOAUTO"
B "merge with -R" 'gh -R o/r pr merge 5 --squash' 2 "$NOAUTO"
B "disable auto" 'gh pr merge 5 --disable-auto' 0
B "rest merge" 'gh api -X PUT repos/o/r/pulls/5/merge' 2 "a merge through gh api."
B "graphql merge" 'gh api graphql -f query='"'"'mutation { mergePullRequest(input: {pullRequestId: "x"}) { clientMutationId } }'"'" 2 "a merge through gh api."
B "graphql auto merge" 'gh api graphql -f query='"'"'mutation { enablePullRequestAutoMerge(input: {pullRequestId: "x"}) { clientMutationId } }'"'" 0
B "merge after status" 'git status && gh pr merge 5 --squash' 2 "$NOAUTO"
B "commit message names a merge" 'git commit -m "gh pr merge 5 --squash"' 0

echo "== quotes"
B "double quoted semicolon" 'git commit -m "x; gh pr merge 5 --squash"' 0
B "single quoted operators" "git commit -m 'a && gh pr merge 5 | b'" 0
B "escaped quote" 'git commit -m "a \" ; gh pr merge 5"' 0
B "merge then quoted semicolon" 'gh pr merge 5 --squash; echo "a;b"' 2 "$NOAUTO"
B "command substitution" 'echo "$(gh pr merge 5 --squash)"' 2 "$NOAUTO"
check "powershell tool, quoted merge" PowerShell 'git commit -m "x; gh pr merge 5"' 0

echo "== --admin"
B "admin next to auto" 'gh pr merge 5 --auto --admin --squash' 2 "gh pr merge with --admin."

echo "== force push and push to the base branch"
B "force slot form" 'git -C /w/slot-1 push --force origin feat/5-x' 2 "a force push."
B "force short" 'git -C /w/slot-1 push -f origin feat/5-x' 2 "a force push."
B "force cluster" 'git push -uf origin feat/5-x' 2 "a force push."
B "force plus refspec" 'git -C /w/slot-1 push origin +feat/5-x' 2 "a force push."
B "push main" 'git -C /w/slot-1 push origin main' 2 "a push to main."
B "push full ref" 'git -C /w/slot-1 push origin HEAD:refs/heads/main' 2 "a push to main."
B "push with -c" 'git -c x=y push origin HEAD:main' 2 "a push to main."
B "push branch" 'git -C /w/slot-1 push -u origin feat/5-x' 0
B "branch ending in main" 'git push -u origin feat/5-main' 0
B "stash push with free text" 'git -C /w/slot-1 stash push --include-untracked -m "Unmet tests for #5: push main -f +x --force" -- t.sh' 0
B "stash push plain" 'git stash push --include-untracked -m "Tester files for #5: push to main -f" -- t.sh' 0
B "commit with free text" 'git -C /w/slot-1 commit -m "fix push --force to main; gh pr merge 5"' 0
proj="$tmp/trunk"
B "push trunk" 'git push origin trunk' 2 "a push to trunk."
B "push main when trunk is the base" 'git push origin main' 0
proj="$tmp/proj"

echo "== a status edit to Ready or Approved"
EDIT='gh project item-edit --id I --project-id P --field-id F --single-select-option-id'
: > "$tmp/gh.log"
B "item-edit Ready" "$EDIT RID1" 2 "setting Ready on the board."
B "item-edit Approved" "$EDIT AID2" 2 "setting Approved on the board."
B "item-edit Approved with =" 'gh project item-edit --id I --project-id P --field-id F --single-select-option-id=AID2' 2 "setting Approved on the board."
B "item-edit other status" "$EDIT SID3" 0
B "ids that contain an option id" 'gh project item-edit --id XRID1Y --project-id AID2X --single-select-option-id SID3' 0
B "graphql Approved" 'gh api graphql -f query='"'"'mutation {
  updateProjectV2ItemFieldValue(input: {projectId: "P", itemId: "I", fieldId: "F", value: {singleSelectOptionId:
  "AID2"}}) { clientMutationId } }'"'" 2 "setting Approved on the board."
B "graphql other ids" 'gh api graphql -f query='"'"'mutation { updateProjectV2ItemFieldValue(input: {projectId: "P", itemId: "XAID2", fieldId: "F", value: {singleSelectOptionId: "SID3"}}) { clientMutationId } }'"'" 0
: > "$tmp/gh.fail"
B "lookup fails" "$EDIT SID3" 2 "option ids could not be read"
rm -f "$tmp/gh.fail"

echo "== everything else"
: > "$tmp/gh.log"
B "no status edit" 'gh pr view 5' 0
[ ! -s "$tmp/gh.log" ] || fail "gh pr view: the guard called gh: $(cat "$tmp/gh.log")"
check "other tool" Edit 'gh pr merge 5 --squash' 0
check "powershell tool, merge" PowerShell 'gh pr merge 5 --squash' 2 "$NOAUTO"
run_guard "$proj" 'this is not json'
[ "$code" = 0 ] || fail "invalid JSON: expected exit 0, got $code"
[ -z "$err$out" ] || fail "invalid JSON: expected no output, got: $err$out"
run_guard "$tmp/bare" '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 5 --admin"}}'
[ "$code" = 0 ] || fail "no nightmill.json: expected exit 0, got $code"
[ -z "$err$out" ] || fail "no nightmill.json: expected no output, got: $err$out"

echo "== the command hooks/hooks.json wires"
cmd=$(grep '"command":' "$here/hooks/hooks.json" | grep 'guard.sh' | sed 's/^[^:]*: *"//; s/",* *$//; s/\\"/"/g')
[ -n "$cmd" ] || fail "hooks/hooks.json wires no guard.sh command"
cmd=${cmd//'${CLAUDE_PLUGIN_ROOT}'/$here}
ev='{"tool_name":"Bash","tool_input":{"command":"gh pr merge 5 --squash"},"cwd":"'$tmp'"}'
CLAUDE_PROJECT_DIR="$tmp/proj" PATH="$tmp/bin:$PATH" bash -c "$cmd" <<< "$ev" > /dev/null 2> "$tmp/err.txt"
code=$?
[ "$code" = 2 ] || fail "hooks.json command: expected exit 2, got $code"

echo "GUARD OK"
