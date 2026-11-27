# Iteration 71: /spec holds a spec to a size limit, and a story that does not fit gets a split proposal

Status: draft, awaiting approval (#347)

Story #347, epic #337 (fast verification loop). A new config key, `iterations.maxSpecLines`, holds the most lines a
spec file may have; 0, the default, and an absent key mean no limit, and `/spec` then runs exactly as today. With a
limit, the spec writer's prompt states it, the spec reviewer reports a spec over it as a blocking finding, and a writer
that cannot fit the story returns a split instead of a spec: the session posts the split as a comment on the issue and
stops. The spec template names what does not belong in a spec. Changes `schema/nightmill.schema.json`,
`templates/nightmill.example.json`, `README.md`, `skills/spec/SKILL.md`, `agents/spec-reviewer.md`,
`templates/spec.md`, `tests/lint.sh` (one start line), the new `tests/test-spec-size-limit.sh` and `CHANGELOG.md`.

**Never auto-merged.** A new config key is a story trigger, so `/next` opens the pull request without `--auto` and the
maintainer merges it by hand with `gh pr merge <n> --auto --squash`.

## Story trigger and manual check

**A story trigger: "a new, renamed or removed config key"** (`iterations.maxSpecLines` is new). No status, no one who
sets a status, and no slot marker changes. **Compatible** holds: a config without the key behaves as today, and the
previous version reads a config with it and only warns `unknown key` (an error only with `--strict`).

**The manual check applies.** `skills/spec/SKILL.md` and `agents/spec-reviewer.md` change (paths `skills` and `agents`);
its steps are under Tests. **Shells**: bash only (decision record 0004, iteration 68); no file under `scripts/` and no
`.ps1` file is added or changed. The steps involved are the lint (which starts the new test) and `tests/check.sh`.

## Facts this rests on

Read on `spec/71-spec-size-limit` at 5a95ed5, equal to `main`, on 2026-11-27.

- The `iterations` keys of the schema (`specDir`, `specPattern`, `changelog`, `milestonePattern`, `decisionsDir`) have
  no description; limits elsewhere are named `max<What>` (`review.maxFixRounds`, `parallel.maxAgents`). A key whose 0
  means "no limit" exists: `parallel.fixAllMaxBugs` (default 0).
- The spec reviewer has the tools Read, Grep and Glob only, so it counts lines by the line numbers Read shows.
- `tests/lint.sh` pins `Result: complete | partial | failed` in `skills/spec/SKILL.md` as a substring, and
  `tests/test-spec-template.sh` checks the headings of `templates/spec.md` and the comment two lines below each optional
  heading. Neither breaks when text is added as decided below.
- **Iteration 70** (#343, PR #399, not merged) also changes `tests/lint.sh` and `README.md`: the rules that compare
  `ci.yml` with the step list, and a sentence in `## Developing nightmill`. This iteration touches neither: its README
  change is the `iterations` row of the configuration table, and its lint change is one start line placed by content
  (Files touched). Both merge in either order. Iteration 70 adds a rule that every `tests/test-*.sh` runs somewhere;
  the start line in `tests/lint.sh` meets it, and no step is added to `tests/check.sh`, so neither its step list nor its
  affects map changes.
- Iteration 70's spec has 655 lines; this story aims at specs much shorter than that.

## Decisions

1. **The key.** `iterations.maxSpecLines`, next to `specDir` and `specPattern`: `{ "type": "integer", "minimum": 0,
   "default": 0, "description": ... }`. Description, exactly: `The most lines a spec file may have, every line counted
   (blank lines, headings and the status line too). /spec tells the spec writer the limit, the spec reviewer reports a
   spec over it as a blocking finding, and a story that does not fit gets a split proposed on its issue instead of a
   spec. 0: no limit.` A default of 0 rather than none, so the key has a default (the config contract in
   `.claude/CLAUDE.md`) and the example can carry it without imposing a limit.
2. **Measured how.** The number of lines of the spec file as `awk 'END { print NR }' <file>` counts them: every line,
   and a last line without a newline counts too. It is the number of the last line that Read shows.
3. **When it applies.** `skills/spec/SKILL.md` gets, directly before the line `The prompt, with the placeholders filled
   in`, exactly: `The size limit applies only when iterations.maxSpecLines in the base-branch configuration is at least
   1; with the key absent or 0 nothing below is added.` Everything of decisions 4 to 6 and 8 is text added under that
   condition. Without the key the skill's static text still holds the conditional paragraph, but no prompt gets a line,
   the result block stays as today and the writer cannot return `split`.
4. **The writer's paragraph**, a conditional paragraph of the writer's prompt in `skills/spec/SKILL.md`, after the
   paragraph that ends `do not contradict a decision or a spec that exists.`, written like the S5 one, exactly:
   `<only when the size limit applies: The spec has at most <iterations.maxSpecLines> lines, every line of the file
   counted (blank lines, headings and the status line too). If the story cannot be specified within that, write no spec
   file: return Result: split with Spec: none and, on the Split line, the two or more stories it should be split into.`
   followed by the sentence of decision 5 and `>`.
5. **The split result**, the last sentence of that paragraph, exactly: `With Result: split, the block below gets one
   last line after Left: Split: <the proposed stories, one per line as "- <title>: <the acceptance criteria it
   takes>">.` The unconditional result block stays exactly as today (`Result: complete | partial | failed` and its
   four lines), so the lint pin on it holds.
6. **The reviewer's prompt** in "The spec review" step 3 gets, after the line `The spec template: ...`, only when the
   limit applies: `The size limit of a spec: <iterations.maxSpecLines> lines.`
7. **The reviewer's point** in `agents/spec-reviewer.md`, a new point 8: `when your prompt gives a size limit, the spec
   has at most that many lines (the number of its last line as Read shows it).` A spec over it is reported as exactly
   this line (its line number is the first line past the limit):

   ```
   - blocking <file>:<limit + 1> the spec has <n> lines, over the limit of <limit> (iterations.maxSpecLines)
   ```

   It is blocking by the sentence under the points, which already makes a broken point blocking, and fix rounds send it
   back as any blocking finding.
8. **The split.** In "The spec writer" step 4, a new case before `Result: partial`: `Result: split` with at least two
   lines `- <title>: <criteria>` on `Split`. No form check runs and no pull request opens. The session posts one
   comment on the issue, only when no comment of the maintainer's login on it starts with `Split proposed for #<issue>:`,
   with `gh issue comment <issue> --body-file <file>`, the body exactly:

   ```
   Split proposed for #<issue>: the story does not fit in a spec of <limit> lines (iterations.maxSpecLines).

   - <title>: <the acceptance criteria it takes>
   - <title>: <the acceptance criteria it takes>

   The maintainer decides. #<issue> stays at Spec; no spec pull request was opened.
   ```

   It then prints `Stopped: #<issue> does not fit the spec size limit of <limit> lines; a split is proposed on the
   issue. The status of #<issue> is Spec.` and does the clean-up of step 5 (a branch with nothing committed goes; a spec
   file of an earlier round is committed unfinished, not pushed). No status is set and no story is filed. A
   `Result: split` with fewer than two stories is a wrong form (`partial`), as today. **Later rounds**, one rule: a
   writer of a fix round of the spec review (status Spec, no pull request yet) gets the same comment, `Stopped:` line
   and clean-up. In the extra round or a check fix round (status Spec review, the spec pull request open) the comment's
   last line is instead `The maintainer decides. #<issue> stays at Spec review; the spec pull request #<pr> is not
   changed by this proposal.`, nothing is pushed, the pull request and its auto-merge stay as they are (off after the
   extra round's proposal; in a check fix round on, and the red check keeps it from merging), and the round ends as a
   round that does not finish (the extra round) or as a hand-over (a check fix round), with the reason
   `the story does not fit the spec size limit`. The first line is the same in every case, so a rerun posts no second
   comment.
9. **The template's sentence**, a new comment line in `templates/spec.md` directly under the comment below the status
   line, exactly: `<!-- Not in a spec: the issue restated (point to it), the history of a decision (state the rule and its
   reason only), the text of other specs (name the spec and its rule). -->` No heading changes.
10. **The README row.** The `iterations` row of the configuration table becomes, exactly:

    ```
    | `iterations` | Spec directory and name pattern, CHANGELOG path, milestone pattern, decisions directory, and the most lines a spec may have (`maxSpecLines`, default 0: no limit) |
    ```

11. **The example** gets `"maxSpecLines": 0` as the last key of `iterations`. This repository's `.claude/nightmill.json`
    is not changed; the maintainer sets a limit when wanted.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The configuration holds a size limit for a spec; without the key nothing changes | Decisions 1, 2, 3 (no prompt line, result block as today), 10, 11 |
| 2 | The spec writer is told the limit, and the spec reviewer reports a spec over it as a blocking finding | Decisions 4, 6, 7 |
| 3 | A spec that cannot fit proposes a split of the story instead, as a comment on the issue, and stops | Decisions 5, 8 |
| 4 | The spec template names what does not belong in a spec | Decision 9 |

## Tests

All in the new `tests/test-spec-size-limit.sh` (the tester's), which joins each file's text (newlines to spaces, runs
of spaces made one) before it searches, and prints one `FAIL: <criterion>: <what>` line per miss.

- Criterion 1: `schema`: `properties.iterations.properties.maxSpecLines` has type `integer`, minimum 0, default 0 and
  the description of decision 1. `example`: `templates/nightmill.example.json` has `iterations.maxSpecLines` 0.
  `validate`: copies of the example with the value 120 pass `scripts/validate-config.sh --strict`, with -1 and with
  `"x"` fail. `readme`: the line of `README.md` that starts `` | `iterations` | `` holds `` `maxSpecLines` `` and
  `default 0: no limit`. `applies`: `skills/spec/SKILL.md` holds the sentence of decision 3 (`grep -F` on the joined
  text) and does not hold `Result: complete | partial | failed | split`.
- Criterion 2: `writer`: `skills/spec/SKILL.md` holds the paragraph of decision 4 (from `<only when the size limit
  applies:` to `stories it should be split into.`) and the line of decision 6.
  `reviewer`: `agents/spec-reviewer.md` holds point 8 and the finding text of decision 7.
- Criterion 3: `split`: `skills/spec/SKILL.md` holds the sentence of decision 5 (in the conditional paragraph, not the
  unconditional result block), the comment's first line, both its last lines, `Split proposed for #<issue>:` as the
  duplicate check, and the `Stopped:` line of decision 8.
- Criterion 4: `template`: `templates/spec.md` holds the comment of decision 9; `tests/test-spec-template.sh`, which
  stays unchanged, still checks that its headings did not change.

Only the manual check shows that agents follow the text. **The manual check**, as `verification.manualCheckText`
says: in a scratch project with a board, start `claude --plugin-dir <a separate checkout of the feature branch>` (never
`--plugin-dir .` in this repository), with `"maxSpecLines": 120` in the scratch project's config on its base branch.

1. A small story (one acceptance criterion) at Ready: `/spec <n>` writes a spec of at most 120 lines, the review
   reports no size finding, and the story reaches Spec review.
2. Set the limit to 40 and put an oversized story (eight criteria across three areas) at Ready: `/spec <n>` opens no
   pull request, posts one comment starting `Split proposed for #<n>:` with two or more stories, prints the `Stopped:`
   line, leaves the status at Spec and deletes the empty branch.
3. Move that story back to Ready and run `/spec <n>` again: no second comment is posted.
4. Remove the key and run step 1 again: the run is the same as before this iteration.

## Files touched

- `schema/nightmill.schema.json`: the key `iterations.maxSpecLines` (decision 1). Implementer.
- `templates/nightmill.example.json`: `"maxSpecLines": 0` (decision 11). Implementer.
- `README.md`: the `iterations` row of the configuration table (decision 10). Implementer.
- `skills/spec/SKILL.md`: decisions 3 to 6 and 8, in "The spec writer" (the prompt and step 4) and "The spec review"
  step 3. Implementer.
- `agents/spec-reviewer.md`: point 8 (decision 7). Implementer.
- `templates/spec.md`: the comment of decision 9. Implementer.
- `tests/test-spec-size-limit.sh`: new, the tests above; it follows the rules that `tests/test-lint-pipefail.sh` and
  `tests/test-mktemp-template.sh` check on every `tests/*.sh`. Tester.
- `tests/lint.sh`: one section, placed directly after the line `bash tests/test-fast-lane.sh "$PWD" || fail=1`:
  `echo "== a spec stays within its size limit"`, a comment `# Iteration 71 (#347): iterations.maxSpecLines; the pins
  live in tests/test-spec-size-limit.sh.`, and `bash tests/test-spec-size-limit.sh "$PWD" || fail=1`. Tester. No
  existing lint rule changes, and the implementer edits no file under `tests/`.
- `CHANGELOG.md`, under `Unreleased`, added by the `/next` session, exactly:

  ```
  - Iteration 71 (#347): a spec stays short: `iterations.maxSpecLines` (default 0, no limit) holds a spec to a number of lines; the spec reviewer reports a spec over it as blocking, and a story that does not fit gets a split proposed on its issue instead of a spec.
  ```

## Risks

- A writer may cut needed rules to fit. The reviewer still checks every criterion (point 1), and the split is the way
  out, so a spec never fits by dropping a criterion.
- A limit set too low makes most stories propose a split. The default is no limit, and the maintainer chooses the
  number.
- A story left at Spec after a split may look stuck in `/status`. That is the existing state of a stopped `/spec`, and
  the comment says why.

## Size estimate

S: about 10 lines in the schema, example and README, about 20 in `skills/spec/SKILL.md`, 4 in the reviewer, 1 in the
template, 4 in the lint and about 70 in the new test, so about 110 changed lines; at the upper edge of S. This spec
has 203 lines.

## Not done

- No estimate of a story's size before the spec (#179).
- No delivered spec is shortened, and the lint does not check the length of specs in `docs/specs`.
- No limit is set in this repository's `.claude/nightmill.json`.
- The session does not count lines itself; the reviewer does. No story is filed from a split, and no label is set.
- No heading of `templates/spec.md` changes, and the workflow skill does not change.
