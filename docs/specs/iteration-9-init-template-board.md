# Iteration 9: /init copies a template board, so views and workflows come configured

Status: delivered in iteration 9 (PR #27)

Story: #10, epic #3 (Setup and onboarding). Adds `templates/board-template.json`, the scripts
`scripts/template-board.ps1` and `scripts/template-board.sh`, a "copy first" branch in `skills/init/SKILL.md`,
smoke tests, a lint check and a README section. No config key, no change to the status flow, no change to
the slot marker: none of `escalation.storyTriggers` applies, so the implementation PR may auto-merge.

## Goal

A maintainer who runs `/init` on a project without a board gets a board whose views (filters, grouping,
sorting, columns) and workflows are already configured as the flow needs, with nothing set by hand in the
browser. When that is not possible, `/init` works exactly as it does today and says why.

## Facts this rests on

Measured by the maintainer on a throwaway copy of a configured board
(`gh project copy <n> --source-owner <owner> --target-owner <owner> --title <title>`), from the issue:

- Fields, all views with filter, grouping, sorting and visible columns, and every workflow with its enabled
  state come across. Items and the repository link do not (the link is one `gh project link`).
- Replacing the Status options of a board disables the workflows that pointed at a removed option. A copy
  whose Status options already carry the right names keeps its workflows valid, because `/init` keeps an
  option whose name exists, with its id (iteration 1, "As built").

Not measured, and the first thing the implementation verifies:

- Whether a user who is **not** the owner can copy a **public** board, and whether the workflows survive that
  copy. Only copies inside one account were tested.
- Whether replacing the Area options of a copied board keeps the `Board` view's grouping by Area. The view
  refers to the field id, which stays, so it should; the read-back below checks it.

Decided by the maintainer (2026-11-05): the project board of this repository (board 2) stays **private**. The
template is therefore a separate board that holds no items, only structure, and is the only public one.

## Before implementation (maintainer)

Making a board public is the maintainer's call, so the implementation does not do it. When this spec is
approved and before `/next` runs, the maintainer:

1. Creates the template from the configured board 2: `gh project copy 2 --source-owner CodaColaLight
   --target-owner CodaColaLight --title "nightmill template"`; checks in the browser that it has no items
   and that the ten workflows of the `/init` table are enabled with their targets.
2. Makes it public: `gh project edit <n> --owner CodaColaLight --visibility PUBLIC`.
3. Comments the template's number on #10.

Until step 3 the implementation ships `templates/board-template.json` with `"number": null`, which every
script treats as "no template", so `/init` falls back. The PR that fills in the number is the last commit of
the implementation, after the stranger test below passed. If that test fails, the number stays `null` and the
story is split as the workflow rules say.

## `templates/board-template.json`

```json
{ "owner": "CodaColaLight", "number": null }
```

The location of nightmill's own template. It belongs to the plugin, not to a project, so it is not a config
key and not in `.claude/nightmill.json`: a project cannot point `/init` at another template (see Not done).
Valid JSON, `owner` a non-empty string, `number` an integer or `null`; the lint checks it.

## `scripts/template-board.ps1` and `.sh`

Same behaviour and output in both shells. Read-only: `gh project view`, `gh project field-list`, never
`gh project copy`, `item-edit` or any mutation. Run from the plugin root or anywhere: the script finds
`templates/board-template.json` next to itself.

| | PowerShell | bash |
|---|---|---|
| Check the template against a config | `template-board.ps1 -Config <file>` | `template-board.sh --config <file>` |

`<file>` is the candidate config `/init` builds in step 3 (before the plan). The script reads
`board.statusField`, `board.priorityField`, `board.areaField` and the eight `board.statuses`; a key the file
does not have takes its default from `schema/nightmill.schema.json`. Prints exactly one line:

- `template: usable (<owner>/<number>)`
- `template: not usable: <reason>`, the reason one of
  - `none published` (`number` is `null`)
  - `not reachable` (`gh` could not read the project: not found, no access, not public for this account)
  - `fields differ` (a field name of the config is not a field of the template, or is not single select)
  - `statuses differ` (the template's Status options are not exactly the eight `board.statuses`, in order)

Exit code 0 whenever the line was printed, "usable" or not. Exit 2 for a usage error, an unreadable file,
`gh` missing or not logged in; message on standard error. The bash version needs only git, gh and bash
(iteration 7).

## `/init` with a template

Step 1 (Detect) already finds whether a board exists. The new rule applies only when **none** exists.

1. **Check.** Run the script above on the candidate config. Only reading, so it belongs before the
   confirmation.
2. **Plan.** The **Board** line becomes one of:
   - `create (copy of <owner>/<number>)`, when the script said `usable`;
   - `create (field by field: <reason>)`, when it said `not usable`, with the reason in words
     (`no template published yet`, `the template is not reachable from this account`, `your config renames a
     field or a status`). This is the fallback and the plan says so, never silently.
   The user answers the single confirmation as today. A user who skips the copy line gets the
   field-by-field board.
3. **Apply the copy**, in the order of step 5: `gh project copy <number> --source-owner <owner> --target-owner
   <project owner> --title <repo>`; read the new board's number from the result; then the repository link
   (`gh project link`); then **only** the Area options: replaced with `areas` through `updateProjectV2Field`
   with every option, as today (the copied ones are unused, so all are dropped). The Priority options are
   replaced too when `board.priorities` differs from the template's, and left alone otherwise. The Status
   field and its option ids are **not touched**. The existing board-view lines of the plan are **exists**
   for every view the copy brought; a view that is missing is created as today.
4. **Read back** (new, after the changes): each view's filter, grouping and sorting through GraphQL, and the
   workflows (`workflows(first: 20) { nodes { name enabled } }`), as the existing read-only line does.
   A copy that lost the `Board` grouping, or that has a disabled workflow, is reported as **by hand** for
   that item only; the board is kept, never deleted.

### Report

- Copied board, read-back matches (views with grouping and sorting present, the ten workflows enabled): the
  Board row says **created (copy of the template)** and the "browser-only settings" section is replaced by one
  line: `Views, grouping, sorting and workflows came with the template; their targets are the template's.`
  The workflow targets themselves still cannot be read through the API, so the line says so and gives the
  workflows page link.
- Copied board, read-back differs: only the differing view setting or workflow is listed, with the same
  instruction as today.
- Field-by-field board (fallback, or the user skipped the copy): the report is unchanged from today, the
  two view settings and the ten-workflow table, plus the reason for the fallback.

## README

A section "The template board": where it lives (`templates/board-template.json`, a public board of the
maintainer with no items), what `/init` does with it, and how the maintainer refreshes it from a configured
board: `gh project copy` of the configured board under a new title, check that it holds no items, make it
public, update the number in `templates/board-template.json` in a PR, delete the old template board.

## Tests

- `tests/smoke-template-board.ps1` and `.sh`, with `gh` replaced by a fixture the way `smoke-status` does it.
  Scenarios: usable; `number` null; not reachable (`gh` exits 1); a field renamed in the config; one status
  renamed in the config; a Status option missing in the template; a key missing from the config (default
  taken); usage error (exit 2). Both shells print the same line in each.
- `tests/lint.sh`: `templates/board-template.json` is valid with the shape above; `skills/init/SKILL.md`
  mentions `gh project copy`, `template-board` and the fallback; the README has the section.
- `bash tests/check.sh` stays green.

## Verification

The skill is prose, so the manual check applies (`verification.manualCheckPaths` holds `skills`):

1. `claude --plugin-dir .` against a throwaway repository under the maintainer's account: `/init` copies,
   the read-back matches, nothing is left for the browser except what the report names. Run `/init` a second
   time: it changes nothing.
2. **The stranger test**, before the number is filled in: the same under a GitHub account that does not own
   the template, with the template public. Record whether views, grouping, sorting and all ten enabled
   workflows survived. A second account is needed; if there is none, the PR says "stranger copy not
   verified" and the number stays `null`, so no user gets an untested path.
3. With the template unreachable (number `null`, or a repository under an account that cannot read it):
   `/init` says so in the plan and builds the board field by field.

## Not done

- Copying items.
- A config key to point `/init` at another template, or a template for organisations: one template, the
  maintainer's.
- Creating, publishing or refreshing the template board from `/init` or from a script: it is the
  maintainer's, by hand, as described in the README.
- Changing the flow, the eight statuses or the workflows' targets.
- Replacing the Status options of a copied board. A config that renames a field or a status takes the
  fallback, not a rename after the copy.
- Making board 2 public.
