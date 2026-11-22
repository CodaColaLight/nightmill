# Iteration 63: a fast lane in /fix for low-risk bugs

Status: delivered in iteration 63 (PR #362)

Story #341, epic #337 (fast verification loop). A new config key, `review.fastLane`, names the priorities whose bugs
start in a fast lane and the paths a fast-lane fix may change. In the fast lane `/fix` launches one agent, in the role
`fixer`, that writes the regression test and the fix and runs the affected check. The pull request then opens
without the tester and without the code review. After that agent returns, the session checks what it changed. A
changed path outside the lane's paths, a path in `parallel.hotFiles`, a story trigger the agent names, or a partial
result takes the bug out of the lane. The agent's work is then set aside in the stash, and the long way runs from the
tester, as today. The run and the pull request say which lane the bug took. Without the key nothing changes. Changes
`skills/fix/SKILL.md`, `skills/workflow/SKILL.md`, `schema/nightmill.schema.json`, `templates/nightmill.example.json`,
`README.md`, `tests/lint.sh`, the new `tests/test-fast-lane.sh` and `CHANGELOG.md`.

## Story trigger and manual check

**A story trigger**: *a new, renamed or removed config key*. `review.fastLane` is new (hence a story, as the issue
says). It goes into the schema with a description and defaults, into the example config and into the README's
configuration table. This repository's `.claude/nightmill.json` does not set it.

- *A change to the status flow or who sets a status*: no. A bug still goes Ready > In progress > Review > Done, and the
  session sets the same statuses at the same steps. No decision record is needed.
- *A change to the slot marker format*: no. The two new step names (`fast-fix`, `lane-left`) are values of the
  existing `step` field, which `slot --report` takes as free text.
- **Compatible**: an older plugin that reads a config holding `review.fastLane` ignores it. Its validator reports the
  key as unknown: a warning, or an error with `--strict`. That is true of every new key. No key is renamed or removed.

**The manual check applies**: `skills` is in `verification.manualCheckPaths`, and `skills/fix/SKILL.md` and
`skills/workflow/SKILL.md` change. Its steps are under Tests. Nothing under `agents` or `hooks` changes.

**Both shells**: no script in `scripts/` changes. `validate-config.sh` and `.ps1` walk the schema, so the new key is
validated by both with no code change (the keywords used are `type`, `items` and `properties`, all supported).
`tests/test-fast-lane.sh` tests only skill texts, the schema and the example, like `tests/test-extra-round.sh`, so it
has no PowerShell twin.

**Hot files**: `skills/workflow/SKILL.md` and `schema/nightmill.schema.json` are in `parallel.hotFiles`, so this story
is not paired with another story that changes either of them.

## Facts this rests on

Read on `main` at 50b5618.

- `/fix` today: tester, then fixer, then code review, with up to `review.maxFixRounds` fix rounds (disputes and
  undone rounds count too), the manual check, then the pull request and the auto-merge rule of step 6. Both the
  fixer's prompt and its fix rounds say "Run the check" (iteration 59, Left: the prompts still run the full check).
- `tests/check.sh --affected` (iteration 59) runs the lint plus the steps mapped to the paths changed against
  `origin/<git.baseBranch>`, and the full check for a shared or unknown path. Since iteration 62 it also leaves out the
  steps marked slow. Its last line is `AFFECTED CHECK PASSED (...)`. Under the workflow rule, a check whose first line
  does not start with `check: AFFECTED` has no such mode, and the agent runs the check instead.
- `parallel.hotFiles` entries are files or directories. `/fix all` already matches a path against them: a path is
  inside a directory entry when it starts with the entry followed by `/`.
- `/init` gives each slot permission rules for exactly the git forms the skills write. Among them are
  `git -C <S> reset --mixed -q *`, `add *`, `diff *`, `stash push *` and `merge-base *`, but not `branch` or `switch`.
- #167 (a verdict that decides auto-merge) is open and has no spec. Nothing here contradicts it.

## Decisions

**1. The key: `review.fastLane`**, an object with two arrays of strings:

```json
"review": { "fastLane": { "priorities": ["Low"], "paths": ["docs", "tests"] } }
```

- `priorities`: names from `board.priorities`. Default `[]`. A bug starts in the fast lane when the value of its
  `board.priorityField` (from step 1's item listing) equals one of these names exactly. A bug without a priority
  never does. A name that is not in `board.priorities` matches no bug (the safe side: the long way).
- `paths`: files or directories, relative to the repository root. Default `[]`. A trailing `/` of an entry is
  dropped, and an entry that is then empty is ignored. A changed path is **in** an entry when it equals the entry or
  starts with the entry followed by `/`. The comparison is case-sensitive text with no wildcards: a `*` is a
  character. An empty `paths` list means every fix leaves the lane. The regression test is a changed path like any
  other, so a project names its test directory here.
- **Absent key**: `/fix` runs exactly as today. No lane line is printed and the pull request has no `Lane:` line.
  `"fastLane": {}` or empty `priorities` is a set key, and every bug takes the long way with its reason.
- **Validation**: the schema types only (an object, arrays of strings), checked by `validate-config` in both shells.
  Unknown keys inside it are warnings, as everywhere. The skill reads the arrays as they are, and a value that is not
  an array of strings means the long way, with the reason `review.fastLane is not valid`.
- **Why under `review`**: it decides how much of the review chain a bug goes through, beside `maxFixRounds`.

**2. Entering the lane.** Right after the picking of step 1 and before step 3, with the key set, the run prints one
line:

- `Lane: fast for #<issue>: priority <p> is in review.fastLane.priorities.`, or
- `Lane: long for #<issue>: priority <p | none> is not in review.fastLane.priorities.` (or
  `Lane: long for #<issue>: review.fastLane is not valid.`).

Step 2 (is it a bug) still comes first and is unchanged: a bug that already needs a story trigger stops there, in
either lane.

**3. The fast lane's one agent.** Step 3 is unchanged. In place of "The tester" and "The fixer", the session records
`<lane base>` (`git -C <slot> rev-parse HEAD`), counts the agents, checks the room, reports `fast-fix` (role `fixer`)
and launches one fresh agent. It is launched as "The fixer" step 2 says: on `roles.fixer.model`, passed explicitly,
not a fork. Its prompt is the fixer's prompt with these changes:

- The paragraphs from "The tester has written a regression test" to "The session passes the dispute to the tester."
  are replaced by: "No tester and no code review follow: you write the regression test and the fix. Write the test
  first. It follows the report's 'How to reproduce' as closely as a test can, expects what the report says should
  happen, and fails because what the report says happens does happen. Run it and watch it fail for that reason before
  you change any file that is not a test. A bug you cannot reproduce with a test is reported as `failed`, never forced."
- Its step 1 becomes "Write the regression test and watch it fail for the reason in the issue".
- Its step 4 runs the affected check, `cd <absolute slot path> && <verification.check> --affected`. When its first
  line does not start with `check: AFFECTED`, the agent runs `<verification.check>` instead.
- The `Disputes:` line is removed from the result block. After `Manual check:` comes
  `Story trigger: <none | the trigger, as configured, that the fix needs>`, and the sentence on story triggers says
  to stop and name the trigger there.
- The prompt names neither `review.fastLane.paths` nor `parallel.hotFiles`. The agent writes the smallest right fix,
  and the session judges where it landed, so the fix is not bent to fit the lane.

The fixer's own step reports (`test`, `code`, `check`, `commit`) are the same. The gate runs after the agent returns,
with `--role fixer`, as after every launch.

**4. Staying or leaving: decided by the session after the agent returns**, in this order. The first rule that holds
decides:

1. The result block has a `Story trigger:` line that is not `none`, whatever its `Result:`: leave, with the reason
   `the fix needs a story trigger: <the line's value>`.
2. `Result: failed`, no result block, or an error: the stop of "The fixer" step 3, unchanged
   (`Stopped: the fixer returned failed: <Left>`). This is a stop, not a lane change.
3. `Result: partial`: leave, with the reason `the fixer returned partial: <Left>`.
4. The branch checks of "The fixer" step 3 (a clean tree, a log that is not empty). When one fails, it is handled as
   rule 2.
5. The changed paths: `git -C <slot> diff --name-only --no-renames origin/<git.baseBranch>...<branch>`, the command
   of the merge step. When git fails: leave, with the reason
   `the changed paths could not be listed (<the first line of git's message>)`. Otherwise each path, in sorted order:
   a path in an entry of `parallel.hotFiles` (the matching rule of decision 1) leaves, with
   `<path> is in the hot file entry <entry>`. A path in no entry of `review.fastLane.paths` leaves, with
   `<path> is outside review.fastLane.paths`. A hot file leaves even when it is inside the lane's paths.
6. Otherwise the bug **stays** in the fast lane: decision 6.

The story-trigger rule comes first, before the `failed` stop, so an agent that stops on a story trigger leaves the
lane whichever `Result:` it returns (criterion 3), and the prompt need not fix that `Result:`. Of the two ways the
spec review offered, this order is the smaller change: the prompt and the result block stay as decision 3 has them.

**5. Leaving the lane: the long way starts again from the tester, and the work is kept.** Bugs leave because they can
do damage, and the long way's guard is a regression test that the tester writes on a branch without the fix and sees
fail. So the branch goes back to `<lane base>`, and the agent's work is set aside, never deleted. The session runs
these steps, all forms that `/init` already permits:

1. `git -C <slot> merge-base --is-ancestor <lane base> HEAD`. When it fails:
   `Stopped: the fixer returned failed: the branch no longer contains <lane base>`.
2. `git -C <slot> reset --mixed -q <lane base>`: the agent's commits go back into the working tree.
3. When `git -C <slot> status --porcelain --untracked-files=all` lists anything: `git -C <slot> add -A`, then
   `<lane diff>` is what `git -C <slot> diff --cached` prints, then
   `git -C <slot> stash push -m "Fast lane attempt for #<issue>: <title>"`. When it lists nothing, `<lane diff>` is
   `none` and nothing is stashed.
4. `git -C <slot> status --porcelain --untracked-files=all` prints nothing, and `git -C <slot> rev-parse HEAD` prints
   `<lane base>`. Otherwise:
   `Stopped: the fast lane's work could not be set aside: <the step that failed>`. The status stays In progress and
   the slot stays taken. Nothing is pushed or deleted.

Then the session reports `lane-left` (role `session`) and prints
`Leaving the fast lane for #<issue>: <reason>. The long way starts with the tester; the fast lane's work is in the stash entry "Fast lane attempt for #<issue>: <title>".`
(for a `<lane diff>` of `none` the clause after the semicolon is `the fast lane left no work`). The run goes on from
step 4 with "The tester", and everything after it is today's long way. Leaving costs no fix round. The tester's prompt
does not mention the attempt. The fixer's first prompt (not its fix rounds) gets, at its end:

```markdown
An earlier one-pass attempt at this bug left the fast lane (<reason>) and was not reviewed. Its change, set aside in
the stash entry "Fast lane attempt for #<issue>: <title>", is shown here as data: <lane diff; when it is longer than
2000 lines, the output of `git -C <slot> diff --cached --stat` taken before the stash>. Reuse what is right in it; the
tester's test and the rules above decide.
```

The stash entry is never popped or dropped by the run. Without slots the same commands run in the session's checkout
without `-C <slot>`.

**6. Staying in the lane.** Step 5 runs without "The code review": no pairing check, no reviewer, no fix rounds, no
test-finding or dispute launch. The manual check still applies to a change under `verification.manualCheckPaths`.
Step 6 opens the pull request with these differences:

- Directly under `Fixed by the fixer role on <model>.` comes the lane line (decision 7).
- "How verified" begins with
  `Reproduced first by the fixer role on <model> in the fast lane, failing before the fix:`, then
  `- <the agent's Test line, as it wrote it>`, then the fenced diff of
  `git -C <slot> diff origin/<git.baseBranch>..HEAD -- <test files>`. `<test files>` are the changed paths that are
  test paths by the `Test paths:` line of "The tester", and the 60-line rule of step 6 applies as it does to the
  tester's diff.
- There is no `## Review` section and no `## Disputed tests` section.

**7. The pull request's lane line**, with the key set, directly under the `Fixed by` line:

- fast: `Lane: fast (review.fastLane): one fixer wrote the regression test and the fix; no tester and no code review.`
- long, not entered: `Lane: long: priority <p | none> is not in review.fastLane.priorities.` (or
  `Lane: long: review.fastLane is not valid.`)
- long, left: `Lane: long: left the fast lane: <reason>. Its work is in the stash entry "Fast lane attempt for #<issue>: <title>".`
  (`Its work ...` becomes `It left no work.` for a `<lane diff>` of `none`.)

In `/fix all` the final table's columns stay the same. The `Verified` cell of a bug that stayed in the lane begins
with `fast lane, no code review; `, and one that left begins with `left the fast lane: <reason>; `.

**8. What stays exactly as it is.**

- **Auto-merge**: the rule of step 6 and of **CI and merging**, unchanged. A complete fix gets
  `gh pr merge <pr> <git.mergeFlags>`, and the same cases withhold it: partial, a story trigger, an open blocking
  finding, an open dispute, the merge-flags check and the `.claude/` / `.github/` paths check. A fast-lane pull request
  is a complete fix, because a partial result leaves the lane (decision 4 rule 3).
- **The long way**: the tester, the fixer, "The tester's files", "The code review", its fix rounds and their count,
  the extra review round and the `## Review` section, word for word. The fixer's long-way prompt keeps
  "Run the check".
- **Watching the checks** (step 7), for a fast-lane pull request too: a check fix round there still has the `fixer`
  and the `codeReviewer`.
- **The story triggers**: step 2 and the fixer's stop on a story trigger are unchanged. Decision 4 rule 1 only moves
  a bug out of the fast lane.
- The gate, the agent count, the room check, the slot handling and batch mode's order, overlap and freeing rules.

**9. The skill texts.**

- `skills/fix/SKILL.md`: a section `## The fast lane` after "The fixer", holding decisions 1 to 7. Steps 4 and 5 open
  with "In the fast lane (`review.fastLane`) see "The fast lane"; otherwise:". Step 6 gets the lane line and the fast
  lane's "How verified". The reporting table gets two rows: just before the fast lane's launch, `fixer`, `fast-fix`;
  after the fast lane's work is set aside, `session`, `lane-left`. Batch mode gets the `Verified` cell of decision 7.
- `skills/workflow/SKILL.md`: in **Agent roles and models**, the `fixer` row's "Reviewed by" cell becomes
  `codeReviewer (not in the fast lane of /fix)`. In **Findings and fix rounds**, one sentence after the paragraph on
  `/next` and `/fix`: "A bug that stays in the fast lane of `/fix` (`review.fastLane`) has no code review, no fix round
  and no `## Review` section; its pull request says so in its `Lane:` line."

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The configuration says which bugs take the fast lane, by priority and by the paths a fix may touch; without the key every bug goes the long way, as today | Decision 1 (key, shape, defaults, matching, absent key), decision 2 |
| 2 | In the fast lane one agent writes the regression test and the fix, the affected-steps check runs, and the pull request opens without a review round | Decisions 3 and 6 |
| 3 | A fix that touches a path outside the fast lane's paths, a hot file or a story trigger leaves the fast lane and goes the long way, and the run says so | Decisions 4 and 5 |
| 4 | The pull request says which lane it took | Decision 7 |
| 5 | Auto-merge rules are unchanged | Decision 8 |

## Tests

The skills are conversations, so the tests pin the texts the behaviour depends on, as `tests/test-extra-round.sh`
does: the same `need` / `gone` helpers, with the text joined (newlines to spaces, runs of spaces made one) before it is
searched. The new file `tests/test-fast-lane.sh` is run from `tests/lint.sh` in a section
`== the fast lane of /fix`, right after `== an extra review round is proposed`, as
`bash tests/test-fast-lane.sh "$PWD" || fail=1`. It is not a step of `tests/check.sh`, so neither the map nor CI
changes.

- Criterion 1: `schema: fastLane`: `properties.review.properties.fastLane` has type `object` and a description.
  `priorities` and `paths` each have type `array`, items of type `string`, a `default` of `[]` and a description.
  The test reads them with `scripts/lib/json.sh`. `example: fastLane`: `templates/nightmill.example.json` has
  `review.fastLane.priorities` and `review.fastLane.paths` (the lint already validates the example with `--strict`).
  `readme: fastLane`: `README.md` has a table row starting `` | `review.fastLane` | ``. `validator: fastLane`:
  `bash scripts/validate-config.sh <tmp>` on `{"review":{"fastLane":{"priorities":"Low"}}}` prints
  `error: review.fastLane.priorities: expected array, got string` and exits 1. `fix: absent key`: the fix skill says
  that without `review.fastLane` no lane line is printed and the run is today's, and it has both lines of decision 2.
- Criterion 2: `fix: one agent`: the fix skill has the replaced paragraph's "No tester and no code review follow",
  `--affected` in the fast lane's step 4, `Story trigger: <none |`, the `fast-fix` row, and decision 6's sentence that
  step 5 runs without "The code review".
- Criterion 3: `fix: leaving`: the fix skill has the four reasons of decision 4 (`is in the hot file entry`,
  `is outside review.fastLane.paths`, `the fix needs a story trigger:`, `the fixer returned partial:`), the first
  rule's ``whatever its `Result:` `` (and the story-trigger reason comes before `the fixer returned failed:` in the fast
  lane section, so a stop on a trigger leaves the lane), the commands
  `reset --mixed -q <lane base>` and `stash push -m "Fast lane attempt for #<issue>: <title>"`, the
  `Leaving the fast lane for #<issue>:` line, the `lane-left` row, the fixer's paragraph "An earlier one-pass attempt",
  and the sentence that the tester's prompt does not mention the attempt.
- Criterion 4: `fix: lane line`: the three `Lane:` lines of decision 7 and the fast lane's "How verified" opening.
  `workflow: fast lane`: the workflow skill has decision 9's sentence and `not in the fast lane of /fix`.
- Criterion 5: `fix: auto-merge kept`: the fix skill still has, unchanged, "For a complete fix enable auto-merge" and
  the two merge-step lines (`it must contain --auto and never --admin`, `which is never auto-merged`), and the
  workflow skill's **CI and merging** paragraph is unchanged (its first sentence pinned). Only the manual check shows
  that a fast-lane pull request is auto-merged by the same rule.

**The full check on the branch**: `bash tests/check.sh` is green.

**Manual check by the maintainer** (skills change). Use a throwaway test project whose base-branch config has
`"review": { "fastLane": { "priorities": ["Low"], "paths": ["docs", "tests"] } }` and
`"parallel": { "hotFiles": ["docs/index.md"] }`. Load nightmill from a separate checkout of the implemented branch
(`claude --plugin-dir <that checkout>`).

1. A Low bug whose fix is a line in `docs/guide.md`: `/fix <n>` prints `Lane: fast for #<n>: ...`. One fixer agent
   runs, and no tester and no code reviewer is launched. Its `Check:` line is the affected check's, or the check's
   when the project's check has no such mode. The pull request has the fast `Lane:` line, the fast lane's
   "How verified", no `## Review`, and auto-merge on.
2. A Low bug whose fix is in `docs/index.md` (a hot file inside the lane's paths): after the agent returns, the run
   prints `Leaving the fast lane for #<n>: docs/index.md is in the hot file entry docs/index.md. ...`.
   `git stash list` shows the entry, the branch is back at its start, and the tester, the fixer (its prompt has the
   earlier attempt) and the code reviewer run. The pull request has `Lane: long: left the fast lane: ...` and a
   `## Review` section.
3. A Medium bug prints `Lane: long for #<n>: priority Medium is not in review.fastLane.priorities.` and runs the long
   way. With `review.fastLane` removed from the config, a bug runs with no `Lane:` line anywhere.

Delete the throwaway branches, the stash entries and the test project's pull requests afterwards.

## Files touched

- `skills/fix/SKILL.md`: decision 9.
- `skills/workflow/SKILL.md`: decision 9.
- `schema/nightmill.schema.json`: `review.properties.fastLane`, with these descriptions:
  - `fastLane`: "Which bugs /fix fixes in one pass: one fixer writes the regression test and the fix, the affected
    check runs, and the pull request opens without the tester and the code review. A bug starts in it when its
    priority is in priorities. It leaves for the long way (the tester, the fixer and the code review, from the start)
    when its fix changes a path outside paths or in parallel.hotFiles, needs a story trigger, or is partial. Absent:
    every bug goes the long way."
  - `priorities`: "Priorities, names from board.priorities, whose bugs start in the fast lane. A name not in
    board.priorities matches no bug. Empty: no bug does."
  - `paths`: "Files or directories, relative to the repository root, that a fast-lane fix may change. A directory
    covers every path under it, a trailing / is ignored, and there are no wildcards. The regression test counts too,
    so name the test directory. Empty: every fix leaves the fast lane."
- `templates/nightmill.example.json`: `"review": { "maxFixRounds": 3, "watchChecksMinutes": 30, "fastLane": { "priorities": ["Low"], "paths": ["docs", "tests"] } }`.
- `README.md`, the configuration table, a row after `review.watchChecksMinutes`:
  `` | `review.fastLane` | Which bugs `/fix` fixes in one pass, without the tester and the code review: `priorities` (names from `board.priorities`, default none) and `paths` (files or directories the fix may change, default none); a fix outside `paths`, in a hot file, needing a story trigger or partial goes the long way. Absent: every bug goes the long way | ``
- `tests/test-fast-lane.sh` (new) and `tests/lint.sh` (the section that runs it).
- `CHANGELOG.md`, one bullet under `Unreleased`:

  ```
  - Iteration 63 (#341): a fast lane in /fix for low-risk bugs. The new key review.fastLane names the priorities whose
    bugs start in it and the paths a fix may change. In the fast lane one fixer writes the regression test and the
    fix, the affected check runs, and the pull request opens without the tester and the code review. A fix that
    changes a path outside the lane's paths or in parallel.hotFiles, needs a story trigger or is partial leaves the
    lane: its work goes to the stash and the long way starts from the tester. The run and the pull request say which
    lane a bug took. Without the key nothing changes; auto-merge rules are unchanged.
  ```

Not touched: every script in `scripts/`, `tests/check.sh` and its map, `.github/workflows/ci.yml`, `agents/*.md`,
`skills/init/SKILL.md` (no new git form), `skills/next/SKILL.md`, `.claude/nightmill.json`.

## Risks

- **A fix that does damage inside the lane's paths.** It merges without a review. What limits it: the lane is opt-in
  per priority and per path, hot files always leave it, the affected check runs, CI runs on the pull request, and
  auto-merge waits for CI. A project that lists broad paths accepts that.
- **A test the agent wrote to pass.** No independent tester sees it fail. The agent's prompt demands that it fail
  first, and the pull request shows the test's diff so the maintainer can judge. It is the trade the issue asks for.
- **Wasted work when a bug leaves.** The agent's work is kept in the stash and given to the next fixer, but the long
  way's tester and review run in full. A lane whose paths are too narrow leaves often, and the `Leaving` lines show
  why.
- **Stash entries pile up.** The stash is shared by all worktrees, and the run never drops an entry. Each entry names
  its issue, so the maintainer drops it once the bug is merged.
- **A misspelt priority** silently turns the lane off for it (the safe side). The `Lane: long ... is not in` line
  shows the cause.

## Size estimate

`M`: about 260 changed lines. `skills/fix/SKILL.md` about 120, `skills/workflow/SKILL.md` about 4, the schema about 8,
the example 1, README 1, CHANGELOG 7, `tests/lint.sh` 4, `tests/test-fast-lane.sh` about 110.

## Not done

- No fast lane in `/next` or for stories (out of scope), and no change to any role's model.
- No change to the long way: the tester, the fixer's long-way prompt (it still runs the check, not the affected check),
  the code review, the fix rounds, the extra round, the check fix rounds of step 7.
- No change to auto-merge, the story triggers, the status flow, the gate or the room check.
- No guess before the agent runs: the issue's named files are not used to keep a bug out of the lane, and only the
  changed paths after the agent decide.
- No wildcards or patterns in `review.fastLane.paths`, no lane by area or label, and no size limit (changed lines) for
  the lane.
- No default lane: the key's defaults are empty, so a project that does not set it keeps today's behaviour, and this
  repository's own config does not set it.
- No change to any script, to `/init`'s permission rules, or to the slot marker format.

## Left

- **Where the long way starts after leaving.** This spec starts it again from the tester, with the agent's work in
  the stash and given only to the fixer (decision 5), so the independent, failing-first test of the long way holds.
  The other reading keeps the agent's commit and goes straight to the code review, skipping the tester. That is
  cheaper but drops the independent test for exactly the changes that can do damage. The maintainer may choose it
  instead.
- **Partial results leave the lane** (decision 4 rule 3). The issue names only paths, hot files and story triggers.
  This spec adds partial because a fast-lane pull request has no review, and a partial unreviewed fix would otherwise
  open as one.
