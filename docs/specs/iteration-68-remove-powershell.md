# Iteration 68: the PowerShell scripts, their tests and the PowerShell CI parts are removed

Status: draft, awaiting approval (#365)

Story #365, epic #337 (fast verification loop): step 4, the last, of the migration outline of decision record 0004
(step 1 was iteration 64, #361; step 2 iteration 65, #363; step 3 iteration 67, #364, merged as 4058d29). The 23
PowerShell scripts of `scripts/` and `scripts/lib/`, the 19 `tests/smoke-*.ps1` and the 9 `tests/test-*.ps1` are
removed (51 files); `tests/check.ps1` stays as the wrapper for a PowerShell prompt, and the two image tools in `tools/`
stay (decision 1). `tests/check.sh` loses its 27 `ps` steps, the `ps` kind and `--powershell`, and stops reading
`verification.platform`; CI loses the four PowerShell parts and the required job `PowerShell scripts smoke tests`,
whose Job times step moves to the final Git Bash job; the maintainer takes that name out of the ruleset of `main`
before the merge (decision 3). The lint stops asking for `.ps1` twins and fails on a `.ps1` file other than the
three that stay, and on any file outside `docs/` and `CHANGELOG.md` that names a removed `.ps1`. The slots pane runs
`scripts/panel.sh` with bash on Windows too, the driver's workflow template runs `drive.sh` in Git Bash, and every
text that named a `.ps1` form names the `.sh` form or nothing. Changes (besides the 51 removals): `tests/check.sh`,
`tests/check.ps1`, `tests/lint.sh`, `tests/smoke-check.sh`, `tests/test-ci-parts.sh`, `tests/test-ci-job-times.sh`,
`tests/test-ci-run-steps.sh`, `tests/ci-jobs-summary.sh`, `tests/test-ci-summary.sh`, `tests/fixtures/ci-summary/jobs.tsv`
and `jobs.md`, `tests/test-lint-agreement.sh`, `tests/test-lint-agreement-cases.sh`, `tests/test-lint-agreement-cost.sh`,
`tests/test-lintcopy-output.sh`, the other bash tests of decision 11, `tests/fixtures/drive/README.txt`,
`tests/fixtures/gate/README.txt`, a new `tests/test-no-powershell.sh`, `.github/workflows/ci.yml`,
`.github/pull_request_template.md`, `.claude/CLAUDE.md`, `.claude/nightmill.json`, `CONTRIBUTING.md`, `README.md`,
`CHANGELOG.md`, `schema/nightmill.schema.json`, `skills/init/SKILL.md`, `hooks/panel.tsx`, `hooks/panel.test.tsx`,
`templates/CLAUDE.snippet.md`, `templates/workflows/nightmill-drive.yml` and the comments of 27 files under
`scripts/` (decision 10). The maintainer decided that all of it lands in one pull request, which closes #365
(decision 13).

## Story trigger and manual check

**A story trigger, by iteration 65's reading.** *Config key*: none is added, renamed or removed;
`verification.platform` keeps its name, type, `enum` `["all", "windows", "unix"]` and default `all`, and every value
still validates. What changes is what nightmill's own check does with it: it no longer reads it, so `all` no longer
runs a PowerShell family (there is none). Iteration 65 treated a change of what a value does as the trigger "a new,
renamed or removed config key" protects; this spec does the same, and the maintainer approves the new description by
approving the spec. *Status flow*: no status, no board call, no decision record changes (record 0004 holds the
decision). *Slot marker*: `scripts/slot.sh` changes only in comments; `slot.ps1` wrote the same marker and goes, so the
format does not change.

**Compatible** (the invariant): a config of the previous version reads unchanged. What breaks is what record 0004
step 4 and the issue name: a project's hand-wired `session-start.ps1` or `guard.ps1` hook stops working, and its `.ps1`
allow rules match nothing. The changelog says what to remove and to pin the release before this one until then
(decision 12).

**The manual check applies**: `verification.manualCheckPaths` is `skills`, `agents`, `hooks`, and `hooks/panel.tsx`,
`hooks/panel.test.tsx` and `skills/init/SKILL.md` change (nothing under `agents/`). Its steps are under Tests.

**Shells.** After this iteration there is one: every changed test is bash, plus the module test `hooks/panel.test.tsx`.
`tests/check.ps1` changes only to drop an option `tests/check.sh` no longer has (decision 2), the rule for a frozen
file. Smoke steps: no new script behaviour; the bash smoke tests of the scripts are unchanged except where decision 11
says.

**Never auto-merged.** The pull request changes `.claude/CLAUDE.md`, `.claude/nightmill.json` and paths under
`.github/`, carries the story trigger (what nightmill's check does with `verification.platform`), and removes a
required check (decision 3), so it is opened without `--auto`; the maintainer makes the ruleset change and then
merges it.

## Facts this rests on

Measured on `spec/68-remove-powershell` at 4058d29 (equal to `main`) on 2026-11-27 with `find . -name '*.ps1'`,
`wc -l`, `git grep -n -E '\.ps1' -- . ':!docs' ':!CHANGELOG.md' ':!*.ps1'`, the step list of `tests/check.sh` counted
with `grep -c '^add bash'` and `'^add ps'`, and `gh issue view` / `gh project item-list` (read only). The sweep of
rule 2 (decision 6) was re-run with `grep -InoE '[A-Za-z0-9_-]+\.ps1'` over every tracked file outside `docs/`,
`CHANGELOG.md` and the `.ps1` files, the names `check.ps1`, `make-icon.ps1` and `make-social-preview.ps1` left out.

- **PowerShell files: 54**, no `.psm1` or `.psd1`. `scripts/`: 19 (5901 lines); `scripts/lib/`: 4 (`baseconfig`,
  `exactkeys`, `ledger`, `load`; 544 lines); `tests/smoke-*.ps1`: 19 (8405 lines); `tests/test-*.ps1`: 9 (`json-bom`,
  `lintcopy-output`, `release-low-defects`, `release-resume`, `render-quoting`, `slot-low-defects`, `smoke-slot-tar`,
  `status-controls`, `warmup-interpreter`; 858 lines); `tests/check.ps1` (26 lines, runs `bash tests/check.sh`, passes
  `-PowerShell` on as `--powershell`); `tools/make-icon.ps1` and `tools/make-social-preview.ps1` (196 lines; System.Drawing,
  run by hand, by no test, no check step and no CI job; no `.sh` form). Record 0004 step 4 names "the 23 `.ps1`
  scripts, the 19 `smoke-*.ps1` and 9 `test-*.ps1` files": 51 files, 15708 lines.
- **Names of a `.ps1`**: 379 lines in 70 files outside `docs/`, `CHANGELOG.md` and the `.ps1` files: `tests/lint.sh`
  95, `tests/check.sh` 73, `tests/smoke-check.sh` 31, `README.md` 22, `tests/test-lint-agreement.sh` 16,
  `tests/test-lint-agreement-cases.sh` 14, `tests/test-ci-parts.sh` 12, `scripts/slot.sh` 10, `.claude/CLAUDE.md` 9,
  `tests/test-lintcopy-output.sh` 6, `tests/test-interrupt-docs.sh` and `tests/test-config-from-base.sh` 5 each, 4 each
  in `tests/test-limits-docs.sh`, `tests/test-drive-docs.sh`, `tests/test-docs-low-gaps.sh`, `.github/workflows/ci.yml`,
  and 1 to 3 in 54 more (26 of them under `scripts/`, 27 with `scripts/slot.sh`, all comments but `scripts/release.sh` line 285, which prints the
  `.ps1` call; `hooks/panel.tsx` 2, `hooks/panel.test.tsx` 2, `templates/CLAUDE.snippet.md` 1,
  `templates/workflows/nightmill-drive.yml` 2, `.claude/nightmill.json` 1 (`parallel.hotFiles` holds
  `scripts/slot.ps1`), `schema/nightmill.schema.json` 1 (the description of `worktrees.warmup[].command`),
  `.gitattributes` 1 (`*.ps1 text eol=lf`)).
- **The check**: the step list has 1 `lint`, 48 `bash` and 27 `ps` steps, then 2 `claude` steps: 78. `first` marks:
  bash `smoke-slot.sh`, `test-spec-template.sh` and ps `smoke-slot.ps1`, `smoke-release.ps1`, `smoke-validate.ps1`,
  `smoke-check.ps1`, `test-lintcopy-output.ps1`, `smoke-drive.ps1`; `slow`: bash `test-lintcopy-output.sh`, ps
  `test-lintcopy-output.ps1`, `smoke-drive.ps1`. The `ps` kind: the PowerShell detection (`--powershell`, else `pwsh`,
  else `powershell`), the skip reason `PowerShell smoke tests (no pwsh or powershell)`, the runner line
  `ps) "$ps" -NoProfile ...`, the fixture kind check `lint|bash|ps|claude`. `verification.platform` is read only by the
  block from line 429 (`windows` and `unix` skip the `ps` steps). The map of `--affected` names a `.ps1` step in 35 lines
  and has 4 lines whose pattern is a `.ps1` file (`scripts/lib/ledger.ps1`, `tests/smoke-check.ps1`,
  `tests/smoke-release.ps1`, `tests/smoke-slot.ps1`); `shared tests/check.ps1` is one of its shared lines and the only
  `.ps1` name of `tests/check.sh` outside an `add ps` or `map` line.
  `test-warmup-interpreter.ps1` is no step: `tests/lint.sh` starts it in `== one interpreter runs a warm-up command`
  when `powershell` is on the PATH.
- **CI** (`.github/workflows/ci.yml`, 162 lines): jobs `lint` and `smoke-bash` (required, `Lint (generic, JSON, skills,
  shell)` and `bash scripts smoke tests`); `smoke-powershell-part` (lines 46 to 69, four parts on Windows) and
  `smoke-powershell` (lines 71 to 100, `PowerShell scripts smoke tests`, required, the one job-level `permissions:`
  block with `actions: read`, and the `Job times` step, the only caller of `tests/ci-jobs-summary.sh`, with
  `--parts 'PowerShell smoke part '`); `smoke-gitbash-part` (seven parts, its check step `continue-on-error: true`) and
  `smoke-gitbash` (`Git Bash smoke tests (Windows, not blocking)`, no checkout step); `validate`. `tests/lint.sh` pins
  the three required names (two loops and a heredoc, the `Required check` comment exactly 3 times). Iteration 65's
  decision 7 did not land: the Git Bash jobs are not blocking and their final job is not required.
- **Issue #390** (Backlog, "The lint fails on a new PowerShell file, and the Git Bash jobs block once required") holds
  what iteration 65 left out: the freeze lint with the removal of the twin rules (item 1) and the Git Bash jobs as a
  required check (item 2). The twin rules are still in `tests/test-lint-agreement.sh` (every `tests/smoke-*.sh` but
  `smoke-json.sh` has a `.ps1` twin, every `scripts/*.sh` has one), and `.claude/CLAUDE.md` says the freeze lint
  "comes in a follow-up".
- **The pane**: `hooks/panel.tsx` lines 122 to 126 read `OS` and run
  `powershell -NoProfile -ExecutionPolicy Bypass -File <root>/scripts/panel.ps1` when it is `Windows_NT`, else
  `bash <root>/scripts/panel.sh`; a failed start draws `unknown` with `the panel script did not run: <message>`.
  `hooks/panel.test.tsx` lines 211 and 219 pin the Windows argv; README line 675 says it.
- **The driver template** runs `drive.sh` in a `shell: bash` step with `if: runner.os != 'Windows'` and `drive.ps1` in a
  `shell: pwsh` step on Windows; its bash step takes the install path from `claude plugin list --json` with awk,
  which on Windows yields the JSON-escaped `C:\\...` form.
- **The release before this one has not been cut.** `.claude-plugin/plugin.json` is at 0.9.0, and iterations 65, 66
  and 67 (#363, #382, #364) are still bullets under `Unreleased` in `CHANGELOG.md`. Record 0004 step 3 says "One
  release carries this step before step 4", and iteration 67's bullet tells a project to "pin this release" until it
  has moved a hand-wired `.ps1` hook; so a release that carries iteration 67 has to exist before this iteration's pull
  request merges (decision 3, step 1).
- **Every bash test that names a removed `.ps1`** (`grep -noE '[A-Za-z0-9_-]+\.ps1' tests/*.sh`, the names other
  than `check.ps1`, `make-icon.ps1` and `make-social-preview.ps1`, which is what rule 2 of decision 6 flags): besides
  `tests/check.sh`, `tests/lint.sh` and `tests/smoke-check.sh`, the files `smoke-control`, `smoke-dashboard`,
  `smoke-drive`, `smoke-gate`, `smoke-history`, `smoke-load`, `smoke-models`, `smoke-panel`, `smoke-room`, `smoke-slot`,
  `smoke-template-board`, `smoke-validate`, `test-ci-job-name-rule`, `test-ci-parts`, `test-config-from-base`,
  `test-docs-low-gaps`, `test-drive-docs`, `test-guard-gql-keyword`, `test-guard-rules`, `test-interrupt-docs`,
  `test-limits-docs`, `test-lint-agreement`, `test-lint-agreement-cases`, `test-lint-agreement-cost`,
  `test-lintcopy-output`, `test-slot-low-defects` and `test-warmup-interpreter` (all `.sh`). Header comments that name
  a *script's* `.ps1` (not a twin test): `tests/test-guard-gql-keyword.sh` line 4 (`... in scripts/guard.sh and, when
  a PowerShell is on the PATH, scripts/guard.ps1.`), `tests/test-interrupt-docs.sh` lines 2 to 4 (`the header comment
  of both slot scripts ... in scripts/slot.sh and` / `# scripts/slot.ps1, and the sentences ...`) and
  `tests/test-drive-docs.sh` line 4 (`(history.ps1)`). Outside a header line:
  `tests/smoke-dashboard.sh` line 198 and `tests/smoke-panel.sh` line 162 (the comment `# #329: slot.sh and slot.ps1
  both list that slot as busy and unknown ...`), `tests/smoke-slot.sh` line 1158 (claim 7), `tests/test-drive-docs.sh`
  lines 21 to 30 and 94, `tests/test-limits-docs.sh` lines 131 to 168, `tests/test-config-from-base.sh` lines 79 to 93,
  `tests/test-interrupt-docs.sh` lines 29 and 39 to 47, `tests/test-guard-gql-keyword.sh` lines 51 and 56,
  `tests/test-guard-rules.sh` line 36, `tests/test-lintcopy-output.sh` lines 93 to 171; `tests/test-ci-job-name-rule.sh`
  line 6 (`... in tests/smoke-check.sh and tests/smoke-check.ps1.`) and `tests/test-docs-low-gaps.sh` line 14
  (`(tests/smoke-render.ps1)`, the source of item (f)) are comments too. `tests/test-lint-agreement-cost.sh` has 51
  lines; its only such names are its history comment, lines 3 and 4 (there is no line 245). `tests/test-docs-low-gaps.sh`
  line 147 (`find ... -name '*.ps1'`) and `tests/smoke-stages.sh` (`tests/check.ps1`) are not flagged.
- **Outside `tests/`** the same sweep finds: `README.md` (line 675, the pane; lines 1104 to 1122, the 19
  `tests/smoke-*.ps1` lines; line 1132, the CI sentence), `.github/workflows/ci.yml` lines 57 to 63 (the PowerShell
  parts' `only:` lists), `.claude/CLAUDE.md` lines 44, 58, 59 and 61, `.claude/nightmill.json` line 63,
  `schema/nightmill.schema.json` line 218 (`slot.ps1` and `new-worktree.ps1` in the `worktrees.warmup[].command`
  description), `hooks/panel.tsx` lines 5 and 125, `hooks/panel.test.tsx` lines 211 and 219,
  `templates/CLAUDE.snippet.md` line 7, `templates/workflows/nightmill-drive.yml` lines 6 and 56,
  `tests/fixtures/drive/README.txt` and `tests/fixtures/gate/README.txt` line 1, and the 39 lines in 27 files under
  `scripts/` (decision 10). Each is covered by decisions 1 to 11 and listed under Files touched.
- **Bash tests that start PowerShell**: `tests/smoke-slot.sh` (claim 7 "across the shells" starts `slot.ps1`; the
  reader cases 1 to 4 start `powershell -Command` to hold a file open with `FileShare.Read`, no `.ps1`),
  `tests/test-guard-gql-keyword.sh` (its `guard.ps1` half), `tests/lint.sh` (`test-warmup-interpreter.ps1`).

## Decisions

**1. What goes, and what stays.** Removed with `git rm`, 51 files: the 19 `scripts/*.ps1`, the 4
`scripts/lib/*.ps1`, the 19 `tests/smoke-*.ps1` and the 9 `tests/test-*.ps1`. Stay, 3 files: `tests/check.ps1`
(the issue; changed by decision 2) and `tools/make-icon.ps1`, `tools/make-social-preview.ps1`, unchanged. The two tools
stay because the story's goal is the second *track*: they are no plugin script (record 0004 counts 23 scripts and
leaves them out), no test, no check step and no CI part, have no `.sh` form to fall back to, and run by hand only after
an icon or tagline change; rewriting them in bash would mean a new image renderer, which no criterion asks for
(criterion 4 forbids naming the `.ps1` *form of a script*, and they have no other form). `.gitattributes` keeps
`*.ps1 text eol=lf` for the three. No fixture directory goes; `tests/fixtures/drive/README.txt` and
`tests/fixtures/gate/README.txt` drop "and tests/smoke-<x>.ps1".

**2. The check.** In `tests/check.sh`:

- The 27 `add ps` lines go: 51 steps (the lint, 48 `bash`, 2 `claude`). `first` stays on bash `smoke-slot.sh` and
  `test-spec-template.sh` only; `slow` on bash `test-lintcopy-output.sh` only. No other step gains a mark.
- The `ps` kind goes: the detection block (`ps=""` to its `fi`), the loop that sets
  `PowerShell smoke tests (no pwsh or powershell)`, the runner line `ps) ...`, `bash|ps` in `add` (becomes `bash`), and
  `ps` in the fixture kind check, which becomes `lint|bash|claude`, so a fixture line of kind `ps` fails with the
  existing `check: <file>: unknown kind ps` and exit 2.
- `--powershell` goes from the option loop, both `case` lists and `USAGE`, which becomes
  `usage: tests/check.sh [--quick | --only <step>[,<step>...] | --affected [--within <step>[,<step>...]]] [--jobs <1-16>] [--summary <file>]`;
  `--powershell <x>` is then a usage error (exit 2).
- The platform block (from the comment at line 429 to the end of its `if`) goes: the check does not read
  `verification.platform`, prints no note for any value, and skips nothing for it. The header loses the `ps <file>`
  and `--powershell` lines, and its paragraph on the platform (lines 30 to 34) becomes exactly
  `# verification.platform is not read (iteration 68): the steps are the same on every platform (on Windows the bash`
  `# tests run in Git Bash), and what the machine cannot run is listed as SKIPPED.`
- The map: every `<x>.ps1` step goes from every map line; the 4 lines whose pattern is a `.ps1` file go; a line left
  without a step goes; `shared tests/check.ps1` stays. The map comment "a script is always scripts/<x>.*, so both
  twins select the tests of both shells" becomes "a script is scripts/<x>.*". Other comments that speak of "both
  shells" or "both families" say "the tests".

`tests/check.ps1`: the `-PowerShell` parameter, its help line and its `--powershell` line go, and `[-PowerShell
powershell|pwsh]` leaves the usage line; nothing else changes.

**3. CI, the required checks and the order of the ruleset change.** In `.github/workflows/ci.yml`:

- The jobs `smoke-powershell-part` and `smoke-powershell` (lines 46 to 100, 55 lines) go.
- The job `smoke-gitbash` keeps its name, `needs`, `if: always()`, `runs-on`, `timeout-minutes: 5` and its step
  `Every Git Bash part succeeded`, and gains, in this order: below `timeout-minutes`, the comment line
  `    # The one job-level permissions block (iteration 55 decision 11): the job times need actions: read.` and the
  block `    permissions:` / `      contents: read` / `      actions: read`; as its first step the same pinned
  `actions/checkout` line the other jobs use; as its last step the `Job times` step of the removed job, word for word,
  with `--parts 'Git Bash smoke part '` in place of `--parts 'PowerShell smoke part '`. Its comment becomes
  `    # The Git Bash parts together (iteration 66). Not a required check until #390 makes it one.`
- Nothing else changes: `lint` and `smoke-bash` keep their names, lists and `Required check` comments; the Git Bash
  parts keep `continue-on-error: true` (#390).

**The required checks**: today `Lint (generic, JSON, skills, shell)`, `bash scripts smoke tests` and
`PowerShell scripts smoke tests`. After the merge no job reports the third name, so it must leave the ruleset; no job
keeps the name as a stand-in, because a job that only says success under a PowerShell name is the track the story
removes. The remaining two run on every event (no `if:`, no path filter, as the lint already holds), so they report on
every pull request. The order applies to this iteration's one pull request, which states it in a section
`## Ruleset` of its body:

1. The maintainer cuts the release that carries iteration 67 (#364) with `scripts/release.sh --version X.Y.Z` (per
   `.claude/CLAUDE.md` "CHANGELOG by version": merge the release pull request it opens, then `--publish` to tag),
   before this pull request merges. That release takes iterations 65 to 67 out of `Unreleased`; it is the release
   before this one that record 0004 step 3 asks for and that the changelog bullet (decision 12) tells a project to pin.
   The pull request may be opened before it; it is not merged before it, and it is brought up to date with `main`
   after it (decision 12).
2. The pull request is opened; its own run cannot report `PowerShell scripts smoke tests` (it waits as expected).
   "How verified" shows `Lint (generic, JSON, skills, shell)` and `bash scripts smoke tests` green and every Git Bash
   part's check step log ending `SELECTED CHECKS PASSED (<k> of 51 steps; the full check has not run)`, the `<k>`
   adding up to 47 (the change touches `tests/check.sh` and `ci.yml`, shared paths, so every part runs its whole list;
   the parts do not fail on a red step, so the log is the evidence).
3. The maintainer removes `PowerShell scripts smoke tests` from the required status checks of the ruleset on `main`
   (by hand; no code here changes the ruleset).
4. The maintainer merges the pull request with `gh pr merge <n> --auto --squash`.
5. Nothing is added to the ruleset here: `Git Bash scripts smoke tests` becomes required in #390.

Between steps 3 and 4 other open pull requests still run the PowerShell parts, no longer required (Risks).

**4. The CI tests follow the jobs.**

- `tests/test-ci-parts.sh`: rules 1 to 6 (the PowerShell parts) and the part of rule 7 that pins the PowerShell final
  job go, with their cases (`noguard` to `dashrun`, `noalways`, `nosuccess`, `numbers`, `of5`, `norunonly`); the Job
  times check of rule 7 and rule 8 now read the job `smoke-gitbash`: the Job times text becomes
  `the job smoke-gitbash has no Job times step (a step that runs tests/ci-jobs-summary.sh with if: always() and continue-on-error: true)`,
  rule 8 allows the job-level block only in `smoke-gitbash` (`(only smoke-gitbash may, with contents: read and actions: read)`,
  `the job smoke-gitbash's 'permissions:' block is not exactly 'contents: read' and 'actions: read'`), and its cases
  `actionswrite`, `checksread`, `noperm` act on that job. Rules 10a, 10b and 11 and their cases are unchanged (10b
  fails only on a step that runs `tests/check.sh`, which the new checkout and Job times steps do not). The header says
  what is left; the OK line becomes `OK: the CI parts`.
- `tests/test-ci-job-times.sh`: the same cases on the job `smoke-gitbash` (its insert after
  `          echo "the Git Bash parts: `).
- `tests/test-ci-run-steps.sh` (bug #296): the same three cases on the job `smoke-gitbash-part` and its run line
  `        run: bash tests/check.sh --summary`, each expecting rule 10a's `the Git Bash parts are malformed (` line.
- `tests/ci-jobs-summary.sh` line 97 prints
  `The parts (<prefix without its trailing space>): <duration> from the start of the first part to the end of the last (<n> parts).`
  instead of the fixed name `PowerShell scripts smoke tests`. In `tests/fixtures/ci-summary/jobs.tsv` and `jobs.md`
  every `PowerShell smoke part` becomes `Git Bash smoke part` and every `PowerShell scripts smoke tests` becomes
  `Git Bash smoke tests (Windows, not blocking)`; `jobs.md` line 14 becomes
  `The parts (Git Bash smoke part): 9m20s from the start of the first part to the end of the last (4 parts).`;
  `tests/test-ci-summary.sh` passes `--parts 'Git Bash smoke part '` and pins the new row and chain lines.
- `tests/lint.sh`: the two required-name loops and the heredoc hold `Lint (generic, JSON, skills, shell)` and
  `bash scripts smoke tests` only; the `Required check` comment count is 2 with the text
  `(exactly 2 expected, one per required job)`; the comment "a check such as 'PowerShell scripts smoke tests (1)'"
  names `'bash scripts smoke tests (1)'`; in `== CI selects the steps a pull request affects` the allowed
  `if: always()` is that of `smoke-gitbash` only, the step-level `if:` check reads `lint` and `smoke-bash`, and
  `depth smoke-powershell-part` goes; "three required names" in comments becomes "two"; `== CI runs with least
  privilege` says `smoke-gitbash` where it says `smoke-powershell`; the section `== the PowerShell job runs in parts`
  is renamed `== the CI parts are well formed` and its comment describes rules 7 to 11.

**5. The lint stops expecting a twin.** In `tests/lint.sh`:

- `== the check starts the longest steps first`: `want_firsts` is
  `add bash smoke-slot.sh first|add bash test-spec-template.sh first|`.
- `== the check runs every smoke script`: the step-list pattern is `^add (lint|bash) ...` (an `add ps` line makes the
  list malformed); `want_slows` is `bash test-lintcopy-output.sh|`; `chk_prof` starts empty (its three `.ps1` files
  go; the slow steps are still added); the loop reads `tests/smoke-*.sh` only and the kind check `bash` only; the
  comment says the bash job and the Git Bash parts.
- `== every script and every test step is in the map`: the loop reads `scripts/*.sh scripts/lib/*`; rule 5 ("twins
  select the same steps") goes; the line `map scripts/lib/ledger.ps1 ...` goes with decision 2.
- Every section that pins a script lists only its `.sh`, `.awk` and README forms: the entries `tests/smoke-<x>.ps1`,
  `tests/test-<x>.ps1`, `scripts/<x>.ps1` and `scripts/lib/<x>.ps1` of these sections go, and so do the checks below
  that read only a `.ps1`. In full: the `.ps1` entries of the file loops and word lists go (status, template board,
  models, slot, capacity, report, stage record, history, load, room, control, dashboard, slots pane, reviewer pairing),
  and so do the checks that read only a `.ps1` (`scripts/validate-config.ps1` pairing text, `scripts/models.ps1` roles,
  `-Capacity`, `-Report`, `scripts/lib/load.ps1` readers, `scripts/room.ps1` words, `scripts/control.ps1` actions and
  words, `scripts/dashboard.ps1` and `scripts/status.ps1 -Porcelain`, `scripts/panel.ps1 -Status -Porcelain`). The
  slots pane section drops `'Windows_NT'`, `'scripts/panel.ps1'` and the README word `panel.ps1`, and `'slot.ps1'`
  from the words `hooks/panel.tsx` must not contain.
- `== the PowerShell scripts read the config with exact keys (#329)` goes (there is no such script).
- `== one interpreter runs a warm-up command` runs `bash tests/test-warmup-interpreter.sh` only.
- `== the skills, the agents and the README name the .sh form only (#364)`: the `dev` mode of `sh_only_scan` and its
  call, the exemption of the pane line, and the loop that wants `scripts/<x>.ps1` to exist (with its `so_s.ps1`) go;
  its comment loses "The .ps1 files still ship (#365 removes them) ..."; the `skill`, `agent` and `user` modes and the
  changelog words of iteration 67 stay.
- `== the lists and the shell twins agree` is renamed `== the README lists every smoke file`; in
  `tests/test-lint-agreement.sh` the twin rules go (the loop `has no PowerShell twin tests/<x>.ps1`, `twin_exceptions`
  with its two texts and `is_exception`, the loop `has no PowerShell twin scripts/<x>.ps1`), and its README parser
  reads only `bash tests/smoke-<x>.sh` lines (the `ps` branch and the rule `runs ... in the wrong shell` go). Its
  self-tests `shell`, `no twin`, `exception gone`, `exception twinned` and `script` go, `twice` uses a `.sh` line, and a
  new one `no twin needed` (`tests/smoke-b.sh` with its README line and `scripts/b.sh`, no `.ps1`) prints nothing; the
  OK line becomes `OK: the README lists every smoke file`. `tests/test-lint-agreement-cases.sh` drops the `.ps1` files
  of its scratch trees and the cases of the removed rules, and keeps the others. Its cost bound
  (`tests/test-lint-agreement-cost.sh`) is unchanged; its history comment (lines 3 and 4) names no removed file. The
  section's comment (lines 1577 and 1578, "every tests/smoke-*.sh has a .ps1 twin ..., every scripts/*.sh has a .ps1
  twin") becomes
  `# Iteration 51 (#157): the README lists every tests/smoke-*.sh once. The rule lives in tests/test-lint-agreement.sh.`
- **The comments of `tests/lint.sh` that name a removed file or speak of two shells.** Rule 2 of decision 6 reads
  comments too (`grep -noE '[A-Za-z0-9_-]+\.ps1' tests/lint.sh`); besides the code lines of the sections above, two
  comment lines name a script's `.ps1` outside a section that this spec rewrites (line 1524 is in the section
  decision 4 rewrites; lines 1944 and 1945 in the section that goes). They and the stale "both shells" comments
  become, word for word:
  - lines 1702 and 1703 (`== the guard reads a GraphQL keyword ...`) become
    `# Iteration 50 (#253): an operation named query, subscription or fragment stays the kind its first name says, in`
    and `# scripts/guard.sh. The cases live in tests/test-guard-gql-keyword.sh.` (line 1704 goes; its text is in the
    new 1703).
  - lines 740 to 742 (`== the stage record is wired`) become
    `# The time a story spends in each stage is recorded and shown (iteration 41): scripts/slot.sh appends one line per`,
    `# take, report and freeing to <worktrees.root>/.slots/ledger.tsv; scripts/stages.sh prints the table;` and
    `# tests/check.sh and CI run its smoke test; the README says where the record lives and how to` (line 743 stays).
  - lines 235 to 237 (`== reviewer pairing is checked`, "Both shells carry the rule, ...") become
    `# The validator (scripts/lib/validate.awk) rejects a reviewer ranked below the role it reviews and warns about a`
    and `# model that is not in models.ranking (iteration 15); a change that drops the rule fails here.`, with the
    check of `scripts/validate-config.ps1` (bullet above).
  - line 680 (`== slots free themselves`): "(iteration 17), in both shells, with the tip check" becomes
    "(iteration 17), with the tip check".
  - lines 1738 and 1739 (`== one interpreter runs a warm-up command`) become the one line
    `# Bug #133: slot.sh and new-worktree.sh run worktrees.warmup[].command in bash, and the schema says so.`
  - "tests/smoke-check.sh/.ps1" becomes "tests/smoke-check.sh" in the comments at lines 1531, 1538, 1539, 1580,
    1585, 1979, 1985 and 1992. `/.ps1` is no match of rule 2, so this is for the reader, not for the rule.
  After the change, with these and the sections above, `grep -noE '[A-Za-z0-9_-]+\.ps1' tests/lint.sh` prints only
  `check.ps1` (today line 1512, `shared tests/check.ps1` of the map rule); the names decision 12 adds are built from a
  variable and do not match.

**6. A guard that no PowerShell script comes back, or is named.** A new bash file `tests/test-no-powershell.sh
[<root>]`, started once by `tests/lint.sh` in a new section `== no PowerShell script is left, and none is named (#365)`
placed directly before `== shell` (outside the range the lint copies of `tests/smoke-check.sh` run). Both rules are
fully on:

- Rule 1: the files under `<root>` whose name ends in `.ps1`, `.psm1` or `.psd1` in any case, `.git/` and `tmp/`
  pruned, are among exactly `tests/check.ps1`, `tools/make-icon.ps1`, `tools/make-social-preview.ps1`; each other one
  prints
  `FAIL: <path> is a PowerShell file; only tests/check.ps1, tools/make-icon.ps1 and tools/make-social-preview.ps1 are left (decision record 0004)`.
  A listed file that is missing is no failure.
- Rule 2: every text file of `<root>` (`git -C <root> ls-files -co --exclude-standard` when `<root>` is the top of a
  work tree, else every file under it with `.git/` pruned; binary files skipped by `grep -I`), except paths under
  `docs/`, `CHANGELOG.md` and the three files of rule 1, is read in one `grep` over all files (bug #270: no process
  per file) for the extended pattern `[A-Za-z0-9_-]+\.ps1`; each match whose name is not `check.ps1`,
  `make-icon.ps1` or `make-social-preview.ps1` prints `FAIL: <path>:<n> names <name>, which is gone (#365)`.
  `*.ps1` (`.gitattributes`, `tests/test-docs-low-gaps.sh`) does not match. Every hit of the sweep in Facts is
  removed or reworded by decisions 1 to 11, so on the branch rule 2 prints nothing.
- The file's own cases run after the rules, on scratch trees, and build every `.ps1` name from a variable
  (`ext=ps1`, `"scripts/a.$ext"`), so the file itself names none: a tree with the three files prints nothing; with
  `scripts/a.<ext>` added rule 1 prints its line; with `tools/x/Y.PS1` and `scripts/lib/m.psm1` one line each; a
  README naming `slot.<ext>` prints rule 2's line with `README.md:<n>`, and so does one naming `tests/smoke-a.<ext>`;
  a README naming `tests/check.<ext>`, `tools/make-icon.<ext>` and `*.<ext>` prints nothing; `docs/a.md` and
  `CHANGELOG.md` naming `slot.<ext>` print nothing.
- Exit 1 on any failure, else `OK: no PowerShell script is left or named`.

The changelog check of decision 12 is in the same lint section.

This is also #390's item 1 (the freeze lint), with the list of the three files left (Left item 3).

**7. `verification.platform` stays readable and says what it does now.**

- Schema, `verification.properties.platform`: `type`, `enum`, `default` unchanged; the description becomes exactly
  `"The platform the project runs on, for a check command that reads it. windows is Windows (the bash tests run in Git Bash, from Git for Windows), unix is Linux or macOS, all is a project worked on from both. nightmill's own tests/check.sh does not read it (iteration 68): its tests are bash only and the same on every platform, and it lists what the machine cannot run. /nightmill:init proposes the detected platform."`
- `templates/nightmill.example.json` keeps `"platform": "all"`, and `.claude/nightmill.json` keeps `"windows"`:
  both stay valid.
- README, the `verification` row of the configuration table, its end from "and which test families the check runs"
  becomes "and the platform the project runs on (`platform`: `windows`, `unix` or `all`, default `all`, for a check that
  reads it; nightmill's own check does not read it and runs the bash tests on every platform)".
- README, `## Developing nightmill`: the sentence "With `verification.platform` set to `windows` or `unix`, ... through
  `--only`." becomes "`tests/check.sh` runs the same steps on every platform (the bash tests in Git Bash on Windows)
  and does not read `verification.platform`; it lists what the machine cannot run as `SKIPPED:`."; "the tests of a
  changed script in both shells" becomes "the tests of a changed script".
- `skills/init/SKILL.md` question 8 (line 56) becomes exactly
  `8. **platform** (`verification.platform`): `windows` for Windows or `unix` for Linux and macOS, or `all` for a project worked on from both; read only by a check command that reads it (nightmill's own check runs the bash tests on every platform, in Git Bash on Windows). An empty answer deletes the key`
  Line 42 (the detection) is unchanged.
- `tests/lint.sh`, the platform block: the description must contain `tests/check.sh does not read it`, else
  `FAIL: schema: verification.platform's description does not say tests/check.sh does not read it` (in place of the
  iteration 65 check); the other checks stay (`tests/check.sh` still names `verification.platform`, in its header).

**8. The slots pane on Windows.** `hooks/panel.tsx` runs `['bash', `${root}/scripts/panel.sh`]` on every platform:
the `OS` read and `isWindows` go, and the header (line 5) says "The data comes only from scripts/panel.sh, run with
bash (on Windows the bash on the PATH of Claude Code's process, Git Bash from Git for Windows), ...". Where no bash
starts, the existing path draws `unknown` with `the panel script did not run: <message>`; nothing new is decided in
the module. `hooks/panel.test.tsx`: the test `on Windows the pane runs scripts/panel.ps1 with Windows PowerShell`
becomes `on Windows too the pane runs scripts/panel.sh with bash` (`world.os.current = 'Windows_NT'`; argv length 2,
`argv[0]` `bash`, `argv[1]` matches `/^.+\/scripts\/panel\.sh$/`, cwd `/work`, `timeoutMs` 20000); the other tests
stay. README line 675 becomes "The pane runs `scripts/panel.sh` with bash on every platform; on Windows that is the
`bash` on the PATH of Claude Code's process (Git Bash, from Git for Windows), and where none starts the pane shows the
slots as unknown with the reason."

**9. The two templates.**

- `templates/CLAUDE.snippet.md` line 7: "Worktree slots: `slot.sh` in the plugin's `scripts/` folder."
- `templates/workflows/nightmill-drive.yml`: the step `Run the driver (Windows)` goes; the other step loses its
  `if:`, is named `Run the driver`, keeps `shell: bash` (Git Bash on a Windows runner), and its awk program gains
  `gsub(/\\\\/, "/");` directly before `print`, so a Windows install path, JSON-escaped as `C:\\Users\\...`, becomes
  `C:/Users/...`; header line 6 says "runs scripts/drive.sh of the installed nightmill plugin in the main checkout
  (in Git Bash on a Windows runner),". `tests/test-drive-docs.sh` line 94 then wants no `shell: pwsh` and no `drive.`
  followed by `ps1` (the check of rule 2 covers the name too).

**10. Every text names the `.sh` form or nothing.** The texts below are written for the state after the merge.

- **Comments under `scripts/`** (39 lines in 27 files: 38 comment lines and the `echo` of `release.sh` line 285, one
  `.ps1` name each): a clause or sentence that names a `.ps1` twin or says it does the same ("Bash twin of slot.ps1.",
  "Same behaviour as slot.ps1.", "; models.ps1 prints the same.", "PowerShell File.Move" kept only where it explains
  the claim) goes; the rest of the sentence stays; a rule that pointed to the `.ps1` ("The rules are those of
  stages.ps1 (decisions 6 to 10 of ...)") points to the spec it names. `release.sh` line 249 starts
  `# The line ends (iteration 57, #329):`, and line 285 prints
  ``After this merges, run `scripts/release.sh --version $version --publish` to tag it and create the GitHub Release.``
  `scripts/guard.sh` keeps every mention of the PowerShell *tool* (`Bash|PowerShell`), and `scripts/lib/json.awk` its
  note on the byte order mark Windows PowerShell writes. `scripts/slot.sh`'s sentence
  "Same behaviour as slot.ps1, which prints "<step> stopped" and cannot set the exit code." goes, and with it
  `tests/test-interrupt-docs.sh` changes as decision 11 says.
- **`.claude/CLAUDE.md`** (four places): the rule `- **Bash only.**` becomes exactly

  ```
  - **Bash only.** A script in `scripts/` is bash and runs in bash on Linux and macOS and in Git Bash on Windows
    (decision record 0004); a change to one has a smoke step in `tests/smoke-*.sh`. No PowerShell file is added: the
    lint fails on one that is not on the list of `tests/test-no-powershell.sh`, which holds only `tests/check.ps1`
    (a wrapper that runs `bash tests/check.sh`) and `tools/make-icon.ps1` and `tools/make-social-preview.ps1` (run by
    hand). `tests/check.sh` runs what the machine can run and lists what it skipped; CI runs all of it (bash on
    Ubuntu, and in Git Bash on Windows).
  ```

  "CHANGELOG by version": "`scripts/release.sh --version X.Y.Z` (or `release.ps1`), merges" becomes
  "`scripts/release.sh --version X.Y.Z`, merges". "CI and merging": "a PR merges only when the lint and both smoke-test
  jobs pass" becomes "a PR merges only when the lint and the bash smoke-test job pass". Commands: the two
  `powershell ... tests/smoke-*.ps1` lines go; the `render-templates.ps1` line becomes
  `bash scripts/render-templates.sh --project . --force   # after editing areas or invariants`; the two `tools/` lines
  stay. Layout: `scripts` "each as .ps1 and .sh; lib/ holds what they share (awk, sh and ps1 helpers)" becomes
  "each as .sh; lib/ holds what they share (awk and sh helpers)"; `tests` "lint.sh, smoke-*.sh/.ps1, test-*.sh/.ps1,
  check.sh/.ps1, fixtures/" becomes "lint.sh, smoke-*.sh, test-*.sh, check.sh and check.ps1 (its wrapper for a
  PowerShell prompt), fixtures/".
- **`.claude/nightmill.json`**: `parallel.hotFiles` drops `"scripts/slot.ps1"` (a value, no key).
- **`schema/nightmill.schema.json`**, `worktrees.warmup[].command`: the description becomes
  `"One command line, run by bash: bash -c in slot.sh and new-worktree.sh (on Windows in Git Bash). Write it in bash syntax (&&, $VAR, quoting)."`
- **`README.md`**: the 19 `powershell -ExecutionPolicy Bypass -File tests/smoke-*.ps1` lines of `## Developing
  nightmill` (lines 1104 to 1122) go; the CI sentence from "CI runs the smoke jobs through `tests/check.sh`:" to "runs
  in no part or in two." becomes "CI runs the smoke jobs through `tests/check.sh`: the bash test steps on Ubuntu, and
  all of them but `test-lintcopy-output.sh` (the Ubuntu job runs that one) in Git Bash in seven parts on seven Windows
  runners at once (decision record 0004), the longest steps alone in theirs; a further job, `Git Bash smoke tests
  (Windows, not blocking)`, fails unless every part succeeded; it is not a required check yet (#390), and a failing
  step shows in its part's summary without failing the part; the lint fails when a bash step runs in no Git Bash part
  or in two."; the pane line (decision 8), the `verification` row and the platform sentences (decision 7).
  `check.ps1 -Summary <file>` stays (the wrapper has it). The hook lines 98 and 217 and the tool lines 199, 357, 362
  stay (the PowerShell tool and hook shell, not a script).
- **`CONTRIBUTING.md`**: line 45 "the bash smoke tests, the PowerShell smoke tests (when PowerShell is installed),"
  becomes "the bash smoke tests,"; line 50 "the bash ones on Ubuntu and in Git Bash on Windows, the PowerShell ones on
  Windows," becomes "the bash ones on Ubuntu and in Git Bash on Windows,"; line 55 stays.
- **`.github/pull_request_template.md`** line 12 becomes `- [ ] A changed script has a smoke step in the bash tests`.

**11. The bash tests that named or started a `.ps1`.** What follows the check, CI and the removed tests, every test
that *starts* a `.ps1` script, and every pin or comment that *reads the text* of a `.ps1` script or names one:

- `tests/smoke-check.sh`: `USAGE` as in decision 2; `usage_case --powershell cmd` becomes `usage_case --powershell pwsh`
  (now an unknown option); the `cp` lines copy `tests/check.sh` without `tests/check.ps1`, and `mkcopy` copies
  `tests/*.sh` and `scripts/*.sh` only. The section `== the platform from the config` becomes
  `== verification.platform is not read`: fixture steps `l` (lint), `b` (bash), `c` (claude); for each of `"windows"`,
  `"unix"`, `"all"`, no key, `"linux"` and `3`: exit 0, log `l,b,c,`, no `SKIPPED:` line, standard error empty, last
  line `ALL CHECKS PASSED`; and a fixture line of kind `ps` exits 2 with `check: <file>: unknown kind ps` on standard
  error. In `== affected` and the slow and `--within` cases the fixture steps `p1` and `p2` keep their names and become
  kind `bash`, every changed path `scripts/foo.ps1` becomes `scripts/foo.sh`, `aff_cfg` always writes no platform key,
  and the cases that only show the platform's effect go (the `for plat` loop "a changed script runs its tests in both
  shells", "the PowerShell steps of the list ... unix", "the bash steps ... windows"); the step counts, verdict lines
  and summary lines of the others stay. `== the slowest steps of the real list start first` pins only the bash marks of
  decision 2. The `lint_break` cases: `cips`, the twin-map case (`scripts/slot.sh and scripts/slot.ps1 map to
  different steps`) and `shdev` (with the `dev` mode it breaks, decision 5) go; `cibegins` renames
  `claude plugin validate (not blocking)` to `bash scripts smoke tests (1)`; `cidepth`'s range ends at
  `/^  smoke-gitbash-part:$/`; `slowformat` turns `add bash test-lintcopy-output.sh slow` into `... slow first`,
  `slowset` drops its `slow`, `slownote` deletes the `# Time: ` line of `tests/test-lintcopy-output.sh`;
  `platformmeaning` replaces `tests/check.sh does not read it` and expects `does not say tests/check.sh does not read
  it`; `shskill`, `shreadme` and `initps` inject the PowerShell form without a `.ps1` name and expect the same texts as
  today: `shskill` replaces the status call by
  `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh"` (caught as
  `powershell`), `shreadme` replaces `bash scripts/load.sh [--porcelain]` by `bash scripts/load.sh -Porcelain` (caught
  by the parameter pattern, which needs a space, a backtick, `(` or `/` before the dash), and `initps` adds
  `Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "<P>/scripts/<name>.sh" *)` (caught as `Bash(powershell`).
- `tests/smoke-slot.sh`: claim 7's block "across the shells" (`bg_ps`, `ps_slot`, the skip line) goes; the reader
  cases 1 to 4 stay (they start `powershell -Command`, a Windows tool, no script).
- `tests/smoke-stages.sh` line 166: copies `tests/check.sh` only.
- `tests/test-lintcopy-output.sh`: the `ps1_ok` text check of `tests/smoke-check.ps1` goes, and its comments name no
  removed file.
- `tests/test-guard-gql-keyword.sh`: the PowerShell half (lines 46 to 57: `ps=""`, `run_ps`, its skip line) goes, and
  header line 4 ends "`query mutation { viewer }` passes, in scripts/guard.sh." (the clause "and, when a PowerShell is
  on the PATH, scripts/guard.ps1" goes). `tests/test-guard-rules.sh` reads `scripts/guard.sh` only (line 36;
  `Bash|PowerShell` stays).
- `tests/test-interrupt-docs.sh`: header lines 2 to 4 become
  `# tests/test-interrupt-docs.sh - the README and the header comment of scripts/slot.sh describe what an interruption`,
  `# of a take does (iteration 36, #190): the paragraph after "Retries (iteration 35)" in scripts/slot.sh, and the`
  and `# sentences in the README's "Why slots".`; the pin of the `scripts/slot.sh` sentence that names `slot.ps1`
  (line 29) goes from its list, and the block that reads the header of `scripts/slot.ps1` (lines 39 to 47) goes.
- `tests/test-config-from-base.sh`: the `.ps1` pins (lines 79, 85, 89, 91, 93) go. `tests/test-limits-docs.sh`
  reads `scripts/drive.sh` only (lines 144 to 152, the `*.ps1)` branch with its `ledger.ps1` message too); line 131
  stays (an absence check that names `gate.ps1`, reworded to build the name, `gate.$ext`); its pin of
  `tests/smoke-gate.ps1` (line 168) goes. `tests/test-drive-docs.sh` reads `scripts/drive.sh` only (lines 21 to 30),
  its header line 4 drops "(history.ps1)", and decision 9.
- `tests/test-docs-low-gaps.sh`: item (f)'s check (line 138 on, which reads every `*.ps1` left, now the three files)
  is unchanged; its header line 14 drops the parenthesis `(tests/smoke-render.ps1)`, so lines 13 and 14 end
  "Windows PowerShell 5.1 reads a file without one as ANSI".
- `tests/test-ci-job-name-rule.sh` line 6 becomes
  `# The rule itself is pinned by the lint_break case "cibegins" in tests/smoke-check.sh.`; nothing else changes.
- `tests/smoke-dashboard.sh` line 198 and `tests/smoke-panel.sh` line 162: the comment `# #329: slot.sh and slot.ps1
  both list that slot as busy and unknown` becomes `# #329: slot.sh lists that slot as busy and unknown`; in
  `smoke-dashboard.sh` the rest of the sentence "so status succeeds in both shells" becomes "so status succeeds".
- Header comments of the kept bash tests that say a `.ps1` twin runs the same cases (`smoke-control`, `smoke-dashboard`,
  `smoke-drive`, `smoke-gate`, `smoke-history`, `smoke-load`, `smoke-models`, `smoke-panel`, `smoke-room`,
  `smoke-template-board`, `smoke-validate`, `smoke-check`, `test-slot-low-defects`, `test-warmup-interpreter`,
  `test-json-bom`, `test-slot-number`) lose that clause.
- The sweep in Facts ("Every bash test that names a removed `.ps1`", with its header comments) is the list this
  decision and decisions 2, 4 and 5 cover; after the change `grep -noE '[A-Za-z0-9_-]+\.ps1' tests/*.sh` prints only
  `check.ps1`, `make-icon.ps1` and `make-social-preview.ps1`.

**12. The changelog.** One bullet under `Unreleased` (Files touched), and a lint check in the section of decision 6:
`CHANGELOG.md` (lines joined) contains `Iteration 68 (#365)`, `hand-wired session-start.ps1 or guard.ps1 hook`,
`.ps1 allow rules` and `pin the release before this one`, else `FAIL: CHANGELOG.md does not say: <words> (#365)`
(`<words>` printed as checked, with the names whole). `tests/lint.sh` is not exempt from rule 2, so its word list
builds the two names from a variable, as the cases of decision 6 do: `ps=ps1` and the loop
`for cl_w in 'Iteration 68 (#365)' "hand-wired session-start.$ps or guard.$ps hook" '.ps1 allow rules' 'pin the release before this one'; do`;
`'.ps1 allow rules'` stays literal, since no name character stands before its dot, so rule 2's pattern does not match
it. No other text this spec adds to `tests/lint.sh` or to a test names a `<x>.ps1` other than `check.ps1`,
`make-icon.ps1` and `make-social-preview.ps1`: the iteration 67 changelog words that stay say `the .ps1 files`, the
`lint_break` expectations of decision 11 and the messages of decisions 4, 5 and 7 name none, and decision 6's own
cases and `tests/test-limits-docs.sh` line 131 build the name (`$ext`). Nothing *left* in `tests/lint.sh` names one
either, once every change of decisions 4 and 5 is made, the comment bullet of decision 5 included: the comments at
lines 741 (`scripts/stages.ps1`) and 1703 (`scripts/guard.ps1`) were the two that no section rewrite covered.
`CHANGELOG.md` is outside rule 2, so it may name the `.ps1` files. "The release before this one" is the release the
maintainer cuts from `Unreleased` before the pull request merges (decision 3, step 1), the one that carries
iterations 65 to 67; the pull request is brought up to date with `main` after that release, so iteration 67's bullet
is then in that release's section, this bullet is the first under a new `Unreleased`, and it names that release as
the one a project pins. It is the iteration's only bullet.

**13. One pull request (the maintainer's decision).** #365 is implemented by one `/next` run against this spec, and
all of it lands in one pull request:

- Its title is `Iteration 68: the PowerShell scripts, their tests and the PowerShell CI parts are removed (#365)`, and
  its body says `Closes #365`, so its merge closes the story.
- It carries every decision: the 51 removals (decision 1), the check (2), CI with its `## Ruleset` section (3), the CI
  tests (4), the lint (5), `tests/test-no-powershell.sh` with both rules fully on (6), `verification.platform`
  including `skills/init/SKILL.md` (7), the pane (8), the templates (9), every text (10), the bash tests (11), and the
  one changelog bullet with its lint check (12).
- It changes `hooks/` and `skills/`, so it carries the whole manual check of Tests; its "How verified" has the full
  check on the branch, the parts' logs of decision 3 step 2 and the manual check's steps.
- **It is never auto-merged**: it changes `.claude/` and `.github/`, carries the story trigger, and removes a required
  check. The ruleset steps of decision 3 apply to it in their order: the release is cut first, the maintainer then
  removes the check name from the ruleset, then merges.
- #368 (several pull requests per story) is irrelevant here: the story is closed by this one pull request.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The PowerShell scripts, their smoke tests and their other tests are removed, and `tests/check.ps1` stays as a wrapper | Decisions 1, 2 (`check.ps1`), 6 (rule 1) |
| 2 | The PowerShell steps of the check and the PowerShell CI parts are removed, and the required check names of `main` still report on every pull request (the ruleset change is the maintainer's, said in the pull request) | Decisions 2, 3, 4 |
| 3 | The lint and the README no longer expect a `.ps1` twin | Decisions 5, 10 (README) |
| 4 | No file of the repository outside `docs/` and `CHANGELOG.md` still names a `.ps1` form of a script (`tests/check.ps1` itself stays), including the Commands block of `.claude/CLAUDE.md`, `templates/CLAUDE.snippet.md` and `templates/workflows/nightmill-drive.yml` | Decisions 6 (rule 2), 8, 9, 10, 11 |
| 5 | The changelog says what a project removes (hand-wired `.ps1` hooks, dead `.ps1` allow rules) and that it pins the release before this one until it has done so | Decision 12; Files touched (the bullet) |
| 6 | The check stays green on Linux, macOS and Windows with Git Bash | Decision 3 (the parts' logs); Tests (criterion 6; manual check step 6 for macOS, which has no CI) |

## Tests

The tester writes the failing tests for every criterion before the change.

- Criterion 1: **`tests/test-no-powershell.sh`** rule 1 and its cases (decision 6); it fails on the checkout before
  the change (51 lines, the removed files) and passes after. **`tests/smoke-check.sh`**, the fixture case of kind
  `ps` (`unknown kind ps`, exit 2) and `usage_case --powershell pwsh`. The code reviewer checks `git diff --stat` for
  the 51 removals and the `tests/check.ps1` diff (decision 2: three lines and the usage line).
- Criterion 2: **`tests/lint.sh`** `== the check runs every smoke script` (an `add ps` line is malformed;
  `want_firsts`, `want_slows`), the map section, and the two required names with the comment count 2 (decision 4);
  **`tests/smoke-check.sh`** `== verification.platform is not read`, the changed `== affected` cases and `lint_break`
  cases of decision 11; **`tests/test-ci-parts.sh`**, **`tests/test-ci-job-times.sh`**, **`tests/test-ci-run-steps.sh`**,
  **`tests/test-ci-summary.sh`** as in decision 4 (rule 8 fails when the permissions block is in another job, the Job
  times rule when `smoke-gitbash` has no such step). The required names reporting is seen on the pull request's run
  and stated in its `## Ruleset` (decision 3); no test reads the ruleset.
- Criterion 3: **`tests/test-lint-agreement.sh`** self-test `no twin needed` and **`tests/test-lint-agreement-cases.sh`**
  (a tree of `.sh` files with its README lines and no `.ps1`: no `FAIL`); the lint passes on the checkout with no
  `.ps1` test and no `.ps1` script; the code reviewer checks that the README lists no `.ps1` test.
- Criterion 4: **`tests/test-no-powershell.sh`** rule 2 and its cases; on the branch it prints nothing. The code
  reviewer reads the three named places (`.claude/CLAUDE.md` Commands, `templates/CLAUDE.snippet.md`,
  `templates/workflows/nightmill-drive.yml`) against decisions 9 and 10, and runs
  `git grep -n -E '[A-Za-z0-9_-]+\.ps1' -- . ':!docs' ':!CHANGELOG.md' ':!tests/check.ps1' ':!tools'`, whose every line
  names `check.ps1`, `make-icon.ps1` or `make-social-preview.ps1`. **`tests/test-drive-docs.sh`** (decision 9) and
  **`hooks/panel.test.tsx`** (decision 8, through `claude plugin test`).
- Criterion 5: the lint check of decision 12; the code reviewer checks the bullet word for word.
- Criterion 6: `bash tests/check.sh` is green on the branch (its last line, the `Times:` total, the `SKIPPED:` lines
  in "How verified", 51 steps); on the pull request's run `Lint (generic, JSON, skills, shell)` and
  `bash scripts smoke tests` are green and the seven Git Bash parts' logs end as decision 3 step 2 says. CI covers
  Ubuntu (the lint and the bash job) and Windows in Git Bash (the seven parts) only; there is no macOS CI (#156), so
  macOS is covered by manual check step 6 alone.
- **The manual check** (the session of the `/next` run, step 4 of `/next`), with a separate checkout of the branch
  loaded by `claude --plugin-dir <checkout>` in a test project that is not this repository (never `--plugin-dir .`),
  the project having `worktrees` set:
  1. Windows with Git for Windows: `/nightmill-slots` opens the pane and shows the slot rows (not `unknown` with
     `the panel script did not run`); `/nightmill-slots off` closes it.
  2. Windows: a new session in a project without a config prints the hint (`session-start.sh`); a Bash tool call
     `gh pr merge 5 --squash` is refused by the guard with its one line.
  3. Windows: `/nightmill:init` in a project without `.claude/nightmill.json`, up to the plan, declining at the
     confirmation: question 8 reads as decision 7.
  4. Windows, in a PowerShell prompt in the checkout:
     `powershell -ExecutionPolicy Bypass -File tests/check.ps1 -Only smoke-json.sh` ends `SELECTED CHECKS PASSED`.
  5. Linux or macOS (or WSL): steps 1 and 3.
  6. macOS, in a terminal in the checkout of the branch: `bash tests/check.sh` ends `ALL CHECKS PASSED` (its last
     line, the `Times:` total and the `SKIPPED:` lines go into "How verified"). Where no Mac is at hand the session
     runs it on Linux or WSL instead and says so; what then stays unverified is macOS's own tools (BSD `sed`, `awk`,
     `date`, `find`, `stat` and bash 3.2 where `/bin/bash` is the default), and the step is left to the maintainer.
  Steps 1 to 5 apply because `hooks/` and `skills/` change; step 6 is the evidence for criterion 6 on macOS. The
  steps and what each showed go into "How verified"; a step the session cannot run is named there and left to the
  maintainer.

## Files touched

- Removed (51): `scripts/{control,dashboard,drive,gate,guard,history,load,models,new-worktree,panel,release,render-templates,room,session-start,slot,stages,status,template-board,validate-config}.ps1`,
  `scripts/lib/{baseconfig,exactkeys,ledger,load}.ps1`, the 19 `tests/smoke-*.ps1`, the 9 `tests/test-*.ps1` (Facts).
- `tests/check.sh`, `tests/check.ps1`: decision 2.
- `.github/workflows/ci.yml`: decision 3.
- `tests/test-ci-parts.sh`, `tests/test-ci-job-times.sh`, `tests/test-ci-run-steps.sh`, `tests/ci-jobs-summary.sh`,
  `tests/test-ci-summary.sh`, `tests/fixtures/ci-summary/jobs.tsv`, `tests/fixtures/ci-summary/jobs.md`: decision 4.
- `tests/lint.sh`: decisions 4, 5 (the comments at lines 235 to 237, 680, 740 to 742, 1577 and 1578, 1702 to 1704,
  1738 and 1739, and the `tests/smoke-check.sh/.ps1` comments at 1531, 1538, 1539, 1580, 1585, 1979, 1985 and 1992
  included), 6 (the section, with the changelog check), 7, 12.
- `tests/test-lint-agreement.sh`, `tests/test-lint-agreement-cases.sh`, `tests/test-lint-agreement-cost.sh`:
  decision 5.
- `tests/test-no-powershell.sh` (new): decision 6.
- `schema/nightmill.schema.json` (`verification.platform`: decision 7; `worktrees.warmup[].command`: decision 10),
  `skills/init/SKILL.md`: decision 7.
- `hooks/panel.tsx`, `hooks/panel.test.tsx`: decision 8.
- `templates/CLAUDE.snippet.md`, `templates/workflows/nightmill-drive.yml`: decision 9.
- The 27 files under `scripts/` of Facts, `.claude/CLAUDE.md`, `.claude/nightmill.json`, `README.md`,
  `CONTRIBUTING.md`, `.github/pull_request_template.md`, `tests/fixtures/drive/README.txt`,
  `tests/fixtures/gate/README.txt`: decisions 1, 7, 8, 10.
- `tests/smoke-check.sh`, `tests/smoke-slot.sh`, `tests/smoke-stages.sh`, `tests/test-lintcopy-output.sh`,
  `tests/test-guard-gql-keyword.sh` (lines 4 and 46 to 57), `tests/test-guard-rules.sh`,
  `tests/test-interrupt-docs.sh` (header lines 2 to 4, line 29, lines 39 to 47), `tests/test-config-from-base.sh`,
  `tests/test-limits-docs.sh` (lines 131, 144 to 152, 168), `tests/test-drive-docs.sh` (lines 4, 21 to 30, 94),
  `tests/test-docs-low-gaps.sh` (header line 14), `tests/test-ci-job-name-rule.sh` (line 6), the comments of
  `tests/smoke-dashboard.sh` line 198 and `tests/smoke-panel.sh` line 162, and the header comments of decision 11:
  decision 11.
- `CHANGELOG.md`, one bullet under `Unreleased`, which the release of decision 3 step 1 has emptied (iteration 67's
  bullet is then in that release's section; the pull request is brought up to date with `main` after it):

  ```
  - Iteration 68 (#365): the PowerShell scripts, their tests and the PowerShell CI parts are removed (decision record
    0004, step 4): every script is bash and runs in bash on Linux and macOS and in Git Bash on Windows, and the check
    and CI run the bash tests only. A project removes two things from its settings before it takes this release: a
    hand-wired session-start.ps1 or guard.ps1 hook (hooks/hooks.json already runs the .sh form), and the .ps1 allow
    rules /nightmill:init wrote before iteration 67, which match nothing now. Until it has done so, it should pin the
    release before this one, the one that carries iteration 67 (#364). On Windows the slots pane runs scripts/panel.sh with bash, and the driver's workflow
    template runs drive.sh in Git Bash. tests/check.ps1 stays, a wrapper for a PowerShell prompt that runs bash
    tests/check.sh. verification.platform keeps its values and default; nightmill's own check no longer reads it.
  ```

  With its lines joined it holds the four lint words of decision 12.

Not touched: `agents/`, `hooks/hooks.json`, `templates/nightmill.example.json`, `templates/ISSUE_TEMPLATE/`,
`.github/ISSUE_TEMPLATE/`, `tools/`, `.gitattributes`, `docs/`.

## Risks

- **Windows loses its blocking CI check until #390.** After step 3 of decision 3 the required checks run on Ubuntu
  only; the Git Bash parts run every bash step on Windows but do not fail on a red one. A Windows break shows in the
  parts' summaries, not as a red check. #390 item 2 closes it; the maintainer may take #390 first (Left item 2).
- **The ruleset step.** The pull request cannot merge before the maintainer removes the name; between that and the
  merge, other open pull requests run the PowerShell parts without needing them. If the pull request is then not
  merged, the name must be added back by hand.
- **One large change.** The pull request is size L (Size estimate); a slip in one part (the check, CI, the lint or a
  test pin) holds back the whole. The check on the branch and the code reviewer's `git grep` of Tests are the guard;
  a red part is fixed in the same pull request.
- **The pane on Windows** depends on `bash` being found from Claude Code's process: Git for Windows' default install
  puts `git` on the PATH but not always `bash.exe`, and a WSL `System32\bash.exe` may be found first. The pane then
  shows `unknown` with the reason rather than failing; manual check step 1 shows which it is (Left item 4).
- **A hand-wired `.ps1` hook breaks** in a project that upgrades without reading the changelog: the hook command fails
  to find its file. Claude Code treats a failing SessionStart hook as no output and a failing PreToolUse hook (exit
  other than 2) as allow, so a lost guard lets calls through; the changelog names the fix.
- **A missed reference.** Rule 2 of decision 6 fails on any remaining `.ps1` name; references to PowerShell without a
  `.ps1` (comments that say "both shells") are the code reviewer's to find.
- **Parallel work.** `parallel.hotFiles` changes here (`scripts/slot.ps1` leaves it) and `schema/nightmill.schema.json`
  is a hot file; the pull request conflicts with any open change to `tests/check.sh`, `tests/lint.sh`, `ci.yml` or the
  scripts' headers, so it runs alone.
- **The local check on this repository's Windows machine** stays as iteration 65 left it (the bash steps in Git Bash,
  2 to 3 hours for a full check); the full check runs once before the commit, as iteration 65 decision 8 describes.

## Size estimate

`L`: about 1000 changed lines besides the 51 removed files (15708 lines removed with `git rm`). `tests/check.sh` about
120 (27 step lines, 35 map lines, the `ps` kind, the option and the platform block), `tests/lint.sh` about 130,
`tests/smoke-check.sh` about 110, `tests/test-ci-parts.sh` about 170 (mostly removed rules and cases), the other CI tests
and fixtures about 90, `tests/test-lint-agreement*.sh` about 60, `tests/test-no-powershell.sh` about 70 (new), the other
bash tests about 100, `.github/workflows/ci.yml` about 75, comments under `scripts/` about 45, `README.md` about 35,
`.claude/CLAUDE.md` about 15, hooks about 20, templates about 15, schema, init, config, CONTRIBUTING and PR template
about 10, CHANGELOG 8. Most of it is removal, but it is more than one implementation context holds comfortably: one
context is tight, and the implementer may need its fix rounds (the check, the code reviewer's findings) to finish. The
maintainer decided on one pull request (decision 13), so it is implemented as one.

## Not done

- Rewriting or removing `tools/make-icon.ps1` and `tools/make-social-preview.ps1` (decision 1, Left item 5).
- Emptying the story's `grep -rn '\.ps1'` outside `docs/`. This spec departs from that agent note on purpose: after
  the change it still prints lines, because `tests/check.ps1` stays (criterion 1), `tools/*.ps1` stay (decision 1),
  `.gitattributes` keeps `*.ps1`, `tests/test-docs-low-gaps.sh` reads `*.ps1`, and the texts that name the wrapper or
  the tools stay. The measure is criterion 4's: rule 2 of decision 6 and the `git grep` of Tests, criterion 4.
- Making the Git Bash jobs blocking or required, renaming `smoke-gitbash`, or rebalancing its parts (#390, iteration
  66); adding `first` marks to bash steps now that the PowerShell ones are gone.
- Removing or renaming `verification.platform` or a value of it, or question 8 of `/nightmill:init`.
- Removing a project's `.ps1` allow rules or hooks for it, or any init step that removes a rule.
- The PowerShell *tool*: the hook matcher `Bash|PowerShell`, `agents/worker.md`'s `tools:` line, the guard's handling
  of PowerShell tool calls, and the README lines on them; Windows PowerShell 5.1's byte order mark in the config readers.
- The `Shell used for the scripts` options of `.github/ISSUE_TEMPLATE/nightmill-bug.yml` (`PowerShell`, `Both`): a
  project pinned to an earlier release can still report a bug there.
- The invariant text in `.claude/nightmill.json` and the issue forms ("the PowerShell files are frozen, and no new one
  is added"), which stays true for the three files.
- Another runtime (record 0004's third option) and macOS CI (#156).

## Left

1. **Size: one pull request is decided.** The maintainer decided that #365 lands in one pull request (decision 13):
   `Closes #365`, never auto-merged, with the ruleset steps of decision 3. It is size L and one context is tight
   (Size estimate). Nothing is left to decide here; #368 (several pull requests per story) is irrelevant to it.
2. **#390 and the Windows gap.** After this iteration Windows has no blocking check (Risks). Taking #390 item 2 (the
   Git Bash parts blocking and `Git Bash scripts smoke tests` required) before #365 would close the gap first; its
   budget was not met in iteration 65. The maintainer decides the order.
3. **Overlap with #390 item 1.** Decision 6 is #390's freeze lint (no new PowerShell file) with a list of three files
   instead of 54, and decision 5 removes the twin rules that #390 item 1 also removes. After this iteration #390 keeps
   only its item 2; its body should then be trimmed by the maintainer.
4. **The pane's bash on Windows.** Decision 8 takes `bash` from the PATH. If manual check step 1 shows the pane cannot
   start it on a usual Git for Windows install, the session reports it and the pane is left at `unknown` for that
   machine; finding Git Bash beside `git` (as `slot.ps1` did) would be a follow-up story, not part of this one.
5. **`tools/*.ps1`.** Decision 1 keeps them by the criteria. If the maintainer reads "no second PowerShell track" to
   include them, they go to a follow-up story (a bash or other renderer for the icon and the social preview); the two
   `.claude/CLAUDE.md` Commands lines and rule 1's list then change with it.
