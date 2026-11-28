# Iteration 75: a new test needs no line in the map of tests/check.sh

Status: draft, awaiting approval (#405)

Story #405, epic #337 (fast verification loop): the rest of #343, criterion 3, which iteration 70 met only in part
(decision 11 of `docs/specs/iteration-70-ci-step-lists-generated.md`, PR #404). After this iteration a bash step that no
map line names gets a default place in `--affected`: every changed path that does not make the run the full check
selects it (decision 1). Map rule 3 of `tests/lint.sh` ("every bash step is named by a map line") is replaced by a rule
for the steps that have no default, the two claude steps (decision 3). A pull request that adds a test then adds the
test file and one line in the step list, and nothing else in `tests/check.sh` or `tests/lint.sh`. The map's lines stay
as they are. Changes `tests/check.sh`, `tests/lint.sh`, `tests/smoke-check.sh`, `README.md` and `CHANGELOG.md`.

## Story trigger and manual check

**Not a story trigger.** No status changes, no rule on who sets one changes, and no decision record is needed. No config
key is added, renamed or removed: the map is this repository's test layout and stays in `tests/check.sh` (iteration 59,
decision 3). No file under `scripts/` changes, so the slot marker format stays the same. **Compatible** holds: a project
reads nothing that changes.

**The manual check does not apply.** Nothing under `skills`, `agents` or `hooks` changes. **Shells**: bash only
(decision record 0004). No `.ps1` file is added or changed. The steps involved are the lint and
`tests/smoke-check.sh`, both under the shared path `tests/check.sh`, so the full check runs on the pull request.

## Facts this rests on

Read on `spec/75-map-default` at a2e55fd (equal to `main`) on 2026-11-28.

- The step list of `tests/check.sh` has `add lint lint` and 49 `add bash` lines. The two claude steps are added in code
  after the list. The map (`# affects: begin` to `# affects: end`) has 68 `map` lines, 5 `shared` lines and 1
  `lintonly` line. Every bash step and both claude steps are named by at least one `map` line today.
- How a path selects steps today (iteration 59, decision 4, as the code does it): a `shared` match makes the run the
  full check. Otherwise the path selects the steps of every matching `map` line, plus `<s>` when the path is
  `tests/<s>`. When that is nothing, a `lintonly` match selects the lint alone, and no match makes the run the full
  check (`<path> is in no line of the map`). So today a step that no map line names is selected only by its own path,
  by a shared path, by a path in no line of the map and by a missing merge base. A change to the script it tests does
  not select it. Map rule 3 exists so that no real step is in that state.
- The fixtures of `tests/smoke-check.sh` already have such steps. In the `== affected` fixture map, `p2` (bash) and `c`
  (claude) are named by no line, and the cases expect `docs/specs/x.md` to run the lint alone and `scripts/foo.sh` to
  run `l,b1`. In the `--affected --within @gitbash-3` case of the groups fixture, `b` and `g` are named by no line, and
  the case expects `d` alone.
- A new `tests/test-*.sh` today changes three places outside the test: its step line, a `map` line, and the README
  sentence "so a new test is one line there (and one line in the map of `tests/check.sh`)". Its path matches
  `map tests/*.sh ...`, so a change to the test itself never makes the run the full check.
- Lint rules 4 and 4b (every script and every file under `tests/fixtures/` is placed by the map) use `aff_select`, which
  reads `map` and `shared` lines only.

## Decisions

**1. The default: a bash step that no map line names is selected by every path of a selective run.** A step is
*named* when its name is in the step list of at least one `map` line of the map in use (its own path, rule 2 of
iteration 59 decision 4, does not name it). Decision 4 of iteration 59 gains one rule, applied per path after its
rules 1 to 4:

- 5\. When rules 1 to 4 did not make the run the full check, the path also selects every bash step that is not named.

Rules 3 and 4 are judged on what rule 2 selected, before rule 5. So a path in no line of the map still makes the run
the full check, and a path that only a `lintonly` line matches is not "in no line of the map" either (it selects the
lint and the unnamed steps). A `shared` path still wins. With no changed path the run is still the lint alone. `--within`
and the `slow` mark apply to an unnamed step as to any selected step (iterations 60 and 62). The `affected: <path> ->`
line and the summary table list the unnamed steps among the path's steps, in list order; "the lint only" is printed
only when the path selects no step at all. A lint step and a claude step get no default.

*Why*: before this iteration a new test had a map line, and that line could name any path (a script, a skill, a
fixture, even a path under `docs/`). The only rule that selects a step without a line, everywhere any line could have
selected it, is every path of a selective run. A step that the map names keeps its selection exactly. *Rejected*:
dropping rule 3 with no default (a change to the script a new test reads would no longer run it, so fewer steps);
treating an unnamed step as shared (every pull request runs the full check while one exists); a default from the
test's name or from the paths its file names (a guess, and the map's content is out of scope).

**2. What "wherever it was before" means here.** For every set of changed paths:

- (a) whether the run is selective or the full check, and the reason of the full check, are what they are today with
  the same map;
- (b) every named step is selected exactly where it is selected today;
- (c) an unnamed bash step is selected in every selective run that has at least one changed path, so it runs in every
  run where any map line naming it could have selected it (a superset). A path that such a line would have matched and
  that is in no other line makes the run the full check, which runs it too.

So naming a step (adding a map line) never adds a run of it, only removes some: the line is optional, for the cost.

**3. Map rule 3 is replaced.** New rule 3 in `== every script and every step is placed by the map` (the section's new
header): every step that is neither the lint nor a bash step (today `claude plugin validate` and `claude plugin test`)
is named by at least one `map` line. Otherwise the text stays `FAIL: tests/check.sh: no path maps to the step <x>`.
*Why*: such a step has no default, so without a line it would run only in the full check and the fallbacks: that is the
step the check cannot place. A bash step is always placed (by its lines or by decision 1), so no rule is needed for it.
Rules 1, 2, 4, 4b and 6 stay; rule 4 and 4b still count `map` and `shared` lines only (decision 1 places steps, not
paths).

**4. The existing fixtures keep their expectations.** The fixture map of `== affected` gets the line
`map tests/fixtures/p2/* p2`, and the groups map gets `map x/other b,c,e,f,g`, so each of their bash steps is named
and every existing case keeps its expected steps and lines. The new cases (Tests) use a map with an unnamed step.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | A pull request that adds a test file and its step line changes no other line of `tests/check.sh` or `tests/lint.sh` | Decision 1 (an unnamed bash step is placed by the default) and decision 3 (no lint rule asks a bash step for a map line); Tests, criterion 1 |
| 2 | A step that no map line names is still selected by the affected check wherever it was before, so the check does not run fewer steps than it should | Decisions 1 and 2: rule 5 runs after the full-check rules, a named step is selected exactly as today, an unnamed one in every selective run with a changed path |
| 3 | The lint still fails on a step the check cannot place | Decision 3: new rule 3 for the steps with no default (the claude steps), with the text of the old rule; its removal for bash steps is justified there |

## Tests

All in `tests/smoke-check.sh`, by behaviour (the steps that run and the lines the check prints), with fixture steps
(`NIGHTMILL_CHECK_STEPS`), maps (`NIGHTMILL_CHECK_MAP`) and paths (`NIGHTMILL_CHECK_PATHS`), and lint copies
(`mkcopy`, `lint_in`, `lint_break`). The old `mapstep` case goes (it asserts the rule decision 3 removes).

- Criterion 1: `mapnew` (lint copy): in a copy, write `tests/test-zz-new.sh` (`#!/usr/bin/env bash`,
  `set -euo pipefail`, `exit 0`) and insert `add bash test-zz-new.sh` before `# steps: end`. Asserts that
  `diff` of the copy's `tests/check.sh` against the repository's shows exactly one added line and no other change, that
  `tests/lint.sh` is unchanged, and that the section passes with no `FAIL` line. `mapunnamed` (lint copy): delete every
  map entry of `smoke-hook.sh` (the old `mapstep` sed); the section passes with no `FAIL` line.
- Criterion 2: the section `== affected: a step no map line names`, on the six steps of `mk_aff` with the map
  `map scripts/foo.* b1,p1`, `map templates/t.md b2`, `shared scripts/lib/*`, `lintonly docs/*` (`p2` and `c` unnamed):
  - `scripts/foo.sh`: runs `l,b1,p1,p2`; first line `4 of 6 steps`; `affected: scripts/foo.sh -> b1,p1,p2`; last line
    `AFFECTED CHECK PASSED (4 of 6 steps, changed paths: 1; the full check has not run)`; `c` does not run.
  - `docs/specs/x.md`: runs `l,p2`; `affected: docs/specs/x.md -> p2`.
  - `tests/p2`: runs `l,p2`.
  - `other/thing`: first line `check: AFFECTED: other/thing is in no line of the map; running the full check`, every
    step runs (the default does not hide an unknown path).
  - `scripts/lib/x.sh`: the full check with the shared reason; no changed path: the lint alone.
  - `--within b1,b2` with `scripts/foo.sh`: runs `b1`; `--within b1,p2`: runs `b1,p2`, and the line is
    `affected: scripts/foo.sh -> b1,p2`.
  - slow: with `mk_aff_slow` (p1 slow) and the map `map templates/t.md b2`, `lintonly docs/*`, the path
    `templates/t.md` runs `l,b1,b2,p2` and prints the `LEFT OUT: p1` line.
  - the superset (decision 2): for each path set `scripts/foo.sh`, `templates/t.md`, `docs/specs/x.md`, `tests/p2`,
    `tests/fixtures/p2/a`, `other/thing`, `scripts/lib/x.sh`, `scripts/foo.sh` with `docs/a.md`, and none, run once with
    the map above plus `map tests/fixtures/p2/* p2` (p2 named) and once without it. Asserts that every step of the
    named run also runs in the unnamed run, that the two runs are the same except for `p2`, and that both are selective
    or both full with the same first line, for every path set but `tests/fixtures/p2/a`.
  - every existing `== affected`, `--within`, summary, slow and groups case passes unchanged with the maps of
    decision 4.
- Criterion 3: `mapclaude` (lint_break): `/^map /s/,claude plugin test//g` on `tests/check.sh`; expects
  `no path maps to the step claude plugin test`. The `mapname`, `mapscript`, `mapfixture` and `mapshared` cases stay.

No manual check (no skill, agent or hook changes). `bash tests/check.sh` and `bash tests/lint.sh` pass.

## Files touched

- `tests/check.sh`: decision 1 (a step is named or not, read from the map in use; rule 5 after the full-check rules,
  in the `--affected` loop), the header comment of `--affected` and the comment above the map (a step no map line
  names runs in every selective run; a map line narrows it). The step list and the map's lines do not change.
- `tests/lint.sh`: decision 3 (new rule 3 for the claude steps, the old loop over bash steps removed), the section header
  `== every script and every step is placed by the map` and its comment.
- `tests/smoke-check.sh`: the cases under Tests; the two fixture map lines of decision 4; `mapstep` removed.
- `README.md`: "so a new test is one line there (and one line in the map of `tests/check.sh`)" becomes "so a new test is
  one line there; a test that no map line names runs in every selective `--affected` run, and a map line in
  `tests/check.sh` makes it run only for the paths it names".
- `CHANGELOG.md`, under `Unreleased`:
  `- Iteration 75 (#405): a new test needs no line in the map of tests/check.sh: a bash step that no map line names runs in every selective --affected run, and the lint asks a map line only of the claude steps.`

## Risks

- **Cost**: an unnamed test runs in every selective run, docs-only pull requests included, in its CI part. It is safe
  (more steps, never fewer) and visible in the `affected:` lines; a later pull request may add its map line. Today no
  real step is unnamed, so the output of the check does not change.
- **The full-check fallback**: if rule 5 ran before rules 3 and 4, an unknown path would select the unnamed steps and
  stop making the run full, so fewer steps would run. The `other/thing` case and the superset loop catch that order.
- **A fixture directory of a new test** under `tests/fixtures/` still needs a map line (rule 4b, bug #379); that is a
  path, not a step, and stays.

## Size estimate

M: about 25 lines in `tests/check.sh`, 15 in `tests/lint.sh`, 80 in `tests/smoke-check.sh`, 2 in `README.md` and 2 in
`CHANGELOG.md`, about 125 changed lines.

## Not done

- No map line is added, removed or narrowed, and no existing step loses its lines (the map's content is out of scope).
- The step list, its marks and the CI groups do not change (iteration 70); the slow steps and their mark do not change.
- No default for a claude step or the lint, and no default for a path (rules 4 and 4b and the fallback for a path in
  no line of the map stay).
- A new `tests/smoke-*.sh` still gets its README line (iteration 51) and a new fixture directory its map line (rule 4b);
  the criterion is about `tests/check.sh` and `tests/lint.sh`, and its test adds a `tests/test-*.sh`.
- `--affected` does not read a test file to guess the paths it names.

## Left

- Criterion 2's "wherever it was before" has two readings. Read on the code, an unnamed step today is selected only by
  its own path and the fallbacks; keeping exactly that would let a change to the script a new test reads skip the test,
  against "does not run fewer steps than it should" and the goal. This spec reads it as "everywhere a map line naming
  it could have selected it" and keeps the named steps exact (decision 2). The maintainer confirms the reading at
  approval.
