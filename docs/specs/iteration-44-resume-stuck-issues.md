# Iteration 44: /spec and /next, named by number, finish a story that an earlier run left at Spec, Spec review, In progress or Review

Status: draft, awaiting approval (#112)

Story: #112, epic #107 (Hardening from the code review), finding HI-4 of the review of 0.2.0. With an issue number,
`/spec` also takes a story at Spec or Spec review, and `/next` also takes one at In progress or Review, when the story's
own work exists (a branch, a slot holding it, a pull request). The skill reads what exists, prints where it resumes,
and goes on from the first step that left no trace. Every step that can meet its own earlier result is made idempotent:
a status already set is only read back, an existing branch is switched to, an open pull request is reused, a comment
already posted is not posted again, and a CHANGELOG entry or status line already written is not written twice. To make
an implementation branch findable, `/next` puts the iteration number into its branch name, as `/spec` already does.
Without a number nothing changes. Changes `skills/workflow/SKILL.md`, `skills/spec/SKILL.md`, `skills/next/SKILL.md`,
`skills/status/SKILL.md`, `README.md`, `.claude/CLAUDE.md`, `tests/lint.sh` and `CHANGELOG.md`. No script, agent, hook, schema or config
file.

## Story trigger and manual check

**Not a story trigger**, as far as this spec can judge (see Left, item 1):

- *A change to the status flow or who sets a status*: no. The eight statuses, their order and who sets each stay as the
  table in `skills/workflow/SKILL.md` has them. No transition is added: a resumed `/spec` still moves Spec to Spec
  review, a resumed `/next` still moves In progress to Review, and nothing moves a story backwards; Ready and Approved
  are still set only by the maintainer. What changes is which status a skill accepts at its start when it is named by
  number. The invariant "Fixed flow" is not touched, so no decision record is written.
- *A new, renamed or removed config key*: no. The rules read `git.specPrefix`, `git.featurePrefix`,
  `iterations.milestonePattern`, `iterations.specDir`, `iterations.changelog` and `worktrees.stalledAfterMinutes`,
  which all exist.
- *A change to the slot marker format*: no. No script changes. The one new step name, `resumed` (decision 9), is a value
  of the existing `step` key, which `--report` already accepts (1 to 40 letters, digits or `-`) and which the previous
  version prints as it is. So slot markers and config keys stay readable by the previous version ("Compatible").

**The manual check applies**: `skills` is in `verification.manualCheckPaths`, and four skills change. Its steps are under
Tests. No script changes, so no smoke step is added and "Both shells" is not touched. `skills/workflow/SKILL.md` is in
`parallel.hotFiles`: this story is not run at the same time as another story that changes the workflow skill.

## Facts this rests on

Read on `main` at b76b0cd (release 0.5.0 and one fix after it). The issue was read against d13c9b5; the finding still
holds on b76b0cd.

- **The refusal.** `skills/workflow/SKILL.md`, "Picking an issue", rule 1: "An issue whose board status is not the
  skill's status is refused with one line that names the status found and the skill that takes it, for example
  `#12 is at Spec review, not Ready; /spec only takes Ready stories.` Nothing is changed." `skills/spec/SKILL.md` step 1:
  "take that issue; refuse when it is not at Ready"; `skills/next/SKILL.md` step 1: "refuse when it is not at Approved".
  "Stories and bugs": "An agent only works on issues whose status is Ready (spec, or bug fix) or Approved
  (implementation)."
- **What promises otherwise.** README, line 30: "a different agent can pick a story up at any stage because the board
  and the repository hold the state". `skills/status/SKILL.md`, item 2: "In progress or Spec with nothing behind it is
  `/next`, `/spec` or the maintainer". `/spec` step 6: "If the maintainer asks for changes, revise the spec in a
  follow-up PR and keep the status at Spec review" (inside the same session, after the stop).
- **What a `/spec` run leaves, step by step.** Step 2.1 sets Spec. Step 2.2 picks the iteration number N and puts the
  issue into milestone `iteration-<N>` (`iterations.milestonePattern`). "The spec writer" step 1 creates
  `<git.specPrefix><N>-<slug>` from `origin/<git.baseBranch>` in the session's own checkout and switches to it; the
  writer writes `<iterations.specDir>/iteration-<N>-<slug>.md` uncommitted; the review runs on the working tree; step 4
  commits it (the PR title `docs: iteration <N> spec (#<issue>)`), pushes, opens the PR with the body's first line
  `Spec for #<issue>.` and enables auto-merge unless a blocking finding is open (then the body has
  `Auto-merge is not enabled: blocking review findings are still open (see Review).`), and switches back. Step 5 sets
  Spec review, then posts `Spec: <path> (PR #<pr>). Waiting for approval.` A stop commits the spec file as
  `docs: iteration <N> spec (#<issue>), unfinished` without pushing, or deletes the empty branch it created. The spec
  branch therefore carries the **iteration** number, not the issue number (this branch is `spec/44-resume-stuck-issues`
  for #112). `/spec` takes no slot.
- **What a `/next` run leaves.** Step 2.1 sets In progress and finds the spec (the `Spec:` comment, else the milestone's
  spec); its file name gives N. Step 2.2 takes a slot with `--take <git.featurePrefix><slug>`: the slug is free, so the
  branch carries **no number** (the remote has `feat/parallel-check`, `feat/stage-times`). The tester's files stay
  uncommitted until the implementer commits them with its code; the session holds `<tester files>`, `<tester blobs>`,
  the review blocks and the fix rounds in its own memory only. Step 5 adds the CHANGELOG entry, the spec's delivered
  status line and rebases; step 6 opens the PR (`Closes #<issue>`) and sets Review; step 7 enables auto-merge or says
  why not; the session reports `done`. `/fix` names its branch `<git.fixPrefix><number>-<slug>` with the issue number.
- **The slot script already switches to an existing branch.** `slot.sh --take <branch>` (and `slot.ps1 -Take`) checks
  `refs/heads/<branch>` and runs `git switch <branch>` when it exists, `git switch -c <branch> --no-track <base>`
  otherwise (iteration 34, steps 4 and 5). A branch checked out in another worktree makes the switch fail, the take
  restores the slot and prints `git switch failed (exit N); slot <n> is free again`. A take never looks at
  `refs/remotes`.
- **What tells a live run from a dead one.** `slot --status --porcelain` prints per busy slot the branch (field 3), the
  agent state (field 6: `running` while the last report is at most `worktrees.stalledAfterMinutes` old, default 30,
  `stalled` after that, `unknown` without a report), the step (field 9; `taking` for a live claim, `take-died` for a
  dead one) and the report time (field 10). The README: "a step longer than the threshold (a long code review or check)
  shows stalled while it runs". `/spec` has no such signal; git refuses to check out a branch that another worktree has
  checked out.
- **What `/status` can attribute.** `docs/specs/iteration-8-status.md`: "slots are tied to PRs, not to issue numbers, so
  a slot without a PR cannot be attributed to a story"; the flag `stale: In progress, no PR and no busy slot` and
  `stale: Spec but no spec PR` exist. `/status` changes nothing; this story does not change its script.
- **`/fix N`** takes the bug it is named without any status check (step 1: "If `$ARGUMENTS` has a number, use it"); it
  is not part of this story (Not done).
- `templates/spec.md` (iteration 40) is not on `main` yet; this spec follows the headings of iteration 40's decision 1,
  as iteration 42 does.

## Decisions

**1. Only with a number.** The picking without a number is unchanged: `/spec` lists only Ready stories, `/next` only
Approved ones, and neither ever picks up a story at another status on its own. A number is the maintainer's statement
that the story is to be finished; the skill then checks that it has something to finish (decision 3) and that no other
run is visibly at work on it (decision 5).

**2. Which status each skill takes with a number.**

| Skill | Takes | Refused, with the line |
|---|---|---|
| `/spec N` | Ready (as today), Spec, Spec review | Backlog: `#<n> is at Backlog, not Ready, Spec or Spec review; only the maintainer moves a story to Ready.` Approved, In progress, Review: `#<n> is at <status>, not Ready, Spec or Spec review; /next takes it.` Done: `#<n> is at Done; nothing is left to do.` |
| `/next N` | Approved (as today), In progress, Review | Backlog: `#<n> is at Backlog, not Approved, In progress or Review; only the maintainer moves a story to Ready.` Ready, Spec: `#<n> is at <status>, not Approved, In progress or Review; /spec takes it.` Spec review: `#<n> is at Spec review, not Approved, In progress or Review; the maintainer approves its spec first.` Done: `#<n> is at Done; nothing is left to do.` |

An epic or a bug is refused as today. Every refusal changes nothing. The Ready and Approved paths are exactly today's.

**3. "Its own work": the artefacts and how each is found.** N is the iteration number of the story.

- **N for `/spec`**: the issue's milestone, when its title matches `iterations.milestonePattern` (`iteration-<N>`), read
  from `gh issue view <issue> --json milestone`. No such milestone: no N, so no branch and no spec pull request can be
  its own.
- **N for `/next`**: the number in the spec's file name, found as step 2.1 finds it today (the `Spec:` comment, else the
  milestone's spec).
- **The branch**: after `git fetch origin`, the local branches `refs/heads/<prefix><N>-*` and the remote ones
  `refs/remotes/origin/<prefix><N>-*` (`git for-each-ref --format='%(refname:short)' ...`), with `<prefix>` =
  `git.specPrefix` for `/spec` and `git.featurePrefix` for `/next`. A local branch and its `origin/` twin are one
  branch. More than one branch is refused: `#<n> has more than one branch of iteration <N>: <names, comma-separated>; the maintainer keeps one. Nothing was changed.`
  For `/next`, the head of an open pull request that closes the issue (below) is its branch whatever its name, so a
  branch named before this iteration (`feat/<slug>`) is found through its pull request.
- **The spec pull requests** (`/spec`): `gh pr list --state all --search "<issue> in:body" --limit 50 --json
  number,state,headRefName,body,autoMergeRequest` filtered with `--jq` (not piped into `jq` or `python`) to those whose
  head starts with `<git.specPrefix><N>-` and whose body's first line is `Spec for #<issue>.`.
- **The implementation pull requests** (`/next`): `gh pr list --state all --search "<issue> in:body" --limit 50 --json
  number,state,headRefName,body,autoMergeRequest,closingIssuesReferences`, filtered with `--jq` to those whose
  `closingIssuesReferences` holds the issue.
- **The slot** (`/next`): the busy line of `slot --status --porcelain` whose field 3 is the branch.

The artefacts of a story are its branch, its slot and its pull requests (open, merged or closed). A status alone, or a
milestone alone, is not an artefact.

**4. No artefact: refused.** At Spec, Spec review, In progress or Review with no artefact, the skill prints
`#<n> is at <status>, but no branch <prefix><N>-*, no slot and no pull request of it exists; nothing to continue. The maintainer moves it back to <Ready | Approved>.`
(`/spec`: no `no slot` part and `Ready`; `/next`: `Approved`; without N the branch part reads `no branch`), and changes
nothing. Why: such a story was left between setting the status and its first artefact, or another run has just set
the status and is seconds from its first artefact; continuing could start a second run on the same story, and only the
maintainer may set Ready or Approved.

**5. A run that is visibly at work is never joined.** `/next` refuses, changing nothing, when the slot holding the
branch is in one of these states:

| Slot state (porcelain) | Line |
|---|---|
| field 6 `running` | `#<n>: slot <s> (<branch>) is running (last report <field 10>, step <field 9>); another run is working on it. Nothing was changed.` |
| field 9 `taking` | `#<n>: slot <s> (<branch>) is being taken; another run is working on it. Nothing was changed.` |
| field 9 `take-died` | `#<n>: slot <s> (<branch>) holds a take that did not finish; free it with slot --abandon <s> (-Abandon <s>) and run /next <n> again. Nothing was changed.` |

`stalled` and `unknown` are resumed; the resume line (decision 7) names the state and the last report, so the
maintainer sees it. `/spec` has no slot: the branch checked out in a worktree other than the session's own (from `git
worktree list --porcelain`) is refused with `#<n>: <branch> is checked out in <path>; another run may be working there. Switch that checkout away from it and run /spec <n> again. Nothing was changed.`
The threshold is the existing `worktrees.stalledAfterMinutes`; no new number.

**6. The first unfinished step is the first step that left no artefact.** What a dead run held only in its memory (a
writer's or tester's result block, `<tester blobs>`, review blocks, fix rounds used) counts as not done, so the step
that produces it runs again. The tables below are read top to bottom; the first row that matches decides.

`/spec N` at **Spec** (status read back, not set again; N from decision 3):

| # | Found | Resumes at | Then |
|---|---|---|---|
| S1 | an open spec pull request | `the pull request` | auto-merge as in step 4, only when its `autoMergeRequest` is empty and its body does not have `Auto-merge is not enabled`; step 5; step 6 |
| S2 | a merged spec pull request, none open | `Spec review` | step 5; step 6 |
| S3 | only closed, unmerged spec pull requests | refused: `#<n>: its spec pull request #<pr> was closed without a merge; the maintainer decides. Nothing was changed.` | |
| S4 | the branch, the spec file on it committed with the subject `docs: iteration <N> spec (#<issue>)` (the last commit that touches it), the tree clean | `the spec review` | "The spec review" from step 1 (round 0), then steps 4 to 6 |
| S5 | the branch, the spec file on it (committed `, unfinished`, or uncommitted in the session's checkout) | `the spec writer` | the writer with the resume paragraph (decision 8), the review, steps 4 to 6 |
| S6 | the branch, no spec file on it | `the spec writer` | the writer as today, the review, steps 4 to 6 |
| S7 | no artefact | refused (decision 4) | |

`/spec N` at **Spec review**:

| # | Found | Resumes at | Then |
|---|---|---|---|
| R1 | an open spec pull request | `the pull request` | auto-merge as in S1; the comment of step 5 when it is missing; step 6 |
| R2 | a merged spec pull request, none open | `the comment` | the comment of step 5 when it is missing; step 6 |
| R3 | anything else | refused: `#<n> is at Spec review, but no open or merged spec pull request of it exists; the maintainer decides. Nothing was changed.` | |

When R1 or R2 finds nothing to do, the skill prints `#<n>: every step of /spec is done; the spec waits for approval (PR #<pr>, <open | merged>).`
and changes nothing.

`/next N` at **In progress** or **Review** (the edit check of step 1 runs as today; step 2.1 reads the status back and
finds the spec):

| # | Found | Resumes at | Then |
|---|---|---|---|
| N1 | an open pull request that closes the issue | `Review` | set Review when it is not, read it back, again after a minute; step 7 only when its `autoMergeRequest` is empty and its body does not have `Auto-merge is not enabled`; report `done` to the slot that holds its branch, if any |
| N2 | a merged one, none open | refused: `#<n>: its pull request #<pr> has merged; its Closes sets Done. Nothing was changed.` | |
| N3 | only closed, unmerged ones | refused: `#<n>: its pull request #<pr> was closed without a merge; the maintainer decides. Nothing was changed.` | |
| N4 | at Review, none of the above | refused: `#<n> is at Review, but no pull request of it is open; the maintainer decides. Nothing was changed.` | |
| N5 | the branch in a slot that decision 5 refuses | refused (decision 5) | |
| N6 | the branch, in a stalled, unknown or `done` slot, or in no slot | `the slot` | decision 9 (the slot), then N7 to N9 on what the branch holds |
| N7 | the slot's tree not clean | refused: `Stopped: slot <s> (<branch>) of #<n> has uncommitted files from an earlier run: <paths, at most 10, then "and <k> more">. Nothing else was changed; commit, stash or discard them and run /next <n> again.` (report `stopped`) | |
| N8 | no commit on the branch (`git -C <slot> log origin/<git.baseBranch>..HEAD` empty) | `the tester` | step 3 as today, then steps 4 to 8 |
| N9 | commits on the branch | `the code review` | decision 10, then "The code review" from step 1 (round 0), steps 4 to 8 |
| N10 | no artefact | refused (decision 4) | |

**7. The resume line.** Right after the picking line (`Picking #N "<title>": <status>, <priority>, named by number`) and
before the first change, a resumed run prints one line:
`Resuming #<n> at <step>: <what was found>`, where `<step>` is the "Resumes at" cell and `<what was found>` lists, comma
separated, `branch <name>` (`, only on origin` when there is no local one), `slot <s> (<agent state>, last report
<time> | no report)`, `pull request #<pr> <open | merged>`, `spec file <path> <committed | committed unfinished |
uncommitted>`, `no pull request`. Example:
`Resuming #112 at the code review: branch feat/44-resume-stuck-issues, slot 2 (stalled, last report 2026-11-08T09:14:02), no pull request.`
A run that starts at Ready or Approved prints no resume line.

**8. Idempotent steps.** In a resumed run, and harmlessly in every run:

- **A status** already at the value a step sets is not set again; it is read back.
- **The branch**: `/spec` switches its checkout to the found branch instead of creating one (the tree must be clean,
  except in S5 when the checkout is already on it with the spec file as its only uncommitted change); a branch only on
  `origin` is created locally from it (`git switch -c <branch> origin/<branch>`, `/spec`; `git branch --no-track
  <branch> origin/<branch>` before the take, `/next`). The clean-up after a stop ("The spec writer" step 5) never
  deletes a branch the run did not create.
- **The writer's resume paragraph** (S5), added at the end of the writer's prompt: `The spec file exists from an earlier
  run that did not finish (<committed as unfinished | uncommitted>). Read it, keep what is right, and complete it.` The
  form check of "Read the result" accepts, in a resumed run, no change at all when the spec file on the branch has the
  right form. A writer launched in the run writes the line `Written by the specWriter role on <model>.` as today; in S4
  (no writer launched) the line is `Written by the specWriter role in an earlier run that did not finish; resumed by /spec at the spec review.`
- **The push** is `git push -u origin <branch>`; a rejected push stops with `Stopped: the push of <branch> was rejected: <first line of git's message>. Nothing was opened; the status of #<issue> is Spec.`
  (`/next`: `In progress`, and the slot).
- **The pull request** is created only when no open pull request has the branch as its head; an open one is reused
  (S1, R1, N1) and its body is not rewritten.
- **The comment** of `/spec` step 5 is posted only when no comment of the maintainer's login on the issue starts with
  `Spec: <path> (PR #<pr>).`
- **The CHANGELOG entry** of `/next` step 5 is added only when `iterations.changelog` on the branch has no entry for
  iteration N; the spec's status line is changed only when it is not already `Status: delivered in iteration <N> ...`.
- **The rounds** of a resumed review start at round 0 with the full `review.maxFixRounds`; the rounds of the dead run
  are not known.

**9. The slot of a resumed `/next`** (N6). A slot that holds the branch (stalled, unknown or `done`) is reused as it is:
no take. Otherwise the branch is taken with `--take <branch>` (the take switches to the existing local branch). Without
slots, the session's checkout is switched to it (`git switch <branch>`, the tree clean). Right after, the session
reports the new step `resumed` (role `session`) to the slot, so that it shows `running` again, and from there every
step is reported as today. A take that fails because the branch is checked out elsewhere stops with the take's line,
as every failed take does.

**10. The tester's files in a resumed code review** (N9). The dead run's `<tester files>` are not known. The resumed run
takes as `<tester files>` every path of `git -C <slot> diff --name-only origin/<git.baseBranch>...HEAD` that is a test
path by the `Test paths:` line of "The tester", records `<tester blobs>` and `<tester originals>` for them by rule 1
(round 0), and from there guards them as today. This guards the implementer's own tests too, which only makes it
stricter. The code review's prompt lists them as committed. The pull request's "How verified" begins, instead of the
tester's block, with:

```
Resumed by /next at the code review; the earlier run's tester result is not known. Tests on the branch:
- <path>, one per line
```

and the line under `Closes #<issue>` is `Written by the implementer role in an earlier run that did not finish; resumed by /next at the code review.`,
followed by `Fix rounds by the implementer role on <model>.` when this run launched the implementer. A stash entry
whose message is `Unmet tests for #<issue>: <title>` (`git stash list`) is named in the final message and in "How
verified" as `- set aside by an earlier run: stash "<message>"`; it is not popped.

**11. `/next` names its branch with the iteration number.** Step 2.2 takes `<git.featurePrefix><N>-<slug>` (N from the
spec's file name), and the single-checkout path `git switch -c` the same name. Why: the issue asks for "a branch
`<prefix><N>-*`"; the spec branch already carries the iteration number, the implementation pull request's title
already carries it (`Iteration <N>: ...`), and N is known before the take. The issue number was the other choice (as
`/fix` does); see Left, item 2.

## Criteria and rules

The issue has no "Acceptance criteria" list (it was filed as a bug); these are derived from "What should happen" and
the Evidence, in that order.

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | `/spec N` takes a story at Spec when its own artefacts exist and continues from the first unfinished step | Decisions 2, 3, 6 (S1 to S6), 7, 8 |
| 2 | `/spec N` takes a story at Spec review when its own artefacts exist and continues from the first unfinished step | Decisions 2, 3, 6 (R1, R2), 8 |
| 3 | `/next N` takes a story at In progress when its own artefacts exist (branch, slot marker, open pull request) and continues from the first unfinished step | Decisions 2, 3, 5, 6 (N1, N5 to N9), 7 to 11 |
| 4 | `/next N` takes a story at Review when its own artefacts exist and continues from the first unfinished step | Decisions 2, 3, 6 (N1) |
| 5 | Without its own artefacts, or at a status the skill does not take, the issue is refused with one line and nothing changes; without a number the picking is as today | Decisions 1, 2, 4, 5; rows S3, S7, R3, N2 to N4, N7, N10 |
| 6 | Every step is idempotent: an existing branch is switched to, an open pull request is reused, nothing is done twice | Decisions 8, 9 |
| 7 | `/status` and the README point to the way out for a stuck item | `skills/status/SKILL.md` and `README.md` under Files touched |

## Tests

The skills are conversations; as in every skill iteration, `tests/lint.sh` pins the wording the behaviour depends on,
and the manual check runs the behaviour.

**`tests/lint.sh`**, new section `== a stuck story is continued`, after `== /fix all runs bugs in parallel` and before
`== bash files do not use jq`. The text of each file is joined (`tr '\n' ' '`, runs of spaces made one) before it is
searched, as `== text from issues is data` does. It fails with `FAIL: <file> does not say the resume item: <text>` for
each missing text:

- Criteria 1 to 5, `skills/workflow/SKILL.md` ("Picking an issue"): `also takes Spec and Spec review`, `also takes In
  progress and Review`, `its own artefacts`, `the first unfinished step`, `Resuming #<n> at <step>`, `nothing to
  continue`, `another run is working on it`; and the old example `/spec only takes Ready stories` is gone
  (`FAIL: skills/workflow/SKILL.md still refuses every status but the skill's own`).
- Criterion 1 and 2, `skills/spec/SKILL.md`: `<git.specPrefix><N>-*`, `Spec for #<issue>.`, `The spec file exists from
  an earlier run that did not finish`, `every step of /spec is done; the spec waits for approval`, `resumed by /spec at
  the spec review`, `never deletes a branch the run did not create`.
- Criteria 3 and 4, `skills/next/SKILL.md`: `<git.featurePrefix><N>-<slug>`, `closingIssuesReferences`,
  `--status --porcelain`, `is running (last report`, `slot --abandon <s>`, `resumed` in the report table
  (`| `session` | `resumed` |`), `Resumed by /next at the code review`, `resumed by /next at the code review`.
- Criterion 6, both skills: `is not set again; it is read back`, `an open one is reused`; `skills/spec/SKILL.md`: `only
  when no comment`; `skills/next/SKILL.md`: `has no entry for iteration N`.
- Criterion 7: `skills/status/SKILL.md` has `/spec N` and `/next N` and no longer says `with nothing behind it is
  `/next`, `/spec` or the maintainer`; `README.md` has `continues a story` for both rows.
- The existing sections stay green: `== spec and next stay split` (`Ready`, `Approved`, `Picking #`), `== the review is
  recorded in the pull request` and `== the spec review is recorded in the spec pull request` (the lines
  `Written by the specWriter role on <model>.` and `Written by the implementer role on <model>.` stay, beside the
  resumed ones).

`bash tests/check.sh` stays green.

**The manual check** (`verification.manualCheckText`), in a scratch project with its own board and two slots, with
`claude --plugin-dir <this checkout>`. Each step names the criterion it shows.

1. *Criterion 3, the issue's reproduction*: start `/next <n>` on an Approved story, end the session after
   `Slot N is yours` and the `slot-taken` report (the branch exists, no commit). Run `/next <n>` again at once: it
   refuses with the `is running` line (decision 5). Lower `worktrees.stalledAfterMinutes` to 1 in the scratch config,
   wait two minutes, run it again: it prints `Resuming #<n> at the tester: branch feat/<N>-..., slot 1 (stalled, ...)`,
   reports `resumed`, reuses slot 1 without a take and goes on to a pull request. Check `slot --status`: one busy slot.
2. *Criterion 3, N9*: end a `/next` run after the implementer's commit and before the pull request; `/next <n>` resumes
   at the code review, lists the tests on the branch in "How verified", opens one pull request.
3. *Criteria 4 and 6, N1*: end a run after the pull request opened and before auto-merge; `/next <n>` at Review reuses
   the pull request (no second one, body unchanged), enables auto-merge, reports `done`.
4. *Criterion 1, S5 and S1*: end `/spec <n>` while the writer runs (the spec file uncommitted); `/spec <n>` resumes at
   the spec writer with the resume paragraph, on the same branch. End another run after the pull request opened;
   `/spec <n>` resumes at the pull request, sets Spec review and posts the comment once.
5. *Criterion 2*: `/spec <n>` on a story at Spec review whose comment exists prints `every step of /spec is done` and
   changes nothing (the board, the issue's comments and the pull request are as before).
6. *Criterion 5*: `/next <n>` on a story set to In progress by hand with nothing behind it prints the
   `nothing to continue` line; `/spec` and `/next` without a number pass over Spec and In progress stories; `/next <n>`
   on a slot whose take died prints the `--abandon` line.

## Files touched

- `skills/workflow/SKILL.md`: "Stories and bugs", first bullet: an agent works on Ready or Approved issues, and, named
  by number, on a story at Spec, Spec review, In progress or Review to finish its own work. "Picking an issue": rule 1
  gets decisions 1 to 5 and 7 (the statuses each skill takes, the artefacts, the refusal lines, the resume line) and a
  new example; a new rule 4 says the first unfinished step is the first that left no artefact and that every step is
  idempotent (decision 8), pointing to `/spec` and `/next` for their tables.
- `skills/spec/SKILL.md`: step 1 (the statuses, the artefacts of decision 3, the refusals, the resume line); a new
  section "Resuming a story" with the tables S and R of decision 6; the idempotent steps of decision 8 in steps 2.1,
  4, 5 and "The spec writer" steps 1, 4 and 5; the resume paragraph of the writer's prompt.
- `skills/next/SKILL.md`: step 1 (the statuses, the artefacts, decision 5's refusals, the resume line); step 2.2 the
  branch `<git.featurePrefix><N>-<slug>` (decision 11); a new section "Resuming a story" with table N and decisions
  9 and 10; the idempotent steps of decision 8 in steps 2.1, 5 and 6; the step `resumed` in "Reporting the steps"
  (`| when a resumed run has its slot (decision 9) | `session` | `resumed` |`); the resumed lines of "How verified" and
  under `Closes`.
- `skills/status/SKILL.md`, item 2: a story at Spec, Spec review, In progress or Review with a branch, a slot or a pull
  request behind it is continued by `/spec N` or `/next N`; with nothing behind it the maintainer moves it back to
  Ready or Approved; a `stalled` slot of `/next` is continued by `/next N` (the issue of iteration N) or freed by the
  maintainer as today.
- `README.md`: the rows of `/nightmill:spec [N]` and `/nightmill:next [N]` in "What is in the plugin" each get one
  sentence: `/spec N` also continues a story that a run left at Spec or Spec review, `/next N` one left at In progress
  or Review, from the first step that left nothing behind. The sentence of line 30 stays.
- `.claude/CLAUDE.md`, "Development process": the sentence "An agent only works on issues whose board status is Ready
  or Approved; only the maintainer sets those." gets the same addition as the workflow skill's first bullet (named by
  number, a story at Spec, Spec review, In progress or Review, to finish its own work).
- `tests/lint.sh`: the section of Tests.
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 44 (#112): /spec N and /next N finish a story that an earlier run
  left at Spec, Spec review, In progress or Review. With a number, /spec also takes Spec and Spec review and /next also
  takes In progress and Review when the story's own branch, slot or pull request exists; they print where they resume
  and go on from the first step that left nothing behind, reuse the branch, the slot and an open pull request, and set
  no status, comment or CHANGELOG entry twice. A story with nothing behind it, or a slot whose agent is still
  running, is refused. /next names its branch with the iteration number. Without a number nothing changes.`

## Risks

- **A run that is alive but shows `stalled`.** A step longer than `worktrees.stalledAfterMinutes` (a long check or
  review) shows `stalled` while it runs, so `/next N` could join a live run. Limits: only a run named by number does it,
  the resume line shows the state and the last report, the `resumed` report makes the slot `running` again for the
  next look, and two runs on the same branch cannot both take a slot (the second take's switch fails). Two sessions in
  one reused slot are not prevented; see Left, item 3.
- **`/spec` has no liveness signal.** A `/spec` run in another checkout is caught only when it has the branch checked
  out (decision 5); one between its status and its branch is caught by decision 4.
- **More reviews than `1 + review.maxFixRounds`** across runs of one story (decision 8, the rounds); each run keeps the
  limit.
- **The reconstructed tester files** (decision 10) include the implementer's own tests, and a test the dead run's
  implementer had already weakened is taken as the tester's. The code reviewer still checks the tests against the spec.
- **The search for pull requests** (`<issue> in:body`, 50 results) misses a pull request whose body does not name the
  issue; every pull request of `/spec` and `/next` does (`Spec for #`, `Closes #`).
- **Branches named before this iteration** (`feat/<slug>`) are found only through an open pull request; a story left
  with such a branch and no pull request is refused by decision 4.

## Size estimate

M: about 60 lines in `skills/next/SKILL.md`, 45 in `skills/spec/SKILL.md`, 20 in `skills/workflow/SKILL.md`, 5 in
`skills/status/SKILL.md`, 4 in `README.md`, 40 in `tests/lint.sh` and 6 in `CHANGELOG.md`: about 180 changed lines.

## Not done

- No change to `/fix` (it takes a numbered bug at any status today, and its batch mode has its own rules), to
  `/story`, or to the picking without a number.
- No revision of a spec at Spec review (`/spec` step 6's follow-up PR): a story at Spec review with every step done is
  only reported (row R1, R2). See Left, item 4.
- No status is moved backwards; nothing sets Ready or Approved; a story with nothing behind it waits for the
  maintainer.
- No change to any script: not `slot.*` (no new flag, no take that reuses a busy slot), not `status.*`, `stages.*`,
  `dashboard.*` or `panel.*`; no new flag text in `/status`'s table.
- Nothing frees, abandons or deletes a slot, a branch, a stash entry or a file of an earlier run; uncommitted files
  stop the run (N7).
- No record of a run's memory (result blocks, review blocks, fix rounds) in the repository or the slot, so those steps
  run again.
- No rename of existing branches, and no change to the spec branch's name.
- Step 8 of `/next` (the rest filed as a new story) is not redone for a pull request that an earlier run opened.
- The running/stalled view of #67 (iteration 23) is used as it is, not changed.

## Left

1. **Story trigger.** This spec reads "a change to the status flow or who sets a status" as the statuses, their order
   and who sets them, none of which change. The sentence "An agent only works on issues whose status is Ready ... or
   Approved" does change. If the maintainer counts that as the status flow, the pull request must not auto-merge and a
   decision record is needed ("Fixed flow").
2. **The number in `/next`'s branch.** Decision 11 uses the iteration number, as the spec branch and the PR title do.
   The issue number (as `/fix`'s `fix/<number>-<slug>`) would let `/status`'s slot row show the issue directly; the
   maintainer may prefer it.
3. **The liveness rule.** The issue does not say how to tell a crashed run from a live one. Decision 5 uses the existing
   `running` / `stalled` threshold and refuses only `running`; a stricter rule (for example a second threshold) would
   need a number or a key the issue does not give.
4. **A spec revision through `/spec N`.** The issue names `/spec`'s follow-up-PR sentence as part of the problem, but
   "What should happen" asks only to continue unfinished steps. Whether `/spec N` at Spec review with every step done
   should start a revision (reading the maintainer's comments) is for the maintainer; it would be its own story.
5. **No `templates/spec.md` on `main`**: this spec follows iteration 40's headings, which are not delivered yet.
