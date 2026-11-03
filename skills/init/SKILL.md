---
name: init
description: Set a project up for nightmill - write .claude/nightmill.json, render the issue forms, check the board's status options and print the CLAUDE.md snippet. Use when installing nightmill in a repository or when the config is missing.
disable-model-invocation: true
---

Set this repository up for the nightmill workflow.

Current configuration, if any:

!`cat .claude/nightmill.json 2>/dev/null || echo "(no .claude/nightmill.json yet)"`

The plugin's files are under `${CLAUDE_PLUGIN_ROOT}`. Work through these steps and report each result.

## 1. The configuration file

If `.claude/nightmill.json` exists, keep it and only fill gaps. Otherwise start from
`${CLAUDE_PLUGIN_ROOT}/templates/nightmill.example.json` (the schema is
`${CLAUDE_PLUGIN_ROOT}/schema/nightmill.schema.json`; every key is described there) and find the real
values before asking:

- `github.owner` and `github.repo`: `gh repo view --json owner,name`.
- `github.projectNumber`: `gh project list --owner <owner> --format json`; if several, ask.
- `maintainer.name`: `gh api user --jq .name` (fall back to the login); confirm with the user.
- `verification.check`: the project's existing check script or CI steps (look in `scripts/`, `Makefile`,
  `package.json`, `.github/workflows`). If there is none, propose one and ask.
- `areas`, `invariants`, `escalation.storyTriggers`, `parallel.hotFiles`, `worktrees.*`: read the
  repository's README and CLAUDE.md for hints, propose values, and ask the user to confirm them.
  Delete keys that do not apply instead of leaving example values in.

Write the file with LF line endings. Then check it against the schema by reading both; there is no
validator to run.

## 2. The issue forms

Run the renderer from the repository root:
`"${CLAUDE_PLUGIN_ROOT}/scripts/render-templates.ps1"` (PowerShell) or
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/render-templates.sh"`. It writes `.github/ISSUE_TEMPLATE/{epic,story,bug,config}.yml`
from `areas` and `invariants`. If the directory already has forms, show the diff before overwriting and ask.

## 3. The board

Read the board's `board.statusField` options
(`gh project field-list <project> --owner <owner> --format json`) and compare them with
`board.statuses`. For each missing option print the GraphQL `updateProjectV2Field` call that adds it
(it must list **every** existing option with its id, or existing items lose their status) and ask the
user whether to run it or add the options in the GitHub UI. Also check the labels (`gh label list`)
against `labels` and `areas`, and offer to create the missing ones with `gh label create`.

## 4. CLAUDE.md and settings

Print `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.snippet.md` and offer to add it to the project's
CLAUDE.md. Suggest permission rules for `.claude/settings.json` that the workflow needs:
`Bash(gh project:*)`, `Bash(gh issue:*)`, `Bash(gh pr:*)`, `Bash(gh api:*)`, `Bash(git status:*)`,
`Bash(git diff:*)`, `Bash(git log:*)`, and one for `verification.check`. Do not edit settings.json yourself.

## 5. Report

End with a short table: step, done or skipped, what the user still has to do by hand.
