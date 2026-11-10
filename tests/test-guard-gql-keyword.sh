#!/usr/bin/env bash
# tests/test-guard-gql-keyword.sh - iteration 50 (#253): only the first name of a GraphQL definition is its keyword,
# so an operation named after a keyword does not change its kind. `mutation query { deleteIssue }` is refused and
# `query mutation { viewer }` passes, in scripts/guard.sh and, when a PowerShell is on the PATH, scripts/guard.ps1.
#   tests/test-guard-gql-keyword.sh [<root>]   # root: the checkout to test (default: this one)
set -uo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-test-guard-gql.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
bad=0
fail() { echo "FAIL: $*" >&2; bad=1; }

mkdir -p "$tmp/bin" "$tmp/proj/.claude"
printf '%s\n' '{ "github": { "owner": "o", "projectNumber": 7 } }' > "$tmp/proj/.claude/nightmill.json"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$tmp/bin/gh"
chmod +x "$tmp/bin/gh"

# event <graphql document>: the hook event of a Bash call gh api graphql -f query='<doc>' (no quote or backslash in doc)
event() {
  local cmd="gh api graphql -f query='$1'"
  cmd=${cmd//\"/\\\"}
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$cmd" "$tmp"
}

# expect <shell label> <name> <exit code> <document> <runner...>
expect() {
  local label=$1 name=$2 want=$3 doc=$4 code err
  shift 4
  err=$(event "$doc" | CLAUDE_PROJECT_DIR="$tmp/proj" PATH="$tmp/bin:$PATH" "$@" 2>&1 >/dev/null)
  code=$?
  [ "$code" = "$want" ] || fail "$label: $name: expected exit $want, got $code ($err)"
  if [ "$want" = 2 ]; then
    case "$err" in *"deleteIssue"*) ;; *) fail "$label: $name: the refusal does not name deleteIssue: $err" ;; esac
  fi
}

REFUSED='mutation query { deleteIssue(input: {issueId: "x"}) { clientMutationId } }'
PASSED='query mutation { viewer { login } }'
SUBFRAG='mutation subscription { deleteIssue(input: {issueId: "x"}) { clientMutationId } } fragment mutation on User { login }'

run_sh() { expect bash "$@" bash "$root/scripts/guard.sh"; }
run_sh "mutation named query" 2 "$REFUSED"
run_sh "query named mutation" 0 "$PASSED"
run_sh "mutation named subscription" 2 "$SUBFRAG"

ps=""
if command -v powershell >/dev/null 2>&1; then ps=powershell
elif command -v pwsh >/dev/null 2>&1; then ps=pwsh
fi
if [ -n "$ps" ]; then
  run_ps() { expect "$ps" "$@" "$ps" -NoProfile -ExecutionPolicy Bypass -File "$root/scripts/guard.ps1"; }
  run_ps "mutation named query" 2 "$REFUSED"
  run_ps "query named mutation" 0 "$PASSED"
  run_ps "mutation named subscription" 2 "$SUBFRAG"
else
  echo "test-guard-gql-keyword: no PowerShell on the PATH, scripts/guard.ps1 not run"
fi

[ "$bad" = 0 ] || exit 1
echo "GUARD GQL KEYWORD OK"
