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

- **Board view** (the columns): a view with `layout: BOARD_LAYOUT`, named after the repository, created
  with the mutation below. A board layout groups by `Status` by default, so the eight statuses become the
  columns. **exists** when the board already has any view whose `layout` is `BOARD_LAYOUT`
  (`projectV2(number: <n>) { views(first: 20) { nodes { name layout } } }`).

  ```graphql
  mutation { createProjectV2View(input: { projectId: "<project node id>", name: "<repo>", layout: BOARD_LAYOUT,
    configuration: { visibleFieldIds: ["<priority field id>", "<area field id>"] } })
    { projectV2View { number layout verticalGroupByFields(first: 1) { nodes { ... on ProjectV2SingleSelectField { name } } } } } }
  ```

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
  answered value, keys the user left empty deleted. Check it against the schema by reading both (a
  validator script is a separate story); a wrong type or an unknown key is fixed before the plan is shown.
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

## 4. Confirm once

Print the plan as one table (line, action) and ask a single question: apply all, or name the lines to
skip. The CLAUDE.md edit and the `settings.json` edit are shown in the same message as the exact text
or diff that will be written, so that the one answer covers them. A skipped line is **declined** and is
not asked about again in this run.

When the plan holds only **exists** lines, ask nothing: say "already set up, nothing to change" and go
to the report.

## 5. Apply

Apply the kept lines in this order: board and fields, view, link, labels, config, forms, CLAUDE.md,
settings. After each GitHub change read it back (`gh project field-list`, `gh label list`,
the `repositories` and `views` queries); a line whose read-back does not show the change is **failed**, with
the command's error, and the run goes on with the lines that do not depend on it (the view, the field options and the link depend on the board, the forms on the config; nothing else does).

Every line is idempotent, so re-running is safe: a second run finds each line **exists** and applies nothing.

## 6. Report

End with one table: line, result (**created**, **changed**, **already there**, **declined**, **failed**).
Below it, "Still to do by hand:" with exactly the declined and failed lines, or "nothing". Do not print
instructions for lines that were applied.

One note always follows, never as a failure: the board's **workflows** (for example "item closed > Done",
"pull request merged > Done") are not reachable through the API; the maintainer enables them once in the
board's Workflows settings in the browser.
