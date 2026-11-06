# Iteration 20: a separate spec reviewer reviews the spec before it goes to Spec review

Status: delivered in iteration 20 (PR #83)

Story: #39, epic #30 (Independent spec review). Adds the agent `agents/spec-reviewer.md` and a review step in
`skills/spec/SKILL.md`: after the `specWriter` subagent has returned a spec of the right form and before the spec is
committed, pushed and opened as a pull request, a `specReviewer` subagent on the model the configuration gives the role
reads it against the issue, the decisions and the existing specs, and reports findings in the format iteration 18 (#36)
defined; blocking findings go back to a new spec writer for at most `review.maxFixRounds` fix rounds. Adds a lint
section and one README sentence. No config key (it reads `roles.specReviewer.model` and `review.maxFixRounds` of
iteration 10), no script, no change to the workflow skill (a hot file: the findings format, the rounds and the pairing
rule are the ones it already holds), none to the status flow or the slot marker: none of `escalation.storyTriggers`
applies, so the PR may auto-merge. The change touches `skills` and `agents`, so the manual check applies.

**Depends on #36 (iteration 18).** This story reuses its agent pattern, its section "Findings and fix rounds" in the
workflow skill and the lint it adds, so it is implemented after #36 has merged.

## Goal

Before a spec moves to Spec review, a different agent, on a model at least as strong as the writer's, reviews it
against the issue, the decisions and the existing specs, and the writer fixes what it finds.

## Facts this rests on

- Iteration 14 made `/spec` launch a `specWriter` subagent (a fresh agent, never a fork, never the `worker`, the model
  passed explicitly, counted against `parallel.maxAgents`). The session creates the spec branch from the up-to-date
  base before the launch, the writer writes only the spec file in the main checkout and returns a result block, the
  session checks the form (one changed file, the title, the status line), commits the spec only, opens the pull request
  and sets Spec review. A stop (partial, failed, a wrong form, an unusable model) leaves the story at Spec, opens no pull
  request, keeps the unfinished file in a local, unpushed commit and removes an empty branch ("Clean-up after a stop").
- Iteration 18 (#36) adds, and this story reuses unchanged: the section "Findings and fix rounds" of
  `skills/workflow/SKILL.md` (the block `Review: findings | no findings`, `Blocking: <n>`, `Advisory: <n>` and the lines
  `- blocking|advisory <file>:<line> <text>`; blocking and advisory defined; the rounds, a story reviewed at most
  `1 + review.maxFixRounds` times; the pairing checked with `validate-config` and its `ranks below` line; a review
  that cannot be had stops the run), `agents/code-reviewer.md` as the model of a read-only reviewer
  (`tools: Read, Grep, Glob`, `model:` equal to the schema default), the review step of `/next` and `/fix`, and the lint
  section "a separate code reviewer reviews the change".
- The definitions of blocking and advisory in that section name code (a criterion without a test, work beyond the
  spec, a violated invariant, an item of "Not done" done anyway). For a spec the same words apply to the points listed
  below; the agent file of the spec reviewer says so, the workflow section is not changed.
- Iteration 15: the validator reports `specReviewer on "<m1>" ranks below specWriter on "<m2>"` on the path
  `roles.specReviewer.model` when the reviewer ranks below the writer.
- The spec is in the main checkout, inside the project directory, uncommitted, on the spec branch when the review
  runs. A read-only agent reads it by its absolute path there, and reads `docs/decisions/` and `docs/specs/` the same
  way. Unlike the slots of `/next` and `/fix`, nothing here is outside the project directory.
- #40 follows this story: what happens to blocking findings that are left after the rounds (the issue comment, the
  rule in "CI and merging" for spec pull requests). Until then this story has the same interim as iteration 18.

## Decisions

**1. An agent file, like the code reviewer.** The spec reviewer must change nothing, and an agent definition with
`tools: Read, Grep, Glob` says so in a way a prompt sentence cannot. `agents/spec-reviewer.md` has `model:` equal to the
schema default of `roles.specReviewer.model`, kept in step by the lint; the call overrides it explicitly as always.

**2. The reviewer gets the facts, not the writer's account.** The prompt carries the story (issue body and comments),
its epic, the path of the spec, the directories of the decisions and the existing specs, and from the configuration
`escalation.storyTriggers`, `verification.manualCheckPaths` and `invariants`. It does not carry the writer's own
`Criteria`, `Decisions` or `Left` lines or any of its transcript: the reviewer shares no context with the writer.

**3. What a spec review checks** (the agent's body, one finding when a point fails):

1. every acceptance criterion of the issue is covered by a rule of the spec and is testable: the spec names the test
   or the manual scenario that protects it;
2. exact rules and numbers are in the spec itself: no value left as "suitable", "a few" or "as the implementer sees fit",
   and no number pushed into the issue;
3. the spec contradicts no decision in `docs/decisions/` and no existing spec in `docs/specs/` (it names the one it
   contradicts);
4. it has a "Not done" list;
5. it states whether the change is one of `escalation.storyTriggers` and whether the manual check of
   `verification.manualCheckPaths` applies;
6. it adds no scope the issue does not ask for (a rule, a flag, a key or a skill the issue never mentions);
7. its first heading and status line have the form the skill checks (`# Iteration <N>:` and
   `Status: draft, awaiting approval (#<issue>)`).

A point that fails is **blocking** when it breaks one of 1 to 6 or 7; **advisory** is anything else (wording,
ordering, a clearer name).

**4. Only blocking findings go back, to a new writer.** As in iteration 18: a fresh `specWriter` agent on the same
role model, with the same prompt as the first writer and, at the end, the blocking lines and the instruction to fix
exactly those in the spec file and nothing else. It edits the file in place; the session then checks the form again and
reviews again. At most `1 + review.maxFixRounds` reviews.

**5. The pairing is checked with the validator, once.** Before the first review the session runs `validate-config`; a
line on `roles.specReviewer.model` with `ranks below` stops the run. A reviewer model that is not in `models.ranking`
is a warning of the validator and does not stop it.

**6. A review that cannot be had stops the run**, as in iteration 18, never read as "no findings"; the clean-up after
a stop is the writer's existing one.

**7. Interim until #40.** When the rounds are used up and blocking findings remain, the session still opens the spec
pull request with the findings listed under a plain heading and does **not** enable auto-merge, because a spec pull
request that merges by itself over a known blocking defect is what this epic exists to prevent. #40 replaces the
heading with its own rule and adds the issue comment and the "CI and merging" sentence.

## The agent

`agents/spec-reviewer.md`:

```markdown
---
name: spec-reviewer
description: Reviews a spec against its issue, the decisions and the existing specs before it goes to Spec review. Reads only, changes nothing, and reports findings in one fixed format. Used by /spec on the specReviewer model.
tools: Read, Grep, Glob
model: opus
---
```

and a body that says, in this order:

1. You review a spec you did not write, with fresh eyes. You change nothing: no file, no board item, no pull request,
   no branch. You start no other agent and you ask no questions; you work from the prompt and from what you can read.
2. The seven points of decision 3, each to be reported as a finding when it fails, and how to look: read the issue in the
   prompt, read the spec at the path, search `docs/decisions/` and `docs/specs/` for a rule the spec contradicts.
3. A finding is **blocking** (it breaks one of the seven points) or **advisory** (anything else). Do not pad: report
   what you can point at. `<file>` is the spec's path and `<line>` the line in it; a finding about something missing
   (a criterion the spec does not cover) names the spec's path and `-` as the line.
4. End your last message with exactly the block of "Findings and fix rounds" in the workflow skill, and nothing after it.

The body repeats the format lines so that the agent file is complete by itself; the lint compares them with those of
the workflow skill and of `agents/code-reviewer.md`.

## `/spec`

After the writer's `Result: complete` and a right form (the step "Read the result" of "The spec writer") and before the
commit, the push and the pull request, a new section "The spec review" in `skills/spec/SKILL.md` and, in "The spec
writer", the line that points at it. The session:

1. **The pairing.** Runs `validate-config` of the shell in use on the project's config
   (`"${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.ps1" -Config <project>/.claude/nightmill.json`, or
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.sh" <project>/.claude/nightmill.json`). A line on
   `roles.specReviewer.model` with the text `ranks below` stops the run with
   `Stopped: the specReviewer ranks below the specWriter: <the text of that line>. Nothing was reviewed; the status of
   #<issue> is Spec.` and the clean-up of "The spec writer". A validator that cannot run (exit code 2, missing script)
   stops it with `Stopped: the pairing could not be checked: <the reason>. Nothing was reviewed.`
2. **Counts and launches.** One Agent call, after counting the agents as for the writer: `subagent_type`
   `nightmill:spec-reviewer`, not a fork, with the `model` that **Agent roles and models** gives `specReviewer`
   (`roles.specReviewer.model`, else the schema default), passed explicitly. A model that cannot be used stops the run
   with that section's line for `specReviewer`, naming the status Spec, and does the clean-up.
3. **The prompt**, filled in by the session:

   ```markdown
   Review the spec <absolute path of the spec> for story #<issue> "<title>" in <owner>/<repo> (read it, and read
   anything else you need under <absolute repository path>).

   The story, in full: <issue body and comments>. Its epic #<epic>, in full: <epic body>.
   The decisions are in <absolute path of iterations.decisionsDir>, the existing specs in <absolute path of
   iterations.specDir>.
   The change is a story trigger when it is one of: <escalation.storyTriggers, one per line>.
   The paths that require a manual check: <verification.manualCheckPaths>.
   The invariants of the project: <config invariants, one per line>.

   End with the findings block of the workflow skill, and nothing after it.
   ```
4. **Reads the block.** `no findings`, or advisory findings only: go on to the commit, keeping the advisory lines. With
   blocking findings, while fewer than `review.maxFixRounds` fix rounds have been used: a fix round (a fresh specWriter,
   the writer's prompt plus the blocking lines and "Fix exactly these blocking findings in the spec file and nothing
   else"), the form check of "Read the result" again (a failure stops the run as there), and a new review from step 2
   (the pairing is not checked again). No valid block, or an error: stop with
   `Stopped: the spec review could not be had: <the reason>. Nothing was opened.` and do the clean-up.
5. **After the last review.** Blocking findings that remain are listed in the spec pull request under the heading
   `Open review findings` (each as in the block) and auto-merge is **not** enabled; the pull request says so. Advisory
   findings are listed under `Review notes`, one line each. The body keeps `Spec for #<issue>.` and the writer's line
   and gets, on its own line, `Reviewed by the specReviewer role on <model> after <r> fix round(s).`

The reviewer reads the file in the working tree, so the review runs before the commit; the commit then holds the spec
as the last round left it. The statuses, the comment on the issue, the stop at Spec review and every hard rule stay with
the session as before.

## README

In "Agent roles and models", the sentence added in iteration 14 for `/spec` gets one more clause: a `specReviewer`
subagent on its configured model reviews the spec before it goes to Spec review and the blocking findings go back to the
writer for at most `review.maxFixRounds` rounds.

`.claude/CLAUDE.md`, the layout line `agents  worker.md, code-reviewer.md` (iteration 18) becomes
`agents  worker.md, code-reviewer.md, spec-reviewer.md`.

## Tests

Each acceptance criterion of #39 is a test or a manual scenario. `/spec` is a conversation, so the lint pins the wording
and the manual check does the behaviour.

**`tests/lint.sh`**, new section "== a separate spec reviewer reviews the spec", written like the one of iteration 18:

- `agents/spec-reviewer.md` exists with `name: spec-reviewer`; its `tools:` line is exactly `Read, Grep, Glob`; its
  `model:` line equals the schema default of `roles.specReviewer.model`; its body says it changes nothing and contains
  `acceptance criterion`, `Not done`, `decision`, `escalation`, `scope`, `blocking`, `advisory` and `no findings`;
- the format lines of its findings block equal those of the workflow skill's section "Findings and fix rounds" and of
  `agents/code-reviewer.md` (the same check, now over three files);
- `skills/spec/SKILL.md` contains `nightmill:spec-reviewer`, `roles.specReviewer.model`, `Findings and fix rounds`,
  `validate-config`, `Stopped: the specReviewer ranks below`, `Stopped: the spec review could not be had`,
  `Open review findings`, `Reviewed by the specReviewer role on` and `not a fork`;
- the check on `agents/` of iteration 18 now allows exactly `agents/worker.md`, `agents/code-reviewer.md` and
  `agents/spec-reviewer.md`.

`bash tests/check.sh` stays green.

## Verification

The change touches `skills` and `agents`, so the manual check applies. In a throwaway project with nightmill installed
from this checkout (`claude --plugin-dir <checkout>`), a board and Ready throwaway stories:

1. **A planted defect is caught and fixed.** A story with an acceptance criterion the spec is likely to leave without a
   test or manual scenario (or that contradicts a decision planted in `docs/decisions/`): `/spec` runs the writer, the
   reviewer returns a block with a `blocking` finding naming the spec's path and line, a fix round runs a fresh writer,
   the reviewer runs again and returns `Review: no findings`; the pull request says `Reviewed by the specReviewer role on
   opus after 1 fix round(s).`
2. **No findings is explicit.** A trivial story: `Review: no findings`, `Blocking: 0`, `Advisory: 0` and no fix round.
3. **Advisory only** goes on, is listed under `Review notes` and does not stop auto-merge.
4. **Rounds are used up.** A contradiction the writer cannot resolve: after `review.maxFixRounds` rounds the pull
   request is opened with `Open review findings`, auto-merge is off and the pull request says why; the story is at Spec
   review. With `review.maxFixRounds` at 0 the spec is reviewed once and nothing is sent back.
5. **The reviewer changes nothing.** A hash of the spec file before and after a review is the same, `git status` shows
   only the spec, and the board is unchanged; the agent has no `Bash`, `Write` or `Edit`.
6. **The pairing stops the run.** `roles.specReviewer.model` set to `haiku`: `Stopped: the specReviewer ranks below the
   specWriter: ...`, nothing reviewed, no pull request, the story at Spec, the unfinished spec in a local commit and the
   original branch checked out. A `no-such-model` for the reviewer: the `Stopped:` line of the workflow skill for
   `specReviewer`.
7. **The reviewer is separate.** The prompt of the reviewer, as the session sent it, holds none of the writer's
   `Criteria`, `Decisions` or `Left` lines.
8. **A review that cannot be had** (a reply without a block): `Stopped: the spec review could not be had`, no pull
   request, the same clean-up.

The PR's "How verified" lists the eight results and the check.

## Not done

- What happens to open blocking findings beyond the interim: the issue comment, the sentence in "CI and merging" for spec
  pull requests, and the final form of the findings in the pull request are #40.
- No change to the workflow skill, to what the writer writes, to the findings format, to the number of rounds or to the
  models.
- No code review (#36, #37), no tester (#42 to #45).
- No re-run of the review after the maintainer asks for changes at Spec review: a revision is a follow-up pull request
  by the maintainer's request, as before.
- No script, no config key, no new board status, no change to who sets a status or to the slot marker.
