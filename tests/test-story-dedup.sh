#!/usr/bin/env bash
# Regression test for #148: /story looks for an existing issue before it files one (spec iteration 37). Only the
# contracts of skills/story/SKILL.md are checked: the search command with its flags (all states, no label filter),
# gh issue create, and the three answers the skill compares the maintainer's reply with (`file anyway`, `use #<n>`,
# `do not file`). The order of the steps, the lines it prints and the limit rule are the reviewers' (iteration 76).
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

# the search command and its flags
need search 'gh issue list --state all --search'
need search 'in:title'
need search '--limit 100'
need search '--json number,title,state,stateReason,labels,url'
need create 'gh issue create'

# the search command filters on no label and not on open issues only
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

# the answers the skill compares the maintainer's reply with
need answers '`file anyway`'
need answers '`use #<n>`'
need answers '`do not file`'

[ "${fail}" = 0 ] && echo "ok: /story searches for an existing issue before it files"
exit "${fail}"
