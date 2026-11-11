#!/usr/bin/env bash
# tests/test-ci-parts.sh - the PowerShell smoke job runs in parts (iteration 55, decisions 3 and 5): every `add ps` step
# of tests/check.sh is named in exactly one part of the matrix of the job smoke-powershell-part in
# .github/workflows/ci.yml, each list is in the order of the step list, smoke-slot.ps1 has a part of its own, the final
# job smoke-powershell (the required name) fails unless every part succeeded, and only that job has a job-level
# permissions block (contents: read, actions: read). Prints one FAIL line per broken rule, then runs its own cases on
# scratch copies, each broken once. tests/lint.sh starts it once.
#   tests/test-ci-parts.sh [<root>]
# Exit 1 on any failure, else 0 with the line "OK: the PowerShell parts". Needs bash, awk, sed and tr.
set -o pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-ci-parts.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
PFX='.github/workflows/ci.yml: '

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

  local names=() onlys=() ks=() nameM="" ff=0 ro=0 runs=0 runok=0 shellprev=0 bad=""
  prev=""
  while IFS= read -r l; do
    t="${l#"${l%%[![:space:]]*}"}"
    case "$t" in
      "fail-fast: false") ff=1 ;;
      "runs-on: windows-latest") ro=1 ;;
      'name: PowerShell smoke part ${{ matrix.part }} of '*) nameM=${t##* of } ;;
      "- part: "*) ks[${#ks[@]}]=${t#- part: } ;;
      "only: "*) onlys[${#onlys[@]}]=${t#only: } ;;
      "run: "*)
        runs=$((runs + 1))
        if [ "$t" = 'run: bash tests/check.sh --powershell powershell --summary "$GITHUB_STEP_SUMMARY" --only ${{ matrix.only }}' ] && { [ "$prev" = "shell: bash" ] || [ "$prev" = "- shell: bash" ]; }; then runok=$((runok + 1)); fi ;;
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
    fl 'the PowerShell part job does not run tests/check.sh --only ${{ matrix.only }}'
  fi

  # the ps steps of the step list, in list order
  local ps=() x i j n idx last
  while IFS= read -r x; do [ -z "$x" ] || ps[${#ps[@]}]=$x; done < <(awk '/^# steps: begin$/ { on = 1; next } /^# steps: end$/ { on = 0 } on && $1 == "add" && $2 == "ps" { print $3 }' "$chk")
  [ "${#ps[@]}" -gt 0 ] || fl "tests/check.sh has no ps steps"

  # rules 3 to 6, per part and per step
  local list parr cnt slotpart
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
}

# on the checkout
out=$(rules "$root")
if [ -n "$out" ]; then printf '%s\n' "$out"; fail=1; fi

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
case_sed norunonly '/run: bash tests\/check\.sh --powershell powershell/s/ --only \${{ matrix.only }}//' 'does not run tests/check.sh --only ${{ matrix.only }}'
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

[ "$fail" = 0 ] || exit 1
echo "OK: the PowerShell parts"
