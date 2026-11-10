# Iteration 38: CI runs with least privilege, timeouts and a concurrency that does not cancel main

Status: delivered in iteration 38 (PR #201)

Story: #154, epic #107 (Hardening from the code review), finding MD-T3 of the review of 0.2.0. `ci.yml` gets a
read-only token, a timeout on every job, a concurrency group that cancels only pull request runs, a comment on each
required job name and actions pinned by commit SHA; the lint pins all five. Changes `.github/workflows/ci.yml`,
`tests/lint.sh` and `CHANGELOG.md`. Nothing else: `.github/dependabot.yml` already does what the story asks (decision 6 below)
and stays as it is.

**Not a story trigger.** No config key is added, renamed or removed, the status flow and who sets a status do not
change, and the slot marker format does not change. No path in `verification.manualCheckPaths` (`skills`, `agents`,
`hooks`) changes (`.github` and `tests` are not among them), so **the manual check does not apply**. No script in
`scripts/` changes, so no smoke step is added; `tests/lint.sh` has no PowerShell twin (`tests/check.ps1` runs
`tests/check.sh` through bash), so the new lint pins exist in bash only.

## Goal

A compromised or hung job can do little damage and every `main` commit gets a result.

## Facts this rests on

Checked on 2026-11-07 against `main` at ef48c6b with read-only `gh` calls.

- `ci.yml` has no `permissions:` key at any level, no `timeout-minutes`, and
  `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }`, which also cancels a running push run on
  `main` when the next push arrives. The finding holds.
- It runs on `push` to `main` and on `pull_request`. Four jobs: `lint`, `smoke-bash`, `smoke-powershell`, `validate`
  (`continue-on-error: true`). Five `uses:` lines: `actions/checkout@v7` in every job, `actions/setup-node@v7` in
  `validate`. No other workflow exists under `.github/workflows/`.
- No job writes to GitHub: they check out, run tests, install `@anthropic-ai/claude-code` from npm and run
  `claude plugin validate` and `claude plugin test`. The lint reads the secret `FORBIDDEN_WORDS`; secrets are not
  governed by `permissions:`.
- The ruleset `main` (id 26558992, `gh api repos/CodaColaLight/nightmill/rulesets/26558992`) requires three status
  checks, by the job's `name:` (not its id): `Lint (generic, JSON, skills, shell)`, `bash scripts smoke tests`,
  `PowerShell scripts smoke tests`. `claude plugin validate (not blocking)` is not required.
- Both tags are lightweight (the ref's object type is `commit`), and the major tag points at the same commit as the
  newest release, so pinning changes no behaviour:

  | Action | Release | Commit (`gh api repos/<action>/git/ref/tags/<release>`) | `v7` points at |
  |---|---|---|---|
  | `actions/checkout` | `v7.0.1` (latest) | `3d3c42e5aac5ba805825da76410c181273ba90b1` | the same |
  | `actions/setup-node` | `v7.1.0` (latest) | `949feb2413d6458794dcd2491c4babbbce0c15c1` | the same |

- Job durations over the last 40 runs of `ci.yml` (from `started_at` to `completed_at` of the jobs API), longest:
  lint 16 s, bash smoke 130 s, PowerShell smoke 752 s (recent runs 449 to 752 s), validate 17 s.
- `.github/dependabot.yml` already lists `package-ecosystem: "github-actions"`, `directory: "/"`, weekly, commit
  prefix `ci`. It works: Dependabot opened #13 and #14 (checkout and setup-node 4 to 7), both merged.
- GitHub concurrency: a group holds at most one running and one pending run; a newly queued run **cancels the pending
  one** of its group even with `cancel-in-progress: false`. `cancel-in-progress` and `group` both accept expressions
  with the `github` context at workflow level.

## Decisions

**1. Permissions: `contents: read` at the top, no job asks for more.** Every job only reads the repository (checkout)
and needs nothing else from the token; `setup-node` reads the Node version manifest from another public repository,
which this repository's token scopes do not govern, so it needs no extra scope. Every other scope is then `none`. No job gets its own `permissions:` key.

**2. Timeouts: about 3 times the longest of the last 40 runs, rounded up to whole minutes, at least 5.**

| Job | Longest | × 3 | `timeout-minutes` |
|---|---|---|---|
| `lint` | 16 s | 48 s | 5 |
| `smoke-bash` | 435 s | 1305 s | 22 |
| `smoke-powershell` | 752 s | 2256 s | 38 |
| `validate` | 17 s | 51 s | 5 |

The floor of 5 is for the two jobs under a minute: 1 minute would cut a slow checkout or npm install, and 5 is still
a small fraction of the default of 360. The `smoke-bash` row was 130 s and 7 until bug #264 (a 435 s run cancelled
at 7 minutes). A job that hits its timeout is cancelled; for a required job the check does not pass and
the PR does not merge until it is re-run or the cause is fixed. A spec that adds enough
smoke steps to bring a job near its timeout raises the number.

**3. Concurrency: pull request runs share a group per ref and cancel; every push run is alone in its group.**

```yaml
concurrency:
  group: ci-${{ github.event_name == 'pull_request' && github.ref || github.run_id }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

A pull request run gets `ci-refs/pull/<n>/merge`, as today, so a new push to a PR cancels its older run. A push run
gets `ci-<run id>`, unique per run (a re-run keeps its run id and is still alone). `cancel-in-progress: false` alone
would not do: a third push to `main` would cancel the second one while it waits (fact above), so the group must be
unique. Two pushes to `main` in a row therefore run side by side and each commit gets its own result; the second
expression says the intent and makes sure a push run never cancels anything, even if the group is later changed.

**4. The comment on each required job name.** On the line directly above the `name:` of `lint`, `smoke-bash` and
`smoke-powershell`, indented like it, exactly:

```yaml
    # Required check: the ruleset on main requires this name; renaming it blocks every pull request.
```

`validate` gets no such comment (it is not required). No job id and no `name:` changes.

**5. Pins: the full commit SHA with the release in a trailing comment.**

```yaml
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
```

All four checkout lines take the first form, the setup-node line the second. The implementer confirms each with
`gh api repos/<action>/git/ref/tags/<release>` (object type `commit`: its `sha` is the pin; type `tag`: the pin is
`object.sha` of `gh api repos/<action>/git/tags/<that sha>`). If a newer release exists by then, the pins above still
go in; Dependabot proposes the bump.

**6. `.github/dependabot.yml` is not changed.** It already keeps the `github-actions` ecosystem current, and
Dependabot updates a SHA pin together with its `# vX.Y.Z` comment. The lint pins that the entry stays (decision 7).

**7. Lint section `== CI runs with least privilege`** in `tests/lint.sh`, before `== bash files do not use jq`, with
a comment in the style of the other sections (iteration 38, what it pins). It reads `.github/workflows/ci.yml` with
grep and awk only, assuming the block style the file uses (jobs at 2 spaces, job keys at 4); anything it cannot match
fails. Each failure is one `FAIL:` line naming the file and what is missing.

1. A line `permissions:` at column 0, the next line exactly `  contents: read`, the line after it not indented (no
   other scope); no line matches `^[[:space:]]+permissions:` (no job-level block); no line contains `: write`.
2. In the `jobs:` section every job (a line `^  [A-Za-z0-9_-]+:[[:space:]]*$`) has a line
   `^    timeout-minutes: [0-9]+$` before the next job, with a value from 1 to 360; at least one job is found.
3. The `concurrency:` block (column 0) holds exactly the two lines of decision 3, and the file has no
   `cancel-in-progress: true`.
4. For each of the three required names (written in the lint, as the ruleset names them, and compared as fixed
   strings with grep -F, since they contain parentheses and commas), the line
   `    name: <name>` exists and the line before it is the comment of decision 4; the comment occurs exactly 3 times.
5. Every line selected by `^[[:space:]]*(- )?uses:` must itself match, anchored at the line start like the selector,
   `^[[:space:]]*(- )?uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$` (grep -E), so a
   pin inside a trailing comment cannot satisfy it; each selected line that does not is one `FAIL:` line, and at
   least one selected line exists.
6. `.github/dependabot.yml` has a line `  - package-ecosystem: "github-actions"`.

The lint cannot check that a SHA exists or belongs to the release in its comment (review, with the `gh api` calls of
decision 5), that GitHub accepts the expressions, that the three names still match the ruleset (it pins the names
this spec verified), or that Dependabot runs.

## CHANGELOG

Under `Unreleased`: `- Iteration 38 (#154): CI runs with a read-only token, a timeout on every job (5 to 38
minutes), cancels superseded runs of a pull request only (every push to main gets its own result), says on each
required job name that the ruleset requires it, and pins its actions by commit SHA, kept current by Dependabot.`

## Verification

| Criterion | Checked by |
|---|---|
| 1 `permissions: contents: read` at the top | lint pin 1 |
| 2 every job has a `timeout-minutes` | lint pin 2; the numbers of decision 2 in the review of the diff |
| 3 `cancel-in-progress` for pull requests only | lint pin 3; the PR's own run (it starts, so the expressions parse) |
| 4 a comment on each required job name | lint pin 4 |
| 5 SHA pins with the version, Dependabot keeps them current | lint pins 5 and 6; the review runs the `gh api` calls of decision 5 |

`bash tests/check.sh` green on the branch. The pull request's own CI run is the only test of the workflow itself: it
must start, and the three required checks must report under their unchanged names (else auto-merge waits forever). A
hung job hitting its timeout and two pushes to `main` running side by side cannot be tested here; the first push run
after the merge shows the new group (`ci-<run id>`) in its run page.

## Not done

- No new job, action, workflow, secret, trigger or step; no `persist-credentials: false`, no job-level permissions.
- No change to the ruleset, to branch protection, to job ids or names, to `.github/dependabot.yml` (no grouping, no
  schedule change), to `tests/check.sh` or to any script, skill, agent or hook.
- No pin check for workflows other than `ci.yml` (there are none).

## Left

Nothing.
