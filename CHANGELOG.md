# Changelog

## Unreleased

- Iteration 12 (#48): `/nightmill:init` installs the edit permission a lights-out run needs. A new plan line,
  **Edit permission**, adds the rule `Edit(**)` to `permissions.allow` of the personal
  `.claude/settings.local.json`, so `/spec`, `/next` and `/fix` write files inside the project without a prompt
  (not Bash, not other directories; `.claude/` still prompts). The plan shows the exact text or diff before the
  one confirmation, says when the local file is not ignored by git, reports a skipped line as `declined (edits
  will prompt)` and a covered project (the rule in either file, or `defaultMode` `acceptEdits` or
  `bypassPermissions`) as `exists`, and never removes or reorders an entry. The README has a section "The edit
  permission". The slots under `worktrees.root` are outside the project directory and are not covered; that is
  the next story of the unattended-runs epic. The lint has a section that pins the wording, including that
  `Edit(/**)`, which reaches outside the project, is never written. No script and no config key changed.

## 0.2.0 (2026-11-05)

- Iteration 11 (#33): the workflow skill defines the agent roles and how a skill picks a role's model. A new
  section "Agent roles and models" lists the seven roles with what each produces and which role reviews which,
  and states the rule: the model of a role is `roles.<role>.model`, else the default in the schema, passed
  explicitly on every launch, never inherited from the session and never through a fork. A model that cannot be
  used stops the run with a line naming the role and the model; no skill falls back to another model. The old
  "always pass a model" sentence in "Parallel work" is replaced by a pointer to the section, and the README says
  the same in one sentence. The lint checks that the section names every role of the schema, carries the rule's
  wording, and that `agents/worker.md` has the schema default; a smoke case in both shells shows the lint fails
  when a role is missing.
- Iteration 10 (#31): three optional config keys name the agent roles and their models. `roles.<role>.model` sets
  the model of `specWriter`, `specReviewer`, `tester`, `implementer`, `codeReviewer`, `fixer` and `worker` (a role
  that is absent or empty takes the default in the schema), `models.ranking` lists models weakest first (models of
  one level share an entry joined by `=`) and `review.maxFixRounds` is how many fix rounds a producer gets after a
  review (default 2). All three are in the schema with descriptions and defaults, in the example config, in this
  repository's own config and in the README. Nothing reads them yet, so a project without them behaves as before.
  The lint checks the schema, the example, the repository's config and the README for them; both validate smoke
  tests cover the new keys.
- Iteration 9 (#10): `/nightmill:init` copies nightmill's template board when a project has none, so the views
  (filters, grouping, sorting) and the workflows come configured and nothing is left for the browser. It links
  the repository, replaces only the Area options (and Priority when `board.priorities` differs) and keeps the
  Status options and their ids. `scripts/template-board.ps1` and `scripts/template-board.sh` check, read only,
  whether the template is usable for a candidate config and print one line; when it is not (none published, not
  reachable, a renamed field or status) `/init` says why in the plan and builds the board field by field as
  before. The template's location is `templates/board-template.json`, not a config key; its number stays `null`
  until the maintainer publishes the template. Smoke tests run both scripts against fixtures and a fake `gh`; the
  lint checks the wiring and that the scripts only read.
- Iteration 8 (#9): `/nightmill:status` prints one table of what waits for the maintainer and what is stuck:
  board items with their pull request and CI state, the busy slots, and stale states flagged (Review with a
  merged PR, In progress or Spec with nothing behind it, a busy slot whose PR is merged or closed). It reads only.
  `scripts/status.ps1` and `scripts/status.sh` print the same table (the bash one needs no `jq`); `slot --porcelain`
  lists the slots for scripts. Smoke tests run both against fixtures and a fake `gh`.
- Iteration 7 (#7): the bash scripts read JSON without `jq`. `scripts/lib/json.awk` is a strict JSON parser in
  POSIX awk and `scripts/lib/json.sh` the functions on top of it (`json_get`, `json_len`, `json_keys`, `json_has`,
  `json_quote`, `json_marker`); `slot.sh`, `new-worktree.sh`, `render-templates.sh` and `validate-config.sh` use
  them, the validator's walk is now `scripts/lib/validate.awk`, and the slot marker is byte for byte what it was.
  The bash smoke tests run on a machine with only git, gh and bash; CI cross-checks the reader against `jq`, then
  hides `jq` for the other bash tests, and the lint fails if a bash file starts using `jq` again.
- Iteration 6 (#8): `scripts/validate-config.ps1` and `scripts/validate-config.sh` check a config against the
  schema: required keys, types, `minimum`, `minItems`, `enum`, closed objects, and a warning for an unknown key
  with a hint for a likely typo (`worktree` for `worktrees`). One line per finding names the key; the bash version
  needs `jq`. `/init` validates the candidate config before it shows the plan, and the lint validates the example
  and this repository's own config and fails if the schema gains a keyword the validator does not understand.
- Iteration 5 (#6): `scripts/release.sh` and `scripts/release.ps1` cut a release in two steps: prepare a
  `release/vX.Y.Z` pull request (version bump, changelog cut, README line), then `--publish` after the merge
  to tag the release commit and create the GitHub Release. `--dry-run` shows the plan. The lint fails when
  `plugin.json`, the newest changelog heading and the README's `Version` line disagree; the README line now
  reads `Version 0.1.1.`. Decision 0002 records why a release goes through a pull request.
- Iteration 4 (#5): `CONTRIBUTING.md`, two issue forms for outsiders (`nightmill-bug.yml` and
  `nightmill-idea.yml`, next to the rendered workflow forms), a pull request template, and a README line on
  what a stranger needs before installing. The lint checks that they exist and say what the spec requires;
  the render smoke tests check that rendering leaves other forms alone; the lint job in CI passes the
  `FORBIDDEN_WORDS` secret to the generic-words check when the repository has one.
- Iteration 3 (#12): a `SessionStart` hook (`hooks/hooks.json`, `scripts/session-start.sh` and `.ps1`)
  makes Claude offer `/nightmill:init` in a project that has the plugin enabled but no
  `.claude/nightmill.json`; in a configured project it is silent. `NIGHTMILL_HINT=off` silences it for
  people who enabled the plugin at user scope.
- Iteration 2 (#14): `/spec` and `/next` are two commands. `/spec [N]` writes the spec for a Ready story
  and stops at Spec review; `/next [N]` implements an Approved story only and, with nothing Approved,
  lists the Ready stories and points to `/spec`. Both print `Picking #N ...` before they change anything
  (rule: "Picking an issue" in the `workflow` skill). **`/next` no longer writes specs**: a project note
  or habit that calls `/next` for a Ready story must call `/spec`.
- Iteration 1 (#10): `/init` is an install chat. It detects owner, repo, board, check command and areas,
  asks the rest one question at a time with a proposed default, shows one plan, and after one
  confirmation creates or completes the board (eight Status options with existing ids kept, Priority and
  Area, four views (Board, Ready, Epics, Bugs) with filters and visible fields so the statuses are columns,
  the repository link), the labels, the config, the issue forms, the CLAUDE.md snippet and the permission
  rules in `.claude/settings.json`; it ends with a table of created, changed, already there, declined and
  failed lines. Re-running changes nothing. The board workflows cannot be set through the API: `/init`
  reads whether the ten it needs are enabled and always ends with the table to set by hand in the board's
  Workflows settings (item added > Backlog, item closed and pull request merged > Done, pull request
  linked, code review approved and code changes requested > Review, item reopened > In progress, auto-add
  and auto-add sub-issues on, auto-archive of closed items after one day, kept short to limit the items
  fetched and the GitHub rate limits). A view's grouping and sorting cannot be set through the API either;
  both are listed in the same closing section.
- nightmill develops itself: `.claude/nightmill.json`, issue forms, `.claude/CLAUDE.md`, `tests/check.sh`
  (one check command that runs what the machine can and lists what it skipped) and decision 0001.
- Plugin icon (`.claude-plugin/icon.png`): a white windmill and crescent moon on dark purple,
  rendered by `tools/make-icon.ps1`.

## 0.1.1 (2026-11-03)

- The PowerShell scripts read the config, templates and markers as UTF-8. Windows PowerShell 5.1
  otherwise used the ANSI code page, which turned an em dash in an invariant into mojibake in the
  rendered issue forms.

## 0.1.0 (2026-11-03)

First extraction of the workflow out of the project it grew up in, as a Claude Code plugin.

- Skills `next`, `fix`, `story`, `check`, `init` and the `workflow` rules; every project-specific value
  moved to `.claude/nightmill.json` (schema in `schema/`).
- The status flow gained two states: **Spec review** (the spec is written and merged, waiting for the
  maintainer) and **Approved** (any worker may implement). The spec is now a PR of its own, so a
  different agent can pick the story up after approval.
- `worker` agent for mechanical jobs.
- Slot scripts in PowerShell and bash, configured from the project file (root, slot count, ports,
  warm-up commands with lockfile-hash skip, run hints); new `-Abandon` to free a slot without a merged PR.
- Issue-form templates rendered from `areas` and `invariants`.
- Tests: generic-words lint, JSON and skill checks, slot smoke tests in both shells; CI for all of them.
- Licensed under the Apache License 2.0.
