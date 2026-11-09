#!/usr/bin/env bash
# Regression test for #148: /story looks for an existing issue before it files one. The skill is
# text the model follows, so this checks the text of skills/story/SKILL.md (spec iteration 37).
# These are the checks of the spec's "tests/lint.sh" section, kept in their own file.
set -u
cd "$(dirname "$0")/.." || exit 1
f=skills/story/SKILL.md
fail=0
if [ ! -f "${f}" ]; then echo "FAIL: ${f} not found"; exit 1; fi
text=$(tr '\n' ' ' <"${f}")

need() { # need <label> <fixed string>
  case "${text}" in
    *"$2"*) ;;
    *) echo "FAIL: ${f} lacks: $2 ($1)"; fail=1 ;;
  esac
}

# criterion 1: a search of open issues for a similar title, with the match shown
need search 'gh issue list --state all --search'
need search 'in:title'
need search '--limit 100'
need search '--json number,title,state,stateReason,labels,url'
need similar 'at least 2 key words'
need shown 'At most 5'
need none 'No similar issue found'
need 'closed shown' 'closed as not planned'

# criterion 3: closed issues and any label are considered, no label named, no label filter
need labels 'whatever they are'
case "${text}" in
  *needs-triage*) echo "FAIL: ${f} names the repository's own needs-triage label (Config-driven)"; fail=1 ;;
esac
cmd=""
case "${text}" in
  *"--state all --search"*)
    before=${text%%--state all --search*}
    after=${text#*--state all --search}
    cmd="${before##*\`}--state all --search${after%%\`*}" ;;
esac
if [ -z "${cmd}" ]; then
  echo "FAIL: ${f} has no backticked command with --state all --search"; fail=1
else
  case "${cmd}" in *--label*) echo "FAIL: the search command filters on a label"; fail=1 ;; esac
  case "${cmd}" in *"--state open"*) echo "FAIL: the search command searches open issues only"; fail=1 ;; esac
fi

# criterion 1: the search comes before the issue is created
s=0; c=0; n=0
while IFS= read -r line; do
  n=$((n + 1))
  if [ "${s}" = 0 ] && [[ "${line}" == *"--state all --search"* ]]; then s=${n}; fi
  if [ "${c}" = 0 ] && [[ "${line}" == *"gh issue create"* ]]; then c=${n}; fi
done <"${f}"
if [ "${s}" = 0 ] || [ "${c}" = 0 ] || [ "${s}" -ge "${c}" ]; then
  echo "FAIL: ${f}: the search (line ${s}) does not come before gh issue create (line ${c})"; fail=1
fi

# the second search, right before creating
need 'second search' 'no third search'
need 'once' 'at most once per run'

# criterion 2: asks, files only on an explicit answer, never silently
need answers '`file anyway`'
need answers '`use #<n>`'
need answers '`do not file`'
need answers 'trimmed and lower-cased'
need answers 'Only `file anyway` files'
need answers 'Not filed: #<n> is the existing issue.'
need answers 'Not filed: possible duplicate of #<n>.'
need failed 'Not filed: the search for existing issues failed'
need headless 'Not filed: no one to answer'

# maintainer's decision: a full page (100) with nothing similar prints the limit notice and files
need limit 'limit of 100'
need limit 'may not have been checked'
case "${text}" in
  *"a similar issue may be missing"*) echo "FAIL: ${f} still claims a similar issue may be missing at the limit"; fail=1 ;;
esac
# the limit paragraph must say the issue is filed as when nothing was found, for both searches
case "${text}" in *"limit of 100"*) has_limit=1 ;; *) has_limit=0 ;; esac
if [ "${has_limit}" = 1 ]; then
  rest=${text#*limit of 100}
  seg=${rest:0:400}
  case "${seg}" in
    *"nothing similar"*|*"No similar"*|*"no similar"*) ;;
    *) echo "FAIL: ${f}: the 100 limit text does not treat a full page without a similar issue like no match"; fail=1 ;;
  esac
else
  echo "FAIL: ${f}: no text on the limit of 100"; fail=1
fi
case "${text}" in
  *"first and the second"*|*"first or the second"*|*"either search"*|*"both searches"*) ;;
  *) echo "FAIL: ${f}: the limit rule is not stated for both searches"; fail=1 ;;
esac

# README row
row=$(grep -F '/nightmill:story' README.md | head -n 1)
case "${row}" in
  *"similar title"*) ;;
  *) echo "FAIL: README.md /nightmill:story row lacks: similar title"; fail=1 ;;
esac

[ "${fail}" = 0 ] && echo "ok: /story searches for an existing issue before it files"
exit "${fail}"
