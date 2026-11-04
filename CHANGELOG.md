# Changelog

## Unreleased

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
