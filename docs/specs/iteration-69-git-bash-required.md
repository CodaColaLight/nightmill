# Iteration 69: the Git Bash parts fail on a failing step, and their final job takes the required name

Status: draft, awaiting approval (#390)

Story #390, epic #337 (fast verification loop): the rest of #363, iteration 65 decision 7, which did not land in pull
request #389. The Git Bash CI parts of iteration 66 lose `continue-on-error` on their check step, so a failing step
fails its part and the final job; the final job `smoke-gitbash` is renamed `Git Bash scripts smoke tests`, the name the
maintainer then adds to the required checks of the ruleset on `main` by hand. The lint fails on a part with
`continue-on-error` and on any other final-job name. The change lands only after two measured full runs of the Git
Bash jobs on the pull request's final commit within the budget of iteration 66 decision 2; the maintainer measures
them and writes the result in the pull request, and when the budget is missed the pull request says so and is not
merged. Changes `.github/workflows/ci.yml`, `tests/test-ci-parts.sh`, `tests/lint.sh`, `README.md`, `.claude/CLAUDE.md`
and `CHANGELOG.md`.

**Never auto-merged.** The pull request changes `.github/workflows/ci.yml` and `.claude/CLAUDE.md`, so `/next` opens it
without `--auto` (its rule for `.claude/` and `.github/`) and the maintainer merges it by hand, after the budget comment
of decision 8 says `Budget met`.

## Story trigger and manual check

**Not a story trigger.** *Status flow*: no status, no board call, no decision record changes. *Config key*: none is
added, renamed or removed; a CI job name is a name in this repository's workflow and in its ruleset, not a key of
`.claude/nightmill.json` or of the schema, so renaming `smoke-gitbash`'s `name:` is not "a new, renamed or removed
config key". *Slot marker*: no script changes, so no marker changes. **Compatible** holds: a project reads nothing that
changes.

**The manual check does not apply.** `verification.manualCheckPaths` is `skills`, `agents`, `hooks`, and no file under
them changes. In its place the maintainer measures the pull request's own runs (decision 8).

**Shells.** No file under `scripts/` changes. The changed tests are bash (`tests/test-ci-parts.sh`, `tests/lint.sh`);
no `.ps1` file is added or changed (`tests/check.ps1`, the wrapper, stays as it is). The smoke steps involved: none is
changed; the lint (which starts `tests/test-ci-parts.sh` once) and `tests/smoke-check.sh` (whose lint copies run
`tests/test-ci-parts.sh` with `NIGHTMILL_CI_PARTS_RULES_ONLY=1`) run the changed rules.

## Facts this rests on

Read on branch `spec/69-git-bash-required` at 6132af2 ("Iteration 68: the PowerShell scripts, their tests and the
PowerShell CI parts are removed (#365) (#394)"), equal to `main`, on 2026-11-27. No network call was made; the CI times
below were given with the story (measured on recent runs of `main` and of pull request heads) and were not read here.

- **The part job** (`.github/workflows/ci.yml` lines 46 to 77): `smoke-gitbash-part`, comment lines 47 to 49 (`# The
  bash steps in Git Bash on Windows runners, in parts (iterations 64 and 66; decision record 0004, migration` / `# step
  1). Not a required check, and its check step does not fail the part: the job smoke-gitbash below fails` / `# unless
  every part succeeded.`), `name: Git Bash smoke part ${{ matrix.part }} of 7`, `runs-on: windows-latest`,
  `timeout-minutes: 360` (line 52), `fail-fast: false`, seven parts (1 to 6 one step each: `smoke-slot.sh`,
  `smoke-status.sh`, `smoke-check.sh`, `test-guard-rules.sh`, `smoke-release.sh`, `smoke-validate.sh`; part 7 the other
  41), a full-history checkout, and one step `- shell: bash` / `continue-on-error: true` (line 76) / `run: bash
  tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT ${{ matrix.only }}`. 47 of the 48 bash steps of
  `tests/check.sh` run there; `test-lintcopy-output.sh` runs on Ubuntu only (iteration 66 decision 3). The step list has
  51 steps in all (the lint, 48 bash, 2 claude).
- **The final job** (lines 79 to 108): `smoke-gitbash`, comment line 80 `# The Git Bash parts together (iteration 66).
  Not a required check until #390 makes it one.`, `name: Git Bash smoke tests (Windows, not blocking)` (line 81),
  `needs: smoke-gitbash-part`, `if: always()`, `runs-on: ubuntu-latest`, `timeout-minutes: 5`, since iteration 68 the
  job-level `permissions:` block (`contents: read`, `actions: read`), a checkout, the step `Every Git Bash part
  succeeded` (fails unless `needs.smoke-gitbash-part.result` is `success`) and the step `Job times` (with `if: always()`
  and `continue-on-error: true`, line 100, which is the final job's and stays). The PowerShell jobs are gone (#365), so
  this chain is the only Windows check.
- **While the check step has `continue-on-error: true`**, a part succeeds even when a step fails, so the final job fails
  only when a part is cancelled, times out or cannot start (iteration 66 decision 5).
- **`tests/test-ci-parts.sh`** holds both the rules and their cases in one file. Rule 10a (lines 103 to 158) wants the
  run step in a step with `shell: bash` and `continue-on-error: true` (`gstep_end`, line 109; the key read at line 129;
  the text at line 157). Rule 10b (lines 160 to 179) wants the line `    name: Git Bash smoke tests (Windows, not
  blocking)` (line 166). The cases `gbcoe` (line 329, deletes `continue-on-error: true`) and `gbfname` (line 353,
  deletes ` (Windows, not blocking)`) break those two. The header (lines 2 to 16) says the parts "do not block" and the
  final job is "not yet a required check". Every case runs through `expect_gb`, which fails a case whose text the
  unchanged checkout already prints, and `changed`, which fails a case whose edit did not apply.
- **What the lint pins of the required checks** (`tests/lint.sh`): `== the check runs every smoke script`, the loop at
  line 1365 (each required name is the `name:` of exactly one job) and the loop at line 1371 (no job name begins with a
  required name, comment line 1368), both over `'Lint (generic, JSON, skills, shell)' 'bash scripts smoke tests'`;
  `== CI runs with least privilege`, rule 4, the heredoc at lines 1774 to 1777 (the comment `# Required check: the
  ruleset on main requires this name; renaming it blocks every pull request.` directly above each required name) and
  the count at line 1779 (`exactly 2 expected, one per required job`); the comments at lines 1497 ("the two required
  names always report") and 1695 ("a comment on the two job names the ruleset on main requires"). The job-level
  `if: always()` of `smoke-gitbash` is already allowed (line 1518). `Git Bash smoke part` does not begin with
  `Git Bash scripts smoke tests`, so the begins-with rule holds for the parts.
- **Other tests that read the Git Bash jobs**, none of which reads the final job's name or the parts'
  `continue-on-error`: `tests/test-ci-job-times.sh` (the final job's `Job times` step and the step name `Every Git Bash
  part succeeded`); `tests/test-ci-run-steps.sh` (the part job's run lines; it expects rule 10a's
  `the Git Bash parts are malformed (`); `tests/smoke-check.sh` (`lint_break cidepth` reads the job ids `smoke-bash` and
  `smoke-gitbash-part`, `cibegins` the name of `validate`); `tests/test-ci-summary.sh` with
  `tests/fixtures/ci-summary/jobs.tsv` and `jobs.md`, which name `Git Bash smoke tests (Windows, not blocking)` as
  fixture data that no rule reads against `ci.yml` (iteration 68 decision 4). No test reads the README's job sentence or
  the `.claude/CLAUDE.md` sentence "CI and merging".
- **The selection on this pull request.** `tests/check.sh`'s map has `shared .github/workflows/*`, so a pull request
  that changes `ci.yml` makes every part take the fallback and run its whole list (`check: AFFECTED: <reason>; running
  every --within step` in the log, `Selection: --affected ran every --within step: <reason>.` in the summary).
- **Who can measure.** `/next` writes the pull request body when it opens the pull request, before CI has run; it does
  not watch a pull request whose auto-merge it withheld, and its hard rules forbid `gh run rerun`. So the two runs of
  iteration 66 decision 2 are measured after `/next` has ended, by the maintainer (as iteration 68 decision 3, step 2,
  left the Windows evidence to the maintainer's comment).
- **The CI times so far** (given with the story): the wall time of a whole `ci.yml` run was 15m16s, 16m15s, 16m54s,
  18m29s and 18m44s; in the last run the longest Git Bash part, part 7, took 18m15s, the others 3m52s to 15m32s. Against
  iteration 66 decision 2 (each part's `Wall time:` at most 14m00s and its job time at most 17m00s, the chain at most
  17m00s) the budget is met only some of the time for the chain, and part 7 missed it in the last run. Iteration 65's
  Facts had part 7 at 17m31s to 20m36s and the chain at 17m54s to 20m56s.

## Decisions

**1. Rule 10a: no `continue-on-error` in the part job** (the tester's, `tests/test-ci-parts.sh`). In the loop over the
block of `smoke-gitbash-part`, a line whose text, after its indent and a leading `- `, begins with
`continue-on-error:` (any value: `true`, `false` or an expression; at the job level, in the matrix or in a step) sets a
flag. After the `a needs: line` check and before the part checks, the flag gives `<what>` exactly
`a continue-on-error: line`, so the line is
`FAIL: .github/workflows/ci.yml: the Git Bash parts are malformed (a continue-on-error: line)`. The run step is counted
when its line is the run line and its step has `shell: bash` (the `gcoe` condition of `gstep_end` goes), and its text
becomes exactly
`the run step is not a run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT ${{ matrix.only }} in a step with shell: bash`.
The final job's `Job times` step keeps its `continue-on-error: true` and its rule: rule 10a reads only the block of
`smoke-gitbash-part`.

**2. Rule 10b: the final job's name** (the tester's). The first wanted line of the loop at line 166 becomes
`    name: Git Bash scripts smoke tests`; the rest of 10b stays. A final job under any other name, the old one included,
gives `FAIL: .github/workflows/ci.yml: the Git Bash job is malformed (missing: name: Git Bash scripts smoke tests)`.
The header comment (lines 2 to 16) says, in place of "and do not block" and "with shell: bash and continue-on-error:
true", that the parts block: the run step is "in a step with shell: bash, and no line of the job has
continue-on-error"; and in place of "(not yet a required check)", "(the required check Git Bash scripts smoke tests,
iteration 69)".

**3. The workflow** (the implementer's, `.github/workflows/ci.yml`), iteration 65 decision 7 brought up to date with
#365. Exactly:

- Job `smoke-gitbash-part`: the three comment lines 47 to 49 become the two lines
  `    # The bash steps in Git Bash on Windows runners, in parts (iterations 64, 66 and 69; decision record 0004); the`
  and `    # job smoke-gitbash below carries the required name and fails unless every part succeeded.`; the line
  `        continue-on-error: true` of the check step (line 76) goes; `timeout-minutes: 360` becomes
  `timeout-minutes: 51` (decision 4). Its name, strategy, matrix, lists, checkout and run line stay.
- Job `smoke-gitbash`: line 80 is replaced by
  `    # Required check: the ruleset on main requires this name; renaming it blocks every pull request.`, directly above
  `    name: Git Bash scripts smoke tests` (in place of line 81). `needs`, `if: always()`, `runs-on`, `timeout-minutes: 5`,
  its permissions comment and block, and its three steps stay word for word.
- Nothing else in the file changes.

**4. The parts' timeout is 51 minutes**: 3 times the 17m00s that iteration 66 decision 2 allows a part's job, the
factor of iteration 65 decision 7 and of bug #264's `smoke-bash` timeout. Iteration 65 decision 7 took the 3 times from
"the longest part's job time on the first run that meets the rule"; that run exists only after the pull request is
open and `/next` has ended, and a timeout changed after it would make a new final commit and void the measurement. A
part within the budget runs at most a third of the timeout; a hung part now fails after 51 minutes instead of 6 hours,
which matters once every pull request waits for the chain. The lint's rule (1 to 360) holds. No test pins the number;
the code reviewer checks it.

**5. The lint knows three required names** (the implementer's, `tests/lint.sh`, as iteration 65 decision 7 gave it
to the implementer): `Git Bash scripts smoke tests` is added, after `'bash scripts smoke tests'`, to the loops at lines
1365 and 1371 and as a third line of the heredoc of rule 4 (after line 1776); the count at line 1779 is 3, its text
`(exactly 3 expected, one per required job)`; the comments at lines 1497 and 1695 say "three" for "two". No
`lint_break` is added: each costs a lint copy (bug #270), and the lint on the checkout exercises the names.

**6. The two texts that describe the jobs** (the implementer's), iteration 65 decision 7 brought up to date:

- `README.md`, `## Developing nightmill` (lines 1116 to 1118): "a further job, `Git Bash smoke tests (Windows, not
  blocking)`, fails unless every part succeeded; it is not a required check yet (#390), and a failing step shows in its
  part's summary without failing the part;" becomes "a failing step fails its part, and the required check `Git Bash
  scripts smoke tests` is a final job that fails unless every part succeeded;". The rest of the paragraph stays.
- `.claude/CLAUDE.md`, rule "CI and merging": "a PR merges only when the lint and the bash smoke-test job pass" becomes
  "a PR merges only when the lint, the bash smoke-test job and the Git Bash smoke tests pass".

Both become true when the maintainer makes the ruleset change right after the merge (decision 9); the pull request is
merged only when the budget is met (decision 8), so neither text lands while the check is not to be required.

**7. Who writes which file** (the tester guard: a file the tester wrote is the tester's as a whole, and the implementer
does not touch it). `tests/test-ci-parts.sh` holds rules and cases, both test code: the rules are the lint's test of
`ci.yml`, and the file is a test path. So:

- **The tester** writes `tests/test-ci-parts.sh` only, whole: rule 10a (decision 1), rule 10b (decision 2), the header,
  and the cases of Tests. With the workflow still as on `main`, its rules print the `a continue-on-error: line` and the
  `missing: name: Git Bash scripts smoke tests` lines on the checkout and its new cases fail through `expect_gb`'s
  "already printed for the checkout itself" guard: the tests fail because the behaviour is missing.
- **The implementer** writes `.github/workflows/ci.yml` (decisions 3 and 4), `tests/lint.sh` (decision 5), `README.md`
  and `.claude/CLAUDE.md` (decision 6), and never `tests/test-ci-parts.sh` or `CHANGELOG.md`. A dispute over a rule or
  a case goes back to the tester.
- **The `/next` session** adds the `CHANGELOG.md` bullet of Files touched (step 5 of `/next`, only when the changelog
  has no entry for iteration 69 yet); the implementer does not touch `CHANGELOG.md`.
- No new test file: the rules and their cases stay in the one file the lint starts once and the lint copies run rules
  only (bug #270, #293).

**8. The budget: measured by the maintainer, exactly as iteration 66 decision 2 says, and written in the pull
request.** The measured commit is the pull request's final commit (`gh pr view <n> --json headRefOid`); nothing is
pushed to the branch while it is measured. The two full runs are the `CI` run its push started (`gh run list --workflow
ci.yml --commit <sha> --event pull_request --json databaseId`), attempt 1, and one re-run of all its jobs after attempt
1 has finished, `gh run rerun <id>` (no `--failed`), attempt 2. No other attempt and no other run counts. For each
attempt `<a>`, the jobs are read with `gh run view <id> --attempt <a> --json jobs` (name, conclusion, `startedAt`,
`completedAt`) and each part's log with `gh run view <id> --attempt <a> --log --job <job id>` (read only). The budget is
**met** when in both attempts:

- every part `Git Bash smoke part <k> of 7` has the conclusion `success`, its check step's log has the line
  `check: AFFECTED: <reason>; running every --within step` (the summary's `Selection: --affected ran every --within
  step: <reason>.`), and its last line is `SELECTED CHECKS PASSED (<n> of 51 steps; the full check has not run)`, the
  seven `<n>` adding up to 47;
- every part's `Wall time:` (the `total` line of the `Times:` block of its log, the same span) is at most **14m00s**,
  and its job time (`completedAt` minus `startedAt`) at most **17m00s**;
- `Git Bash scripts smoke tests` has the conclusion `success`, and the **chain**, from the earliest `startedAt` of a part
  to the `completedAt` of that job, is at most **17m00s**.

Any other outcome is **missed**: a number over its bound, a failing or cancelled part, a red step (a step that fails
in Git Bash is a bug of its own, iteration 64 decision 3, and the budget cannot hold while it fails). The maintainer
writes the result as one comment on the pull request, exactly in this form (durations as the check prints them,
`<m>m<ss>s`), and only then ticks criterion 3 in the body (decision 9; until then it is shown open):

```
Budget <met | missed> (iteration 66 decision 2), commit <sha>, run <id>
Attempt 1: chain <d>; Git Bash scripts smoke tests <conclusion>; parts (Wall time / job time): 1 <w>/<j>, 2 <w>/<j>, 3 <w>/<j>, 4 <w>/<j>, 5 <w>/<j>, 6 <w>/<j>, 7 <w>/<j>; <n> of 47 steps passed
Attempt 2: <the same>
<met:> The Git Bash jobs are within the budget: ready to be required (## Ruleset, step 3).
<missed:> Over the budget: <each bound missed, as "attempt <a> part <k> Wall time <w> > 14m00s", "job time <j> > 17m00s", "chain <d> > 17m00s", or "part <k>: <first FAIL line>">. The Git Bash jobs are not ready to be required: no ruleset change, and this pull request is not merged.
```

**What the pull request records when the budget is missed**: that comment, and nothing that says the change is ready
to be required: the body written by `/next` never says so (decision 9), and the maintainer does not merge the pull
request (the change "lands only after measured green runs within the budget", iteration 65 decision 7 and the story's
context) and makes no ruleset change. The rest, getting the chain within the budget (rebalancing or splitting the parts
by iteration 66 decision 5, rewriting slow sections by its decision 4), is a story of its own under #337, which the
maintainer files (`/story`) and links to #390 in a second comment; it is not done here. When that story has merged, this
pull request is brought up to date with `main` (a new final commit) and measured again by this decision.

**9. The ruleset change and its order: the maintainer's, by hand, named in the pull request.** No code of this
iteration changes the ruleset. `/next` writes into the body a section `## Ruleset`, exactly:

```
## Ruleset

The maintainer's steps, by hand, in this order (spec decisions 8 and 9):

1. After CI has run on this pull request's final commit, measure the Git Bash jobs in two full runs (the push run and one `gh run rerun <id>`), post the budget comment of spec decision 8, and then tick criterion 3 in this body.
2. Only when that comment says `Budget met`: merge with `gh pr merge <n> --auto --squash`. When it says `Budget missed`, stop here: no merge and no ruleset change.
3. After the merge, add the status check `Git Bash scripts smoke tests` (the final job; never a part's name) to the required checks of the ruleset on `main`.
4. Bring every pull request opened before the merge up to date with `main`: until then it reports the old name and waits for the new one.
```

and ends "How verified" with the line
`Git Bash budget: measured by the maintainer on the final commit after CI has run, in a comment on this pull request (spec decision 8); this pull request does not claim the Git Bash jobs are ready to be required.`
**Criterion 3 stays unticked in the body `/next` writes**: the measurement cannot exist before the pull request does,
so the body's criteria list shows it open, exactly
`- [ ] 3. The budget of iteration 66 decision 2 is measured and the result written in a comment: not met yet: the maintainer measures it after CI, see spec decision 8.`
while criteria 1, 2, 4 and 5 are ticked when they hold. Only the maintainer ticks criterion 3, by editing the body,
once the comment of decision 8 exists (`Budget met` or `Budget missed`: either way the result is written, which is what
the criterion asks).

**The result block.** The implementer reports `Result: complete` when criteria 1, 2, 4 and 5 hold, with criterion 3
under its `Left:` as `criterion 3: not met yet, the maintainer's step after CI (spec decision 8)`, and `/next` carries
that into the pull request as above; it never ticks criterion 3. `complete` and not `partial`, because the workflow
skill (**Stories and bugs**) makes `partial` mean a rest filed as a new story under the epic, and criterion 3 is not a
rest a story could do: it is a step on this same pull request, which a new story would only duplicate. The two things
that rule forbids both hold: no criterion that is not met is ticked, and the issue is not left half-done, since the pull
request closes #390 only when it merges, and it merges only after the `Budget met` comment (step 2), that is with
criterion 3 met.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The Git Bash parts fail the pull request on a failing step (no `continue-on-error`), and the lint (`tests/test-ci-parts.sh`) fails when a part has `continue-on-error` again | Decisions 1 and 3; decision 7 (who writes which) |
| 2 | The final Git Bash job takes the name `Git Bash scripts smoke tests`, and the lint pins that name | Decisions 2, 3 and 5 |
| 3 | The budget of iteration 66 decision 2 is checked as that decision says (two full runs of the Git Bash jobs on the final commit, measured), the result is written in the pull request, and when the budget is not met the pull request says so and does not claim the change is ready to be required | Decision 8; decision 9 (the body's lines; criterion 3 shown open, not ticked, until the maintainer's comment exists); decision 4 (the timeout without a measured run) |
| 4 | The ruleset change (the new required check name) is the maintainer's, by hand, named in the pull request with its place in the order | Decision 9 |
| 5 | The check stays green | Decisions 5 and 7; Tests (criterion 5) |

## Tests

- Criterion 1: **`tests/test-ci-parts.sh`**, rule 10a of decision 1 passes on the checkout after the implementer's
  change. Cases, each on a scratch copy changed once, through `gb_case` (so `changed` and `expect_gb` guard them):
  - `gbcoe` becomes: `/^      - shell: bash$/a\` + `        continue-on-error: true` (the step-level line back), expects
    `the Git Bash parts are malformed (a continue-on-error: line)`;
  - new `gbjobcoe`: `/^    runs-on: windows-latest$/a\` + `    continue-on-error: true` (at the job level), expects the
    same text;
  - new `gbcoeexpr`: `/^      - shell: bash$/a\` + `        continue-on-error: ${{ matrix.part == 7 }}` (one part
    exempted by an expression), expects the same text;
  - new `gbcoefalse`: the same with `        continue-on-error: false`, expects the same text;
  - `gbshell` stays (`shell: bash` removed) and now expects the run-step text of decision 1
    (`in a step with shell: bash)`); the other rule 10a cases stay as they are.
  `tests/test-ci-run-steps.sh` passes unchanged. That a red step now fails the part and the final job is shown only by
  CI (criterion 3's runs; Risks).
- Criterion 2: **`tests/test-ci-parts.sh`**, rule 10b of decision 2 passes on the checkout. Cases through `gbf_case`:
  - `gbfname` becomes `s/^    name: Git Bash scripts smoke tests$/    name: Git Bash smoke tests (Windows, not blocking)/`
    (the old name), expects `the Git Bash job is malformed (missing: name: Git Bash scripts smoke tests)`;
  - new `gbfrename`: `s/^    name: Git Bash scripts smoke tests$/    name: Git Bash smoke tests/`, expects the same text;
  - `gbfgone`, `gbfalways`, `gbfneeds`, `gbfsuccess` and `gbfcheck` stay.
  **`tests/lint.sh`** (decision 5): on the checkout the name is the `name:` of exactly one job, carries the
  `Required check` comment directly above it, and the comment occurs 3 times; no case of its own (no `lint_break`).
- Criterion 3: no test; the maintainer's budget comment (decision 8) is the evidence. The code reviewer checks the
  `## Ruleset` section and the "How verified" line against decision 9, that criterion 3 is unticked in the body with
  the open line of decision 9, and that the body claims nowhere that the jobs are ready to be required.
- Criterion 4: the code reviewer checks the `## Ruleset` section word for word against decision 9 (the four steps, in
  that order, the name `Git Bash scripts smoke tests`, the stop on `Budget missed`). No test reads the ruleset.
- Criterion 5: `bash tests/check.sh` is green on the branch (it runs the full check: `ci.yml` and the tests are shared
  paths); "How verified" gives its last line and its `Times:` total. The code reviewer checks that
  `git diff origin/main --stat` lists exactly the files of Files touched, and that the diff of `ci.yml` is the lines of
  decisions 3 and 4 only. On the pull request's run `Lint (generic, JSON, skills, shell)` and
  `bash scripts smoke tests` are green.
- **The tester** runs `bash tests/test-ci-parts.sh` (it fails on the checkout as decision 7 says) and nothing longer;
  **the implementer** runs `bash tests/test-ci-parts.sh`, `bash tests/lint.sh` and then the full check before the
  commit.

## Files touched

- `.github/workflows/ci.yml` (the implementer): the part job's comment, its check step without
  `continue-on-error: true`, its `timeout-minutes: 51`; the final job's `Required check` comment and name (decisions 3
  and 4). About 7 changed lines.
- `tests/test-ci-parts.sh` (the tester): rules 10a and 10b, the header, the cases of Tests (decisions 1, 2 and 7). About
  25 changed lines.
- `tests/lint.sh` (the implementer): the third required name in two loops and the heredoc, the count 3 and its text, two
  comments (decision 5). About 7 changed lines.
- `README.md` (the implementer): the job sentence (decision 6).
- `.claude/CLAUDE.md` (the implementer): the "CI and merging" sentence (decision 6).
- `CHANGELOG.md` (the `/next` session, step 5 of `/next`, only when the changelog has no entry for iteration 69 yet;
  the implementer does not touch it), one bullet under `## Unreleased`, below the bullet of iteration 68:

  ```
  - Iteration 69 (#390): the Git Bash CI parts fail on a failing step (no continue-on-error), time out after 51
    minutes, and their final job is named Git Bash scripts smoke tests, the check the maintainer adds to the required
    checks of main once two measured runs are within the 17-minute budget of iteration 66; the lint fails on a part
    with continue-on-error and on any other name for the final job. No config key.
  ```

Not touched: `tests/check.sh`, `tests/check.ps1`, `tests/test-ci-job-times.sh`, `tests/test-ci-run-steps.sh`,
`tests/smoke-check.sh`, `tests/test-ci-summary.sh` and `tests/fixtures/ci-summary/` (fixture data, Facts), the other
jobs of `ci.yml`, every file under `scripts/`, `skills/`, `agents/`, `hooks/`, `templates/` and `schema/`,
`.claude/nightmill.json`, `CONTRIBUTING.md`, `docs/decisions/` and the specs of iterations 65 and 66.

## Risks

- **The budget is most likely missed** (Facts: part 7 took 18m15s in the last run against 17m00s for its job and
  14m00s for its `Wall time:`). The pull request then stays open with its comment (decision 8) until the follow-up
  story brings the chain within the budget; approving this spec accepts that (Left item 1).
- **A required chain near its budget fails pull requests by chance.** Windows runners differ from run to run; the
  3-minute margin of iteration 66 decision 2 and its second run bound that. A required chain also makes every pull
  request that changes a shared path wait for the Git Bash parts; `--within` keeps the others short.
- **An intermittent step now fails pull requests** (iteration 65's Facts: `smoke-slot.sh` went red once in
  `== interruption (iteration 36)` and passed again). Before, a red step only showed in its part's summary. A red step
  is a bug of its own; the two runs of decision 8 make one that shows there a miss.
- **Open pull requests after the ruleset change** report the old name and wait for the new one until they are brought
  up to date with `main` (decision 9, step 4). Step 3 comes after the merge so that no pull request is held before it.
- **The timeout cuts a slow part**: a part over 51 minutes fails. By the Facts no part has come near it; a part that
  slow is far over the budget anyway.

## Size estimate

`S`: about 50 changed lines (`ci.yml` 7, `tests/test-ci-parts.sh` 25, `tests/lint.sh` 7, README 4, CLAUDE.md 2,
CHANGELOG 5).

## Not done

- Rebalancing, adding or splitting the Git Bash parts, or rewriting a test to make it faster, also when the budget is
  missed (a story of its own, decision 8).
- Changing the ruleset in code, or making a part's name required (iteration 66 decision 8: only the final job's name).
- Running the measurement inside `/next` (its hard rules forbid `gh run rerun`), or more than the two attempts of
  decision 8 on one commit.
- The final job's own `continue-on-error: true` on its `Job times` step, its `timeout-minutes: 5`, and the non-blocking
  `claude plugin validate` job: unchanged.
- The freeze lint and the removal of any `.ps1` file (#365), a skill, an agent or a README call line (#364), the
  meaning of `verification.platform` (#363).
- Renaming the fixture data of `tests/test-ci-summary.sh` that names the old final-job name.
- Fixing a bash step that fails in Git Bash (a bug of its own).

## Left

1. **On a miss, the pull request waits open.** By the Facts the budget is likely missed, and by the story's context the
   change lands only after measured runs within it, so decision 8 has the maintainer hold the pull request (no merge, no
   ruleset change) until the follow-up story has merged, then measure again. If the maintainer prefers to merge the
   blocking parts and the new name without making the check required, the `Required check` comment, the lint's third
   name (decision 5) and the README and CLAUDE.md sentences (decision 6) would then be untrue; that choice needs a
   change to this spec before `/next`.
2. **The timeout departs from iteration 65 decision 7's input** (decision 4: 3 times the budget of a part's job, 51
   minutes, in place of 3 times a measured job time), because the measured run comes only after `/next` has ended. The
   maintainer confirms it by approving this spec.
