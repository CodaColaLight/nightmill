# 0003: nightmill develops itself on the installed release and previews from the release branch

Date: 2026-11-05

## Decision

This replaces the plugin-loading part of [0001](0001-nightmill-develops-itself.md). The rest of 0001
(the board, the labels, the eight statuses, specs under `docs/specs/`, the check command, the ruleset on
`main`) stays as it is.

- Work on the nightmill repository runs on the **installed release** of nightmill, installed at user scope
  from the marketplace in this repository. Claude Code is **not** started with `--plugin-dir .` in a checkout
  that is also being edited.
- Before a release, the maintainer installs the release pull request's branch as a **preview**:
  `claude plugin marketplace add CodaColaLight/nightmill#release/vX.Y.Z`, then
  `claude plugin install nightmill@nightmill`, and tries it in a real project. Releasing, or abandoning the
  preview, goes back to the stable marketplace with `claude plugin marketplace remove nightmill` and
  `claude plugin marketplace add CodaColaLight/nightmill`.
- To try a skill that is still being changed, start a session in another folder with
  `claude --plugin-dir <path to a separate checkout>`. The folder being edited and the folder being loaded
  as the plugin are never the same.

## Why

- A directory loaded with `--plugin-dir` is a protected path, so Claude Code does not auto-approve writes to
  it. With `--plugin-dir .` the whole repository is that directory. Checked on 2026-11-05 with the same
  headless write under `--permission-mode acceptEdits`: allowed without `--plugin-dir`, denied with it.
  Working on nightmill that way means a prompt for almost every edit, which defeats the lights-out purpose.
- A project that installs nightmill gets a copy from the marketplace, pinned by version. Developing on the
  installed release means the maintainer sees what a user sees. The preview step is where an unreleased
  change is tried before it reaches them; 0001 got that from the working tree.
- A git-based install is copied into the plugin cache, outside the repository, so it adds no protected path.

## Consequences

- An installed copy updates only when `version` in `plugin.json` changes. A skill fix merged to `main` does
  not reach the maintainer's own workflow until a version is cut. A fix that must be used sooner is tried with
  `--plugin-dir` on a separate checkout.
- One marketplace named `nightmill` can be registered at a time, and the plugin has the same name on every
  branch. The stable release and a preview replace each other; they are never installed together.
- A preview is a real `X.Y.Z`. `release.sh` and the lint accept only `X.Y.Z` with digits, so there is no
  `-rc` suffix. A preview that is abandoned leaves a branch and a closed pull request and no tag; the tag is
  only created by `--publish`. Allowing a pre-release suffix would be a story.
- Whether pushing a fix to the release branch is picked up by removing the marketplace and installing it again,
  without a new version, has not been checked. If it is not, a retest needs a new version and a new release
  branch.
- `.claude/CLAUDE.md`, `CONTRIBUTING.md` and the README's "run the plugin from a checkout" line describe the
  setup 0001 chose and change with this decision; so does the rule that nightmill is not installed in this
  repository.
