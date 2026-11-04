---
name: init
description: Set a project up for nightmill in one conversation - detect what gh and the repository can tell, ask the rest one question at a time, show one plan, then create the board with its columns view, the labels, the config, the issue forms, the CLAUDE.md snippet and the permission rules. Use when installing nightmill in a repository, when the config is missing, or to complete a half-done setup.
disable-model-invocation: true
---

Set this repository up for the nightmill workflow.

Current configuration, if any:

!`cat .claude/nightmill.json 2>/dev/null || echo "(no .claude/nightmill.json yet)"`

The plugin's files are under `${CLAUDE_PLUGIN_ROOT}`: the schema `schema/nightmill.schema.json` (every
key described, with defaults), the example `templates/nightmill.example.json`, the CLAUDE.md snippet
`templates/CLAUDE.snippet.md`, the renderer `scripts/render-templates.ps1` / `.sh`.

This is an install chat. The order is fixed: **1 Detect, 2 Ask, 3 Plan, 4 Confirm once, 5 Apply,
6 Report.** Nothing is written or created before the confirmation in step 4 is answered; steps 1 to 3
only read. Every step uses `gh` and `git` alone, so it works in either shell.

The flow this sets up: Backlog > Ready > Spec > Spec review > Approved > In progress > Review > Done.
The names come from `board.statuses` (defaults in the schema); the eight statuses and who sets them are
not configurable.

## 1. Detect (no questions)

Read these, in this order, and never ask for a value that was found:

| Value | Source |
|---|---|
| `github.owner`, `github.repo` | `gh repo view --json owner,name` |
| existing board | `gh project list --owner <owner> --format json`; prefer a board linked to this repository (GraphQL: `projectV2(number: <n>) { repositories(first: 10) { nodes { nameWithOwner } } }` on the owner; `gh project view` does not list them), else one whose title equals the repo name, else none |
| existing config | `.claude/nightmill.json`; it is kept and only gaps are filled |
| `maintainer.name` | `gh api user --jq .name`, else the login |
| `verification.check` | an existing check script in `scripts/` or `tests/`, a `Makefile` target, a `package.json` script, or the steps of `.github/workflows/*.yml` |
| `areas` | top-level directories that hold source or docs, minus `.git*`, `.claude*`, `node_modules`, `target`, `dist`, `build` and other build output |
| `verification.manualCheckPaths` | the areas that look like a UI or an app: a `package.json` with a dev server, `src/ui`, `client`, `app` |
| `worktrees.slots`, `parallel.maxAgents` | physical memory, one per 8 GB, at least 1 and at most 4 (PowerShell: `(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory`; bash: `/proc/meminfo` or `sysctl hw.memsize`) |
| `worktrees.ports` | one name per dev server found (`PORT` or `--port` in `package.json` scripts or in config files); none when none |

## 2. Ask

One question per message, in this order. Each question proposes the detected value as the default and
asks only "keep" or "change":

1. **maintainer name** (`maintainer.name`)
2. **check command** (`verification.check`); when nothing was detected, propose one from the build tool found and say that it is a guess
3. **areas** (`areas`)
4. **invariants** (`invariants`), proposed from the "rules", "principles" or "invariants" sections of `CLAUDE.md` and the README; may be empty
5. **manual-check paths** (`verification.manualCheckPaths`) and, when there are any, the one-sentence `verification.manualCheckText`
6. **slot count** (`worktrees.slots`, also used for `parallel.maxAgents`)
7. **ports** (`worktrees.ports`); skipped when no dev server was detected

A question is skipped when the existing config already holds the key, so a configured project is asked
nothing. The user may answer "defaults" at any point; the remaining questions then take their proposed
values. A key the user leaves empty is deleted from the config rather than written with an example value.

## 3. Plan

Build the full list of changes. Mark each line **create**, **change** or **exists** (nothing to do):

- **Board**: when none was found, `gh project create --owner <owner> --title <repo>`. The `Status` field
  gets exactly the eight `board.statuses` in flow order with one `updateProjectV2Field` call that lists
  **every** option: an option whose name already exists keeps its `id`; an old option that is not one of
  the eight and is used by no item is left out (dropped); one that is still used by an item stays in the
  list and is named in the plan, because dropping it would strip those items of their status. The
  `Priority` field gets `board.priorities`, the `Area` field gets `areas`, both single select
  (`gh project field-create <n> --owner <owner> --name <field> --data-type SINGLE_SELECT --single-select-options "a,b,c"`
  for a new field; `updateProjectV2Field` with every existing option and its id for a field that only misses options).
  Read ids with `gh project field-list <n> --owner <owner> --format json`.

  ```graphql
  mutation { updateProjectV2Field(input: { fieldId: "<status field id>", singleSelectOptions: [
    { id: "<existing id>", name: "Backlog", color: GRAY, description: "Filed, not reviewed" },
    { name: "Ready", color: BLUE, description: "Acceptance criteria reviewed; an agent may start (maintainer only)" },
    { name: "Spec", color: YELLOW, description: "An agent is writing the spec" },
    { name: "Spec review", color: ORANGE, description: "Spec merged as a docs PR; waiting for the maintainer" },
    { name: "Approved", color: PINK, description: "Spec approved; any worker may implement (maintainer only)" },
    { name: "In progress", color: PURPLE, description: "Being implemented or fixed" },
    { name: "Review", color: RED, description: "A PR is open" },
    { name: "Done", color: GREEN, description: "Merged or closed" }
  ] }) { projectV2Field { ... on ProjectV2SingleSelectField { options { id name } } } } }
  ```

- **Board views** (the columns and the saved filters): four views, created with `createProjectV2View` and
  given their filter with `updateProjectV2View`. A board layout groups by `Status` by default, so the
  eight statuses become the columns. A view is **exists** when the board already has a view of that name
  (`projectV2(number: <n>) { views(first: 20) { nodes { id name layout filter } } }`); a view that exists
  with a different filter is shown in the plan and changed only when the user keeps that line. The
  default table "View 1" of a new board is renamed to `Epics` instead of creating a fifth view.

  | View | Layout | Filter | Columns shown |
  |---|---|---|---|
  | `Board` | `BOARD_LAYOUT` | `-label:epic,bug` | Title, Priority, Area |
  | `Ready` | `TABLE_LAYOUT` | `status:Ready,Approved -label:epic -label:bug` | Title, Labels, Priority, Area |
  | `Epics` | `TABLE_LAYOUT` | `label:epic` | Title, Status, Linked pull requests, Sub-issues progress |
  | `Bugs` | `BOARD_LAYOUT` | `label:bug` | Title, Assignees, Status, Linked pull requests |

  Use the label names from `labels` in the filters. Field ids come from `gh project field-list`.

  ```graphql
  mutation { createProjectV2View(input: { projectId: "<project node id>", name: "Board", layout: BOARD_LAYOUT,
    configuration: { visibleFieldIds: ["<title field id>", "<priority field id>", "<area field id>"] } })
    { projectV2View { id number layout verticalGroupByFields(first: 1) { nodes { ... on ProjectV2SingleSelectField { name } } } } } }
  mutation { updateProjectV2View(input: { viewId: "<view id>", filter: "-label:epic,bug" }) { projectV2View { name filter } } }
  ```

  The API **cannot set a view's grouping or sorting** (the configuration input has only
  `visibleFieldIds`), so two settings stay by hand and are always listed in the report: on `Board`,
  group by `Area` (swimlanes) and sort by `Priority` descending; on `Ready`, sort by `Priority`
  ascending.
- **Repository link**: `gh project link <n> --owner <owner> --repo <owner>/<repo>`; **exists** when the
  board's `repositories` (the GraphQL query above) already list this one.
- **Labels**: `gh label create <name> --color <hex> --description "<text>"` for each missing one. A label
  that exists is **exists** and is left alone, even when its colour or description differs.

  | Label | Colour | Description |
  |---|---|---|
  | `labels.epic` (`epic`) | `5319E7` | Capability area; parent of stories |
  | `labels.story` (`story`) | `0E8A16` | One shippable slice = one spec = one PR |
  | `labels.bug` (`bug`) | `D73A4A` | Defect in shipped behaviour |
  | `labels.needsSpec` (`needs-spec`) | `E99695` | Story accepted but the spec is not written yet |
  | `blocked` | `000000` | Waiting on another issue (name it in the body) |
  | `<labels.areaPrefix><area>` for each of `areas` | `1D76DB` | Area: `<area>` |
  | `<labels.priorityPrefix><priority, lower case>` for each of `board.priorities` | Critical `B60205`, High `D93F0B`, Medium `F9D0C4`, Low `C5DEF5` | Priority: `<priority>` |

- **Config**: `.claude/nightmill.json` with LF line endings, from the example with every detected and
  answered value, keys the user left empty deleted. Write the candidate to a temporary file outside the
  project and validate it before the plan is shown: `"${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.ps1" -Config <file>`
  (PowerShell) or `bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.sh" <file>`. An error (a wrong
  type, a missing required key) is fixed and the validator run again; a warning (an unknown key, with a hint
  when it looks like a typo) is listed in the plan. After the real file is written, run the validator on it
  and put its summary line, for example `0 errors, 0 warnings`, in the report's **Config** row.
- **Issue forms**: `"${CLAUDE_PLUGIN_ROOT}/scripts/render-templates.ps1"` (PowerShell) or
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/render-templates.sh"` from the repository root, writing
  `.github/ISSUE_TEMPLATE/{epic,story,bug,config}.yml` from `areas` and `invariants`. An existing form
  that differs is shown as a diff in the plan and overwritten only when the user keeps that line
  (`-Force` / `--force`).
- **CLAUDE.md**: append `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.snippet.md` to the project's `CLAUDE.md`
  (root, else `.claude/CLAUDE.md`, creating the root file when neither exists); **exists** when either file
  already contains the line `This project runs on the [nightmill]`.
- **Permissions**: add these rules to `permissions.allow` in the project's `.claude/settings.json`,
  merging into the existing array without removing or reordering an entry, and creating the file as `{}`
  plus the array when it is missing: `Bash(gh project:*)`, `Bash(gh issue:*)`, `Bash(gh pr:*)`,
  `Bash(gh api:*)`, `Bash(git status:*)`, `Bash(git diff:*)`, `Bash(git log:*)`, and one rule for
  `verification.check` (`Bash(<the exact check command>)`). A rule already present is **exists**.
- **Board workflows** (read-only, never applied): the API can list a board's workflows and whether each is
  enabled, but it has **no mutation to create, enable or configure one** (only `deleteProjectV2Workflow`
  exists), and it does not expose which status a workflow sets. So this line only reads
  (`user(login: "<owner>") { projectV2(number: <n>) { workflows(first: 20) { nodes { name enabled } } } }`;
  use `organization(login: ...)` for an organization) and is marked **exists** when the ten workflows in
  the table of step 6 are all enabled, else **by hand**. Read it **last**, after the board and field
  changes: replacing the Status options disables every workflow that pointed at an option that is gone
  (a fresh board starts with its workflows enabled; after the options are replaced "Item added to project"
  and "Pull request linked to issue" were seen disabled). Even when all ten are enabled, which status each
  sets cannot be read, so the report always lists the expected targets.

## 4. Confirm once

Print the plan as one table (line, action) and ask a single question: apply all, or name the lines to
skip. The CLAUDE.md edit and the `settings.json` edit are shown in the same message as the exact text
or diff that will be written, so that the one answer covers them. A skipped line is **declined** and is
not asked about again in this run.

When the plan holds only **exists** lines, ask nothing: say "already set up, nothing to change" and go
to the report.

## 5. Apply

Apply the kept lines in this order: board and fields, view, link, labels, config, forms, CLAUDE.md,
settings; then read the board workflows (read-only, see the plan). After each GitHub change read it back (`gh project field-list`, `gh label list`,
the `repositories` and `views` queries); a line whose read-back does not show the change is **failed**, with
the command's error, and the run goes on with the lines that do not depend on it (the view, the field options and the link depend on the board, the forms on the config; nothing else does).

Every line is idempotent, so re-running is safe: a second run finds each line **exists** and applies nothing.

## 6. Report

End with one table: line, result (**created**, **changed**, **already there**, **declined**, **failed**,
**by hand**). Below it, "Still to do by hand:" with exactly the declined, failed and by-hand lines, or
"nothing". Do not print instructions for lines that were applied.

Then, **always**, even when everything else was already there, print the board settings that only the
browser can change. It is not a failure: the GitHub API cannot create, enable or configure board
workflows, and cannot set a view's grouping or sorting. First the two view settings from the plan
(`Board`: group by `Area`, sort by `Priority` descending; `Ready`: sort by `Priority` ascending), at the
board's view menu. Then the workflows, which the maintainer sets once at
`https://github.com/users/<owner>/projects/<n>/workflows`
(`https://github.com/orgs/<owner>/projects/<n>/workflows` for an organization). Print the table below with
the current state from the read in step 3 (enabled or disabled, never "unknown" for a workflow that was
listed; "missing" for one that was not), and the sentence that follows it.

| Workflow | Enable it and set | Why the flow needs it |
|---|---|---|
| Item added to project | Status = Backlog (`board.statuses.backlog`) | a new issue lands in Backlog |
| Item closed | Status = Done | a closed issue finishes |
| Pull request merged | Status = Done | a merged PR finishes its story |
| Pull request linked to issue | Status = Review | a PR with `Closes #N` moves its story to Review |
| Code review approved | Status = Review | an approved review keeps the story in Review |
| Code changes requested | Status = Review | a PR that needs changes stays in Review |
| Item reopened | Status = In progress | a reopened issue is being worked on again |
| Auto-add sub-issues to project | on | the stories of an epic appear on the board |
| Auto-add to project | repository = this repository, filter `is:issue,pr` | every issue and PR of the repository is on the board |
| Auto-archive items | filter `is:issue,pr is:closed updated:@today-1d` | closed items leave the board a day after their last update |

After the table print these three notes:

- **Why the auto-archive filter is that short.** Archiving closed items one day after their last update
  keeps the number of items each board query has to fetch small, and so keeps the agents clear of
  GitHub's rate limits. Do not lengthen it without a reason.
- **Missing workflows.** On the new boards checked, only six workflows existed (Item added, Item closed,
  Pull request merged, Pull request linked to issue, Auto-add sub-issues, Auto-close issue). Item
  reopened, Code review approved, Code changes requested, Auto-add to project and Auto-archive items are
  added on the workflows page with "Add workflow", then configured as in the table.
- **Leave Auto-close issue off.** The agents set Ready, Spec, Spec review, Approved and In progress
  themselves (the maintainer sets Ready and Approved), so no workflow touches those, except Item reopened
  which sets In progress. Replacing the Status options of an existing board disables the workflows that
  pointed at a removed option, so check this table again after any later change to the options.
