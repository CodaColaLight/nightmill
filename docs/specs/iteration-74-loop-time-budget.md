# Iteration 74: the check has a time budget, and /spec and /next ask before new work while it is exceeded

Status: delivered in iteration 74 (PR #413)

Story #345, epic #337 (fast verification loop). Three new optional keys under `verification` hold a budget for one
run of the check, a budget for one step, and the epic whose stories repair the loop. When a budget is set,
`tests/check.sh` prints one `check: OVER BUDGET:` line when the run or a step took longer, never fails for it, and
writes the run's time to a record shared by every worktree. `scripts/status.sh` shows that record against the budget
in one line, and `status.sh --budget` prints only that line. While the line says `OVER BUDGET`, `/spec` and `/next`
print it before they pick and ask the maintainer before they take a story outside the repair epic, picked from the
board or named by number. When a change adds a step to the check, its pull request states that step's time. Without
the keys nothing changes. **`verification.budgetEpic` is an addition beyond the two keys the issue names**: a skill
cannot know "this epic" of criterion 4 without a config value, and Config-driven forbids writing the epic's number
into a skill. If the maintainer refuses it, the alternative is under Left; the maintainer accepts or refuses the key
explicitly at approval. Changes
`schema/nightmill.schema.json`, `templates/nightmill.example.json`, `README.md`, `.claude/nightmill.json`,
`tests/check.sh`, `scripts/status.sh`, `skills/spec/SKILL.md`, `skills/next/SKILL.md`, `tests/smoke-check.sh`,
`tests/smoke-status.sh` and `CHANGELOG.md`.

**Never auto-merged.** New config keys are a story trigger, so `/next` opens the pull request without `--auto` and the
maintainer merges it by hand with `gh pr merge <n> --auto --squash`.

## Story trigger and manual check

**A story trigger: "a new, renamed or removed config key"**. `verification.checkBudgetSeconds`,
`verification.stepBudgetSeconds` and `verification.budgetEpic` are new. No status, no one who sets a status, and no
slot marker changes (`slot-N.json` and `ledger.tsv` are not touched). **Compatible** holds. A config without the keys
behaves as today. The previous version reads a config with them and only warns `unknown key` (an error only with
`--strict`), as iterations 42 and 71 found. **Config-driven** holds: the numbers and the epic live in the config, and
the skills and scripts hold no project value.

**The manual check applies.** `skills/spec/SKILL.md` and `skills/next/SKILL.md` change (path `skills`). Its steps are
under Tests. **Shells**: bash only (decision record 0004). `scripts/status.sh` changes and gets smoke steps in
`tests/smoke-status.sh`. `tests/check.sh` gets smoke steps in `tests/smoke-check.sh`. No `.ps1` file changes.

## Facts this rests on

Read on `spec/74-loop-time-budget` at 8dde608 (equal to `main`) on 2026-11-28, on Linux with 4 processors.

- `tests/check.sh` reads the clock through `scripts/lib/ledger.sh` (`NIGHTMILL_CLOCK_FILE` in tests). Every result
  line is `-- <name>: ok (<duration>)` or `-- <name>: FAILED (<duration>)`, then the `Times:` block and its `total`
  line (iteration 41, decision 13). It keeps each step's seconds in `t_names` / `t_secs`. It reads
  `verification.checkJobs` from `.claude/nightmill.json` of its own root with `json_load` (iteration 42). The final
  `mode` is `full`, `quick`, `only` or `affected`; an `--affected --within` run that falls back becomes `only`.
- Iteration 41, decision 13: "The check does not write the record" (`ledger.tsv`). This spec keeps that. The check
  writes a file of its own (decision 4).
- `scripts/status.sh` reads `.claude/nightmill.json` of the main checkout and dies without `gh` before it reads
  anything else. Its text form ends with the `capacity:` line when the config has `worktrees`. `scripts/dashboard.sh`
  reads only `--porcelain`. `tests/smoke-status.sh` pins the usage line `usage: status.sh [--all] [--porcelain | --json]`
  in two places.
- `/spec` and `/next` pick in step 1 ("Picking an issue" in the `workflow` skill). `scripts/drive.sh` runs
  `/nightmill:next <N>` headless, always with a number. `/fix` takes bugs. `/spec` and `/next` refuse bugs.
- `verification` keys today: `check`, `manualCheckPaths`, `manualCheckText`, `benchRule`, `checkJobs`, `platform`.
  `tests/lint.sh` allows `maximum` since iteration 53 (the `limits` keys use it): `scripts/validate-config.sh`
  ignores it, so the script that reads the key checks the upper end, and the description states the range.
- **The check's time today**: one run of `bash tests/check.sh` for this spec, 4 at a time, on an idle machine, took
  `total 3m20s`. The slowest steps were `test-guard-rules.sh` 1m40s, `test-lintcopy-output.sh` 1m37s,
  `smoke-drive.sh` 1m00s, `smoke-validate.sh` 1m00s, `smoke-status.sh` 47s and `smoke-slot.sh` 44s. Seven steps
  failed because of the local mawk 1.3.4, as iteration 73 found (`lint` and those that copy it). A green run can take
  somewhat longer.

## Decisions

1. **The keys**, in `verification.properties` after `platform`, in this order:
   - `checkBudgetSeconds`: `{ "type": "integer", "minimum": 0, "maximum": 86400, "default": 0, "description": "The most seconds one
     full or --affected run of the check may take (0 to 86400), for a check command that reads it; nightmill's own
     tests/check.sh does. A run over it prints one OVER BUDGET line and does not fail. While the last run is over a
     budget, /spec and /next ask before they take a story outside budgetEpic. 0: no budget." }`
   - `stepBudgetSeconds`: the same type, minimum, maximum and default, description: `The most seconds one step of the check
     may take (0 to 86400), for a check command that reads it; nightmill's own tests/check.sh does. A step over it is
     named on the OVER BUDGET line and does not fail the check. 0: no budget.`
   - `budgetEpic`: `"type": "integer"`, `"minimum": 0`, `"default": 0` and no maximum (an issue number), description: `The epic whose stories make the check faster:
     while the check is over its budget, /spec and /next take a story of this epic without asking. 0: none.`

   A *budget is set* when `checkBudgetSeconds` or `stepBudgetSeconds` is from 1 to 86400. A reader takes a value
   that is not a whole number from 0 to 86400 as 0 and prints one note on standard error:
   `<reader>: verification.<key> must be a whole number from 0 to 86400; no budget` (`<reader>` is `check` or
   `status.sh`). The range follows iteration 53: the schema holds `maximum`, the validator ignores it, the reader
   checks it. The default is 0 rather than absent, so each key has a default (the config contract).
2. **Over** means more seconds than the budget, strictly. The run's seconds are the `total` of the `Times:` block
   (start to end of the last step). A step's seconds are those of its result line, also for a step that "ended
   without a result".
3. **The line of the check.** With a budget set, directly after the `total` line of the `Times:` block and before the
   empty line, when anything is over, exactly one line:

   ```
   check: OVER BUDGET: <part>[; <part>]...
   ```

   The first part, only in a `full` or `affected` run whose total is over `checkBudgetSeconds`, is
   `the check took <d> (budget <b>)`. Then one part per step over `stepBudgetSeconds`, in list order, in every mode:
   `<step> took <d> (budget <b>)`. `<d>` and `<b>` are durations as `ledger_duration` prints them. Nothing is over:
   no line. The exit code, the result lines, the `SKIPPED:` and `LEFT OUT:` lines, the `--summary` text and the
   verdict line stay as they are. An interrupted check prints no line.
4. **The record.** With a budget set, a `full` or `affected` run that was not interrupted, passed or failed, writes
   one line to `<git common dir>/nightmill-check.tsv` (`git rev-parse --path-format=absolute --git-common-dir` from
   the check's root, so every worktree of the checkout shares one file). It replaces the file through a temporary
   file in the same folder and `mv -f`. The line has six tab-separated fields and ends with LF:
   `<stamp> <mode> <verdict> <total seconds> <slowest step> <its seconds>`. `<stamp>` is `ledger_stamp` of the end of
   the last step (UTC). `<mode>` is `full` or `affected`. `<verdict>` is `passed` or `failed`. The slowest step is the
   one with the most seconds (a tie: the first in list order); with no step run it is `-` and `0`. Outside a git
   checkout no record is written and nothing is printed. A failed write prints
   `check: the time record was not written (<first line of the error>)` on standard error and changes nothing else.
   `--quick` and `--only` runs write no record. **Tests only**: with `NIGHTMILL_CHECK_STEPS` or
   `NIGHTMILL_CHECK_RECORD` set, the check skips the git lookup: the record goes to the file `NIGHTMILL_CHECK_RECORD`
   names, and none is written when it is unset. So a fixture run never overwrites the record of the real checkout,
   and the record test works in the fixture copy `nrepo`, which is not a git checkout. The header comment names `NIGHTMILL_CHECK_RECORD` with the other test variables.
   Without a budget set, no record is read or written.
5. **The status line.** `scripts/status.sh` reads `<git common dir>/nightmill-check.tsv` of the main checkout and the
   keys of decision 1 from its config. With a budget set, the text form ends with one more line, after the `capacity:`
   line (or after the table without `worktrees`):

   ```
   check time: last <mode> check <stamp> (<verdict>) took <total> (budget <B>); slowest step <step> <d> (budget <S>): <within budget | OVER BUDGET>
   ```

   `<B>` and `<S>` are durations, or `none` for a budget of 0. `OVER BUDGET` when `<B>` is set and the total is over
   it, or `<S>` is set and the slowest step's seconds are over it. With no record:
   `check time: no check recorded yet (budget <B> per check, <S> per step)`. A record that is not one line of six
   fields as in decision 4 (a stamp `YYYY-MM-DDTHH:MM:SSZ`, mode, verdict, seconds `^[0-9]{1,9}$`):
   `check time: the record <path> is not readable (budget <B> per check, <S> per step)`. Without a budget set, no line
   and no read. `--porcelain` and `--json` do not change, so `scripts/dashboard.sh` sees nothing new.
6. **`status.sh --budget`** is plumbing for `/spec` and `/next` (decision 7): it lets them read the line of decision 5
   without `gh`, which the text form needs before anything else, and without the board table. It prints only the line of decision 5, or `check time: no budget set` without a budget, and
   exits 0. It needs only git and the config: it calls no `gh`, and a missing `gh` does not stop it. With any other
   option it is a usage error (exit 2). The usage line becomes
   `usage: status.sh [--all] [--porcelain | --json] | --budget`. The `/status` skill shows the line as printed and
   does not change.
7. **`/spec` and `/next`, step 1**, the same paragraph in both skills, run only when a budget is set in the
   base-branch configuration (otherwise step 1 is as today):
   - Before listing the board, or before reading a named issue, run
     `bash "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh" --budget`. When the line ends with `: OVER BUDGET`, print it.
   - **Every story taken**, picked from the board or named by number (also one named to finish its own work at Spec,
     Spec review, In progress or Review), once the story is known and accepted by "Picking an issue" and before the
     `Picking` line: if its parent epic is `verification.budgetEpic` (not 0), go on without a question. Otherwise ask
     the maintainer, exactly:
     `The check is over its budget. Take #<n> "<title>" anyway, a story outside epic #<budgetEpic>? (yes / no)`;
     with `budgetEpic` 0 the text after the comma is left out. `yes` goes on. `no` (or no answer) changes nothing
     and prints `Stopped: the check is over its budget; #<n> was not taken. Nothing was changed.`
   - **When no person can answer**: in a step of the driver (`NIGHTMILL_RUN_STARTED` is set, as `scripts/drive.sh`
     sets it for every headless run, which always names a number), the question is not asked. The skill prints the
     line and then `Going on without asking: no one can answer in a driver step (#<n>).` and goes on. The issue grants
     no stop, so an unattended run is not blocked; the line stays in the run's output. This rule is under Left.
   - The parent epic is `parent.number` from
     `gh api graphql -f query='query { repository(owner: "<owner>", name: "<repo>") { issue(number: <n>) { parent { number } } } }' --jq .data.repository.issue.parent.number`
     (the sub-issue link that `/story` makes). When it is empty, the first `Epic: #<k>` in the body counts.
   - Bugs are never asked about: `/fix` does not change, and `/spec` and `/next` refuse bugs as today.
8. **A new step's time.** When a budget is set in the base-branch configuration, the implementer's result block
   in `skills/next/SKILL.md` gets one more line after `Check:`:
   `New check steps: <name> <duration>, one per step the change adds to the check, with the time from its result line in the last full check; none>`.
   When it names a step, the session adds one line per step to "How verified", after the check line:
   `- New check step <name>: <duration> (step budget <S>)`, `<S>` as in decision 5. The line is a statement for the
   maintainer, not a gate. Without a budget the block and the body are as today.
9. **This repository's values.** `.claude/nightmill.json` gets `"checkBudgetSeconds": <B>`,
   `"stepBudgetSeconds": <S>` and `"budgetEpic": 337`, after `platform`, with `<B>` 300 and `<S>` 120. That is
   5 minutes for a run, about 1.5 times the measured 3m20s, and 2 minutes for a step, above the slowest measured
   step (1m40s). The run is under budget today, and a step that grows by a fifth shows up. The example gets all three
   as 0, so a project that copies it gets no budget.
10. **The README row.** In the `verification` row of the configuration table, after the `platform` part, exactly:
    `, and the time budget of the check (`checkBudgetSeconds`, one run, and `stepBudgetSeconds`, one step; default 0:
    no budget, for a check that reads them; nightmill's own check prints an OVER BUDGET line and does not fail) and the
    epic whose stories /spec and /next take without asking while the check is over budget (`budgetEpic`, default 0: none)`.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The configuration holds a budget for the per-change check and one for a single step; without the keys nothing changes | Decisions 1, 4 (no record without a budget), 5, 7, 8, 10 |
| 2 | The check prints one line when a run or a step went over its budget, naming the step; it does not fail for it | Decisions 2, 3 |
| 3 | `/status` shows the last check's time against the budget | Decisions 4, 5, 6 |
| 4 | While the budget is exceeded, `/spec` and `/next` say so before picking a story and ask the maintainer whether to go on; a story of this epic and every bug are picked without the question | Decisions 1 (`budgetEpic`), 6, 7 |
| 5 | A new test step's pull request states the step's time | Decision 8 |

## Tests

Behaviour only (iteration 73, decision 1): the tests run the check and the status script on fixtures with the fixture
clock. No test searches skill text.

**`tests/smoke-check.sh`**, a new section `== the time budget`, in the copy `nrepo` with its own config. The fixture
steps write a new time into `NIGHTMILL_CLOCK_FILE`, as `== the check's step times` of `tests/smoke-stages.sh` does, with
`--jobs 1`. Steps: `one` +12 s, `two` +75 s, `three` +40 s, all exit 0 unless named.

- Criterion 1, `no keys`: with no budget key, no line starts with `check: OVER BUDGET` and no file appears at
  `NIGHTMILL_CHECK_RECORD`. With both keys 0, the output is byte for byte that of the run without keys. The existing
  sections, which run without the keys, stay unchanged and green.
- Criterion 2, `run over`: `checkBudgetSeconds` 120: the line `check: OVER BUDGET: the check took 2m07s (budget
  2m00s)` comes directly after the `total` line; exit 0 and `ALL CHECKS PASSED`.
- Criterion 2, `step over`: `stepBudgetSeconds` 60: `check: OVER BUDGET: two took 1m15s (budget 1m00s)`. With both
  (120, 30): one line `check: OVER BUDGET: the check took 2m07s (budget 2m00s); two took 1m15s (budget 30s); three took
  40s (budget 30s)`. With `two` failing: the same line, exit 1 and `CHECK FAILED: two`. With 200 and 100: no line.
- Criterion 2, `modes`: `--quick` with `checkBudgetSeconds` 120 and `stepBudgetSeconds` 60 names `two` only, not the
  check, and writes no record. `--only one,two` the same.
- Criterion 2, `bad value`: `checkBudgetSeconds` `"x"` and 86401 each give the note of decision 1 and no line.
- Criterion 3, `record`: the `run over` run writes one line, six fields, `full`, `passed`, `127`, `two`, `75`, the
  stamp of the clock's last value. A failed run writes `failed`. With `NIGHTMILL_CHECK_RECORD` unset, nothing is
  written. With the record's folder not writable: the note of decision 4, the same exit code.

**`tests/smoke-status.sh`**, a new section `== the check time line`, on the existing fixture repository with a record
file written into its git common dir:

- Criterion 1: no budget key: the text form is unchanged byte for byte (the existing expected outputs).
- Criterion 3: budgets 120 and 60 and a record `full passed 127 two 75`: the last line is
  `check time: last full check <stamp> (passed) took 2m07s (budget 2m00s); slowest step two 1m15s (budget 1m00s): OVER BUDGET`.
  Budgets 200 and 100: the same with `within budget`. Budget 120 only: `(budget none)` for the step. No record: the
  `no check recorded yet` line. A record of five fields: the `not readable` line. `--porcelain` and `--json` are
  unchanged.
- Criterion 4: `--budget` prints only that line, exit 0, with no `gh` on the PATH and no call in the fake `gh`'s log.
  Without a budget: `check time: no budget set`. `--budget --all`: the new usage line, exit 2.

**Only the manual check shows criteria 4 and 5** (the skills follow the text). In a scratch project with a board,
start `claude --plugin-dir <a separate checkout of the feature branch>` (never `--plugin-dir .` here). Its base
config has `"checkBudgetSeconds": 1` and `"budgetEpic": <an epic of the scratch board>`, and its check command is a
copy of nightmill's `tests/check.sh`.

1. Run the check once. `/status` ends with the `check time:` line saying `OVER BUDGET`.
2. With a Ready story outside the epic at top priority, `/spec`: the line is printed, then the question. `no`: the
   `Stopped:` line, nothing changed. Again with `yes`: the run goes on as today.
3. With the top Ready story under the epic: `/spec` prints the line and asks nothing. The same for `/next` with an
   Approved story. `/next <n>` named, for a story outside the epic: the line, then the question; for a story under
   the epic: the line and no question.
4. In the scratch project's main checkout, `NIGHTMILL_RUN_STARTED=$(date +%s) claude -p "/nightmill:next <n>"` for an
   Approved story outside the epic: the output has the line and the `Going on without asking` line, and the run goes
   on.
5. A story whose change adds a step to the check: the pull request's "How verified" has the `New check step` line.
6. Remove the three keys: `/status`, `/spec` and `/next` run as before this iteration.

## Files touched

- `schema/nightmill.schema.json`: the three keys (decision 1). Implementer.
- `templates/nightmill.example.json`: the three keys, 0 (decision 9). Implementer.
- `.claude/nightmill.json`: the three values (decision 9). Implementer.
- `README.md`: the `verification` row (decision 10). Implementer.
- `tests/check.sh`: decisions 1 to 4, and the header comment (the budget keys, the line, the record,
  `NIGHTMILL_CHECK_RECORD`). No step is added, so the step list and the map do not change. Implementer.
- `scripts/status.sh`: decisions 5 and 6, and its header comment. Implementer.
- `skills/spec/SKILL.md`, `skills/next/SKILL.md`: step 1 (decision 7); in `/next` also the implementer's result block
  and "How verified" (decision 8). Implementer.
- `tests/smoke-check.sh`, `tests/smoke-status.sh`: the sections of Tests, and the two usage lines in
  `tests/smoke-status.sh`. Tester.
- `CHANGELOG.md`, under `Unreleased`, added by the `/next` session, exactly:

  ```
  - Iteration 74 (#345): the check has a time budget: `verification.checkBudgetSeconds` and `verification.stepBudgetSeconds` (default 0, no budget) make tests/check.sh print one OVER BUDGET line without failing, `/status` shows the last check's time against them, and while the check is over budget `/spec` and `/next` ask before they take a story outside `verification.budgetEpic`; a pull request that adds a check step states its time.
  ```

## Risks

- A record from another branch's run is shown as "the last check". That is the intent: the loop is shared, and the
  stamp and mode are on the line.
- A budget set too low makes every pick ask. Picking a story of the epic and every bug does not ask, and the
  maintainer sets the numbers.
- Times vary with the machine and its load, so a run near the budget may be over once and under the next time. The
  line only informs and the question only asks; nothing fails.
- CI runs the real check with this repository's config, so its logs may show the line. That is informative only.
  Failing CI on time is out of scope.

## Size estimate

M: about 45 changed lines in `tests/check.sh`, 45 in `scripts/status.sh`, 25 in the two skills, 12 in the schema,
the example, the README and the config, and about 150 in the two smoke tests: about 280 lines.

## Not done

- CI never fails on time, and CI's step summary does not change.
- No change to `/fix`, the driver or the `workflow` skill. A driver step prints the line and goes on without a
  question (decision 7).
- No history of check times: the record keeps the last run only. `scripts/history.sh`, `ledger.tsv` and
  `scripts/stages.sh` do not change.
- No budget for CI's jobs, and no automatic split or speed-up of a slow step.
- `--porcelain`, `--json`, the dashboard and the slots pane do not show the budget.

## Left

- **The epic key, accepted or refused at approval.** Criterion 4 names "this epic", and a skill cannot know it
  without a config value (Config-driven forbids writing #337 into a skill), so this spec adds
  `verification.budgetEpic`, a third key beyond the issue's two. If the maintainer refuses it, the alternative is to
  add no third key and no epic exemption: every story outside the bugs gets the question, the maintainer answers
  `yes` for a story of the repair epic, and criterion 4's "a story of this epic ... without the question" is then not
  met and needs the issue changed. There is no key-free way to tell the epic.
- **When no person can answer.** A driver step does not ask: it prints the line and goes on (decision 7), because the
  issue grants no stop. So the driver keeps taking stories outside the epic while over budget. Whether a driver step
  should stop instead is for the maintainer to decide.
- **The numbers.** 300 s and 120 s come from one local run in which seven steps were red because of mawk. The
  maintainer may want to set them from a green run instead.
