# Iteration 40: specs are written from a template, and the lint checks their headings

Status: draft, awaiting approval (#150)

Story: #150, epic #107 (Hardening from the code review), finding MD-S16 of the review of 0.2.0. A new file
`templates/spec.md` holds the title, the status line and seven required sections; `/spec`'s writer writes from it, the
spec reviewer checks its headings, and `tests/lint.sh` checks the headings of every spec from iteration 40 on in
`iterations.specDir`. Changes `templates/spec.md` (new), `skills/spec/SKILL.md`, `agents/spec-reviewer.md`,
`tests/lint.sh`, `README.md` and `CHANGELOG.md`. Nothing else.

## Story trigger and manual check

**Not a story trigger.** No config key is added, renamed or removed (`templates/spec.md` is a file of the plugin, not a
key; the lint reads the existing `iterations.specDir` and `iterations.specPattern`), the status flow and who sets a
status do not change, and the slot marker format does not change. No decision record.

`skills` and `agents` change, so **the manual check applies** (steps under Tests). No script in `scripts/` changes, so no
smoke step is added. `tests/lint.sh` has no PowerShell twin (`tests/check.ps1` runs `tests/check.sh` through bash), so
the new section exists in bash only, like every other lint section.

## Facts this rests on

Read on `main` at 633ebcd.

- **The finding holds.** `templates/` has `CLAUDE.snippet.md`, `nightmill.example.json`, `board-template.json` and
  `ISSUE_TEMPLATE/`; no spec template. The writer's prompt in `skills/spec/SKILL.md` takes "the most recent spec in
  <iterations.specDir> as the model for the form". The session's form check ("Read the result", step 4) checks the first
  heading `# Iteration <N>:`, the line `Status: draft, awaiting approval (#<issue>)` and exactly one changed file; point 7
  of `agents/spec-reviewer.md` checks the same two lines. No lint section reads `docs/specs`.
- **The 38 specs on `main` (1 to 38) differ.** `## Not done` and `## Goal` are in 38, `## Tests` in 37,
  `## Facts this rests on` in 36, `## Verification` in 30, `## Decisions` in 27, `## Left` in 5; none has a criteria
  table, a files section, a risks section or a size. The trigger and manual-check statement is a bold paragraph in the
  introduction (iterations 37, 38). A delivered spec's status line reads `Status: delivered in iteration <N> (PR #<pr>)`.
  Iteration 35 has a line that starts `#128` and is not a heading. Iteration 39 (#159) is an open pull request (#197).
- **`/init` would not install the file.** `scripts/render-templates.*` read only `templates/ISSUE_TEMPLATE/`, and
  `/init` names `CLAUDE.snippet.md`, `nightmill.example.json` and `board-template.json` by name; it copies no folder.
- **The lint reads config** with `scripts/lib/json.sh` (`json_load`, `json_get`), loaded before
  `== roles and models are described`; it uses no jq, python or yq. A throwaway input checked inside the lint has a
  precedent: the pairing check builds a config with `mktemp` and expects the validator to refuse it.
- `skills/spec/SKILL.md` has two prompts to subagents; `== text from issues is data` counts them (`spec:2`).

## Decisions

1. **The required sections, their exact headings and their order** (each a line of its own, exactly this text):
   `## Story trigger and manual check`, `## Criteria and rules`, `## Tests`, `## Files touched`, `## Risks`,
   `## Size estimate`, `## Not done`. Before them: the first heading `# Iteration <N>: <what>` and a `Status: ` line
   (the draft text is `Status: draft, awaiting approval (#<issue>)`). The trigger statement comes first because the
   reviewer and the maintainer must see an escalation before anything else (it is in the introduction today); the table
   follows the decisions it points into; Not done stays near the end, where all 38 specs have it.
2. **Three optional sections**, kept in the template because most specs have them: `## Facts this rests on` and
   `## Decisions` (between the trigger section and the table), `## Left` (last). Their guidance comment begins
   `Optional.`; the lint does not look for them. A section of the writer's own (`## README`, `## The scripts`) may stand
   anywhere between the required ones; `## Verification` is not kept: its steps go under `## Tests`.
3. **Size estimate scale:** `S` up to 100 changed lines, `M` 101 to 400, `L` more than 400, counted over all files
   touched, with the reason.
4. **Guidance as HTML comments** (`<!-- ... -->`), one line under each heading: invisible on GitHub if one is left in;
   the writer's prompt says to delete them.
5. **The session's form check stays as it is.** A wrong form stops the run with no fix round; a missing heading is a
   blocking finding of the reviewer (point 7), which the writer fixes in a fix round, and in this repository the lint
   fails the spec pull request. Step 4 of "Read the result" gains one sentence saying so.
6. **Existing specs are exempt, not migrated.** The lint checks a spec whose file name is `iteration-<N>-<slug>.md`
   with N of at least 40, and prints one line for the rest. Migrating 39 specs (1 to 39, including the six in flight,
   34 to 39) is not asked for, would rewrite delivered records, and would conflict with the open pull requests #194 and
   #197. This spec is number 40, so the lint checks it; it follows the template.
7. **The required headings live twice:** in `templates/spec.md` and in one array in `tests/lint.sh`; the lint checks
   the template against the array, so the two cannot drift apart unnoticed.
8. **The template path in projects** is the plugin's: the session passes the absolute path of
   `${CLAUDE_PLUGIN_ROOT}/templates/spec.md`, as it expands in the session, into both prompts (the writer and the
   reviewer cannot expand it). The lint is nightmill's own and checks only this repository's specs.

The template, in full (`templates/spec.md`):

```markdown
# Iteration <N>: <what changes, in one line>

Status: draft, awaiting approval (#<issue>)

<!-- One paragraph: the story and its epic, what changes, and every file that changes. -->

## Story trigger and manual check

<!-- Is the change one of escalation.storyTriggers (name it, or say none is)? Does the manual check of verification.manualCheckPaths apply (which path changes)? Which shells, which smoke steps? -->

## Facts this rests on

<!-- Optional. What was read or run for this spec, on which commit, and what it showed; whether the finding still holds. -->

## Decisions

<!-- Optional. Numbered: each choice the issue does not settle, with its exact rule, its numbers and the reason. -->

## Criteria and rules

<!-- One row per acceptance criterion of the issue, in the issue's order. -->

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | <criterion> | <where the spec settles it> |

## Tests

<!-- Per criterion: the test or lint section names, what each asserts, and what only the manual check can show; then the manual check's steps. -->

- Criterion 1: <test name>: <what it asserts>

## Files touched

<!-- Every file that changes, one line each with what changes; the CHANGELOG bullet in full. -->

## Risks

<!-- What can go wrong with the change or its rollout, and what limits it. -->

## Size estimate

<!-- S (up to 100 changed lines), M (101 to 400) or L (more than 400), with the count behind it. -->

## Not done

<!-- What a reader might expect and this iteration does not do. -->

## Left

<!-- Optional. What the writer could not settle, for the maintainer. -->
```

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | `templates/spec.md` has the required sections | Decisions 1 to 4; the template above |
| 2 | `/spec` writes from the template | Decisions 5 and 8; `skills/spec/SKILL.md` and `agents/spec-reviewer.md` under Files touched |
| 3 | The lint checks the headings of every spec in `iterations.specDir`, existing specs exempt or migrated | Decisions 6 and 7; `tests/lint.sh` under Files touched |

## Tests

**`tests/lint.sh`**, new section `== specs follow the template`, after `== the spec review is recorded in the spec pull
request` and before `== load is wired`. Its check is one function, `spec_form <file> <N>`, written with awk (no jq,
python or yq). It ignores the lines inside fences and a trailing carriage return and trailing blanks, and prints one
line per problem, nothing when the form is right. A fence line is one matching `/^```/` (as at lines 699 and 716 of
`tests/lint.sh`), so an opening line with an info string such as ```` ```markdown ```` counts; `~~~` fences are not
recognised.

- `FAIL: <file>: the first heading is not '# Iteration <N>:'` (a heading is a line matching `^#+ ` (no interval
  expression, which not every awk has), so `#128 ...` is not one);
- `FAIL: <file>: no 'Status: ' line before the first '## ' heading`;
- `FAIL: <file>: missing heading '<h>'`, `FAIL: <file>: heading '<h>' appears <c> times`, and
  `FAIL: <file>: heading '<h>' comes before '<g>'` when a required heading stands above one that precedes it in the
  array `spec_req` (the seven of decision 1, in order).

What the function cannot check: whether a section's content is good, whether the table has a row per criterion, or
whether a `Status: ` line is the right one. That is the reviewer's and the maintainer's.

- Criterion 1: `spec_form templates/spec.md '<N>'` prints nothing (the template has the title with `<N>`, a status
  line and the seven headings once each, in order); `templates/spec.md` has the exact line
  `Status: draft, awaiting approval (#<issue>)`.
- Criterion 2, on each file joined into one line (as in `== text from issues is data`): `skills/spec/SKILL.md` names
  `templates/spec.md` at least twice (the writer's and the reviewer's prompt), contains
  `keep its headings, with their exact text and in their order` and no longer contains `as the model for the form`;
  `agents/spec-reviewer.md` names `templates/spec.md` and contains `in its order`; `README.md` names
  `templates/spec.md`. The count of prompts in `== text from issues is data` stays `spec:2`. Only the manual check shows
  that the writer actually follows the template.
- Criterion 3: `iterations.specDir` is read from `.claude/nightmill.json` (`json_get`; empty is
  `FAIL: .claude/nightmill.json has no iterations.specDir`); `iterations.specPattern` other than
  `iteration-<N>-<slug>.md` is `FAIL: ... iterations.specPattern is '<p>', the lint knows only 'iteration-<N>-<slug>.md'`.
  A file in the folder that does not match `iteration-*.md` is ignored. N is taken with the bash regex
  `^iteration-([0-9]+)-.+\.md$` (`BASH_REMATCH[1]`); an `iteration-*.md` that does not match it is a `FAIL`; N below
  40 is counted, N of 40 or more goes through `spec_form`. Then one line:
  `exempt: <k> specs below iteration 40 (written before the template)`.
  Four throwaway specs in a `mktemp -d` folder, made from `templates/spec.md` with `<N>` set to 99, check the function
  itself: unchanged it prints nothing (else `FAIL: the spec form check rejected a spec filled in from templates/spec.md`
  with its output); without the `## Risks` line it prints `missing heading '## Risks'`; with `## Tests` and
  `## Files touched` exchanged it prints `comes before`; with `## Not done` between two fence lines it prints
  `missing heading '## Not done'`; the unchanged one checked with N 98 prints `the first heading`. Each miss is
  `FAIL: the spec form check accepted <case>`.
  **Clean-up of the folder**, as `pair_cfg` at lines 150 to 157 (made with `mktemp`, removed by a plain `rm -f` after
  its checks, no trap): no new `trap` (it would replace the `EXIT` trap at line 18). The four cases are built and
  checked in one function, `spec_cases <dir>`, which prints the `FAIL` lines of the cases and nothing else. The section
  runs `spec_tmp=$(mktemp -d)`, then `rc=0; cases_out=$(spec_cases "$spec_tmp") || rc=$?`, then
  `rm -rf "$spec_tmp"` on the next line, and only then reports: it prints `cases_out` and sets `fail=1` when it is not
  empty, and prints `FAIL: the spec form self-test exited <rc>` and sets `fail=1` when `rc` is not 0. A command that
  fails inside `spec_cases` cannot end the script before the `rm`: the call is the left side of `||`, where bash does
  not apply `set -e`, and its status is captured in `rc`; a failed build step gives a wrong output, which the case's
  comparison reports as a miss. Only a signal that kills the lint leaves the folder behind, as it would `pair_cfg`.

`bash tests/check.sh` stays green, and `tests/smoke-render.*` are unchanged and green (nothing new is rendered).

**Manual check**, with nightmill loaded from a separate checkout of the branch (`claude --plugin-dir <checkout>`, never
the checkout being edited, decision 0003), in a throwaway repository with a board and one Ready story:

1. `/spec <n>`: the written spec has the title, the status line and the seven required headings in order, no template
   comment left, and the review has no blocking finding on point 7.
2. Copy that spec as `docs/specs/iteration-99-manual.md` into a copy of the branch, change the number in its first
   line to 99 (`# Iteration 99:`, the rest of the line and the file unchanged; a throwaway repository's spec has a
   number below 40, which the lint would only count as exempt), and run `bash tests/lint.sh`: the new section reports
   nothing for it.
3. Delete `## Risks` from the spec in the throwaway repository and launch the spec reviewer on it as `/spec` does: a
   blocking finding names the missing heading.

## Files touched

- `templates/spec.md` (new): the template above.
- `skills/spec/SKILL.md`, the writer's prompt: `Read every spec and decision the story or the epic references, and the
  most recent spec in <iterations.specDir> as the model for the form: <their paths>.` becomes
  `Read every spec and decision the story or the epic references: <their paths>. Write the spec from the template
  <absolute path of ${CLAUDE_PLUGIN_ROOT}/templates/spec.md>: keep its headings, with their exact text and in their
  order, fill in every section that is not optional, delete its comments, and put a section of your own only between
  them.` The reviewer's prompt gains, after the line of the manual-check paths,
  `The spec template: <absolute path of ${CLAUDE_PLUGIN_ROOT}/templates/spec.md>.` Step 4 of "Read the result", after
  `That is the form only; whether the spec is good is for the reviewer and the maintainer.`, gains
  `The headings of templates/spec.md are checked by the reviewer, not here.`
- `agents/spec-reviewer.md`, line 24 (point 7) becomes exactly:

  ```markdown
  7. its first heading starts `# Iteration <N>:`, it has the line `Status: draft, awaiting approval (#<issue>)`, and it has every heading of the spec template in your prompt (`templates/spec.md` of the plugin) whose comment does not begin `Optional.`, with the template's text and in its order.
  ```
- `tests/lint.sh`: the section of Tests; the header comment is unchanged.
- `README.md`: the row of `/nightmill:spec [N]` becomes `Takes a Ready story and writes its spec from
  templates/spec.md as its own PR, sets Spec review and stops.` (`templates/spec.md` in backticks).
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 40 (#150): specs follow a template. templates/spec.md holds the
  title, the status line and seven required sections (story trigger and manual check, criteria and rules, tests, files
  touched, risks, size estimate, not done); /spec's writer writes from it, the spec reviewer checks its headings, and
  the lint checks the headings of every spec from iteration 40 on in iterations.specDir (earlier specs are exempt). No
  config key; /init installs nothing new.` (paths and commands in backticks).

Not touched: `skills/init/SKILL.md`, `scripts/render-templates.*`, the schema, the example config, the workflow skill.

## Risks

- **Release lag.** This repository runs `/spec` from the installed release. Until a release carries this iteration, a
  new spec (41 and up) is written without the template and its pull request fails the new section. Such a pull request
  is revised (headings added) before it merges, never merged red; installing the release branch as a preview
  (`.claude/CLAUDE.md`) avoids it.
- **A spec above 40 on `main` before this lands** (none exists today; 39 is the highest, open) fails this pull request's
  check. The implementer then adds the missing headings to it in this pull request, changes nothing else in it, and names
  it in the pull request.
- **Content.** The lint sees headings only; an empty section passes it. The reviewer's checklist (points 1, 2, 4) stays
  the check of content.

## Size estimate

`M`: about 50 lines of template, 60 of lint, 10 in the skill, the agent and the README, 5 of CHANGELOG: about 125
changed lines in six files.

## Not done

- No migration of specs 1 to 39, including 34 to 39 in flight; no change to their headings or status lines.
- No heading check in the session's form check (decision 5), and no check of a section's content.
- No lint of specs in other projects: a project's own lint is its own; `/init` installs no template and no lint.
- No PowerShell lint, no new script, no smoke step, no config key, no change to the status flow.
- No change to the workflow skill's description of a spec, `/next`, `/fix` or the code reviewer.
