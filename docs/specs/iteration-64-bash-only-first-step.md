# Iteration 64: record 0004 is accepted, and Windows CI runs the bash tests in Git Bash

Status: delivered in iteration 64 (PR #367)

Story #361, epic #337 (fast verification loop). This is the first pull request of the move to bash only, and it
covers only (a) the acceptance of decision record 0004 with the option **Bash only, with Git Bash on Windows**, the
maintainer's decision on #361, and (b) step 1 of the record's migration outline: a new CI job runs every bash test step
of `tests/check.sh` in Git Bash on a Windows runner. The four PowerShell parts, the final job
`PowerShell scripts smoke tests`, every script, every test and every skill stay as they are. Only CI grows. Steps 2 to 4
of the outline are later iterations (Left). Changes `docs/decisions/0004-scripts-in-one-language.md`,
`.github/workflows/ci.yml`, `tests/lint.sh`, `tests/test-ci-parts.sh`, `README.md` and `CHANGELOG.md`.

**Never auto-merged.** The pull request changes `.github/workflows/ci.yml` (a path under `.github/`) and accepts a
decision record, so the implementer opens it without `--auto` and the maintainer merges it by hand (Tests, "On the pull
request's run").

## Story trigger and manual check

**Not a story trigger.** *Status flow*: no status, no board call, no change to who sets what; record 0004 changes the
**Both shells** invariant, not the flow, and the invariant text itself is not changed here (step 2). *Config key*: none
is added, renamed or removed, and `verification.platform` keeps its meaning (step 2 changes it); the new job is this
repository's CI, not a project value. *Slot marker*: no script changes. **Compatible** holds: nothing a project reads
changes.

**The manual check does not apply**: nothing under `skills`, `agents` or `hooks` changes. The maintainer's look at the
pull request's own CI run stands in for it (Tests).

**Both shells** (still in force in this iteration): no script in `scripts/` changes, no smoke test changes.
`tests/test-ci-parts.sh` is a bash-only test of this repository's CI, as since iteration 55.

## Facts this rests on

Read on `main` at 014601f (iteration 63 merged) on 2026-11-22; no network call was made, so the ruleset and the CI
times are taken from the record and from iteration 60's Facts, not read again.

- **Record 0004** has `Status: proposed (#342)` on line 5, the sections `## Question` to `## Migration outline`, and no
  `## Decision` section. Iteration 61 decision 4 says how it is accepted: `Status: accepted <date>` and a
  `## Decision` section (the option, the date, the follow-up stories). Its table names four Git Bash problems, all
  closed with a workaround and a regression test: #300 (`MSYS_NO_PATHCONV=1` in `scripts/lib/baseconfig.sh`,
  `tests/test-baseconfig-pathconv.sh`), #302 (the same in the skills' injected line), #303 (`git` outside `/usr/bin`,
  `tests/test-restricted-path-git.sh`), #304 (GNU tar and `C:`, in `smoke-slot.ps1`). It says the Windows Git Bash
  job is not measured and is likely the slowest job (iteration 56: 2 to 3 hours for the local check in Git Bash).
  Measured CI (run 44952977845): the bash job 5 min 20 s; the four PowerShell parts 44 min 51 s of runner time; 16 min
  59 s from the first job's start to the end of `PowerShell scripts smoke tests`.
- **`ci.yml` today.** `CHECK_SELECT` (iteration 60) is `--affected --within` on a pull request and `--only` on every
  other event. Jobs: `lint` (required), `smoke-bash` (required `bash scripts smoke tests`, Ubuntu, 22 min, full-history
  checkout, two check lines: `smoke-json.sh`, then jq hidden, then the other 47 bash steps), `smoke-powershell-part`
  (four Windows parts, `shell: bash`, `bash tests/check.sh --powershell powershell ... $CHECK_SELECT ${{ matrix.only }}`,
  full history), `smoke-powershell` (required `PowerShell scripts smoke tests`, Ubuntu, `needs` the parts,
  `if: always()`, the only job-level `permissions:`, the job-times step), `validate` (job-level `continue-on-error`).
- **`tests/check.sh`.** The step list has `add lint lint`, 48 `add bash` steps (`smoke-json.sh` to
  `test-slot-low-defects.sh`), 27 `add ps` steps, then two `claude` steps. `--only` and `--affected --within` never apply
  `verification.platform`; a change under `.github/workflows/` is `shared`, so a pull request that changes CI runs
  every step of every list (`--only <list>`). A selective run leaves out `slow` steps. `--summary` appends the wall time
  and the five slowest steps.
- **`verification.platform`** (iteration 56): `windows` skips the bash steps and `unix` the ps steps in a full or quick
  run; this repository sets `windows`, so its local full check does not run the bash family. CI is not affected.
- **The lint pins `ci.yml`.** `== the check runs every smoke script`: exactly two lines in the whole file match
  `run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT ` (the first `smoke-json.sh` before
  `Hide jq`, the second every other bash step in list order); `--only`/`--affected` only in the env line; no smoke
  file run outside the check; the three required names once each, and no other job name that begins with one.
  `== CI selects the steps a pull request affects`: no job-level `if:` but the final job's `if: always()`, no step
  `if:` in `lint`, `smoke-bash`, `smoke-powershell-part`, `fetch-depth: 0` in `smoke-bash` and the parts.
  `tests/test-ci-parts.sh` (started once by the lint, rules only in the lint copies of `smoke-check.*`): every ps step
  in exactly one part, in list order, the final job, the job-level permissions only in `smoke-powershell`.
  `== CI runs with least privilege`: a timeout from 1 to 360 on every job, the `Required check` comment exactly 3 times.
- **The watch of `/next` and `/fix`** (`skills/workflow/SKILL.md`) counts every check, required or not: `fail` and
  `cancel` are red and start a check fix round; a check still pending when the time is out ends the watch without harm,
  and auto-merge waits only for the required checks.
- **Line endings**: `.gitattributes` has `* text=auto eol=lf`, so the Windows checkout keeps LF in the bash files.

## Decisions

**1. Record 0004 is accepted, with an edit of two places and nothing else.**

- Line 5 `Status: proposed (#342)` becomes `Status: accepted <date> (#361)`. `<date>` is the day the maintainer filed
  #361 (`gh issue view 361 --json createdAt`, read only), the decision.
- A section is appended after `## Migration outline`, exactly:

  ```
  ## Decision

  Accepted on <date> by the maintainer in story #361: **Bash only, with Git Bash on Windows**, the option this record
  recommends. Why: nightmill is to be developed and tested in one shell, with no second PowerShell track to keep in step;
  bash is already needed on Windows for the hooks, the warm-up commands, the skills' injected config and the check, so
  Git for Windows is no new requirement for a Windows project. The migration takes the four steps above, in that order,
  each leaving the plugin working, each one story under epic #337: step 1 is iteration 64 (#361); the follow-up
  stories are #363 (step 2), #364 (step 3) and #365 (step 4).
  ```

Every other line of the record stays as it is, the `Date:` line, the facts and the sentence "This is a proposal; the
maintainer decides." included: they record what was proposed, and on which commit.

**2. One new job, `smoke-gitbash`, after `smoke-powershell` and before `validate`**, written exactly so, with the 48
bash steps of the step list in list order in place of `<list>`:

```yaml
  smoke-gitbash:
    # The bash steps in Git Bash on a Windows runner (iteration 64; decision record 0004, migration step 1). Not a
    # required check, and its check step does not fail the job, until a later iteration makes it required.
    name: Git Bash smoke tests (Windows, not blocking)
    runs-on: windows-latest
    timeout-minutes: 360
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
      - shell: bash
        continue-on-error: true
        run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT <list>
```

- One check line with every bash step, `smoke-json.sh` included, and jq not hidden: that the scripts need no jq is
  already pinned on Ubuntu; here `smoke-json.sh` cross-checks against jq when the runner has it.
- `$CHECK_SELECT` as in every smoke job: on a pull request only the selected bash steps run; a push to `main`, and a
  pull request that changes a shared path (this one included), runs all 48. `verification.platform` is never read
  (`--only` and `--within` ignore it), so this repository's `windows` does not skip them.
- No `if:`, no `needs`, no job-level `permissions:`, no `Required check` comment; the name begins with no required
  name. The PowerShell parts and the final job do not wait for it.
- Its place after `smoke-powershell` keeps the sed ranges of the existing lint cases (for example `cidepth`, from
  `  smoke-bash:` to `  smoke-powershell-part:`) on the jobs they mean.

**3. It reports and does not block: every bash step runs, none is skipped on Windows.** The four known Git Bash
problems are closed with workarounds (Facts), so no step is known to fail there, and a skip list would guess at what
nobody has measured. So the check step carries `continue-on-error: true` on the step, not on the job: a failing bash
step shows in the job's log and in its summary (`Wall time: ... FAILED`), and the job's result stays `success`, so the
watch of `/next` and `/fix`, which counts every check, does not start a check fix round for a Windows failure outside
the change. A failure found is not fixed in this pull request: the implementer lists each failing step with its first
`FAIL` line under "How verified", and each is a bug of its own for the maintainer to file.

**4. Not required in this iteration; the ruleset is not changed.** The job is unmeasured, and a required job that fails
or runs for hours would hold every pull request. The three required names, their comments and the final job stay. What
the maintainer does after the first green run (decision 5): reads its numbers; when every step passed and the wall time
is within the budget, a later iteration removes `continue-on-error`, gives the job a name to require (with the
`Required check` comment and the lint's list of required names), and the maintainer adds that name to the ruleset by
hand; when it is over the budget, that iteration first splits the job into parts by the measured step times, as
iteration 55 did for PowerShell. That iteration is not specified here (Left).

**5. The time budget, and how the first run measures it.** The budget for a full run of the job is **17 minutes** of wall
time: the 16 min 59 s of the PowerShell chain it is to replace (record, Facts), so that requiring it later does not
lengthen a pull request's wait. This iteration does not have to meet it; it measures it. This pull request changes
`ci.yml`, a shared path, so its own run runs all 48 steps: the first full measurement. The implementer puts into "How
verified": the job's wall time (the run's job list), its `### tests/check.sh` section (the `Wall time:` line and the five
slowest steps), the failing steps if any (decision 3), and the run's link. `timeout-minutes` is 360 (the maximum the
lint allows) only for that measurement; in the same pull request, before the merge, the implementer sets it to 3 times
the measured wall time rounded up to whole minutes, at most 360 (iteration 38 decision 2, as iteration 55 did), which
runs the job once more. When the job is cancelled at 360 minutes, the implementer reports `partial` with the steps that
finished and their times, and the maintainer decides. Slower than the budget is not a failure of this iteration: it is
recorded and decides the parts of decision 4.

**6. The lint learns the job.**

- `== the check runs every smoke script`: the two-line rule for the bash check line reads only the lines of the job
  `smoke-bash` (from `  smoke-bash:` to the next line that starts with two spaces and a letter), not the whole file.
  Its texts do not change.
- `tests/test-ci-parts.sh` gains the rules of the job `smoke-gitbash` (no new process in the lint, bug #270; the
  lint copies of `smoke-check.*` check them through `NIGHTMILL_CI_PARTS_RULES_ONLY=1` as today), each printing
  `FAIL: .github/workflows/ci.yml: ...`:
  - **Rule 10**: the job block exists; it has the job keys `name: Git Bash smoke tests (Windows, not blocking)` and
    `runs-on: windows-latest`, a `fetch-depth: 0`, no line `if:` at any indent, no line `needs:`, exactly one run step (every `run:` and
    `- run:` line counts, as rule 2 does since bug #296), and that run step's line is
    `run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT <list>` in a step with the keys
    `shell: bash` and `continue-on-error: true`. Else `the Git Bash job is malformed (<what>)`.
  - **Rule 11**: the list holds every `add bash` step of the step list exactly once, nothing else, in list order. Else
    `tests/<x> runs in no Git Bash list`, `tests/<x> is named more than once in the Git Bash list`,
    `the Git Bash list names tests/<x>, which is not a bash step of tests/check.sh`, or
    `the Git Bash list is not in the order of the step list`.
  - Rule 8 (permissions) is unchanged and covers the new job. The file's header comment names rules 10 and 11; its
    last line stays `OK: the PowerShell parts`.

**7. Every step of the move leaves the check green; for this step**: no script, test step, skill or config changes, so
`bash tests/check.sh` passes as before (with this repository's `windows`, the lint, the PowerShell steps and the
`claude` steps), and the three required jobs run and report as today.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | Decision record 0004 is accepted with the option "bash only, with Git Bash on Windows": its status line and a decision section say so | Decision 1 |
| 2 | Windows CI runs the bash tests in Git Bash before any PowerShell test is removed, and the required checks of `main` still report on every pull request | Decisions 2, 5 and 6 |
| 3 | The new Windows job does not block a merge until it has run green and been measured, and the failures it shows are listed so they can be filed as bugs | Decisions 3, 4 and 5 |
| 4 | Nothing a project reads changes in this step, and the check stays green | Story trigger and manual check (**Compatible**); decision 7 |

## Tests

- Criterion 2: **`tests/test-ci-parts.sh`**, rules 10 and 11 pass on the checkout, and new cases, each on a scratch copy
  changed once, each asserting its text: the job `smoke-gitbash` removed (`the Git Bash job is malformed`);
  `runs-on: ubuntu-latest` (`malformed`); `fetch-depth: 0` removed from the job (`malformed`); an
  `if: github.event_name == 'push'` added as a job key (`malformed`); the step's `continue-on-error: true` removed
  (`malformed`); `shell: bash` removed (`malformed`); a second step `- run: echo x` (`malformed`); `smoke-guard.sh,`
  removed from the list (`tests/smoke-guard.sh runs in no Git Bash list`); `smoke-gate.sh` named twice
  (`more than once in the Git Bash list`); a line `add bash smoke-new.sh` added to the step list only
  (`tests/smoke-new.sh runs in no Git Bash list`); `smoke-slot.ps1` added to the list (`which is not a bash step`);
  `smoke-hook.sh,smoke-release.sh` swapped (`not in the order of the step list`).
- Criterion 2: **`tests/lint.sh`** passes on the branch with three check lines of the same shape in `ci.yml`, which the
  unscoped rule would fail (decision 6); the existing `lint_break` cases of `tests/smoke-check.sh` and `.ps1`
  (`cibash`, `cijson`, `ciswap`, `cidepth` and the rest) pass unchanged: they look for their text, and an extra line
  from rule 11 where a sed address also matches the new line does not hide it.
- Criterion 1: no test reads the record; the code reviewer checks that `git diff origin/main -- docs/decisions/` shows
  line 5 changed and the `## Decision` section of decision 1 appended exactly, naming step 1 as iteration 64 (#361) and
  the follow-up stories #363, #364 and #365, and nothing else. The lint's generic-word check covers the new text.
- Criterion 3: **`tests/test-ci-parts.sh`**, rule 10, with the cases above that remove the step's
  `continue-on-error: true` or its `shell: bash`, and two more, each asserting `the Git Bash job is malformed`: the name
  changed to `Git Bash smoke tests`, and a job key `needs: smoke-bash` added. **`tests/lint.sh`**: the `Required check`
  comment still counts exactly 3, and no job name begins with a required name (`== the check runs every smoke script`,
  unchanged), so the new job is not declared required; the ruleset is not changed (decision 4), which the maintainer
  sees on the pull request's run (the new job not marked "Required"). The failures: the code reviewer and the maintainer
  check that "How verified" lists each failing step with its first `FAIL` line, or says that none failed (decision 3).
- Criterion 4: the code reviewer checks that `git diff origin/main --stat` touches only the files of "Files touched"
  (nothing under `scripts/`, `skills/`, `agents/`, `hooks/`, `schema/`, `templates/`, nor `.claude/`); `bash tests/check.sh`
  is green on the branch, and the implementer puts its last line and the `Times:` total into "How verified".
- **On the pull request's run** (what the maintainer checks instead of auto-merge, before merging): the checks list
  shows `Lint (generic, JSON, skills, shell)`, `bash scripts smoke tests` and `PowerShell scripts smoke tests` green,
  the four parts, and `Git Bash smoke tests (Windows, not blocking)`; the new job's summary says
  `Selection: --affected ran every --within step: .github/workflows/ci.yml is shared by many steps.` and lists 48
  steps; the numbers of decision 5 are in "How verified", and the last commit carries the timeout of decision 5. After
  the merge, the push run on `main` runs the job with `--only` (`check: only ...`), a second full measurement.

## Files touched

- `docs/decisions/0004-scripts-in-one-language.md`: line 5 and the appended `## Decision` (decision 1), nothing else.
- `.github/workflows/ci.yml`: the job `smoke-gitbash` (decision 2), its timeout set after the first run (decision 5).
- `tests/lint.sh`: the bash-line rule scoped to `smoke-bash`, and its comment (decision 6).
- `tests/test-ci-parts.sh`: rules 10 and 11, their cases, the header comment (decision 6, Tests).
- `README.md`, under `## Developing nightmill`, after "...fails unless every part succeeded;": "a further job,
  `Git Bash smoke tests (Windows, not blocking)`, runs every bash test step in Git Bash on a Windows runner (decision
  record 0004, step 1); it is not a required check, and a failing step there shows in its summary without failing the
  job;".
- `CHANGELOG.md`, one bullet under `Unreleased`:

  ```
  - Iteration 64 (#361): decision record 0004 is accepted (bash only, with Git Bash on Windows), and CI gains its first
    migration step: a job that runs every bash test step in Git Bash on a Windows runner (Git Bash smoke tests (Windows,
    not blocking)). It is not a required check and a failing step does not fail it yet; the PowerShell parts, the
    required checks, every script and every skill stay as they are. Nothing changes for a project.
  ```

Not touched: the ruleset, the three required jobs, the PowerShell parts, `tests/check.sh`, `tests/check.ps1`, every
script, smoke test and skill, `.claude/nightmill.json`, `.claude/CLAUDE.md`, the issue forms, the schema.

## Risks

- **Failures in Git Bash** surface for the first time. They do not block (decision 3) and become bugs; until they are
  fixed the job cannot be made required.
- **Long full runs.** Every push to `main` and every pull request that touches a shared path runs all 48 steps on
  Windows. A watch still waiting on it ends "out of time" without harm, and auto-merge waits only for required checks.
  A job cancelled by its timeout is red for the watch; decision 5 bounds that by 3 times the measured time.
- **Runner time.** One more Windows runner per run (five with the parts); free for this public repository, paid in a
  private fork. The parts go only in step 4.
- **Steps that behave differently in Git Bash** (paths, `tar`, PATH tricks; the record's "stays, wider" rows) may pass
  here and still differ for a user; the workarounds and their tests stay.

## Size estimate

`M`: about 115 changed lines. `ci.yml` about 14, `tests/lint.sh` about 8, `tests/test-ci-parts.sh` about 75, the
record about 9, README about 4, CHANGELOG about 5.

## Not done

- Steps 2 to 4 of the outline: the invariant text, `verification.platform`'s new meaning, the skills, agents, README
  and `/nightmill:init` naming `.sh` only, and the removal of any `.ps1` file, test, check step or CI part.
- Making the new job required, renaming it, splitting it into parts, or changing the ruleset.
- Fixing any bash test that fails in Git Bash, and any skip list for Windows.
- macOS in CI (#156), PowerShell 7 (#155), deriving CI's lists from the check (#343).

## Left

- **How #361 relates to this pull request (needs the maintainer).** This iteration delivers criterion 1, criterion 2
  and, for step 1, criterion 7; criteria 3 to 6 stay open (steps 2 to 4). A pull request that says `Closes #361` would
  close the story with four criteria open. Recommended: the maintainer splits #361 into one story per migration step
  (the record's outline already says "Each step is one story under epic #337"), this pull request closing the step-1
  story and referring to #361 only with `Refs #361`; or #361 stays open as the story of all four steps and each
  pull request says `Refs #361`. The spec does not decide it.
- **The date of acceptance** is taken as the day #361 was filed (decision 1); the maintainer may name another.
- **Which later iteration makes the job required** (decision 4): part of step 2's story, or a story of its own before
  it. For the maintainer, after the first measured run.
