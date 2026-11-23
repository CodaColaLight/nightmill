# Iteration 65: the Both shells invariant becomes Bash only, and verification.platform windows runs the bash tests

Status: draft, awaiting approval (#363)

Story #363, epic #337 (fast verification loop): step 2 of the migration outline of decision record 0004 (accepted in
#361; step 1 was iteration 64). The invariant **Both shells** becomes **Bash only** (bash on Linux and macOS, Git Bash
on Windows), with one text in the project config, the project instructions and the issue forms. The PowerShell files
are frozen: they stay and keep working, but no new one is added, and the lint fails on one; the lint stops asking a new
bash script or smoke test for a PowerShell twin. `verification.platform` keeps its key, values and default, but
`windows` now runs the bash tests (in Git Bash) and skips the PowerShell tests, as `unix` does; `all` still runs both. The
Git Bash CI job of iteration 64 is made blocking and named for the ruleset, which the maintainer changes by hand
(decision 7, which lands only after a measured green run). Changes `.claude/nightmill.json`, `.claude/CLAUDE.md`,
`CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/story.yml`, `.github/ISSUE_TEMPLATE/bug.yml`, `schema/nightmill.schema.json`,
`README.md`, `CHANGELOG.md`, `tests/check.sh`, `tests/lint.sh`, `tests/test-lint-agreement.sh`,
`tests/test-lint-agreement-cases.sh`, `tests/smoke-check.sh`, `tests/smoke-check.ps1`, and with decision 7
`.github/workflows/ci.yml` and `tests/test-ci-parts.sh`. `templates/nightmill.example.json` does not change (decision 4).
No file under `scripts/`, `skills/`, `agents/` or `hooks/` changes, and no `.ps1` file is removed.

**Never auto-merged.** The pull request changes paths under `.claude/` and `.github/` and is a story trigger, so the
implementer opens it without `--auto` and the maintainer merges it by hand.

## Story trigger and manual check

**A story trigger, by the issue's own words.** Of the three listed triggers, the nearest is "a new, renamed or removed
config key", and literally it does not apply: `verification.platform` keeps its name, its type, its `enum`
`["all", "windows", "unix"]` and its default `all`. What changes is what one value does: `windows` ran the PowerShell
tests and now runs the bash tests. A project that set the key gets other tests from the same config, which is the
contract the trigger protects (CLAUDE.md, "Config keys are a contract"); the issue and record 0004 (migration step 2)
call it a story trigger, and this spec treats it as one. The maintainer approves the new meaning by approving this
spec. *Status flow*: no status, no board call, no decision record changes; record 0004 already holds the decision.
*Slot marker*: no script changes, so no marker changes.

**Compatible** (ticked): the config is read by the previous version unchanged (same key, same values). A project on the
previous version with `windows` keeps running the PowerShell tests there; on this version it runs the bash tests. No
value becomes invalid (decision 4).

**The manual check does not apply**: `verification.manualCheckPaths` is `skills`, `agents`, `hooks`, and no file under
them changes. `skills/init/SKILL.md` still describes the old meaning of `windows` in its question 8; it is left to #364
(Left). The maintainer's look at the pull request's run stands in (Tests, "On the pull request's run").

**Shells.** This iteration changes the invariant itself. No script in `scripts/` changes. The changed tests are bash
(`tests/lint.sh`, `tests/test-lint-agreement*.sh`, `tests/test-ci-parts.sh`, `tests/smoke-check.sh`) plus one
existing PowerShell test, `tests/smoke-check.ps1`, changed only so that it stays green (decision 5's rule for a frozen
file).

**Hot file.** `schema/nightmill.schema.json` is in `parallel.hotFiles`; `parallel.doNotPair` forbids pairing this story
with another that changes the schema.

## Facts this rests on

Read on `main` at 4bcd383 (`Release 0.9.0 (#369)`) on 2026-11-23. CI runs and pull request #367 read with
`gh run list`, `gh run view` and `gh pr view` (read only).

- **Where the invariant's text lives** (`grep -rn 'Both shells\|Two shells'`, outside `docs/`): `.claude/nightmill.json`
  line 26 (`invariants[2]`, `"Both shells — every script exists in PowerShell and bash and behaves the same"`);
  `.github/ISSUE_TEMPLATE/story.yml` line 54 and `bug.yml` line 50 (the same text as `- label: "..."`, rendered from the
  config by `scripts/render-templates.*`; no lint ties form and config); the rule `- **Two shells.**` of
  `.claude/CLAUDE.md` (line 29) and of `CONTRIBUTING.md` (line 54). `templates/nightmill.example.json`,
  `templates/ISSUE_TEMPLATE/*.yml` and `templates/CLAUDE.snippet.md` do not carry it (the example's invariants are
  generic examples; the template forms hold a placeholder). `.claude/nightmill.json` `verification.benchRule` ends
  "a new script flag gets a smoke step in both shells"; it is handed to the agents by `/next` and `/fix`.
- **Where `verification.platform` is read or described**: `tests/check.sh` (header lines 30 to 33, the block at lines
  427 to 445; `windows` sets `plat_kind=bash` and the reason `bash tests (verification.platform is windows)`, `unix`
  `plat_kind=ps` and `PowerShell tests (verification.platform is unix)`, `all` nothing, anything else the note
  `check: verification.platform must be windows, unix or all; running both families`; it acts only in a full or quick
  run, never under `--only` or a selective `--affected`, and never on a step a changed path selected); the schema
  (line 95); `templates/nightmill.example.json` (`"platform": "all"`); `README.md` (the `verification` row, line 396,
  and lines 1154 to 1156); `skills/init/SKILL.md` (lines 42 and 56); `.claude/nightmill.json` (`"platform": "windows"`);
  `tests/lint.sh` (lines 1341 to 1356: type, default `all`, enum order, a description, the example's `all`, and that
  `README.md`, `skills/init/SKILL.md` and `tests/check.sh` mention the key); the cases `== the platform from the config`
  and the `--affected`/`--within` cases of `tests/smoke-check.sh` and `.ps1`; `tests/smoke-validate.sh` and `.ps1`
  (`== verification.platform is windows, unix or all`). CI never reads the key (`--only` and `--within`).
- **The twin lint** is iteration 51's `tests/test-lint-agreement.sh` (started once by `tests/lint.sh`, section
  `== the lists and the shell twins agree`; its cases in `tests/test-lint-agreement-cases.sh`, which sources it): besides
  the README's smoke list it fails `tests/<x>.sh has no PowerShell twin tests/<x>.ps1` (except `smoke-json.sh`, the one
  entry of `twin_exceptions`), the two exception texts, and `scripts/<x>.sh has no PowerShell twin scripts/<x>.ps1`.
  Iteration 57's lint section (`the PowerShell scripts read the config with exact keys (#329)`, `Select-ExactKeys` in
  every `scripts/*.ps1` and `scripts/lib/*.ps1` that reads the config) only reads existing `.ps1` files.
- **PowerShell files**: `git ls-files '*.ps1'` lists 54: 19 in `scripts/`, 4 in `scripts/lib/`, 29 in `tests/`, 2 in
  `tools/`. No `.psm1` or `.psd1`.
- **The Git Bash job** (`smoke-gitbash`, `name: Git Bash smoke tests (Windows, not blocking)`, `timeout-minutes: 360`,
  its check step with `continue-on-error: true`). PR #367's "How verified" left the first measurement "to be added", and
  the timeout is still 360. The two push runs on `main` since: run 45079116338 (on e8303ba) and run 45080452382 (on
  4bcd383). In both the job is `success` only because of `continue-on-error`: its verdict is
  `SELECTED CHECKS FAILED: smoke-json.sh smoke-slot.sh smoke-drive.sh (the full check has not run)`, with the first
  `FAIL` lines `jq cross-check json_keys worktrees: expected [root ...`, `interruption 4: the marker changed: {` and
  `left behind: the step's background process is still alive`; its wall time was 38 min 52 s and 32 min 13 s. Iteration
  64's budget for a full run is 17 minutes (its decision 5). No issue was filed for these three failures (`gh issue list
  --search "Git Bash"`).
- **The required checks** are pinned by `tests/lint.sh`: the three names in `== the check runs every smoke script`
  (lines 1408 and 1414) and in rule 4 of the CI section (the heredoc at line 1776), the `Required check` comment exactly
  3 times (line 1779); `tests/test-ci-parts.sh` rule 10 pins the Git Bash job's name and its `continue-on-error: true`.
  Iteration 64 decision 4: the iteration that makes the job required removes `continue-on-error`, gives it a name to
  require with the comment and the lint's list, and "when it is over the budget, that iteration first splits the job
  into parts by the measured step times".
- **Iteration 56** (Facts and decision 2): the full check in Git Bash on Windows took 2 to 3 hours on the maintainer's
  machine, which is why `windows` skipped the bash family.

## Decisions

**1. The invariant's one text**, used byte for byte in every place that carries it:

```
Bash only — every script is bash and behaves the same in bash on Linux and macOS and in Git Bash on Windows; the PowerShell files are frozen, and no new one is added
```

(the dash is U+2014, as in the other invariants). It replaces `invariants[2]` of `.claude/nightmill.json` in place (the
order of the five stays), and the two forms are rendered again from the config
(`bash scripts/render-templates.sh --project . --force`), so `story.yml` line 54 and `bug.yml` line 50 become
`        - label: "<the text>"`. The name changes from **Both shells** to **Bash only** because the old name says the
opposite; earlier issues keep their old checkbox text.

**2. The project instructions say the same.**

- `.claude/CLAUDE.md`: the rule `- **Two shells.** ...` (three lines) becomes exactly:

  ```
  - **Bash only.** A script in `scripts/` is bash and runs in bash on Linux and macOS and in Git Bash on Windows
    (decision record 0004); a change to one has a smoke step in `tests/smoke-*.sh`. The PowerShell files are frozen
    until they are removed (#365): no new one is added (the lint fails on it), and an existing one changes only to fix
    a bug in it or to keep its own test green. `tests/check.sh` runs what the machine can run and lists what it
    skipped; CI runs all of it (bash on Ubuntu; on Windows the bash tests in Git Bash and the PowerShell tests).
  ```

  The Commands block, which names `.ps1` calls, is a call line and stays (#364).
- `CONTRIBUTING.md`: the rule `- **Two shells.** ...` (two lines) becomes
  `- **Bash only.** Every script is bash and behaves the same in bash on Linux and macOS and in Git Bash on Windows,`
  `  with a smoke step in the bash tests. The PowerShell files are frozen: no new one is added.`; in the paragraph above
  it, "CI runs all of them, the bash ones on Ubuntu and the PowerShell ones on Windows" becomes "CI runs all of them,
  the bash ones on Ubuntu and in Git Bash on Windows, the PowerShell ones on Windows". The lint's words for that file
  (`PowerShell`, `bash`) are still there.
- `.claude/nightmill.json` `verification.benchRule` ends "a new script flag gets a smoke step in the bash tests"
  instead of "in both shells".

**3. The new meaning of `verification.platform`**, in `tests/check.sh`, for a full or a quick run (where it acts today):

| Value | Runs | Skips, with the `SKIPPED:` line |
|---|---|---|
| `windows` | the lint, every `bash` step (in Git Bash, the runner's bash), the `claude` steps | every `ps` step: `SKIPPED: PowerShell tests (verification.platform is windows)` |
| `unix` | the same as today: the lint, every `bash` step, the `claude` steps | every `ps` step: `SKIPPED: PowerShell tests (verification.platform is unix)` (unchanged) |
| `all`, no key, no or unreadable config | both families, as today | nothing, no note |
| any other value | both families, as today | nothing; the note `check: verification.platform must be windows, unix or all; running both families` (unchanged) |

- In code: the `windows)` line of the `case` becomes `windows) plat_kind=ps; plat_reason="PowerShell tests (verification.platform is windows)" ;;`.
  The reason replaces a step's own reason, as for `unix` today. Everything else stays: `--only` and a selective
  `--affected` do not read the key; when `--affected` runs the full check, the key does not apply to a step a changed
  path selected; the verdict and `Times:` lines are unchanged.
- `--quick` with `windows`: the lint and every `bash` step, no `SKIPPED:` line (the `ps` steps are left out by the
  quick mode, not skipped), as with `unix` today. The quick header and last lines stay word for word.
- The header comment (lines 30 to 33) and the block comment (lines 427 to 429) say: "windows and unix skip the ps steps
  (the scripts are bash only, decision record 0004: on Windows the bash tests run in Git Bash), all (or no key) runs
  both".
- Why both `windows` and `unix` remain, with the same effect: removing or renaming a value would break a config that
  sets it (a story of its own, and record 0004's step 4 or later decides whether the key goes).

**4. The schema, the example and the README.**

- Schema, `verification.properties.platform`: `type`, `enum` and `default` unchanged; the description becomes exactly:
  `"The platform the project runs on, for a check command that reads it; nightmill's own tests/check.sh does. windows runs the bash tests in Git Bash (from Git for Windows) and skips the PowerShell tests; unix (Linux or macOS) runs the bash tests and skips the PowerShell tests; all runs the bash and the PowerShell tests. The lint and claude plugin validate and test run on every platform. The check lists what it skipped; --only ignores this key. /nightmill:init proposes the detected platform."`
- `templates/nightmill.example.json` keeps `"platform": "all"`: the file carries values, not descriptions, and `all`
  is valid and means the same under the new meaning (both families); the lint already pins it. So the criterion holds
  for the example without a change to it.
- README, the `verification` row of the configuration table: its end
  "and which test family the check runs (`platform`: `windows`, `unix` or `all`, default `all`, for a check that reads it)"
  becomes
  "and which test families the check runs (`platform`: `windows` and `unix` run the bash tests, on Windows in Git Bash from Git for Windows; `all` runs the bash and the PowerShell tests; default `all`, for a check that reads it)".
- README, `## Developing nightmill`, the sentence "With `verification.platform` set, `tests/check.sh` runs only that
  platform's tests (the PowerShell tests on `windows`, the bash tests on `unix`), always the lint and the `claude` steps,
  and lists the family it skipped;" becomes "With `verification.platform` set to `windows` or `unix`, `tests/check.sh`
  runs the bash tests (in Git Bash on Windows) and not the PowerShell tests, always the lint and the `claude` steps, and
  lists the family it skipped;". The rest of the sentence stays.
- "A project that sets it keeps working" means, testably: each of `windows`, `unix` and `all` validates with
  `0 errors, 0 warnings` under `--strict` (the existing smoke-validate cases, unchanged), and a check run with each value
  exits 0 with its verdict line, prints no note on standard error, and runs the families of the table (Tests,
  criterion 2). This repository keeps `"platform": "windows"`.

**5. The freeze, and how the lint sees it.**

- *Frozen* means: no new PowerShell file (a file whose name ends in `.ps1`, `.psm1` or `.psd1`, in any case) is added
  anywhere in the repository; an existing one may change only to fix a bug in it or to keep its own test green (a rule
  for people and reviewers, not checked by the lint); removing one is allowed (#365 removes them).
- `tests/test-lint-agreement.sh` gets a list `frozen_ps1`, one path per line relative to the root: exactly the output of
  `git ls-files '*.ps1' '*.psm1' '*.psd1'` on the implementation's base commit (54 lines at 4bcd383), sorted, and a
  function `frozen <root>` that lists every such file under `<root>` with
  `find "$r" \( -path "$r/.git" -o -path "$r/tmp" \) -prune -o -type f \( -iname '*.ps1' -o -iname '*.psm1' -o -iname '*.psd1' \) -print`,
  untracked files included, and for each path not on the list prints on standard error exactly
  `FAIL: <path> is a new PowerShell file; the PowerShell files are frozen (decision record 0004): write it in bash`
  and returns 1 when it printed any. A listed path that no longer exists is not a failure. The file's main body runs
  `frozen "$root"` after `check "$root"` (no new process, bug #270); `check` itself does not call it, so the sourced
  cases keep their scratch trees.
- The twin rules go, because they demand the opposite: the loop that prints `tests/<x>.sh has no PowerShell twin
  tests/<x>.ps1`, the list `twin_exceptions` with the two texts about it, and the loop that prints `scripts/<x>.sh has
  no PowerShell twin scripts/<x>.ps1`. The README list rules stay, and so does the OK line `OK: lists and twins agree`.
  The header comment of the file and the comment of the lint section say: the README lists every smoke file, and no
  PowerShell file is added (iteration 65).
- Iteration 57's section (`Select-ExactKeys`) is unchanged: it reads the frozen files only. The twin rule of the check's
  map (`tests/lint.sh` rule 5, "twins select the same steps") applies only where both twins exist and is unchanged.

**6. The required check: what this repository's text and code do, and what the maintainer does.** The ruleset of
`main` is changed by the maintainer by hand; no code of this iteration changes it. The pull request says, in its own
section `## Ruleset`, the change to make: add the status check `Git Bash scripts smoke tests` to the required checks of
the ruleset on `main`, after this pull request is merged (so that open pull requests without the job are not held), and
names the run id or ids of decision 7's measurement. Those ids are measured on the pull request's own run, never taken
from this spec.

**7. The Git Bash job becomes blocking, only after a measured green run** (iteration 64 decision 4). Its changes:

- `.github/workflows/ci.yml`, job `smoke-gitbash`: its two-line comment becomes `# The bash steps in Git Bash on a
  Windows runner (decision record 0004). A required check of main once the maintainer adds it to the ruleset.`; the line
  directly above `name:` is the comment `    # Required check: the ruleset on main requires this name; renaming it
  blocks every pull request.`; `name: Git Bash scripts smoke tests`; the step's `continue-on-error: true` is removed;
  `timeout-minutes` is 3 times the measured wall time, rounded up to whole minutes, at most 360 (iteration 64
  decision 5). The job keeps no `if:`, no `needs`, no job-level `permissions:`.
- `tests/lint.sh`: the name `Git Bash scripts smoke tests` joins the three required names in the two loops of
  `== the check runs every smoke script` and in the heredoc of rule 4; the comment count is 4, with the text
  `(exactly 4 expected, one per required job)`.
- `tests/test-ci-parts.sh` rule 10: the name line is `    name: Git Bash scripts smoke tests`; the run step's step has
  `shell: bash` and no `continue-on-error:` line, and any `continue-on-error:` line in the job is malformed (the texts:
  `the name line is not 'Git Bash scripts smoke tests'`, and `the run step is not a run: bash tests/check.sh --summary
  "$GITHUB_STEP_SUMMARY" $CHECK_SELECT <list> in a step with shell: bash and no continue-on-error`). Rule 11 and the
  header comment's rule 11 are unchanged; the header's sentence on rule 10 says "and blocks".
- README, `## Developing nightmill`: "a further job, `Git Bash smoke tests (Windows, not blocking)`, runs every bash test
  step in Git Bash on a Windows runner (decision record 0004, step 1); it is not a required check, and a failing step
  there shows in its summary without failing the job;" becomes "the required check `Git Bash scripts smoke tests` runs
  every bash test step in Git Bash on a Windows runner (decision record 0004) and fails on a failing step;".
- `.claude/CLAUDE.md`, rule "CI and merging": "a PR merges only when the lint and both smoke-test jobs pass" becomes
  "a PR merges only when the lint and the three smoke-test jobs (bash, PowerShell, Git Bash) pass".

The measurement: this pull request changes `ci.yml`, a shared path, so its own run runs all 48 bash steps in the job.
**The rule (closed; no other budget and no other exception applies):** decision 7 lands only when the pull request's
own full run of the job, with `continue-on-error` removed, has the conclusion `success`, its summary ends
`SELECTED CHECKS PASSED (48 of <M> steps; the full check has not run)`, and its wall time is at most 17 minutes, the
budget of iteration 64 decision 5. Then the implementer puts into "How verified" the run id, the job's wall time, its
`Wall time:` line and five slowest steps, sets the timeout, and cites the second run that the timeout commit starts.
**The fallback, when any of the three conditions fails:** decision 7 does not land. The implementer takes every change
of this decision out of the branch again (the job, the lint, `test-ci-parts.sh`, the README job sentence, the CLAUDE.md
"CI and merging" sentence and the changelog's last sentence stay as on `main`), does not fix a failing bash test and
does not split the job here, reports `partial` with criterion 4 unmet, giving the run id, the wall time and each
failing step with its first `FAIL` line, and files the remainder (criterion 4: the job made blocking and required after
a measured green run within the budget) as a new story under #337 with `/story`, linked to #363, as the workflow's rule
for a story only partly done says; the pull request says so and leaves criterion 4 unticked. Criteria 1, 2, 3 and 5 are
delivered without it. By the Facts (two red runs of 32 and 39 minutes), approving this spec as written accepts this
fallback unless the job changes before the implementation (Left item 1).

**8. The check stays green, and the changelog.** `bash tests/check.sh` passes on the branch. The rule is needed: today
`tests/check.sh` line 435 makes `windows` skip every `bash` step in a full run, so on a Windows machine with this
repository's `windows` the local full check has never run the 48 bash steps; with decision 3 it runs them in Git Bash,
`smoke-json.sh`, `smoke-slot.sh` and `smoke-drive.sh` among them (the three that fail on the Windows runner, Facts).
**The rule for the implementer (closed), when `bash tests/check.sh` on the branch is red only because of one or more
of `smoke-json.sh`, `smoke-slot.sh` and `smoke-drive.sh`** (its last line `CHECK FAILED:` names no other step). It
follows `/next`'s rule for a story only partly done (its step 8, and the `Result: partial` of "The implementer"); `/next`
does not resume #363.

- *What the implementer does.* It does not fix the three steps (Not done stays), does not skip them (no skip list, no
  reason, no change to `verification.platform`), and does not commit red. It takes criterion 2 out of the branch: its
  own uncommitted changes of decisions 3 and 4 (the `windows)` line and the two comments of `tests/check.sh`, the
  schema description, the README row and platform sentence) go back to `main`'s text, so `tests/check.sh` treats
  `windows` as on `main` and the three steps run on this machine exactly as often as they do on `main` (not at all in
  a full run). The tester's files that hold criterion 2's tests, `tests/smoke-check.sh`, `tests/smoke-check.ps1` and
  `tests/lint.sh`, are set aside with the stash of `/next` (`Unmet tests for #363: <title>`) and listed under Left as
  `unmet: <path> (criterion 2)`. It runs the full check again; when it is green it commits, and puts the stash back.
  A check that is still red, or red at the first run with any other step, is the implementer's own failure to fix, as
  for any change. It reports `Result: partial`; `Check:` is the green last line; `Left` holds the `unmet:` lines and,
  for the bugs below, the first run's `CHECK FAILED:` line and each failing step's first `FAIL` line.
- *What the partial pull request holds and ticks.* **Criterion 3** is delivered and ticked (decision 5;
  `tests/test-lint-agreement.sh` and `tests/test-lint-agreement-cases.sh` hold only its tests). The changes of
  **criterion 1** (decisions 1 and 2: the config, the two forms, `CLAUDE.md`, `CONTRIBUTING.md`, the `benchRule`) are
  committed, since they do not depend on decision 3, but criterion 1 is **not met and not ticked**: its test is the new
  section of `tests/lint.sh`, a file that also holds criterion 2's test and so stays uncommitted as a whole (`/next`'s
  rule for a shared file). **Criterion 2** cannot be delivered without a green full check that runs the bash steps on
  Windows. **Criterion 5** is not met: the check is green, but "a Windows project needs Git for Windows" is true only
  with criterion 2. **Criterion 4** falls back by decision 7 (its run fails the same three steps). The session adds
  this bullet under `Unreleased` instead of the one of Files touched (step 5 of `/next`):

  ```
  - Iteration 65 (#363), partly done: the invariant Both shells becomes Bash only (decision record 0004, step 2):
    every script is bash and runs in bash on Linux and macOS and in Git Bash on Windows. The PowerShell files are
    frozen, not removed: they still ship and work, the lint fails on a new one, and it no longer asks a new bash script
    or smoke test for a PowerShell twin. The new meaning of verification.platform and the required Git Bash check
    follow in a new story under #337.
  ```

  The pull request still says `Closes #363`, opens without auto-merge (it is partial and a story trigger), and names
  the new story and the three bugs.
- *What the session files* (the implementer touches no issue). (a) One bug per failing step, from the bug form, each
  with its first `FAIL` line and the run (local, and the Git Bash CI run ids of Facts); they are fixed through `/fix`
  once the maintainer sets them Ready. (b) The rest of #363 as one new story under #337 with `/story`, linked to #363
  both ways, the pull request saying so (step 8 of `/next`): criteria 1, 2, 4 and 5 of #363 as its criteria, this spec
  named as its source, the paths, the stash's message and the copied text of the set-aside tests (step 8), and the line
  that the three bugs must be merged before its `/next` starts. When decision 7's fallback also applies, its remainder
  is part of this one story, not a second one. The maintainer approves the new story only after the three fixes are
  merged.

The CHANGELOG bullet is under Files touched; its last sentence is written only when decision 7 lands.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The **Both shells** invariant says bash only (bash on Linux and macOS, Git Bash on Windows) in the project config, the project instructions and the issue forms | Decisions 1 and 2 |
| 2 | `verification.platform` has its new meaning in the schema, the example config and the README table, and a project that sets it keeps working | Decisions 3 and 4; Story trigger and manual check |
| 3 | The PowerShell scripts are frozen: no new PowerShell twin is added, and the lint says so | Decision 5 |
| 4 | The Git Bash CI job from #361 is a required check of `main` after a measured green run (a ruleset change the maintainer makes by hand, said in the pull request) | Decisions 6 and 7; Left item 1 |
| 5 | The changelog says what a Windows project now needs (Git for Windows), and the check stays green | Decision 8; Files touched (the bullet) |

## Tests

- Criterion 1: **`tests/lint.sh`**, a new section `== the invariant is Bash only (#363)`, with the text of decision 1 in
  one variable: `.claude/nightmill.json` has an `invariants` item equal to it (else
  `FAIL: .claude/nightmill.json: no invariant is the Bash only text`) and no item that begins with `Both shells` (else
  `FAIL: .claude/nightmill.json: an invariant still begins with Both shells`); `.github/ISSUE_TEMPLATE/story.yml` and
  `bug.yml` each have the line `        - label: "<the text>"` exactly once and no line containing `Both shells —` (else
  `FAIL: .github/ISSUE_TEMPLATE/<f> does not carry the Bash only invariant`, or `... still carries the Both shells
  invariant`); `.claude/CLAUDE.md` and `CONTRIBUTING.md` each have a line that begins `- **Bash only.**` and none with
  `**Two shells.**` (else `FAIL: <file> has no Bash only rule`, or `FAIL: <file> still has the Two shells rule`). The
  implementer breaks each rule once in a scratch copy and sees its line (as iteration 56 did); the code reviewer checks
  the CLAUDE.md and CONTRIBUTING texts against decision 2.
- Criterion 2: **`tests/smoke-check.sh`** and **`tests/smoke-check.ps1`**, case `== the platform from the config`
  (fixture steps `l`, `b`, `p`, `c`), the `windows` lines changed and the rest kept; `WIN_LINE` becomes
  `SKIPPED: PowerShell tests (verification.platform is windows)`:
  - `windows`: exit 0, log `l,b,c,`, the `SKIPPED:` lines exactly `WIN_LINE`, no `== p` section, last line
    `ALL CHECKS PASSED`, standard error empty;
  - `windows` with `p` given the reason `no pwsh here`: log `l,b,c,`, `WIN_LINE` printed, `SKIPPED: no pwsh here` not;
  - `windows` with `b` given the reason `other reason`: log `l,c,`, the `SKIPPED:` lines in this order
    `SKIPPED: other reason`, `WIN_LINE`; last line `ALL CHECKS PASSED`;
  - `--quick` with `windows`: log `l,b,`, no `SKIPPED:` line, the quick last line;
  - unchanged: `unix` (log `l,b,c,`), `all` and no key (log `l,b,p,c,`, equal outputs, standard error empty),
    `linux` and `3` (the note), `--only b,p` with each value (log `b,p,`, no `SKIPPED:` line).
  - In the `--affected` cases, "a shared file with a changed script" under `windows` (changed `scripts/lib/x.sh` and
    `scripts/foo.sh`): log `l,b1,b2,p1,c,` and `WIN_LINE` printed (for `p2`); "p1 with a reason" under `windows`: log
    `l,b1,` as today. The `--within` cases are unchanged (the key does not apply).
  - **`tests/smoke-validate.sh`** and `.ps1`, `== verification.platform is windows, unix or all`: unchanged, and they
    pass (each value `0 errors, 0 warnings` under `--strict`).
  - **`tests/lint.sh`**, the platform block: the description of `verification.properties.platform` contains
    `windows runs the bash tests in Git Bash`, else
    `FAIL: schema: verification.platform's description does not say windows runs the bash tests in Git Bash`; the existing
    checks (example `all`, the README row mentions `platform`) stay. **`tests/smoke-check.sh`** gains
    `lint_break platformmeaning schema/nightmill.schema.json 's/windows runs the bash tests in Git Bash/windows runs the PowerShell tests/' 'does not say windows runs the bash tests in Git Bash'`
    (bash only: no new step in a frozen file). The README row's text is checked by the code reviewer against decision 4.
- Criterion 3: **`tests/test-lint-agreement-cases.sh`**, calling `frozen` (sourced) on scratch trees: a tree with
  `scripts/slot.ps1`, `tests/check.ps1` and `scripts/b.sh` prints nothing and returns 0; `scripts/new.ps1` added prints
  `FAIL: scripts/new.ps1 is a new PowerShell file; the PowerShell files are frozen (decision record 0004): write it in bash`;
  `tests/smoke-new.ps1`, `tools/x/y.PS1` and `scripts/lib/m.psm1` each print the same line with their path; a file
  `.git/hooks/h.ps1` prints nothing; a tree without any listed file prints nothing; `frozen "$root"` on this checkout
  prints nothing. The existing cases `script` (`scripts/b.sh has no PowerShell twin`) and the first expectation of
  `all rules run` change: `scripts/b.sh` alone and `tests/smoke-b.sh` with its README line pass with no `FAIL`, and
  `all rules run` adds `scripts/new.ps1` and expects its frozen line and the README line (through `runfile`).
  **`tests/test-lint-agreement.sh`**'s self-tests `no twin`, `exception gone`, `exception twinned` and `script` are
  replaced by `no twin needed` (a `tests/smoke-b.sh` with its README line and a `scripts/b.sh`: no output). The lint
  passes on this checkout with its 54 files.
- Criterion 4 (only with decision 7): **`tests/test-ci-parts.sh`**, rule 10 passes on the checkout; the cases change:
  `gbcoe` adds `        continue-on-error: true` after `shell: bash` (expect `the Git Bash job is malformed`), and
  `gbname` is `s/ scripts smoke tests$/ smoke tests/` (expect `malformed`); the other cases stay. **`tests/lint.sh`**:
  the four names each once with the comment above, the comment exactly 4 times; **`tests/smoke-check.sh`** gains
  `lint_break cigbrename .github/workflows/ci.yml 's/name: Git Bash scripts smoke tests/name: Git Bash smoke/' 'the required job Git Bash scripts smoke tests is missing'`.
  The ruleset is the maintainer's (decision 6): the code reviewer checks that the pull request has the `## Ruleset`
  section and the run ids, and no test reads the ruleset.
- Criterion 5: the code reviewer checks the bullet against Files touched and that `git diff origin/main --stat` touches
  only the files listed there (nothing under `scripts/`, `skills/`, `agents/`, `hooks/`, `templates/`, no `.ps1` added
  or removed); `bash tests/check.sh` is green on the branch, and the implementer puts its last line, the `Times:` total
  and the `SKIPPED:` lines into "How verified".
- **On the pull request's run** (the maintainer, before merging by hand): `Lint (generic, JSON, skills, shell)`,
  `bash scripts smoke tests` and `PowerShell scripts smoke tests` green; with decision 7, `Git Bash scripts smoke tests`
  green (not yet marked Required) with 48 steps in its summary; the run ids and numbers of decision 7 in "How verified".

## Files touched

- `.claude/nightmill.json`: `invariants[2]` (decision 1), `verification.benchRule` (decision 2). `platform` stays
  `windows`.
- `.github/ISSUE_TEMPLATE/story.yml`, `.github/ISSUE_TEMPLATE/bug.yml`: re-rendered, one line each (decision 1).
- `.claude/CLAUDE.md`: the `Bash only` rule (decision 2); with decision 7 the "CI and merging" sentence.
- `CONTRIBUTING.md`: the rule and the CI sentence (decision 2).
- `schema/nightmill.schema.json`: the description of `verification.platform` (decision 4).
- `tests/check.sh`: the `windows)` line and two comments (decision 3).
- `tests/smoke-check.sh`, `tests/smoke-check.ps1`: the cases of criterion 2; `smoke-check.sh` also the two
  `lint_break` lines.
- `tests/lint.sh`: the section of criterion 1, the description check of criterion 2, the section comment of
  `== the lists and the shell twins agree`; with decision 7 the required names and the count.
- `tests/test-lint-agreement.sh`, `tests/test-lint-agreement-cases.sh`: decision 5 and its cases.
- With decision 7: `.github/workflows/ci.yml` (the job `smoke-gitbash`), `tests/test-ci-parts.sh` (rule 10, two cases,
  header).
- `README.md`: the `verification` row and the platform sentence (decision 4); with decision 7 the job sentence.
- `CHANGELOG.md`, one bullet under `Unreleased`:

  ```
  - Iteration 65 (#363): the invariant Both shells becomes Bash only (decision record 0004, step 2): every script is
    bash and runs in bash on Linux and macOS and in Git Bash on Windows. The PowerShell files are frozen, not removed:
    they still ship and work, the lint fails on a new one, and it no longer asks a new bash script or smoke test for a
    PowerShell twin. verification.platform keeps its values and default, but windows now runs the bash tests in Git
    Bash and skips the PowerShell tests, as unix does; all still runs both. A Windows project now needs Git for Windows
    (which brings Git Bash) for the check, as its hooks already do. The Git Bash CI job is now Git Bash scripts smoke
    tests and fails on a failing step, to be made a required check of main.
  ```

  Without decision 7 the last sentence is left out.

Not touched: `templates/` (decision 4), `scripts/`, `skills/` (`skills/init/SKILL.md` included, Left item 3),
`agents/`, `hooks/`, `tests/check.ps1`, `tests/smoke-validate.*`, every other `.ps1`, `docs/decisions/`.

## Risks

- **This repository's local check on Windows gets much longer and may go red.** With `windows` it now runs the 48 bash
  steps in Git Bash: 32 to 39 minutes on a CI runner, 2 to 3 hours on the maintainer's machine by iteration 56. Three of
  them fail on the Windows runner today (Facts); if they fail locally too, decision 8's rule makes #363 partly done
  (criterion 3 delivered, the rest a new story that waits for the three bug fixes; Left item 2). `--affected` keeps the per-change check short; only the full check grows.
- **A Windows project without Git for Windows** gets no bash tests from its check; it already lacked the hooks. The
  changelog names the need.
- **The init question still tells a new project that `windows` runs the PowerShell tests** until #364 (Left item 3).
- **Requiring a 30-minute job** lengthens every pull request that changes a shared path; `--within` keeps the others
  short. Decision 7 only lands green and within the 17-minute budget; otherwise its fallback applies.
- **The frozen list is data in a test**: a removal in #365 leaves stale lines, which do no harm (a missing listed file is
  not a failure); #365 removes the list with the files.

## Size estimate

`M`: about 190 changed lines. `tests/test-lint-agreement.sh` about 70 (the 54-line list, the function, the self-tests),
`tests/test-lint-agreement-cases.sh` about 25, `tests/lint.sh` about 25, `tests/smoke-check.sh` and `.ps1` about 25,
`tests/check.sh` 5, the config, forms, schema, CLAUDE.md, CONTRIBUTING and README about 25, CHANGELOG 8; decision 7
about 20 more.

## Not done

- Removing any `.ps1` file, test, check step or CI part (#365); `tests/check.ps1` stays.
- Changing a skill, an agent, a hook or a README call line, `/nightmill:init`'s question 8 included (#364).
- Renaming or removing `verification.platform` or one of its values; a new key.
- Changing the ruleset (the maintainer's hand step) or splitting the Git Bash job into parts.
- Fixing the three bash steps that fail in Git Bash on the Windows runner, or any skip list for Windows.
- macOS in CI (#156), PowerShell 7 (#155), anything in `scripts/`.

## Left

1. **The Git Bash job is over the budget and red today (needs the maintainer).** Its two measured full runs on `main`
   took 38 min 52 s and 32 min 13 s against iteration 64's 17 minutes, and both failed three steps (Facts). Iteration
   64 decision 4 says the iteration that makes the job required first splits it into parts when it is over the budget;
   this spec does not split it (no green run exists to measure step times by). So decision 7 cannot land as things
   stand, and its rule (green, at most 17 minutes) and fallback (partial, criterion 4 filed as a new story under #337)
   are fixed by this spec. The maintainer's choice, before approving: (a) a split of the job, as a story of its own,
   done before #363's implementation, so that the rule can be met, or (b) criterion 4 split off #363 into its own story
   now. **Approving the spec as written accepts the fallback**: the implementer then most likely reports `partial` and
   files criterion 4 as a new story.
2. **Three Git Bash failures with no issue** (`smoke-json.sh`, `smoke-slot.sh`, `smoke-drive.sh`, Facts). They block
   decision 7, and, because this repository sets `windows`, possibly the local full check on Windows; decision 8's rule
   then delivers #363 partly (criterion 3 only), files each failure as a bug for `/fix` and the rest of #363 as a new
   story under #337 that waits for those fixes. Filing and fixing them before `/next` starts on #363 avoids the split.
3. **`skills/init/SKILL.md` question 8** ("`windows` (the check runs the PowerShell tests)") becomes wrong with this
   iteration. Out of scope here (no skill changes); it belongs in #364, or the maintainer adds it here, which makes the
   manual check apply.
