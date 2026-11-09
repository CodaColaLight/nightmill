#!/usr/bin/env bash
# tests/smoke-render.sh - render-templates.sh against a throwaway project: placeholders filled,
# areas, labels and invariants quoted (also with , : # and "), non-ASCII text intact, the no-invariants
# case drops the checkbox block, existing forms kept without --force.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
R="$here/scripts/render-templates.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$tmp/.claude"

cat > "$tmp/.claude/nightmill.json" <<'EOF'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "areas": ["core", "ui"],
  "invariants": ["Fog of war — nothing unseen is sent", "Quote \"this\" and `that`"],
  "labels": { "story": "feature" },
  "verification": { "check": "make check", "manualCheckText": "Open the app and click around" }
}
EOF

echo "== render"
bash "$R" --project "$tmp" >/dev/null
story="$tmp/.github/ISSUE_TEMPLATE/story.yml"
grep -qF 'options: ["core", "ui"]' "$story" || fail "areas not filled or not quoted"
grep -qF 'labels: ["feature", "needs-spec"]' "$story" || fail "labels not filled"
grep -qF -- '- label: "Fog of war — nothing unseen is sent"' "$story" || fail "non-ASCII invariant damaged or unquoted"
grep -qF -- '- label: "Quote \"this\" and `that`"' "$story" || fail "quotes not escaped"
! grep -q '{{' "$story" || fail "placeholder left"
! grep -q 'INVARIANTS_BEGIN' "$story" || fail "marker left"
grep -qF '`make check` green' "$story" || fail "check command not filled"
grep -qF 'Open the app and click around' "$story" || fail "manual check not filled"
grep -q 'Invariants the fix must respect' "$tmp/.github/ISSUE_TEMPLATE/bug.yml" || fail "bug form lost its invariants"
[ -f "$tmp/.github/ISSUE_TEMPLATE/config.yml" ] || fail "config.yml missing"

echo "== kept without --force"
echo "hand edited" > "$tmp/.github/ISSUE_TEMPLATE/epic.yml"
out=$(bash "$R" --project "$tmp")
grep -q 'kept .*epic.yml' <<<"$out" || fail "hand-edited form was not reported as kept: $out"
grep -q 'hand edited' "$tmp/.github/ISSUE_TEMPLATE/epic.yml" || fail "hand-edited form overwritten"
bash "$R" --project "$tmp" --force >/dev/null
! grep -q 'hand edited' "$tmp/.github/ISSUE_TEMPLATE/epic.yml" || fail "--force did not overwrite"

echo "== other forms in the folder are left alone"
echo "mine" > "$tmp/.github/ISSUE_TEMPLATE/nightmill-bug.yml"
bash "$R" --project "$tmp" --force >/dev/null
grep -qx 'mine' "$tmp/.github/ISSUE_TEMPLATE/nightmill-bug.yml" || fail "render-templates touched a form it does not own"
for f in epic story bug config; do [ -f "$tmp/.github/ISSUE_TEMPLATE/$f.yml" ] || fail "$f.yml was not written"; done

echo "== no invariants drops the block"
grep -v '"invariants"' "$tmp/.claude/nightmill.json" > "$tmp/cfg2.json" && mv "$tmp/cfg2.json" "$tmp/.claude/nightmill.json"
bash "$R" --project "$tmp" --force >/dev/null
! grep -q 'invariants' "$story" || fail "checkbox block not dropped"
! grep -q '{{' "$story" || fail "placeholder left after drop"

echo "== areas and labels with , : # and \" are quoted and escaped (bug #135)"
cat > "$tmp/.claude/nightmill.json" <<'EOF'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "areas": ["a, b", "c: d", "#e", "f \"g\""],
  "labels": { "story": "s: \"x\"", "bug": "b #1, y", "epic": "e, \"z\"" }
}
EOF
bash "$R" --project "$tmp" --force >/dev/null
d="$tmp/.github/ISSUE_TEMPLATE"
for f in story bug; do
  grep -qF 'options: ["a, b", "c: d", "#e", "f \"g\""]' "$d/$f.yml" || fail "$f.yml areas not quoted: $(grep 'options:' "$d/$f.yml")"
done
grep -qxF 'labels: ["s: \"x\"", "needs-spec"]' "$d/story.yml" || fail "story labels not quoted: $(grep '^labels:' "$d/story.yml")"
grep -qxF 'labels: ["b #1, y"]' "$d/bug.yml" || fail "bug label not quoted: $(grep '^labels:' "$d/bug.yml")"
grep -qxF 'labels: ["e, \"z\""]' "$d/epic.yml" || fail "epic label not quoted: $(grep '^labels:' "$d/epic.yml")"

echo "RENDER OK"
