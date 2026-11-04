# Iteration 1: `/init` as an install chat

Status: delivered in iteration 1 (PR #17)

Story: #10, epic #4 (Setup and onboarding). Replaces the body of `skills/init/SKILL.md`. No script, no new
config key, no change to the status flow, no change to the slot marker: none of `escalation.storyTriggers`
applies, so the PR may auto-merge.

## Goal

After `/nightmill:init` a maintainer has a board with columns, labels, issue forms, a config and the
CLAUDE.md snippet, and pasted nothing by hand except what they declined.

## Shape

`/init` stays one skill (`skills/init/SKILL.md`, `disable-model-invocation: true`). The steps are run with
`gh` and `git` only, so they work in either shell; there is no new script and therefore no
two-shells work. `render-templates` is reused as it is.

The order is fixed: **1 Detect, 2 Ask, 3 Plan, 4 Confirm once, 5 Apply, 6 Report.** Nothing is written or
created before step 4 is answered, except the read-only lookups of the earlier steps.

## 1. Detect (no questions)

Read, in this order, and never ask for what is found:

| Value | Source |
|---|---|
| `github.owner`, `github.repo` | `gh repo view --json owner,name` |
| existing board | `gh project list --owner <owner> --format json`: a board whose linked repository is this one; else one whose title equals the repo name; else none |
| existing config | `.claude/nightmill.json` (kept; only gaps are filled) |
| `maintainer.name` | `gh api user --jq .name`, else the login |
| `verification.check` | `scripts/`, `Makefile`, `package.json` scripts, `.github/workflows` |
| `areas` | top-level directories that hold source or docs, minus `.git*`, `node_modules`, build output |
| `verification.manualCheckPaths` | the areas that look like a UI or an app (a `package.json` with a dev server, `src/ui`, `client`, `app`) |
| `worktrees.slots`, `parallel.maxAgents` | physical memory, one per 8 GB, at least 1 and at most 4 |
| `worktrees.ports` | one name per dev server found (`PORT`/`--port` in `package.json` scripts or config); none if none |

## 2. Ask

One question per message, in this order, each with the detected value as the proposed default and
"keep" / "change" as the only decision the user has to make:

1. maintainer name
2. check command
3. areas
4. invariants (proposed from `CLAUDE.md` and the README "rules" sections; may be empty)
5. manual-check paths (and, if any, the one-sentence manual check)
6. slot count
7. ports (skipped when no server was detected)

A question is skipped when the existing config already holds the key (a configured project is asked
nothing). The user may answer "defaults" at any point; the remaining questions then take their proposed
values. A key the user leaves empty is deleted from the config rather than written with an example value.

## 3. Plan

Build the full list of changes, each marked **create**, **change** or **exists** (nothing to do):

- **Board**: create when none was found (`gh project create --owner <owner> --title <repo>`). The Status
  field gets exactly the eight `board.statuses` in flow order. Options whose name already exists keep their
  id; an old option that is not one of the eight and is used by no item is dropped; one that is used by an
  item stays and is listed for the user (it is never removed silently, because the items would lose their
  status). The `Priority` field gets `board.priorities`, the `Area` field gets `areas`; both are single
  select. Missing options are added to the existing fields with every existing option and its id listed.
- **Board view**: a view with `layout: BOARD_LAYOUT` named after the project (the repo name), created with
  the GraphQL mutation `createProjectV2View`; the board layout groups by Status by default. **exists** when
  the board already has a view with a board layout (any name).
- **Repository link**: `gh project link <n> --owner <owner> --repo <repo>`; **exists** when linked.
- **Labels**: from `labels` and `areas` and `board.priorities`: `epic`, `story`, `bug`, `needs-spec`,
  `blocked`, one `area:<area>` per area, one `prio:<priority lowercased>` per priority. Colour and
  description come from a fixed table in the skill; labels that exist are left alone, even when their
  colour differs.
- **Config**: `.claude/nightmill.json` (LF line endings), checked against `schema/nightmill.schema.json`
  by reading both, since the validator is a separate story (#9).
- **Issue forms**: `render-templates` into `.github/ISSUE_TEMPLATE/`; an existing form that differs is
  shown as a diff and only overwritten if the user says so.
- **CLAUDE.md**: append `templates/CLAUDE.snippet.md` unless the project's `CLAUDE.md` (root or
  `.claude/`) already contains the line `This project runs on the [nightmill]`.
- **Permissions**: add the rules below to the project's `.claude/settings.json` (`permissions.allow`),
  merging into the existing array, never removing or reordering an entry, creating the file as `{}` plus the
  array when missing. Rules: `Bash(gh project:*)`, `Bash(gh issue:*)`, `Bash(gh pr:*)`, `Bash(gh api:*)`,
  `Bash(git status:*)`, `Bash(git diff:*)`, `Bash(git log:*)`, and one rule for `verification.check`.
  Rules already present count as **exists**.

## 4. Confirm once

Print the plan as one table (what, action) and ask a single question: apply all, or name the lines to
skip. The CLAUDE.md edit and the `settings.json` edit are shown as the exact text or diff that will be
written, inside the same table message, so that the one answer covers them. Whatever is skipped is
**declined** and is not asked again in this run.

If the plan holds only **exists** lines, nothing is asked: the skill says "already set up, nothing to
change" and ends with the report.

## 5. Apply

Apply the confirmed lines in this order: board and fields, view, link, labels, config, forms, CLAUDE.md,
settings. After each GitHub change read it back (`gh project field-list`, `gh label list`,
`gh project view`); a line whose read-back does not show the change is reported as **failed** with the
command's error, and the run goes on with the lines that do not depend on it (the view and the options
depend on the board; the rest do not).

Re-running is safe at every line because every line is idempotent: a second run finds each line
**exists** and applies nothing.

## 6. Report

One table: line, result (**created**, **changed**, **already there**, **declined**, **failed**). Below it
"Still to do by hand:" listing exactly the declined and failed lines, or "nothing". The report is the last
output; the skill does not print the old "what you should do by hand" instructions for lines it applied.

Not reachable through the API and therefore always listed as a note, never as a failure: board workflows
(for example "item closed > Done"), which the maintainer enables in the board's settings in the browser.

## Tests

Skills are prose, so the tests protect what the prose must keep saying, and the manual check proves it
behaves.

- `tests/lint.sh` gains a check that `skills/init/SKILL.md` contains: `createProjectV2View`,
  `BOARD_LAYOUT`, `updateProjectV2Field`, `gh label create`, `gh project link`, and each of the seven
  question topics from step 2 in order; and does not contain the sentence "Do not edit settings.json
  yourself" (the old rule). Named `init skill keeps the install-chat steps`.
- The existing lint (frontmatter, forbidden words, JSON, shell syntax) keeps passing.
- Manual check (`skills` path changed, so required): run `claude --plugin-dir <this checkout>` in
  1. a throwaway repository with no board: expect seven questions one at a time, a plan, one
     confirmation, then a board with eight Status options, Priority and Area fields, a Board view with
     columns, all labels, forms, config, CLAUDE.md and `settings.json`, and a report with no failed line;
  2. the same repository again: expect "already set up, nothing to change" and `git status` unchanged;
  3. this repository: expect no question and no change.

  The PR describes what was seen.

## Not done

- A config validator (#9); `/init` keeps checking by reading until it exists.
- A `SessionStart` hook that offers `/init` (#12).
- Board workflows/automations (not reachable through the API); listed as a note in the report.
- Removing a Status option that items still use, or renaming a label whose colour differs.
- Editing user-level settings (`~/.claude/settings.json`); only the project file is touched.
- Any new config key, any change to the status flow, any new script.