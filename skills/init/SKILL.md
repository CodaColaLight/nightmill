---
name: init
description: Set a project up for nightmill in one conversation - detect what gh and the repository can tell, ask the rest one question at a time, show one plan, then create the board with its columns view, the labels, the config, the issue forms, the CLAUDE.md snippet and the permission rules. Use when installing nightmill in a repository, when the config is missing, or to complete a half-done setup.
disable-model-invocation: true
allowed-tools: Bash(cat .claude/nightmill.json *), Bash(echo "*no .claude/nightmill.json yet*")
---

Set this repository up for the nightmill workflow.

Current configuration, if any:

!`cat .claude/nightmill.json 2>/dev/null || echo "(no .claude/nightmill.json yet)"`

The plugin's files are under `${CLAUDE_PLUGIN_ROOT}`: the schema `schema/nightmill.schema.json` (every
key described, with defaults), the example `templates/nightmill.example.json`, the CLAUDE.md snippet
`templates/CLAUDE.snippet.md`, the renderer `scripts/render-templates.ps1` / `.sh`, the location of nightmill's
template board `templates/board-template.json` and the check of it `scripts/template-board.ps1` / `.sh`.

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
| `verification.platform` | the platform Claude Code runs on: Windows (`win32`, also in Git Bash, MSYS or Cygwin) is `windows`; Linux and macOS (`linux`, `darwin`) are `unix`. When the platform is not known: `uname -s` in bash (`MINGW*`, `MSYS*`, `CYGWIN*` give `windows`, anything else `unix`), or `$env:OS -eq 'Windows_NT'` in PowerShell |

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
8. **platform** (`verification.platform`): `windows` (the check runs the PowerShell tests) or `unix` for Linux and macOS (the bash tests); `all` runs both, for a project worked on from both; read only by a check command that reads it. An empty answer deletes the key, and the check then runs both families

A question is skipped when the existing config already holds the key, so a configured project is asked
nothing. The user may answer "defaults" at any point; the remaining questions then take their proposed
values. A key the user leaves empty is deleted from the config rather than written with an example value.

## 3. Plan

Build the full list of changes. Mark each line **create**, **change** or **exists** (nothing to do):

- **Board, with the template** (only when no board was found): nightmill keeps a public template board whose
  views (filters, grouping, sorting, columns) and workflows are already configured, and `gh project copy`
  carries all of them across. Build the candidate config first (the **Config** line below), write it to a
  temporary file outside the project and run the check on it:
  `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/template-board.ps1" -Config <file>` (PowerShell) or
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/template-board.sh" --config <file>`. It only reads and prints one line:
  `template: usable (<owner>/<number>)` or `template: not usable: <reason>` (an exit code 2 is an error to
  report, not a reason; fall back as below and say what failed). The plan's **Board** line is then one of:
  - `create (copy of <owner>/<number>)` when the line said `usable`;
  - `create (field by field: <reason>)` otherwise, with the reason in words: `no template published yet`
    (`none published`), `the template is not reachable from this account` (`not reachable`), `your config
    renames a field or a status` (`fields differ`, `statuses differ`). This is the fallback; the plan always
    says so, never silently. The fallback is the field-by-field board described next.

  A user who skips the copy line gets the field-by-field board. A copy is never offered for a board that
  already exists. Nothing about the template is a config key: a project cannot point `/init` at another one.
- **Board, field by field**: when none was found and the template is not used,
  `gh project create --owner <owner> --title <repo>`. The `Status` field
  gets exactly the eight `board.statuses` in flow order with one `updateProjectV2Field` call that lists
  **every** option: an option whose name already exists keeps its `id`; an old option that is not one of
  the eight and is used by no item is left out (dropped); one that is still used by an item stays in the
  list and is named in the plan, because dropping it would strip those items of their status. The
  `Priority` field gets `board.priorities`, the `Area` field gets `areas`, both single select
  (`gh project field-create <n> --owner <owner> --name <field> --data-type SINGLE_SELECT --single-select-options "a,b,c"`
  for a new field; `updateProjectV2Field` with every existing option and its id for a field that only misses options).
  Read ids with `gh project field-list <n> --owner <owner> --format json`. Send each mutation of this line and of
  **Board views** inline, one per call, as `gh api graphql -f query='mutation { ... }'`; never from a file or with
  `--input`, which the guard refuses.

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
  default table "View 1" of a new board is renamed to `Epics` instead of creating a fifth view. On a board
  copied from the template every view the copy brought is **exists**, with its grouping and sorting; a view
  that is missing is created as above.

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
  | `paused` | `FBCA04` | Pauses every run on the issues of this epic (nightmill's pause flag) |
  | `<labels.areaPrefix><area>` for each of `areas` | `1D76DB` | Area: `<area>` |
  | `<labels.priorityPrefix><priority, lower case>` for each of `board.priorities` | Critical `B60205`, High `D93F0B`, Medium `F9D0C4`, Low `C5DEF5` | Priority: `<priority>` |

- **Config**: `.claude/nightmill.json` with LF line endings, from the example with every detected and
  answered value, keys the user left empty deleted. Write the candidate to a temporary file outside the
  project and validate it before the plan is shown: `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.ps1" -Config <file>`
  (PowerShell) or `bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.sh" <file>`. An error (a wrong
  type, a missing required key) is fixed and the validator run again; a warning (an unknown key, with a hint
  when it looks like a typo) is listed in the plan. After the real file is written, run the validator on it
  and put its summary line, for example `0 errors, 0 warnings`, in the report's **Config** row.
- **Issue forms**: `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/render-templates.ps1"` (PowerShell) or
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
- **Deny rules**: so that the harness, not only the skills' text, refuses what the hard rules forbid, add 23 rules
  to `permissions.deny` of the project's `.claude/settings.json` (shared: they only take permissions away, hold no
  machine path, and every collaborator runs the `gh` allow rules of that file). `<B>` is `git.baseBranch` (default
  `main`). In this order:
  `Bash(gh pr merge *--admin*)`; `Bash(gh issue delete *)`, `Bash(gh project delete *)`, `Bash(gh repo delete *)`;
  `Bash(gh api *-X DELETE*)`, `Bash(gh api *-XDELETE*)`, `Bash(gh api *--method DELETE*)`,
  `Bash(gh api *--method=DELETE*)`; `Bash(git push --force*)`, `Bash(git push * --force*)`, `Bash(git push -f*)`,
  `Bash(git push * -f*)`, `Bash(git push * +*)`; `Bash(git push * <B>)`, `Bash(git push * <B> *)`,
  `Bash(git push *:<B>)`, `Bash(git push *:<B> *)`, `Bash(git push *:refs/heads/<B>*)`;
  `Bash(gh project item-delete *)`, `Bash(gh project field-delete *)`, `Bash(gh label delete *)`,
  `Bash(gh release delete *)`, `Bash(gh release delete-asset *)`.
  - **Why these.** They refuse a merge with `--admin`, deleting an issue, a board or the repository, a board item
    or field, a label or a release, an API `DELETE`, a force push and a push to `<B>`, in every permission mode
    (deny rules hold in `bypassPermissions` too, and an allow rule cannot carve an exception out of them). Each begins with a fixed command prefix and has
    no `*` before its end, and the git rules' variable part follows a space or a colon, which a branch name cannot
    hold, so no command the skills write matches one, whatever its title or message. There is no rule for the slot
    form (`-C <slot path>` before `push`): a `*` there would also match the skills' stash and commit lines; the
    plugin's guard hook refuses that form instead.
  - **Detect.** A rule is present when it is in `permissions.deny` of `.claude/settings.json` or of
    `.claude/settings.local.json` (string equality). The line is **exists** when all 23 are present, else
    **create** (no `settings.json`) or **change** (a project set up with the 18 rules of iteration 47 gets the five new
    ones appended). `defaultMode` does not make it **exists**: deny rules hold in every mode.
  - **Show the exact text** in the plan message, with the other settings texts: for a missing file the whole file
    (2-space indentation, LF), for a present file the diff (the missing rules appended to `permissions.deny` in the
    order above, the array created when missing, every other byte unchanged). Above it one sentence: these rules
    refuse, in every permission mode, a merge with `--admin`, deleting an issue, a board or the repository, a board
    item or field, a label or a release, an API `DELETE`, a force push and a push to `<B>`; they match the usual spelling of a command, not every spelling, and
    the base branch's ruleset stays the backstop.
  - **Apply** with the other settings changes, after **Permissions** and before **Edit permission**, merging into
    `permissions.deny` without removing or reordering an entry. Read the file back; a read-back that lacks a rule
    is **failed**, naming the first missing one.
  - **Declined.** `settings.json` gets none of them; the report says
    `Deny rules: declined (the forbidden actions are refused only by the plugin's guard hook and the skills' text)`.
  - **Report row**, one of: `added to .claude/settings.json (<k> rules)`, `exists`, `declined (...)`,
    `failed: <reason>`. After an add the report says that the rules follow `git.baseBranch` and that `/init` is
    run again after it changes (old rules are kept).
- **Edit permission**: so that `/spec`, `/next` and `/fix` write files without a prompt, add the one rule
  `Edit(**)` to `permissions.allow` of the project's `.claude/settings.local.json` (personal, not committed:
  letting an unattended run edit is the choice of whoever runs it, so it stays out of the committed
  `settings.json`). One `Edit(**)` rule covers the Write tool as well as the Edit tool and is relative to the
  directory of the session, so it does not reach a path outside it. Write exactly `Edit(**)`: the variant that
  starts with a slash was seen to allow a write outside the project, and a bare `Edit` allowed nothing.
  - **Detect.** The line is **exists** when `Edit(**)` is in `permissions.allow` of `.claude/settings.local.json`
    or of `.claude/settings.json`, or when `permissions.defaultMode` is `acceptEdits` or `bypassPermissions` in
    either file (the project already covers it; the plan names which file or mode). Otherwise it is **create**
    (the file is missing) or **change** (the file is there).
  - **Show the exact text** in the plan message, next to the CLAUDE.md and settings texts: with the file
    missing, the whole file that will be created, `{ "permissions": { "allow": [ "Edit(**)" ] } }` written with
    2-space indentation and LF endings; with the file present, the diff, one added line `"Edit(**)"` at the
    end of `permissions.allow` (the array is created when the file has none), every other byte unchanged.
    The line says in one sentence what is granted (file edits and writes inside the project directory, not Bash,
    not other directories) and that `.claude/` still prompts.
  - **Git.** When `git check-ignore -q .claude/settings.local.json` fails, the file is not ignored: the line says
    "not ignored by git; add it to .gitignore, it is personal". Never edit `.gitignore`.
  - **Apply** with the other settings changes, merging into the existing array
    without removing or reordering an entry (the rule of **Permissions**); a missing file is created as `{}` plus the array. Read the file back; a
    line whose read-back does not show `Edit(**)` is **failed**, with the reason.
  - **Declined.** A line the user skips is **declined**: neither settings file is touched, and the report says
    `Edit permission: declined (edits will prompt)`. It is not asked again in this run.
  - **Report row**, one of: `added to .claude/settings.local.json`, `exists (<file or defaultMode>)`, `declined`,
    `failed: <reason>`. After an add the report also says that the slots under `worktrees.root` are covered by
    **Run permissions**, not by this rule, and that a headless run (`claude -p`) ignores a project's allow rules
    until the workspace is trusted once in an interactive session.
- **Run permissions**: so that `/spec`, `/next` and `/fix` take an item to an open pull request, and `/check` and
  `/status` run, without a prompt, add to the personal `.claude/settings.local.json` (never to `settings.json`: the
  paths are absolute and differ per machine, and letting an unattended run commit and push is the choice of whoever
  runs it) the git commands the skills run, the slot root, one edit rule for the slots, the scripts at the plugin's
  folder and the quick check. Merge into the existing arrays without removing or reordering an entry; the rules of
  **Permissions** and **Edit permission** stay as they are.
  - **Values.** `<C>` is `verification.check`, `<B>` `git.baseBranch`, `<Sp>`, `<Fe>`, `<Fx>` `git.specPrefix`,
    `git.featurePrefix`, `git.fixPrefix` (defaults `main`, `spec/`, `feat/`, `fix/`). `<R>` is the slot root,
    resolved the way the slot script of the shell in use does it, without creating it: the main checkout is the
    parent of `git rev-parse --path-format=absolute --git-common-dir`; `<R>` is `<main>/<worktrees.root>` (default
    `../<main folder name>-wt`) with `.` and `..` resolved as text, in the form the script prints (bash: `/c/...`
    under Git Bash, `/...` elsewhere; PowerShell: `C:\...`). `<S>` is one slot, `<R>/slot-<n>` with the separator
    of that form. `<P>` is `${CLAUDE_PLUGIN_ROOT}` exactly as it expands in this text, the same string every skill
    of this installed version expands to, so a rule and the command the model copies from a skill are the same text.
  - **A. The main checkout**, 15 rules: `Bash(git fetch origin)`, `Bash(git switch *)`, `Bash(git add *)`,
    `Bash(git commit *)`, `Bash(git push -u origin <Sp>*)`, `Bash(git push -u origin <Fe>*)`,
    `Bash(git push -u origin <Fx>*)`, `Bash(git pull --ff-only)`, `Bash(git rebase origin/<B>)`,
    `Bash(git rebase --continue)`, `Bash(git stash push *)`, `Bash(git stash list)`, `Bash(git ls-tree *)`,
    `Bash(git rev-parse *)`, `Bash(<C> --quick)`.
  - **B. Each slot**, 21 rules per slot `<S>`, for n from 1 to `worktrees.slots`, in this order:
    `Bash(git -C <S> status *)`, `Bash(git -C <S> diff *)`, `Bash(git -C <S> log *)`, `Bash(git -C <S> add *)`,
    `Bash(git -C <S> commit *)`, `Bash(git -C <S> stash push *)`, `Bash(git -C <S> stash list)`,
    `Bash(git -C <S> stash pop *)`, `Bash(git -C <S> hash-object *)`, `Bash(git -C <S> rev-parse *)`,
    `Bash(git -C <S> ls-tree *)`, `Bash(git -C <S> merge-base *)`, `Bash(git -C <S> reset --mixed -q *)`,
    `Bash(git -C <S> reset -q -- *)`, `Bash(git -C <S> update-index *)`, `Bash(git -C <S> checkout-index *)`,
    `Bash(git -C <S> symbolic-ref *)`, `Bash(git -C <S> rebase origin/<B>)`, `Bash(git -C <S> rebase --continue)`,
    `Bash(git -C <S> push -u origin <Fe>*)`, `Bash(git -C <S> push -u origin <Fx>*)`. A slot added later (a higher
    `worktrees.slots`, `--capacity --slot-count`) has no rules until `/init` runs again.
  - **C. Edits in the slots**, one rule: `Edit(//<R as POSIX path, without its leading slash>/slot-*/**)`, for
    example `Edit(//Users/a/work/app-wt/slot-*/**)` or, on Windows, `Edit(//c/Users/a/work/app-wt/slot-*/**)`.
    `slot-*` is one path segment, so `<R>/.slots/` (markers, ledger, capacity) is not covered and still prompts.
  - **D. The scripts**, 10 rules, for `<name>` in `slot`, `room`, `gate`, `validate-config`, `status`:
    `Bash(bash "<P>/scripts/<name>.sh" *)` and
    `Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "<P>/scripts/<name>.ps1" *)`. Other scripts get no
    rule. The folder holds the version, so after an upgrade the next run finds these missing and adds the new ones;
    rules of another plugin folder already in the file are kept, and the plan says
    `kept: <k> script rules for another plugin folder`.
  - **E. The directory**: `<R>` once in `permissions.additionalDirectories` (the array is created when missing),
    so files in the slots are read without a prompt and a `cd` into a slot is read-only.
  - **Count.** `26 + 21 × worktrees.slots` rules and one directory: 68 rules for 2 slots, 110 for 4.
  - **Never broader.** Each rule names its subcommand before the first `*`. No bare `git push` rule, no wildcard
    for git as a whole or for `git -C` in any directory, no hard reset, no `git stash drop`, `git branch -D`,
    `git clean` or `git checkout`. Refusing the forbidden actions is the job of **Deny rules** and the plugin's guard hook (#110), not this line's.
  - **Unmatchable root.** When `<R>` contains a space, a quote or (in the bash form) a backslash, the line is
    **failed**: `worktrees.root resolves to <R>, which a rule cannot match unquoted; slot commands will prompt`;
    A and D are still written.
  - **Detect.** A rule is present when it is in `permissions.allow` of `.claude/settings.local.json` or of
    `.claude/settings.json` (string equality), `<R>` when it is in `permissions.additionalDirectories` of either.
    The line is **exists** when all are present, or when `permissions.defaultMode` is `bypassPermissions` in either
    file (`exists (defaultMode bypassPermissions)`); `acceptEdits` covers only C and does not make it **exists**.
    Otherwise it is **create** (no local file) or **change**.
  - **Show the exact text** in the plan message, next to the CLAUDE.md, `settings.json` and edit-permission texts:
    for a missing file the whole file (2-space indentation, LF, `permissions.allow` in the order A, B by slot then
    by rule, C, D, then `permissions.additionalDirectories`); for a present file the diff (the missing rules
    appended at the end of `permissions.allow` in that order, `<R>` appended to `additionalDirectories`, every other
    byte unchanged). Above it one sentence: it grants the skills' git commands in the main checkout and in the
    slots, edits in the slots, the five scripts of nightmill `<version>` and the quick check; it does not grant
    other git commands, other directories or other scripts; the plugin's scripts change folder with each version.
  - **Git.** The `git check-ignore` line of **Edit permission** covers this file too; it is said once.
  - **Apply** with the other settings changes, after **Edit permission**, merging without removing or reordering
    an entry. Read the file back; a line whose read-back lacks a rule or `<R>` is **failed**, naming the first
    missing one.
  - **Declined.** Neither settings file gets any of these entries; the report says
    `Run permissions: declined (the skills' git commands, scripts and slot edits will prompt)`.
  - **Report row**, one of: `added to .claude/settings.local.json (<k> rules, <d> directory)`,
    `exists (<file or defaultMode>)`, `declined (...)`, `failed: <reason>`. After an add the report says that the
    rules follow `worktrees.slots`, `worktrees.root`, the branch prefixes and the plugin version, and that `/init`
    is run again after any of them changes.
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
skip. The CLAUDE.md edit, the `settings.json` edits (the permissions and the deny rules) and the `.claude/settings.local.json` edits (the edit
permission and the **Run permissions**) are shown in the same message as the exact text or diff that will be
written, so that the one answer covers them. A skipped line is **declined** and is
not asked about again in this run.

When the plan holds only **exists** lines, ask nothing: say "already set up, nothing to change" and go
to the report.

## 5. Apply

Apply the kept lines in this order: board and fields, view, link, labels, config, forms, CLAUDE.md,
settings (the permissions, the deny rules, the edit permission, then the run permissions); then read the board workflows (read-only, see the plan). After each GitHub change read it back (`gh project field-list`, `gh label list`,
the `repositories` and `views` queries); a line whose read-back does not show the change is **failed**, with
the command's error, and the run goes on with the lines that do not depend on it (the view, the field options and the link depend on the board, the forms on the config; nothing else does).

**A board copied from the template** replaces "create the board and its fields" and goes in this order:

1. `gh project copy <number> --source-owner <owner> --target-owner <project owner> --title <repo>`, with
   `<owner>` and `<number>` from `templates/board-template.json`. Read the new board's number from the result
   and put it in `github.projectNumber` of the config written later.
2. The repository link (`gh project link`), as for any board.
3. **Only** the options of the `Area` field: replaced with `areas` through `updateProjectV2Field` with every
   option, as for any board (the copied ones are unused, so all are dropped). The `Priority` options are
   replaced too when `board.priorities` differs from the template's, and left alone otherwise. The `Status`
   field and its option ids are **not touched**: the workflows point at them.
4. Views that the copy did not bring are created as in the plan; the ones it brought are left alone.
5. **Read back**, after the changes: each view's filter, layout, grouping and sorting through GraphQL, on the
   copy and on the template (a public board, so the same query reads it)
   (`views(first: 20) { nodes { name filter layout groupByFields(first: 2) { nodes { ... on ProjectV2FieldCommon { name } } } verticalGroupByFields(first: 2) { nodes { ... on ProjectV2FieldCommon { name } } } sortByFields(first: 5) { nodes { direction field { ... on ProjectV2FieldCommon { name } } } } } }`;
   on a board layout `verticalGroupByFields` are the columns and `groupByFields` the swimlanes), and the
   workflows of the copy (`workflows(first: 20) { nodes { name enabled } }`). The copy matches when each of
   its views has the filter, grouping and sorting of the template's view of that name and the ten workflows are
   enabled. A view setting that differs from the template, a setting the plan expects that the copy does not
   show (`Board`: group by `Area`, sort by `Priority` descending; `Ready`: sort by `Priority` ascending), or a
   disabled workflow is reported **by hand** for that item only; the board is kept, never deleted.

If the copy itself fails, say so with the command's error, build the board field by field (the plan's
fallback) and put the reason in the report. A half-made copy is not reused: tell the user its number.

Every line is idempotent, so re-running is safe: a second run finds each line **exists** and applies nothing.

## 6. Report

End with one table: line, result (**created**, **changed**, **already there**, **declined**, **failed**,
**by hand**). Below it, "Still to do by hand:" with exactly the declined, failed and by-hand lines, or
"nothing". Do not print instructions for lines that were applied.

Below that, always, with no plan line and nothing asked (the hook comes with the plugin), print
`Guard hook: refuses a status edit to <ready> or <approved> and any merge without --auto (scripts/guard.sh)`, with
`board.statuses.ready` and `board.statuses.approved` for the names. When `git.mergeFlags` does not contain the word
`--auto`, add `git.mergeFlags is "<value>", without --auto: the guard refuses the skills' merge step; add --auto`.

**A board copied from the template** (the Board row says **created (copy of the template)**): when the read
back of step 5 matches (the views with grouping and sorting present, the ten workflows enabled), do not print
the browser-only settings below. Print one line instead: `Views, grouping, sorting and workflows came with the
template; their targets are the template's (the API cannot read them): <the workflows page link>.` When the
read back differs, list only the differing view setting or workflow, with the same instruction as below.

For a board built **field by field** (the fallback, a skipped copy, or a board that already existed), the
report is unchanged from before and starts with the reason for the fallback, if any. Then, **always**, even
when everything else was already there, print the board settings that only the
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
