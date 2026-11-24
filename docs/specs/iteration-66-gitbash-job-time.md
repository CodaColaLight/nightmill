# Iteration 66: the Git Bash CI job runs its full step list within 17 minutes

Status: draft, awaiting approval (#382)

Story #382, epic #337 (fast verification loop). It supersedes bug #376. Iteration 64 (#361) added the job
`smoke-gitbash`, which runs every bash test step in Git Bash on a Windows runner. Iteration 65 (#363) is to make it a
required check, but only after a full run is green and takes at most 17 minutes (iteration 64 decision 5, iteration 65
decision 7). A full run takes about an hour today. This iteration measures where the time of the slowest steps goes.
The measurement is its first deliverable, and the implementer writes it into this spec (`## Measurements`). The
iteration then cuts the time by fixed rules, in a fixed order: the nested step `test-lintcopy-output.sh` comes off the
job's list (decision 3); the measured sections that start many processes are rewritten to start fewer, with the same
cases (decision 4); and the work stops when the budget of decision 2 is met, or as `partial` when it is not
(decision 5). Changes `docs/specs/iteration-66-gitbash-job-time.md` (the measurements), `.github/workflows/ci.yml` (the
Git Bash list), `tests/test-ci-parts.sh` (rule 11), the bash tests that decision 4 rewrites (from
`tests/smoke-slot.sh`, `tests/smoke-status.sh`, `tests/smoke-check.sh`, `tests/test-guard-rules.sh`,
`tests/smoke-release.sh`, `tests/smoke-validate.sh` and any other step decision 1 measures), `README.md` and
`CHANGELOG.md`.

**Never auto-merged.** The pull request changes `.github/workflows/ci.yml`, so the implementer opens it without `--auto`
and the maintainer merges it by hand, as in iterations 60 and 64.

## Story trigger and manual check

**Not a story trigger.** *Status flow*: no status, no board call and no decision record changes. *Config key*: none is
added, renamed or removed. `verification.checkJobs` and `verification.platform` keep their values and meaning, and the
job's step list belongs to this repository's CI, not to a project. *Slot marker*: no script that writes a marker
changes its behaviour (decision 6). **Compatible** holds: a project reads nothing that changes.

**The manual check does not apply.** `verification.manualCheckPaths` is `skills`, `agents`, `hooks`, and no file under
them changes. In its place the maintainer looks at the pull request's own CI runs (Tests, "On the pull request's run").

**Shells.** The changes are to bash tests and to CI. No `.ps1` file changes, so no PowerShell script changes its
behaviour (out of scope) and the PowerShell tests run as before. A script under `scripts/` changes only under decision
6's rule, which keeps its behaviour, so its PowerShell twin needs no change and **Both shells** still holds. The smoke
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
  Whether a step is faster when nothing runs beside it is not known.
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
- **What the specs already fix.** Iteration 64 decision 3: the job runs every bash step and has no skip list, "a skip
  list would guess at what nobody has measured". Iteration 64 decision 4: the iteration that makes the job required
  splits it into parts first when it is over the budget. Iteration 65 decision 7 (draft): the job becomes
  `Git Bash scripts smoke tests` and lands only when a full run is green, its summary ends
  `SELECTED CHECKS PASSED (48 of <M> steps; ...)`, and its wall time is at most 17 minutes. Iteration 62: a profiled
  step says where its time goes in a `# Time: ` note, and the seconds go into the pull request.
- **The test files stay generic.** No bash test branches on the platform, so Ubuntu and Git Bash run the same cases.

## Measurements

Filled in by the implementer (decision 1) before any test changes, and completed in the same pull request. It holds
three tables and one paragraph.

**Cost of one process** (local Git Bash, 200 runs each, total and per run):

| What | 200 runs | Per run |
|---|---|---|
| `/usr/bin/true` | | |
| `x=$(printf y)` (a subshell) | | |
| `git --version` | | |
| `git init -q` plus one `git commit` in a fresh folder | | |

**Sections** (one block of rows per measured step):

| Step | Section (`== ` header) | Alone, local Git Bash | Share of the step | What it starts (by reading) | Why it costs (process-bound, lint, wait, other) | Action (decision 4) |
|---|---|---|---|---|---|---|

**Steps in CI** (the Git Bash job's `Times:` block, before and after, and the Ubuntu job's time for the same step):

| Step | Git Bash before (45235773214) | Git Bash after (final run) | Ubuntu (45235773214) |
|---|---|---|---|

**Summary paragraph**: which sections cost the most, and why, in at most eight sentences.

## Decisions

**1. The measurement comes first, and goes into this spec.** The issue asks this spec to hold the measurement and to
choose how the time is cut. A spec is written before the work, and no per-section timing exists yet, so nothing is
invented here. The measurement is the implementation's first deliverable. The choice is made now, as rules (decisions
2 to 5) that the implementer applies to what it measures, with fixed numbers. The rules do not depend on the timings.
The timings only decide which sections decision 4 rewrites and when decision 5 stops the work.

- *What is measured*: the seven steps of Facts, and every other bash step whose time in the `Times:` block of the Git
  Bash job of run 45235773214 is 5m00s or more (read with `gh run view 45235773214 --log`, read only).
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
- The implementer commits the filled tables with the first change of decision 4, so the reviewer reads each rewrite
  against the row that chose it. The "after" column and the summary paragraph are completed from the final run.

**2. The budget.** The time a required check is allowed is **17 minutes**: iteration 64 decision 5, the 16m59s of the
PowerShell chain it is to replace. The iteration has met it when the final commit of the pull request has two full runs
of the Git Bash job: the run its push starts, and one re-run of that job. Every bash step of the job's list runs
(`$CHECK_SELECT` takes the fallback, because the pull request changes `ci.yml`). In each of the two runs:

- the check step passes, with the summary ending `SELECTED CHECKS PASSED (<k> of <M> steps; the full check has not run)`,
  where `<k>` is the length of the job's list;
- the check's `Wall time:` in the job's `### tests/check.sh` section is at most **14m00s**;
- the job's own time in the run's job list, from start to completion, is at most **17m00s**.

The 14m00s leaves 3 minutes for the runner's start, the full-history checkout, and the spread between two runs of the
same commit. A run that only just meets 17 minutes would make a required check fail by chance. `continue-on-error`
stays and the timeout stays 360. Making the job blocking, and its timeout, belong to iteration 65 decision 7.

**3. A smaller list: `test-lintcopy-output.sh` comes off the Git Bash job.** The job's list becomes every `add bash`
step of `tests/check.sh` except the steps on the list `gitbash_out`, which is exactly `test-lintcopy-output.sh`. That
makes 47 steps, in list order.

- *Why this step*: it alone took 34m40s, twice the budget. Half of it is whole runs of `smoke-status.sh`,
  `smoke-release.sh` and `smoke-check.sh` on copies, and the same job runs each of them as a step of its own. No cut
  of its own sections brings it under 17 minutes unless those three steps get faster too.
- *What coverage it gives up*: the regression checks it holds, run in Git Bash on Windows. They are #217 (a smoke test
  prints the lint's `FAIL:` lines when the lint fails on its copy), #280 (`test-spec-template.sh` starts no nested
  lint), #293 (`smoke-check.sh`'s lint copies skip the CI-parts cases) and #340 (no agreement cases on the lint copies).
  They check what the bash tests themselves print and start, not a script under `scripts/`.
- *Where it is tested now*: in the Ubuntu job `bash scripts smoke tests`, which keeps it in its `--only` list. That job
  runs it on every push to `main` and on every pull request that changes a shared path. Locally,
  `bash tests/check.sh --only test-lintcopy-output.sh` runs it. Its PowerShell twin stays in its part.
- *No other step comes off the list.* Each other step starts at least one script, hook or check run that only it
  starts. A further step comes off only if the maintainer adds it to this decision (Left).
- `tests/test-ci-parts.sh` rule 11 learns the list (Tests). `tests/check.sh`, the slow mark and the Ubuntu job's list
  do not change. Iteration 62 decision 7 (the `--only` lists of `smoke-bash` and the parts name every step) still
  holds. It does not cover the Git Bash job.

**4. Fewer processes, with the same cases.** For every measured section of 60 s or more alone, taken in order of time
(largest first), the implementer does exactly one of these, and the section's row in `## Measurements` says which:

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

**5. When to stop.** After each round of rewrites the implementer pushes, and the pull request's run is a full run
(decision 2).

- **Done**: decision 2 holds on the final commit. The implementer fills the "after" column and the summary paragraph,
  and no further section is rewritten.
- **Partial**: every measured section of 60 s or more has its action (rewrite or keep), and decision 2 still fails. The
  implementer then does not split the job, does not take more steps off the list, and does not lower a check. It
  reports `partial` with criterion 3 unmet and gives the final run's id, its `Wall time:`, the job's time and the five
  slowest steps. The rest is filed with `/story` as a new story under #337, linked to #382, following the workflow's
  rule for a story only partly done. That story chooses between a split into parts (iteration 64 decision 4) and
  further cuts, and the maintainer decides (Left). The rewrites done so far stay in the pull request, since they keep
  every case.
- A step that fails in Git Bash is not a time problem. The implementer lists it with its first `FAIL` line, does not
  fix it here, and it becomes a bug of its own (iteration 64 decision 3). Decision 2 cannot hold while it fails.

**6. Scripts under `scripts/`.** The cuts are made in the tests. A file under `scripts/` changes only when its row in
`## Measurements` shows that the script's own process starts cost the section 60 s or more. Even then it changes only
so that, for every input of its smoke tests, its standard output, standard error, exit code and the files it writes
(markers included) stay byte for byte the same. Its smoke tests in both shells then pass unchanged, and its `.ps1`
twin does not change. A change that cannot keep that is not made here. Its row says "keep (needs a behaviour change)".

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The time of each section of the slowest bash steps is measured in Git Bash on Windows, and the result (which sections cost the most, and why) is written in the spec | Decision 1; `## Measurements` (filled by the implementer) |
| 2 | The spec chooses how the time is cut (cheaper scenarios, fewer processes, a split of steps, or a smaller step list for the job) and says what coverage each choice gives up | Decisions 3 (a smaller list, its coverage given up), 4 (fewer processes and lighter lint copies, no coverage given up) and 5 (no split in this iteration); decision 6 |
| 3 | A full run of the Git Bash job, with every step it has to run, finishes within the time a required check is allowed | Decision 2 (17m00s, 14m00s, two runs); decision 3 (the list it has to run); decision 5 (done or partial) |
| 4 | No scenario is dropped without the spec saying which behaviour it covered and where that is tested now | Decision 3 (`test-lintcopy-output.sh`: what it covers, where it runs now); decision 4 (no case dropped, and how that is checked) |
| 5 | The check stays green on Linux and in the PowerShell jobs | Decisions 4 and 6 (same cases, no `.ps1` change); Tests (criterion 5) |

## Tests

- Criterion 1: no test reads the measurements. The code reviewer checks that `## Measurements` has every table filled
  for every step decision 1 names, that each section of 60 s or more has an action, and that the summary paragraph
  names the costliest sections and their cause. The implementer pastes the raw timestamper output of each measured step
  into "How verified" (collapsed), so the reviewer can check the tables against it.
- Criterion 2 and 4, the list: **`tests/test-ci-parts.sh`** rule 11 gets the list `gitbash_out` (one name per line,
  exactly `test-lintcopy-output.sh`). A bash step that is on `gitbash_out` is expected in no Git Bash list, and every
  other bash step as today. New texts, each with the prefix `FAIL: .github/workflows/ci.yml: `:
  `the Git Bash list names tests/<x>, which the Git Bash job leaves out (docs/specs/iteration-66-gitbash-job-time.md, decision 3)`
  for a left-out step that is on the list, and
  `the Git Bash job leaves out tests/<x>, which is not a bash step of tests/check.sh` for a name on `gitbash_out` that
  is not a bash step. Rule 11 passes on the checkout. New cases, each on a scratch copy changed once:
  - `test-lintcopy-output.sh,` put back after `smoke-check.sh,` in the Git Bash list: `which the Git Bash job leaves out`;
  - `gitbash_out` given `smoke-nope.sh`: `which is not a bash step of tests/check.sh`.

  The existing cases (`gbnoguard`, `gbgate2`, `gbnewstep` and the rest) keep their expected text. The header comment's
  sentence on rule 11 says "every `add bash` step but those the Git Bash job leaves out (iteration 66)".
- Criterion 4, the cases: for each test file decision 4 changes, the implementer puts into "How verified" the
  `diff` of its `grep -E '^[[:space:]]*echo "== '` output before and after (empty), and the count of failure texts
  before and after, with none missing. The code reviewer checks the rewrites against the means of decision 4 and that
  no wait bound, expected text or platform branch changed.
- Criterion 3: **on the pull request's run**, by the maintainer before merging by hand. The job
  `Git Bash smoke tests (Windows, not blocking)` has, in two runs of the final commit, a summary that begins with
  `Selection: --affected ran every --within step: .github/workflows/ci.yml is shared by many steps.`, lists 47 steps,
  and ends `SELECTED CHECKS PASSED (47 of <M> steps; the full check has not run)`, with `Wall time:` at most 14m00s
  and the job's time at most 17m00s. "How verified" gives both run ids and the numbers. After the merge, the push run on
  `main` runs the job with `--only` (`check: only ...`), a third full run.
- Criterion 5: `bash tests/check.sh` is green on the branch, and the implementer puts its last line and its `Times:`
  total into "How verified". On the pull request's run, `Lint (generic, JSON, skills, shell)`,
  `bash scripts smoke tests` (which still runs `test-lintcopy-output.sh`) and `PowerShell scripts smoke tests` are
  green. The code reviewer checks that `git diff origin/main --stat` lists no `.ps1` file and only the files of "Files
  touched".

## Files touched

- `docs/specs/iteration-66-gitbash-job-time.md`: `## Measurements` filled (decision 1).
- `.github/workflows/ci.yml`: job `smoke-gitbash`. `test-lintcopy-output.sh,` comes out of its list (decision 3), and
  its comment's first line names iteration 66 (`# The bash steps in Git Bash on a Windows runner (iteration 64; decision
  record 0004, migration step 1), test-lintcopy-output.sh left out (iteration 66).`, wrapped at 120 columns). Nothing
  else in the file changes.
- `tests/test-ci-parts.sh`: `gitbash_out`, rule 11, the two cases and the header comment (Tests).
- The bash tests decision 4 rewrites, each named in `## Measurements`. These are expected among `tests/smoke-slot.sh`,
  `tests/smoke-status.sh`, `tests/smoke-check.sh`, `tests/test-guard-rules.sh`, `tests/smoke-release.sh` and
  `tests/smoke-validate.sh`. A rewrite of `tests/lint.sh` follows decision 4's lint-copy rule only.
- A file under `scripts/` only under decision 6, its `.ps1` twin never.
- `README.md`, under `## Developing nightmill`: "runs every bash test step in Git Bash on a Windows runner (decision
  record 0004, step 1)" becomes "runs every bash test step but `test-lintcopy-output.sh` in Git Bash on a Windows runner
  (decision record 0004, step 1; the bash job runs that one)".
- `CHANGELOG.md`, one bullet under `Unreleased`:

  ```
  - Iteration 66 (#382): the Git Bash CI job runs its full step list within 17 minutes, the time a required check is
    allowed. The slowest bash steps are measured section by section in Git Bash on Windows (the spec holds the
    numbers); their costliest sections start fewer processes with the same cases, and test-lintcopy-output.sh, which
    nests whole runs of three other steps, leaves the Git Bash job (the Ubuntu bash job still runs it). No config key.
  ```

  If the iteration ends `partial` (decision 5), "runs its full step list within 17 minutes, the time a required check
  is allowed" becomes "is faster", and "The rest follows in #<new story>." is added.

Not touched: `tests/check.sh` (its step list, marks and map), the other jobs of `ci.yml`, every `.ps1` file,
`tests/check.ps1`, `.claude/nightmill.json`, the schema, every skill, agent and hook, `docs/decisions/`.

## Risks

- **The budget is not reached.** By the Facts, the seven steps took about twice the step-minutes 17 minutes allows,
  before the 41 others. Fewer processes may not cut that much. Decision 5 then ends the iteration as `partial`, with a
  measured basis for a split. Left item 1 lets the maintainer choose the split now.
- **A rewrite changes what a case tests.** Decision 4 allows only listed means, keeps headers, texts and cases, and the
  Ubuntu job runs the same files. A rewrite that gets a case wrong goes red there.
- **`test-lintcopy-output.sh` counts what `smoke-check.sh` starts** (#293, #340). A rewrite of `smoke-check.sh` can
  change those counts. It stays green only when the counted calls stay at their bound. The Ubuntu job runs it.
- **A shared fixture leaks between cases.** A fixture repository built once and copied per case must be copied, never
  used in place. A case that changes the fixture changes only its copy.
- **Local times are not CI times.** The local alone times choose the sections. Only the CI runs of decision 2 decide
  whether the budget is met.
- **Runner spread.** Windows runners differ from run to run. The 3-minute margin and the second run of decision 2 bound
  that. A later slowdown shows in the summary of every push run.

## Size estimate

`L` is likely, but it depends on the measurement. Fixed parts: `ci.yml` about 3 lines, `tests/test-ci-parts.sh` about
30, `## Measurements` about 40 to 60, README 2, CHANGELOG 5, so about 85. The rewrites of decision 4 are not known
before decision 1. At 30 to 60 changed lines per rewritten section and 5 to 8 sections, they add 150 to 480, so
about 235 to 565 in all.

## Not done

- Making the job blocking or required, renaming it, changing its timeout, or changing the ruleset (#363).
- Splitting the job into parts, or changing `verification.checkJobs` or `--jobs` for it (decision 5, Left).
- Leaving any step but `test-lintcopy-output.sh` off the Git Bash list, a skip list, or a platform branch in a test.
- Removing, merging or weakening a case, lowering a wait bound, or changing an expected text.
- Any change to a `.ps1` file (#365 removes them; they are frozen once #363 merges), or a behaviour change of a script
  under `scripts/`.
- Fixing a bash step that fails in Git Bash (it becomes a bug).
- A permanent per-section timer in the check or a lint on test times (the epic's time budget is a story of its own).
- `# Time: ` notes for the rewritten steps (iteration 62's notes stay as they are).
- The map rule for `tests/fixtures/` (#379, done).

## Left

1. **Split now, or `partial` first (needs the maintainer).** By the Facts, reaching 17 minutes with one job means
   cutting about half of the step-minutes. Iteration 64 decision 4 foresaw a split into parts when the job is over the
   budget. This spec does not split. A split changes what iteration 65 decision 7 pins (one job, one run step, one name
   to require), and it should be chosen on measured step times. Approving the spec as written accepts decision 5's
   `partial` outcome. The maintainer may instead add a split as a stage after decision 4, which would also amend
   iteration 65 decision 7.
2. **Iteration 65's "48".** Iteration 65 decision 7 (draft) expects the job's summary to end
   `SELECTED CHECKS PASSED (48 of <M> steps; ...)`. With decision 3 the job runs 47 steps. This spec does not edit
   iteration 65. Its text needs "47", or "every step of the job's list", before its `/next`.
3. **The spec holds numbers its implementer writes.** The issue asks the spec to hold the measurement, so decision 1
   has the implementer fill `## Measurements` in the implementation's pull request. The maintainer approves the rules
   now and reads the numbers in the pull request. If the maintainer prefers, the measurement can be a separate step
   before approval: a measurement-only pull request, then this spec revised with its numbers.
4. **Further steps off the list.** Decision 3 leaves out only `test-lintcopy-output.sh`. If the measurement shows
   another step that tests only repository text (for example the text sections of `test-guard-rules.sh`), the
   maintainer may add it to decision 3, with its coverage written there.
