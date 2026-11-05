# .claude/CLAUDE.md

nightmill is a Claude Code plugin that carries a lights-out development workflow; `README.md` says what
it is and how a project installs it. This file is for working *on* nightmill.

## Development process

This project runs on the [nightmill](https://github.com/CodaColaLight/nightmill) workflow plugin: itself, from
the installed release. The rules are in `skills/workflow/SKILL.md`
(`/nightmill:workflow`); this project's values are in `.claude/nightmill.json` (board 2 on the
`CodaColaLight` account, labels, areas, the check command, slots). `/spec` writes the
spec for a Ready story, `/next` implements an Approved one, `/fix` fixes a bug, `/story` files a story,
`/check` runs the check. An agent only works on issues whose board status is Ready or Approved; only the
maintainer sets those. Run the check before every commit; never commit red.

**Work on the installed release; never `claude --plugin-dir .` here** (`docs/decisions/0003`). A folder
loaded with `--plugin-dir` is a protected path, so with `.` almost every edit in this repository prompts.
Edit in a worktree (`../nightmill-wt/<slug>`). To try a skill that is still changing, start a session in
another folder with `claude --plugin-dir <a separate checkout>`. Before a release, install the release
branch as a preview: `claude plugin marketplace add CodaColaLight/nightmill#release/vX.Y.Z`. Only one
marketplace named `nightmill` is registered at a time (stable or preview), and never load the same skills
twice (installed and `--plugin-dir`) in one session; they shadow each other.

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
  bullet under `Unreleased` naming the iteration and the issue; the maintainer cuts a version with
  `scripts/release.sh --version X.Y.Z` (or `release.ps1`), merges the release pull request it opens, then runs
  it again with `--publish` to tag. The lint keeps `plugin.json`, the changelog and the README line in step.
  Projects pin by version.
- **CI and merging.** `ci.yml` runs on every push and PR to `main`. A ruleset protects `main`: squash
  only, no force push, a PR merges only when the lint and both smoke-test jobs pass
  (`claude plugin validate` does not block). Only ever `gh pr merge <n> --auto --squash`; a plain
  `gh pr merge` would let the admin bypass merge a red PR. A red PR is fixed, never forced.

## Commands

```sh
bash tests/check.sh                                   # everything the machine can run
bash tests/lint.sh                                    # generic words, JSON, skill frontmatter, shell syntax
bash tests/smoke-slot.sh; bash tests/smoke-render.sh; bash tests/smoke-json.sh
powershell -ExecutionPolicy Bypass -File tests/smoke-slot.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-render.ps1
claude plugin validate . --strict
powershell -ExecutionPolicy Bypass -File scripts/render-templates.ps1 -Project . -Force   # after editing areas or invariants
powershell -ExecutionPolicy Bypass -File tools/make-icon.ps1                               # after editing the icon
powershell -ExecutionPolicy Bypass -File tools/make-social-preview.ps1                     # after the icon or the tagline changes; upload docs/social-preview.png in Settings > General by hand
```

## Layout

```
.claude-plugin   plugin.json (name, version), marketplace.json, icon.png
skills           one folder per skill: workflow (rules), spec, next, fix, story, check, init
agents           worker.md, code-reviewer.md
scripts          slot, new-worktree, render-templates; each as .ps1 and .sh
schema           nightmill.schema.json, every config key described
templates        nightmill.example.json, ISSUE_TEMPLATE/*.yml with {{placeholders}}, CLAUDE.snippet.md
tests            lint.sh, smoke-*.sh/.ps1, check.sh/.ps1
tools            make-icon.ps1, make-social-preview.ps1, fonts/ (Creepster, SIL OFL, licence beside it)
docs             specs/ (iteration specs), decisions/
```
