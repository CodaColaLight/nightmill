#!/usr/bin/env bash
# tests/check.sh - the local equivalent of CI, in one command (verification.check in .claude/nightmill.json).
#   tests/check.sh [--quick | --only <step>[,<step>...] | --affected [--within <step>[,<step>...]]] [--jobs <1-16>] [--powershell powershell|pwsh] [--summary <file>]
# The steps are the lines of the step list below (between '# steps: begin' and '# steps: end'; tests/lint.sh reads it
# and fails on a smoke script that is not in it), then the two claude steps:
#   lint                      tests/lint.sh
#   bash <file>               the bash smoke tests and regression tests (they need git and the tools every POSIX shell has, no jq)
#   ps <file>                 the PowerShell smoke tests (when powershell or pwsh is on the PATH)
#   claude plugin validate    claude plugin validate --strict (when claude is on the PATH)
#   claude plugin test        claude plugin test . (the module test hooks/panel.test.tsx; when claude has it)
# Up to L steps run at the same time (iteration 42): L is --jobs N, else verification.checkJobs, else 4; the last two
# are capped at the machine's processors, and any UPDATE_*_FIXTURES=1 makes L 1. With L = 1 the steps run one after
# another in the foreground; with more, each step's output goes to a file of its own and is printed whole, in the
# order of the list, whatever order the steps finish in. The steps marked 'first' are started before the others. The
# two claude steps run one after the other in one job. A step line is add <kind> <name>[ first][ slow]: a step marked
# 'slow' (iteration 62) does not run in a selective --affected run (with or without --within), which lists it as
# LEFT OUT:; the full check, --only and the fallbacks of --affected run it as any step.
#   --quick        the lint and the bash smoke tests only; never prints the line of a passed full check
#   --only a,b     exactly the named steps (CI runs its smoke jobs this way)
#   --affected     the lint and the steps the paths changed against origin/<git.baseBranch> map to (iteration 59): the
#                  changed paths are git diff --name-only against the merge base plus the untracked files, and the map
#                  between '# affects: begin' and '# affects: end' below turns each into steps (map <pattern> <steps>,
#                  shared <pattern>, lintonly <pattern>; a pattern is a case pattern on the whole path, a changed
#                  tests/<step> runs itself). A shared path, a path in no line of the map, or no merge base runs the
#                  full check instead. Never prints the line of a passed full check unless it ran the full check.
#   --within a,b   with --affected only (iteration 60; CI's smoke jobs on a pull request): of the named steps, those the
#                  changed paths select (the lint only when it is named; verification.platform does not apply). Where
#                  --affected alone would run the full check, it runs --only a,b instead. With --summary, the section
#                  also says which steps ran, which were left out, and why.
# verification.platform (iteration 56, iteration 65) picks the test families of a full or quick run: windows and unix
# skip the ps steps (the scripts are bash only, decision record 0004: on Windows the bash tests run in Git Bash), all
# (or no key) runs both; the lint and the claude steps run on every platform, and the
# skipped family is listed as SKIPPED. --only ignores the key and does not read it; --affected does not apply it to
# a step that a changed path selected (so a changed script runs its tests in both shells).
#   --jobs N       the limit for this run, 1 to 16, not capped
#   --powershell   the PowerShell for the ps steps (default: pwsh, else powershell)
#   --summary F    appends the check's wall time and its five slowest steps to the Markdown file F, before the
#                  verdict line, whatever the verdict (iteration 55; CI passes $GITHUB_STEP_SUMMARY); an interrupted
#                  check writes none
# Exit code is non-zero when any step that ran failed (2 for a usage error). Skipped steps are listed at the end. Each
# result line carries the step's time, and a Times: block after the last step lists every step's time and the total
# (iteration 41; the total is the wall time from the start to the end of the last step).
# For the tests only: NIGHTMILL_CHECK_STEPS names a file of <name> TAB <command> [TAB <kind> [TAB <reason> [TAB first
# [TAB slow]]]] lines (kind lint, bash, ps or claude; bash when left out; a step with a reason is not run and is listed
# as SKIPPED: <reason>; first marks a step to start first and slow marks a slow step, as in the step list; empty fields
# keep their place); the check then runs exactly those steps (bash -c <command>) instead of its own. NIGHTMILL_CLOCK_FILE (see
# scripts/lib/ledger.sh) is the clock the times are read from. With NIGHTMILL_CHECK_STEPS set, NIGHTMILL_CHECK_MAP
# names a file of map lines read instead of the map below (unset: an empty map). NIGHTMILL_CHECK_PATHS names a file
# whose lines are the changed paths of --affected; git is then not called. CI sets none of them.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
. scripts/lib/ledger.sh
. scripts/lib/json.sh

USAGE='usage: tests/check.sh [--quick | --only <step>[,<step>...] | --affected [--within <step>[,<step>...]]] [--jobs <1-16>] [--powershell powershell|pwsh] [--summary <file>]'
usage() { echo "$USAGE" >&2; exit 2; }
whole_1_16() { [[ "$1" =~ ^[1-9][0-9]?$ ]] && [ "$1" -le 16 ]; }

mode=full; only=""; within=""; jobs=""; psopt=""; summary=""; seen=" "
while [ $# -gt 0 ]; do
  case $1 in
    --quick|--only|--affected|--within|--jobs|--powershell|--summary)
      case $seen in *" $1 "*) usage ;; esac
      seen="$seen$1 " ;;
  esac
  case $1 in
    --quick) mode=quick; shift ;;
    --affected) mode=affected; shift ;;
    --only) { [ $# -ge 2 ] && [ -n "$2" ]; } || usage; only=$2; mode=only; shift 2 ;;
    --within) { [ $# -ge 2 ] && [ -n "$2" ]; } || usage; within=$2; shift 2 ;;
    --jobs) [ $# -ge 2 ] || usage; whole_1_16 "$2" || usage; jobs=$2; shift 2 ;;
    --powershell) [ $# -ge 2 ] || usage; case $2 in powershell|pwsh) psopt=$2 ;; *) usage ;; esac; shift 2 ;;
    --summary) { [ $# -ge 2 ] && [ -n "$2" ]; } || usage; summary=$2; shift 2 ;;
    *) usage ;;
  esac
done
case $seen in *" --quick "*) case $seen in *" --only "*) usage ;; esac ;; esac
case $seen in *" --affected "*) case $seen in *" --quick "*|*" --only "*) usage ;; esac ;; esac
case $seen in *" --within "*) case $seen in *" --affected "*) ;; *) usage ;; esac ;; esac

# The step list: k_kind, k_name, k_first ('first' or empty), k_slow ('slow' or empty), k_skip (a reason, or empty),
# k_cmd (fixture steps only)
n=0
add() { # add <kind> <name> [first] [slow]
  local marks="${*:3}"
  case $marks in
    ""|first|slow|"first slow") ;;
    *) echo "check: the step list is malformed: add $*" >&2; exit 2 ;;
  esac
  k_kind[n]=$1; k_name[n]=$2; k_first[n]=""; k_slow[n]=""; k_skip[n]=""; k_cmd[n]=""
  case $marks in first*) k_first[n]=first ;; esac
  # a lint or claude step is never slow
  case $marks in *slow) case $1 in bash|ps) k_slow[n]=slow ;; esac ;; esac
  n=$((n + 1))
}

ps=""
if [ -n "$psopt" ]; then
  if command -v "$psopt" >/dev/null 2>&1; then ps=$psopt; fi
elif command -v pwsh >/dev/null 2>&1; then ps=pwsh
elif command -v powershell >/dev/null 2>&1; then ps=powershell
fi

real_steps() {
# steps: begin
add lint lint
add bash smoke-json.sh
add bash smoke-hook.sh
add bash smoke-release.sh
add bash smoke-slot.sh first
add bash smoke-render.sh
add bash smoke-validate.sh
add bash smoke-status.sh
add bash smoke-template-board.sh
add bash smoke-models.sh
add bash smoke-load.sh
add bash smoke-room.sh
add bash smoke-control.sh
add bash smoke-dashboard.sh
add bash smoke-panel.sh
add bash smoke-stages.sh
add bash smoke-check.sh
add bash test-lintcopy-output.sh slow
add bash test-lint-pipefail.sh
add bash test-release-resume.sh
add bash test-release-low-defects.sh
add bash test-json-bom.sh
add bash test-render-quoting.sh
add bash test-changelog-refs.sh
add bash test-check-skill.sh
add bash test-status-controls.sh
add bash test-worker-merge.sh
add bash test-script-modes.sh
add bash test-fix-pick.sh
add bash test-changelog-coverage.sh
add bash test-json-speed.sh
add bash test-mktemp-template.sh
add bash test-skill-config-fallback.sh
add bash test-slot-number.sh
add bash test-board-listing.sh
add bash test-resume-stuck.sh
add bash test-story-dedup.sh
add bash test-interrupt-docs.sh
add bash test-spec-template.sh first
add bash smoke-guard.sh
add bash test-watch-checks.sh
add bash test-guard-rules.sh
add bash smoke-drive.sh
add bash smoke-gate.sh
add bash smoke-history.sh
add bash test-ci-summary.sh
add bash test-baseconfig-pathconv.sh
add bash test-restricted-path-git.sh
add bash test-slot-low-defects.sh
add ps smoke-slot.ps1 first
add ps smoke-render.ps1
add ps smoke-hook.ps1
add ps smoke-release.ps1 first
add ps smoke-validate.ps1 first
add ps smoke-status.ps1
add ps smoke-template-board.ps1
add ps smoke-models.ps1
add ps smoke-load.ps1
add ps smoke-room.ps1
add ps smoke-control.ps1
add ps smoke-dashboard.ps1
add ps smoke-panel.ps1
add ps smoke-stages.ps1
add ps smoke-check.ps1 first
add ps test-lintcopy-output.ps1 first slow
add ps test-release-resume.ps1
add ps test-release-low-defects.ps1
add ps test-json-bom.ps1
add ps test-render-quoting.ps1
add ps test-status-controls.ps1
add ps test-smoke-slot-tar.ps1
add ps test-slot-low-defects.ps1
add ps smoke-guard.ps1
add ps smoke-drive.ps1 first slow
add ps smoke-gate.ps1
add ps smoke-history.ps1
# steps: end
  local i
  if [ -z "$ps" ]; then
    for ((i = 0; i < n; i++)); do
      [ "${k_kind[i]}" != ps ] || k_skip[i]="PowerShell smoke tests (no pwsh or powershell)"
    done
  fi
  add claude "claude plugin validate"
  add claude "claude plugin test"
  if command -v claude >/dev/null 2>&1; then
    if ! claude plugin test --help >/dev/null 2>&1 </dev/null; then
      k_skip[n - 1]="claude plugin test not available"
    fi
  else
    k_skip[n - 2]="claude plugin validate (claude is not installed)"
    k_skip[n - 1]="claude plugin test not available"
  fi
}

# The map of --affected (iteration 59, decision 3; tests/lint.sh reads it and fails on a test step that no map line
# names and on a script that maps to no step). map <pattern> <step>[,<step>...]: a changed path that matches selects
# the steps; shared <pattern>: a changed path that matches runs the full check; lintonly <pattern>: a changed path
# that matches and matches no map line runs the lint alone. A pattern is a case pattern on the whole path ('*' also
# matches '/'); a script is always scripts/<x>.*, so both twins select the tests of both shells. The map lines name
# the repository paths each test file names.
affects_map() {
  cat <<'MAP'
# affects: begin
shared scripts/lib/*
shared tests/check.sh
shared tests/check.ps1
shared .github/workflows/*
shared .claude-plugin/plugin.json
lintonly docs/*
map .claude-plugin/* claude plugin validate,claude plugin test
map .claude-plugin/plugin.json smoke-release.sh,test-release-resume.sh,test-release-low-defects.sh,smoke-release.ps1,test-release-resume.ps1,test-release-low-defects.ps1
map .claude/CLAUDE.md test-changelog-coverage.sh
map .github/workflows/ci.yml smoke-check.sh,smoke-check.ps1
map CHANGELOG.md smoke-release.sh,test-release-resume.sh,test-release-low-defects.sh,test-changelog-refs.sh,test-changelog-coverage.sh,smoke-release.ps1,test-release-resume.ps1,test-release-low-defects.ps1
map CONTRIBUTING.md smoke-check.sh,smoke-check.ps1
map README.md smoke-release.sh,smoke-check.sh,test-release-resume.sh,test-release-low-defects.sh,test-resume-stuck.sh,test-story-dedup.sh,test-interrupt-docs.sh,test-spec-template.sh,test-watch-checks.sh,test-guard-rules.sh,smoke-release.ps1,smoke-check.ps1,test-release-resume.ps1,test-release-low-defects.ps1
map agents/* test-script-modes.sh,test-guard-rules.sh,claude plugin validate,claude plugin test
map agents/spec-reviewer.md test-spec-template.sh
map agents/worker.md test-worker-merge.sh
map hooks/* claude plugin validate,claude plugin test
map hooks/hooks.json smoke-hook.sh,smoke-guard.sh,test-guard-rules.sh,smoke-hook.ps1
map schema/nightmill.schema.json smoke-json.sh,smoke-validate.sh,smoke-template-board.sh,smoke-check.sh,test-watch-checks.sh,smoke-validate.ps1,smoke-template-board.ps1,smoke-check.ps1
map scripts/control.* smoke-control.sh,test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-control.ps1
map scripts/dashboard.* smoke-dashboard.sh,test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-dashboard.ps1
map scripts/drive.* test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-drive.sh,smoke-drive.ps1
map scripts/gate.* test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-gate.sh,smoke-gate.ps1
map scripts/guard.* test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-guard.sh,test-guard-rules.sh,smoke-guard.ps1
map scripts/history.* test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-drive.sh,smoke-history.sh,smoke-drive.ps1,smoke-history.ps1
map scripts/lib/baseconfig.sh test-baseconfig-pathconv.sh
map scripts/lib/json.awk smoke-json.sh
map scripts/lib/json.sh smoke-json.sh,smoke-slot.sh,smoke-status.sh,smoke-dashboard.sh,smoke-panel.sh,test-json-bom.sh,test-json-speed.sh,smoke-history.sh,test-baseconfig-pathconv.sh
map scripts/lib/ledger.ps1 smoke-history.ps1
map scripts/lib/ledger.sh smoke-history.sh
map scripts/load.* smoke-load.sh,test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-load.ps1
map scripts/models.* smoke-models.sh,test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-models.ps1
map scripts/new-worktree.* test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,test-slot-low-defects.sh,test-slot-low-defects.ps1
map scripts/panel.* smoke-panel.sh,test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-panel.ps1
map scripts/release.* smoke-release.sh,test-lint-pipefail.sh,test-release-resume.sh,test-release-low-defects.sh,test-script-modes.sh,test-changelog-coverage.sh,test-mktemp-template.sh,smoke-release.ps1,test-release-resume.ps1,test-release-low-defects.ps1
map scripts/render-templates.* smoke-render.sh,test-lint-pipefail.sh,test-render-quoting.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-render.ps1,test-render-quoting.ps1
map scripts/room.* smoke-room.sh,test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-drive.sh,smoke-room.ps1,smoke-drive.ps1
map scripts/session-start.* smoke-hook.sh,test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-hook.ps1
map scripts/slot.* smoke-slot.sh,smoke-control.sh,test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,test-skill-config-fallback.sh,test-slot-number.sh,test-interrupt-docs.sh,smoke-drive.sh,test-slot-low-defects.sh,smoke-slot.ps1,smoke-control.ps1,test-smoke-slot-tar.ps1,test-slot-low-defects.ps1,smoke-drive.ps1
map scripts/stages.* smoke-slot.sh,smoke-stages.sh,test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-slot.ps1,smoke-stages.ps1
map scripts/status.* smoke-status.sh,smoke-dashboard.sh,test-lint-pipefail.sh,test-status-controls.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-status.ps1,smoke-dashboard.ps1,test-status-controls.ps1
map scripts/template-board.* smoke-template-board.sh,test-lint-pipefail.sh,test-script-modes.sh,test-mktemp-template.sh,smoke-template-board.ps1
map scripts/validate-config.* smoke-validate.sh,smoke-models.sh,test-lint-pipefail.sh,test-json-bom.sh,test-script-modes.sh,test-mktemp-template.sh,test-board-listing.sh,smoke-validate.ps1,smoke-models.ps1,test-json-bom.ps1
map skills/* test-script-modes.sh,test-watch-checks.sh,test-guard-rules.sh,claude plugin validate,claude plugin test
map skills/check/* smoke-check.sh,test-check-skill.sh,smoke-check.ps1
map skills/fix/* test-fix-pick.sh,test-watch-checks.sh
map skills/init/* smoke-check.sh,test-skill-config-fallback.sh,test-guard-rules.sh,smoke-check.ps1
map skills/next/* test-resume-stuck.sh,test-watch-checks.sh
map skills/spec/* test-resume-stuck.sh,test-spec-template.sh,test-watch-checks.sh,test-guard-rules.sh
map skills/status/* test-resume-stuck.sh
map skills/story/* test-story-dedup.sh
map skills/workflow/* smoke-validate.sh,test-board-listing.sh,test-resume-stuck.sh,test-watch-checks.sh,test-guard-rules.sh,smoke-validate.ps1
map templates/ISSUE_TEMPLATE/* smoke-render.sh,test-render-quoting.sh,smoke-render.ps1,test-render-quoting.ps1
map templates/board-template.json smoke-template-board.sh,smoke-template-board.ps1
map templates/nightmill.example.json smoke-json.sh,smoke-validate.sh,smoke-models.sh,smoke-check.sh,test-json-bom.sh,test-board-listing.sh,test-watch-checks.sh,smoke-validate.ps1,smoke-models.ps1,smoke-check.ps1,test-json-bom.ps1
map templates/spec.md test-spec-template.sh
map tests/*.sh test-lint-pipefail.sh,test-mktemp-template.sh,test-restricted-path-git.sh
map tests/ci-jobs-summary.sh test-ci-summary.sh
map tests/fixtures/ci-summary/* test-ci-summary.sh
map tests/fixtures/dashboard/* smoke-dashboard.sh,smoke-dashboard.ps1
map tests/fixtures/drive/* smoke-drive.sh
map tests/fixtures/gate/* smoke-gate.sh,smoke-history.sh
map tests/fixtures/history/* smoke-history.sh,smoke-history.ps1
map tests/fixtures/panel/* smoke-panel.sh,smoke-panel.ps1
map tests/fixtures/smoke-json-crlf/* lint
map tests/fixtures/stages/* smoke-stages.sh,smoke-stages.ps1
map tests/fixtures/status-controls/* test-status-controls.sh,test-status-controls.ps1
map tests/fixtures/status/* smoke-status.sh,smoke-dashboard.sh,test-mktemp-template.sh,smoke-status.ps1,smoke-dashboard.ps1
map tests/fixtures/template-board/* smoke-template-board.sh,smoke-template-board.ps1
map tests/lint.sh smoke-release.sh,smoke-validate.sh,smoke-status.sh,smoke-check.sh,test-lintcopy-output.sh,test-story-dedup.sh,test-spec-template.sh,smoke-release.ps1,smoke-validate.ps1,smoke-check.ps1
map tests/smoke-check.ps1 test-lintcopy-output.sh
map tests/smoke-check.sh test-lintcopy-output.sh
map tests/smoke-history.sh test-restricted-path-git.sh
map tests/smoke-release.ps1 test-lintcopy-output.ps1
map tests/smoke-slot.ps1 test-smoke-slot-tar.ps1
map tests/test-ci-parts.sh smoke-check.sh,test-lintcopy-output.sh,smoke-check.ps1
map tests/test-spec-template.sh test-lintcopy-output.sh
# affects: end
MAP
}

if [ -n "${NIGHTMILL_CHECK_STEPS:-}" ]; then
  # Split on every tab, so an empty field (an empty reason before 'first') keeps its place; read with IFS=$'\t'
  # would merge adjacent tabs, because a tab is IFS white space.
  while IFS= read -r f_line || [ -n "$f_line" ]; do
    f_line=${f_line%$'\r'}
    f=(); while :; do
      case $f_line in *$'\t'*) f+=("${f_line%%$'\t'*}"); f_line=${f_line#*$'\t'} ;; *) f+=("$f_line"); break ;; esac
    done
    f_name=${f[0]}; f_cmd=${f[1]:-}; f_kind=${f[2]:-}; f_reason=${f[3]:-}; f_first=${f[4]:-}; f_slow=${f[5]:-}
    [ -n "$f_name" ] || continue
    case ${f_kind:-bash} in lint|bash|ps|claude) ;; *) echo "check: $NIGHTMILL_CHECK_STEPS: unknown kind $f_kind" >&2; exit 2 ;; esac
    case $f_first in ""|first) ;; *) echo "check: $NIGHTMILL_CHECK_STEPS: the fifth field is first or empty, not $f_first" >&2; exit 2 ;; esac
    case $f_slow in ""|slow) ;; *) echo "check: $NIGHTMILL_CHECK_STEPS: the sixth field is slow or empty, not $f_slow" >&2; exit 2 ;; esac
    add "${f_kind:-bash}" "$f_name" $f_first $f_slow
    k_cmd[n - 1]=$f_cmd; k_skip[n - 1]=$f_reason
  done < "$NIGHTMILL_CHECK_STEPS"
  fixture=1
else
  real_steps
  fixture=0
fi

# --within (iteration 60): w_in[i] is 1 for a step of the list, wn is how many steps the list names; a name that is no
# step is the usage error, as with --only
wn=0; w_lint=""
for ((i = 0; i < n; i++)); do w_in[i]=0; done
if [ -n "$within" ]; then
  rest=$within,
  while [ -n "$rest" ]; do
    want=${rest%%,*}; rest=${rest#*,}
    [ -n "$want" ] || usage
    hit=""
    for ((i = 0; i < n; i++)); do
      if [ "${k_name[i]}" = "$want" ]; then
        hit=1
        if [ "${w_in[i]}" = 0 ]; then w_in[i]=1; wn=$((wn + 1)); [ "${k_kind[i]}" != lint ] || w_lint=1; fi
      fi
    done
    [ -n "$hit" ] || { echo "check: no step named $want" >&2; usage; }
  done
fi

# --affected (iteration 59): the changed paths, each turned into steps by the map. aff is selective (the lint and the
# selected steps run) or full (the full check runs, and its reason is aff_reason); aff_sel[i] is 1 for a step that a
# changed path selected, and the platform does not apply to it.
aff=""; aff_reason=""; aff_c=0; aff_ref=""; aff_lines=(); aff_paths=(); aff_texts=()
for ((i = 0; i < n; i++)); do aff_sel[i]=0; done
if [ "$mode" = affected ]; then
  if [ "$fixture" = 1 ]; then
    map_text=""
    if [ -n "${NIGHTMILL_CHECK_MAP:-}" ]; then map_text=$(cat "$NIGHTMILL_CHECK_MAP") || exit 2; fi
  else
    map_text=$(affects_map)
  fi
  # the map: m_kind[j] (map, shared or lintonly), m_pat[j], m_steps[j] (',<step>,<step>,' for a map line)
  nm=0
  while IFS= read -r ml; do
    ml=${ml%$'\r'}
    case $ml in ''|'#'*) continue ;; esac
    m_kind[nm]=${ml%% *}; m_rest=${ml#* }; m_steps[nm]=""
    case ${m_kind[nm]} in
      map) case $m_rest in *' '?*) ;; *) echo "check: the map line '$ml' is malformed" >&2; exit 2 ;; esac
        m_pat[nm]=${m_rest%% *}; m_steps[nm]=",${m_rest#* }," ;;
      shared|lintonly) m_pat[nm]=$m_rest ;;
      *) echo "check: the map line '$ml' is malformed" >&2; exit 2 ;;
    esac
    nm=$((nm + 1))
  done <<<"$map_text"
  # the changed paths, sorted and unique
  paths=""
  if [ -n "${NIGHTMILL_CHECK_PATHS:-}" ]; then
    aff_ref=NIGHTMILL_CHECK_PATHS
    [ -f "$NIGHTMILL_CHECK_PATHS" ] || { echo "check: NIGHTMILL_CHECK_PATHS names no file: $NIGHTMILL_CHECK_PATHS" >&2; exit 2; }
    paths=$(while IFS= read -r l || [ -n "$l" ]; do l=${l%$'\r'}; [ -z "$l" ] || printf '%s\n' "$l"; done < "$NIGHTMILL_CHECK_PATHS" | LC_ALL=C sort -u)
  else
    base=main
    if [ -f .claude/nightmill.json ] && json_load .claude/nightmill.json >/dev/null 2>&1 && json_has git.baseBranch; then
      base=$(json_get git.baseBranch); [ -n "$base" ] || base=main
    fi
    aff_ref=origin/$base
    if mb=$(git merge-base "origin/$base" HEAD 2>/dev/null) && [ -n "$mb" ] &&
      paths=$({ git -c core.quotepath=off diff --name-only --no-renames "$mb" &&
        git -c core.quotepath=off ls-files --others --exclude-standard; } 2>/dev/null | LC_ALL=C sort -u); then :
    else
      aff_reason="the changed paths are unknown (no merge base with origin/$base)"; paths=""
    fi
  fi
  # each path in sorted order (decision 4): a shared path or a path in no line of the map makes the run the full
  # check, the first such path names the reason
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    aff_c=$((aff_c + 1))
    is_shared=""; is_lintonly=""; names=","
    for ((j = 0; j < nm; j++)); do
      # shellcheck disable=SC2254
      case $p in
        ${m_pat[j]})
          case ${m_kind[j]} in
            shared) is_shared=1 ;;
            lintonly) is_lintonly=1 ;;
            map) names="$names${m_steps[j]#,}" ;;
          esac ;;
      esac
    done
    if [ -n "$is_shared" ]; then
      [ -n "$aff_reason" ] || aff_reason="$p is shared by many steps"
      continue
    fi
    case $p in tests/*) names="$names${p#tests/}," ;; esac
    got=""; got_w=""
    for ((i = 0; i < n; i++)); do
      case $names in
        *",${k_name[i]},"*) aff_sel[i]=1; got="$got${got:+,}${k_name[i]}"
          [ "${w_in[i]}" = 0 ] || got_w="$got_w${got_w:+,}${k_name[i]}" ;;
      esac
    done
    if [ -z "$got" ] && [ -z "$is_lintonly" ]; then
      [ -n "$aff_reason" ] || aff_reason="$p is in no line of the map"
      continue
    fi
    # what the path selects: its steps, the lint only, or (with --within) none of the steps of the list
    if [ -z "$within" ]; then
      if [ -n "$got" ]; then sel_text=$got; else sel_text="the lint only"; fi
    elif [ -n "$got_w" ]; then sel_text=$got_w
    elif [ -z "$got" ] && [ -n "$w_lint" ]; then sel_text="the lint only"
    else sel_text="none of the --within steps"
    fi
    aff_lines+=("affected: $p -> $sel_text"); aff_paths+=("$p"); aff_texts+=("$sel_text")
  done <<<"$paths"
  if [ -n "$aff_reason" ]; then
    aff=full
    # with --within the fallback is --only <the list> (decision 2, rule 3)
    if [ -n "$within" ]; then mode=only; only=$within; else mode=full; fi
  else
    aff=selective
  fi
fi

# The platform (iteration 56, iteration 65): verification.platform windows and unix skip the ps steps (the scripts are
# bash only, decision record 0004: on Windows the bash tests run in Git Bash), all (or no key) runs both; the lint and
# the claude steps belong to neither family. --only does not read it, nor does a selective --affected; when
# --affected runs the full check, the key does not apply to a step that a changed path selected.
if [ "$mode" != only ] && [ "$mode" != affected ] && [ -f .claude/nightmill.json ] &&
  json_load .claude/nightmill.json >/dev/null 2>&1 && json_has verification.platform; then
  # json_get gives a number or a boolean as its text, which is never one of the three words
  plat=$(json_get verification.platform); plat_kind=""; plat_reason=""
  case $plat in
    windows) plat_kind="ps"; plat_reason="PowerShell tests (verification.platform is windows)" ;;
    unix) plat_kind="ps"; plat_reason="PowerShell tests (verification.platform is unix)" ;;
    all) ;;
    *) echo "check: verification.platform must be windows, unix or all; running both families" >&2 ;;
  esac
  if [ -n "$plat_kind" ]; then
    for ((i = 0; i < n; i++)); do
      [ "${k_kind[i]}" != "$plat_kind" ] || [ "${aff_sel[i]}" = 1 ] || k_skip[i]=$plat_reason
    done
  fi
fi

# The selection: sel[i] is 1 for a step this run takes
for ((i = 0; i < n; i++)); do
  case $mode in
    full) sel[i]=1 ;;
    quick) case ${k_kind[i]} in lint|bash) sel[i]=1 ;; *) sel[i]=0 ;; esac ;;
    only) sel[i]=0 ;;
    affected)
      if [ "${k_kind[i]}" = lint ]; then sel[i]=1; else sel[i]=${aff_sel[i]}; fi
      [ -z "$within" ] || [ "${w_in[i]}" = 1 ] || sel[i]=0 ;;
  esac
done
if [ "$mode" = only ]; then
  rest=$only,
  while [ -n "$rest" ]; do
    want=${rest%%,*}; rest=${rest#*,}
    [ -n "$want" ] || usage
    hit=""
    for ((i = 0; i < n; i++)); do
      if [ "${k_name[i]}" = "$want" ]; then sel[i]=1; hit=1; fi
    done
    [ -n "$hit" ] || { echo "check: no step named $want" >&2; usage; }
  done
fi
# A selective --affected run leaves out every selected step marked slow (iteration 62, decision 5): it does not run,
# is not counted and is listed as LEFT OUT: (k_left[i] is 1), even with a skip reason
n_left=0
for ((i = 0; i < n; i++)); do
  k_left[i]=0
  if [ "$mode" = affected ] && [ "${sel[i]}" = 1 ] && [ "${k_slow[i]}" = slow ]; then
    sel[i]=0; k_left[i]=1; n_left=$((n_left + 1))
  fi
done

# The limit L and why
if [ -n "$jobs" ]; then
  L=$jobs; why="--jobs $jobs"
else
  L=4; why="default 4"
  if [ -f .claude/nightmill.json ] && json_load .claude/nightmill.json >/dev/null 2>&1; then
    if json_has verification.checkJobs; then
      v=$(json_get verification.checkJobs)
      if whole_1_16 "$v"; then
        L=$v; why="verification.checkJobs $v"
      else
        echo "check: verification.checkJobs must be a whole number from 1 to 16; using 4" >&2
      fi
    fi
  fi
  procs=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || true)
  if [[ "$procs" =~ ^[0-9]+$ ]] && [ "$procs" -ge 1 ] && [ "$L" -gt "$procs" ]; then
    L=$procs; why="$why, capped at $procs processors"
  fi
fi
for u in UPDATE_STATUS_FIXTURES UPDATE_DASHBOARD_FIXTURES UPDATE_PANEL_FIXTURES; do
  if [ "${!u:-}" = 1 ]; then L=1; why="$u is set"; break; fi
done

case $mode in
  full)
    [ "$aff" != full ] || echo "check: AFFECTED: $aff_reason; running the full check"
    echo "check: full, $L at a time ($why)" ;;
  affected)
    # with --within, <n> is the number of steps of the list
    k=0; for ((i = 0; i < n; i++)); do [ "${sel[i]}" = 1 ] && k=$((k + 1)); done
    aff_n=$n; [ -z "$within" ] || aff_n=$wn
    echo "check: AFFECTED, $L at a time ($why): $k of $aff_n steps, changed paths: $aff_c (against $aff_ref); the full check does not run"
    for l in ${aff_lines[@]+"${aff_lines[@]}"}; do printf '%s\n' "$l"; done ;;
  quick) echo "check: QUICK, $L at a time ($why): the lint and the bash smoke tests only; the full check does not run" ;;
  only)
    [ "$aff" != full ] || echo "check: AFFECTED: $aff_reason; running every --within step"
    names=""
    for ((i = 0; i < n; i++)); do [ "${sel[i]}" = 1 ] && names="$names${names:+,}${k_name[i]}"; done
    echo "check: only $names, $L at a time ($why)" ;;
esac

# step_cmd <i>: runs step i
step_cmd() {
  local i=$1
  if [ "$fixture" = 1 ]; then bash -c "${k_cmd[i]}"; return; fi
  case ${k_kind[i]} in
    lint) bash tests/lint.sh ;;
    bash) bash "tests/${k_name[i]}" ;;
    ps) "$ps" -NoProfile -ExecutionPolicy Bypass -File "tests/${k_name[i]}" ;;
    claude)
      case ${k_name[i]} in
        "claude plugin validate") claude plugin validate . --strict ;;
        "claude plugin test") claude plugin test . ;;
      esac ;;
  esac
}

failed=(); times=(); t_names=(); t_secs=()
ledger_clock; check_start=$ledger_s; check_end=$ledger_s
# result <i> <rc> <t0> <t1>: the result line of step i, its time and the verdict
result() {
  local name=${k_name[$1]} d
  d=$(ledger_duration $(($4 - $3)))
  if [ "$2" = 0 ]; then echo "-- $name: ok ($d)"; else echo "-- $name: FAILED ($d)"; failed+=("$name"); fi
  [ "$4" -le "$check_end" ] || check_end=$4
  times+=("$(printf '  %-28s %8s' "$name" "$d")")
  t_names+=("$name"); t_secs+=($(($4 - $3)))
}
# times_block: the Times: block (every step that ran, in list order, then the total from the start to the end of the
# last step)
times_block() {
  local l
  echo
  echo "Times:"
  for l in ${times[@]+"${times[@]}"}; do printf '%s\n' "$l"; done
  printf '  %-28s %8s\n' total "$(ledger_duration $((check_end - check_start)))"
}
# selection_md: the selection section of a --within run (iteration 60, decision 6), its trailing empty lines cut: which
# steps ran and which were left out, and why; for the fallback, the reason every step of the list ran
selection_md() {
  local i r=0 ran="" left="" slow="" ns=0 nk=0 c=${#aff_paths[@]}
  if [ "$aff" = full ]; then printf 'Selection: --affected ran every --within step: %s.\n\n' "$aff_reason"; return; fi
  for ((i = 0; i < n; i++)); do
    [ "${w_in[i]}" = 1 ] || continue
    if [ "${sel[i]}" = 1 ]; then ran="$ran${ran:+, }\`${k_name[i]}\`"; nk=$((nk + 1))
    else left="$left${left:+, }\`${k_name[i]}\`"; fi
    if [ "${k_left[i]}" = 1 ]; then slow="$slow${slow:+, }\`${k_name[i]}\`"; ns=$((ns + 1)); fi
  done
  if [ "$ns" -gt 0 ]; then
    # iteration 62, decision 9: the slow steps left out are counted apart
    printf 'Selection: --affected against %s: %s of %s steps ran, %s left out (%s slow, %s selected by no changed path).\n\n' "$aff_ref" "$nk" "$wn" "$((wn - nk))" "$ns" "$((wn - nk - ns))"
  else
    printf 'Selection: --affected against %s: %s of %s steps ran, %s left out (no changed path selects them).\n\n' "$aff_ref" "$nk" "$wn" "$((wn - nk))"
  fi
  if [ "$c" -gt 0 ]; then
    printf '| Changed path | Selects |\n|---|---|\n'
    for ((r = 0; r < c && r < 50; r++)); do printf '| `%s` | %s |\n' "${aff_paths[r]}" "${aff_texts[r]}"; done
    [ "$c" -le 50 ] || printf 'And %s more changed paths (the log lists every one).\n' "$((c - 50))"
    printf '\n'
  fi
  printf 'Ran: %s\n\nLeft out: %s\n\n' "${ran:-none}" "${left:-none}"
  [ "$ns" = 0 ] || printf 'Slow steps left out: %s (a push to the base branch runs them).\n\n' "$slow"
}
# write_summary <file>: appends the wall time and the five slowest steps that ran (most seconds first, a tie in list
# order) as Markdown (iteration 55, decision 6); a file that cannot be written gets a note on standard error
write_summary() {
  local sum_file=$1 text verdict=passed k=${#t_names[@]} i row
  [ ${#failed[@]} -eq 0 ] || verdict=FAILED
  text="### tests/check.sh"$'\n\n'"Wall time: $(ledger_duration $((check_end - check_start))) for $k steps, $L at a time: $verdict"$'\n\n'
  [ -z "$within" ] || text="$text$(selection_md)"$'\n\n'
  if [ "$k" -gt 0 ]; then
    text="$text| Slowest step | Time |"$'\n'"|---|---|"$'\n'
    while IFS=$'\t' read -r _ i; do
      row="| \`${t_names[i]}\` | $(ledger_duration "${t_secs[i]}") |"
      text="$text$row"$'\n'
    done < <(for ((i = 0; i < k; i++)); do printf '%s\t%s\n' "${t_secs[i]}" "$i"; done | sort -t$'\t' -k1,1nr -k2,2n | head -n 5)
    text="$text"$'\n'
  fi
  printf '%s' "$text" 2>/dev/null >> "$sum_file" || echo "check: cannot write the summary to $sum_file" >&2
}

# The steps that run, in list order (prints), and the jobs, in start order (starts: the steps marked first, then the
# rest). Consecutive claude steps form one group: they run one after the other in the job of the first (g_next).
prints=(); starts=(); lead=""
for ((i = 0; i < n; i++)); do
  g_next[i]=""; s_job[i]=""
  [ "${sel[i]}" = 1 ] && [ -z "${k_skip[i]}" ] || { lead=""; continue; }
  prints+=("$i")
  if [ "${k_kind[i]}" = claude ] && [ -n "$lead" ]; then
    j=$lead; while [ -n "${g_next[j]}" ]; do j=${g_next[j]}; done
    g_next[j]=$i; s_job[i]=$lead
  else
    s_job[i]=$i
    if [ "${k_kind[i]}" = claude ]; then lead=$i; else lead=""; fi
  fi
done
# With L = 1 the start order is the list order (the 'first' marks are ignored)
if [ "$L" = 1 ]; then
  starts=(${prints[@]+"${prints[@]}"})
else
  for pass in first rest; do
    for i in ${prints[@]+"${prints[@]}"}; do
      [ "${s_job[i]}" = "$i" ] || continue
      if { [ "$pass" = first ] && [ "${k_first[i]}" = first ]; } || { [ "$pass" = rest ] && [ "${k_first[i]}" != first ]; }; then
        starts+=("$i")
      fi
    done
  done
fi

dir=""; started=()
# stop_jobs: TERM to the process group of every job this run started that still runs, then the run's folder is
# removed
stop_jobs() {
  local s
  for s in ${started[@]+"${started[@]}"}; do
    [ "${j_live[s]}" != 1 ] || kill -TERM -- "-${j_pid[s]}" 2>/dev/null || kill -TERM "${j_pid[s]}" 2>/dev/null
  done
  [ -z "$dir" ] || rm -rf "$dir"
}
interrupted() {
  stop_jobs
  echo
  echo "CHECK INTERRUPTED"
  exit 130
}
trap interrupted INT TERM

if [ "$L" = 1 ]; then
  for i in ${prints[@]+"${prints[@]}"}; do
    echo; echo "== ${k_name[i]}"
    ledger_clock; t0=$ledger_s
    step_cmd "$i" </dev/null; rc=$?
    ledger_clock
    result "$i" "$rc" "$t0" "$ledger_s"
  done
else
  dir=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-check.XXXXXX") || { echo "check: mktemp -d failed" >&2; exit 1; }
  trap stop_jobs EXIT
  # start_job <i>: step i (and the steps of its group) as one background job, in a process group of its own (set -m):
  # without job control a background job has INT ignored, which no step could undo (the interruption cases of
  # tests/smoke-slot.sh signal their takes with INT); stop_jobs ends the group
  start_job() {
    local i=$1
    set -m
    (
      j=$i
      while [ -n "$j" ]; do
        ledger_clock; t0=$ledger_s
        step_cmd "$j" > "$dir/$j.log" 2>&1 < /dev/null; rc=$?
        ledger_clock; t1=$ledger_s
        printf '%s %s %s\n' "$rc" "$t0" "$t1" > "$dir/$j.tmp" && mv "$dir/$j.tmp" "$dir/$j.done"
        j=${g_next[j]}
      done
    ) &
    j_pid[i]=$!; set +m; j_live[i]=1; started+=("$i")
    ledger_clock; j_t0[i]=$ledger_s
  }
  ns=${#starts[@]}; np=${#prints[@]}; next=0; running=0; p=0
  while [ "$p" -lt "$np" ]; do
    for ((q = 0; q < next; q++)); do
      i=${starts[q]}
      if [ "${j_live[i]}" = 1 ] && ! kill -0 "${j_pid[i]}" 2>/dev/null; then
        wait "${j_pid[i]}" 2>/dev/null; j_live[i]=0; running=$((running - 1))
      fi
    done
    while [ "$running" -lt "$L" ] && [ "$next" -lt "$ns" ]; do
      start_job "${starts[next]}"; next=$((next + 1)); running=$((running + 1))
    done
    while [ "$p" -lt "$np" ]; do
      i=${prints[p]}; job=${s_job[i]}
      if [ -f "$dir/$i.done" ]; then
        read -r rc t0 t1 < "$dir/$i.done"
        echo; echo "== ${k_name[i]}"
        cat "$dir/$i.log"
        result "$i" "$rc" "$t0" "$t1"
      elif [ -n "${j_live[job]:-}" ] && ! kill -0 "${j_pid[job]}" 2>/dev/null && [ ! -f "$dir/$i.done" ]; then
        ledger_clock
        echo; echo "== ${k_name[i]}"
        [ ! -f "$dir/$i.log" ] || cat "$dir/$i.log"
        echo "(the step ended without a result)"
        result "$i" 1 "${j_t0[job]}" "$ledger_s"
      else
        break
      fi
      p=$((p + 1))
    done
    [ "$p" -ge "$np" ] || sleep 0.2
  done
  wait 2>/dev/null
fi

times_block
echo
# the steps that cannot run, in list order, each text once (the steps --quick leaves out are not listed)
shown="|"
for ((i = 0; i < n; i++)); do
  [ "${sel[i]}" = 1 ] && [ -n "${k_skip[i]}" ] || continue
  case $shown in *"|${k_skip[i]}|"*) continue ;; esac
  shown="$shown${k_skip[i]}|"
  echo "SKIPPED: ${k_skip[i]}"
done
# the slow steps a selective --affected run left out, in list order (iteration 62, decision 9)
for ((i = 0; i < n; i++)); do
  [ "${k_left[i]}" = 1 ] || continue
  echo "LEFT OUT: ${k_name[i]} (a slow step; the full check and CI on the base branch run it)"
done
[ -z "$summary" ] || write_summary "$summary"
case $mode in
  quick)
    if [ ${#failed[@]} -gt 0 ]; then echo "QUICK CHECK FAILED: ${failed[*]} (the full check has not run)"; exit 1; fi
    echo "QUICK CHECK PASSED (the lint and the bash smoke tests only; the full check has not run)"
    exit 0 ;;
  only)
    if [ ${#failed[@]} -gt 0 ]; then echo "SELECTED CHECKS FAILED: ${failed[*]} (the full check has not run)"; exit 1; fi
    k=0; for ((i = 0; i < n; i++)); do [ "${sel[i]}" = 1 ] && k=$((k + 1)); done
    echo "SELECTED CHECKS PASSED ($k of $n steps; the full check has not run)"
    exit 0 ;;
  affected)
    if [ ${#failed[@]} -gt 0 ]; then echo "AFFECTED CHECK FAILED: ${failed[*]} (the full check has not run)"; exit 1; fi
    echo "AFFECTED CHECK PASSED ($k of $aff_n steps, changed paths: $aff_c; the full check has not run)"
    exit 0 ;;
esac
if [ ${#failed[@]} -gt 0 ]; then echo "CHECK FAILED: ${failed[*]}"; exit 1; fi
echo "ALL CHECKS PASSED"
