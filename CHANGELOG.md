# Changelog

## Unreleased

- Iteration 2 (#14): `/spec` and `/next` are two commands. `/spec [N]` writes the spec for a Ready story
  and stops at Spec review; `/next [N]` implements an Approved story only and, with nothing Approved,
  lists the Ready stories and points to `/spec`. Both print `Picking #N ...` before they change anything
  (rule: "Picking an issue" in the `workflow` skill). **`/next` no longer writes specs**: a project note
  or habit that calls `/next` for a Ready story must call `/spec`.
- Iteration 1 (#10): `/init` is an install chat. It detects owner, repo, board, check command and areas,
  asks the rest one question at a time with a proposed default, shows one plan, and after one
  confirmation creates or completes the board (eight Status options with existing ids kept, Priority and
  Area, a Board-layout view so the statuses are columns, the repository link), the labels, the config,
  the issue forms, the CLAUDE.md snippet and the permission rules in `.claude/settings.json`; it ends with
  a table of created, changed, already there, declined and failed lines. Re-running changes nothing.
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
