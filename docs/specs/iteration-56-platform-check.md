# Iteration 56: the platform chosen in /init decides which test family the local check runs

Status: draft, awaiting approval (#307)

Story #307, epic #306 (platform support). On Windows the bash tests run in Git Bash, fail there for reasons that are
not product bugs (#300, #302, #303, #304) and make the full check take 2 to 3 hours; CI already runs each family on its
own platform. A new key, `verification.platform` (`windows`, `unix` or `all`, default `all`), says once which platform
the project runs on. `/nightmill:init` asks for it as its eighth question, with the detected platform as the proposed
default. `tests/check.sh` reads it: with `windows` it skips every bash test step and runs the PowerShell tests, with
`unix` it skips every PowerShell test step and runs the bash tests, and in both cases it prints one `SKIPPED:` line for
the family it left out. The lint and the two `claude` steps belong to neither family and run on both. Without the key,
or with `all`, the check runs exactly as today. `--only` names steps explicitly and ignores the key, and CI runs
`tests/check.sh` only through `--only`, so CI is unchanged. Changes `tests/check.sh`, `tests/smoke-check.sh`,
`tests/smoke-check.ps1`, `tests/smoke-validate.sh`, `tests/smoke-validate.ps1`, `tests/lint.sh`,
`schema/nightmill.schema.json`, `templates/nightmill.example.json`, `skills/init/SKILL.md`, `README.md`,
`CHANGELOG.md` and this repository's `.claude/nightmill.json` (it gets `"platform": "windows"`, the maintainer's
decision). `tests/check.ps1`, `scripts/validate-config.*` and `.github/workflows/ci.yml` do not change.

## Story trigger and manual check

**This is a story trigger**: "a new, renamed or removed config key". One key is added, and none is renamed or removed:

- `verification.platform`: string, `enum` `["all", "windows", "unix"]`, `default` `"all"`. Schema text, exactly:
  `"The platform the project runs on, for a check command that reads it; nightmill's own tests/check.sh does. windows
  runs the PowerShell tests and skips the bash tests (Git Bash on Windows counts as windows); unix (Linux or macOS)
  runs the bash tests and skips the PowerShell tests; all runs both. The lint and claude plugin validate and test run
  on every platform. The check lists what it skipped; --only ignores this key. /nightmill:init proposes the detected
  platform."`

It goes into `schema/nightmill.schema.json` (in `verification.properties`, after `checkJobs`), into
`templates/nightmill.example.json` (`"platform": "all"`, after `"checkJobs": 4`) and into the README's configuration
table (the `verification` row). **Compatible** (ticked): the previous version reads a config with the key unchanged. The
schema says "Unknown keys are ignored", `scripts/validate-config.*` validate against the schema of their own version
(the previous version's validator reports at most a warning for an unknown key, never an error), and no script of the
previous version reads `verification.platform`. No slot marker changes.

- *A change to the status flow or who sets a status*: no. No status, no board call and no decision record change;
  `docs/decisions/` 0001 to 0003 stay as they are.
- *A change to the slot marker format*: no. No script in `scripts/` changes.

Because it is a story trigger, `/next` does not enable auto-merge on its pull request; the maintainer merges it.

**The manual check applies**: `skills` is in `verification.manualCheckPaths`, and `skills/init/SKILL.md` changes. The
issue's own Verification asks for it; its steps are under Tests. No path under `agents` or `hooks` changes.

**Both shells** (invariant ticked): no script in `scripts/` changes. `tests/check.sh` is the one runner in both shells
(`tests/check.ps1` passes its parameters to it through Git's bash, iteration 42 decision 8), so the platform is read
once, in bash, and `tests/check.ps1` needs no parameter of its own. `tests/smoke-check.sh` and `tests/smoke-check.ps1`
get the same new case with the same expected text (the `.ps1` through `tests/check.ps1`), and
`tests/smoke-validate.sh` and `tests/smoke-validate.ps1` the same validator case.

**Hot file.** `schema/nightmill.schema.json` is in `parallel.hotFiles`, and `parallel.doNotPair` forbids pairing this
story with any other that changes the schema.

## Facts this rests on

Read on `main` at 922d5f0 (bug #304 merged, 0.7.0 released) on 2026-11-12; #155, #156 and #200 read with
`gh issue view` (read only).

- **The step list of `tests/check.sh`** (between `# steps: begin` and `# steps: end`): `add lint lint`; 46 lines
  `add bash <file>` (from `smoke-json.sh` to `test-restricted-path-git.sh`); 25 lines `add ps <file>` (from
  `smoke-slot.ps1` to `smoke-history.ps1`). After the block the two steps of kind `claude`, `claude plugin validate`
  and `claude plugin test`, are added by code. Kinds are `lint`, `bash`, `ps` and `claude`; a fixture step of
  `NIGHTMILL_CHECK_STEPS` carries its kind in the third field (bash when empty).
- **Skipping today.** `k_skip[i]` holds a reason; a selected step with a reason does not run, and at the end the check
  prints `SKIPPED: <reason>` once per distinct text, in list order. Without `pwsh` or `powershell` every `ps` step gets
  `PowerShell smoke tests (no pwsh or powershell)`; the `claude` steps get `claude plugin validate (claude is not
  installed)` and `claude plugin test not available`. A skipped step is not a failure: the verdict stays
  `ALL CHECKS PASSED` when every step that ran passed. Decision 0001: "The check command runs what the machine can run
  and lists what it skipped; CI is the full run."
- **The modes today.** Full: every step. `--quick`: the steps of kind `lint` and `bash`; steps it leaves out are not
  listed as skipped (iteration 42 decision 6), but a selected step with a reason is. `--only a,b`: exactly the named
  steps (iteration 42 decision 7); a named `ps` step without PowerShell is listed with today's `SKIPPED:` line.
- **The config is read** with `scripts/lib/json.sh` (`json_load .claude/nightmill.json`, `json_has`, `json_get`) from
  the repository root (`cd "$(dirname "${BASH_SOURCE[0]}")/.."`), only in the block that computes the limit L, and
  only when `--jobs` is not given. A missing or unreadable file gives the default without a note; a bad
  `verification.checkJobs` gives a note on standard error and the default.
- **`tests/check.ps1`** finds `bash` with `Get-Command bash` and runs `tests/check.sh` with the translated parameters.
  So on Windows the runner itself is Git's bash, whatever the platform key says; the key decides which test steps run,
  not which shell runs the runner.
- **The lint is bash** (`tests/lint.sh`) and runs on Windows in Git Bash today, as a step of its own (`add lint lint`).
  Four PowerShell steps (`smoke-release.ps1`, `smoke-validate.ps1`, `smoke-check.ps1`, `test-lintcopy-output.ps1`) also
  run the lint on a copy of the repository through Git's bash (iteration 55, Facts). By their titles and the tests they
  added, #300 and #304 are failures of a bash test step (`test-baseconfig-pathconv.sh`) and of a PowerShell step that
  unpacks with `tar` (`smoke-slot.ps1`, `test-smoke-slot-tar.ps1`), not of the lint step; #302 and #303 were not read
  for this spec.
- **CI** (`.github/workflows/ci.yml`) runs `tests/check.sh` in exactly two lines, both with `--only`:
  `run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" --only <the 45 bash files but smoke-json.sh>` (job
  `bash scripts smoke tests`, Ubuntu) and
  `run: bash tests/check.sh --powershell powershell --summary "$GITHUB_STEP_SUMMARY" --only ${{ matrix.only }}`
  (the four PowerShell parts, Windows). The lint job runs `bash tests/lint.sh`, `smoke-json.sh` runs directly, and
  `validate` runs `claude plugin validate` and `claude plugin test` directly. The lint pins both `--only` lines
  (`== the check runs every smoke script`, iteration 42 decision 11 rule 6 as changed by iteration 55 decision 5, and
  `tests/test-ci-parts.sh` rule 2) and fails on any other line that runs a smoke file.
- **The schema** describes `verification.checkJobs` with `type`, `minimum`, `default` and a description that says "for
  a check command that reads it; nightmill's own tests/check.sh does". `scripts/validate-config.sh` and `.ps1` support
  `enum` (header comments; `.ps1` line 139), as `parallel.controlMode` (`["off", "report", "apply"]`, default `off`)
  shows; no validator code is needed for a new enum key.
- **`/nightmill:init`** detects without asking (step 1, a table of value and source), then asks one question per
  message in a fixed numbered order, each proposing the detected value and asking "keep" or "change"; a question is
  skipped when the existing config holds the key; "defaults" takes the remaining proposals; a key left empty is
  deleted. The lint (`== init skill keeps the install-chat steps`) pins the seven questions `1.` to `7.` by their bold
  names. The skill says "Every step uses `gh` and `git` alone, so it works in either shell"; its memory detection
  already names a PowerShell and a bash source.
- **This repository's `.claude/nightmill.json`** has `verification.check` `bash tests/check.sh` and `checkJobs` 4, and
  no platform. CI checks out the same file.

## Decisions

**1. The key: `verification.platform`, `all` | `windows` | `unix`, default `all`.** It sits beside `checkJobs` because
it, too, is read by the check command and means nothing to the skills. `unix` covers Linux and macOS, which share the
bash family (#156 will test macOS in CI). `all` is the default and means today's behaviour, so the schema has a real
default and an absent key and `all` behave the same. `/init` only proposes `windows` or `unix`; a user who wants both
families answers `all` or leaves the answer empty (the key is then deleted).

**2. The families.** In `tests/check.sh` and its fixture mode, by kind:

| Kind | Family | `windows` | `unix` | `all` or no key |
|---|---|---|---|---|
| `bash` (46 real steps, `smoke-json.sh` to `test-restricted-path-git.sh`) | bash | skipped | runs | runs |
| `ps` (25 real steps, `smoke-slot.ps1` to `smoke-history.ps1`) | PowerShell | runs | skipped | runs |
| `lint` (`tests/lint.sh`) | neither | runs | runs | runs |
| `claude` (`claude plugin validate`, `claude plugin test`) | neither | runs | runs | runs |

The lint stays on Windows: the maintainer decided that `tests/lint.sh` runs on every platform, `windows` included. It
is the check of the repository's text (the private word list, JSON, the skills, the
spec template, the wiring), not a test of the bash scripts, and a commit that breaks it is refused by the required lint
job, so skipping it locally would let "never commit red" fail only in CI. It runs today in Git Bash and is not among
the failures that led to this story (Facts), and the PowerShell steps run it on a copy anyway. `tests/check.ps1` keeps
running the check through Git's bash: the runner is not a test. The `claude` steps test the plugin, not a shell.

**3. Where the key acts and what it prints.** After the step list is built (real or fixture) and before the
selection, when the mode is full or quick, the check reads `verification.platform` from `.claude/nightmill.json` at
the repository root with `json_load`, `json_has` and `json_get` (once, whether or not `--jobs` is given), and sets
the reason of every step of the skipped family:

- `windows`: every step of kind `bash` gets the reason `bash tests (verification.platform is windows)`;
- `unix`: every step of kind `ps` gets the reason `PowerShell tests (verification.platform is unix)`, replacing the
  reason `PowerShell smoke tests (no pwsh or powershell)` or a fixture reason the step had;
- `all`, an absent key, a missing or unreadable file: no reason is set, without a note;
- any other value (another string, a number, `null`, an array): one line on standard error,
  `check: verification.platform must be windows, unix or all; running both families`, and no reason is set.

The existing end of the run then prints it: one line, after the `Times:` block, among the other `SKIPPED:` lines in
list order, `SKIPPED: bash tests (verification.platform is windows)` or
`SKIPPED: PowerShell tests (verification.platform is unix)`. A `windows` run on a machine without PowerShell keeps
`SKIPPED: PowerShell smoke tests (no pwsh or powershell)` for the `ps` steps, so it prints both lines. The header, the
`Times:` block (it lists only steps that ran), the `--summary` text and the verdict lines are unchanged: a run whose
steps that ran all passed prints `ALL CHECKS PASSED`, as a run without PowerShell does today. The header comment of
`tests/check.sh` gains three lines naming the key, the two families and that `--only` ignores it.

**4. `--quick`** selects the steps of kind `lint` and `bash` as today, and then the key applies: with `windows` the bash
steps are skipped and listed, so a quick check on Windows runs the lint alone and prints
`SKIPPED: bash tests (verification.platform is windows)`; with `unix` nothing changes (the `ps` steps are left out by
the quick mode, not skipped, and are not listed). The quick header and its two last lines stay word for word (the
skills recognise `check: QUICK`, iteration 42 decision 10). A quick mode that runs the PowerShell tests on Windows is
not part of this story (Left).

**5. `--only` ignores the key.** A step named with `--only` runs whatever `verification.platform` says, and the key is
not read, so no note is printed for a bad value either. Naming a step is an explicit choice, as `--jobs` overrides
`checkJobs`; it lets a Windows user run one bash test on purpose
(`bash tests/check.sh --only test-baseconfig-pathconv.sh`). Today's reasons still apply under `--only` (no PowerShell,
no `claude`).

**6. CI is unchanged.** Every line of `ci.yml` that runs `tests/check.sh` passes `--only` (Facts), so by decision 5 CI
never reads the key, whichever value a repository's config holds; the lint already fails when that line loses `--only`
or another line runs a smoke file directly. No job, step, name, list, runner or timeout changes; the lint job and the
`validate` job do not run `tests/check.sh`.

**7. This repository's config gets `"platform": "windows"`.** The maintainer decided: this repository's
`.claude/nightmill.json` sets `"platform": "windows"` in its `verification` object, after `"checkJobs": 4`. The
implementer adds it in the same change as the schema key, so the file validates: the lint already validates
`.claude/nightmill.json` with `scripts/validate-config.sh --strict` (`tests/lint.sh`, the loop over
`templates/nightmill.example.json .claude/nightmill.json`), and with `--strict` an unknown key is a warning that
fails. The
consequence the maintainer accepted: a contributor who uses this repository from Linux or macOS gets the bash family
skipped by the local check until they change the key in their own checkout; CI is unaffected because `--only` ignores
the key (decisions 5, 6). The change touches a path under `.claude/`, which is never auto-merged (the existing rule of
the workflow skill and of `/next`), so the implementation pull request is merged by hand, as the story trigger already
requires. The CHANGELOG bullet and the README row describe the key's default (`all`), not this repository's setting.

**8. `/nightmill:init`: detect, then a question 8.**

- Step 1 gains a row: `verification.platform` from the platform Claude Code runs on: Windows (`win32`, also in Git
  Bash, MSYS or Cygwin) is `windows`; Linux and macOS (`linux`, `darwin`) are `unix`. When the platform is not known,
  `uname -s` in bash (`MINGW*`, `MSYS*`, `CYGWIN*` give `windows`; anything else `unix`) or `$env:OS -eq 'Windows_NT'`
  in PowerShell.
- Step 2 gains, after `7. **ports**`, the question
  `8. **platform** (`verification.platform`): `windows` (the check runs the PowerShell tests) or `unix` for Linux and
  macOS (the bash tests); `all` runs both, for a project worked on from both; read only by a check command that reads it`.
  It proposes the detected value as every question does.
- The general rules hold for it unchanged: it is skipped when the existing config holds `verification.platform`
  (whatever its value), so a configured project is asked nothing and an older config without the key is asked only
  this question; "defaults" takes the detected value; an empty answer deletes the key (the check then runs both
  families). The answer is written into `.claude/nightmill.json` with the other values on the **Config** line, which the
  validator checks as today (an answer other than the three values is an `enum` error to fix before the plan).
- Step 2's opening and the lint keep "one question per message, in this order"; the lint's list gains `platform` as
  question 8.

**9. The validator** needs no code: the `enum` in the schema is checked by `scripts/validate-config.sh` and `.ps1` as
for `parallel.controlMode`. A smoke case in both shells pins it (Tests).

**10. The lint.** `== init skill keeps the install-chat steps`: the question list gains `platform`, so the loop checks
`8. **platform**`, and its comment says eight questions. `== the check runs every smoke script` gains four greps,
each failing with `FAIL: <file> does not mention <word>`: `schema/nightmill.schema.json` mentions `"platform"`,
`templates/nightmill.example.json` has `verification.platform` `all` (read with `json_get`; else
`FAIL: templates/nightmill.example.json does not mention verification.platform all`), and `README.md`,
`skills/init/SKILL.md` and `tests/check.sh` mention `verification.platform`.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | `/init` asks which platform the project runs on, proposes the detected one as the default, and stores the answer in `.claude/nightmill.json` | Decision 8; Decision 10 (the lint pins question 8) |
| 2 | On Windows the check runs the PowerShell tests only | Decisions 2, 3 (`windows` skips every `bash` step; lint and `claude` steps are no test family); decision 7 (a check run on this repository, which sets `windows`, skips the bash family and prints its `SKIPPED:` line) |
| 3 | On Linux and macOS the check runs the bash tests only | Decisions 1, 2, 3 (`unix` skips every `ps` step) |
| 4 | The check prints what it skipped | Decision 3 (the `SKIPPED:` lines), decision 4 (`--quick`) |
| 5 | Without the new key the check behaves as it does today, so an older configuration keeps working | Decision 1 (`all` is the default), decision 3 (absent, `all`, unreadable: nothing set), decision 5; Story trigger (Compatible) |
| 6 | CI is unchanged and runs both test families | Decisions 5, 6 |
| 7 | The new key is in the schema with a description and a default, in the example configuration and in the README's configuration table | Story trigger (the schema text), Files touched (example, README), decisions 9, 10; decision 7 (the lint validates this repository's configuration with the key) |

## Tests

**`tests/smoke-check.sh` and `tests/smoke-check.ps1`**, a new case `== the platform from the config`, after
`== the limit from the config`, in the same throwaway repository `$repo` (the copy of `tests/check.sh`,
`tests/check.ps1` and `scripts/lib/`) with its own `.claude/nightmill.json`; the `.ps1` runs `tests/check.ps1` with its
parameters (`-Quick`, `-Only`), the expected text is the same. A steps file of four fixture steps `l` (kind `lint`),
`b` (`bash`), `p` (`ps`) and `c` (`claude`), each appending its name to one log, run with `--jobs 1`.

- Criterion 2: `"platform": "windows"`: the log is exactly `l`, `p`, `c`; the output has the line
  `SKIPPED: bash tests (verification.platform is windows)` once and no `== b` section; the last line is
  `ALL CHECKS PASSED`; exit 0.
- Criterion 3: `"platform": "unix"`: the log is exactly `l`, `b`, `c`; the line
  `SKIPPED: PowerShell tests (verification.platform is unix)` once; `ALL CHECKS PASSED`; exit 0. The same with `p`
  given the fixture reason `no pwsh here`: the platform's line is printed and `SKIPPED: no pwsh here` is not.
- Criterion 4: with `windows` and `b` given the fixture reason `other reason`, the platform's line is printed and
  `SKIPPED: other reason` is not; with `windows` and `p` given the reason `no pwsh here`, both
  `SKIPPED: bash tests (verification.platform is windows)` and `SKIPPED: no pwsh here` are printed, in list order.
- Criterion 5: `"platform": "all"` and no key: the log is `l`, `b`, `p`, `c`, no `SKIPPED:` line, and the two
  outputs are equal line for line; standard error is empty in both. `"platform": "linux"` and `"platform": 3`: the
  note `check: verification.platform must be windows, unix or all; running both families` on standard error and the
  log `l`, `b`, `p`, `c`. The existing cases of the file pass unchanged (their configs have no key).
- Criterion 4 (quick): `--quick` with `windows`: the log is `l` only, the line
  `SKIPPED: bash tests (verification.platform is windows)`, the last line
  `QUICK CHECK PASSED (the lint and the bash smoke tests only; the full check has not run)`. `--quick` with `unix`:
  the log is `l`, `b`, no `SKIPPED:` line.
- Criterion 6: `--only b,p` with `windows` and with `unix`: the log is `b`, `p` both times, no `SKIPPED:` line, the
  last line `SELECTED CHECKS PASSED (2 of 4 steps; the full check has not run)`; with `"platform": "linux"` and
  `--only b` no note on standard error.

**`tests/smoke-validate.sh` and `tests/smoke-validate.ps1`**, one case (criterion 7): a copy of a valid config with
`"platform": "windows"` validates with 0 errors; with `"platform": "linux"` the validator exits non-zero and its
error line names `verification.platform` (the message is the validator's existing `enum` text, the same in both
shells).

**`tests/lint.sh`** (criteria 1 and 7): the rules of decision 10. Break each once in a scratch copy and see it fail:
rename `8. **platform**`, remove `"platform"` from the schema, set the example's value to `unix`, remove the word from
the README row. This repository's `.claude/nightmill.json` with `"platform": "windows"` passes the lint's existing
`scripts/validate-config.sh --strict` step (criterion 7, decision 7); a scratch copy with `"platform": "linux"` fails
it.

**CI** (criterion 6): the pull request's run shows the same jobs and the same required checks as `main`'s, the bash job
running its 45 steps and the four PowerShell parts their 25, with no `verification.platform` line in any log; `ci.yml`
has no diff.

**The full check on the branch** (criterion 2, decision 7): `bash tests/check.sh` on the branch, with this
repository's committed `"platform": "windows"`, runs the lint, the PowerShell steps and the `claude` steps, skips the
bash family, prints `SKIPPED: bash tests (verification.platform is windows)` and ends `ALL CHECKS PASSED`; the
implementer puts that line and the total of the `Times:` block into "How verified". The bash family is run once as
well, with `--only` naming its steps or with a scratch change of the key to `all` that is not committed, and is green.

**Manual check by the maintainer** (`skills/init/SKILL.md` changes): in a throwaway project (not this repository),
start `claude --plugin-dir <a separate checkout of the branch>` and run `/nightmill:init`:

1. With no `.claude/nightmill.json`: question 8 asks for the platform and proposes `windows` on Windows (in a session
   started from Git Bash as well) or `unix` on Linux or macOS; keep it, confirm the plan, and see
   `"platform": "<that value>"` under `verification` in the written file and `0 errors` in the report's Config row.
2. Remove only `verification.platform` from the file and run `/nightmill:init` again: it asks that question alone.
3. Run it a third time: it asks nothing and says "already set up, nothing to change".

## Files touched

- `tests/check.sh`: decisions 3 to 5 (the platform read, the reasons, the note) and three lines of its header comment.
- `tests/smoke-check.sh`, `tests/smoke-check.ps1`: the case `== the platform from the config`.
- `tests/smoke-validate.sh`, `tests/smoke-validate.ps1`: the validator case of Tests.
- `tests/lint.sh`: decision 10.
- `schema/nightmill.schema.json`: `verification.platform` (Story trigger), after `checkJobs`.
- `templates/nightmill.example.json`: `"platform": "all"` after `"checkJobs": 4`.
- `.claude/nightmill.json`: `"platform": "windows"` after `"checkJobs": 4` (decision 7), in the same change as the
  schema.
- `skills/init/SKILL.md`: decision 8 (the detect row, question 8).
- `README.md`: the `verification` row of the configuration table ends `..., how many steps of the check run at once
  (`checkJobs`, default 4, for a check that reads it), and which test family the check runs (`platform`: `windows`,
  `unix` or `all`, default `all`, for a check that reads it)`; under `## Developing nightmill`, the paragraph after the
  test list gains: with `verification.platform` set, `tests/check.sh` runs only that platform's tests (the PowerShell
  tests on `windows`, the bash tests on `unix`), always the lint and the `claude` steps, and lists the family it skipped;
  `--only` ignores the key, and CI runs both families through `--only`. The `/nightmill:init` paragraph's list of what it
  asks is not itemised and does not change.
- `CHANGELOG.md`, one bullet under `Unreleased`:

  ```
  - Iteration 56 (#307): the platform chosen in /init decides which test family the check runs. A new key,
    verification.platform (windows, unix or all, default all), is asked by /nightmill:init as its eighth question,
    with the detected platform proposed. tests/check.sh runs the PowerShell tests only on windows and the bash tests
    only on unix, always the lint and claude plugin validate and test, and lists the family it skipped; without the
    key it runs both, as before. --only ignores the key, so CI is unchanged and runs both families.
  ```

Not touched: `tests/check.ps1` (it passes no platform; the runner reads the key), `scripts/validate-config.*`
(decision 9), `.github/workflows/ci.yml` (decision 6), `CONTRIBUTING.md`.

## Risks

- **A committed `windows` on a mixed team.** The key is project-wide in a tracked file, but the platform is a property
  of each machine. A contributor on the other platform gets a full check that skips the tests their machine can run.
  The `SKIPPED:` line says why, `--only` still runs any step, and CI runs both families; the init question names `all`
  for such a project.
- **Fewer tests before a commit.** On Windows the local check no longer runs the bash tests, so a bash change can pass
  locally and fail in CI. That is the story's intent and decision 0001's rule (CI is the full run); the check fix
  rounds of `/next` and `/fix` handle a red CI as today.
- **Regenerating fixtures on Windows.** `UPDATE_*_FIXTURES=1` makes a bash smoke test rewrite a fixture; with
  `windows` those steps are skipped, so a maintainer regenerates them with `--only smoke-status.sh` (and the like).
- **Another reader of the key.** A project's own check command does not read the key unless it implements it; the
  schema text says "for a check command that reads it", as for `checkJobs`.

## Size estimate

`M`: about 190 changed lines. `tests/check.sh` about 25, `smoke-check.sh` and `.ps1` about 110 together,
`smoke-validate.sh` and `.ps1` about 16, `tests/lint.sh` about 8, the schema and the example 2, this repository's
`.claude/nightmill.json` 1, `skills/init/SKILL.md` about 8, README about 6, CHANGELOG 5.

## Not done

- Any change to which tests CI runs, its jobs, names, lists, parts or timeouts (out of scope).
- Fixing #302, #303 or #304, or making any bash test pass in Git Bash (out of scope).
- Shells other than PowerShell and bash; separate values for Linux and macOS.
- A command-line option to choose the platform for one run (`--only` covers running a single step of the other
  family); a per-machine setting outside the tracked config.
- A quick mode that runs the PowerShell tests on Windows (decision 4; see Left).
- Skipping the lint or the `claude` steps on any platform.
- Any change to the skills other than `/nightmill:init`, to the agents or to the hooks.

## Left

- **A quick check on Windows** runs only the lint after this story (decision 4). A quick mode that runs a short set of
  PowerShell tests on Windows would be a story of its own (it changes the quick mode's words, which the skills read).
