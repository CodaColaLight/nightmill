#!/usr/bin/env bash
# Regression test for #139: the entries for iterations 1 to 3 in CHANGELOG.md cited
# #10, #14 and #12, which in this repository are other items, and GitHub auto-links
# them. Either the numbers are corrected or they no longer auto-link (no "#" before
# the number). Iteration 9 rightly keeps #10. Offline: a text check only.
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0

header() { grep -E "^- Iteration $1 \(" CHANGELOG.md | head -1; }

# The reported wrong numbers: an auto-linking #N on the entry head of iterations 1 to 3
# must not be one of the numbers that point at unrelated items here.
for pair in "1:10" "2:14" "3:12"; do
  it=${pair%%:*}; bad=${pair##*:}
  line=$(header "$it")
  if [ -z "$line" ]; then echo "FAIL: no entry for iteration $it"; fail=1; continue; fi
  head=${line%%):*}
  if [[ "$head" =~ \#${bad}([^0-9]|$) ]]; then
    echo "FAIL: iteration $it still cites #$bad, which is another item in this repository"
    fail=1
  fi
done

# Iteration 9 is the story #10 and must stay.
l9=$(header 9)
if [[ "$l9" != "- Iteration 9 (#10):"* ]]; then
  echo "FAIL: iteration 9 no longer cites #10"; fail=1
fi

# The version headings stay (the lint pins them).
grep -E '^## ' CHANGELOG.md >/dev/null || { echo "FAIL: no version headings"; fail=1; }

[ "$fail" -eq 0 ] && echo "OK: changelog issue references"
exit "$fail"
