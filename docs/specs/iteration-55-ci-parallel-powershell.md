# Iteration 55: the PowerShell smoke job runs in four parts on four runners at once, a final job keeps its required name, and every job writes its times to the run's summary

Status: draft, awaiting approval (#289)

Story #289, filed under epic #47 (unattended runs) as a workflow-speed item. Every pull request waits for CI before it
merges, and the check fix rounds of `/next` and `/fix` and every run of the driver pay that wait again. Today the job
`PowerShell scripts smoke tests` runs its 24 steps four at a time on one Windows runner and takes about 15 minutes;
after this iteration the same 24 steps run in four parts, on four Windows runners at the same time, `smoke-slot.ps1`
alone in a part of its own, and a final job on Ubuntu with the required name `PowerShell scripts smoke tests` fails
unless every part succeeded. `tests/check.sh` gains `--summary <file>` (PowerShell wrapper `-Summary <file>`), which
appends the check's wall time and its five slowest steps to a Markdown file; every job that runs the check passes
`$GITHUB_STEP_SUMMARY`, and the final job adds a table of every job's wall time and, per job, its five slowest
workflow steps (from the jobs API's `steps`). For that one call the final job gets `actions: read`, which amends
decision 1 of iteration 38 for that job alone (decision 11). The lint learns the parts: a step of the PowerShell list
in no part or in two fails it. The bash job keeps its name and its single runner (it is bound by
bug #280). Changes `.github/workflows/ci.yml`, `tests/check.sh`, `tests/check.ps1`, `tests/smoke-check.sh`,
`tests/smoke-check.ps1`, `tests/lint.sh`, `tests/test-ci-parts.sh` (new), `tests/ci-jobs-summary.sh` (new),
`tests/test-ci-summary.sh` (new) with a fixture `tests/fixtures/ci-summary/jobs.tsv` and its expected output
`tests/fixtures/ci-summary/jobs.md` (new), `README.md` and `CHANGELOG.md`.

## Story trigger and manual check

**Not a story trigger.** None of `escalation.storyTriggers` applies:

- *A change to the status flow or who sets a status*: no. No skill, status or board step changes; no decision record
  is needed, and `docs/decisions/` 0001 to 0003 are not touched.
- *A new, renamed or removed config key*: no. The parts are this repository's CI layout, not a project's value, so
  they live in `.github/workflows/ci.yml` and not in `.claude/nightmill.json` (invariant **Config-driven** holds).
  `verification.checkJobs` is read as before. The schema, `templates/nightmill.example.json` and the README's
  configuration table do not change.
- *A change to the slot marker format*: no. No slot script changes. **Compatible** (not ticked, checked anyway): the
  change touches neither a slot marker nor a config key. `tests/check.sh` without `--summary` prints exactly what it
  prints today.

**The manual check does not apply**: nothing under `skills`, `agents` or `hooks` (`verification.manualCheckPaths`)
changes.

**Both shells** (invariant ticked): no script in `scripts/` changes. `tests/check.sh` is the one check in both shells
(`tests/check.ps1` passes its parameters to it through Git's bash, iteration 42), so `--summary` is written once in
bash and `check.ps1` gains the parameter `-Summary` that passes it on; `tests/smoke-check.sh` and
`tests/smoke-check.ps1` get the same new case and the same changes to their lint cases. `tests/ci-jobs-summary.sh` and `tests/test-ci-parts.sh` are tests of
this repository's CI, bash only, like `tests/lint.sh` and `tests/test-lint-agreement.sh` (iteration 51); they are not
smoke scripts and need no `.ps1` twin.

**Never auto-merged.** The pull request changes `.github/workflows/ci.yml`; a path under `.github/` withholds
auto-merge (`skills/workflow/SKILL.md`, "CI and merging"), so the maintainer merges it. The ruleset on `main` is not
changed: the three required check names stay (decision 4).

**Order with other work.** Bug #280 (the slow `tests/test-spec-template.sh`) is being fixed in another slot and touches
`tests/lint.sh` and `tests/test-spec-template.sh`; neither depends on the other. A conflict in `tests/lint.sh` would be
textual (different sections). This iteration does not change `test-spec-template.sh`.

## Facts this rests on

Read on `main` at 75059ea (iteration 54 merged) on 2026-11-11.

- **The measurement of the issue** (run 43087110265, PR #288, shared runners, four steps at a time):
  `PowerShell scripts smoke tests` 14m53s, `bash scripts smoke tests` 7m25s, the lint 40s. The PowerShell steps add up
  to about 54 minutes; the longest are `smoke-slot.ps1` 9m14s, `smoke-drive.ps1` 9m01s, `smoke-check.ps1` 8m31s, so
  the other 21 steps add up to about 27 minutes. The bash job is bound by `test-spec-template.sh` (7m18s, bug #280).
  **Not re-measured**: from this machine `gh run view` fails on the TLS check of `api.github.com` (sandbox), and no
  PowerShell is installed here, so no step time could be taken; the per-step times of the other 21 PowerShell steps
  are not known. The parts of decision 2 are therefore balanced on the three known times and on the `first` marks
  (#279: the marks sit on the steps that took longest in a CI run), and decision 7 measures them on this story's own
  pull request.
- **`.github/workflows/ci.yml`**: jobs `lint` (`Lint (generic, JSON, skills, shell)`), `smoke-bash`
  (`bash scripts smoke tests`, ubuntu, 22 minutes), `smoke-powershell` (`PowerShell scripts smoke tests`,
  `windows-latest`, 38 minutes, one step `shell: bash`, `bash tests/check.sh --powershell powershell --only <24 ps
  steps>`), `validate` (not blocking). Workflow permissions `contents: read`; `concurrency` cancels a pull request's
  older run.
- **`tests/check.sh`**: the step list between `# steps: begin` and `# steps: end`, lines `add <kind> <name>[ first]`;
  `--only` takes exactly the named steps and keeps the start order (steps marked `first` first); up to L steps at once
  (`verification.checkJobs` 4, capped at the processors; a `windows-latest` runner has 4); prints a `Times:` block
  with every step's time and the total (the wall time from the start to the end of the last step). Times are seconds
  from `ledger_clock` (`scripts/lib/ledger.sh`) and printed with `ledger_duration` (`42s`, `9m14s`).
- **24 PowerShell steps**, in list order: `smoke-slot.ps1` (first), `smoke-render.ps1`, `smoke-hook.ps1`,
  `smoke-release.ps1` (first), `smoke-validate.ps1` (first), `smoke-status.ps1`, `smoke-template-board.ps1`,
  `smoke-models.ps1`, `smoke-load.ps1`, `smoke-room.ps1`, `smoke-control.ps1`, `smoke-dashboard.ps1`,
  `smoke-panel.ps1`, `smoke-stages.ps1`, `smoke-check.ps1` (first), `test-lintcopy-output.ps1` (first),
  `test-release-resume.ps1`, `test-json-bom.ps1`, `test-render-quoting.ps1`, `test-status-controls.ps1`,
  `smoke-guard.ps1`, `smoke-drive.ps1` (first), `smoke-gate.ps1`, `smoke-history.ps1`. `smoke-slot.ps1` has 2091
  lines, the next largest (`smoke-drive.ps1`) 596.
- **The lint** (`tests/lint.sh`): `== the check starts the longest steps first` pins the `first` marks
  (`want_firsts`); `== the check runs every smoke script` (iteration 42 decision 11) pins the step list, exactly one
  `run: bash tests/check.sh --only ` line and one `run: bash tests/check.sh --powershell powershell --only ` line whose
  lists equal the step list's bash (but `smoke-json.sh`) and ps steps in list order, and each required name once as
  `    name: <name>`.
- **The lint runs inside PowerShell steps.** `smoke-release.ps1`, `smoke-validate.ps1`, `smoke-check.ps1` and
  `test-lintcopy-output.ps1` run the lint on a copy of the repository; bug #270 showed that each process the lint
  starts costs time there (`tests/test-lint-agreement-cost.sh`).
- **GitHub Actions**: a matrix job's checks are named after its `name:` with the matrix values; a job that `needs` a
  matrix job sees one `needs.<id>.result` for all its legs (`success` only when every leg succeeded, else `failure`,
  `cancelled` or `skipped`); a job without `if: always()` is skipped when a job it needs fails, and a skipped required
  check counts as passed for the ruleset, which is why the final job must run always and decide itself. The jobs API
  (`GET /repos/{owner}/{repo}/actions/runs/{run_id}/attempts/{attempt}/jobs`) gives every job's `name`, `status`,
  `conclusion`, `started_at` and `completed_at`, and its `steps`, each with `name`, `status`, `conclusion`,
  `started_at` and `completed_at` (null for a step that has not started or was skipped); GitHub adds steps of its own
  (`Set up job`, `Post ...`, `Complete job`). The call needs `actions: read`; with the workflow's `contents: read`
  alone every other scope is `none`, and the `GITHUB_TOKEN` is refused (an unauthenticated call to a public repository
  is limited per IP address, which shared runners share, so it is not relied on). A job-level `permissions:` replaces
  the workflow's, so the job lists `contents: read` again for its checkout.
- **Workflow steps per job** (`ci.yml` today): `lint` 2 (checkout, `tests/lint.sh`), `smoke-bash` 4 (checkout,
  `smoke-json.sh`, hide `jq`, the check), `smoke-powershell` 2 (checkout, the check), `validate` 5 (checkout,
  `setup-node`, `npm install`, `claude plugin validate`, `claude plugin test`); the final job of decision 3 has 3.
  The jobs API lists these plus GitHub's own.
- **Iteration 38** (`docs/specs/iteration-38-ci-hardening.md`): decision 1, "`contents: read` at the top, no job asks
  for more ... No job gets its own `permissions:` key", pinned by the lint's `== CI runs with least privilege`
  (`tests/lint.sh` line 1492: any indented `permissions:` fails); decision 2, `timeout-minutes` about 3 times the
  longest run, rounded up to whole minutes, at least 5, which the lint does not pin as a value (it checks 1 to 360 per
  job; only `smoke-bash` has a pin of its own, `tests/test-ci-smoke-bash-timeout.sh`, bug #264). Both are spec
  decisions, not decision records.
- **Iteration 42 decision 12** ("no job is added, removed or renamed") described that iteration's change; this story
  asks for new jobs and keeps the three required names, so this spec replaces that rule for the PowerShell job
  (decision 3). It is a spec, not a decision record.

## Decisions

**1. Four parts, `smoke-slot.ps1` alone; no test is split.** The job cannot end before its longest step, and
`smoke-slot.ps1` took 9m14s with three other steps beside it. It gets a part of its own: alone on a runner it competes
with no other step for the disk and the processors, so it runs no longer than measured, and the set-up (checkout,
about 20 to 60 s) still keeps the part under 10 minutes. Splitting the test (2091 lines) would change a test, which the
story leaves to bugs of their own (out of scope: making single tests faster). `smoke-drive.ps1` and `smoke-check.ps1`
each lead a part, and the three other steps marked `first` (`smoke-release.ps1`, `smoke-validate.ps1`,
`test-lintcopy-output.ps1`) are spread one per part, so no part holds two of the known long steps. Four parts rather
than three: the long steps of parts 2 and 3 then share their runner with six short steps instead of ten, so less of
their time is lost to contention, for one more minute of set-up.

**2. The parts**, each in step-list order (the lint checks the order, decision 5):

| Part | Steps | Known long steps |
|---|---|---|
| 1 | `smoke-slot.ps1` | 9m14s |
| 2 | `smoke-render.ps1`, `smoke-release.ps1`, `smoke-status.ps1`, `smoke-dashboard.ps1`, `test-release-resume.ps1`, `test-json-bom.ps1`, `smoke-drive.ps1` | `smoke-drive.ps1` 9m01s, `smoke-release.ps1` (first) |
| 3 | `smoke-hook.ps1`, `smoke-validate.ps1`, `smoke-control.ps1`, `smoke-panel.ps1`, `smoke-check.ps1`, `test-render-quoting.ps1`, `smoke-gate.ps1` | `smoke-check.ps1` 8m31s, `smoke-validate.ps1` (first) |
| 4 | `smoke-template-board.ps1`, `smoke-models.ps1`, `smoke-load.ps1`, `smoke-room.ps1`, `smoke-stages.ps1`, `test-lintcopy-output.ps1`, `test-status-controls.ps1`, `smoke-guard.ps1`, `smoke-history.ps1` | `test-lintcopy-output.ps1` (first) |

1 + 7 + 7 + 9 = 24 steps, each once. Within a part the check runs four at a time as today, and the `first` marks keep
working through `--only` (they are unchanged; `want_firsts` stays). A new PowerShell step goes into the part with the
least work, by the latest run's summaries, and never into part 1.

**3. The parts live in the workflow; `tests/check.sh` does not learn parts.** `--only` already takes any subset in
list order, so a part is one `--only` list in the matrix of `.github/workflows/ci.yml`; no `--part` option and no
group field in the step list are added, and the step-list line format stays `add <kind> <name>[ first]`. The
PowerShell job becomes two jobs, written exactly so (the lint and `tests/test-ci-parts.sh` read these lines):

```yaml
  smoke-powershell-part:
    # The PowerShell smoke steps in parts, one runner each (iteration 55). Not a required check: the job
    # smoke-powershell below carries the required name and fails unless every part succeeded.
    name: PowerShell smoke part ${{ matrix.part }} of 4
    runs-on: windows-latest
    timeout-minutes: 28
    strategy:
      fail-fast: false
      matrix:
        include:
          - part: 1
            only: smoke-slot.ps1
          - part: 2
            only: smoke-render.ps1,smoke-release.ps1,smoke-status.ps1,smoke-dashboard.ps1,test-release-resume.ps1,test-json-bom.ps1,smoke-drive.ps1
          - part: 3
            only: smoke-hook.ps1,smoke-validate.ps1,smoke-control.ps1,smoke-panel.ps1,smoke-check.ps1,test-render-quoting.ps1,smoke-gate.ps1
          - part: 4
            only: smoke-template-board.ps1,smoke-models.ps1,smoke-load.ps1,smoke-room.ps1,smoke-stages.ps1,test-lintcopy-output.ps1,test-status-controls.ps1,smoke-guard.ps1,smoke-history.ps1
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - shell: bash
        run: bash tests/check.sh --powershell powershell --summary "$GITHUB_STEP_SUMMARY" --only ${{ matrix.only }}

  smoke-powershell:
    # Required check: the ruleset on main requires this name; renaming it blocks every pull request.
    name: PowerShell scripts smoke tests
    needs: smoke-powershell-part
    if: always()
    runs-on: ubuntu-latest
    timeout-minutes: 5
    # The one job-level permissions block (iteration 55 decision 11): the job times need actions: read.
    permissions:
      contents: read
      actions: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: Every part succeeded
        env:
          PARTS: ${{ needs.smoke-powershell-part.result }}
        run: |
          echo "the PowerShell parts: $PARTS"
          [ "$PARTS" = success ] || { echo "FAIL: a PowerShell part did not succeed ($PARTS)"; exit 1; }
      - name: Job times
        if: always()
        continue-on-error: true
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/$GITHUB_RUN_ATTEMPT/jobs" --paginate \
            --jq '.jobs[] | (["job", .name, (.conclusion // .status), (.started_at // ""), (.completed_at // "")] | @tsv),
                  (.name as $j | .steps[]? | ["step", $j, .name, (.started_at // ""), (.completed_at // "")] | @tsv)' \
            | bash tests/ci-jobs-summary.sh --parts 'PowerShell smoke part ' --now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            >> "$GITHUB_STEP_SUMMARY"
```

- `fail-fast: false`: a failing part does not cancel the others, so one run reports every failure and a check fix
  round sees all of them at once.
- The final job runs on Ubuntu (it runs no PowerShell), with `if: always()`, so it runs when a part failed, was
  cancelled or was skipped, and fails then because the result is not `success` (criterion 1). A timed-out part is
  `failure` or `cancelled`, so it fails too. When the whole run is cancelled by a newer push (`concurrency`), the final
  job fails as well; that run is superseded and its result does not matter.
- The job-times step cannot change the verdict: it comes after the verdict step, runs whatever that did
  (`if: always()`), and is `continue-on-error: true`, so its own failure leaves the job's result to the verdict. It
  runs last so that the final job's own steps before it are complete when it reads them (decision 7, `--now`).
- The part job's `timeout-minutes` follows iteration 38 decision 2 (about 3 times the longest run, rounded up to whole
  minutes): no part has run yet, and the longest a part is planned to take is its longest step, `smoke-slot.ps1`
  9m14s = 554 s; 3 × 554 = 1662 s, so 28. The old 38 was for 24 steps on one runner. When the pull request's run
  (decision 9) shows a part longer than 554 s, the implementer raises the value to 3 times that part's wall time,
  rounded up. The final job keeps the floor of 5 (it runs well under a minute). The lint's timeout rule (every job
  from 1 to 360) holds for both and needs no change.

**4. The required names stay.** `Lint (generic, JSON, skills, shell)`, `bash scripts smoke tests` and
`PowerShell scripts smoke tests` are each the `name:` of exactly one job, with the ids `lint`, `smoke-bash` and
`smoke-powershell` as today. The part job's name, `PowerShell smoke part <k> of 4`, does not begin with any required
name, so no check like `PowerShell scripts smoke tests (1)` appears. The ruleset is not changed.

**5. What the lint pins.** In `== the check runs every smoke script`, the rule for the two `--only` lines (iteration 42
decision 11, rule 6) changes:

- the bash job: exactly one line matching `^[[:space:]]*(- )?run: bash tests/check\.sh --summary "\$GITHUB_STEP_SUMMARY" --only `,
  whose list (after `--only `) is checked by `chk_only` against the step list's bash steps but `smoke-json.sh`, as
  today;
- the PowerShell list is no longer read from a run line there; the section checks instead that no `name:` line of
  `ci.yml` other than the three exact required lines contains a required name
  (`FAIL: .github/workflows/ci.yml: the job name '<name>' begins with the required name '<req>'`).

A new section `== the PowerShell job runs in parts`, right after it, starts `bash tests/test-ci-parts.sh "$PWD"` once
(one process, bug #270). That file reads `tests/check.sh` (the step list) and `.github/workflows/ci.yml` (the block of
the job `  smoke-powershell-part:` and the block of `  smoke-powershell:`, each up to the next line that starts with
two spaces and a letter) and prints one `FAIL:` line per broken rule, prefixed `.github/workflows/ci.yml: `:

1. the part job has `fail-fast: false`, `runs-on: windows-latest`, the name line
   `name: PowerShell smoke part ${{ matrix.part }} of <M>`, and M pairs of lines `- part: <k>` / `only: <list>` with
   k = 1, 2, ..., M in order and M ≥ 2 equal to the M of the name; else `the PowerShell parts are malformed (<what>)`;
2. it has exactly one run line `run: bash tests/check.sh --powershell powershell --summary "$GITHUB_STEP_SUMMARY" --only ${{ matrix.only }}`
   after a `shell: bash` line; else `the PowerShell part job does not run tests/check.sh --only ${{ matrix.only }}`;
3. every `add ps <x>` step of the step list is named in exactly one part, exactly once: else
   `tests/<x> runs in no PowerShell part` or `tests/<x> runs in more than one PowerShell part` (named twice in one
   part counts as more than one);
4. every name in a part is a ps step of the step list: else
   `PowerShell part <k> names tests/<x>, which is not a ps step of tests/check.sh`;
5. each part's list is in the order of the step list: else `PowerShell part <k>: the --only list is not in the order of the step list`;
6. the part that holds `smoke-slot.ps1` holds nothing else: else `PowerShell part <k>: smoke-slot.ps1 shares its part` (decision 1);
7. the job `smoke-powershell` has the job keys (exactly four spaces of indent) `name: PowerShell scripts smoke tests`,
   `needs: smoke-powershell-part` and `if: always()`, and the lines `PARTS: ${{ needs.smoke-powershell-part.result }}`
   and `[ "$PARTS" = success ] || {`; else
   `the job PowerShell scripts smoke tests does not fail unless every part succeeded (missing: <line>)`;
8. the job-level permissions of decision 11: in the whole `jobs:` section, a line `permissions:` with any indent is
   allowed only as the job key `    permissions:` of the job `smoke-powershell`, followed by exactly the two lines
   `      contents: read` and `      actions: read` (in that order) and then a line not indented by six spaces or more;
   a `permissions:` in any other job, or at any other indent, gives
   `job <id> has a job-level 'permissions:' block (only smoke-powershell may, with contents: read and actions: read)`,
   and a block of `smoke-powershell` with other or further lines gives
   `the job smoke-powershell's 'permissions:' block is not exactly 'contents: read' and 'actions: read'`.

In `== CI runs with least privilege`, rule 1 keeps the top-level checks (`permissions:` at column 0 followed by
exactly `  contents: read`) and the `: write` check; its line `grep -qE '^[[:space:]]+permissions:'` and its `FAIL`
line are removed, and the section's comment says that the job-level rule lives in `tests/test-ci-parts.sh` (rule 8),
as the `smoke-bash` timeout pin lives in `tests/test-ci-smoke-bash-timeout.sh`.

Then `tests/test-ci-parts.sh` runs its own cases (Tests) in the same process on scratch copies, and exits 1 when any rule or case failed,
else 0 with the line `OK: the PowerShell parts`. The lines are matched with their leading spaces removed and trailing
blanks and a carriage return ignored.

**6. The summary: `tests/check.sh --summary <file>`** (`tests/check.ps1 -Summary <file>`).

- After the `Times:` block and the `SKIPPED:` lines, before the verdict line, in every mode (full, `--quick`,
  `--only`) and whatever the verdict, the check appends to `<file>` (creating it when missing):

  ```
  ### tests/check.sh

  Wall time: <total> for <k> steps, <L> at a time: <passed|FAILED>

  | Slowest step | Time |
  |---|---|
  | `<name>` | <duration> |
  ```

  followed by one empty line. `<total>` is the total of the `Times:` block; `<k>` the steps that ran; `<L>` the limit
  of the header; `FAILED` when any step that ran failed. The table has the five steps that ran with the most seconds,
  most first, a tie in list order; fewer rows when fewer ran; no table when none ran. `<duration>` is
  `ledger_duration` of the step's seconds, as in the `Times:` block. The check keeps each step's seconds in an array
  beside `times` for this.
- `--summary` given twice, without a value or with an empty value: the usage error, exit 2. The usage line becomes
  `usage: tests/check.sh [--quick | --only <step>[,<step>...]] [--jobs <1-16>] [--powershell powershell|pwsh] [--summary <file>]`.
- A file that cannot be written: `check: cannot write the summary to <file>` on standard error; the verdict line and
  the exit code are those of the steps.
- Without `--summary` the output is byte for byte today's.
- An interrupted check (`CHECK INTERRUPTED`, exit 130) writes no summary.

The check reads the step times itself, so nothing parses its output, and both shells get the option through one
change in bash: on the Windows runner the parts run `bash tests/check.sh` already, and `check.ps1` passes `-Summary`
on as `--summary`.

**7. The job table: `tests/ci-jobs-summary.sh --parts <prefix> [--now <stamp>]`.** Reads on standard input lines of
five tab-separated fields, of two kinds:

- `job`, the job's name, its result (`conclusion`, or `status` while it runs), its start, its end;
- `step`, the name of the job it belongs to, the step's name, its start, its end.

Stamps are `YYYY-MM-DDTHH:MM:SSZ`; either may be empty. It prints:

```
### Job times

| Job | Result | Wall time |
|---|---|---|
| <name> | <result> | <duration> |

PowerShell scripts smoke tests: <duration> from the start of the first part to the end of the last (<n> parts).

#### Slowest steps: <job name>

| Step | Time |
|---|---|
| <step name> | <duration> |
```

- The table: one row per `job` line, in input order. `<duration>` is `ledger_duration` of end − start
  (`ledger_epoch`, sourced from `scripts/lib/ledger.sh`); with an empty end it is the time from the start to `--now`
  followed by ` (running)`, or `running` without `--now`; `?` when a stamp does not parse or the start is empty.
- The chain line takes the `job` lines whose name begins with `<prefix>`: the earliest start to the latest end; it is
  left out when no such job has both stamps.
- Then, per `job` line in input order, one `#### Slowest steps: <job name>` section with the five `step` lines of that
  job with the most seconds, most first, a tie in input order; a step with an empty end counts to `--now` and is
  marked ` (running)`, or is left out without `--now`; a step without a start or with a stamp that does not parse is
  left out; a job with no step left has no section. Each section ends with one empty line.
- A line with another first field or with fewer than five fields is skipped. Exit 0, or 2 with the usage on stderr for
  a missing `--parts`, an empty or unparsable `--now`, or an unknown argument. It needs no `jq` and no network (the
  `gh api --jq` call of decision 3 does the JSON).

The final job passes `--now` from the clock at the time of the call, so its own row and its own section count to that
moment: its checkout and verdict steps are complete then, and only its tail (the job-times step itself and GitHub's
`Complete job`, a few seconds) is cut.

Together, the run's summary page shows, for every job, its wall time (the table) and its five slowest workflow steps
(a `#### Slowest steps` section): the lint (2 workflow steps, plus GitHub's own), `validate` (5), the bash job (4), the
four parts (2 each) and the final job (3). For the jobs that run `tests/check.sh` (`bash scripts smoke tests` and the
four parts), one workflow step holds the whole check, so their `### tests/check.sh` section (decision 6) adds the five
slowest steps of the check itself.

**8. The bash job.** Its name, runner, `timeout-minutes` and steps stay; only its check line becomes
`run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" --only <list>`, and the list gains `test-ci-summary.sh`
(decision 10). It is not split: it is bound by `test-spec-template.sh` (7m18s), bug #280, and already under the
10-minute figure. After this iteration the pull request's wait is the longer of the bash job (about 7.5 minutes until
#280 is fixed) and the PowerShell chain.

**9. The figure and its measurement.** The figure is the issue's: **at most 10 minutes**. Measured on the pull
request's own CI run on its last commit, as the last line of the jobs table of decision 7: from the start of the first
part to the end of the last part. The final job adds about 15 to 30 s (an Ubuntu runner and a checkout) and is
reported beside it. The implementer puts into "How verified" of the pull request: that line, the four parts' wall
times, the bash job's wall time, each part's five slowest steps (from the summaries), and the run's link. When the
chain is above 10 minutes, the implementer may move steps once between parts 2, 3 and 4 by the measured times (never
into part 1, the lint holds the rest) and measure again; when it is still above, or part 1 alone is above 10 minutes,
it reports `partial` with the numbers and does not drop, shorten or split a test (the splitting of `smoke-slot.ps1`
would be a story of its own, see Left).

**Runner minutes.** The step work stays the same, about 54 step-minutes at four at a time (less if fewer steps beside
the long ones run faster). The Windows time billed is the sum of the four parts' wall times instead of one job's
15 minutes: about 9 + 9 + 8.5 + 4 plus about one minute of set-up per part, so about 34 Windows runner-minutes per run
(at most 4 × 10 = 40 when every part meets the figure), plus well under a minute of Ubuntu for the final job (the
steps sections add no API call: the same jobs call returns the `steps`). For this
public repository GitHub-hosted runner minutes are free; a private fork would pay Windows minutes at their rate. The
measured sum goes into "How verified" too.

**10. Tests of the new files run where they cost least.** `tests/test-ci-summary.sh` is a bash step of the step list
(`add bash test-ci-summary.sh`, after `add bash smoke-history.sh`) and so of the bash job's `--only` list; it is not
started by the lint, so the lint copies inside the PowerShell steps (Facts) do not pay for it. `tests/test-ci-parts.sh`
is started by the lint once, because the lint must pin the agreement of the step list and the workflow; its cases run
in its own process on small scratch files.

**11. The final job reads the job times with `actions: read`; this amends iteration 38 decision 1 for that job
alone.** Criterion 5 asks for every job's wall time and slowest steps, and only the jobs API knows the wall time of a
job and of its workflow steps (a job cannot time its own set-up and checkout from inside, and the lint and `validate`
jobs would each need extra steps that write times). The token is refused without `actions: read` (Facts). So the job
`smoke-powershell` gets the block of decision 3, `contents: read` and `actions: read`, both read-only; no other job gets
a `permissions:` key, the top-level block stays exactly `contents: read`, and no `: write` appears anywhere. Iteration
38's rule becomes: "`contents: read` at the top; no job asks for more, except `smoke-powershell`, which adds
`actions: read` to read the run's job times". `actions: read` lets the job read this repository's workflow runs,
jobs, logs and artifacts, all of which are public for this repository anyway. The lint pins it (decision 5, rule 8).
No decision record: iteration 38's decision is a spec decision, and the status flow does not change.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The PowerShell smoke job runs its steps on several runners at the same time, and the required check `PowerShell scripts smoke tests` still reports one result that fails when any part fails, is cancelled or is skipped | Decisions 1, 2, 3 (matrix of four parts, final job with `needs`, `if: always()` and the `success` test); decision 5 rule 7 |
| 2 | Every step of the PowerShell list runs in exactly one part, and the lint fails when a step of tests/check.sh runs in none or in two | Decision 2 (the parts), decision 5 (rules 3 to 6, `tests/test-ci-parts.sh`); Tests |
| 3 | The job `PowerShell scripts smoke tests` finishes in at most 10 minutes on a run with no failure | Decisions 1 and 9 (10 minutes, measured from the start of the first part to the end of the last on the pull request's run; what happens when missed) |
| 4 | The names of the required checks stay as they are | Decision 4; decision 5 (the lint keeps each name once and refuses a job name that begins with one) |
| 5 | A run shows, per job, its wall time and its five slowest steps | Decision 7 (every job's wall time and five slowest workflow steps from the jobs API, the final job included through `--now`), decision 6 (the five slowest check steps of the jobs that run `tests/check.sh`), decision 11 (`actions: read` for the call) |

## Tests

- Criterion 1 and 2: **`tests/test-ci-parts.sh`** (new, started once by the lint section
  `== the PowerShell job runs in parts`). On this checkout: no `FAIL:` line. Then cases, each on a scratch copy of
  `tests/check.sh` and `.github/workflows/ci.yml` changed by one `sed` or `awk`, each asserting its `FAIL:` text:
  `smoke-guard.ps1` removed from part 4 (`runs in no PowerShell part`); `smoke-render.ps1` added to part 3 as well
  (`runs in more than one PowerShell part`); `smoke-gate.ps1` named twice in part 3 (`more than one`); a line
  `add ps smoke-new.ps1` added to the step list and to no part (`tests/smoke-new.ps1 runs in no PowerShell part`);
  `smoke-nothing.ps1` in part 2 (`which is not a ps step`); two names of part 2 exchanged (`not in the order of the step
  list`); `smoke-hook.ps1` moved into part 1 (`smoke-slot.ps1 shares its part`); `if: always()` removed, and the
  `[ "$PARTS" = success ]` line removed (`does not fail unless every part succeeded`); the part numbers `1, 2, 4, 3`
  and the name `of 5` with four parts (`malformed`); the run line without `--only ${{ matrix.only }}`; for rule 8:
  the block `permissions:` / `contents: read` added to the job `lint` (`job lint has a job-level 'permissions:'
  block`), `      actions: read` changed to `      actions: write`, and a third line `      checks: read` added to
  the block of `smoke-powershell` (each `is not exactly 'contents: read' and 'actions: read'`), the block removed
  from `smoke-powershell` (no rule 8 line; the job is allowed none), and a `permissions:` at six spaces inside a step
  of `smoke-bash` (`job smoke-bash has a job-level 'permissions:' block`). A case that
  does not give its text prints `FAIL: case <name>: ...`. Exit 1 on any failure.
- Criterion 4: **`tests/lint.sh`**, `== the check runs every smoke script`: each required name once as
  `    name: <name>` (kept), and a job name that begins with a required name fails (new rule, decision 5). Only the
  pull request's checks list can show that the ruleset still finds its three names (manual, below).
- Criterion 5: **`tests/smoke-check.sh` and `tests/smoke-check.ps1`**, a new case `== summary` (the `.ps1` through
  `tests/check.ps1 -Summary`, same steps, same expected text): a `NIGHTMILL_CHECK_STEPS` file of six steps `a` to `f`
  run with `--jobs 1`, each advancing the clock file (`NIGHTMILL_CLOCK_FILE`) by 5, 30, 1, 30, 12 and 7 seconds, `e`
  exiting 1; the summary file then holds exactly `### tests/check.sh`, `Wall time: 1m25s for 6 steps, 1 at a time:
  FAILED` and the rows `b` 30s, `d` 30s, `e` 12s, `f` 7s, `a` 5s (`c` left out, the tie in list order); the exit code
  is 1 and the standard output equals a run without `--summary`. Further: `--summary` twice and `--summary` without a
  value exit 2 with the usage; a directory as the file gives `check: cannot write the summary to <dir>` on stderr and
  the steps' exit code; a passing two-step run appends a second section after the first (the file is appended to,
  not replaced).
- Criteria 2 and 4: **`tests/smoke-check.sh` and `tests/smoke-check.ps1`**, the existing lint cases follow the new
  lines of `ci.yml` (decisions 3, 5, 6 and 8), so that each edit still changes a line. The section is still cut from
  `== the check runs every smoke script` to `== text from issues is data`, so it now holds the new section
  `== the PowerShell job runs in parts` too, and the scratch copy has `tests/test-ci-parts.sh` (every script in
  `tests/` is copied). The constant `USAGE` becomes
  `usage: tests/check.sh [--quick | --only <step>[,<step>...]] [--jobs <1-16>] [--powershell powershell|pwsh] [--summary <file>]`
  (decision 6). The four cases (`.sh` sed address / `.ps1` `-like` pattern; the replacement inside the line as today):
  - `cibash`: the line `run: bash tests/check.sh --summary` (sed `/run: bash tests\/check\.sh --summary/`, `.ps1`
    `'*run: bash tests/check.sh --summary*'`; the part job's line has `--powershell powershell` before `--summary`, so
    it does not match), `smoke-hook.sh,` removed; expects, as today,
    `FAIL: .github/workflows/ci.yml does not run tests/smoke-hook.sh`.
  - `cijson`: the same line, `--only ` replaced by `--only smoke-json.sh,`; expects, as today,
    `FAIL: .github/workflows/ci.yml: tests/smoke-json.sh is not a step of its job or is named twice`.
  - `ciswap`: the same line, `smoke-hook.sh,smoke-release.sh` replaced by `smoke-release.sh,smoke-hook.sh`; expects,
    as today, `FAIL: .github/workflows/ci.yml: the --only list is not in the order of the step list`.
  - `cips`: the matrix line of part 3 (sed `/^ *only: smoke-hook\.ps1,/`, `.ps1` `'*only: smoke-hook.ps1,*'`),
    `smoke-hook.ps1,` removed; expects
    `FAIL: .github/workflows/ci.yml: tests/smoke-hook.ps1 runs in no PowerShell part` (decision 5 rule 3, printed by
    `tests/test-ci-parts.sh`; the old text `does not run tests/smoke-hook.ps1` is no longer printed).
- Criterion 5: **`tests/test-ci-summary.sh`** (new, a bash step): runs
  `tests/ci-jobs-summary.sh --parts 'PowerShell smoke part ' --now 2026-11-11T10:20:00Z` on
  `tests/fixtures/ci-summary/jobs.tsv` and compares the output byte for byte with `tests/fixtures/ci-summary/jobs.md`.
  The fixture has `job` lines for the lint job, `validate`, the bash job, four parts (one with the result `failure`)
  and the final job still `in_progress` with no end; `step` lines for each: the lint's 4 (GitHub's `Set up job` and
  `Complete job` beside its 2), `validate`'s 7 (more than five, with two of equal time for the tie in input order),
  the bash job's 6, each part's 4, and the final job's 4 with the job-times step still without an end; plus one step
  without a start (a skipped step), one line of four fields, one line whose first field is `other`, one bad stamp.
  The expected file shows the table (the final job's wall time to `--now` with ` (running)`, `?` for the bad stamp),
  the chain line over the four parts, and one `#### Slowest steps` section per job with at most five rows (the skipped
  step and the bad lines left out, the running step marked ` (running)`). Then the same input without `--now`: the
  final job's row says `running` and its running step is left out. Then without `--parts`, with `--now` empty or
  `--now yesterday`, and with an unknown argument: exit 2.
- Criterion 3: only the pull request's own run shows it (decision 9).
- `bash tests/check.sh` green on the branch.

**On the pull request's own run** (the manual part; no skill changes, so `verification.manualCheckText` does not
apply): the checks list shows `Lint (generic, JSON, skills, shell)`, `bash scripts smoke tests`,
`PowerShell scripts smoke tests` and four `PowerShell smoke part <k> of 4`, the three required ones green and the
pull request mergeable; the run's summary page has the jobs table and five `### tests/check.sh` sections (the bash job
and the four parts); the chain line is at most 10 minutes, with the numbers of decision 9 in "How verified". The
failing case of criterion 1 (a part red, the required check red) is shown by the lint's rule 7 and the structure of
decision 3, not by pushing a red commit. The jobs table must have rows for all eight jobs (lint, bash, four parts,
the final job, `validate`) and a `#### Slowest steps` section for each; that first run is also the test that
`actions: read` suffices for the call.

## Files touched

- `.github/workflows/ci.yml`: the job `smoke-powershell` becomes the part job `smoke-powershell-part` and the final
  job `smoke-powershell` of decision 3; the bash job's check line gains `--summary "$GITHUB_STEP_SUMMARY"` and
  `test-ci-summary.sh` in its list (decision 8). `lint` and `validate` unchanged.
- `tests/check.sh`: `--summary <file>` (decision 6), the usage line and the header comment; `add bash
  test-ci-summary.sh` in the step list after `smoke-history.sh`.
- `tests/check.ps1`: the parameter `-Summary <file>`, passed on as `--summary`; its header comment.
- `tests/smoke-check.sh`, `tests/smoke-check.ps1`: the `== summary` case; the constant `USAGE` (`.sh` line 14,
  `.ps1` line 16) gains ` [--summary <file>]`; the lint cases `cibash`, `cijson` and `ciswap` find their line by
  `run: bash tests/check.sh --summary` instead of `run: bash tests/check.sh --only`, and `cips` edits the part line
  `only: smoke-hook.ps1,...` instead of the `--powershell powershell --only` line and expects
  `tests/smoke-hook.ps1 runs in no PowerShell part` (Tests).
- `tests/lint.sh`: `== the check runs every smoke script` (decision 5: the bash line shape, the PowerShell line rule
  moved out, the job-name rule); the new section `== the PowerShell job runs in parts`; in `== CI runs with least
  privilege`, the job-level `permissions:` grep and its `FAIL` line removed and the comment pointing to
  `tests/test-ci-parts.sh` rule 8 (decision 11).
- `tests/test-ci-parts.sh` (new): the rules 1 to 8 of decision 5 and their cases.
- `tests/ci-jobs-summary.sh` (new): decision 7, the jobs table and the per-job steps sections.
- `tests/test-ci-summary.sh` (new), `tests/fixtures/ci-summary/jobs.tsv` and `jobs.md` (new).
- `README.md`, under `## Developing nightmill`: the paragraph after the test list says that CI runs the PowerShell
  smoke steps in four parts on four Windows runners, that the required check `PowerShell scripts smoke tests` is a
  final job that fails unless every part succeeded, that `bash tests/check.sh --summary <file>` appends the check's
  wall time and its five slowest steps to a Markdown file, and that each CI run's summary page shows every job's wall
  time and its five slowest workflow steps (read by the final job, the one job with `actions: read`), and each check's
  five slowest steps. No line is added to the list of smoke tests (no new smoke file).
- `CHANGELOG.md`, under `Unreleased`, first:

  ```
  - Iteration 55 (#289): CI runs the PowerShell smoke steps in four parts on four Windows runners at once
    (`smoke-slot.ps1` alone in one); a final job keeps the required name `PowerShell scripts smoke tests` and fails
    unless every part succeeded. `tests/check.sh --summary <file>` (`check.ps1 -Summary`) appends the check's wall
    time and its five slowest steps to a Markdown file, and each run's summary page shows every job's wall time and
    five slowest workflow steps (the final job alone gets `actions: read` for that, amending iteration 38). The
    lint fails when a PowerShell step runs in no part or in two. No config key, no marker change.
  ```

## Risks

- **The figure rests on one run's times.** The other 21 steps were not measured one by one (Facts); a part may end up
  heavier than planned. Decision 9 allows one move between parts 2 to 4 and reports `partial` instead of cutting a
  test. Part 1 is bound by `smoke-slot.ps1` alone; if a shared runner is slow that day, it may pass 10 minutes even so.
- **A skipped required check passes.** If the final job lost `if: always()`, a failing part would skip it and the
  ruleset would treat the skip as passed: a red pull request could merge. Decision 5 rule 7 pins the lines, and the
  final job decides on `needs.<id>.result` itself.
- **Windows runner queueing.** Four Windows jobs at once may wait for runners on a busy day; the wait counts toward
  the pull request's time but not toward the job's wall time. The jobs table shows the starts.
- **The jobs API call** may fail (rate limit, an outage): the step is `continue-on-error`, the summary misses the
  table and the steps sections, the verdict is unchanged. `actions: read` is granted to the final job only
  (decision 11), and the lint (rule 8) fails on any other job-level `permissions:`.
- **The final job's own times are cut short** by its tail (the job-times step itself and `Complete job`, a few
  seconds), since a job cannot read its own end (decision 7).
- **The lint's cost inside PowerShell steps** (bug #270): the new section starts one process and its cases are small
  scratch files; `tests/test-ci-summary.sh` is not started by the lint (decision 10).
- **A conflict with the fix of #280** in `tests/lint.sh` is textual only.

## Size estimate

`L`: about 550 changed lines. `ci.yml` about 50, `tests/check.sh` about 40, `tests/check.ps1` about 5,
`smoke-check.sh` and `.ps1` about 80 together (the `== summary` case, `USAGE` and the four lint cases), `tests/lint.sh` about 30, `tests/test-ci-parts.sh` about 190,
`tests/ci-jobs-summary.sh` about 80, `tests/test-ci-summary.sh` and its fixtures about 65, README about 8, CHANGELOG
about 6.

## Not done

- No test is made faster or split: `smoke-slot.ps1`, `smoke-drive.ps1`, `smoke-check.ps1` and `test-spec-template.sh`
  (bug #280) keep their content.
- The bash job is not split into parts.
- No larger or paid runner, no caching, no change of the PowerShell under test (Windows PowerShell 5.1 stays).
- No `--part` option and no part field in `tests/check.sh`'s step list; the parts live only in `ci.yml`.
- The parts are not balanced automatically from measured times; a new PowerShell step is placed by hand (decision 2).
- No change to the ruleset on `main`, the lint job, the `validate` job or `verification.checkJobs`.
- No job other than `smoke-powershell` gets a `permissions:` key, and no job writes its own step times; the jobs API
  call in the final job is the only source of workflow step times.
- No history of CI times across runs; each run's summary shows its own.

## Left

- Part 1 is `smoke-slot.ps1` alone, which is the floor: if the pull request's run shows it above 10 minutes even
  alone, the figure cannot be met without splitting that test, which the story puts out of scope. The maintainer then
  decides between another figure and a story to split `smoke-slot.ps1` (and its bash twin).
- The step times of 21 of the 24 PowerShell steps were not available to this spec (no network to the GitHub API and
  no PowerShell on the machine that wrote it); decision 2 is a plan to be confirmed by the pull request's run.
- Decision 11 widens iteration 38's least-privilege rule by `actions: read` for one job. If the maintainer prefers no
  job-level `permissions:` at all, criterion 5 can only be met by each job timing and writing its own steps (no set-up
  time), and decision 7 would change.
