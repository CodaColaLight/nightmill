# 0001: nightmill develops itself, from the working tree

Date: 2026-11-04

## Decision

The nightmill repository runs on the nightmill workflow: its own board (project 2 on the
`CodaColaLight` account), the same labels, the same eight statuses, specs under `docs/specs/`, one
check command (`bash tests/check.sh`), a ruleset on `main` with auto-merge.

Claude Code is started with `claude --plugin-dir .` in this checkout. The plugin is **not** installed
from the marketplace here, so the skills in use are always the ones in the working tree, and a change
to a skill is exercised by the next story that runs through it.

## Why

- The workflow is the product. Every gap in a skill shows up first in the project that uses it most.
- Two copies of the same skills (installed and `--plugin-dir`) shadow each other; one source of truth
  avoids testing the wrong one.
- Projects that install nightmill pin a version. Dogfooding from the working tree means an unreleased
  change is tried here before it reaches them.

## Consequences

- The maintainer's name in `.claude/nightmill.json` is the GitHub account name, so the generic-words
  lint keeps holding for this repository too.
- `CHANGELOG.md` stays versioned; an iteration adds a bullet under `Unreleased`, a release moves it
  under a version heading (see `.claude/CLAUDE.md`).
- The check command runs what the machine can run and lists what it skipped; CI is the full run.
