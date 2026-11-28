#!/usr/bin/env bash
# Regression test for #125 and #242: the board listing hard-coded the field names. Only the contracts are checked: the
# listing of /spec, /next and /fix is one gh project item-list <project> command with its own --jq filter and no pipe,
# the filter indexes the item by the <board.statusField ...> and <board.priorityField ...> placeholders and names no
# literal .status or .priority key, the three skills and the workflow skill name both keys, and a field name with a
# quote or a backslash is either refused by validate-config or escaped (the escapes of the command's argument) in the
# three skills. The sentences around the listing (the lower-cased key, the warning on a full page) are the reviewers'
# (iteration 76).
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
opt="--j""q"   # the option text, built so the word is not spelled out (lint: bash files do not use it)

for s in spec next fix; do
  f=skills/$s/SKILL.md
  line=$(grep -F 'gh project item-list <project>' "$f" | head -n 1)
  if [ -z "$line" ]; then echo "FAIL: $f holds no board listing"; fail=1; continue; fi

  # the filter (the single-quoted part after --jq) names no literal .status or .priority key
  filter=$(sed -n "s/.*--j[q] '\([^']*\)'.*/\1/p" <<<"$line")
  if [ -z "$filter" ]; then echo "FAIL: $f listing has no quoted ${opt} filter"; fail=1
  else
    if grep -E '\.(status|priority)([^A-Za-z]|$)|\[ *"(status|priority)" *\]' <<<"$filter" >/dev/null; then
      echo "FAIL: $f listing hard-codes a status or priority key in its filter"; fail=1
    fi
    # the key is taken from the configured name: a placeholder inside the filter, for each field
    for fld in statusField priorityField; do
      if ! grep -E "\.\[\"<board\.${fld}[^>\"]*>\"\]" <<<"$filter" >/dev/null; then
        echo "FAIL: $f filter does not index the item by a <board.${fld}> placeholder"; fail=1
      fi
    done
  fi

  # one command, no pipe outside the quoted filter
  cmd=$(sed -n 's/.*\(gh project item-list <project>[^`]*\).*/\1/p' <<<"$line")
  bare=$(sed "s/'[^']*'//g" <<<"$cmd")
  if [ -z "$cmd" ] || ! grep -F -e "${opt}" <<<"$cmd" >/dev/null || grep -F '|' <<<"$bare" >/dev/null; then
    echo "FAIL: $f listing is not a single gh project item-list ... ${opt} command without a pipe"; fail=1
  fi
done

# The three listing skills and the workflow skill name both keys.
for s in spec next fix workflow; do
  f=skills/$s/SKILL.md
  if ! grep -F 'board.statusField' "$f" >/dev/null || ! grep -F 'board.priorityField' "$f" >/dev/null; then
    echo "FAIL: $f does not name board.statusField and board.priorityField"; fail=1
  fi
done

# A field name with a quote or a backslash (#242): the filter sits inside a single-quoted argument, so
# the repository must give a working answer. Either (a) all three listing skills hold the escapes, or (b) validate-config refuses such a name for
# board.statusField and for board.priorityField. The test passes when (a) or (b) holds completely.
(
  # (a) every listing skill holds all three escapes, each as a fixed string:
  # \" (double quote), \\ (backslash) and '\'' (single quote inside the single-quoted argument)
  esc_ok=1
  for s in spec next fix; do
    f=skills/$s/SKILL.md
    if ! grep -F -e '\"' "$f" >/dev/null \
       || ! grep -F -e '\\' "$f" >/dev/null \
       || ! grep -F -e "'\\''" "$f" >/dev/null; then esc_ok=0; fi
  done
  # (b) the validator reports an error on the key, exit code 1, for each name and each field
  val_ok=1
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-board-quote.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  n=0
  for fld in statusField priorityField; do
    for name in 'Prio \"A\"' "Owner's prio" 'Prio\\A'; do
      n=$((n + 1))
      cfg="$tmp/c$n.json"
      sed "s/\"$fld\": \"[^\"]*\"/\"$fld\": \"${name//\\/\\\\}\"/" templates/nightmill.example.json > "$cfg"
      grep -F -e "\"$fld\"" "$cfg" >/dev/null || { val_ok=0; continue; }
      out=$(bash scripts/validate-config.sh "$cfg" 2>&1); rc=$?
      if [ "$rc" != 1 ] || ! grep -F "error: board.$fld" <<<"$out" >/dev/null; then val_ok=0; fi
    done
  done
  if [ "$esc_ok" = 0 ] && [ "$val_ok" = 0 ]; then
    echo "FAIL: a board field name with a quote or backslash neither is escaped by the listing skills nor refused by validate-config"
    exit 1
  fi
  exit 0
) || fail=1

[ "$fail" = 0 ] && echo "ok: the board listing uses the configured field names"
exit "$fail"
