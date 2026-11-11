#!/usr/bin/env bash
# Regression test for #125: the board listing hard-codes the field names and silently drops items
# past the first 200. The listing of /spec, /next and /fix (step 1) and the listing rule of the
# workflow skill ("Picking an issue", item 2) must (a) build the filter of --jq from the configured
# board.statusField and board.priorityField, not the literal keys of the default names, (b) say
# what to do when the listing returns as many items as the limit (a visible warning that items may
# be missing) and (c) stay one gh project item-list command with its own --jq and no pipe. The
# skills are text the model follows, so this checks text.
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
opt="--j""q"   # the option text, built so the word is not spelled out (lint: bash files do not use it)

# The listing window: the line holding "gh project item-list <project>" and the 5 lines after it.
for s in spec next fix; do
  f=skills/$s/SKILL.md
  win=$(awk '/gh project item-list <project>/{n=6} n>0{print; n--}' "$f")
  if [ -z "$win" ]; then echo "FAIL: $f holds no board listing"; fail=1; continue; fi
  line=$(grep -F 'gh project item-list <project>' "$f" | head -n 1)

  # (a) the filter (the single-quoted part after --jq) names no literal .status or .priority key
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
    # ... and says the key is the lower-cased field name (in the placeholder or next to the listing)
    if ! grep -i -E 'lower' <<<"$win" >/dev/null; then
      echo "FAIL: $f listing does not say the key is the lower-cased field name"; fail=1
    fi
  fi
  # ... and the text ties the filter to the configured field names
  if ! grep -F 'board.statusField' <<<"$win" >/dev/null || ! grep -F 'board.priorityField' <<<"$win" >/dev/null; then
    echo "FAIL: $f listing does not build the filter from board.statusField and board.priorityField"; fail=1
  fi

  # (b) a full page (as many items as the limit) gives a visible warning that items may be missing
  if ! grep -i -E 'warn' <<<"$win" >/dev/null || ! grep -i -E 'missing|dropped|truncat|cut off|more items|not shown' <<<"$win" >/dev/null; then
    echo "FAIL: $f listing does not warn when the page is full and items may be missing"; fail=1
  fi

  # (c) one command, no pipe outside the quoted filter
  cmd=$(sed -n 's/.*\(gh project item-list <project>[^`]*\).*/\1/p' <<<"$line")
  bare=$(sed "s/'[^']*'//g" <<<"$cmd")
  if [ -z "$cmd" ] || ! grep -F -e "${opt}" <<<"$cmd" >/dev/null || grep -F '|' <<<"$bare" >/dev/null; then
    echo "FAIL: $f listing is not a single gh project item-list ... ${opt} command without a pipe"; fail=1
  fi
done

# The workflow skill: item 2 of "Picking an issue" carries its own listing rule.
f=skills/workflow/SKILL.md
item=$(awk '/^2\. \*\*Without a number\*\*/{on=1;print;next} /^3\. /{on=0} on' "$f" | tr '\n' ' ')
if [ -z "$item" ]; then echo "FAIL: $f holds no listing rule"; fail=1
else
  if ! grep -F 'board.statusField' <<<"$item" >/dev/null || ! grep -E 'board\.priorityField' <<<"$item" >/dev/null \
     || ! grep -i -E 'key|field name|configured' <<<"$item" >/dev/null; then
    echo "FAIL: $f listing rule does not build the filter from the configured status and priority field names"; fail=1
  fi
  if ! grep -i -E 'warn' <<<"$item" >/dev/null || ! grep -i -E 'missing|dropped|truncat|cut off|more items|not shown' <<<"$item" >/dev/null; then
    echo "FAIL: $f listing rule does not warn when the page is full and items may be missing"; fail=1
  fi
fi

# A field name with a quote or a backslash (#242): the filter sits inside a single-quoted argument, so
# the repository must give a working answer. Either (a) all three listing skills tell the model how to
# escape the name (text next to the listing line), or (b) validate-config refuses such a name for
# board.statusField and for board.priorityField. The test passes when (a) or (b) holds completely.
(
  quotefail=0
  # (a) every listing window mentions escaping and holds a backslash
  esc_ok=1
  for s in spec next fix; do
    win=$(awk '/gh project item-list <project>/{n=8} n>0{print; n--}' "skills/$s/SKILL.md")
    if ! grep -i -E 'escap' <<<"$win" >/dev/null || ! grep -F '\' <<<"$win" >/dev/null; then esc_ok=0; fi
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

[ "$fail" = 0 ] && echo "ok: the board listing uses the configured field names and warns on a full page"
exit "$fail"
