#!/usr/bin/env bash
# tests/test-render-quoting.sh - regression for bug #135: render-templates.sh must quote and escape
# areas and labels in the issue forms like it does invariants, for `,` `:` `#` and `"`.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
R="$here/scripts/render-templates.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$tmp/.claude"

cat > "$tmp/.claude/nightmill.json" <<'JSON'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "areas": ["ui, web", "api: v2", "#tag", "say \"hi\""],
  "invariants": ["Keep it simple"],
  "labels": { "story": "feat: \"new\"", "bug": "bug #1, urgent", "epic": "big \"epic\"", "needsSpec": "needs \"spec\"" },
  "verification": { "check": "make check" }
}
JSON

bash "$R" --project "$tmp" >/dev/null
d="$tmp/.github/ISSUE_TEMPLATE"
want='options: ["ui, web", "api: v2", "#tag", "say \"hi\""]'
grep -qF "$want" "$d/story.yml" || fail "story.yml areas not quoted and escaped: $(grep 'options:' "$d/story.yml")"
grep -qF "$want" "$d/bug.yml" || fail "bug.yml areas not quoted and escaped: $(grep 'options:' "$d/bug.yml")"
grep -qxF 'labels: ["feat: \"new\"", "needs \"spec\""]' "$d/story.yml" || fail "story labels not escaped: $(grep '^labels:' "$d/story.yml")"
grep -qxF 'labels: ["bug #1, urgent"]' "$d/bug.yml" || fail "bug label not quoted: $(grep '^labels:' "$d/bug.yml")"
grep -qxF 'labels: ["big \"epic\""]' "$d/epic.yml" || fail "epic label not escaped: $(grep '^labels:' "$d/epic.yml")"
echo "RENDER QUOTING OK"
