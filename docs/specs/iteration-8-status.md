# Iteration 8: /status, one table of what waits and what is stuck

Status: draft, awaiting approval (#9)

Story: #9, epic #4 (Board visibility). Adds `scripts/status.ps1` and `scripts/status.sh`, a `--porcelain`
listing to `slot.ps1` and `slot.sh`, the skill `skills/status/SKILL.md`, smoke tests and a lint check. No
config key, no change to the status flow, no change to the slot marker, nothing written to the board: none of
`escalation.storyTriggers` applies, so the PR may auto-merge.

## Goal

One command shows the maintainer what waits for them and what is stuck, in one table read from the board, the
pull requests and the slots.

## Facts this rests on

- The board, the PR list and the slot markers are three views. Nothing joins them: a story at Review whose PR
  merged an hour ago, a slot that is busy with no open PR, an Approved story nobody picked up, each look fine
  alone.
- `gh project item-list` gives status, title, labels, assignees and the linked pull request URLs of every
  item, but no time. The time a status was set is on the issue's timeline as `ProjectV2ItemStatusChangedEvent`
  (`createdAt`, `previousStatus`, `status`), available through GraphQL; checked against this board.
- `gh pr list --json` gives `headRefName`, `state`, `isDraft`, `mergedAt`, `closedAt`, `statusCheckRollup`,
  `closingIssuesReferences` and `title`.
- A spec PR is on a branch with `git.specPrefix` and does not close its issue (`Spec for #N.`). An
  implementation PR is titled `Iteration <N>: ... (#<issue>)` and closes it. A slot is taken for a branch, so
  a slot belongs to a PR through the PR's `headRefName`, not through an issue number.
- The bash scripts must run with only git, gh and bash (iteration 7). `gh` carries its own `--jq`, so the bash
  version reads `gh` output without `jq`; the PowerShell version uses `ConvertFrom-Json`.

## The scripts

`scripts/status.ps1` and `scripts/status.sh`, the same behaviour and the same output.

| | PowerShell | bash |
|---|---|---|
| Show the table | `status.ps1` | `status.sh` |
| Include Backlog and Done items | `-All` | `--all` |

Run from inside the project (any checkout or worktree), like `slot.sh`. They read `.claude/nightmill.json` of
the main checkout: `github.owner`, `github.repo`, `github.projectNumber`, `board.statuses`, `labels.epic`,
`git.specPrefix`. They only read: `gh project item-list`, `gh pr list`, `gh api graphql` with a query (never a
mutation) and the slot listing. They never call `gh project item-edit`, `gh pr merge`, `gh issue edit` or
`gh issue comment`. Exit code 0 when the table was printed, even if it carries flags; 2 for a usage error, an
unreadable config, `gh` missing or not logged in, or a failed `gh` call (message on standard error).

### What is listed

Open issues on the board that are not epics (label `labels.epic`) and not at Backlog or Done, plus, with
`--all`, the ones at Backlog and Done. Without `--all` a last line counts what is hidden:
`not shown: 4 at Backlog, 7 at Done (use --all)`.

Order: **Spec review** first, then **Approved** (these wait for the maintainer or for a worker), then In
progress, Review, Spec, Ready, and with `--all` Backlog and Done; within one status the oldest first.

### Columns

```
  #  Title                                 Status       Who     PR                  Age  Flag
 12  Config validator against the sche...  Spec review  -       #31 open            5h
  9  /status: one table of board items...  Review       slot 2  #33 open, ci fail   1d
  7  bash scripts read the config with...  Review       -       #23 merged          3d   stale: Review but the PR is merged
```

| Column | Content |
|---|---|
| `#` | the issue number |
| `Title` | the title without a leading `[Story] ` or `[Bug] `, cut to 36 characters with `...` |
| `Status` | the board status as the board names it |
| `Who` | the first assignee login; else `slot N` when a busy slot's branch is the head of one of the issue's PRs; else `-` |
| `PR` | the issue's pull request (below) as `#<n> <state>`, plus `, ci <state>` for an open one; `-` when there is none |
| `Age` | the time since the status was set (the latest status-change event on the issue's timeline; the item's creation time when there is none), as `<m>m` under an hour, `<h>h` under a day, else `<d>d` |
| `Flag` | `stale: <reason>` or empty |

An issue's pull requests are those that close it (`closingIssuesReferences`) or whose title contains
`(#<issue>)`. The PR shown is the open one, else the most recently merged, else the most recently closed. A
spec PR (branch starts with `git.specPrefix`) is shown only while the status is Spec or Spec review, an
implementation PR otherwise. PR states: `open`, `draft`, `merged`, `closed`. CI states of an open PR, from
`statusCheckRollup`: `fail` when any check concluded FAILURE, ERROR, TIMED_OUT or CANCELLED; else `pending`
when any is queued or running; else `pass` when there is at least one check; else `none`.

### Slots

A second table follows when at least one slot is busy:

```
slots
 slot  Branch                 Since  PR                 Flag
    1  feat/bash-without-jq      2h  #23 open, ci pass
    2  feat/old-thing            3d  -                  stale: busy, no open PR
```

`Since` is the age of the marker. `PR` is the PR whose head is the slot's branch (open, else merged, else
closed). With no slot busy the section prints `slots: none busy`. With no slots configured it is left out.

### Stale flags

Fixed texts. `grace` is 2 hours, a constant in both scripts (it is not project-specific, so it is not
configuration).

| Where | Condition | Flag text |
|---|---|---|
| issue at Review | all of its PRs are merged or closed (none open) | `stale: Review but the PR is merged` or `... is closed` |
| issue at In progress | it has no PR and no slot is busy, and the status is older than the grace | `stale: In progress, no PR and no busy slot` |
| issue at Spec | it has no spec PR (open or merged) and the status is older than the grace | `stale: Spec but no spec PR` |
| busy slot | its branch has only a merged or closed PR | `stale: busy, PR merged (slot --release N)` or `... PR closed (slot --abandon N)` |
| busy slot | its branch has no PR and the marker is older than the grace | `stale: busy, no open PR` |

A story at In progress with no PR but with a busy slot is not flagged: slots are tied to PRs, not to issue
numbers, so a slot without a PR cannot be attributed to a story. That slot shows in the slot table without a
flag until it is older than the grace.

## `slot --porcelain`

`slot.sh --status --porcelain` and `slot.ps1 -Status -Porcelain` print one line per slot, tab separated and
without the human text: `<n> TAB busy TAB <branch> TAB <since>` or `<n> TAB free`. `since` is the marker's
`since` value as written. Without `--porcelain` the output is unchanged. The status scripts call this instead
of reading the markers, so the slot directory layout stays inside `slot.*`.

## The skill

`skills/status/SKILL.md`, `/nightmill:status`. It runs the script of the shell in use (`status.ps1` on
Windows, `status.sh` otherwise, from `${CLAUDE_PLUGIN_ROOT}/scripts/`), shows the output and adds at most
three lines: what waits for the maintainer (the Spec review and Approved items by number), what is flagged and
who or what fixes it (`/next`, `/fix`, `slot --release`, the maintainer). It says it changed nothing and does
not fix any flag. The lint's skill check applies (frontmatter, description).

## Other changes

- `tests/smoke-status.sh` and `tests/smoke-status.ps1` (below), added to `tests/check.sh` and to the bash and
  PowerShell jobs of `.github/workflows/ci.yml`; `tests/smoke-slot.sh` and `.ps1` gain the `--porcelain` case.
- `tests/lint.sh`: a check `status is wired` (the skill, both scripts and both smoke tests exist, the README
  mentions the skill, and the scripts contain no `item-edit`, `pr merge`, `issue edit`, `issue comment` or
  GraphQL `mutation`).
- `README.md`: `/nightmill:status` in the skills list, the smoke tests in the command list. `CHANGELOG.md`: a
  bullet under `Unreleased` for iteration 8 (#9). No decision record: no flow or status changes.

## Tests

`tests/smoke-status.sh` and `tests/smoke-status.ps1`, the same cases in both. They put a fake `gh` first on
the `PATH` (a script in a temporary folder; on Windows a `gh.cmd` that calls it) which answers each `gh` call
from fixture files and appends the call to a log, and they run the script in a throwaway git repository with a
config and a slot root. No network, no real board.

1. **The table**: a fixture with an item at each status, an epic and items at Backlog and Done. The exact
   output is compared: Spec review first, then Approved, then In progress, Review, Spec, Ready; epics,
   Backlog and Done absent; the `not shown:` line; titles stripped of `[Story] ` and cut at 36 characters.
2. **Ordering inside a status**: two items at Review, the older first.
3. **Age**: the status-change event gives the age (`5h`, `1d`, `40m`); an item with no event uses its creation
   time.
4. **PR column**: open with `ci pass`, `ci fail`, `ci pending`, `ci none`; draft; merged; closed; an issue
   with a merged and an open PR shows the open one; a spec PR is shown at Spec review and an implementation PR
   at Review.
5. **Stale flags**: one fixture per row of the flag table gives exactly that flag text; each has a twin
   fixture that must not be flagged (Review with an open PR, In progress with a busy slot, Spec younger than 2
   hours, a busy slot younger than 2 hours with no PR).
6. **Who**: an assignee wins over a slot; a slot shows as `slot N`; neither shows `-`.
7. **Slots table**: busy slots with their PR, `slots: none busy`, and the section left out when no slot is
   configured.
8. **`--all`** includes Backlog and Done and drops the `not shown:` line.
9. **Reads only**: the log of `gh` calls contains no `item-edit`, `pr merge`, `issue edit`, `issue comment` and
   no GraphQL `mutation`.
10. **Errors**: `gh` missing from the `PATH`, a failing `gh` call, no config and an unknown option each exit 2
    with a message.
11. **`slot --porcelain`** (in the slot smoke tests): free and busy lines, and the output without the flag is
    unchanged.
12. The lint check `status is wired` fails on a script copy that gains `gh project item-edit`.

The existing lint, smoke tests and `claude plugin validate --strict` keep passing.

Manual check: run `/nightmill:status` with `claude --plugin-dir .` against this board and against a project
with busy slots. The PR describes what was seen, in particular that the ages agree with the board and that no
board item changed.

## Not done

- Fixing any flag (that stays with `/next`, `/fix`, `slot --release` and the maintainer).
- Flags for an Approved story nobody picked up or a PR whose CI has been red for a long time: the `Age` and
  `PR` columns show them, and a threshold would be a number to choose.
- Epics, and the progress of an epic.
- Colour, JSON output, or watching the board continuously.
- More than 200 board items or 100 pull requests (a note is printed when a limit is reached).

## Decisions for the maintainer

1. **Scripts and a thin skill, or a skill only.** The story says "the skill". A skill that makes the model run
   `gh` and format the table is less code but gives a different table each time and cannot be tested; the stale
   rules are exact, so this spec puts them in two scripts (the same pattern as the validator) and keeps the
   skill to running them. If you prefer a skill only, say so and the scripts, their smoke tests and
   `--porcelain` drop out.
2. **A slot is tied to a story only through its PR.** Before the PR exists the slot shows in the slot table but
   not in the story's `Who` column. Tying them earlier would mean putting the issue number into the branch name
   (`feat/9-status`), a convention change that belongs in its own story.
3. **The grace period is 2 hours**, fixed. Without it every fresh Spec and every fresh slot would be flagged
   for the minutes before the first PR exists.
4. **Backlog and Done are hidden** unless `--all`, so the table is about what needs attention. The count of the
   hidden ones stays visible.
