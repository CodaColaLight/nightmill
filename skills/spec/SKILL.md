---
name: spec
description: Write the spec for a Ready story as its own PR and stop at Spec review. Use when asked to spec a story, write the spec for an issue, or start the next Ready story. Implementing an Approved story is /next.
argument-hint: [issue-number]
disable-model-invocation: true
---

Write the spec for a Ready story: $ARGUMENTS

Project configuration (`.claude/nightmill.json`):

!`cat .claude/nightmill.json`

Read the configuration first. Below, *the maintainer* is `maintainer.name`; `<owner>`, `<repo>` and
`<project>` come from `github`; status names from `board.statuses`; label names from `labels`. Where this
text and the configuration disagree, the configuration wins. The process rules are in the `workflow`
skill of this plugin; this skill is the step list.

## 1. Pick the issue

Follow **Picking an issue** in the `workflow` skill with the status **Ready** (`board.statuses.ready`).

- If `$ARGUMENTS` holds an issue number, take that issue; refuse when it is not at Ready.
- Otherwise list the board: `gh project item-list <project> --owner <owner> --limit 200 --format json --jq '.items[] | [.content.number, .content.type, .status, .priority, ((.labels // []) | join(",")), .content.title] | @tsv'`
  and take the highest-priority Ready story that is not an epic and not a bug (bugs go through `/fix`).
- Nothing Ready: print `Nothing is Ready.`, add `Approved: #N ... Run /next to implement.` when Approved
  stories exist, change nothing and stop.
- Print the line `Picking #N "<title>": <status>, <priority>, <reason>` before the first change.
- Read the issue with `gh issue view N --json number,title,labels,body,milestone,comments`, its parent epic,
  and every spec and decision either references.

## 2. Write the spec, then stop

1. Set the status to **Spec** right away and read it back (`gh project item-list` for the item id,
   `gh project field-list` for the field and option ids, then `gh project item-edit`). Not In progress:
   nothing is being implemented yet.
2. Pick the iteration number N: the higher of the latest entry in `iterations.changelog` and the highest
   milestone matching `iterations.milestonePattern` (`gh api repos/<owner>/<repo>/milestones?state=all --paginate`;
   another task may have claimed a number that is not merged yet), plus 1. Create the
   milestone if missing and put the issue in it.
3. **Hand the writing to the spec writer.** The session never writes the spec itself; the spec file
   `<iterations.specDir>/<iterations.specPattern>` is written by a subagent in the role `specWriter` (see "The
   spec writer" below): branch, count the agents, launch it, read its result.
4. Open the spec as its own PR: commit the spec only, push, PR titled `docs: iteration <N> spec (#<issue>)`
   with the body `Spec for #<issue>.` (not `Closes`) and, on its own line,
   `Written by the specWriter role on <model>.` (`<model>` is the exact string passed as `model` in the Agent
   call), and `gh pr merge <pr> <git.mergeFlags>`: a spec PR is docs only. Switch back to the branch you came
   from.
5. Set the status to **Spec review** and read it back. Comment on the issue:
   `Spec: <path> (PR #<pr>). Waiting for approval.`
6. **Stop.** Show the spec to the maintainer with the `Decisions` and `Left` lines of the result block. Only the
   maintainer sets Approved; then `/next` implements it. If the maintainer asks for changes, revise the spec in
   a follow-up PR and keep the status at Spec review.

## The spec writer

The session keeps the picking line, the board statuses, the branch, the commit, the pull request and every hard
rule. The spec file is the writer's.

1. **Branch.** The working tree must be clean; if it is not, say so and stop (the status is already Spec).
   `git fetch`, then create `<git.specPrefix><N>-<slug>` from `origin/<git.baseBranch>` and switch to it.
   Remember the branch you came from. You choose `<slug>`; the file path is known before the launch.
2. **Count.** Before the launch count the agents running (the workflow rule: subagents, slot builds, your own
   builds). At `parallel.maxAgents` wait for one to end and say what you wait for; the session never writes the
   spec itself instead. The writer is one agent (its prompt forbids launching others).
3. **Launch.** One Agent call: a fresh agent (omit `subagent_type`; not nightmill:worker), not a fork, with the
   `model` that **Agent roles and models** in the `workflow` skill gives the role `specWriter`
   (`roles.specWriter.model`, else the schema default), passed explicitly, and the prompt below. When the model
   cannot be used, stop with the line of that section for `specWriter`
   (`Stopped: the specWriter role cannot run on <model>: <the reason>. Nothing was started on another model.`),
   add that the status of #<issue> is Spec, and do the clean-up (nothing was written, so the new branch goes).
4. **Read the result.** The subagent's last message ends with the result block below. Check that the tree has
   exactly one change, the spec file, that its first heading starts `# Iteration <N>:` and that it has the line
   `Status: draft, awaiting approval (#<issue>)`. That is the form only; whether the spec is good is for the
   reviewer and the maintainer.
   - `Result: complete` and the form is right: go on with step 4 above.
   - `Result: partial`, `Result: failed`, no result block, an error, or a wrong form: open no PR and move nothing
     to Spec review. Print `Stopped: the specWriter returned <partial|failed>: <Left>` (a wrong form is
     `partial`, and the line names what is wrong), say that the story stays at Spec, and do the clean-up.
5. **Clean-up after a stop.** When the spec file exists and is the only change, commit it to the local branch
   with `docs: iteration <N> spec (#<issue>), unfinished` and do not push. Switch back to the branch you came
   from. When nothing was committed, delete the branch you created (it is empty and you made it; this is not
   the deletion of a file). Never set Ready; a story left at Spec goes back to Ready only by the maintainer.

The prompt, with the placeholders filled in (the story and the epic verbatim):

```markdown
You are the spec writer for story #<issue> "<title>" in <owner>/<repo>.

Work in the checkout at <absolute path of the repository>, on branch <branch>; it is up to date with
<git.baseBranch>. Write one file: <path, from iterations.specDir and iterations.specPattern>. Nothing else.

The story, in full: <issue body and comments>. Its epic #<epic>, in full: <epic body>. Read every spec and
decision the story or the epic references, and the most recent spec in <iterations.specDir> as the model for the
form: <their paths>.

Write the spec from the acceptance criteria: exact rules and numbers (numbers live only in the spec, never in the
issue), a "Not done" list, and the status line `Status: draft, awaiting approval (#<issue>)` directly under the
title `# Iteration <N>: <what>`. Say whether the change is one of <escalation.storyTriggers> and whether the
manual check of <verification.manualCheckPaths> applies. Add no scope the issue does not ask for, and do not
contradict a decision or a spec that exists.

Do not commit and do not push, do not open or edit a pull request, do not touch the board, any issue or any
status, do not create or switch branches, do not edit any other file, do not delete files, and
do not launch other agents. If the issue is unclear or contradicts a decision, do not decide it yourself: write
what you can and say so under Left.

End your last message with exactly this block:

Result: complete | partial | failed
Spec: <the path>
Criteria: <one line per acceptance criterion: the heading of the spec that covers it, or not covered>
Decisions: <the choices you made that the issue did not settle, one line each; none>
Left: <what is not done and why; nothing>
```

## Hard rules

Never set Ready or Approved (only the maintainer does). Never close an epic. Never delete files
without asking. Never merge any other way than `gh pr merge <pr> <git.mergeFlags>` (a plain
`gh pr merge` would bypass the checks).