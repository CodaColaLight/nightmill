# 0002: a release goes through a pull request

Date: 2026-11-05

## Decision

A release is two steps. `scripts/release.sh --version X.Y.Z` (or `release.ps1 -Version X.Y.Z`) prepares the
branch `release/vX.Y.Z` with one commit (version bump in `plugin.json`, changelog cut, README `Version`
line) and opens a pull request. After the maintainer merges it, the same script with `--publish` creates the
annotated tag `vX.Y.Z` on the commit that introduced the version and publishes the GitHub Release.

The script never pushes to `main` and never uses the admin bypass of the `main` ruleset.

## Why

- `main` takes changes only through pull requests that pass the required checks. A script that committed
  and pushed to `main` would need the bypass, which this project does not use.
- The release pull request is where the maintainer looks at the changelog section before it becomes public.
- Tagging after the merge, and on the release commit rather than on whatever `main` has become, means the
  tag, `plugin.json` and the changelog heading always name the same commit.

## Consequences

- A release needs two commands and one merge. There is no auto-merge on the release pull request.
- Projects pin by the version in `plugin.json`; the tag and the GitHub Release are for people who read them.
- The lint compares `plugin.json`, the newest changelog heading and the README `Version` line, so a release
  prepared by hand cannot drift silently.
