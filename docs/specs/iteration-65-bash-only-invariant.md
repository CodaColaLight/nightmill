# Iteration 65: the Both shells invariant becomes Bash only, and verification.platform windows runs the bash tests

Status: delivered in iteration 65 (PR #389)

Story #363, epic #337 (fast verification loop): step 2 of the migration outline of decision record 0004 (accepted in
#361; step 1 was iteration 64, and iteration 66 split its Git Bash job into parts). The invariant **Both shells**
becomes **Bash only** (bash on Linux and macOS, Git Bash on Windows), with one text in the project config, the project
instructions and the issue forms. The PowerShell files are frozen: they stay and keep working, but no new one is
added, and the lint fails on one; the lint stops asking a new bash script or smoke test for a PowerShell twin.
`verification.platform` keeps its key, values and default, but `windows` now runs the bash tests (in Git Bash) and
skips the PowerShell tests, as `unix` does; `all` still runs both. The Git Bash CI jobs of iterations 64 and 66 become
blocking, and their final job takes the name the maintainer adds to the ruleset by hand (decision 7, which lands only
after measured green runs within the budget). Changes `.claude/nightmill.json`, `.claude/CLAUDE.md`,
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
them changes. `skills/init/SKILL.md` still describes the old meaning of `windows` in its question 8; iteration 67
(#364) changes it (Left). The maintainer's look at the pull request's runs stands in (Tests, "On the pull request's
run").

**Shells.** This iteration changes the invariant itself. No script in `scripts/` changes. The changed tests are bash
(`tests/lint.sh`, `tests/test-lint-agreement*.sh`, `tests/test-ci-parts.sh`, `tests/smoke-check.sh`) plus one
existing PowerShell test, `tests/smoke-check.ps1`, changed only so that it stays green (decision 5's rule for a frozen
file).

**Hot file.** `schema/nightmill.schema.json` is in `parallel.hotFiles`; `parallel.doNotPair` forbids pairing this story
with another that changes the schema.

## Facts this rests on

Read on `main` at d3fc83a (`docs: iteration 67 spec (#364) (#385)`) on 2026-11-26. CI runs, pull request #384 and
issue #382 read with `gh run list`, `gh run view`, `gh pr view` and `gh issue view` (read only).

- **Where the invariant's text lives** (`grep -rn 'Both shells\|Two shells'`, outside `docs/`): `.claude/nightmill.json`
  line 26 (`invariants[2]`, `"Both shells — every script exists in PowerShell and bash and behaves the same"`);
  `.github/ISSUE_TEMPLATE/story.yml` line 54 and `bug.yml` line 50 (the same text as `- label: "..."`, rendered from the
  config by `scripts/render-templates.*`; no lint ties form and config); the rule `- **Two shells.**` of
  `.claude/CLAUDE.md` (line 29) and of `CONTRIBUTING.md` (line 54). `templates/nightmill.example.json`,
  `templates/ISSUE_TEMPLATE/*.yml` and `templates/CLAUDE.snippet.md` do not carry it. `.claude/nightmill.json`
  `verification.benchRule` (line 41) ends "a new script flag gets a smoke step in both shells".
- **Where `verification.platform` is read or described**: `tests/check.sh` (header lines 30 to 33; the block from line
  428, whose `windows)` line 436 sets `plat_kind=bash` and the reason `bash tests (verification.platform is windows)`;
  `unix` sets `plat_kind="ps"` and `PowerShell tests (verification.platform is unix)`, `all` nothing, anything else the
  note `check: verification.platform must be windows, unix or all; running both families`; it acts only in a full or
  quick run, never under `--only` or a selective `--affected`, and never on a step a changed path selected); the schema
  (line 95); `templates/nightmill.example.json` (`"platform": "all"`); `README.md` (the `verification` row, line 396,
  and lines 1155 to 1157); `skills/init/SKILL.md` (lines 42 and 56); `.claude/nightmill.json` (`"platform": "windows"`,
  line 43); `tests/lint.sh` (lines 1341 to 1356, in the section `== the check runs every smoke script`); the case
  `== the platform from the config` (line 174, `WIN_LINE` line 178) and the `--affected` cases of
  `tests/smoke-check.sh`, and the same in `tests/smoke-check.ps1` (lines 220 and 224); `tests/smoke-validate.sh` and
  `.ps1`. CI never reads the key (`--only` and `--within`).
- **The twin lint** is iteration 51's `tests/test-lint-agreement.sh` (main body `check "$root"`, line 102; started once
  by `tests/lint.sh`, section `== the lists and the shell twins agree`, line 1577; its cases in
  `tests/test-lint-agreement-cases.sh`): besides the README's smoke list it fails
  `tests/<x>.sh has no PowerShell twin tests/<x>.ps1` (except `smoke-json.sh`, the one entry of `twin_exceptions`), the
  two exception texts, and `scripts/<x>.sh has no PowerShell twin scripts/<x>.ps1`. Iteration 57's section
  (`Select-ExactKeys`) only reads existing `.ps1` files.
- **PowerShell files**: `git ls-files '*.ps1' '*.psm1' '*.psd1'` lists 54: 19 in `scripts/`, 4 in `scripts/lib/`, 29
  in `tests/`, 2 in `tools/`. No `.psm1` or `.psd1`.
- **The Git Bash jobs** (iteration 66, PR #384, merged as 5da00ec): `smoke-gitbash-part`
  (`name: Git Bash smoke part ${{ matrix.part }} of 7`, `timeout-minutes: 360`, its check step with `shell: bash` and
  `continue-on-error: true`; parts 1 to 6 one step each, `smoke-slot.sh`, `smoke-status.sh`, `smoke-check.sh`,
  `test-guard-rules.sh`, `smoke-release.sh`, `smoke-validate.sh`, part 7 the other 41) and the final job `smoke-gitbash`
  (comment `# The Git Bash parts together (iteration 66). Not a required check until iteration 65 makes it one.`,
  `name: Git Bash smoke tests (Windows, not blocking)`, `needs: smoke-gitbash-part`, `if: always()`, ubuntu,
  `timeout-minutes: 5`). 47 of the 48 bash steps of `tests/check.sh` run there; `test-lintcopy-output.sh` runs on
  Ubuntu only (iteration 66 decision 3).
- **The steps are green in Git Bash now; the time is not.** The three failures the first draft of this spec found
  (`smoke-json.sh`, `smoke-slot.sh`, `smoke-drive.sh`) are fixed (#372, #373, #374). In both push runs on `main` since
  iteration 66, 45681905654 (on 5da00ec) and 45691258685 (on d3fc83a), every part's check step ends
  `SELECTED CHECKS PASSED (<k> of 78 steps; the full check has not run)`, the `<k>` adding up to 47, and the final job
  is `success`. Against iteration 66 decision 2 (each part's `Wall time:` at most 14m00s, the chain at most 17m00s),
  read from the `Times:` totals (the same span as `Wall time:`) and the job times: part 7 took 20m36s and 19m39s (job
  20m50s and 19m52s), part 1 14m36s and 12m06s, every other part at most 12m15s; the chain took 20m56s and 19m58s.
  Part 7's slowest steps in 45691258685: `smoke-drive.sh` 11m42s, `smoke-control.sh` 8m48s, `test-spec-template.sh`
  8m05s, `smoke-load.sh` 5m06s, `smoke-dashboard.sh` 3m21s. Pull request #384's last run, 45677230884, had part 7 at
  17m31s and a chain of 17m54s. PR #384 says the budget was not met yet and left the rebalance and the rewrites of
  iteration 66 decisions 4 and 5 to later rounds; #382 is closed, and no story for the rest was filed.
- **The required checks** are pinned by `tests/lint.sh`: the three names in the two loops of
  `== the check runs every smoke script` (lines 1408 and 1414) and in the heredoc of rule 4 (line 1794), the
  `Required check` comment exactly 3 times (line 1800), the comments at lines 1546 and 1715 say "three". The
  `if: always()` of `smoke-gitbash` is already allowed (line 1567). `tests/test-ci-parts.sh` rule 10a pins the part
  job's check step with `continue-on-error: true` (line 246) and rule 10b the name
  `    name: Git Bash smoke tests (Windows, not blocking)` (line 255); its cases `gbcoe` (line 436) and `gbfname` (line
  460) break those.
- **The local cost on Windows.** Today `windows` skips the bash steps, so PR #384's local full check (1h40m) ran no
  bash step. Iteration 56 recorded 2 to 3 hours for the full check in Git Bash on the maintainer's machine. Iteration
  66's local measurements, each step alone: `test-lintcopy-output.sh` 4575 s, `smoke-slot.sh` 2185 s, `smoke-check.sh`
  1567 s, one whole lint about 620 s; `smoke-slot.sh` went red once in `== interruption (iteration 36)` and passed on a
  second run.

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
  the bash ones on Ubuntu and in Git Bash on Windows, the PowerShell ones on Windows".
- `.claude/nightmill.json` `verification.benchRule` ends "a new script flag gets a smoke step in the bash tests"
  instead of "in both shells".

**3. The new meaning of `verification.platform`**, in `tests/check.sh`, for a full or a quick run (where it acts today):

| Value | Runs | Skips, with the `SKIPPED:` line |
|---|---|---|
| `windows` | the lint, every `bash` step (in Git Bash, the runner's bash), the `claude` steps | every `ps` step: `SKIPPED: PowerShell tests (verification.platform is windows)` |
| `unix` | the same as today: the lint, every `bash` step, the `claude` steps | every `ps` step: `SKIPPED: PowerShell tests (verification.platform is unix)` (unchanged) |
| `all`, no key, no or unreadable config | both families, as today | nothing, no note |
| any other value | both families, as today | nothing; the note `check: verification.platform must be windows, unix or all; running both families` (unchanged) |

- In code: line 436 becomes `    windows) plat_kind=ps; plat_reason="PowerShell tests (verification.platform is windows)" ;;`.
  The reason replaces a step's own reason, as for `unix` today. Everything else stays: `--only` and a selective
  `--affected` do not read the key; when `--affected` runs the full check, the key does not apply to a step a changed
  path selected; the verdict and `Times:` lines are unchanged.
- `--quick` with `windows`: the lint and every `bash` step, no `SKIPPED:` line (the `ps` steps are left out by the
  quick mode, not skipped), as with `unix` today. The quick header and last lines stay word for word.
- The header comment (lines 30 to 33) and the block comment (from line 428) say: "windows and unix skip the ps steps
  (the scripts are bash only, decision record 0004: on Windows the bash tests run in Git Bash), all (or no key) runs
  both".
- Why both `windows` and `unix` remain, with the same effect: removing or renaming a value would break a config that
  sets it (a story of its own; record 0004's step 4 or later decides whether the key goes).

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
- `tests/test-lint-agreement.sh` gets a list `frozen_ps1`, one path per line relative to the root, and a function
  `frozen <root>` that lists every such file under `<root>` with
  `find "$r" \( -path "$r/.git" -o -path "$r/tmp" \) -prune -o -type f \( -iname '*.ps1' -o -iname '*.psm1' -o -iname '*.psd1' \) -print`,
  untracked files included, and for each path not on the list prints on standard error exactly
  `FAIL: <path> is a new PowerShell file; the PowerShell files are frozen (decision record 0004): write it in bash`
  and returns 1 when it printed any. A listed path that no longer exists is not a failure. The file's main body runs
  `frozen "$root"` after `check "$root"` (no new process, bug #270); `check` itself does not call it, so the sourced
  cases keep their scratch trees.
- *How the list is taken*: at implementation time, as the first change, the implementer pastes the sorted output of
  `git ls-files '*.ps1' '*.psm1' '*.psd1'` run on the branch's base commit (`git merge-base HEAD origin/main`) and
  nothing else; 54 lines at d3fc83a. "How verified" names the base commit and the count; the code reviewer compares
  the list with that command's output on the same commit. A `.ps1` that `main` gains after the base commit makes the
  lint fail after a rebase, which is the freeze working.
- The twin rules go, because they demand the opposite: the loop that prints `tests/<x>.sh has no PowerShell twin
  tests/<x>.ps1`, the list `twin_exceptions` with the two texts about it, and the loop that prints `scripts/<x>.sh has
  no PowerShell twin scripts/<x>.ps1`. The README list rules stay, and so does the OK line `OK: lists and twins agree`.
  The header comment of the file and the comment of the lint section say: the README lists every smoke file, and no
  PowerShell file is added (iteration 65).
- Iteration 57's section (`Select-ExactKeys`) is unchanged: it reads the frozen files only. The twin rule of the check's
  map (`tests/lint.sh` rule 5, "twins select the same steps") applies only where both twins exist and is unchanged.

**6. The required check: what this repository's text and code do, and what the maintainer does.** The ruleset of
`main` is changed by the maintainer by hand; no code of this iteration changes it. The pull request says, in its own
section `## Ruleset`, the change to make: add the status check `Git Bash scripts smoke tests` (the final job; never a
part's name, iteration 66 decision 8) to the required checks of the ruleset on `main`, after this pull request is
merged (so that open pull requests without the job are not held), and names the run ids of decision 7's measurement.
Those ids are measured on the pull request's own runs, never taken from this spec.

**7. The Git Bash jobs become blocking, only after measured green runs within the budget** (iteration 64 decision 4,
iteration 66 decision 8). Its changes:

- `.github/workflows/ci.yml`, job `smoke-gitbash-part`: its three comment lines become the two lines
  `    # The bash steps in Git Bash on Windows runners, in parts (iterations 64 to 66, decision record 0004); the job` and
  `    # smoke-gitbash below carries the required name and fails unless every part succeeded.`; the check step's
  `continue-on-error: true` is removed; `timeout-minutes` is 3 times the longest part's job time on the first run that
  meets the rule below, rounded up to whole minutes, at most 360. Its name, matrix, lists and run line stay.
- Job `smoke-gitbash`: its comment line is replaced by the one line
  `    # Required check: the ruleset on main requires this name; renaming it blocks every pull request.` directly above
  `    name: Git Bash scripts smoke tests`; `needs`, `if: always()`, `runs-on`, `timeout-minutes: 5` and its step stay.
- `tests/test-ci-parts.sh` rule 10a: the run step's step has `shell: bash` and no `continue-on-error:` line, and a line
  of the part job whose key (after the indent and `- `) is `continue-on-error:` gives `<what>` `a continue-on-error:
  line`; the run step's text becomes `the run step is not a run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY"
  $CHECK_SELECT ${{ matrix.only }} in a step with shell: bash and no continue-on-error`. Rule 10b wants
  `    name: Git Bash scripts smoke tests` in place of today's name. The header comment says the parts "block" (not "do
  not block"), "no continue-on-error", and that the final job is the required check `Git Bash scripts smoke tests`.
- `tests/lint.sh` (the implementer's change, decision 7 only): the name `Git Bash scripts smoke tests` joins the three
  required names in the loops at lines 1408 and 1414 and in the heredoc of rule 4; the comment count is 4, with the text
  `(exactly 4 expected, one per required job)`; the comments at lines 1546 and 1715 say "four".
- README, `## Developing nightmill`: "and a further job, `Git Bash smoke tests (Windows, not blocking)`, fails unless
  every part succeeded; it is not a required check, and a failing step shows in its part's summary without failing the
  part;" becomes "and the required check `Git Bash scripts smoke tests` is a final job that fails unless every part
  succeeded; a failing step fails its part;", and "(decision record 0004, step 1)" in the same sentence becomes
  "(decision record 0004)".
- `.claude/CLAUDE.md`, rule "CI and merging": "a PR merges only when the lint and both smoke-test jobs pass" becomes
  "a PR merges only when the lint and the three smoke-test checks (bash, PowerShell, Git Bash) pass".

**The rule (closed; no other budget and no other exception applies).** The pull request changes `ci.yml` and
`tests/check.sh`, shared paths, so every part runs its whole list. Decision 7 lands only when iteration 66 decision 2
holds, with `continue-on-error` removed and the new name, on the final commit of the pull request in two full runs (the
run its push starts and one re-run, `gh run rerun <id>`): every part's check step log ends
`SELECTED CHECKS PASSED (<k> of <M> steps; the full check has not run)` with the `<k>` adding up to 47; every part's
summary has `Selection: --affected ran every --within step: <reason>.`; every part's `Wall time:` is at most 14m00s
and its job time at most 17m00s; `Git Bash scripts smoke tests` is `success`; the chain, from the earliest start of a
part to the completion of the final job, is at most 17m00s (`gh run view <id> --json jobs`). "How verified" gives both
run ids, each part's `Wall time:` and job time, the chain, part 7's five slowest steps, and the timeout with the job
time it comes from.

**The fallback, when the rule fails:** decision 7 does not land. The implementer takes its own changes of this decision
out again (the jobs, the lint's names and count, the README job sentence, the CLAUDE.md "CI and merging" sentence and
the changelog's last sentence stay as on `main`), and sets the tester's `tests/test-ci-parts.sh` aside with `/next`'s
stash, listed as `unmet: tests/test-ci-parts.sh (criterion 4)`. It does not rebalance or split the parts, does not
rewrite a test for time and does not fix a failing step here. It reports `partial` with criterion 4 unmet, giving the
run ids, each part's numbers, the chain, and each failing step with its first `FAIL` line. The session files the rest
(criterion 4: the jobs blocking and required after measured green runs within the budget) with `/story` as a new story
under #337, linked to #363, as the workflow's rule for a story only partly done says; the pull request says so and
leaves criterion 4 unticked. Criteria 1, 2, 3 and 5 are delivered without it. By the Facts (a chain of 19m58s to
20m56s on `main`), approving this spec as written most likely means this fallback (Left item 1).

**8. The check stays green, and what the local check on Windows costs.** `bash tests/check.sh` passes on the branch.
With decision 3 this repository's `windows` makes the local full check run the 48 bash steps in Git Bash and skip the
`ps` steps: expected 2 to 3 hours (iteration 56), at least the 4575 s of `test-lintcopy-output.sh` alone (Facts).
`--affected` is no shortcut here: the change touches `tests/check.sh` and `ci.yml`, so it runs the full check, and so
does `--quick` in effect (every bash step).

- *The tester* runs only the test files it writes, never the full check: `bash tests/lint.sh` (about 10 minutes in Git
  Bash), `bash tests/test-ci-parts.sh`, `bash tests/test-lint-agreement-cases.sh` and
  `bash tests/check.sh --only smoke-check.sh` (about 26 minutes), each in the background; `tests/smoke-check.ps1` is
  run with `bash tests/check.sh --only smoke-check.ps1`, which this machine can run.
- *The implementer*, while working, runs the same files; then the full check once, in the background, before the
  commit, and again before each later commit (a fix round). It keeps the commits few: one for the iteration, one per
  fix round. "How verified" gives the last line, the `Times:` total and the `SKIPPED:` lines.
- *When the full check is red*: a failing step whose file this iteration changes (`smoke-check.sh`, or the lint and
  what it starts) is the implementer's to fix, as for any change. Any other failing step is run once more alone with
  `bash tests/check.sh --only <step>`; when that passes (an intermittent failure, as `smoke-slot.sh` had in iteration
  66), the implementer runs the full check again and commits only on a green run. When the step fails again, the
  failure is not caused by this change: the implementer commits nothing, skips nothing, changes no reason and no
  `verification.platform`, and returns `failed` with the step and its first `FAIL` line under Left (`/next`'s rule for
  a failure not caused by the change). The session files it as a bug; #363 waits for its fix.

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
  implementer breaks each rule once in a scratch copy and sees its line; the code reviewer checks the CLAUDE.md and
  CONTRIBUTING texts against decision 2.
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
    `linux` and `3` (the note), `--only b,p` with each value (log `b,p,`, no `SKIPPED:` line);
  - in the `--affected` cases, "a shared file with a changed script" under `windows` (changed `scripts/lib/x.sh` and
    `scripts/foo.sh`): log `l,b1,b2,p1,c,` and `WIN_LINE` printed (for `p2`); "p1 with a reason" under `windows`: log
    `l,b1,` as today. The `--within` cases are unchanged (the key does not apply).
  - **`tests/smoke-validate.sh`** and `.ps1`, `== verification.platform is windows, unix or all`: unchanged, and they
    pass (each value `0 errors, 0 warnings` under `--strict`).
  - **`tests/lint.sh`**, the platform block: the description of `verification.properties.platform` contains
    `windows runs the bash tests in Git Bash`, else
    `FAIL: schema: verification.platform's description does not say windows runs the bash tests in Git Bash`; the
    existing checks stay. **`tests/smoke-check.sh`** gains
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
- Criterion 4 (only with decision 7): **`tests/test-ci-parts.sh`** only (so its fallback sets aside one file), rules
  10a and 10b pass on the checkout; the cases change: `gbcoe` becomes `'/shell: bash/a\` + `        continue-on-error: true'`
  (expect `the Git Bash parts are malformed`); a new `gbjobcoe` adds `    continue-on-error: true` after
  `    runs-on: windows-latest` (expect `the Git Bash parts are malformed (a continue-on-error: line)`); `gbfname`
  becomes `s/^    name: Git Bash scripts smoke tests$/    name: Git Bash smoke tests (Windows, not blocking)/`
  (expect `the Git Bash job is malformed`); the other cases stay. The lint's four names and count are exercised by the
  lint on the checkout; no `lint_break` is added for them (each costs a lint copy). The ruleset is the maintainer's
  (decision 6): the code reviewer checks the `## Ruleset` section and the run ids; no test reads the ruleset.
- Criterion 5: the code reviewer checks the bullet against Files touched and that `git diff origin/main --stat` touches
  only the files listed there (nothing under `scripts/`, `skills/`, `agents/`, `hooks/`, `templates/`, no `.ps1` added
  or removed); `bash tests/check.sh` is green on the branch (decision 8).
- **On the pull request's run** (the maintainer, before merging by hand): `Lint (generic, JSON, skills, shell)`,
  `bash scripts smoke tests` and `PowerShell scripts smoke tests` green (`smoke-check.ps1` runs in PowerShell part 3,
  not on this machine); with decision 7, `Git Bash scripts smoke tests` green (not yet marked Required) and the numbers
  of decision 7's rule in "How verified".

## Files touched

- `.claude/nightmill.json`: `invariants[2]` (decision 1), `verification.benchRule` (decision 2). `platform` stays
  `windows`.
- `.github/ISSUE_TEMPLATE/story.yml`, `.github/ISSUE_TEMPLATE/bug.yml`: re-rendered, one line each (decision 1).
- `.claude/CLAUDE.md`: the `Bash only` rule (decision 2); with decision 7 the "CI and merging" sentence.
- `CONTRIBUTING.md`: the rule and the CI sentence (decision 2).
- `schema/nightmill.schema.json`: the description of `verification.platform` (decision 4).
- `tests/check.sh`: line 436 and two comments (decision 3).
- `tests/smoke-check.sh`, `tests/smoke-check.ps1`: the cases of criterion 2; `smoke-check.sh` also the `lint_break`.
- `tests/lint.sh`: the section of criterion 1, the description check of criterion 2, the section comment of
  `== the lists and the shell twins agree`; with decision 7 the required names, the count and two comments.
- `tests/test-lint-agreement.sh`, `tests/test-lint-agreement-cases.sh`: decision 5 and its cases.
- With decision 7: `.github/workflows/ci.yml` (the jobs `smoke-gitbash-part` and `smoke-gitbash`),
  `tests/test-ci-parts.sh` (rules 10a and 10b, three cases, header).
- `README.md`: the `verification` row and the platform sentence (decision 4); with decision 7 the job sentence.
- `CHANGELOG.md`, one bullet under `Unreleased`, above the bullet of iteration 66:

  ```
  - Iteration 65 (#363): the invariant Both shells becomes Bash only (decision record 0004, step 2): every script is
    bash and runs in bash on Linux and macOS and in Git Bash on Windows. The PowerShell files are frozen, not removed:
    they still ship and work, the lint fails on a new one, and it no longer asks a new bash script or smoke test for a
    PowerShell twin. verification.platform keeps its values and default, but windows now runs the bash tests in Git
    Bash and skips the PowerShell tests, as unix does; all still runs both. A Windows project now needs Git for Windows
    (which brings Git Bash) for the check, as its hooks already do. The Git Bash CI parts now fail on a failing step,
    and their final job, Git Bash scripts smoke tests, is to be made a required check of main.
  ```

  Without decision 7 the last sentence is left out.

Not touched: `templates/` (decision 4), `scripts/`, `skills/` (`skills/init/SKILL.md` included, Left item 2),
`agents/`, `hooks/`, `tests/check.ps1`, `tests/smoke-validate.*`, every other `.ps1`, `docs/decisions/`.

## Risks

- **This repository's local check on Windows gets much longer.** With `windows` it runs the 48 bash steps in Git Bash,
  2 to 3 hours by iteration 56, instead of the PowerShell steps. Decision 8 keeps the tester and the work in between on
  single files, and a step that fails twice for a reason outside this change stops the run as `failed` rather than
  being skipped. After the merge every Windows session of this repository pays that cost for a full check; `--affected`
  keeps the per-change check short where no shared path changes.
- **The Git Bash chain is over the budget** (Facts: part 7 alone 19m39s to 20m36s). Decision 7's rule then fails and
  its fallback leaves criterion 4 to a new story (Left item 1).
- **A Windows project without Git for Windows** gets no bash tests from its check; it already lacked the hooks. The
  changelog names the need.
- **The init question still tells a new project that `windows` runs the PowerShell tests** until #364 (Left item 2).
- **Blocking parts make every pull request that changes a shared path wait for about 20 minutes of Git Bash**; decision
  7 lands only within 17 minutes, and `--within` keeps the others short.
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
- Changing the ruleset (the maintainer's hand step); rebalancing, adding or splitting the Git Bash parts, or rewriting a
  test to make it faster (iteration 66's unfinished rounds).
- Fixing a bash step that fails in Git Bash, or any skip list for Windows.
- macOS in CI (#156), PowerShell 7 (#155), anything in `scripts/`.

## Left

1. **The Git Bash chain is over the budget on `main` today (needs the maintainer).** Every step is green in Git Bash,
   but in both push runs since iteration 66 part 7 took 19m39s and 20m36s against 14m00s, and the chain 19m58s and
   20m56s against 17m00s (Facts). Iteration 66 ended with its own criterion 3 unmet: PR #384 left the rebalance and the
   rewrites to later rounds, #382 is closed, and no story holds the rest. So decision 7's rule most likely fails, and
   the fallback files criterion 4 as a new story. The maintainer's choice, before approving: (a) a story that finishes
   iteration 66's work (a rebalance of part 7 by its decision 5, its decision 4 rewrites) merged before #363's `/next`,
   so that the rule can be met here, or (b) criterion 4 split off #363 now. **Approving the spec as written accepts
   the fallback.**
2. **`skills/init/SKILL.md` question 8** ("`windows` (the check runs the PowerShell tests)") becomes wrong with this
   iteration. Out of scope here (no skill changes); iteration 67 (#364, decision 4) changes it and checks first that
   this iteration's schema text is on `main`.
