#!/usr/bin/env bash
# tests/test-ci-parts.sh - the CI parts are well formed (iterations 55, 68 and 70): the final job smoke-gitbash has a
# Job times step (tests/ci-jobs-summary.sh, with if: always() and continue-on-error: true), and only that job has a
# job-level permissions block (contents: read, actions: read). Rule 10a (iterations 64, 66, 69 and 70, decision record 0004 step 1): the bash
# steps run in Git Bash on Windows runners, in the matrix job smoke-gitbash-part, and block: its name, runs-on:
# windows-latest, fail-fast: false, a full-history checkout, no if:, no needs:, a matrix that is exactly one line
# `part: [1, 2, ..., <n>]` (no include: and no only: lists, iteration 70) numbered 1 to the <n> of its name, and exactly
# one run step, tests/check.sh $CHECK_SELECT @gitbash-${{ matrix.part }}, in a step with shell: bash, and no line of the
# job has continue-on-error. Rule 10b (iterations 66 and 69): the final job smoke-gitbash
# (the required check Git Bash scripts smoke tests, iteration 69) needs the part job, has if: always(), runs on ubuntu-latest, fails unless every part succeeded, and does not run
# tests/check.sh. Rule 11 (iteration 70, decisions 1, 3 and 6): the marks on the `add bash` lines of tests/check.sh are
# pinned to the steps that earlier specs chose (11a: jq, nogitbash and alone, each to its list gitbash_jq, gitbash_out
# and gitbash_alone), and the matrix has as many parts as the step list makes (11b: the steps marked alone, plus one
# packed part when another step is not marked nogitbash). The parts' steps are derived by tests/check.sh and tested in
# tests/smoke-check.sh. Prints one FAIL line per broken rule,
# then runs its own cases on
# scratch copies, each broken once. tests/lint.sh starts it once. With NIGHTMILL_CI_PARTS_RULES_ONLY=1 it checks the
# rules only and skips its cases: tests/smoke-check.sh sets it on its lint copies, so one check runs the cases once
# (bug #293), as tests/test-lint-agreement-cost.sh bounds the agreement section (bug #270).
#   tests/test-ci-parts.sh [<root>]
# Exit 1 on any failure, else 0 with the line "OK: the CI parts". Needs bash, awk, sed and tr.
set -o pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-ci-parts.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
PFX='.github/workflows/ci.yml: '

# The marks' pins (iteration 70, decision 6, rule 11a), one name per line; `rules` reads them as shell variables, so a case can
# set them in a subshell. gitbash_jq: the steps the Ubuntu job runs before it hides jq (iteration 60, decision 5).
# gitbash_out: the bash steps the Git Bash job leaves out, marked nogitbash (iteration 66, decision 3). gitbash_alone:
# the steps that each have a part of their own, marked alone (iteration 66, decision 5).
gitbash_jq='smoke-json.sh'
gitbash_out='test-lintcopy-output.sh'
gitbash_alone='smoke-check.sh
smoke-release.sh
smoke-slot.sh
smoke-status.sh
smoke-validate.sh
test-guard-rules.sh'

inlist() { # inlist <name> <list, one name per line>: the name is on the list
  case $'\n'"$2"$'\n' in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}

# rules <root>: one FAIL line per broken rule, on standard output
rules() {
  local r=$1 ci chk norm fblock l t k
  ci="$r/.github/workflows/ci.yml"; chk="$r/tests/check.sh"
  fl() { echo "FAIL: $PFX$*"; }
  [ -f "$ci" ] || { echo "FAIL: $ci is missing"; return; }
  [ -f "$chk" ] || { echo "FAIL: $chk is missing"; return; }
  norm=$(tr -d '\r' < "$ci" | sed 's/[[:space:]]*$//')
  block() { # block <job id>: the lines of the job, up to the next line that starts with two spaces and a letter
    printf '%s\n' "$norm" | awk -v id="  $1:" '$0 == id { on = 1; next } on && (/^  [A-Za-z]/ || /^[^[:space:]]/) { on = 0 } on'
  }
  fblock=$(block smoke-gitbash)
  local x i j n idx last parr

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
    fl 'the job smoke-gitbash has no Job times step (a step that runs tests/ci-jobs-summary.sh with if: always() and continue-on-error: true)'

  # rule 8: job-level permissions, in the jobs section only
  printf '%s\n' "$norm" | awk '
    /^jobs:$/ { inj = 1; next }
    inj && /^[^[:space:]#]/ { inj = 0 }
    !inj { next }
    /^  [A-Za-z0-9_-]+:$/ { job = $1; sub(/:$/, "", job); next }
    {
      line = $0; ind = match(line, /[^ ]/) - 1; t = substr(line, ind + 1)
      if (t == "permissions:") {
        if (ind == 4 && job == "smoke-gitbash") { want = 2; got = ""; next }
        printf "FAIL: .github/workflows/ci.yml: job %s has a job-level '"'"'permissions:'"'"' block (only smoke-gitbash may, with contents: read and actions: read)\n", job
        next
      }
      if (want > 0) {
        if (ind >= 6) { got = got "|" t; want--; if (want == 0) { chk = 1 } ; next }
        else { want = 0 }
      }
    }
  ' | sort -u
  # the block of smoke-gitbash: exactly the two lines, then a line not indented by six spaces or more
  local pm
  pm=$(printf '%s\n' "$norm" | awk '
    /^jobs:$/ { inj = 1; next }
    inj && /^[^[:space:]#]/ { inj = 0 }
    !inj { next }
    /^  [A-Za-z0-9_-]+:$/ { job = $1; sub(/:$/, "", job); inb = 0; next }
    job == "smoke-gitbash" && $0 == "    permissions:" { inb = 1; blk = ""; next }
    inb { if (match($0, /^      /)) { blk = blk "|" substr($0, 7); next } else { inb = 0; print blk } }
    END { if (inb) print blk }
  ')
  if [ -n "$pm" ] && [ "$pm" != "|contents: read|actions: read" ]; then
    fl "the job smoke-gitbash's 'permissions:' block is not exactly 'contents: read' and 'actions: read'"
  fi

  # the marks of the step list (rule 11), read first: gm_jq, gm_nogb and gm_alone are the marked names, comma-separated in
  # list order; gm_packed is 1 when some bash step is neither alone nor nogitbash; nparts is the number of parts the list makes
  local gm_jq gm_nogb gm_alone gm_packed nparts gmarks
  gmarks=$(awk '/^# steps: begin$/ { on = 1; next } /^# steps: end$/ { on = 0 }
    on && $1 == "add" && $2 == "bash" {
      al = 0; ng = 0
      for (i = 4; i <= NF; i++) {
        if ($i == "jq") j = j (j == "" ? "" : ",") $3
        if ($i == "nogitbash") { n = n (n == "" ? "" : ",") $3; ng = 1 }
        if ($i == "alone") { a = a (a == "" ? "" : ",") $3; al = 1; na++ }
      }
      if (!al && !ng) packed = 1
    }
    END { print j; print n; print a; print packed + 0; print na + 0 }' "$chk")
  gm_jq=$(sed -n 1p <<<"$gmarks"); gm_nogb=$(sed -n 2p <<<"$gmarks"); gm_alone=$(sed -n 3p <<<"$gmarks"); gm_packed=$(sed -n 4p <<<"$gmarks")
  nparts=$(( $(sed -n 5p <<<"$gmarks") + gm_packed ))

  # rule 10a: the Git Bash parts (iterations 64, 66 and 70). A step starts at a line of six spaces, a dash and a space; a
  # compact `- key: value` counts as the key, and every run line counts (bug #296). The matrix is one line, part: [1, 2, ..., <n>]
  local gpblock gfblock gbad="" gname="" gro=0 gff=0 gfd=0 gif=0 gneeds=0 gruns=0 grunok=0 grl="" gsh=0 gcoe=0 gm gw gmat gmok=0 glist
  local gks=()
  local GBRUN='run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT @gitbash-${{ matrix.part }}'
  gstep_end() { # the step just read: is it the one run step, with its keys?
    if [ "$grl" = "$GBRUN" ] && [ "$gsh" = 1 ]; then grunok=$((grunok + 1)); fi
    gsh=0; grl=""
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
      "shell: bash") gsh=1 ;;
      "continue-on-error:"*) gcoe=1 ;;
      "run:"*) gruns=$((gruns + 1)); grl=$t ;;
    esac
  done <<<"$gpblock"
  gstep_end
  # the matrix block: the lines after `      matrix:` that are indented by more than six spaces, without comments and blanks
  gmat=$(printf '%s\n' "$gpblock" | awk '$0 == "      matrix:" { on = 1; next }
    on { if ($0 ~ /^ *$/) next; match($0, /[^ ]/); if (RSTART - 1 <= 6) { on = 0; next }
         t = $0; sub(/^ +/, "", t); if (t ~ /^#/) next; print }')
  if [ -n "$gmat" ] && [ "$(printf '%s\n' "$gmat" | wc -l | tr -d ' ')" = 1 ] && grep -qE '^        part: \[[0-9]+(, [0-9]+)*\]$' <<<"$gmat"; then
    gmok=1
    glist=${gmat#*\[}; glist=${glist%\]}
    IFS=, read -r -a gks <<<"${glist// /}"
  fi
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
  [ -n "$gbad" ] || [ "$gcoe" = 0 ] || gbad="a continue-on-error: line"
  if [ -z "$gbad" ]; then
    if [ "$gmok" = 0 ]; then gbad="the matrix is not one line 'part: [1, 2, ..., $nparts]'"
    elif [ "$gm" -lt 2 ]; then gbad="fewer than two parts"
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
  [ -n "$gbad" ] || [ "$grunok" = 1 ] || gbad='the run step is not a run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT @gitbash-${{ matrix.part }} in a step with shell: bash'
  [ -z "$gbad" ] || fl "the Git Bash parts are malformed ($gbad)"

  # rule 10b: the final job smoke-gitbash fails unless every part succeeded, and runs no check itself
  gbad=""
  gfblock=$(block smoke-gitbash)
  if [ -z "$gfblock" ]; then
    gbad="the job smoke-gitbash is missing"
  else
    for gw in '    name: Git Bash scripts smoke tests' '    needs: smoke-gitbash-part' '    if: always()' '    runs-on: ubuntu-latest'; do
      grep -qxF -- "$gw" <<<"$gfblock" || { gbad="missing: ${gw#    }"; break; }
    done
    if [ -n "$gbad" ]; then
      :
    elif ! grep -qE '^ *PARTS: \$\{\{ needs\.smoke-gitbash-part\.result \}\}$' <<<"$gfblock"; then
      gbad='missing: PARTS: ${{ needs.smoke-gitbash-part.result }}'
    elif ! grep -qE '^ *\[ "\$PARTS" = success \] \|\| \{' <<<"$gfblock"; then
      gbad='missing: [ "$PARTS" = success ] || {'
    elif grep -qF 'tests/check.sh' <<<"$gfblock"; then
      gbad="it runs tests/check.sh"
    fi
  fi
  [ -z "$gbad" ] || fl "the Git Bash job is malformed ($gbad)"

  # rule 11a: the marks of the step list are the steps that earlier specs chose
  csvsort() { printf '%s' "$1" | tr ',' '\n' | LC_ALL=C sort | tr '\n' ','; }
  gbpin() { # gbpin <mark> <marked names, comma-separated> <the pinned names, one per line> <source>
    local want=${3//$'\n'/,}
    if [ "$(csvsort "$2")" != "$(csvsort "$want")" ]; then
      echo "FAIL: tests/check.sh: the steps marked $1 are not exactly $want ($4): ${2:-none}"
    fi
  }
  gbpin jq "$gm_jq" "$gitbash_jq" 'docs/specs/iteration-60-ci-affected-jobs.md, decision 5'
  gbpin nogitbash "$gm_nogb" "$gitbash_out" 'docs/specs/iteration-66-gitbash-job-time.md, decision 3'
  gbpin alone "$gm_alone" "$gitbash_alone" 'docs/specs/iteration-66-gitbash-job-time.md, decision 5'
  # rule 11b: the matrix has as many parts as the step list makes, read only when the matrix parses
  if [ "$gmok" = 1 ] && [ "$gm" != "$nparts" ]; then
    fl "the matrix has $gm parts, the step list of tests/check.sh makes $nparts"
  fi
}

# on the checkout
out=$(rules "$root")
if [ -n "$out" ]; then printf '%s\n' "$out"; fail=1; fi
if [ "${NIGHTMILL_CI_PARTS_RULES_ONLY:-}" = 1 ]; then
  [ "$fail" = 0 ] || exit 1
  echo "OK: the CI parts"; exit 0
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
gb_case gbcoe '/^      - shell: bash$/a\
        continue-on-error: true' 'the Git Bash parts are malformed (a continue-on-error: line)'
gb_case gbjobcoe '/^    runs-on: windows-latest$/a\
    continue-on-error: true' 'the Git Bash parts are malformed (a continue-on-error: line)'
gb_case gbcoeexpr '/^      - shell: bash$/a\
        continue-on-error: ${{ matrix.part == 7 }}' 'the Git Bash parts are malformed (a continue-on-error: line)'
gb_case gbcoefalse '/^      - shell: bash$/a\
        continue-on-error: false' 'the Git Bash parts are malformed (a continue-on-error: line)'
gb_case gbshell '/shell: bash/d' 'in a step with shell: bash)'
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
gb_case gbnumbers 's/part: \[1, 2,/part: [2, 1,/' 'the Git Bash parts are malformed'
gb_case gbinclude '/^        part: \[/a\
        include:' 'the matrix is not one line'
gb_case gbonlyback '/^        part: \[/a\
        only: x' 'the matrix is not one line'
gb_case gbeight 's/ of 7$/ of 8/;s/part: \[1, 2, 3, 4, 5, 6, 7\]/part: [1, 2, 3, 4, 5, 6, 7, 8]/' 'the matrix has 8 parts, the step list of tests/check.sh makes 7'
gb_case gbonlyrun 's/@gitbash-\${{ matrix.part }}/${{ matrix.only }}/' 'the Git Bash parts are malformed'

# the final job (10b)
mkcase gbfgone > /dev/null
ci_awk gbfgone '/^  [A-Za-z]/ { skip = ($0 == "  smoke-gitbash:") } !skip'
changed gbfgone .github/workflows/ci.yml
expect_gb gbfgone 'the Git Bash job is malformed'
gbf_case gbfname 's/^    name: Git Bash scripts smoke tests$/    name: Git Bash smoke tests (Windows, not blocking)/' 'the Git Bash job is malformed (missing: name: Git Bash scripts smoke tests)'
gbf_case gbfrename 's/^    name: Git Bash scripts smoke tests$/    name: Git Bash smoke tests/' 'the Git Bash job is malformed (missing: name: Git Bash scripts smoke tests)'
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

# the marks and the count (11): one unmarked line in the step list puts a test in the check and in every CI job
mkcase gbnewstep > /dev/null
f="$tmp/case-gbnewstep/tests/check.sh"
sed -e 's/^add bash smoke-models\.sh$/add bash smoke-models.sh\
add bash smoke-new.sh/' "$f" > "$f.new" && mv "$f.new" "$f"
changed gbnewstep tests/check.sh
o=$(rules "$tmp/case-gbnewstep")
if [ "$o" != "$out" ]; then echo "FAIL: case gbnewstep: one new unmarked line in the step list changes what the rules print: [$o] against the checkout's [$out]"; fail=1; fi
if [ -n "$out" ]; then echo "FAIL: case gbnewstep: the rules print for the checkout itself, so the new step proves nothing: $out"; fail=1; fi
mkcase gbnewalone > /dev/null
f="$tmp/case-gbnewalone/tests/check.sh"
sed -e 's/^# steps: end$/add bash smoke-new.sh alone\
# steps: end/' "$f" > "$f.new" && mv "$f.new" "$f"
changed gbnewalone tests/check.sh
o=$(rules "$tmp/case-gbnewalone")
expect_gb gbnewalone 'the steps marked alone are not exactly' "$o"
expect_gb gbnewalone 'makes 8' "$o"
mkcase gbunalone > /dev/null
f="$tmp/case-gbunalone/tests/check.sh"
sed -e 's/^add bash smoke-check\.sh alone$/add bash smoke-check.sh/' "$f" > "$f.new" && mv "$f.new" "$f"
changed gbunalone tests/check.sh
o=$(rules "$tmp/case-gbunalone")
expect_gb gbunalone 'the steps marked alone are not exactly' "$o"
expect_gb gbunalone 'makes 6' "$o"
mkcase gbnojq > /dev/null
f="$tmp/case-gbnojq/tests/check.sh"
sed -e 's/^\(add bash smoke-json\.sh\) jq$/\1/' "$f" > "$f.new" && mv "$f.new" "$f"
changed gbnojq tests/check.sh
expect_gb gbnojq 'the steps marked jq are not exactly smoke-json.sh'

# the pins are variables of the test: a case sets one in a subshell, on an unchanged scratch copy
mkcase gbout > /dev/null
o=$(gitbash_out=smoke-nope.sh; rules "$tmp/case-gbout")
expect_gb gbout 'the steps marked nogitbash are not exactly smoke-nope.sh' "$o"
mkcase gbalonenope > /dev/null
o=$(gitbash_alone="$gitbash_alone"$'\n'smoke-nope.sh; rules "$tmp/case-gbalonenope")
expect_gb gbalonenope 'the steps marked alone are not exactly' "$o"

[ "$fail" = 0 ] || exit 1
echo "OK: the CI parts"
