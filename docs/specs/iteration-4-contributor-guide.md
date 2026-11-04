# Iteration 4: a contributor guide and nightmill's own bug and idea forms

Status: draft, awaiting approval (#5)

Story: #5, epic #1 (Public release). Adds documentation and two issue forms, a pull request template, two
labels, one lint check and a CI line. No config key, no change to the status flow, no change to the slot
marker, no script behaviour: none of `escalation.storyTriggers` applies, so the PR may auto-merge.

## Goal

Someone who has never seen this repository can report a problem or propose an idea in the right form and
open a pull request that passes CI on the first try.

## Facts this rests on

- `.github/ISSUE_TEMPLATE/{epic,story,bug,config}.yml` are rendered from `templates/ISSUE_TEMPLATE/` by
  `render-templates` for this repository's own use. The renderer writes exactly those four files and leaves
  every other file in the folder alone. `config.yml` sets `blank_issues_enabled: false`.
- The GitHub API reports no issue templates for a private repository: this repository and another private
  one both return an empty list although both hold forms. So the forms cannot be validated by API before the
  repository is public. They are checked in the browser's issue chooser, and again by API after the switch.
- The lint's generic-words check reads a private word list. CI has no such secret today, so the check prints
  "skipped" in CI and runs only on the maintainer's machine. A pull request from a fork never receives
  secrets, so for fork PRs it would stay skipped even with the secret.
- The README no longer says the repository is private (done outside this story).

## What is built

### `CONTRIBUTING.md` (repository root)

Sections, in this order, each short:

1. **Reporting a problem or an idea.** Use the two forms. A security problem is not filed as an issue: it
   goes through private vulnerability reporting, see `SECURITY.md`.
2. **How work is decided here.** The project board; `Ready` and `Approved` are set by the maintainer only;
   an agent or a person works only on an issue at one of those two statuses. An issue from a stranger is
   triaged by the maintainer: it is closed, answered, or becomes a story. Pull requests for a bug fix or a
   documentation fix are welcome directly. A new feature or a behaviour change needs an idea issue first and
   a `Ready` story, because the spec comes before the code.
3. **Setting up.** Fork and clone; run Claude Code from the clone with `claude --plugin-dir .` so the skills
   under test are the ones in the working tree; do not also install `nightmill@nightmill` in that checkout.
   Set a git identity; GitHub's no-reply address is fine.
4. **Before a pull request.** Run `bash tests/check.sh`. Say what it runs (lint, the hook smoke test, the
   PowerShell smoke tests, `claude plugin validate`) and what it skips (the bash smoke tests need `jq`; CI
   runs all of them, bash on Ubuntu and PowerShell on Windows). The rules a change must keep: every script
   exists in PowerShell and bash and behaves the same; a config key is a contract (schema, example, README
   table); the status flow changes only with a decision record in `docs/decisions/`; add a bullet under
   `Unreleased` in `CHANGELOG.md`; keep nightmill generic, with no project name, person or local path in any
   file, issue or comment. The generic-words check does not run on pull requests from forks, so the
   maintainer checks it in review.
5. **License.** Apache License 2.0; a contribution is licensed under it.

### Issue forms (`.github/ISSUE_TEMPLATE/`)

The files are `nightmill-bug.yml` and `nightmill-idea.yml`. Neither name is one of the four rendered files.
`config.yml` stays as rendered (it comes from a template shared with other projects).

**`nightmill-bug.yml`**: name `Report a problem with nightmill`, title prefix `[Bug] `, labels `bug` and
`needs-triage`. A markdown block first: "Security problems do not belong here, see SECURITY.md." Then:

| id | type | label | required |
|---|---|---|---|
| `area` | dropdown | What is affected: a skill, a script, the SessionStart hook, the templates or issue forms, the documentation, something else | yes |
| `shell` | dropdown | Shell used for the scripts: bash, PowerShell, both, not applicable | yes |
| `os` | dropdown | Operating system: Windows, macOS, Linux, other | yes |
| `claude_code_version` | input | Output of `claude --version` | yes |
| `nightmill_version` | input | The version in `plugin.json`, or the commit when you use `--plugin-dir` | yes |
| `install` | dropdown | Installed from the marketplace, or loaded with `--plugin-dir` | yes |
| `what_happened` | textarea | What happens | yes |
| `expected` | textarea | What should happen | yes |
| `reproduce` | textarea | How to reproduce: commands, steps, the command output | yes |
| `config` | textarea (render `json`) | Your `.claude/nightmill.json`, with owner, repository, names and paths replaced by placeholders | no |
| `checks` | checkboxes | "I searched the open issues" and "I removed private values from the config and the output" | both required |

**`nightmill-idea.yml`**: name `Suggest an idea for nightmill`, title prefix `[Idea] `, labels `idea` and
`needs-triage`. A markdown block first: "The maintainer triages ideas. An accepted idea becomes a story on
the project board; nobody starts work before it is marked Ready." Then `problem` (textarea, what you are
trying to do and what gets in the way, required), `proposal` (textarea, required), `alternatives` (textarea,
optional), `area` (the same dropdown as above, optional), `pr` (checkboxes, "I would like to send a pull
request for this", optional).

### Pull request template (`.github/pull_request_template.md`)

What and why; the linked issue or spec; a checklist: `bash tests/check.sh` passed, scripts changed in both
shells, `CHANGELOG.md` bullet added, nothing project-specific added.

### Labels

`idea` (colour `A2EEEF`, "A suggestion from outside, not yet triaged") and `needs-triage` (colour `FBCA04`,
"Waiting for the maintainer to look at it") are created in the repository with `gh label create`. They are
not part of the workflow's label scheme and `/init` does not create them.

### README

The Install section gets one sentence before the three commands that lists what a stranger needs: Claude
Code, `git`, `gh` signed in with `gh auth login` and the `project` scope (`gh auth refresh -s project`), and
`jq` for the bash scripts. A short "Contributing" section points to `CONTRIBUTING.md` and `SECURITY.md`.

### CI

The lint job gets `env: FORBIDDEN_WORDS: ${{ secrets.FORBIDDEN_WORDS }}`. Without the secret the behaviour is
what it is today. The maintainer creates the secret (one word per line) with `gh secret set FORBIDDEN_WORDS`;
this story does not set it.

### CHANGELOG

A bullet under `Unreleased` for iteration 4 (#5).

## Tests

- `tests/lint.sh` check `contributor files are wired`: `CONTRIBUTING.md` exists and contains `tests/check.sh`,
  `--plugin-dir`, `SECURITY.md`, `Ready`, `Approved`, `PowerShell` and `bash`; `nightmill-bug.yml` and
  `nightmill-idea.yml` exist, start with `name:`, contain `body:`, and the bug form contains the ids `shell`,
  `os`, `claude_code_version`, `nightmill_version` and `config`; `.github/pull_request_template.md` exists.
- `tests/smoke-render.sh` and `tests/smoke-render.ps1`: a case "render leaves other forms alone": a form named
  `nightmill-bug.yml` is placed in the target folder before `render-templates` runs with force; afterwards it
  is unchanged and the four rendered files are written.
- The existing lint (frontmatter, JSON, shell syntax, hook) and `claude plugin validate --strict` keep passing.
- Manual check (`templates` is not a manual-check path, but the forms are only proved in the browser): open
  the repository's `Issues > New issue` page; both new forms appear with every field of the tables above, the
  required ones marked, and the workflow forms appear next to them. After the repository is public,
  `repository.issueTemplates` in the GraphQL API lists both. The PR describes what was seen; the second part
  is a note for after the switch.

## Not done

- A code of conduct, GitHub Discussions, a public project board.
- Setting the `FORBIDDEN_WORDS` secret (the maintainer does).
- Any change to the rendered workflow forms or to `render-templates`; hiding or removing the rendered Epic,
  Story and Bug forms from this repository.
- Adding outsiders' issues to the board automatically.
- A contributor license agreement or a sign-off requirement.
- The release routine (#6) and making the repository public.

## Decisions for the maintainer

1. **Pull requests from strangers:** bug and documentation fixes directly, features only after an idea
   issue and a `Ready` story (section 2 of `CONTRIBUTING.md`). Change this if you want it stricter or looser.
2. **The chooser shows five forms** (Bug, Epic and Story rendered for the workflow, plus the two new ones).
   The Epic and Story forms mean nothing to an outsider, because this repository files its own stories with
   `/story`. Keep them, as the story's criteria say, or delete the rendered copies from this repository.
3. **The pull request template** is an addition beyond the story's criteria. Strike it if you do not want it.
