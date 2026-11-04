# Iteration 5: a release in two commands, and a lint that keeps the versions in step

Status: draft, awaiting approval (#6)

Story: #6, epic #1 (Public release). Adds `scripts/release.ps1` and `scripts/release.sh`, their smoke
tests, a lint check, a decision record and short documentation. No config key, no change to the status flow,
no change to the slot marker: none of `escalation.storyTriggers` applies, so the PR may auto-merge.

## Goal

The maintainer cuts a release with one command (and one more after the pull request merges), and cannot ship
a version whose manifest, changelog, README and tag disagree.

## Facts this rests on

- Projects pin nightmill by the `version` in `.claude-plugin/plugin.json`. A copy reaches a user only when
  that string changes. `marketplace.json` carries no version.
- A release today is three hand edits (`plugin.json`, `CHANGELOG.md`, the README's last line) and a tag, and
  nothing checks that they agree. Right now they do not: `plugin.json` says 0.1.1, the newest changelog
  heading says 0.1.1, the README says 0.1.0.
- `main` accepts changes only through a pull request that passes the three required checks. The admin bypass
  exists but this project never uses it. A script therefore cannot commit to `main` and push. It prepares a
  pull request; the tag is created after that pull request has merged. There is no ruleset on tags.
- `plugin.json` holds the version on a line of its own: `  "version": "0.1.1",`.

## The scripts

`scripts/release.ps1` and `scripts/release.sh`, same behaviour. No `jq`: the files are edited as text.

| | PowerShell | bash |
|---|---|---|
| Prepare a release | `release.ps1 -Version 0.2.0` | `release.sh --version 0.2.0` |
| Publish after the merge | `release.ps1 -Version 0.2.0 -Publish` | `release.sh --version 0.2.0 --publish` |
| Show what would happen, change nothing | add `-DryRun` | add `--dry-run` |
| Skip the push and the pull request (tests) | add `-NoPr` | add `--no-pr` |
| Skip the GitHub Release (tests) | add `-NoRelease` | add `--no-release` |

Files are read and written as UTF-8 without a BOM, and line endings stay as they are. The date is the current
UTC date, `yyyy-MM-dd`. Exit code 0 on success; 1 with one line `refused: <reason>` on standard error for every
refusal below; 2 for a usage error or a missing tool (`git`, and `gh` unless `--no-pr` or `--no-release`).

### Prepare (`--version X.Y.Z`)

Refuses, in this order, with the reason named, when:

1. the version is not three numbers separated by dots (`X.Y.Z`, digits only);
2. the working tree has uncommitted changes (including untracked files);
3. the current branch is not `main`, or `main` is not equal to `origin/main` after a fetch;
4. the version is not greater than the one in `plugin.json` (compared number by number);
5. `CHANGELOG.md` has no `## Unreleased` heading, or nothing between it and the next `## ` heading except
   blank lines;
6. the tag `vX.Y.Z` already exists locally or on `origin`, or the branch `release/vX.Y.Z` exists.

Otherwise, in a new branch `release/vX.Y.Z` made from `main`, it makes exactly these changes and one commit
`Release X.Y.Z`:

- `plugin.json`: the `version` line becomes `X.Y.Z`.
- `CHANGELOG.md`: `## Unreleased` is followed by a blank line and a new heading `## X.Y.Z (yyyy-MM-dd)`, so
  the old Unreleased bullets sit under the new heading and `Unreleased` is empty again.
- `README.md`: the line that starts with `Version ` (in "Status and license") becomes
  `Version X.Y.Z. Apache License 2.0, see `LICENSE`.`

Then, unless `--no-pr`: it pushes the branch and runs `gh pr create` with the title `Release X.Y.Z`, the new
changelog section as the body and a last line telling the maintainer to run the script with `--publish` after
the merge. It does not enable auto-merge, because releasing is the maintainer's act. It prints the pull request
URL and switches back to `main`.

With `--dry-run` it performs the refusal checks, prints the plan (the three edits as before and after
lines, the branch name, the pull request title) and stops. Nothing is written, created or pushed.

### Publish (`--version X.Y.Z --publish`)

Refuses when:

1. the version is not valid, the working tree is dirty, or `origin/main` cannot be fetched;
2. `origin/main`'s `plugin.json` does not hold `X.Y.Z` (the release pull request has not merged), or its
   `CHANGELOG.md` has no `## X.Y.Z (` heading, or its README has no `Version X.Y.Z.` line;
3. the tag `vX.Y.Z` already exists locally or on `origin`.

Otherwise it finds the oldest commit on `origin/main`'s first-parent history whose `plugin.json` holds
`X.Y.Z` (the merge of the release pull request, not whatever `main` has become since), creates the annotated
tag `vX.Y.Z` on it with the message `nightmill X.Y.Z`, and pushes the tag. Unless `--no-release` it then runs
`gh release create vX.Y.Z --title "nightmill X.Y.Z" --notes <the changelog section of X.Y.Z> --verify-tag
--latest`. With `--dry-run` it prints the commit it would tag and stops.

## The lint check

`tests/lint.sh` gains `release metadata agrees`: the `version` in `plugin.json`, the first version heading in
`CHANGELOG.md` below `## Unreleased` (`## X.Y.Z (yyyy-MM-dd)`), and the `Version X.Y.Z.` line of `README.md`
must name the same version, and the heading must carry a valid date. A mismatch prints one `FAIL:` line that
shows the three values.

The same PR makes the check pass: the README's last line becomes `Version 0.1.1. Apache License 2.0, see
`LICENSE`.` (the version `plugin.json` holds today). The PR does not bump the version.

## Other changes

- `tests/smoke-release.sh` and `tests/smoke-release.ps1` (below), added to `tests/check.sh` and to the bash and
  PowerShell jobs of `.github/workflows/ci.yml`.
- `docs/decisions/0002-releases-go-through-a-pull-request.md`: `main` takes changes only through pull
  requests, so a release is prepared as a pull request and tagged after it merges; the script never uses
  the admin bypass.
- `.claude/CLAUDE.md`: the rule "CHANGELOG by version" names the script instead of describing the hand edits.
  `README.md`: a short "Releasing" paragraph under "Developing nightmill" and the new smoke tests in its
  command list. `CHANGELOG.md`: a bullet under `Unreleased` for iteration 5 (#6).

## Tests

`tests/smoke-release.sh` and `tests/smoke-release.ps1`, in a throwaway repository with a bare `origin`, a
copy of the three files and a `main` branch, no `gh` needed (`--no-pr`, `--no-release`):

1. **Refusals**, each leaving the repository untouched (`git status` clean, no new branch, no new tag), each
   with its reason in the message: invalid version `1.2`; dirty working tree; not on `main`; `main` behind
   `origin/main`; version equal to and lower than the current one; empty `Unreleased`; missing `Unreleased`
   heading; existing tag; existing release branch.
2. **Dry run**: prints the plan, exit code 0, repository untouched.
3. **Prepare**: branch `release/v0.2.0` with exactly one new commit `Release 0.2.0`; `plugin.json` holds
   `0.2.0` and is otherwise unchanged; `CHANGELOG.md` has an empty `Unreleased` followed by `## 0.2.0
   (<today>)` over the old bullets and the older sections unchanged; the README line reads `Version 0.2.0.`;
   no file other than these three changed.
4. **Publish**: the release commit is merged into `main` and pushed (the test plays the maintainer), then one
   more commit is added to `main`; publish creates the annotated tag `v0.2.0` on the release commit and not
   on the later one, and the tag exists on `origin`. Publish before the merge refuses; publish twice refuses.
5. The lint check: a copy of the real repository files with one version changed makes `tests/lint.sh` report a
   mismatch; the real files pass.

The existing lint, smoke tests and `claude plugin validate --strict` keep passing.

Manual check (a script that talks to GitHub): in a clone, `release.ps1 -Version 0.1.2 -DryRun` and the bash
equivalent print the plan and leave `git status` clean; the maintainer then runs the first real release
(see below). The PR describes what was seen.

## Not done

- Pre-release versions (`0.2.0-rc.1`), signed tags, release assets, rolling a release back.
- Enabling auto-merge on the release pull request.
- Cutting a release. The first real release (0.2.0, which would carry the install chat, the hook, the
  contributor files and the release script itself) is run by the maintainer after this story merges.
- Publishing to the Anthropic plugin directory, and any change to how projects pin a version.
- A check that every changelog heading has a tag.

## Decisions for the maintainer

1. **Two steps instead of one.** The story says "commits and tags". Because `main` only takes pull requests,
   the commit goes into a release pull request and the tag follows the merge. The alternative is to push to
   `main` with the admin bypass, which this project does not do.
2. **No auto-merge on the release pull request.** You merge it, then run `--publish`.
3. **A decision record** (`0002`) is added for the two-step flow. Strike it if you consider it too small.
