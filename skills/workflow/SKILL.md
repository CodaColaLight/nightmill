---
name: workflow
description: The development process of this project under nightmill - the issue board and its status flow, stories versus bugs, specs, the spec gate, worker slots and parallel work, PRs and auto-merge, verification. Load this before touching an issue, a board status, a spec, a worktree slot or a pull request.
---

# The nightmill workflow

Project configuration (`.claude/nightmill.json`):

!`cat .claude/nightmill.json 2>/dev/null || echo "NO CONFIG: run /nightmill:init first"`

Read the configuration above first. In this text, *the maintainer* is `maintainer.name`, *the board* is
GitHub project `github.projectNumber` of `github.owner`, status names come from `board.statuses`, and
*the check* is `verification.check`. Where this text and the configuration disagree, the configuration wins.

## What lives where

- **Requirements live in GitHub Issues**: epics group stories (`labels.epic`, `labels.story`); bugs are
  defects in shipped behaviour (`labels.bug`). Issue forms are in `.github/ISSUE_TEMPLATE/`.
- **Specs** live in `iterations.specDir`, named by `iterations.specPattern`: exact rules and numbers, a
  "Not done" list, and a status line once delivered. Numbers live only in the spec, never in the issue.
- **Decisions** go in `iterations.decisionsDir`, short and dated. Check there before deciding anything twice.
- **One CHANGELOG entry per iteration** in `iterations.changelog`, newest first.

## The status flow (fixed)

```
Backlog > Ready > Spec > Spec review > Approved > In progress > Review > Done
```

| Status | Meaning | Who sets it |
|---|---|---|
| Backlog | Filed, not reviewed | /story, the maintainer |
| Ready | Acceptance criteria reviewed; an agent may start the spec (or, for a bug, the fix) | **only the maintainer** |
| Spec | An agent is writing the spec | the agent, the moment it picks the story up |
| Spec review | The spec is written and merged; waiting for the maintainer | the agent, when the spec PR is open |
| Approved | The maintainer approved the spec; **any** worker may implement it | **only the maintainer** |
| In progress | Being implemented (stories) or fixed (bugs) | the agent, when it starts |
| Review | A PR is open | the agent, when the PR opens |
| Done | Merged or closed | the PR's `Closes #N`, or the maintainer |

Bugs skip the spec: Ready > In progress > Review > Done.

The board must show the real state at every moment. Set a status the moment the state changes, then
**read it back** (`gh project item-list`) before telling anyone a status. Never set Ready or Approved.
Board automation may overwrite a status seconds after a PR is linked; after opening a PR set Review
again once the link has registered. Look option ids up at runtime (`gh project field-list`); never
keep them in notes.

Four statuses are also set by the board's own **workflows**, not only by an agent: Backlog (item added),
In progress (item reopened), Review (pull request linked, code review approved, code changes requested)
and Done (item closed, pull request merged). Two more workflows add items (all issues and PRs of the
repository, and the sub-issues of an epic) and one archives closed items a day after their last update;
that filter is kept short on purpose, so each board query fetches few items and stays clear of GitHub's
rate limits. The GitHub API cannot create, enable or configure workflows, so the maintainer sets them
once in the board's Workflows settings in the browser; `/init` prints the exact table. If a status stops
moving on its own, read `projectV2.workflows { nodes { name enabled } }` first: replacing the Status
options disables the workflows that pointed at a removed option.

## Stories and bugs

- An agent only works on issues whose status is Ready (spec, or bug fix) or Approved (implementation).
- Every PR closes exactly one story or fixes one bug. `/spec` writes the spec for a Ready story, `/next`
  implements an Approved one, `/fix` fixes a bug, `/story` files a story.
- **Bugs are not iterations**: no spec, milestone, iteration number or CHANGELOG entry. A failing test
  first, then the smallest fix of the cause. A fix that needs one of `escalation.storyTriggers` is a story.
- **A story only partly done**: file the rest as a new story under the same epic (`/story`), link both
  issues, say so in the PR, and let the PR close the old issue. Never leave a half-done issue open or
  tick criteria that were not met.
- **Spec first.** The spec is a PR of its own (docs only, auto-merged). Implementation starts only
  from Approved. A spec that needs changes stays in Spec review while it is revised.

## Picking an issue

`/spec` and `/next` pick their issue by one rule and differ only in the status they take: `/spec` takes a
**Ready** story (`board.statuses.ready`), `/next` an **Approved** one (`board.statuses.approved`).

1. **With a number**, take that issue. An epic or a bug is refused (bugs go through `/fix`). An issue
   whose board status is not the skill's status is refused with one line that names the status found and
   the skill that takes it, for example `#12 is at Spec review, not Ready; /spec only takes Ready stories.`
   Nothing is changed.
2. **Without a number**, list the board (`gh project item-list`), keep open issues at the skill's status
   that are not epics and not bugs, and take the highest `board.priorityField` (the order of
   `board.priorities`; an item without a priority ranks last). On a tie ask the maintainer which, listing
   the tied issues.
3. **Before the first change** (board, branch, file, slot) print one line:
   `Picking #N "<title>": <status>, <priority>, <reason>`, where the reason is `named by number`,
   `only <status> story` or `highest priority of K <status> stories`.

With nothing at the skill's status the skill changes nothing and says so. `/next` then lists the Ready
stories and points to `/spec N`; it never starts a spec itself.

## Definition of done

Spec approved, every acceptance criterion is a test, the check is green, the manual check
(`verification.manualCheckText`) is done when a change touches `verification.manualCheckPaths`, the
PR says how it was verified. `verification.benchRule` applies when set. Tests are mandatory.

## Verify before every commit

Run the check (`/nightmill:check`) before every commit. Never commit red. If CI is red where the local
run was green, fix the local loop, not just the test.

## Parallel work

- One task per slot. Slots are permanent worktrees with warm build output; take one with the slot
  script (`-Take <branch>`), free it after the merge (`-Release N`), list them (`-Status`). The
  scripts are at `${CLAUDE_PLUGIN_ROOT}/scripts/slot.ps1` and `${CLAUDE_PLUGIN_ROOT}/scripts/slot.sh`.
- At most `parallel.maxAgents` agents (subagents, slot builds, your own builds) at the same time.
  Before launching one, count the running ones; queue or do the work inline otherwise.
- Not two tasks over the same files; `parallel.hotFiles` stay with one task. Never pair
  `parallel.doNotPair`. Rebase on the base branch before the PR.
- Prefer a fresh agent with a short, specific prompt over a fork. Always pass a model: the `worker`
  agent (cheap model) for mechanical, fully specified jobs; a strong model for specs and implementation.
- Do not launch agents just to wait on a dependency; start them when it has merged.

## CI and merging

CI runs on every push and PR to `git.baseBranch`; a PR merges only when its blocking jobs pass.
After opening a PR run `gh pr merge <n> <git.mergeFlags>` (never a plain `gh pr merge`: an admin
bypass would let a red PR through) when it is a story whose spec was approved, a spec PR, or a
complete bug fix. Do not, and say why in the PR, when it changes one of `escalation.storyTriggers`,
is partial, skips a required manual check, or the maintainer asked to review it. A red PR is fixed,
never forced.

## Hard rules

Never set Ready or Approved. Never close an epic. Never delete files without asking. Never push to
the base branch. Never merge any other way than with `git.mergeFlags`.
