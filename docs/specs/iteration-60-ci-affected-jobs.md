# Iteration 60: CI runs only the steps a pull request's paths affect

Status: delivered in iteration 60 (PR #354)

Story #339, epic #337 (fast verification loop). It builds on iteration 59 (#338, `tests/check.sh --affected`), which
must be implemented and merged first. On a pull request every smoke job of `.github/workflows/ci.yml` runs
`tests/check.sh --affected --within <its list>`: the steps of its list that the changed paths select; on a push to
`main` it runs `--only <its list>` as today. Every job still runs on every event, so the three required names always
report. The check gains `--within` (decision 2) and, for a run with `--within`, a selection section in its `--summary`
(decision 6). Changes
`.github/workflows/ci.yml`, `tests/check.sh`, `tests/check.ps1`, `tests/smoke-check.sh`, `tests/smoke-check.ps1`,
`tests/lint.sh`, `tests/test-ci-parts.sh`, `tests/test-ci-run-steps.sh`, `README.md` and `CHANGELOG.md`.

**Never auto-merged**: the change touches `.github/workflows/ci.yml`, so the implementer opens the pull request without
`--auto`, and the maintainer merges it.

## Story trigger and manual check

**Not a story trigger.** No status, no board call and no slot marker changes. No config key is added, renamed or
removed: the check reads `git.baseBranch`, which exists; `CHECK_SELECT` (decision 1) is an environment variable of this
repository's workflow, not a key of `.claude/nightmill.json`. **Compatible** holds: `tests/check.sh` without `--within`
prints, and writes to its `--summary` file, exactly what iteration 59 makes it print and write.

**The manual check does not apply**: nothing under `skills`, `agents` or `hooks` changes. The verification on GitHub
(under Tests) stands in for it.

**Both shells**: no script in `scripts/` changes. `tests/check.ps1` passes `-Within` on as `--within`, and
`tests/smoke-check.sh` and `tests/smoke-check.ps1` get the same cases with the same expected text. In CI both shells
keep their jobs; each runs the selected steps of its own list.

## Facts this rests on

Read on `main` at ca0e047.

- The ruleset `main` (read with `gh api repos/<owner>/<repo>/rulesets/<id>`) requires the status checks
  `Lint (generic, JSON, skills, shell)`, `bash scripts smoke tests` and `PowerShell scripts smoke tests` from GitHub
  Actions, with `strict_required_status_checks_policy: false`. These are the three names under the `Required check`
  comments of `ci.yml`, and `tests/lint.sh` pins them (`== CI runs with least privilege`, rule 4).
- `on:` holds `push: branches: [main]` and `pull_request:`, with no path filter. A workflow left out by a `paths` filter
  never starts, so its required checks stay pending and the pull request cannot merge; the design therefore filters
  inside the steps, never by event paths or by job `if:`.
- Every job checks out with the default depth 1, so no `origin/main` exists in a job and iteration 59's
  `git merge-base origin/<B> HEAD` would fail; the check would fall back on every pull request.
- `smoke-bash` runs `bash tests/smoke-json.sh` directly (with jq, before the step that hides it), then
  `tests/check.sh --summary "$GITHUB_STEP_SUMMARY" --only <46 bash steps>`. Each of the 4 PowerShell parts runs
  `bash tests/check.sh --powershell powershell --summary "$GITHUB_STEP_SUMMARY" --only ${{ matrix.only }}`; the final
  job `smoke-powershell` fails unless `needs.smoke-powershell-part.result` is `success`.
- Iteration 59 decision 1 makes `--affected` with `--only` a usage error, and its full-check fallback applies
  `verification.platform`, which this repository sets to `windows`: in the bash job that fallback would skip every
  bash step. So CI cannot use `--affected` as iteration 59 defines it alone; decision 2 adds what it needs.

## Decisions

**1. The event rule: one workflow-level variable.** `ci.yml` gets, at column 0 after `permissions:`, the block

```
env:
  CHECK_SELECT: ${{ github.event_name == 'pull_request' && '--affected --within' || '--only' }}
```

and every check line in a smoke job uses `$CHECK_SELECT <list>` (unquoted, so it splits into its words) where it now
has `--only <list>`. A pull request selects; a push to `main`, and any other event, runs every step of every list.
`on:`, the job names, the matrix, the timeouts and the concurrency block do not change.

**2. What the check needs from iteration 59: `--within <step>[,<step>...]`** (`tests/check.ps1 -Within`). It is valid
only together with `--affected`; without it, given twice or empty, it is the usage error (exit 2), and a name that is no
step gives `check: no step named <x>` and the usage error, as `--only` does. The usage line becomes
`usage: tests/check.sh [--quick | --only <step>[,<step>...] | --affected [--within <step>[,<step>...]]] [--jobs <1-16>] [--powershell powershell|pwsh] [--summary <file>]`.
Everything else of iteration 59 holds; with `--within`:

1. A step runs when it is in the list and the `--affected` run without `--within` would take it. So the lint runs only
   when the list names `lint` (no CI list does), and `verification.platform` is not applied to a selected step.
2. In the first and last line of decision 6 of iteration 59, `<n>` is the number of steps in the list and `<k>` the
   number of those that run. An `affected:` line names only the steps of the list; a path that selects none of them
   prints `affected: <path> -> none of the --within steps`.
3. **The fallback** (iteration 59 decision 5: no merge base, a `shared` path, a path in no map line) runs exactly
   `--only <list>`: the first line is `check: AFFECTED: <reason>; running every --within step`, then the output of
   `--only <list>` unchanged (`check: only ...`, `SELECTED CHECKS PASSED (...)` or `SELECTED CHECKS FAILED: ...`), with
   its exit code. `verification.platform` is not read, as with `--only`. This is the "run everything" of a job when
   the changed paths cannot be listed.

**3. The changed paths in CI.** The checkout of `smoke-bash` and of `smoke-powershell-part` gets `with:` /
`fetch-depth: 0`, which fetches every branch, so `origin/main` exists and iteration 59's rule finds the paths: on a
pull request `HEAD` is GitHub's merge commit, its merge base with `origin/main` is the base the pull request was merged
onto, and the diff is the pull request's changes. `NIGHTMILL_CHECK_PATHS` stays unset in CI (iteration 59 decision 2).
Nothing is fetched by the check. The lint job and the final job keep depth 1 (they run no check).

**4. The required jobs always report.** No job gets a job-level `if:` other than the existing `if: always()` of
`smoke-powershell`, no step of `lint`, `smoke-bash` or `smoke-powershell-part` gets an `if:`, and `on:` gets no path
filter. On a docs-only pull request every job starts, its check selects 0 steps and passes (`AFFECTED CHECK PASSED
(0 of <n> steps, ...)`), every part succeeds, and the final job reports success. A required job therefore never goes
missing: it either runs or the run fails.

**5. `smoke-json.sh` goes through the check.** Its direct step becomes
`- run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT smoke-json.sh`, still before the step that
hides jq, so a docs pull request runs no test in the bash job either. The bash job then has exactly two check lines:
this one, and the one with the other bash steps.

**6. The run summary.** With `--affected --within <list>` and `--summary <file>`, the section `### tests/check.sh`
gets, after its `Wall time:` line and before the slowest-steps table, one of:

- a selective run: `Selection: --affected against <ref>: <k> of <n> steps ran, <n-k> left out (no changed path selects
  them).`, a table `| Changed path | Selects |` with one row per changed path in sorted order, its cell the text after
  ` -> ` of the path's `affected:` line, at most 50 rows and then the line `And <x> more changed paths (the log lists
  every one).`, then `Ran: <names>` and `Left out: <names>` (each name in backticks, comma-separated, in list order, or
  `none`);
- a fallback: `Selection: --affected ran every --within step: <reason>.`

Without `--within` nothing changes: a plain `--affected` run writes its section exactly as iteration 59 decision 6 has
it ("`--summary` writes its section as in the other modes"), with no `Selection:` line, table, `Ran:` or `Left out:`.

On a pull request each smoke job runs with `--within`, so it writes the selection section to `$GITHUB_STEP_SUMMARY`
(the bash job twice). A push runs `--only`, whose section does not change: nothing is left out. The final job's job table (`tests/ci-jobs-summary.sh`) does not change.

**7. A change to the workflow runs everything.** The map of iteration 59 decision 3 gains the line
`shared .github/workflows/*`, and iteration 59 lint rule 6 pins it beside the four lines it pins, so a pull request
that changes CI runs every step of every list.

**8. The lint: a new section `== CI selects the steps a pull request affects`** in `tests/lint.sh`, before
`== the lists and the shell twins agree` (inside the range `tests/smoke-check.*` cut out). Grep and awk only, no
process per line (bug #270). Rules and texts (prefix `FAIL: .github/workflows/ci.yml: `):

1. A column-0 `env:` block holds exactly the line of decision 1. Else `the env block is not exactly the line
   '<that line>'`.
2. The `on:` block is exactly `  push:`, `    branches: [main]`, `  pull_request:`. Else `the 'on:' block is not
   exactly push to main and pull_request (a path filter would leave a required job unreported)`.
3. A line `    if:` occurs only as `    if: always()` in `smoke-powershell`, and no step of `lint`, `smoke-bash` or
   `smoke-powershell-part` has an `if:` key. Else `job <id> has an 'if:' (a required job runs on every event)`.
4. The checkouts of `smoke-bash` and `smoke-powershell-part` have `fetch-depth: 0`. Else `job <id> does not check out
   with fetch-depth: 0 (the changed paths need origin/main)`.
5. In `== the check runs every smoke script`: the pattern of the bash check line becomes
   `run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT `; exactly two lines match, the first with
   the list `smoke-json.sh` and before `- name: Hide jq`, the second with the list the rule checks today. Else
   `the bash smoke job does not run tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT smoke-json.sh, then
   the other bash steps`. `ci.yml` has no line `run: bash tests/smoke-json.sh` (the direct-run rule loses its
   exception), and `--only` and `--affected` occur in it only on the line of decision 1.
6. `tests/test-ci-parts.sh` rule 2 expects the part line
   `run: bash tests/check.sh --powershell powershell --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT ${{ matrix.only }}`,
   and its text becomes `the PowerShell part job does not run tests/check.sh $CHECK_SELECT ${{ matrix.only }}`.

The required names, their comments and the `begins with` rule stay as they are.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | A pull request that changes only docs and specs runs the lint, and the required jobs report success without running tests | Decisions 1, 2 (rule 1), 4, 5; iteration 59's `lintonly docs/*` |
| 2 | A pull request that changes scripts or tests runs the steps the affected-steps mapping of the check names, in both shells | Decisions 1 to 3; iteration 59 decisions 3 and 4 |
| 3 | A push to the base branch still runs everything | Decision 1 (`--only` on every event but `pull_request`); decision 2 rule 3 and decision 7 for pull requests that cannot select |
| 4 | The required job names of the ruleset do not change, and a pull request can never merge with a required job missing | Decision 4; decision 8 rules 2 and 3; the existing name rules |
| 5 | The run summary says which steps ran and which were left out, and why | Decision 6 |

## Tests

**`tests/smoke-check.sh` and `tests/smoke-check.ps1`**, in the case `== affected` of iteration 59, with its fixture
steps (`l`, `b1`, `b2`, `p1`, `p2`, `c`), its map (`map scripts/foo.* b1,p1`, `map templates/t.md b2`,
`shared scripts/lib/*`, `lintonly docs/*`), `NIGHTMILL_CHECK_PATHS` and `--jobs 1`; the `.ps1` runs `-Affected -Within`.

- Criterion 2: paths `scripts/foo.ps1` and `docs/a.md` with `--within b1,b2` give the log `b1`, the first line
  `check: AFFECTED, 1 at a time (--jobs 1): 1 of 2 steps, changed paths: 2 (against NIGHTMILL_CHECK_PATHS); the full check does not run`,
  the lines `affected: docs/a.md -> none of the --within steps` and `affected: scripts/foo.ps1 -> b1`, the last line
  `AFFECTED CHECK PASSED (1 of 2 steps, changed paths: 2; the full check has not run)`, exit 0; with `--within p1,p2`
  and `"platform": "unix"` the log is `p1`.
- Criterion 1: `docs/a.md` alone with `--within b1,p1` gives an empty log, `0 of 2 steps`, exit 0; with
  `--within l,b1` the log is `l`.
- Criterion 3 (the fallback): `scripts/lib/x.sh` with `--within b2,p2` and `"platform": "windows"` gives the first line
  `check: AFFECTED: scripts/lib/x.sh is shared by many steps; running every --within step`, the second line
  `check: only b2,p2, 1 at a time (--jobs 1)`, the log `b2`, `p2`, the last line
  `SELECTED CHECKS PASSED (2 of 6 steps; the full check has not run)`; with `b2` exiting 1 the last line is
  `SELECTED CHECKS FAILED: b2 (the full check has not run)` and exit 1. With git and no `origin/trunk`
  (`"git": { "baseBranch": "trunk" }`, `NIGHTMILL_CHECK_PATHS` unset) the first line is
  `check: AFFECTED: the changed paths are unknown (no merge base with origin/trunk); running every --within step`.
- Criterion 5: `--summary <file>` on the first run above writes
  `Selection: --affected against NIGHTMILL_CHECK_PATHS: 1 of 2 steps ran, 1 left out (no changed path selects them).`,
  the rows ``| `docs/a.md` | none of the --within steps |`` and ``| `scripts/foo.ps1` | b1 |``, `Ran: `b1`` and
  `Left out: `b2``; the fallback run writes `Selection: --affected ran every --within step: scripts/lib/x.sh is shared by
  many steps.`; 51 paths give 50 rows and `And 1 more changed paths (the log lists every one).`
- Unchanged without `--within`: `--summary <file>` on a plain `--affected` run with the paths `scripts/foo.ps1` and
  `docs/a.md` writes a section that has its `Wall time:` line and no line
  beginning `Selection:`, `| Changed path`, `Ran:` or `Left out:`; the same holds for its fallback (`scripts/lib/x.sh`).
- Usage: `--within b1` without `--affected`, `--affected --within b1 --within b2`, `--affected --within ''` exit 2 with
  the usage line of decision 2; `--affected --within nope` prints `check: no step named nope` and exits 2; the log stays
  empty. The `USAGE` constant of both files becomes that line.

**The lint** (criteria 3 and 4; decision 8), as `lint_break` cases in both `tests/smoke-check.*`: `cienv` turns
`'--only'` into `'--quick'` in the env line and expects rule 1; `cipaths` adds `    paths-ignore: ['docs/**']` after
`  pull_request:` and expects rule 2; `ciif` adds `    if: github.event_name == 'push'` to the job `lint` and expects
`job lint has an 'if:'`; `cidepth` deletes the `fetch-depth: 0` of `smoke-bash` and expects rule 4; `cijsondirect`
restores `- run: bash tests/smoke-json.sh` and expects rule 5; `cimapci` removes `shared .github/workflows/*` and
expects `the map does not have the line shared .github/workflows/*`. The cases `cibash`, `cijson`, `ciswap` and
`cidirect` keep their expected texts; their sed expressions follow the new line. `tests/test-ci-parts.sh` (cases
`norunonly`, `dashrun`) and `tests/test-ci-run-steps.sh` (`RULE2`) take the text of rule 6.

**The full check on the branch**: `bash tests/check.sh` is green. In CI the implementation's own pull request changes
`tests/check.sh` and `ci.yml` (both `shared`), so every job runs every step of its list; its summary shows
`Selection: --affected ran every --within step: .github/workflows/ci.yml is shared by many steps.`

**Verification on GitHub by the maintainer, after the merge** (a pull request that carries this change is always a
fallback, so the two cases can only be seen afterwards). Open two throwaway pull requests against `main` and close
them unmerged:

1. One line changed in a file under `docs/`: all three required checks pass; each smoke job's summary says
   `0 of <n> steps ran`; no test step's output appears in the logs.
2. One comment line changed in `scripts/history.sh`: the bash job runs `smoke-history.sh`, the part that lists
   `smoke-history.ps1` runs it, the other parts run 0 steps, and the summaries list what ran and what was left out.

The push of the merge commit to `main` runs every step of every list (`check: only ...` in each job).

## Files touched

- `.github/workflows/ci.yml`: the `env:` block (decision 1), `fetch-depth: 0` on two checkouts (decision 3), the
  smoke-json line (decision 5), `$CHECK_SELECT` in the two other check lines.
- `tests/check.sh`: `--within` (decision 2), the selection section of the summary (decision 6), the map line of
  decision 7, the usage line and the header comment.
- `tests/check.ps1`: `[string]$Within`, passed on as `--within`, and its header comment.
- `tests/smoke-check.sh`, `tests/smoke-check.ps1`: the cases under Tests, the `USAGE` constant, the six `lint_break`
  cases and the four updated sed expressions.
- `tests/lint.sh`: the section of decision 8, the bash-line and smoke-json rules (rule 5), and the fifth line of
  iteration 59 lint rule 6.
- `tests/test-ci-parts.sh`, `tests/test-ci-run-steps.sh`: the part line and its text (rule 6).
- `README.md`, under `## Developing nightmill`: "CI runs the smoke jobs through `tests/check.sh --only`" becomes
  "CI runs the smoke jobs through `tests/check.sh`", and after that sentence: "On a pull request each CI smoke job runs
  `tests/check.sh --affected --within <its list>`: the steps of its list that the changed paths select, or all of them
  when a path is shared or unknown; a push to `main` runs every step. Every required job runs on every event."
- `CHANGELOG.md`, one bullet under `Unreleased`:

  ```
  - Iteration 60 (#339): CI runs only the steps a pull request's paths affect. On a pull request each smoke job runs
    tests/check.sh --affected --within <its list> (new: --within, check.ps1 -Within), with the history fetched so the
    paths are known; a push to main runs every step. Every required job still runs and reports, a docs-only pull
    request runs no test, a change to the workflow runs everything, and each job's summary says which steps ran and
    which were left out, and why. No config key.
  ```

Not touched: the ruleset, the job names, `on:`, the timeouts, the `validate` job, `tests/ci-jobs-summary.sh`, every
script in `scripts/`, every skill.

## Risks

- **A map that misses a dependency** lets a pull request pass that a full run would fail; the push to `main` then runs
  everything and goes red after the merge. The fix is a map line (a bug). Unknown paths and `shared` paths already fall
  back to every step.
- **Runners still start** on a docs pull request: four Windows runners and the final job each check out and run an
  empty check. The wall time is then their start-up, not the slowest test. Skipping them would need job `if:`s, which
  decision 4 rules out.
- **Spurious changed paths** (line endings on the Windows checkout, files a step leaves behind) and `fetch-depth: 0`
  (whole history, seconds on this repository) only add time or steps; they never drop a step.

## Size estimate

`M`: about 260 changed lines. `ci.yml` about 12, `tests/check.sh` about 60, `tests/check.ps1` about 4, the two smoke
files about 120, `tests/lint.sh` about 45, the two CI tests about 8, README about 4, CHANGELOG about 6.

## Not done

- No change to the ruleset, to `on:`, to a job name or a timeout, and no macOS or PowerShell 7 job (#155, #156).
- No job skipped by `if:` or by a path filter; the `validate` job (not required) runs on every event as today.
- No change to iteration 59's rules without `--within` (its output and its `--summary` section included), to `--only`
  or `--quick`, or to `verification.platform`.
- No `NIGHTMILL_CHECK_PATHS` in CI and no fetch by the check.
- No faster or split tests (#340), and no time budget.

## Left

- **`--within` extends iteration 59.** Iteration 59 makes `--affected` with `--only` a usage error and its fallback
  applies `verification.platform`; CI needs both a per-job list and a fallback that ignores the platform. This spec
  adds `--within` rather than changing iteration 59's rules; the maintainer may prefer to amend #338 instead.
- **Decision 7** (`shared .github/workflows/*`) goes a little beyond the issue's text; it keeps a change to CI from
  being verified by its own selection. The maintainer may drop it.
