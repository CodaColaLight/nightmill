# Iteration 72: the load library is tested in-process, and its smoke tests keep only their end-to-end cases

Status: draft, awaiting approval (#346)

Story #346, epic #337 (fast verification loop). This iteration proves the pattern on one library, `scripts/lib/load.sh`,
as the story's agent note says. The rest of `scripts/lib` is left to follow-up stories (Left). A new test,
`tests/test-lib-load.sh`, sources `scripts/lib/json.sh` and `scripts/lib/load.sh` and calls `load_settings`,
`room_settings`, `control_settings`, `load_measure` (on a fixture) and `load_suggest` directly. It needs no repository
and starts no script. The cases of `tests/smoke-load.sh`, `tests/smoke-room.sh` and `tests/smoke-control.sh` that only
repeat those functions' cases are removed, each with a comment that names the replacing section. Changes
`tests/test-lib-load.sh` (new), `tests/smoke-load.sh`, `tests/smoke-room.sh`, `tests/smoke-control.sh`,
`tests/check.sh` (one step line, one map line), `CHANGELOG.md`, and `.github/workflows/ci.yml` only under the condition
of decision 6.

## Story trigger and manual check

**Not a story trigger.** No status and no one who sets a status changes. No config key is added, renamed or removed.
No slot marker changes, and no file under `scripts/` changes. **The manual check does not apply**:
`verification.manualCheckPaths` is `skills`, `agents`, `hooks`, and no file under them changes.

**Shells.** The story's "in both shells" predates iteration 68 (#365). That iteration removed the PowerShell scripts,
their twins and the PowerShell CI parts. The invariant is now **Bash only** (decision record 0004), so "both shells"
here means bash on Linux and macOS and Git Bash on Windows. The new test is a bash step of `tests/check.sh`. CI runs it
on Ubuntu and in a Git Bash part on Windows. No `.ps1` file is added or changed. The steps involved are
`smoke-load.sh`, `smoke-room.sh`, `smoke-control.sh`, the new `test-lib-load.sh`, and the lint.

## Facts this rests on

Read and run on `spec/72-lib-in-process-tests` at 24b3699, equal to `main`, on 2026-11-28. The machine was Linux with
4 processors.

- **What `scripts/lib` holds.** Four sourced bash files: `json.sh`, `ledger.sh`, `load.sh`, `baseconfig.sh`. Seven awk
  programs are run with `awk -f`: `json.awk`, `stages.awk`, `history.awk`, `status.awk`, `dashboard.awk`,
  `models.awk`, `validate.awk`.
  - `json.sh` is already tested in-process: `tests/smoke-json.sh` sources it and starts no script.
  - `baseconfig.sh` needs a repository (`git show origin/HEAD:...`).
  - `load.sh` has five public functions, and none of them needs a repository. `load_measure` reads
    `NIGHTMILL_LOAD_FIXTURE` when it is set. The settings functions read `JSON_FLAT`. `load_suggest` is arithmetic on
    the `LOAD_` variables.
- **How the three smoke tests run.** Each case runs `scripts/load.sh`, `room.sh` or `control.sh` as a new `bash`
  process in a throwaway git repository. `load.sh` and `control.sh` also start `slot.sh`, which reads the base config
  with `git show`. Many cases only test the library:
  - `smoke-load.sh`: "unusable config values fall back" makes 12 runs (10 bad values, null, absent). "The suggestion
    and its reason" makes 14 runs (scenarios b, c, d, e, f, g, i, each human and porcelain). "An unusable fixture"
    makes 8 runs. The rounding case `half` makes 1.
  - `smoke-room.sh`, section 9: 15 `bad_value` runs plus "null values" and "absent keys".
  - `smoke-control.sh`, section 12: 4 `controlMode` runs, 11 `bad_value` runs, plus "null values", "null mode" and
    "absent keys".
- **Times before**, from `bash tests/check.sh --only smoke-load.sh,smoke-room.sh,smoke-control.sh --jobs 1` (its
  `Times:` block): `smoke-load.sh` 13s, `smoke-room.sh` 11s, `smoke-control.sh` 22s, total 46s.
- **No lint rule pins those cases.** `tests/lint.sh` checks only that the three smoke files exist and are wired
  (lines 987, 1017 to 1020, 1028, 1069 to 1072, 1079, 1126 to 1131). The lint also fails on a test step that no map
  line names.
- **Iteration 70** (#343) has its spec on `main` (PRs #399, #400) but is not delivered. Today a new bash step is named
  in two places of `.github/workflows/ci.yml`:
  - the Ubuntu job's list (line 44);
  - the `only:` of Git Bash part 7 (line 69, the part with the most names).

  The lint compares both with the step list. Once iteration 70 is delivered, the step list is the only list, and bash
  lines are kept in name order.

## Decisions

1. **One library: `scripts/lib/load.sh`.** Its smoke cases are the most repeated library cases that need no
   repository: about 70 process runs across three smoke tests. Another library goes in its own follow-up story (Left).
2. **The new test.** `tests/test-lib-load.sh`, bash, `set -euo pipefail`, a temporary directory made with the
   `mktemp -d "${TMPDIR:-/tmp}/nightmill-test-lib-load.XXXXXX"` template and removed by a trap. It follows the rules
   that `tests/test-lint-pipefail.sh` and `tests/test-mktemp-template.sh` check.
   - It sources `scripts/lib/json.sh` and then `scripts/lib/load.sh`. It starts no `scripts/*.sh`, runs no `git`, and
     uses only bash and awk (no `date -d`, no `jq`).
   - It calls each function in the test's own shell (never inside `$( )` for a function that sets variables), with
     standard error sent to a file.
   - For a config case it writes the JSON to a file in the temporary directory and calls `json_load` on it.
   - Each miss prints `FAIL: <section>: <what>`. The test ends with `LIB LOAD OK`.
3. **Its sections**, each headed `echo "== <section>"`. Every value and text below is the one the removed smoke case
   asserted today:
   - `load settings`: `load_settings` with `parallel` absent gives `LOAD_CEILING` 4, `LOAD_GB` 8, `LOAD_WINDOW` 10,
     and nothing on standard error. In-range values (6, 4, 30) are taken. The bad values each give the default and
     exactly one line `load: parallel.<key> must be a whole number from <low> to <high>; using <default>`:
     - `memoryPerAgentGB`: 0, -1, 8.5, 8.0, "8", true;
     - `maxSuggestedAgents`: 0, 100;
     - `loadWindowSeconds`: 1, 61.

     All three null gives the defaults and nothing on standard error.
   - `room settings`: `room_settings` for every value of today's section 9 loops, with the same warning lines (prefix
     `room`) and defaults: `roomPauseSeconds` 0, -1, 8.5, "60", true, 91; `roomMaxCpuPercent` 0, 101; `roomMinFreeMB`
     0, 1000000; `roomMaxWaitMinutes` 0, 1441; `roomCheck` "false", 0, 1. Also: all null; absent.
   - `control settings`: `control_settings` with `controlMode` "Apply", "on", 1, true gives `CONTROL_MODE` off and the
     one `must be "off", "report" or "apply"` line. Each `bad_value` of today's section 12 gives the default and its
     line. Null values and a null mode give the defaults with nothing on standard error. `controlMinAgents` 5 with
     `controlMaxAgents` 3 gives 3 for both and the `is above` line.
   - `measure`: `load_measure 3` with `NIGHTMILL_LOAD_FIXTURE` set to the smoke tests' fixtures:
     - `a` gives `LOAD_SAMPLES` 3, `LOAD_CPU` 10, `LOAD_FREE` 60000, `LOAD_TOTAL` 64000, `LOAD_FROM` fixture;
     - `half` gives `LOAD_CPU` 11;
     - `comments` gives 3 samples;
     - `nocpu` gives an empty `LOAD_CPU` and `LOAD_CPU_WHY` `sample 2 has no CPU reading`;
     - `nomem` gives `LOAD_MEM_WHY` `sample 1 has no memory reading`;
     - `one`, `two`, `cpux`, `cpu101`, `freeneg`, `total0` and a missing file each return 2, with today's message on
       standard error.
   - `suggest`: `load_suggest <busy>` with `LOAD_CEILING` 4 and `LOAD_GB` 8 and the readings of scenarios a, b, c, d,
     e, f, g, i gives today's `LOAD_SUGGEST`, `LOAD_REASON` and `LOAD_WHY`. Scenario h (`LOAD_GB` 4, `LOAD_CEILING` 6,
     fixture a, busy 1) gives 6, `ceiling`. An empty `LOAD_CPU` gives all three empty.
4. **What each smoke test keeps.** Every section heading stays; one end-to-end case stays per family; everything not
   named below as removed stays.
   - `smoke-load.sh` keeps:
     - scenario a, human and porcelain;
     - the window case;
     - scenario h with its config;
     - one `bad_value` (`memoryPerAgentGB` 0), so the warning still reaches the script's standard error;
     - the `missing` fixture (exit 2, empty standard output).
   - `smoke-load.sh` removes scenarios b to i, the other bad values, null and absent, `half`, `comments`, and the
     unusable fixtures other than `missing`.
   - `smoke-room.sh` keeps one `bad_value` (`roomPauseSeconds` 0) and the two `roomMaxWaitMinutes` "gave up" runs. The
     "gave up" runs show that the script uses the default. Sections 1 to 8, 10 and 11 do not change.
   - `smoke-room.sh` removes from section 9, each replaced by section `room settings` of `tests/test-lib-load.sh`:
     - the `bad_value` runs of `roomPauseSeconds` -1, 8.5, "60", true, 91;
     - the `bad_value` runs of `roomMaxCpuPercent` 0, 101 and of `roomMinFreeMB` 0, 1000000 (both loops);
     - the `bad_value` runs of `roomMaxWaitMinutes` 0, 1441 (the loop stays, with only its "gave up" runs);
     - the `bad_value` runs of `roomCheck` "false", 0, 1 (the loop);
     - "null values" and "absent keys".
   - `smoke-control.sh` keeps one `controlMode` value ("Apply"), one `bad_value` (`controlMinAgents` 0) and "cooldown
     default". The `is above` case in section 6 stays: it also asserts the bounds pass. Sections 1 to 11, 13 and 14 do
     not change.
   - `smoke-control.sh` removes from section 12, each replaced by section `control settings` of
     `tests/test-lib-load.sh`:
     - the `controlMode` runs of "on", 1, true;
     - the `bad_value` run of `controlMinAgents` 100 and the `bad_value` runs of `controlMaxAgents` 0, 100;
     - the `bad_value` runs of `controlCooldownMinutes` 0, 1441, 1.5, "15" and of `controlIntervalMinutes` 0, 1441, "5"
       (both loops);
     - "null values", "null mode" and "absent keys".
5. **Each removal is named.** At the place of each removed case or loop, the smoke file gets exactly one comment line
   `# In-process (iteration 72): <what was tested> is tested in tests/test-lib-load.sh, section <section>.` Here
   `<section>` is one of the five names of decision 3. A loop cut to one value says it of the values that went.
6. **The check and CI, stated by content.**
   - `tests/check.sh` gets the step `add bash test-lib-load.sh`. When the step list is in name order (iteration 70
     delivered), it goes at its place by name. Otherwise it goes directly after `add bash test-slot-low-defects.sh`, at
     the end of the list.
   - The map between `# affects: begin` and `# affects: end` gets
     `map scripts/lib/load.sh smoke-load.sh,smoke-room.sh,smoke-control.sh,test-lib-load.sh`, directly after the line
     `map scripts/lib/ledger.sh ...`.
   - The new test needs no mark (no `jq`, `nogitbash`, `alone`, `slow` or `first`).
   - If `.github/workflows/ci.yml` still names steps at implementation time, `test-lib-load.sh` is added in step-list
     order to the Ubuntu job's list and to the `only:` list that holds `smoke-load.sh`, as today's lint requires. The
     pull request then changes `.github/` and is opened without `--auto`. If iteration 70 is delivered, the workflow
     does not change.
7. **Times, before and after.**
   - The command is `bash tests/check.sh --only smoke-load.sh,smoke-room.sh,smoke-control.sh[,test-lib-load.sh]
     --jobs 1` on the same machine. Before: on the base commit, without the new step. After: on the branch, with it.
   - Each is run three times, and the median of each step's time in the `Times:` block is taken.
   - The pull request description carries a table `| step | before | after |` with the four steps and a total row
     (the new step's before is `-`), the commit of each run, and the machine (system and processors).
   - When a Git Bash CI run on the branch shows these steps in its summary, their times are added. They are not
     required.
   - The aim: `test-lib-load.sh` under 5 s on Linux, and the after total below the before total. A miss is reported in
     the table with its cause, and is not hidden.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The functions of `scripts/lib` that need no repository have tests that source the library and call them directly, in both shells | Decisions 1, 2, 3 and 6 for `load.sh`; "both shells" as in Story trigger and manual check; the other libraries in Left |
| 2 | Smoke cases that only repeat such a function's cases are removed; each removal names the in-process test that replaces it | Decisions 4, 5 |
| 3 | Every smoke script keeps at least its end-to-end cases | Decision 4 |
| 4 | The check's time for the affected steps is shown before and after | Decision 7 |

## Tests

- Criterion 1: `tests/test-lib-load.sh` with its five sections (decision 3). It is green on the branch and red if a
  function's warning text, default or result changes. It runs as a check step on Ubuntu and in Git Bash.
- Criterion 2: review of the diff. Every removed case has the comment of decision 5, and every value it asserted is
  asserted in the named section. `grep -c 'In-process (iteration 72)'` is at least 1 in each of the three smoke files.
- Criterion 3: the three smoke steps stay green. Each still has the cases decision 4 keeps, and still prints its
  `... OK` line.
- Criterion 4: the table in the pull request (decision 7). No automatic test.
- All: `bash tests/check.sh` is green, including the lint's rule that every test step is named by a map line.

## Files touched

- `tests/test-lib-load.sh`: new (decisions 2, 3). Tester.
- `tests/smoke-load.sh`, `tests/smoke-room.sh`, `tests/smoke-control.sh`: cases removed and comments added
  (decisions 4, 5). Implementer.
- `tests/check.sh`: one step line and one map line (decision 6). Implementer.
- `.github/workflows/ci.yml`: only under decision 6's condition, the name in two lists. Implementer.
- `CHANGELOG.md`, under `Unreleased`, exactly:

  ```
  - Iteration 72 (#346): the load library (`scripts/lib/load.sh`) is tested in-process in `tests/test-lib-load.sh`; the load, room and control smoke tests keep their end-to-end cases and lose the cases that only repeated it.
  ```

## Risks

- A case removed by mistake loses coverage of the script's own path, for example how it prints a warning. Decision 4
  keeps one end-to-end case per family, and decision 5 makes every removal traceable in review.
- The saving can be small next to the steps' fixed cost (`git init`, `slot.sh`). Decision 7 shows it as measured, and
  that number decides whether the follow-ups are worth it.
- A merge race with iteration 70 on `tests/check.sh` and `ci.yml`. Decision 6 states the rule by content for both
  orders.

## Size estimate

M: about 150 lines for the new test, and about 120 lines removed and 15 added across the three smoke files, plus 2 in
`tests/check.sh`, 1 in the changelog and at most 2 in `ci.yml`. About 290 changed lines.

## Not done

- No other library: `ledger.sh` and the awk programs are not touched, and `json.sh` is already in-process.
- No library behaviour, message or default changes. No script under `scripts/` changes.
- The steps slow for other reasons (`smoke-slot.sh`, `smoke-check.sh` and the like) are not made faster.
- No time budget is enforced by a test.
- No follow-up story is filed by this iteration.

## Left

- **"In both shells"**: the story predates iteration 68 (#365) and decision record 0004. This spec reads it as bash on
  Linux and macOS and Git Bash on Windows (no PowerShell test). The maintainer confirms.
- **Criterion 1 is met for `scripts/lib/load.sh` only**, as the agent note allows. Proposed follow-up stories, for the
  maintainer to file:
  - `ledger.sh`: `ledger_stamp`, `ledger_epoch`, `ledger_duration`, tested through `smoke-history.sh` and the check's
    times;
  - the awk programs whose functions need no repository (`stages.awk`, `history.awk`, `status.awk`, `dashboard.awk`,
    `models.awk`, `validate.awk`), driven by their smoke tests today. Testing them in-process means running `awk -f`
    on a small input in one test, not sourcing them.
