#!/usr/bin/env bash
# tests/test-ci-parts.sh - the PowerShell smoke job runs in parts (iteration 55, decisions 3 and 5): every `add ps` step
# of tests/check.sh is named in exactly one part of the matrix of the job smoke-powershell-part in
# .github/workflows/ci.yml, each list is in the order of the step list, smoke-slot.ps1 has a part of its own, the final
# job smoke-powershell (the required name) fails unless every part succeeded, and only that job has a job-level
# permissions block (contents: read, actions: read). Rule 10a (iterations 64 and 66, decision record 0004 step 1): the bash
# steps run in Git Bash on Windows runners, in the matrix job smoke-gitbash-part, and do not block: its name, runs-on:
# windows-latest, fail-fast: false, a full-history checkout, no if:, no needs:, the part and only lines in pairs, numbered
# 1 to the <n> of its name, and exactly one run step, tests/check.sh $CHECK_SELECT ${{ matrix.only }}, in a step with
# shell: bash and continue-on-error: true. Rule 10b (iteration 66): the final job smoke-gitbash (not yet a required
# check) needs the part job, has if: always(), runs on ubuntu-latest, fails unless every part succeeded, and does not run
# tests/check.sh. Rule 11 (iteration 66, decisions 3 and 5): every `add bash` step of tests/check.sh except the list
# gitbash_out (test-lintcopy-output.sh, which the Ubuntu job runs) is named in exactly one part, each list is in the order
# of the step list, and each step on the list gitbash_alone has a part of its own. Prints one FAIL line per broken rule,
# then runs its own cases on
# scratch copies, each broken once. tests/lint.sh starts it once. With NIGHTMILL_CI_PARTS_RULES_ONLY=1 it checks the
# rules only and skips its cases: tests/smoke-check.sh/.ps1 set it on their lint copies, so one check runs the cases once
# (bug #293), as tests/test-lint-agreement-cost.sh bounds the agreement section (bug #270).
#   tests/test-ci-parts.sh [<root>]
# Exit 1 on any failure, else 0 with the line "OK: the PowerShell parts". Needs bash, awk, sed and tr.
set -o pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-ci-parts.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
PFX='.github/workflows/ci.yml: '

# The Git Bash job's lists (iteration 66), one name per line; `rules` reads them as shell variables, so a case can set
# them in a subshell. gitbash_out: the bash steps the Git Bash job leaves out (decision 3; the Ubuntu job runs them).
# gitbash_alone: the steps that each have a part of their own (decision 5, rule 1; after the rebalance, if any).
gitbash_out='test-lintcopy-output.sh'
gitbash_alone='smoke-slot.sh
smoke-status.sh
smoke-check.sh
test-guard-rules.sh
smoke-release.sh
smoke-validate.sh'

inlist() { # inlist <name> <list, one name per line>: the name is on the list
  case $'\n'"$2"$'\n' in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}

# rules <root>: one FAIL line per broken rule, on standard output
rules() {
  local r=$1 ci chk norm pblock fblock l t prev k m
  ci="$r/.github/workflows/ci.yml"; chk="$r/tests/check.sh"
  fl() { echo "FAIL: $PFX$*"; }
  [ -f "$ci" ] || { echo "FAIL: $ci is missing"; return; }
  [ -f "$chk" ] || { echo "FAIL: $chk is missing"; return; }
  norm=$(tr -d '\r' < "$ci" | sed 's/[[:space:]]*$//')
  block() { # block <job id>: the lines of the job, up to the next line that starts with two spaces and a letter
    printf '%s\n' "$norm" | awk -v id="  $1:" '$0 == id { on = 1; next } on && (/^  [A-Za-z]/ || /^[^[:space:]]/) { on = 0 } on'
  }
  pblock=$(block smoke-powershell-part)
  fblock=$(block smoke-powershell)

  local onlys=() ks=() nameM="" ff=0 ro=0 runs=0 runok=0 bad=""
  prev=""
  while IFS= read -r l; do
    t="${l#"${l%%[![:space:]]*}"}"
    case "$t" in
      "fail-fast: false") ff=1 ;;
      "runs-on: windows-latest") ro=1 ;;
      'name: PowerShell smoke part ${{ matrix.part }} of '*) nameM=${t##* of } ;;
      "- part: "*) ks[${#ks[@]}]=${t#- part: } ;;
      "only: "*) onlys[${#onlys[@]}]=${t#only: } ;;
      "run: "*|"- run: "*) # every run step counts, the compact form `- run: ...` too (bug #296)
        runs=$((runs + 1))
        if [ "$t" = 'run: bash tests/check.sh --powershell powershell --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT ${{ matrix.only }}' ] && { [ "$prev" = "shell: bash" ] || [ "$prev" = "- shell: bash" ]; }; then runok=$((runok + 1)); fi ;;
    esac
    [ -z "$t" ] || prev=$t
  done <<<"$pblock"
  [ -n "$pblock" ] || bad="the job smoke-powershell-part is missing"
  [ -n "$bad" ] || [ "$ff" = 1 ] || bad="no fail-fast: false"
  [ -n "$bad" ] || [ "$ro" = 1 ] || bad="not runs-on: windows-latest"
  m=${#ks[@]}
  case "$nameM" in ''|*[!0-9]*) [ -n "$bad" ] || bad="the name line is not 'PowerShell smoke part \${{ matrix.part }} of <M>'" ;; esac
  if [ -z "$bad" ]; then
    if [ "$m" -lt 2 ]; then bad="fewer than two parts"
    elif [ "$m" != "${#onlys[@]}" ]; then bad="the part and only lines are not in pairs"
    elif [ "$m" != "$nameM" ]; then bad="the name says $nameM parts, the matrix has $m"
    else
      k=0
      while [ "$k" -lt "$m" ]; do
        [ "${ks[$k]}" = "$((k + 1))" ] || { bad="the part numbers are not 1 to $m in order"; break; }
        k=$((k + 1))
      done
    fi
  fi
  [ -z "$bad" ] || fl "the PowerShell parts are malformed ($bad)"
  if [ "$runs" != 1 ] || [ "$runok" != 1 ]; then
    fl 'the PowerShell part job does not run tests/check.sh $CHECK_SELECT ${{ matrix.only }}'
  fi

  # the ps steps of the step list, in list order
  local ps=() x i j n idx last
  while IFS= read -r x; do [ -z "$x" ] || ps[${#ps[@]}]=$x; done < <(awk '/^# steps: begin$/ { on = 1; next } /^# steps: end$/ { on = 0 } on && $1 == "add" && $2 == "ps" { print $3 }' "$chk")
  [ "${#ps[@]}" -gt 0 ] || fl "tests/check.sh has no ps steps"

  # rules 3 to 6, per part and per step
  local parr cnt
  if [ "$m" -ge 1 ] && [ "$m" = "${#onlys[@]}" ]; then
    for x in "${ps[@]}"; do
      cnt=0; i=0
      while [ "$i" -lt "$m" ]; do
        IFS=, read -r -a parr <<<"${onlys[$i]}"
        for n in "${parr[@]}"; do [ "$n" != "$x" ] || cnt=$((cnt + 1)); done
        i=$((i + 1))
      done
      if [ "$cnt" = 0 ]; then fl "tests/$x runs in no PowerShell part"
      elif [ "$cnt" -gt 1 ]; then fl "tests/$x runs in more than one PowerShell part"; fi
    done
    i=0
    while [ "$i" -lt "$m" ]; do
      k=${ks[$i]}
      IFS=, read -r -a parr <<<"${onlys[$i]}"
      last=-1
      for n in "${parr[@]}"; do
        idx=-1; j=0
        while [ "$j" -lt "${#ps[@]}" ]; do [ "${ps[$j]}" != "$n" ] || { idx=$j; break; }; j=$((j + 1)); done
        if [ "$idx" = -1 ]; then
          fl "PowerShell part $k names tests/$n, which is not a ps step of tests/check.sh"
        else
          if [ "$idx" -lt "$last" ]; then fl "PowerShell part $k: the --only list is not in the order of the step list"; last=999999; fi
          [ "$last" = 999999 ] || last=$idx
        fi
        if [ "$n" = smoke-slot.ps1 ] && [ "${#parr[@]}" -gt 1 ]; then fl "PowerShell part $k: smoke-slot.ps1 shares its part"; fi
      done
      i=$((i + 1))
    done
  fi

  # rule 7: the final job
  local want
  for want in '    name: PowerShell scripts smoke tests' '    needs: smoke-powershell-part' '    if: always()'; do
    grep -qxF -- "$want" <<<"$fblock" || fl "the job PowerShell scripts smoke tests does not fail unless every part succeeded (missing: ${want#    })"
  done
  if ! grep -qxF -- '        PARTS: ${{ needs.smoke-powershell-part.result }}' <<<"$fblock"; then
    if ! grep -qE '^ *PARTS: \$\{\{ needs\.smoke-powershell-part\.result \}\}$' <<<"$fblock"; then
      fl 'the job PowerShell scripts smoke tests does not fail unless every part succeeded (missing: PARTS: ${{ needs.smoke-powershell-part.result }})'
    fi
  fi
  grep -qE '^ *\[ "\$PARTS" = success \] \|\| \{' <<<"$fblock" || fl 'the job PowerShell scripts smoke tests does not fail unless every part succeeded (missing: [ "$PARTS" = success ] || {)'
  # the job times step (decision 7, bug #295): a step of the final job runs tests/ci-jobs-summary.sh, with if: always()
  # and continue-on-error: true, so the summary is written after a failed part and never fails the job; the call counts
  # only in the step's run line or a line of its run block, not in a name or a # comment
  printf '%s\n' "$fblock" | awk '
    /^      - / { if (a && c && s) ok = 1; a = c = s = rb = 0 }
    rb && !/^         / && !/^$/ { rb = 0 }
    $0 == "        if: always()" { a = 1 }
    $0 == "        continue-on-error: true" { c = 1 }
    /^(      - |        )run:/ { t = $0; sub(/^ *(- )?run:/, "", t); rb = 1; if (t !~ /^ *#/ && t ~ /tests\/ci-jobs-summary\.sh/) s = 1; next }
    rb && !/^ *#/ && /tests\/ci-jobs-summary\.sh/ { s = 1 }
    END { if (a && c && s) ok = 1; exit !ok }' ||
    fl 'the job PowerShell scripts smoke tests has no Job times step (a step that runs tests/ci-jobs-summary.sh with if: always() and continue-on-error: true)'

  # rule 8: job-level permissions, in the jobs section only
  printf '%s\n' "$norm" | awk '
    /^jobs:$/ { inj = 1; next }
    inj && /^[^[:space:]#]/ { inj = 0 }
    !inj { next }
    /^  [A-Za-z0-9_-]+:$/ { job = $1; sub(/:$/, "", job); next }
    {
      line = $0; ind = match(line, /[^ ]/) - 1; t = substr(line, ind + 1)
      if (t == "permissions:") {
        if (ind == 4 && job == "smoke-powershell") { want = 2; got = ""; next }
        printf "FAIL: .github/workflows/ci.yml: job %s has a job-level '"'"'permissions:'"'"' block (only smoke-powershell may, with contents: read and actions: read)\n", job
        next
      }
      if (want > 0) {
        if (ind >= 6) { got = got "|" t; want--; if (want == 0) { chk = 1 } ; next }
        else { want = 0 }
      }
    }
  ' | sort -u
  # the block of smoke-powershell: exactly the two lines, then a line not indented by six spaces or more
  local pm
  pm=$(printf '%s\n' "$norm" | awk '
    /^jobs:$/ { inj = 1; next }
    inj && /^[^[:space:]#]/ { inj = 0 }
    !inj { next }
    /^  [A-Za-z0-9_-]+:$/ { job = $1; sub(/:$/, "", job); inb = 0; next }
    job == "smoke-powershell" && $0 == "    permissions:" { inb = 1; blk = ""; next }
    inb { if (match($0, /^      /)) { blk = blk "|" substr($0, 7); next } else { inb = 0; print blk } }
    END { if (inb) print blk }
  ')
  if [ -n "$pm" ] && [ "$pm" != "|contents: read|actions: read" ]; then
    fl "the job smoke-powershell's 'permissions:' block is not exactly 'contents: read' and 'actions: read'"
  fi

  # rule 10a: the Git Bash parts (iterations 64 and 66). A step starts at a line of six spaces, a dash and a space; a
  # compact `- key: value` counts as the key, and every run line counts, as in the PowerShell part job (bug #296)
  local gpblock gfblock gbad="" gname="" gro=0 gff=0 gfd=0 gif=0 gneeds=0 gruns=0 grunok=0 grl="" gsh=0 gcoe=0 gm gw
  local gks=() gonlys=()
  local GBRUN='run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT ${{ matrix.only }}'
  gstep_end() { # the step just read: is it the one run step, with its keys?
    if [ "$grl" = "$GBRUN" ] && [ "$gsh" = 1 ] && [ "$gcoe" = 1 ]; then grunok=$((grunok + 1)); fi
    gsh=0; gcoe=0; grl=""
  }
  gpblock=$(block smoke-gitbash-part)
  while IFS= read -r l; do
    t="${l#"${l%%[![:space:]]*}"}"
    case "$l" in "      - "*) gstep_end ;; esac
    t=${t#- }
    case "$l" in
      '    name: Git Bash smoke part ${{ matrix.part }} of '*) gname=${l##* of } ;;
      "    runs-on: windows-latest") gro=1 ;;
    esac
    case "$t" in
      "fail-fast: false") gff=1 ;;
      "fetch-depth: 0") gfd=1 ;;
      "if:"*) gif=1 ;;
      "needs:"*) gneeds=1 ;;
      "part: "*) gks[${#gks[@]}]=${t#part: } ;;
      "only: "*) gonlys[${#gonlys[@]}]=${t#only: } ;;
      "shell: bash") gsh=1 ;;
      "continue-on-error: true") gcoe=1 ;;
      "run:"*) gruns=$((gruns + 1)); grl=$t ;;
    esac
  done <<<"$gpblock"
  gstep_end
  gm=${#gks[@]}
  [ -n "$gpblock" ] || gbad="the job smoke-gitbash-part is missing"
  if [ -z "$gbad" ]; then
    case "$gname" in ''|*[!0-9]*) gbad="the name line is not 'Git Bash smoke part \${{ matrix.part }} of <N>'" ;; esac
  fi
  [ -n "$gbad" ] || [ "$gro" = 1 ] || gbad="not runs-on: windows-latest"
  [ -n "$gbad" ] || [ "$gff" = 1 ] || gbad="no fail-fast: false"
  [ -n "$gbad" ] || [ "$gfd" = 1 ] || gbad="no fetch-depth: 0"
  [ -n "$gbad" ] || [ "$gif" = 0 ] || gbad="an if: line"
  [ -n "$gbad" ] || [ "$gneeds" = 0 ] || gbad="a needs: line"
  if [ -z "$gbad" ]; then
    if [ "$gm" -lt 2 ]; then gbad="fewer than two parts"
    elif [ "$gm" != "${#gonlys[@]}" ]; then gbad="the part and only lines are not in pairs"
    elif [ "$gm" != "$gname" ]; then gbad="the name says $gname parts, the matrix has $gm"
    else
      k=0
      while [ "$k" -lt "$gm" ]; do
        [ "${gks[$k]}" = "$((k + 1))" ] || { gbad="the part numbers are not 1 to $gm in order"; break; }
        k=$((k + 1))
      done
    fi
  fi
  [ -n "$gbad" ] || [ "$gruns" = 1 ] || gbad="$gruns run steps, not exactly one"
  [ -n "$gbad" ] || [ "$grunok" = 1 ] || gbad='the run step is not a run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT ${{ matrix.only }} in a step with shell: bash and continue-on-error: true'
  [ -z "$gbad" ] || fl "the Git Bash parts are malformed ($gbad)"

  # rule 10b: the final job smoke-gitbash fails unless every part succeeded, and runs no check itself
  gbad=""
  gfblock=$(block smoke-gitbash)
  if [ -z "$gfblock" ]; then
    gbad="the job smoke-gitbash is missing"
  else
    for gw in '    name: Git Bash smoke tests (Windows, not blocking)' '    needs: smoke-gitbash-part' '    if: always()' '    runs-on: ubuntu-latest'; do
      grep -qxF -- "$gw" <<<"$gfblock" || { gbad="missing: ${gw#    }"; break; }
    done
    [ -n "$gbad" ] || grep -qE '^ *PARTS: \$\{\{ needs\.smoke-gitbash-part\.result \}\}$' <<<"$gfblock" ||
      gbad='missing: PARTS: ${{ needs.smoke-gitbash-part.result }}'
    [ -n "$gbad" ] || grep -qE '^ *\[ "\$PARTS" = success \] \|\| \{' <<<"$gfblock" || gbad='missing: [ "$PARTS" = success ] || {'
    [ -n "$gbad" ] || ! grep -qF 'tests/check.sh' <<<"$gfblock" || gbad="it runs tests/check.sh"
  fi
  [ -z "$gbad" ] || fl "the Git Bash job is malformed ($gbad)"

  # rule 11: every bash step of the step list that the Git Bash job does not leave out is named in exactly one part,
  # each list is in the order of the step list, and the steps on gitbash_alone have a part of their own. Read only
  # when the parts parse, as the PowerShell rules 3 to 6 are
  local gb=()
  while IFS= read -r x; do [ -z "$x" ] || gb[${#gb[@]}]=$x; done < <(awk '/^# steps: begin$/ { on = 1; next } /^# steps: end$/ { on = 0 } on && $1 == "add" && $2 == "bash" { print $3 }' "$chk")
  [ "${#gb[@]}" -gt 0 ] || fl "tests/check.sh has no bash steps"
  local gbn gball
  printf -v gball '%s\n' "${gb[@]}"
  gbcount() { # gbcount <name>: sets gbn to the number of places the only lists name the step (no subshell: slow in Git Bash)
    local q p
    gbn=0
    for q in "${gonlys[@]}"; do
      IFS=, read -r -a parr <<<"$q"
      for p in "${parr[@]}"; do [ "$p" != "$1" ] || gbn=$((gbn + 1)); done
    done
  }
  if [ "$gm" -ge 1 ] && [ "$gm" = "${#gonlys[@]}" ]; then
    for x in "${gb[@]}"; do
      inlist "$x" "$gitbash_out" && continue
      gbcount "$x"
      if [ "$gbn" = 0 ]; then fl "tests/$x runs in no Git Bash part"
      elif [ "$gbn" -gt 1 ]; then fl "tests/$x runs in more than one Git Bash part"; fi
    done
    i=0
    while [ "$i" -lt "$gm" ]; do
      k=${gks[$i]}
      IFS=, read -r -a parr <<<"${gonlys[$i]}"
      last=-1
      for n in "${parr[@]}"; do
        idx=-1; j=0
        while [ "$j" -lt "${#gb[@]}" ]; do [ "${gb[$j]}" != "$n" ] || { idx=$j; break; }; j=$((j + 1)); done
        if [ "$idx" = -1 ]; then
          fl "Git Bash part $k names tests/$n, which is not a bash step of tests/check.sh"
        else
          if inlist "$n" "$gitbash_out"; then
            fl "Git Bash part $k names tests/$n, which the Git Bash job leaves out (docs/specs/iteration-66-gitbash-job-time.md, decision 3)"
          fi
          if [ "$idx" -lt "$last" ]; then fl "Git Bash part $k: the --only list is not in the order of the step list"; last=999999; fi
          [ "$last" = 999999 ] || last=$idx
        fi
        if inlist "$n" "$gitbash_alone" && [ "${#parr[@]}" -gt 1 ]; then
          fl "Git Bash part $k: tests/$n shares its part (docs/specs/iteration-66-gitbash-job-time.md, decision 5)"
        fi
      done
      i=$((i + 1))
    done
    while IFS= read -r x; do
      [ -n "$x" ] || continue
      inlist "$x" "$(printf '%s\n' "${gb[@]}")" || fl "the Git Bash job leaves out tests/$x, which is not a bash step of tests/check.sh"
    done <<<"$gitbash_out"
    while IFS= read -r x; do
      [ -n "$x" ] || continue
      gbcount "$x"
      [ "$gbn" != 0 ] || fl "tests/$x is to run alone, but it runs in no Git Bash part"
    done <<<"$gitbash_alone"
  fi
}

# on the checkout
out=$(rules "$root")
if [ -n "$out" ]; then printf '%s\n' "$out"; fail=1; fi
if [ "${NIGHTMILL_CI_PARTS_RULES_ONLY:-}" = 1 ]; then
  [ "$fail" = 0 ] || exit 1
  echo "OK: the PowerShell parts"; exit 0
fi

# the cases: each on a scratch copy of tests/check.sh and the workflow changed by one sed or awk
mkcase() { # mkcase <name>: the scratch root of the case
  local d="$tmp/case-$1"
  mkdir -p "$d/tests" "$d/.github/workflows"
  cp "$root/tests/check.sh" "$d/tests/check.sh"
  cp "$root/.github/workflows/ci.yml" "$d/.github/workflows/ci.yml"
  echo "$d"
}
expect() { # expect <name> <text or ->: the rules on the case's scratch root print the text (none for -)
  local d="$tmp/case-$1" o
  o=$(rules "$d")
  if [ "$2" = "-" ]; then
    if grep -q 'permissions' <<<"$o"; then echo "FAIL: case $1: a permissions line was printed: $o"; fail=1; fi
    return
  fi
  if ! grep -qF -- "$2" <<<"$o"; then echo "FAIL: case $1: no '$2' in: $o"; fail=1; fi
}
ci_sed() { # ci_sed <name> <sed expression>
  local f="$tmp/case-$1/.github/workflows/ci.yml"
  sed -e "$2" "$f" > "$f.new" && mv "$f.new" "$f"
}
ci_awk() { # ci_awk <name> <awk program>
  local f="$tmp/case-$1/.github/workflows/ci.yml"
  awk "$2" "$f" > "$f.new" && mv "$f.new" "$f"
}
case_sed() { # case_sed <name> <sed expression> <expected text>
  mkcase "$1" > /dev/null; ci_sed "$1" "$2"; expect "$1" "$3"
}

case_sed noguard '/only: smoke-template-board\.ps1,/s/smoke-guard\.ps1,//' 'tests/smoke-guard.ps1 runs in no PowerShell part'
case_sed render3 's/only: smoke-hook\.ps1,/only: smoke-render.ps1,smoke-hook.ps1,/' 'runs in more than one PowerShell part'
case_sed gate2 '/only: smoke-hook\.ps1,/s/smoke-gate\.ps1$/smoke-gate.ps1,smoke-gate.ps1/' 'more than one'
mkcase newstep > /dev/null
f="$tmp/case-newstep/tests/check.sh"
sed -e 's/^# steps: end$/add ps smoke-new.ps1\
# steps: end/' "$f" > "$f.new" && mv "$f.new" "$f"
expect newstep 'tests/smoke-new.ps1 runs in no PowerShell part'
case_sed nothing '/only: smoke-render\.ps1,/s/smoke-status\.ps1,/smoke-nothing.ps1,smoke-status.ps1,/' 'which is not a ps step'
case_sed order '/only: smoke-render\.ps1,/s/smoke-render\.ps1,smoke-release\.ps1/smoke-release.ps1,smoke-render.ps1/' 'not in the order of the step list'
case_sed slotshare '/only: smoke-hook\.ps1,/s/only: smoke-hook\.ps1,/only: /;/only: smoke-slot\.ps1$/s/$/,smoke-hook.ps1/' 'smoke-slot.ps1 shares its part'
case_sed noalways '/^    if: always()$/d' 'does not fail unless every part succeeded'
case_sed nosuccess '/\[ "\$PARTS" = success \]/d' 'does not fail unless every part succeeded'
case_sed numbers 's/- part: 3$/- part: X/;s/- part: 4$/- part: 3/;s/- part: X$/- part: 4/' 'malformed'
case_sed of5 's/part \${{ matrix.part }} of 4/part ${{ matrix.part }} of 5/' 'malformed'
case_sed norunonly '/run: bash tests\/check\.sh --powershell powershell/s/ \$CHECK_SELECT \${{ matrix.only }}//' 'does not run tests/check.sh $CHECK_SELECT ${{ matrix.only }}'
case_sed dashrun '/run: bash tests\/check\.sh --powershell powershell/a\
      - run: echo x' 'does not run tests/check.sh $CHECK_SELECT ${{ matrix.only }}'
mkcase leadperm > /dev/null
ci_awk leadperm '/^  [A-Za-z]/ { cur = $1 } { print } cur == "lint:" && /^    name:/ { print "    permissions:"; print "      contents: read" }'
expect leadperm "job lint has a job-level 'permissions:' block"
case_sed actionswrite 's/^      actions: read$/      actions: write/' "is not exactly 'contents: read' and 'actions: read'"
case_sed checksread 's/^      actions: read$/      actions: read\
      checks: read/' "is not exactly 'contents: read' and 'actions: read'"
case_sed noperm '/^    permissions:$/d;/^      contents: read$/d;/^      actions: read$/d' '-'
mkcase stepperm > /dev/null
ci_awk stepperm '/^  [A-Za-z]/ { cur = $1 } { print } cur == "smoke-bash:" && /^    steps:/ && !d { print "      permissions:"; d = 1 }'
expect stepperm "job smoke-bash has a job-level 'permissions:' block"

# the Git Bash jobs (iterations 64 and 66): each case changes the job smoke-gitbash-part, the job smoke-gitbash or the
# step list once, and expects the text of the rule it breaks. A case whose change did not apply (no such job in the
# workflow) fails, and so does a case whose text the unchanged checkout already prints: no case passes on a workflow
# that lacks the jobs, and each proves that its own change causes the text.
changed() { # changed <name> <file under the root>: the scratch copy differs from the checkout's file
  if cmp -s "$root/$2" "$tmp/case-$1/$2"; then echo "FAIL: case $1: the change did not apply to $2 (no job smoke-gitbash-part?)"; fail=1; fi
}
expect_gb() { # expect_gb <name> <text> [<rules output>]: the rules on the case's scratch root print the text, which the checkout's own rules do not
  local o
  if [ $# -ge 3 ]; then o=$3; else o=$(rules "$tmp/case-$1"); fi
  if ! grep -qF -- "$2" <<<"$o"; then echo "FAIL: case $1: no '$2' in: $o"; fail=1; return; fi
  if grep -qF -- "$2" <<<"$out"; then echo "FAIL: case $1: '$2' is already printed for the checkout itself, so the change proves nothing"; fail=1; fi
}
gb_case() { # gb_case <name> <sed commands for the lines of the job smoke-gitbash-part> <expected text>
  mkcase "$1" > /dev/null
  ci_sed "$1" "/^  smoke-gitbash-part:\$/,/^  [A-Za-z]/{
$2
}"
  changed "$1" .github/workflows/ci.yml
  expect_gb "$1" "$3"
}
gbf_case() { # gbf_case <name> <sed commands for the lines of the job smoke-gitbash> <expected text>
  mkcase "$1" > /dev/null
  ci_sed "$1" "/^  smoke-gitbash:\$/,/^  [A-Za-z]/{
$2
}"
  changed "$1" .github/workflows/ci.yml
  expect_gb "$1" "$3"
}
ci_awk2() { # ci_awk2 <name> <awk program>: the program reads the workflow twice (NR == FNR is the first pass)
  local f="$tmp/case-$1/.github/workflows/ci.yml"
  awk "$2" "$f" "$f" > "$f.new" && mv "$f.new" "$f"
}

# the parts (10a)
mkcase gbgone > /dev/null
ci_awk gbgone '/^  [A-Za-z]/ { skip = ($0 == "  smoke-gitbash-part:") } !skip'
changed gbgone .github/workflows/ci.yml
expect_gb gbgone 'the Git Bash parts are malformed'
gb_case gbubuntu 's/^    runs-on: windows-latest$/    runs-on: ubuntu-latest/' 'the Git Bash parts are malformed'
gb_case gbdepth '/fetch-depth: 0/d' 'the Git Bash parts are malformed'
gb_case gbif "/^    runs-on: /a\
    if: github.event_name == 'push'" 'the Git Bash parts are malformed'
gb_case gbcoe '/continue-on-error: true/d' 'the Git Bash parts are malformed'
gb_case gbshell '/shell: bash/d' 'the Git Bash parts are malformed'
gb_case gbtwo '/run: bash tests\/check\.sh/a\
      - run: echo x' 'the Git Bash parts are malformed'
gb_case gbname '/^    name: /s/ of [0-9][0-9]*$/ of X/' 'the Git Bash parts are malformed'
gb_case gbneeds '/^    runs-on: /a\
    needs: smoke-bash' 'the Git Bash parts are malformed'
gb_case gbfailfast '/fail-fast: false/d' 'the Git Bash parts are malformed'
mkcase gbof > /dev/null
ci_awk gbof '/^  [A-Za-z]/ { inb = ($0 == "  smoke-gitbash-part:") } inb && /^    name: .* of [0-9]+$/ { sub(/[0-9]+$/, $NF + 1) } { print }'
changed gbof .github/workflows/ci.yml
expect_gb gbof 'the Git Bash parts are malformed'
mkcase gbnumbers > /dev/null
ci_awk2 gbnumbers 'FNR == NR { if ($0 ~ /^  [A-Za-z]/) inb = ($0 == "  smoke-gitbash-part:"); if (inb && $0 ~ /^ *- part: /) { pa = pb; va = vb; pb = FNR; vb = $NF } next }
  FNR == pa { sub(/[0-9]+$/, vb) } FNR == pb { sub(/[0-9]+$/, va) } { print }'
changed gbnumbers .github/workflows/ci.yml
expect_gb gbnumbers 'the Git Bash parts are malformed'
gb_case gbonlyrun '/run: bash tests\/check\.sh/s/ \${{ matrix.only }}//' 'the Git Bash parts are malformed'

# the final job (10b)
mkcase gbfgone > /dev/null
ci_awk gbfgone '/^  [A-Za-z]/ { skip = ($0 == "  smoke-gitbash:") } !skip'
changed gbfgone .github/workflows/ci.yml
expect_gb gbfgone 'the Git Bash job is malformed'
gbf_case gbfname 's/ (Windows, not blocking)$//' 'the Git Bash job is malformed'
gbf_case gbfalways '/^    if: always()$/d' 'the Git Bash job is malformed'
gbf_case gbfneeds '/^    needs: smoke-gitbash-part$/d' 'the Git Bash job is malformed'
gbf_case gbfsuccess '/\[ "\$PARTS" = success \]/d' 'the Git Bash job is malformed'
# a step that runs the check in the final job is no part: the job is malformed, the parts are not
mkcase gbfcheck > /dev/null
ci_sed gbfcheck '/^  smoke-gitbash:$/,/^  [A-Za-z]/{
/^    steps:$/a\
      - run: bash tests/check.sh --only smoke-json.sh
}'
changed gbfcheck .github/workflows/ci.yml
o=$(rules "$tmp/case-gbfcheck")
expect_gb gbfcheck 'the Git Bash job is malformed (it runs tests/check.sh)' "$o"
if grep -qF 'the Git Bash parts are malformed' <<<"$o"; then echo "FAIL: case gbfcheck: the final job's run step counted as a part: $o"; fail=1; fi

# the lists (11)
gb_case gbnoguard 's/smoke-guard\.sh,//;s/,smoke-guard\.sh$//' 'tests/smoke-guard.sh runs in no Git Bash part'
gb_case gbgate2 's/smoke-gate\.sh/smoke-gate.sh,smoke-gate.sh/' 'more than one Git Bash part'
mkcase gbnewstep > /dev/null
f="$tmp/case-gbnewstep/tests/check.sh"
sed -e 's/^# steps: end$/add bash smoke-new.sh\
# steps: end/' "$f" > "$f.new" && mv "$f.new" "$f"
changed gbnewstep tests/check.sh
expect_gb gbnewstep 'tests/smoke-new.sh runs in no Git Bash part'
mkcase gbps > /dev/null
ci_awk2 gbps 'FNR == NR { if ($0 ~ /^  [A-Za-z]/) inb = ($0 == "  smoke-gitbash-part:"); if (inb && $0 ~ /^ *only: /) last = FNR; next }
  FNR == last { $0 = $0 ",smoke-slot.ps1" } { print }'
changed gbps .github/workflows/ci.yml
expect_gb gbps 'which is not a bash step'
mkcase gborder > /dev/null
ci_awk gborder '/^  [A-Za-z]/ { inb = ($0 == "  smoke-gitbash-part:") }
  inb && !d && /^ *only: [^,]+,[^,]+/ {
    match($0, /only: /); pre = substr($0, 1, RSTART + RLENGTH - 1); n = split(substr($0, RSTART + RLENGTH), a, ",")
    t = a[1]; a[1] = a[2]; a[2] = t; s = a[1]; for (i = 2; i <= n; i++) s = s "," a[i]; $0 = pre s; d = 1
  }
  { print }'
changed gborder .github/workflows/ci.yml
expect_gb gborder 'not in the order of the step list'
# test-lintcopy-output.sh, which the job leaves out, added to a packed part in list order (just before its successor)
gb_case gblintcopy 's/test-lint-pipefail\.sh/test-lintcopy-output.sh,test-lint-pipefail.sh/' 'which the Git Bash job leaves out'
# a short step (the first of the list) moved into the part of the first step on gitbash_alone, in list order
gb_first=$(printf '%s\n' "$gitbash_alone" | sed -n 1p)
gb_case gbalone "s/smoke-json\.sh,//;s/,smoke-json\.sh\$//;s/^\( *only: \)\(${gb_first//./\\.}\)\$/\1smoke-json.sh,\2/" 'shares its part'

# the lists are variables of the test: a case sets one in a subshell, on an unchanged scratch copy
mkcase gbout > /dev/null
o=$(gitbash_out=smoke-nope.sh; rules "$tmp/case-gbout")
expect_gb gbout 'which is not a bash step of tests/check.sh' "$o"
mkcase gbalonenope > /dev/null
o=$(gitbash_alone="$gitbash_alone"$'\n'smoke-nope.sh; rules "$tmp/case-gbalonenope")
expect_gb gbalonenope 'tests/smoke-nope.sh is to run alone, but it runs in no Git Bash part' "$o"

[ "$fail" = 0 ] || exit 1
echo "OK: the PowerShell parts"
