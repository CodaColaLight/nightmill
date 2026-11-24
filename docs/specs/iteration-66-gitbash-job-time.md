# Iteration 66: the Git Bash CI job runs in parts and finishes within 17 minutes

Status: draft, awaiting approval (#382)

Story #382, epic #337 (fast verification loop). It supersedes bug #376. Iteration 64 (#361) added the job
`smoke-gitbash`, which runs every bash test step in Git Bash on a Windows runner. Iteration 65 (#363) is to make it a
required check, but only after a full run is green and takes at most 17 minutes (iteration 64 decision 5, iteration 65
decision 7). A full run takes about an hour today. This iteration measures where the time of the slowest steps goes.
The measurement is its first deliverable, and the implementer writes it into this spec (`## Measurements`). The
iteration then cuts the time by fixed rules, in a fixed order: the nested step `test-lintcopy-output.sh` comes off the
job's list (decision 3); the job is split into parts that run at once on several Windows runners, by a rule on the
measured step times, with a final job that fails unless every part succeeded, as iteration 55 did for PowerShell
(decision 5); the measured sections that start many processes, in the parts that still miss the budget, are rewritten
to start fewer, with the same cases (decision 4); and the work stops when the budget of decision 2 is met, or as
`partial` when it is not (decision 5). Changes `docs/specs/iteration-66-gitbash-job-time.md` (the measurements),
`.github/workflows/ci.yml` (the Git Bash part job and the final job), `tests/test-ci-parts.sh` (rules 10 and 11),
`tests/lint.sh` (one line of the `if:` rule), the bash tests that decision 4 rewrites (from `tests/smoke-slot.sh`,
`tests/smoke-status.sh`, `tests/smoke-check.sh`, `tests/test-guard-rules.sh`, `tests/smoke-release.sh`,
`tests/smoke-validate.sh` and any other step decision 1 measures), `README.md` and `CHANGELOG.md`.

**Never auto-merged.** The pull request changes `.github/workflows/ci.yml`, so the implementer opens it without `--auto`
and the maintainer merges it by hand, as in iterations 60 and 64.

## Story trigger and manual check

**Not a story trigger.** *Status flow*: no status, no board call and no decision record changes. *Config key*: none is
added, renamed or removed. `verification.checkJobs` and `verification.platform` keep their values and meaning, and the
job's step list and parts belong to this repository's CI, not to a project. *Slot marker*: no script that writes a
marker changes its behaviour (decision 6). **Compatible** holds: a project reads nothing that changes.

**The manual check does not apply.** `verification.manualCheckPaths` is `skills`, `agents`, `hooks`, and no file under
them changes. In its place the maintainer looks at the pull request's own CI runs (Tests, "On the pull request's run").

**Shells.** The changes are to bash tests and to CI. No `.ps1` file changes, so no PowerShell script changes its
behaviour (out of scope) and the PowerShell tests run as before. No file under `scripts/` changes either (decision 6),
so the "Two shells" rule of `.claude/CLAUDE.md` is not touched and **Both shells** still holds. The smoke
steps involved are those decision 4 rewrites. Each keeps its cases, and the Ubuntu job `bash scripts smoke tests` runs
it as before.

## Facts this rests on

Read on `main` at c5ffdb7 ("fix: the lint fails on a fixture directory that no map line names (#379) (#381)") on
2026-11-24. No network call was made. The CI numbers are the ones the issue gives, and nothing here was timed.

- **The job.** `smoke-gitbash` in `.github/workflows/ci.yml`: `name: Git Bash smoke tests (Windows, not blocking)`,
  `runs-on: windows-latest`, `timeout-minutes: 360`, checkout with `fetch-depth: 0`, and one step with `shell: bash`
  and `continue-on-error: true` whose line is `run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT
  <list>`. `<list>` holds every `add bash` step of `tests/check.sh`, 48 of them, in list order, `smoke-json.sh` first.
  `tests/test-ci-parts.sh` pins this: rule 10 pins the job's shape and rule 11 that the list holds every bash step
  exactly once, nothing else, in list order.
- **How many run at once.** `tests/check.sh` runs `L` steps at a time. `L` is `verification.checkJobs` (4 in
  `.claude/nightmill.json`), capped at the machine's processors. The steps marked `first` start first. Among the bash
  steps those are `smoke-slot.sh` and `test-spec-template.sh`. `test-lintcopy-output.sh` is marked `slow`. A
  selective `--affected` run leaves it out (iteration 62), but `--only` and the fallbacks run it. So on a push to
  `main`, and on a pull request that changes a shared path, the job runs all 48 steps.
- **The CI numbers (from the issue).** Run 45235773214 ran every step in 59m12s. Run 45199508267 ran 10 of the 48 steps
  in 23m41s. The slowest steps of 45235773214, each timed while other steps ran beside it, were:
  `test-lintcopy-output.sh` 34m40s, `smoke-slot.sh` 25m43s, `smoke-status.sh` 18m29s, `smoke-check.sh` 16m44s,
  `test-guard-rules.sh` 16m19s, `smoke-release.sh` 13m10s and `smoke-validate.sh` 12m48s. Together that is 137m53s.
  With 4 steps at a time, a 17-minute wall time holds at most 68 step-minutes, so the seven took about twice that
  before the other 41 steps ran. Six of the seven take more than 12 minutes each, close to the budget on their own.
  Whether a step is faster when nothing runs beside it is not known. The 41 others took at most about 99
  step-minutes together (4 times 59m12s, less the seven), so a split needs several runners, not two.
- **Where the time may go, by reading the code** (to be confirmed by decision 1). These are counts, not timings.
  - `test-lintcopy-output.sh` (175 lines): its `# Time:` note (iteration 62) says it copies the repository twice with
    tar and runs six whole bash scripts. Three of them are steps of the list: `smoke-status.sh`, `smoke-release.sh`
    and `smoke-check.sh`. The `smoke-check.sh` run nests 33 runs of the lint section, each on a fresh copy of the
    repository.
  - `smoke-slot.sh` (2319 lines, 23 `== ` sections): 172 lines that call `git`, 6 `git init`/`git clone` lines, 129
    lines that start `bash`, polling waits of `sleep 0.1` bounded by a counter, and two fixed `sleep 1` in the
    interruption and retry cases. Those two are part of what the cases assert ("the take still runs 1 s later").
  - `smoke-check.sh` (805 lines): about 60 runs of the check on fixture steps, and 33 `lint_break` copies, each of
    which runs the lint range on a fresh copy.
  - `smoke-status.sh`, `smoke-release.sh` and `smoke-validate.sh` each run the whole lint once, on a copy of the
    repository, in their case "the lint notices ...". `smoke-release.sh` also has 37 lines that call `git`.
  - `test-guard-rules.sh` (275 lines, 8 sections) is text checks, plus the guard run on commands. In
    `== no rule matches a command the skills write`, a loop over 3 branches, every span of every skill and agent, and
    every sub-command starts `sed` and `$(unbody ...)` once per sub-command and once per rule. In
    `== no guard refusal matches a command the skills write`, `scripts/guard.sh` runs once per span.
- **The earlier Git Bash failures are fixed.** The three steps that iteration 65's Facts found red on the runner are
  fixed on `main`: `smoke-json.sh` (#372, PR #377), `smoke-slot.sh` (#373, PR #375) and `smoke-drive.sh` (#374,
  PR #378).
- **The precedent for parts (iteration 55).** The PowerShell steps run in the matrix job `smoke-powershell-part`
  (`name: PowerShell smoke part ${{ matrix.part }} of 4`, `fail-fast: false`, one `- part: <k>` / `only: <list>` pair
  per part, one run step `... $CHECK_SELECT ${{ matrix.only }}`), and the final job `smoke-powershell` carries the
  required name, `needs:` the part job, has `if: always()`, and fails unless `needs.smoke-powershell-part.result` is
  `success`. The parts live in the workflow: `tests/check.sh` has no part option (iteration 55 decision 3).
  `tests/test-ci-parts.sh` rules 1 to 8 pin that job pair; `tests/test-ci-job-times.sh` finds the final job's steps by
  their names (`- name: Job times`, `- name: Every part succeeded`).
- **The selection per part (iteration 60).** Each part runs `$CHECK_SELECT <its list>`: on a push `--only <list>`, on a
  pull request `--affected --within <list>`. A part whose list no changed path selects runs 0 steps and passes
  (iteration 60 decision 4); a shared path runs the part's whole list (its decision 2, the fallback, with the summary
  line `Selection: --affected ran every --within step: <reason>.`).
- **What the lint pins of CI.** `tests/lint.sh` line 1566: a job key `    if:` is allowed only as `    if: always()` in
  `smoke-powershell`; any other gives `job <id> has an 'if:' (a required job runs on every event)`. Lines 1408 to
  1418: the three required names are each the `name:` of exactly one job, and no other job's name begins with one of
  them. Lines 1722 and 1799: the `Required check` comment occurs exactly 3 times. Lines 1749 to 1766: every job has a
  `timeout-minutes` from 1 to 360. Rule 8 of `tests/test-ci-parts.sh`: only `smoke-powershell` has a job-level
  `permissions:` block (with `actions: read`, which its job table needs; iteration 55 decision 11).
- **Runners** (by GitHub's documentation, not read for this spec): the standard Windows runner of a public repository
  has 4 processors, so `L` is 4 in each part; the Free plan runs at most 20 jobs of an account at once. A run today
  starts 8 jobs at once (`lint`, `smoke-bash`, 4 PowerShell parts, `smoke-gitbash`, `validate`).
- **What the specs already fix.** Iteration 64 decision 3: the job runs every bash step and has no skip list, "a skip
  list would guess at what nobody has measured" (superseded for the one measured step `test-lintcopy-output.sh` by
  decision 3 of this spec). Iteration 64 decision 4: the iteration that makes the job required
  splits it into parts first when it is over the budget, "by the measured step times, as iteration 55 did for
  PowerShell". Iteration 65 decision 7 (draft): the job becomes `Git Bash scripts smoke tests` and lands only when a
  full run is green, its summary ends `SELECTED CHECKS PASSED (48 of <M> steps; ...)`, and its wall time is at most 17
  minutes. Iteration 62: a profiled step says where its time goes in a `# Time: ` note, and the seconds go into the
  pull request.
- **The test files stay generic.** No bash test branches on the platform, so Ubuntu and Git Bash run the same cases.

## Measurements

Filled in by the implementer (decision 1) before any test changes, and completed in the same pull request. It holds
four tables and one paragraph. Measured on 2026-11-24 in Git Bash on the maintainer's Windows machine, from the slot's
root, one step at a time with nothing else of the check running, through the timestamper of decision 1 (in the
scratchpad, not committed). `smoke-slot.sh`'s first run ended red in `== interruption (iteration 36)` after 1684 s
(the timestamper keeps only the `== ` lines, so its `FAIL:` line is not known); its sections up to there were within
about 10% of the second run, which passed and is the one in the table (the same pipeline with one `tee` added to keep
the output). The local machine is slower than a runner for some steps (`smoke-drive.sh` 27m06s alone here, 6m10s in
CI with three steps beside it), so the local times choose the sections and the CI times choose the parts (Risks).

**Cost of one process** (local Git Bash, 200 runs each, total and per run):

| What | 200 runs | Per run |
|---|---|---|
| `/usr/bin/true` | 8.8 s | 44 ms |
| `x=$(printf y)` (a subshell) | 5.1 s | 26 ms |
| `git --version` | 15.7 s | 79 ms |
| `git init -q` plus one `git commit` in a fresh folder | 59.3 s | 296 ms |

**Sections** (one block of rows per measured step; every section of 60 s or more has a row of its own, the rest of
each step is one row; the seconds are the timestamper's; a step without `== ` headers is one row):

| Step | Section (`== ` header) | Alone, local Git Bash | Share of the step | What it starts (by reading) | Why it costs (process-bound, lint, wait, other) | Action (decision 4) |
|---|---|---|---|---|---|---|
| `smoke-slot.sh` (2185 s) | automatic release | 245 s | 11% | 18 lines that run `scripts/slot.sh` (in `prepare` and `cleanup`, called per case), 13 `git` lines, 37 `$(...)` | process-bound: dozens of runs of `slot.sh`, each starting tens of `git` and helper processes (at 26 to 79 ms each) | pending CI |
| `smoke-slot.sh` | capacity | 287 s | 13% | 29 `slot.sh` lines, 10 `git` lines, 54 `$(...)` | process-bound (`slot.sh` runs) | pending CI |
| `smoke-slot.sh` | reports | 290 s | 13% | 14 `slot.sh` lines, several in loops over the report steps, 64 `$(...)` | process-bound (`slot.sh --report` runs, each reading and writing the marker) | pending CI |
| `smoke-slot.sh` | claim (iteration 34) | 507 s | 23% | 32 `slot.sh` lines, 56 `git` lines, 134 `$(...)`, 4 polling waits (`sleep 0.1` under a counter) | process-bound, with some waiting in the polls | pending CI |
| `smoke-slot.sh` | marker retries (iteration 35) | 246 s | 11% | 6 `slot.sh` lines in loops over retry counts, 11 `git` lines, 4 polling waits | process-bound, with some waiting | pending CI |
| `smoke-slot.sh` | interruption (iteration 36) | 157 s | 7% | 2 `slot.sh` lines run per signal case in the background, 12 `git` lines, 5 waits: polls of `sleep 0.1` (bounded to 60 s and 5 s) and the asserted `sleep 1` | wait-bound in part (the polls until the take is killed and ends), the rest process-bound | pending CI |
| `smoke-slot.sh` | the record (iteration 41) | 103 s | 5% | 6 `slot.sh` lines, 5 `git` lines, 43 `$(...)` | process-bound | pending CI |
| `smoke-slot.sh` | the other 16 sections | 348 s together, at most 52 s each | 16% | `slot.sh` and `git` calls | process-bound | below 60 s each |
| `smoke-status.sh` (1803 s) | json | 122 s | 7% | runs of `scripts/status.sh --json` on fixture boards (a `gh` stub), 14 `$(...)` | process-bound (`status.sh`'s own process starts) | pending CI |
| `smoke-status.sh` | json --all | 72 s | 4% | `status.sh --json --all` runs | process-bound | pending CI |
| `smoke-status.sh` | the text form and the porcelain form are unchanged | 70 s | 4% | `status.sh` runs in the three forms | process-bound | pending CI |
| `smoke-status.sh` | the lint notices a status script that changes the board | 1245 s | 69% | one `tar` copy of the repository and two whole runs of `tests/lint.sh` on it (unchanged, then broken) | lint: two whole lints, about 620 s each | pending CI |
| `smoke-status.sh` | the other 19 sections | 293 s together, at most 53 s each | 16% | `status.sh` runs | process-bound | below 60 s each |
| `smoke-check.sh` (1567 s) | two checks at once | 71 s | 5% | two `tests/check.sh` runs at once on fixture steps | process-bound (`check.sh` starts) | pending CI |
| `smoke-check.sh` | the lint: the check runs every smoke script | 1396 s | 89% | one section of `tests/lint.sh` run 34 times (1 unchanged and 33 `lint_break` copies), each on a fresh `cp` copy of `tests/`, `scripts/`, `skills/` and the CI files, each with a rules-only run of `tests/test-ci-parts.sh` | lint: 34 runs of one lint section, about 41 s each | pending CI |
| `smoke-check.sh` | the other 9 sections | 99 s together, at most 51 s each | 6% | `check.sh` runs on fixture steps | process-bound | below 60 s each |
| `test-guard-rules.sh` (1685 s) | no rule matches a command the skills write | 1053 s | 62% | for 3 branches, 320 spans with 364 sub-commands: per sub-command one `$(printf \| sed)` and 23 `$(unbody ...)`, per span a `fill` (`sed`) and `split_cmds` (`awk`): about 26 000 subshells | process-bound: 26 000 subshells at 26 ms are about 680 s, more than half | pending CI |
| `test-guard-rules.sh` | no guard refusal matches a command the skills write | 627 s | 37% | per span (320) and per GraphQL document: one `fill`, one `$(gjesc ...)` and one run of `scripts/guard.sh` with a `gh` stub | process-bound, most of it in `scripts/guard.sh`'s own starts (about 2 s per run) | pending CI |
| `test-guard-rules.sh` | the other 6 sections | 5 s together | 0% | text checks | other | below 60 s each |
| `smoke-release.sh` (1357 s) | the lint notices versions that disagree | 1275 s | 94% | one `tar` copy and two whole runs of `tests/lint.sh` | lint: two whole lints | pending CI |
| `smoke-release.sh` | the other 7 sections | 79 s together, at most 34 s each | 6% | runs of `scripts/release.sh` on fixture repositories, 37 `git` lines | process-bound | below 60 s each |
| `smoke-validate.sh` (1306 s) | the lint notices a schema keyword the validator does not support | 621 s | 48% | one `tar` copy and one whole run of `tests/lint.sh` | lint: one whole lint | pending CI |
| `smoke-validate.sh` | the lint notices a role the workflow skill does not name | 623 s | 48% | one more `tar` copy and one more whole lint | lint: one whole lint | pending CI |
| `smoke-validate.sh` | the other 14 sections | 61 s together, at most 11 s each | 5% | runs of `scripts/validate-config.sh` | process-bound | below 60 s each |
| `test-lintcopy-output.sh` (4575 s) | (no `== ` headers): the whole step | 4575 s | 100% | two `tar` copies, whole runs of `smoke-status.sh`, `smoke-release.sh`, `smoke-check.sh`, `test-spec-template.sh` and `test-ci-parts.sh` (with shims that count calls), and their nested lints | lint: the nested whole lints and lint sections of three other steps | not needed (off the job, decision 3) |
| `smoke-control.sh` (752 s) | 3. hold in the cooldown | 74 s | 10% | 7 runs of `scripts/control.sh` (each runs the load and slot scripts) | process-bound, in `scripts/control.sh` | pending CI |
| `smoke-control.sh` | 6. bounds | 84 s | 11% | 7 `control.sh` lines, one in a loop | process-bound, in `scripts/control.sh` | pending CI |
| `smoke-control.sh` | 7. steady, and the slot count is raised only by a new limit above it | 87 s | 12% | 7 `control.sh` runs | process-bound, in `scripts/control.sh` | pending CI |
| `smoke-control.sh` | 9. report only decides the same and changes nothing | 163 s | 22% | 3 `control.sh` lines over the scenarios, with report-only runs | process-bound, in `scripts/control.sh` | pending CI |
| `smoke-control.sh` | 12. unusable config values fall back | 143 s | 19% | 6 `control.sh` lines in 4 loops over bad values | process-bound, in `scripts/control.sh` | pending CI |
| `smoke-control.sh` | the other 9 sections | 200 s together, at most 41 s each | 27% | `control.sh` runs | process-bound | below 60 s each |
| `test-spec-template.sh` (720 s) | the lint checks the headings of specs from iteration 40 on | 718 s | 100% | one whole run of `tests/lint.sh` and runs of its spec section alone on spec fixtures | lint | pending CI |
| `test-spec-template.sh` | the other 2 sections | 2 s together | 0% | text checks | other | below 60 s each |
| `smoke-drive.sh` (1626 s) | (no `== ` headers): the whole step | 1626 s | 100% | 38 `new_case` fixtures (a bare `git init`, a `clone`, a commit and a push each) and runs of `scripts/drive.sh` with `gh` and `claude` stubs | process-bound: the 38 fixtures are about 25 s of `git`, the rest is in `scripts/drive.sh`'s runs | pending CI |
| `smoke-load.sh` (458 s) | the suggestion and its reason (scenarios b to g and i) | 114 s | 25% | `scripts/load.sh` runs over the fixture scenarios | process-bound, in `scripts/load.sh` | pending CI |
| `smoke-load.sh` | unusable config values fall back to the default | 103 s | 22% | 3 `load.sh` lines in 3 loops over bad values | process-bound, in `scripts/load.sh` | pending CI |
| `smoke-load.sh` | an unusable fixture stops the command | 62 s | 14% | `load.sh` runs on broken fixtures | process-bound, in `scripts/load.sh` | pending CI |
| `smoke-load.sh` | the other 10 sections | 179 s together, at most 47 s each | 39% | `load.sh` runs | process-bound | below 60 s each |

**Steps in CI** (one row per step of the job's list; `t` is decision 5's input; the Git Bash job's `Times:` blocks,
before and after, and the Ubuntu job's time for the same step; the Ubuntu times are those of the job
`bash scripts smoke tests` of the same run, `smoke-json.sh` from its own step):

| Step | Git Bash before, `t` (45235773214) | Part | Git Bash after (final run) | Ubuntu (45235773214) |
|---|---|---|---|---|
| `smoke-json.sh` | 16s | 7 | pending | 1s |
| `smoke-hook.sh` | 1s | 7 | pending | 0s |
| `smoke-release.sh` | 13m10s | 5 | pending | 1m50s |
| `smoke-slot.sh` | 25m43s | 1 | pending | 1m33s |
| `smoke-render.sh` | 34s | 7 | pending | 2s |
| `smoke-validate.sh` | 12m48s | 6 | pending | 1m49s |
| `smoke-status.sh` | 18m29s | 2 | pending | 2m06s |
| `smoke-template-board.sh` | 59s | 7 | pending | 3s |
| `smoke-models.sh` | 15s | 7 | pending | 1s |
| `smoke-load.sh` | 5m13s | 7 | pending | 15s |
| `smoke-room.sh` | 58s | 7 | pending | 11s |
| `smoke-control.sh` | 8m49s | 7 | pending | 24s |
| `smoke-dashboard.sh` | 3m28s | 7 | pending | 8s |
| `smoke-panel.sh` | 1m54s | 7 | pending | 4s |
| `smoke-stages.sh` | 21s | 7 | pending | 2s |
| `smoke-check.sh` | 16m44s | 3 | pending | 1m05s |
| `test-lintcopy-output.sh` | 34m40s | none (decision 3) | not run | 3m13s |
| `test-lint-pipefail.sh` | 10s | 7 | pending | 0s |
| `test-release-resume.sh` | 41s | 7 | pending | 2s |
| `test-release-low-defects.sh` | 42s | 7 | pending | 2s |
| `test-json-bom.sh` | 1s | 7 | pending | 0s |
| `test-render-quoting.sh` | 4s | 7 | pending | 0s |
| `test-changelog-refs.sh` | 0s | 7 | pending | 0s |
| `test-check-skill.sh` | 0s | 7 | pending | 0s |
| `test-status-controls.sh` | 9s | 7 | pending | 1s |
| `test-worker-merge.sh` | 0s | 7 | pending | 0s |
| `test-script-modes.sh` | 4s | 7 | pending | 1s |
| `test-fix-pick.sh` | 0s | 7 | pending | 0s |
| `test-changelog-coverage.sh` | 1s | 7 | pending | 0s |
| `test-json-speed.sh` | 4s | 7 | pending | 2s |
| `test-mktemp-template.sh` | 19s | 7 | pending | 1s |
| `test-skill-config-fallback.sh` | 13s | 7 | pending | 1s |
| `test-slot-number.sh` | 25s | 7 | pending | 2s |
| `test-board-listing.sh` | 5s | 7 | pending | 0s |
| `test-resume-stuck.sh` | 1s | 7 | pending | 1s |
| `test-story-dedup.sh` | 0s | 7 | pending | 0s |
| `test-interrupt-docs.sh` | 2s | 7 | pending | 0s |
| `test-spec-template.sh` | 6m37s | 7 | pending | 58s |
| `smoke-guard.sh` | 1m56s | 7 | pending | 5s |
| `test-watch-checks.sh` | 8s | 7 | pending | 1s |
| `test-guard-rules.sh` | 16m19s | 4 | pending | 48s |
| `smoke-drive.sh` | 6m10s | 7 | pending | 43s |
| `smoke-gate.sh` | 2m21s | 7 | pending | 6s |
| `smoke-history.sh` | 1m28s | 7 | pending | 4s |
| `test-ci-summary.sh` | 7s | 7 | pending | 1s |
| `test-baseconfig-pathconv.sh` | 4s | 7 | pending | 0s |
| `test-restricted-path-git.sh` | 7s | 7 | pending | 1s |
| `test-slot-low-defects.sh` | 48s | 7 | pending | 2s |

**Parts** (decision 5; one row per part). Rule 1 gives the six alone parts of the Facts. Rule 2 gives `P` = 1: the
other 41 steps sum to 45m35s, under 48m00s, and the largest of them, `smoke-control.sh`, is 8m49s, under 12m00s. So
`N` is 7 (rule 3), not the "about 3" packed parts the spec guessed before the measurement.

| Part | Steps | Sum of `t` | Largest `t` | Estimate | `Wall time:` (final run) | Job time (final run) |
|---|---|---|---|---|---|---|
| 1 | `smoke-slot.sh` | 25m43s | 25m43s | 25m43s | pending | pending |
| 2 | `smoke-status.sh` | 18m29s | 18m29s | 18m29s | pending | pending |
| 3 | `smoke-check.sh` | 16m44s | 16m44s | 16m44s | pending | pending |
| 4 | `test-guard-rules.sh` | 16m19s | 16m19s | 16m19s | pending | pending |
| 5 | `smoke-release.sh` | 13m10s | 13m10s | 13m10s | pending | pending |
| 6 | `smoke-validate.sh` | 12m48s | 12m48s | 12m48s | pending | pending |
| 7 | the other 41 steps of the list, in list order | 45m35s | 8m49s (`smoke-control.sh`) | 11m24s | pending | pending |

The chain of the final run (decision 2): pending (run id pending).

**Summary paragraph**: The costliest sections are the whole lints on a copy of the repository: two in each of
`smoke-status.sh`, `smoke-release.sh` and `smoke-validate.sh` (about 620 s each here, 69% to 96% of those steps), 34
runs of one lint section in `smoke-check.sh` (1396 s, 89%), and one in `test-spec-template.sh` (718 s); they are
lint-bound, and the lint itself starts many processes. Next comes `test-guard-rules.sh`, whose two rule sections
(1053 s and 627 s) start about 26 000 subshells and one `scripts/guard.sh` run per span: process-bound, the first in
the test, the second mostly in the script. `smoke-slot.sh` has no single large section: six sections of 157 s to 507
s, all runs of `scripts/slot.sh` and `git`, are 79% of its 2185 s, process-bound, with the interruption polls as the
only waits. `smoke-control.sh`, `smoke-load.sh` and `smoke-drive.sh` spend their time in runs of their scripts. One
process costs 26 ms (a subshell) to 79 ms (`git`) here, which is why the steps are much slower in Git Bash than on
Ubuntu (7 to 20 times for the seven slowest). By the estimates, the split alone leaves parts 1 to 4 over the 14m00s of
decision 2 and parts 5 and 6 close to it, so decision 4's rounds are expected to be needed on those parts (pending the
pull request's CI run).

## Decisions

**1. The measurement comes first, and goes into this spec.** The issue asks this spec to hold the measurement and to
choose how the time is cut. A spec is written before the work, and no per-section timing exists yet, so nothing is
invented here. The measurement is the implementation's first deliverable. The choice is made now, as rules (decisions
2 to 5) that the implementer applies to what it measures, with fixed numbers. The rules do not depend on the timings.
The timings only decide the parts of decision 5, which sections decision 4 rewrites, and when decision 5 stops the
work.

- *What is measured*: the seven steps of Facts, and every other bash step whose time in the `Times:` block of the Git
  Bash job of run 45235773214 is 5m00s or more (read with `gh run view 45235773214 --log`, read only). The same block
  gives every step's `t` for decision 5 (the table "Steps in CI").
- *Where*: locally, in Git Bash on this Windows machine, each step alone, nothing else of the check running. One
  measured run per step, from the repository root, through this timestamper. It lives in the scratchpad and is never
  committed:

  ```
  bash tests/<step> 2>&1 | { s=$SECONDS; while IFS= read -r l; do case $l in "== "*) printf '%5ds %s\n' $((SECONDS - s)) "$l" ;; esac; done; printf '%5ds (end)\n' $((SECONDS - s)); }
  ```

  A section's time is the next line's seconds minus its own. The loop uses only builtins, so it starts no process
  per line.
- *Why*: each section's row names what it starts (git calls, bash or other processes, lint runs, copies of the
  repository, fixed waits), counted from the code, and the cost of one process from the first table. A section is
  **process-bound** when its counted processes times the cost per process reach half its time or more. Otherwise it is
  lint-bound, wait-bound or other, and the row says which.
- The Ubuntu column comes from the same run's job `bash scripts smoke tests`. A step far slower in Git Bash than on
  Ubuntu points at process starts.
- The implementer commits the filled tables with the split of decision 5, the first change, so the reviewer reads the
  parts and each later rewrite against the rows that chose them. The "after" columns, the chain line and the summary
  paragraph are completed from the final run.

**2. The budget.** The time a required check is allowed is **17 minutes**: iteration 64 decision 5, the 16m59s of the
PowerShell chain it is to replace. The check a pull request waits for is the final job (decision 5), so the budget
holds for the chain of the Git Bash jobs, not for one part. The iteration has met it when the final commit of the pull
request has two full runs of the Git Bash jobs: the run its push starts, and one re-run of that run
(`gh run rerun <id>`). Every bash step of the job's list runs (`$CHECK_SELECT` takes the fallback in every part,
because the pull request changes `ci.yml`). In each of the two runs:

- every part's check step passes: the last line of the check step's log (stdout, not the job summary) is
  `SELECTED CHECKS PASSED (<k> of <M> steps; the full check has not run)`, where `<k>` is the length of the part's
  list, and the `<k>` of all parts add up to the length of the job's list (47, decision 3);
- every part's job summary has, inside its `### tests/check.sh` section, the line
  `Selection: --affected ran every --within step: <reason>.` (the fallback);
- every part's `Wall time:` in its `### tests/check.sh` section is at most **14m00s**;
- every part's own time in the run's job list, from start to completion, is at most **17m00s**;
- the job `Git Bash smoke tests (Windows, not blocking)` has the conclusion `success`, and the **chain**, from the
  earliest start of a Git Bash part to the completion of that final job, is at most **17m00s**. The times are read
  with `gh run view <id> --json jobs` (read only).

The 14m00s leaves 3 minutes for the runner's start, the full-history checkout, the final job, and the spread between
two runs of the same commit. A run that only just meets 17 minutes would make a required check fail by chance. A part
that waits in the queue for a runner counts: the chain is what a pull request waits for. `continue-on-error` stays on
each part's check step, and the parts' timeout stays 360. Making the jobs blocking, and their timeout, belong to
iteration 65 decision 7 (decision 8).

**3. A smaller list: `test-lintcopy-output.sh` comes off the Git Bash job.** The job's list (the parts' lists
together) becomes every `add bash` step of `tests/check.sh` except the steps on the list `gitbash_out`, which is
exactly `test-lintcopy-output.sh`. That makes 47 steps.

- *Iteration 64 decision 3, superseded for this one step*: that decision runs every bash step in the job, with no
  skip list, because "a skip list would guess at what nobody has measured". For `test-lintcopy-output.sh` that reason
  no longer holds: the step was measured, 34m40s in run 45235773214, about half of it re-running three other steps of
  the same job (below). So this decision supersedes iteration 64 decision 3 for that step only. For every other step
  iteration 64 decision 3 still holds (the job runs it, and none is skipped on Windows), and so does its rule that a
  step failing in Git Bash is a bug of its own (decision 5).

- *Why this step*: it alone took 34m40s, twice the budget. Half of it is whole runs of `smoke-status.sh`,
  `smoke-release.sh` and `smoke-check.sh` on copies, and the same job runs each of them as a step of its own. No cut
  of its own sections, and no part, brings it under 17 minutes unless those three steps get faster too.
- *What coverage it gives up*: the regression checks it holds, run in Git Bash on Windows. They are #217 (a smoke test
  prints the lint's `FAIL:` lines when the lint fails on its copy), #280 (`test-spec-template.sh` starts no nested
  lint), #293 (`smoke-check.sh`'s lint copies skip the CI-parts cases) and #340 (no agreement cases on the lint copies).
  They check what the bash tests themselves print and start, not a script under `scripts/`.
- *Where it is tested now*: in the Ubuntu job `bash scripts smoke tests`, which keeps it in its `--only` list. That job
  runs it on every push to `main` and on every pull request that changes a shared path. Locally,
  `bash tests/check.sh --only test-lintcopy-output.sh` runs it. Its PowerShell twin stays in its part.
- *No other step comes off the list.* Each other step starts at least one script, hook or check run that only it
  starts. A further step comes off only when this decision lists it, with its coverage written here.
- `tests/test-ci-parts.sh` rule 11 learns the list (decision 7). `tests/check.sh`, the slow mark and the Ubuntu job's
  list do not change. Iteration 62 decision 7 (the `--only` lists of `smoke-bash` and the parts name every step) still
  holds. It does not cover the Git Bash job.

**4. Fewer processes, with the same cases.** After the split (decision 5), for every measured section of 60 s or more
alone that belongs to a step of a part that misses decision 2's numbers on the latest full run, taken in order of time
(largest first), the implementer does exactly one of these, until decision 2 holds, and the section's row in
`## Measurements` says which (a section that was never reached says `not needed`):

- **rewrite** a process-bound section so that it starts fewer processes, with these means only:
  - a builtin (parameter expansion, `case`, `printf -v`, `read`, `[[ ]]`) in place of `$(...)`, `sed`, `tr`, `grep` or
    `printf | ...` inside a loop;
  - one `awk` or `grep` pass over a file in place of a loop that starts a process per line or per item (bug #270's
    rule);
  - a fixture repository built once per file (`git init` and its commits) and copied with `cp -R` for each case, in
    place of building it again, when the case only needs that starting history;
  - several `git config` or `git` read calls merged into one call where git accepts them in one (for example one
    `git -c ... ` or one `git for-each-ref`).
- **rewrite** a lint-bound section so that a lint copy runs the part of the lint the case is about, with the
  `NIGHTMILL_CI_PARTS_RULES_ONLY=1` means of iterations 55 and 62 (the case files that the lint step runs once are left
  out of the copy). This applies only when the case's expected `FAIL:` text comes from a section that still runs on
  the copy.
- **keep** it, with one line in its row saying why it cannot be made cheaper without dropping a case. A wait-bound
  section is always kept: a polling wait (`sleep 0.1` under a bounded counter) and a fixed `sleep 1` that a case asserts
  on stay as they are.

What every rewrite keeps, for each changed test file:

- The same `== ` section headers, in the same order. The output of `grep -E '^[[:space:]]*echo "== ' tests/<f>` is
  equal before and after.
- Every failure text. Each string passed to `fail`, `bad`, `fl` or `echo "FAIL: ...` before the change is still in the
  file after it.
- The same cases: no case removed, merged so that one failure hides another, or skipped on a platform. No `uname`,
  `OSTYPE` or `MSYSTEM` test is added. No bound of a wait loop is lowered, and no expected text changes.
- A bash smoke file that says "Same cases as smoke-<x>.ps1" stays true. Its `.ps1` twin does not change.

**5. The split into parts, and when to stop** (the maintainer's decision for this iteration: split the job now, and
accept `partial` first). The split gives up no coverage: every step of the job's list still runs in Git Bash on a
Windows runner, exactly once per run, with the same `L` of 4.

*The rule for the parts.* `t(s)` is step `s`'s time in the `Times:` block of the Git Bash job of run 45235773214
(decision 1), for each of the 47 steps of decision 3. A step that has no line there gets its time in the Git Bash job
of the latest push run on `main` that ran it, else 5m00s.

1. **Alone.** Every step with `t` of 12m00s or more gets a part of its own. These parts come first, numbered from 1 in
   order of `t`, largest first (equal `t`: list order). They are the list `gitbash_alone` (decision 7). By the Facts
   these are 6: `smoke-slot.sh`, `smoke-status.sh`, `smoke-check.sh`, `test-guard-rules.sh`, `smoke-release.sh` and
   `smoke-validate.sh`.
2. **Packed.** The other steps go into `P` further parts, by largest first: sorted by `t`, largest first (equal `t`:
   list order), each step goes into the packed part with the smallest sum of `t` so far (equal sums: the lower part
   number). `P` is the smallest number from 1 up for which every packed part's sum of `t` is at most **48m00s** (4
   steps at a time for 12 minutes) and its largest `t` below 12m00s. By the Facts `P` is about 3.
3. **How many.** `N` is the number of alone parts plus `P`, at least 2 and at most **10**. When the rule gives more
   than 10, `P` becomes `10` minus the alone parts and step 2 runs again with that `P` and no 48m00s limit. When it
   gives 1, `P` is 2. The 10 keeps one run at no more than 19 jobs at once (Facts: the 7 other jobs that start at
   once, the PowerShell final job, the `N` parts and the Git Bash final job), under the 20 an account runs at once.
4. Each part's list is in step-list order. The **estimate** of a part is the larger of its largest `t` and its sum of
   `t` divided by 4; the table "Parts" shows it. `t` was timed with 3 other steps beside it on the same runner, so a
   part with fewer steps is not expected to be slower than its estimate.

*The jobs*, written exactly so, after `smoke-powershell` and before `validate`, in place of today's `smoke-gitbash`
(`<N>` the number of parts, one `- part:` / `only:` pair per part, `<list k>` part `k`'s steps comma-separated; the
comment lines wrapped at 120 columns):

```yaml
  smoke-gitbash-part:
    # The bash steps in Git Bash on Windows runners, in parts (iterations 64 and 66; decision record 0004, migration
    # step 1). Not a required check, and its check step does not fail the part: the job smoke-gitbash below fails
    # unless every part succeeded.
    name: Git Bash smoke part ${{ matrix.part }} of <N>
    runs-on: windows-latest
    timeout-minutes: 360
    strategy:
      fail-fast: false
      matrix:
        include:
          - part: 1
            only: <list 1>
          - part: 2
            only: <list 2>
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
      - shell: bash
        continue-on-error: true
        run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT ${{ matrix.only }}

  smoke-gitbash:
    # The Git Bash parts together (iteration 66). Not a required check until iteration 65 makes it one.
    name: Git Bash smoke tests (Windows, not blocking)
    needs: smoke-gitbash-part
    if: always()
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Every Git Bash part succeeded
        env:
          PARTS: ${{ needs.smoke-gitbash-part.result }}
        run: |
          echo "the Git Bash parts: $PARTS"
          [ "$PARTS" = success ] || { echo "FAIL: a Git Bash part did not succeed ($PARTS)"; exit 1; }
```

- The final job needs no checkout and no `permissions:` block, and gets no job table: that step needs `actions: read`,
  which only `smoke-powershell` has (iteration 55 decision 11; Not done). Its step is not named
  `Every part succeeded`, so `tests/test-ci-job-times.sh`, which finds that name, reads only `smoke-powershell`.
- `CHECK_SELECT` and `--within` work per part as in the PowerShell parts (Facts): on a pull request each part checks
  the steps of its own list that the changed paths select, a part with none runs 0 steps and passes, and a shared path
  runs the part's whole list. On a push each part runs `--only <its list>`. `tests/check.sh` does not change: no part
  option, no group field in the step list (iteration 55 decision 3).
- While the check steps keep `continue-on-error: true`, a part succeeds even when a step fails, so the final job fails
  only when a part is cancelled, times out or cannot start. Iteration 65 removes `continue-on-error` (decision 8).

*The order of the work*:

1. Decision 1's measurement; then the split by the rule, committed with the filled tables. The pull request's run is a
   full run (decision 2).
2. **One rebalance.** When a part misses decision 2's numbers on that run, the implementer may compute the rule once
   more, with `t` now each step's time in the `Times:` block of its part on that run, and change the lists (and
   `gitbash_alone`) once. No further rebalance.
3. Decision 4, round by round, on the parts that still miss; each round is pushed and is a full run.

*When to stop*:

- **Done**: decision 2 holds on the final commit. The implementer fills the "after" columns, the chain line and the
  summary paragraph, and no further section is rewritten.
- **Partial**: every measured section of 60 s or more in the steps of the parts that miss has its action (rewrite or
  keep), and decision 2 still fails. The implementer then adds no part beyond the rule's `N` (at most 10), takes no
  more steps off the list, and lowers no check. It reports `partial` with criterion 3 unmet and gives the final run's
  id, each part's `Wall time:` and job time, the chain, and the five slowest steps of each part that misses. The rest
  (criterion 3: a full run of the Git Bash jobs within the budget) is filed with `/story` as a new story under #337,
  linked to #382, following the workflow's rule for a story only partly done; the pull request says so. The split, the
  list and the rewrites done so far stay in the pull request: they keep every case and shorten the job.
- A step that fails in Git Bash is not a time problem. The implementer lists it with its first `FAIL` line, does not
  fix it here, and it becomes a bug of its own (iteration 64 decision 3). Decision 2 cannot hold while it fails.

**6. Scripts under `scripts/` stay as they are.** The cuts are made in the tests and in CI only. No file under
`scripts/` (`scripts/lib/` included) changes in this iteration. *Why this choice*: the issue's agent note ("A change
to a script in `scripts/` needs both shells until #363 freezes the PowerShell twins") and `.claude/CLAUDE.md` "Two
shells" ("a change to a script in `scripts/` is made in both the `.ps1` and the `.sh`") require a change to a script to
be made in both shells, and the out of scope of the issue forbids a change to the behaviour of a PowerShell script.
Changing only the `.sh` would depart from that rule; changing both would put PowerShell work into an iteration about
bash time. Leaving `scripts/` alone departs from no rule.

- *When a measured section's cost sits in a script under `scripts/`* (its row in `## Measurements` shows that the
  script's own process starts cost the section 60 s or more): the implementer leaves the script as it is. Decision 4
  may still rewrite the test around it (fewer calls of the script only where a case does not need them, with the same
  cases). The row's action is "keep (cost in `scripts/<name>.sh`, follow-up)".
- When decision 2 then fails, the iteration ends `partial` (decision 5), and the report and the follow-up story under
  #337 name each such script and its section's time, so that story changes the script in both shells (or in bash
  only, once #363 has frozen the PowerShell twins).

**7. What pins the two jobs.** No new process in the lint (bug #270): the rules stay in `tests/test-ci-parts.sh`,
which the lint starts once and the lint copies run with `NIGHTMILL_CI_PARTS_RULES_ONLY=1`. Every text has the prefix
`FAIL: .github/workflows/ci.yml: `.

- **Rule 10 becomes two.** *10a, the parts*: the block of `smoke-gitbash-part` exists; it has the job keys
  `name: Git Bash smoke part ${{ matrix.part }} of <n>` (`<n>` a whole number) and `runs-on: windows-latest`,
  `fail-fast: false`, `fetch-depth: 0`, no line `if:` and no line `needs:`, at least two parts, the `- part:` and
  `only:` lines in pairs, `<n>` equal to the number of parts, the part numbers 1 to `<n>` in order, and exactly one run
  step (every `run:` and `- run:` line counts), whose line is
  `run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT ${{ matrix.only }}` in a step with
  `shell: bash` and `continue-on-error: true`. Else `the Git Bash parts are malformed (<what>)`, `<what>` one of:
  `the job smoke-gitbash-part is missing`, `the name line is not 'Git Bash smoke part ${{ matrix.part }} of <N>'`,
  `not runs-on: windows-latest`, `no fail-fast: false`, `no fetch-depth: 0`, `an if: line`, `a needs: line`,
  `fewer than two parts`, `the part and only lines are not in pairs`, `the name says <n> parts, the matrix has <m>`,
  `the part numbers are not 1 to <m> in order`, `<k> run steps, not exactly one`, or
  `the run step is not a run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT ${{ matrix.only }} in a step with shell: bash and continue-on-error: true`.
  *10b, the final job*: the block of `smoke-gitbash` has the lines `    name: Git Bash smoke tests (Windows, not
  blocking)`, `    needs: smoke-gitbash-part`, `    if: always()` and `    runs-on: ubuntu-latest`, a line
  `PARTS: ${{ needs.smoke-gitbash-part.result }}` and a line that begins `[ "$PARTS" = success ] || {`, and no line
  that contains `tests/check.sh`. Else `the Git Bash job is malformed (<what>)`, `<what>` one of
  `the job smoke-gitbash is missing`, `missing: <the line without its indent>`, or `it runs tests/check.sh`.
- **Rule 11**: every `add bash` step of the step list that is not on `gitbash_out` is named in exactly one part's
  `only:` list, each list is in step-list order, every name on `gitbash_alone` is the only step of its part, and both
  lists name only bash steps. The texts: `tests/<x> runs in no Git Bash part`;
  `tests/<x> runs in more than one Git Bash part`;
  `Git Bash part <k> names tests/<x>, which is not a bash step of tests/check.sh`;
  `Git Bash part <k> names tests/<x>, which the Git Bash job leaves out (docs/specs/iteration-66-gitbash-job-time.md, decision 3)`;
  `Git Bash part <k>: the --only list is not in the order of the step list`;
  `Git Bash part <k>: tests/<x> shares its part (docs/specs/iteration-66-gitbash-job-time.md, decision 5)`;
  `the Git Bash job leaves out tests/<x>, which is not a bash step of tests/check.sh`;
  `tests/<x> is to run alone, but it runs in no Git Bash part`. The lists `gitbash_out` and `gitbash_alone` are
  variables of `tests/test-ci-parts.sh`, one name per line; `gitbash_alone` holds the alone parts of decision 5's rule
  (after the rebalance, if any).
- The header comment's sentences on rules 10 and 11 say what 10a, 10b and 11 pin, naming iteration 66.
- `tests/lint.sh`, `== CI selects the steps a pull request affects` (Facts, line 1566): the allowed job key
  `    if: always()` holds in `smoke-powershell` and `smoke-gitbash`, no other job; the comment above it says "the
  if: always() of smoke-powershell and smoke-gitbash (3)". No text of the lint changes, and no `lint_break` is added
  (each costs a lint copy, against this story's goal). The three required names, their comment and its count of 3 do
  not change: no job of this iteration is required, and neither new name begins with a required name.

**8. The required-check names, and what iteration 65 decision 7 must change.** The ruleset is changed by the
maintainer by hand (iteration 65 decision 6), not here. When iteration 65 makes the Git Bash jobs required, the ruleset
needs exactly **one** new name, `Git Bash scripts smoke tests`, carried by the final job `smoke-gitbash`, as
`PowerShell scripts smoke tests` is by `smoke-powershell`. The part names `Git Bash smoke part <k> of <N>` are never
required, so the number of parts can change later without a ruleset change, and none begins with a required name.
This iteration does not edit iteration 65's spec. Before #363's `/next`, its spec is revised (`/spec` on #363) so that
decision 7 says:

- `.github/workflows/ci.yml`: the `Required check` comment and `name: Git Bash scripts smoke tests` go on the final job
  `smoke-gitbash`; the comments of both Git Bash jobs drop "not a required check"; `continue-on-error: true` is removed
  from the check step of `smoke-gitbash-part`; `timeout-minutes` of `smoke-gitbash-part` is 3 times the longest part's
  measured job time, rounded up to whole minutes, at most 360; the final job keeps 5.
- `tests/test-ci-parts.sh`: rule 10a wants the run step with `shell: bash` and no `continue-on-error:` line; rule 10b
  wants `    name: Git Bash scripts smoke tests`; the cases `gbcoe` and `gbname` change with them (Tests of this spec).
- The measurement rule: in place of "its summary ends `SELECTED CHECKS PASSED (48 of <M> steps; ...)`, and its wall
  time is at most 17 minutes", the last line of every part's check step log is
  `SELECTED CHECKS PASSED (<k> of <M> steps; ...)` with the `<k>` adding up to 47, and decision 2 of this spec holds (each part's `Wall time:` at most 14m00s, the chain at most
  17m00s). Its Tests line "with 48 steps in its summary" changes the same way.
- `tests/lint.sh`: the fourth required name and the comment count of 4, as decision 7 has them; the `if: always()` of
  `smoke-gitbash` is already allowed (decision 7 here).
- README: the job sentence starts from this iteration's text (Files touched), not today's.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The time of each section of the slowest bash steps is measured in Git Bash on Windows, and the result (which sections cost the most, and why) is written in the spec | Decision 1; `## Measurements` (filled by the implementer) |
| 2 | The spec chooses how the time is cut (cheaper scenarios, fewer processes, a split of steps, or a smaller step list for the job) and says what coverage each choice gives up | Decisions 3 (a smaller list, its coverage given up), 5 (a split into parts by the measured times, no coverage given up), 4 (fewer processes and lighter lint copies, no coverage given up) and 6 |
| 3 | A full run of the Git Bash job, with every step it has to run, finishes within the time a required check is allowed | Decision 2 (the chain 17m00s, each part 14m00s, two runs); decision 3 (the list it has to run); decision 5 (the parts, done or partial); decision 8 (the name to require) |
| 4 | No scenario is dropped without the spec saying which behaviour it covered and where that is tested now | Decision 3 (`test-lintcopy-output.sh`: what it covers, where it runs now); decision 4 (no case dropped, and how that is checked); decision 5 (every step still runs once); decision 7 (the pins) |
| 5 | The check stays green on Linux and in the PowerShell jobs | Decisions 4 and 6 (same cases, no `.ps1` change); decision 7 (the lint and the PowerShell pins unchanged); Tests (criterion 5) |

## Tests

- Criterion 1: no test reads the measurements. The code reviewer checks that `## Measurements` has every table filled
  for every step decision 1 names, that the table "Parts" follows decision 5's rule from the `t` column (the
  reviewer recomputes it), that each section of 60 s or more in a part that missed has an action, and that the summary
  paragraph names the costliest sections and their cause. The implementer pastes the raw timestamper output of each
  measured step into "How verified" (collapsed), so the reviewer can check the tables against it.
- Criteria 2 and 4, the parts and the list: **`tests/test-ci-parts.sh`**, rules 10a, 10b and 11 of decision 7 pass on
  the checkout. The cases of rule 10 and 11, each on a scratch copy changed once (the existing `changed` guard stays,
  so no case passes on a workflow without the jobs); `gb_case` edits the lines of `smoke-gitbash-part`, and a new
  `gbf_case` those of `smoke-gitbash`:
  - kept, retargeted to `smoke-gitbash-part`, each expecting `the Git Bash parts are malformed`: `gbgone` (the part job
    removed), `gbubuntu`, `gbdepth`, `gbif`, `gbcoe`, `gbshell`, `gbtwo`, `gbname` (` of <N>$` becomes ` of X`),
    `gbneeds`;
  - new, each expecting `the Git Bash parts are malformed`: `gbfailfast` (`fail-fast: false` removed), `gbof` (the name
    says one part more than the matrix), `gbnumbers` (the last two part numbers swapped), `gbonlyrun` (
    ` ${{ matrix.only }}` removed from the run line);
  - new, for the final job, each expecting `the Git Bash job is malformed`: `gbfgone` (the job removed), `gbfname`
    (` (Windows, not blocking)` removed), `gbfalways` (`if: always()` removed), `gbfneeds` (the `needs:` line removed),
    `gbfsuccess` (the `[ "$PARTS" = success ]` line removed), `gbfcheck` (a step `- run: bash tests/check.sh --only
    smoke-json.sh` added: it must not count as a part, `it runs tests/check.sh`);
  - kept with the new texts: `gbnoguard` (`smoke-guard.sh,` removed from its part) expects
    `tests/smoke-guard.sh runs in no Git Bash part`; `gbgate2` (`smoke-gate.sh` named twice in its part) expects
    `more than one Git Bash part`; `gbnewstep` expects `tests/smoke-new.sh runs in no Git Bash part`; `gbps`
    (`,smoke-slot.ps1` appended to the last part's list) expects `which is not a bash step`; `gborder` (two steps of
    one packed part swapped) expects `not in the order of the step list`;
  - new: `gblintcopy` (`test-lintcopy-output.sh` added to a packed part, in list order) expects
    `which the Git Bash job leaves out`; `gbalone` (a short step moved into the part of the first name on
    `gitbash_alone`, in list order) expects `shares its part`;
  - new, on an unchanged scratch copy, with `rules` called in a subshell that sets the list first (`rules` reads
    `gitbash_out` and `gitbash_alone` as shell variables, so a case can set them without copying the test):
    `gbout` (`gitbash_out` set to `smoke-nope.sh`) expects `which is not a bash step of tests/check.sh`; `gbalonenope`
    (`gitbash_alone` given the extra name `smoke-nope.sh`) expects
    `tests/smoke-nope.sh is to run alone, but it runs in no Git Bash part`.

  The PowerShell cases (`noguard` to `stepperm`) keep their expected texts. `tests/test-ci-job-times.sh` passes
  unchanged.
- Criterion 4, the cases: for each test file decision 4 changes, the implementer puts into "How verified" the
  `diff` of its `grep -E '^[[:space:]]*echo "== '` output before and after (empty), and the count of failure texts
  before and after, with none missing. The code reviewer checks the rewrites against the means of decision 4 and that
  no wait bound, expected text or platform branch changed.
- Criterion 3: **on the pull request's run**, by the maintainer before merging by hand. In two runs of the final commit
  (decision 2): each `Git Bash smoke part <k> of <N>` has a job summary whose `### tests/check.sh` section holds the
  line `Selection: --affected ran every --within step: <reason>.`, and a check step whose log ends with the line
  `SELECTED CHECKS PASSED (<k> of <M> steps; the full check has not run)`, the `<k>` adding up to 47, each `Wall time:`
  at most 14m00s and each job time at most 17m00s; `Git Bash smoke tests (Windows, not blocking)` is `success`; the
  chain is at most 17m00s. "How verified" gives both run ids, each part's numbers and the chain. After the merge, the
  push run on `main` runs every part with `--only` (`check: only ...`), a third full run.
- Criterion 5: `bash tests/check.sh` is green on the branch, and the implementer puts its last line and its `Times:`
  total into "How verified". On the pull request's run, `Lint (generic, JSON, skills, shell)`,
  `bash scripts smoke tests` (which still runs `test-lintcopy-output.sh`) and `PowerShell scripts smoke tests` are
  green. The code reviewer checks that `git diff origin/main --stat` lists no `.ps1` file, no file under `scripts/`, and only
  the files of "Files touched".

## Files touched

- `docs/specs/iteration-66-gitbash-job-time.md`: `## Measurements` filled (decision 1).
- `.github/workflows/ci.yml`: the job `smoke-gitbash` is replaced by the two jobs of decision 5, in the same place,
  with the lists of decision 5's rule (without `test-lintcopy-output.sh`, decision 3). Nothing else in the file
  changes.
- `tests/test-ci-parts.sh`: `gitbash_out`, `gitbash_alone`, rules 10a, 10b and 11, the cases and the header comment
  (decision 7, Tests).
- `tests/lint.sh`: the `if: always()` condition of line 1566 and its comment (decision 7).
- The bash tests decision 4 rewrites, each named in `## Measurements`. These are expected among `tests/smoke-slot.sh`,
  `tests/smoke-status.sh`, `tests/smoke-check.sh`, `tests/test-guard-rules.sh`, `tests/smoke-release.sh` and
  `tests/smoke-validate.sh`. A rewrite of `tests/lint.sh` follows decision 4's lint-copy rule only. None, when the split
  alone meets the budget.
- No file under `scripts/` (decision 6).
- `README.md`, under `## Developing nightmill`: "a further job, `Git Bash smoke tests (Windows, not blocking)`, runs
  every bash test step in Git Bash on a Windows runner (decision record 0004, step 1); it is not a required check, and a
  failing step there shows in its summary without failing the job;" becomes "the bash test steps but
  `test-lintcopy-output.sh` (the bash job runs that one) run in Git Bash in <N> parts on <N> Windows runners at once
  (decision record 0004, step 1), the longest steps alone in theirs, and a further job,
  `Git Bash smoke tests (Windows, not blocking)`, fails unless every part succeeded; it is not a required check, and a
  failing step shows in its part's summary without failing the part;", with `<N>` written as a word, as "four parts"
  is.
- `CHANGELOG.md`, one bullet under `Unreleased`:

  ```
  - Iteration 66 (#382): the Git Bash CI job runs in parts on several Windows runners at once, the longest steps alone
    in theirs, and a final job, Git Bash smoke tests (Windows, not blocking), fails unless every part succeeded; the
    whole job finishes within 17 minutes, the time a required check is allowed. The slowest bash steps are measured
    section by section in Git Bash on Windows (the spec holds the numbers); their costliest sections start fewer
    processes with the same cases, and test-lintcopy-output.sh, which nests whole runs of three other steps, leaves
    the Git Bash job (the Ubuntu bash job still runs it). No config key.
  ```

  When decision 4 rewrote no section, "their costliest sections start fewer processes with the same cases, and" is
  left out. If the iteration ends `partial` (decision 5), "the whole job finishes within 17 minutes, the time a
  required check is allowed" becomes "the whole job finishes sooner", and "The rest follows in #<new story>." is added.

Not touched: `tests/check.sh` (its step list, marks and map), the other jobs of `ci.yml`, `tests/test-ci-job-times.sh`,
every `.ps1` file, `tests/check.ps1`, `.claude/nightmill.json`, the schema, every skill, agent and hook,
`docs/decisions/`, and the spec of iteration 65 (decision 8).

## Risks

- **The budget is not reached.** By the Facts, six steps took more than 12 minutes each with 3 others beside them, and
  a part cannot end before its longest step. Whether `smoke-slot.sh` (25m43s) runs under 14 minutes alone on a runner
  is not known. A part of its own may not be enough, and fewer processes may not cut that much. Decision 5 then ends
  the iteration as `partial`, with the split delivered and a measured basis for the next story.
- **More runners, more queueing.** About 9 Git Bash parts make one run about 17 jobs at once. Two pull requests at once
  exceed the 20 an account runs at once (Facts, not read here), and a part that waits for a runner lengthens the chain.
  The cap of 10 parts bounds one run. Decision 2 counts the wait, so a run that queues shows it.
- **A rewrite changes what a case tests.** Decision 4 allows only listed means, keeps headers, texts and cases, and the
  Ubuntu job runs the same files. A rewrite that gets a case wrong goes red there.
- **`test-lintcopy-output.sh` counts what `smoke-check.sh` starts** (#293, #340). A rewrite of `smoke-check.sh` can
  change those counts. It stays green only when the counted calls stay at their bound. The Ubuntu job runs it.
- **A shared fixture leaks between cases.** A fixture repository built once and copied per case must be copied, never
  used in place. A case that changes the fixture changes only its copy.
- **Local times are not CI times.** The local alone times choose the sections, and the CI times of a run with 4 steps
  at a time choose the parts. Only the CI runs of decision 2 decide whether the budget is met.
- **Runner spread.** Windows runners differ from run to run. The 3-minute margin and the second run of decision 2 bound
  that. A later slowdown shows in each part's summary on every push run.
- **The parts go stale.** A step that gets slower later is not moved by any test; `gitbash_alone` only keeps the alone
  steps alone. Each part's summary shows its time, as the PowerShell parts' do.

## Size estimate

`L` is likely. Fixed parts: `ci.yml` about 40 lines (two jobs, a pair of lines per part), `tests/test-ci-parts.sh`
about 130 (rules 10a, 10b and 11 about 80, the cases about 40, the header 10), `tests/lint.sh` 2, `## Measurements`
about 60 to 80, README 6, CHANGELOG 6, so about 245 to 265: `M` when the split alone meets the budget. The rewrites of
decision 4 are not known before decision 1. At 30 to 60 changed lines per rewritten section and 0 to 8 sections, they
add 0 to 480, so about 245 to 745 in all.

## Not done

- Making the jobs blocking or required, renaming them for the ruleset, changing the parts' timeout from 360, or
  changing the ruleset (#363, decision 8).
- Editing iteration 65's spec (decision 8 says what its revision changes).
- More than 10 parts, a part option or a group field in `tests/check.sh` (iteration 55 decision 3), or changing
  `verification.checkJobs` or `--jobs` for the parts.
- A job table (`tests/ci-jobs-summary.sh`) in the Git Bash final job, or any job-level `permissions:` for it.
- Leaving any step but `test-lintcopy-output.sh` off the Git Bash list (no entry of `gitbash_out` beyond it unless
  decision 3 names it), or a platform branch in a test.
- Removing, merging or weakening a case, lowering a wait bound, or changing an expected text.
- Any change to a `.ps1` file (#365 removes them; they are frozen once #363 merges), or any change to a file under
  `scripts/` (decision 6: a slow section whose cost sits in a script goes to the follow-up story).
- Fixing a bash step that fails in Git Bash (it becomes a bug).
- A permanent per-section timer in the check or a lint on test times (the epic's time budget is a story of its own).
- `# Time: ` notes for the rewritten steps (iteration 62's notes stay as they are).
- The map rule for `tests/fixtures/` (#379, done).

## Left

1. **Iteration 65's spec must be revised before #363's `/next`.** Its decision 7 pins one job, one run step, one
   `continue-on-error` and 48 steps; with this iteration the Git Bash check is a part job and a final job over 47
   steps. Decision 8 lists what the revision changes. This spec does not edit iteration 65's file, so the revision is a
   `/spec` run on #363 (or the maintainer's edit) once this spec is approved.
2. **The runner limits are from documentation, not read here.** The cap of 10 parts rests on 20 jobs at once and 4
   processors per Windows runner (Facts). If the account's limits differ, the cap is the number to change, in this
   spec, before `/next`.
