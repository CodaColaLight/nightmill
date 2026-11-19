#!/usr/bin/env bash
# tests/smoke-render.sh - render-templates.sh against a throwaway project: placeholders filled,
# areas, labels and invariants quoted (also with , : # and "), non-ASCII text intact, the no-invariants
# case drops the checkbox block, existing forms kept without --force.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
R="$here/scripts/render-templates.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-render.XXXXXX")
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

echo "== control characters are escaped as json_quote does, not written raw (bug #227)"
cat > "$tmp/.claude/nightmill.json" <<'EOF'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "areas": ["a\nb\tc\u0001d"],
  "invariants": ["a\nb\tc\u0001d"],
  "labels": { "story": "a\nb\tc\u0001d" }
}
EOF
bash "$R" --project "$tmp" --force >/dev/null
for f in story bug; do
  grep -qF 'options: ["a\nb\tc\u0001d"]' "$d/$f.yml" || fail "$f.yml area with control characters not escaped: $(grep 'options:' "$d/$f.yml" | od -c | head -3)"
  grep -qxF '        - label: "a\nb\tc\u0001d"' "$d/$f.yml" || fail "$f.yml invariant with control characters not escaped"
done
grep -qxF 'labels: ["a\nb\tc\u0001d", "needs-spec"]' "$d/story.yml" || fail "story label with control characters not escaped"
# no raw control character other than the newline that ends a line may reach a form
if LC_ALL=C grep -q "$(printf '[\001-\010\013-\037]')" "$d/story.yml" "$d/bug.yml" "$d/epic.yml"; then fail "a raw control character was written into a form"; fi

echo "== every other escape matches json_quote byte for byte: CR, BS, FF, VT, 0x1f, and DEL ' < > & raw (bug #227)"
cat > "$tmp/.claude/nightmill.json" <<'EOF'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "areas": ["x\r\b\f\u000b\u001f\u007f'<>&\\y"],
  "invariants": ["x\r\b\f\u000b\u001f\u007f'<>&\\y"],
  "labels": { "story": "x\r\b\f\u000b\u001f\u007f'<>&\\y" }
}
EOF
bash "$R" --project "$tmp" --force >/dev/null
# json_quote writes \r \b \f, \u000b and \u001f (lower-case, four wide), and leaves DEL ' < > & raw
exp=$(printf '"x\\r\\b\\f\\u000b\\u001f\177'"'"'<>&\\\\y"')
for f in story bug; do
  grep -qF "options: [$exp]" "$d/$f.yml" || fail "$f.yml area is not quoted as json_quote does: $(grep 'options:' "$d/$f.yml" | od -c | head -4)"
  grep -qxF "        - label: $exp" "$d/$f.yml" || fail "$f.yml invariant is not quoted as json_quote does"
done
grep -qxF "labels: [$exp, \"needs-spec\"]" "$d/story.yml" || fail "story label is not quoted as json_quote does"
if LC_ALL=C grep -q "$(printf '[\001-\010\013-\037]')" "$d/story.yml" "$d/bug.yml" "$d/epic.yml"; then fail "a raw control character was written into a form"; fi

echo "== twins (#329): an empty label or manualCheckText takes the default"
cat > "$tmp/.claude/nightmill.json" <<'EOF2'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "areas": ["a"],
  "labels": { "epic": "", "story": "", "bug": "", "needsSpec": "" },
  "verification": { "check": "x", "manualCheckText": "" }
}
EOF2
bash "$R" --project "$tmp" --force >/dev/null
d="$tmp/.github/ISSUE_TEMPLATE"
[ "$(sed -n 4p "$d/epic.yml")" = 'labels: ["epic"]' ] || fail "epic.yml line 4 is not the default label: $(sed -n 4p "$d/epic.yml")"
[ "$(sed -n 4p "$d/story.yml")" = 'labels: ["story", "needs-spec"]' ] || fail "story.yml line 4 is not the default labels: $(sed -n 4p "$d/story.yml")"
[ "$(sed -n 4p "$d/bug.yml")" = 'labels: ["bug"]' ] || fail "bug.yml line 4 is not the default label: $(sed -n 4p "$d/bug.yml")"
grep -qxF '        - Manual check as the story describes' "$d/story.yml" || fail "story.yml has no default manual check line"
! grep -qxF '        - ' "$d/story.yml" || fail "story.yml has an empty manual check line"

echo "== twins (#329): invariants: only non-empty strings, newlines kept"
cat > "$tmp/.claude/nightmill.json" <<'EOF2'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "areas": ["a"],
  "invariants": ["one\ntwo", "ends\n", null, "", 5, true, {"k": "v"}, ["x"], "  last  "]
}
EOF2
bash "$R" --project "$tmp" --force >/dev/null
exp=$(printf '%s\n' '        - label: "one\ntwo"' '          required: false' '        - label: "ends\n"' '          required: false' '        - label: "  last  "' '          required: false')
for f in story bug; do
  got=$(grep -E '^( {8}- label: | {10}required: false$)' "$d/$f.yml" || true)
  [ "$got" = "$exp" ] || fail "$f.yml invariants are not the six expected lines: $got"
done
cat > "$tmp/.claude/nightmill.json" <<'EOF2'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "areas": ["a"],
  "invariants": [null, ""]
}
EOF2
bash "$R" --project "$tmp" --force >/dev/null
cp "$d/story.yml" "$tmp/story-nulls.yml"; cp "$d/bug.yml" "$tmp/bug-nulls.yml"
cat > "$tmp/.claude/nightmill.json" <<'EOF2'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "areas": ["a"]
}
EOF2
bash "$R" --project "$tmp" --force >/dev/null
cmp -s "$d/story.yml" "$tmp/story-nulls.yml" || fail "story.yml with only null and empty invariants differs from one without invariants"
cmp -s "$d/bug.yml" "$tmp/bug-nulls.yml" || fail "bug.yml with only null and empty invariants differs from one without invariants"

echo "== twins (#329): config keys are matched by their exact spelling"
cat > "$tmp/.claude/nightmill.json" <<'EOF2'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "areas": ["a"],
  "labels": { "Epic": "big", "story": "tale" }
}
EOF2
bash "$R" --project "$tmp" --force >/dev/null
[ "$(sed -n 4p "$d/epic.yml")" = 'labels: ["epic"]' ] || fail "epic.yml read the key Epic: $(sed -n 4p "$d/epic.yml")"
[ "$(sed -n 4p "$d/story.yml")" = 'labels: ["tale", "needs-spec"]' ] || fail "story.yml labels wrong: $(sed -n 4p "$d/story.yml")"

echo "RENDER OK"
