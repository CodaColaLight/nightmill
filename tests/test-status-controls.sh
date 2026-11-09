#!/usr/bin/env bash
# tests/test-status-controls.sh - regression for #134: an issue title with terminal control characters (ESC, BEL,
# DEL, written as JSON \u escapes) must not reach the output of status.sh, in the table or with --porcelain.
# Same approach as smoke-status.sh: a fake gh answers from tests/fixtures/status-controls/. No network.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
S="$here/scripts/status.sh"
FIX="$here/tests/fixtures/status-controls"
fail() { echo "FAIL: $*" >&2; exit 1; }

git init -q -b main "$tmp/work"
mkdir -p "$tmp/work/.claude" "$tmp/bin"
cat > "$tmp/work/.claude/nightmill.json" <<'JSON'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "labels": { "epic": "epic" },
  "git": { "baseBranch": "main", "specPrefix": "spec/" }
}
JSON
cat > "$tmp/bin/gh" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "project item-list") cat "$GH_FIX/items.json" ;;
  "project view") echo '{"id": "PVT_test", "number": 1}' ;;
  "pr list") cat "$GH_FIX/prs.json" ;;
  "api graphql") cat "$GH_FIX/ages.json" ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$tmp/bin/gh"

check() { # check <name> [args]: run status.sh and look for control bytes
  local name=$1
  shift
  (cd "$tmp/work" && PATH="$tmp/bin:$PATH" GH_FIX="$FIX" NIGHTMILL_NOW=1793880000 bash "$S" "$@") > "$tmp/out.txt" 2> "$tmp/err.txt" \
    || fail "$name: exit code $?: $(cat "$tmp/err.txt")"
  grep -q 'RED' "$tmp/out.txt" || fail "$name: the title is not printed at all"
  # every C0 control except LF (and TAB, the porcelain separator), and DEL
  if LC_ALL=C grep -q "[$(printf '\001-\010\013-\037\177')]" "$tmp/out.txt"; then
    od -c "$tmp/out.txt" | head -5 >&2
    fail "$name: a control character from the title reached the output"
  fi
  grep -q 'x\[31mRED\]0;textend' "$tmp/out.txt" || fail "$name: the printable text of the title was not kept"
}

echo "== table: controls removed from the title"
check "table"
echo "== --porcelain: controls removed from the title"
check "porcelain" --porcelain
echo "ok"
