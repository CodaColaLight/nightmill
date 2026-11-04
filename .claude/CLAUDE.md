# .claude/CLAUDE.md

nightmill is a Claude Code plugin that carries a lights-out development workflow; `README.md` says what
it is and how a project installs it. This file is for working *on* nightmill.

## Development process

This project runs on the [nightmill](https://github.com/CodaColaLight/nightmill) workflow plugin: itself, from
this working tree. The rules are in `skills/workflow/SKILL.md`
(`/nightmill:workflow`); this project's values are in `.claude/nightmill.json` (board 2 on the
`CodaColaLight` account, labels, areas, the check command, slots). `/spec` writes the
spec for a Ready story, `/next` implements an Approved one, `/fix` fixes a bug, `/story` files a story,
`/check` runs the check. An agent only works on issues whose board status is Ready or Approved; only the
maintainer sets those. Run the check before every commit; never commit red.

**Run the plugin from this checkout**, not an installed copy, so the skills under test are the ones in
the working tree: `claude --plugin-dir .` here, or `claude --plugin-dir <path to this checkout>` in
another project to try a change for real. Do not install `nightmill@nightmill` in this repository; two
copies of the same skills shadow each other.

## Rules the workflow skill does not know

- **Generic.** `tests/lint.sh` fails on any word from the private word list (`tests/forbidden-words.local.txt`): the name of the project
  nightmill was extracted from, its maintainer, its domain. That holds for issues and specs too.
- **Two shells.** A change to a script in `scripts/` is made in both the `.ps1` and the `.sh`, with a
  smoke step in both `tests/smoke-*.ps1` and `tests/smoke-*.sh`. `tests/check.sh` runs what the machine
  can run and lists what it skipped; CI runs all of it (bash on Ubuntu, PowerShell on Windows).
- **Config keys are a contract.** A new key goes into `schema/nightmill.schema.json` with a description
  and a default, into `templates/nightmill.example.json`, and into the README's configuration table.
  Renaming or removing one is a story, never a bug fix.
- **The status flow is fixed.** The eight statuses and who sets them change only with a decision record
  in `docs/decisions/` (short, dated, `NNNN-title.md`).
- **CHANGELOG by version.** `CHANGELOG.md` has one section per plugin version. An iteration's entry is a
  bullet under `Unreleased` naming the iteration and the issue; the maintainer cuts a version by moving
  `Unreleased` under a version heading and bumping `.claude-plugin/plugin.json`. Projects pin by version.
- **CI and merging.** `ci.yml` runs on every push and PR to `main`. A ruleset protects `main`: squash
  only, no force push, a PR merges only when the lint and both smoke-test jobs pass
  (`claude plugin validate` does not block). Only ever `gh pr merge <n> --auto --squash`; a plain
  `gh pr merge` would let the admin bypass merge a red PR. A red PR is fixed, never forced.

## Commands

```sh
bash tests/check.sh                                   # everything the machine can run
bash tests/lint.sh                                    # generic words, JSON, skill frontmatter, shell syntax
bash tests/smoke-slot.sh; bash tests/smoke-render.sh  # need jq
powershell -ExecutionPolicy Bypass -File tests/smoke-slot.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-render.ps1
claude plugin validate . --strict
powershell -ExecutionPolicy Bypass -File scripts/render-templates.ps1 -Project . -Force   # after editing areas or invariants
powershell -ExecutionPolicy Bypass -File tools/make-icon.ps1                               # after editing the icon
```

## Layout

```
.claude-plugin   plugin.json (name, version), marketplace.json, icon.png
skills           one folder per skill: workflow (rules), spec, next, fix, story, check, init
agents           worker.md
scripts          slot, new-worktree, render-templates; each as .ps1 and .sh
schema           nightmill.schema.json, every config key described
templates        nightmill.example.json, ISSUE_TEMPLATE/*.yml with {{placeholders}}, CLAUDE.snippet.md
tests            lint.sh, smoke-*.sh/.ps1, check.sh/.ps1
tools            make-icon.ps1
docs             specs/ (iteration specs), decisions/
```
