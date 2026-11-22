# Iteration 62: the slowest tests are profiled, and the slow ones leave the per-change check

Status: delivered in iteration 62 (PR #359)

Story #340, epic #337 (fast verification loop). It builds on iteration 59 (`tests/check.sh --affected`, the per-change
check) and iteration 60 (CI on a pull request runs `--affected --within <its list>`). The three steps the issue names,
`smoke-check.ps1`, `smoke-drive.ps1` and `test-lintcopy-output.ps1`, each get a note in their file header that says
where their time goes. `smoke-check.ps1` (and its twin) is made faster with the same cases: its lint copies stop
running the agreement section's case and cost files, which the lint itself runs once (decision 3). `smoke-drive.ps1`,
`test-lintcopy-output.ps1` and `test-lintcopy-output.sh` are marked slow, and so is `smoke-check.ps1` if the faster
version still misses its budget (decision 4). A step line of the step list can end in the word `slow`. A selective
`--affected` run, with or without `--within`, leaves out every slow step and lists each one it left out. The full
check, `--only` and the fallbacks of iterations 59 and 60 still run the slow steps, so CI on a push to `main` runs them,
and so does the full check before a release. A release pull request, which always changes
`.claude-plugin/plugin.json`, falls back to every step, locally and in CI (decision 6). The lint accepts the mark, pins
the set of slow steps and their notes, and keeps the CI lists equal to the step list as today. Changes
`tests/check.sh`, `tests/lint.sh`, `tests/smoke-check.sh`, `tests/smoke-check.ps1`, `tests/smoke-drive.ps1`,
`tests/test-lintcopy-output.sh`, `tests/test-lintcopy-output.ps1`, `README.md` and `CHANGELOG.md`.

## Story trigger and manual check

**Not a story trigger.**

- *A change to the status flow or who sets a status*: no. No status and no board call changes, and no decision record
  is needed.
- *A new, renamed or removed config key*: no. The slow mark is a word on a line of the step list in `tests/check.sh`.
  It describes this repository's tests, not a project's value, so it does not belong in `.claude/nightmill.json`
  (invariant **Config-driven** holds). The schema, the example config and the README's configuration table do not
  change.
- *A change to the slot marker format*: no. No script in `scripts/` changes. **Compatible** holds: no marker or key
  changes. A full check, `--quick` and `--only` print exactly what they print today. A selective `--affected` run prints
  what it prints today whenever no selected step is slow.

**The manual check does not apply**: nothing under `skills`, `agents` or `hooks` changes. The two runs under Tests
(the CI run of the pull request and one local selective run) stand in for it.

**Not `.github/`**: `.github/workflows/ci.yml` does not change (decision 7), so `/next` may enable auto-merge as usual.

**Both shells**: no script in `scripts/` changes. `tests/check.sh` is the one runner in both shells. `tests/check.ps1`
gets no new parameter because there is no new option. `tests/smoke-check.sh` and `tests/smoke-check.ps1` get the same
new cases with the same expected text. `test-lintcopy-output.sh` gets the new count of decision 3; its `.ps1` half is
the text check that exists already (Facts).

## Facts this rests on

Read on `main` at f54da49 on 2026-11-22. That commit only adds `docs/decisions/0004-scripts-in-one-language.md` to
8f4bd9f, so the CI times of 8f4bd9f hold for it. The issue and #337 were read as handed over; #279 and #293 only
through the specs and tests that cite them (iterations 42 and 55, `tests/lint.sh`, `tests/test-lintcopy-output.sh`).
The CI logs were read with `gh run view <id> --log` (read only).

- **The measurements.** The newest green push run of `ci.yml` on `main` is 45020727310, on 8f4bd9f (every step runs
  through `--only`, four at a time per job). Its `Times:` blocks for the steps this story names, and the steps that
  bound each job:

  | Job | Step | Time | Job total |
  |---|---|---|---|
  | PowerShell part 3 | `smoke-check.ps1` | 20m32s | 20m32s (next: `smoke-validate.ps1` 8m37s) |
  | PowerShell part 2 | `smoke-drive.ps1` | 9m51s | 9m51s (next: `smoke-release.ps1` 7m07s) |
  | PowerShell part 4 | `test-lintcopy-output.ps1` | 4m48s | 4m48s (next: `smoke-load.ps1` 2m25s) |
  | PowerShell part 1 | `smoke-slot.ps1` | 11m34s | 11m34s |
  | bash | `test-lintcopy-output.sh` | 2m47s | 4m20s (next: `smoke-status.sh` 1m24s) |
  | bash | `smoke-check.sh` | 1m16s | |
  | bash | `smoke-drive.sh` | 36s | |

  The run before it, 44952977845 (on 1509b29), had `smoke-check.ps1` 16m33s, `smoke-drive.ps1` 11m14s,
  `test-lintcopy-output.ps1` 4m51s and `test-lintcopy-output.sh` 3m19s. Iteration 55 measured `smoke-check.ps1` at
  8m31s (run 43087110265). It grew with every lint case that iterations 56, 59 and 60 added (see below).
  **Measured on this machine** (one step alone, `bash tests/check.sh --only test-lintcopy-output.ps1 --jobs 1`, on
  f54da49): `-- test-lintcopy-output.ps1: ok (6m19s)`, 6m19s wall time, alone, against 4m48s in CI with three
  other steps beside it. No other step was run here, and the full check (about 1.5 hours here) was not run. The
  issue's statement that the three steps together take longer on the maintainer's machine than all other steps is
  taken as given.
- **Where the time goes, by reading the code** (the implementer measures it, decision 1):
  - `smoke-check.ps1` (747 lines) and `smoke-check.sh` (705): about 60 runs of the check against fixture steps. Each
    `.ps1` run starts `powershell.exe` for `tests/check.ps1`, which starts Git's bash for `tests/check.sh`, which starts
    a `bash -c` per fixture step. Then come **29 runs of the lint range** from `== the check runs every smoke script` to
    `== text from issues is data`, one on the unchanged copy (`lint-ok`) and 28 `lint_break` / `Lint-Break` cases. Each
    run gets a fresh copy (`mkcopy` / `Make-Copy`: every `tests/*.sh` and `*.ps1`, about 100 files, `scripts/`, `skills/`,
    `ci.yml`, the schema, the example, `README.md`, `CONTRIBUTING.md`). The range holds the sections
    `== the lists and the shell twins agree` (it starts `tests/test-lint-agreement.sh` and
    `tests/test-lint-agreement-cases.sh`, whose 17 cases build scratch trees) and `== the agreement section stays cheap`
    (`tests/test-lint-agreement-cost.sh`, which runs the agreement section once more in a scratch tree). So each copy
    also runs the agreement cases and the cost test, 29 times per run of the smoke test, while the lint step runs them
    once already. The copies set `NIGHTMILL_CI_PARTS_RULES_ONLY=1`, and the lint skips only `tests/test-ci-parts.sh`'s
    cases, `tests/test-ci-job-times.sh`, `tests/test-ci-run-steps.sh` and `tests/test-ci-job-name-rule.sh` under it
    (bug #293). `tests/test-lint-agreement-cost.sh` says that a run of the cases file "costs 3.9 s here", 13 times one
    run of the rule file.
  - `smoke-drive.ps1` (596 lines): 35 cases. Each case builds a throwaway bare `origin` and a clone (about 10 `git`
    processes) and starts `scripts/drive.ps1` in a child `powershell.exe`. The driver starts its siblings as processes
    (`slot.ps1 -Reap`, `slot.ps1 -Status -Porcelain`, `room.ps1`, `gate.ps1` before every step, `history.ps1`). Every
    call of the fake `gh` and the fake `claude` is a `.cmd` file that starts `powershell.exe` once more. The time is
    Windows PowerShell process starts, and starting those processes is the driver's own design under test.
    `smoke-drive.sh` runs the same cases with bash fakes in 36 s.
  - `test-lintcopy-output.ps1` (39 lines): one `robocopy` of the repository, then a whole run of the copy's
    `tests/smoke-release.ps1` (7m07s as a step of its own). That run does every release case and a second `robocopy`
    before it reaches the lint-on-a-copy case, which runs the whole lint in Git Bash and fails, as the test wants.
    `test-lintcopy-output.sh` (139 lines) runs, in turn, whole copies of `smoke-status.sh` and `smoke-release.sh`, then
    `test-spec-template.sh` under a `bash` shim (#280), `test-ci-parts.sh` and the whole of `smoke-check.sh` under a `cp`
    shim (#293). Those are five steps that the check also runs on their own.
- **The step list** (`# steps: begin` to `# steps: end`): lines `add <kind> <name>[ first]`. The lint checks them
  against `^add (lint|bash|ps) [A-Za-z0-9._-]+( first)?$`, in `== the check runs every smoke script`, inside the range
  that `tests/smoke-check.*` cut out. `== the check starts the longest steps first` (outside that range) extracts the
  lines matching `/ first$/` and compares them with `want_firsts`. `tests/smoke-check.*`
  (`== the slowest steps of the real list start first`) matches `add <kind> <name> first` as whole lines. A fixture line
  of `NIGHTMILL_CHECK_STEPS` has up to five tab-separated fields, the fifth being `first` or empty.
- **The modes.** `--affected` selective (iteration 59 decision 6; `<k>` counts the selected steps, skipped ones
  included); its fallbacks: the full check (59 decision 5) and, with `--within`, `--only <list>` (60 decision 2 rule 3).
  `--summary` with `--within` writes the `Selection:` section (60 decision 6). CI: a pull request runs
  `$CHECK_SELECT` = `--affected --within <list>` and a push `--only <list>`. The map pins five `shared`/`lintonly` lines
  (59 decision 7 rule 6, 60 decision 7). `.claude-plugin/plugin.json` maps to the release tests and, through
  `map .claude-plugin/*`, to the two `claude` steps.
- **Releases.** `scripts/release.sh` and `scripts/release.ps1` do not run the check, contrary to the issue's agent
  notes: they bump `plugin.json`, cut `CHANGELOG.md`, update the README's `Version` line and open the release pull request,
  or tag after its merge (decision 0002). "The full check still runs before a release" is a rule of the workflow skill
  (iteration 59 decision 8), followed by hand. Today the release pull request's CI is selective, because it changes
  `plugin.json`, `CHANGELOG.md` and `README.md`, none of them `shared`.
- **Decisions.** 0001: "The check command runs what the machine can run and lists what it skipped; CI is the full
  run." 0004 is proposed (bash only) and changes nothing yet.

## Decisions

**1. The profiled steps and their notes.** The profiled steps are the three the issue names: `smoke-check.ps1`,
`smoke-drive.ps1` and `test-lintcopy-output.ps1`. They are the steps of this machine's `Times:` block, which on
`verification.platform` `windows` holds only the `ps` steps. Every step marked slow (decision 4) is also profiled. Each
profiled step's file gets, among the comment lines at its top (before its first line that does not start with `#`), one
paragraph that begins `# Time: `. The paragraph says in words and counts, never in seconds, where the step's time goes:
how many copies of the repository it makes, how many runs of the lint or of the check it nests, and how many processes
of which kind it starts per case. Its last sentence says either `Marked slow (iteration 62).` or
`Made faster in iteration 62: <what changed>.` The seconds go into the pull request. The implementer measures them by
timing the parts of each step on this machine and in CI, for example with timestamps printed around each part in an
uncommitted copy. The pull request gives one line per part with its share of the step's time, and the note must agree
with that line.

**2. The mark: the word `slow` at the end of a step line.** The line format becomes `add <kind> <name>[ first][ slow]`,
in that order: `add ps smoke-drive.ps1 first slow`. The `add` function takes the words after the name in any of the
three forms `first`, `slow` and `first slow`; any other word is the malformed list. For the tests,
`NIGHTMILL_CHECK_STEPS` gets a sixth field, `slow` or empty. Any other value gives
`check: <file>: the sixth field is slow or empty, not <x>` on standard error and exit 2, as the fifth field does today.
The header comment of `tests/check.sh` names the mark and the field. A step of kind `lint` or `claude` is never slow.

**3. `smoke-check.ps1` and `smoke-check.sh` are made faster, with the same cases.** In `tests/lint.sh`, the two calls
`bash tests/test-lint-agreement-cases.sh "$PWD" || fail=1` (section `== the lists and the shell twins agree`) and
`bash tests/test-lint-agreement-cost.sh "$PWD" || fail=1` (section `== the agreement section stays cheap`) each get the
guard that the CI-parts tests have: `[ "${NIGHTMILL_CI_PARTS_RULES_ONLY:-}" = 1 ] || ...`. The rule file
`tests/test-lint-agreement.sh` still runs on every copy. So the 29 lint copies of each smoke-check file check the
agreement rules and no longer run the agreement cases and the cost test. The lint step runs both once, as today. The
comment above each guard names #340 and says that the lint copies of `tests/smoke-check.sh`/`.ps1` check the rules
only. No case is removed, moved or changed; the cases of `tests/smoke-check.*` stay the same 29 lint runs with the
same expected texts. The variable keeps its name; its meaning, "a lint copy checks the rules only; the case files run
once, in the lint", was already wider than the CI parts (the job-times, run-steps and job-name tests use it). Nothing
else in the smoke-check files changes for speed: the copies stay one per case.

**4. The slow steps.** The steps marked slow are:

| Step | Why slow |
|---|---|
| `smoke-drive.ps1` | Its time is the Windows PowerShell process starts of the driver and its fakes (Facts), which are the driver's own behaviour under test. Removing them would mean fakes in another language or fewer cases, and the issue rules out both. |
| `test-lintcopy-output.ps1` | It nests a whole run of `smoke-release.ps1`, a step the check runs anyway, to reach one case. |
| `test-lintcopy-output.sh` | The same cause: it nests whole runs of `smoke-status.sh`, `smoke-release.sh`, `test-spec-template.sh`, `test-ci-parts.sh` and `smoke-check.sh`. It is the slowest step of the bash job (2m47s of 4m20s). |

`smoke-check.ps1` is marked slow as well when, after decision 3, its time in the `Times:` block of PowerShell part 3
in the CI run of this story's pull request is more than **5m00s**. That run executes every step, because the pull
request changes the shared `tests/check.sh` (decision 6 of iteration 60). 5m00s is a quarter of the 20m32s it took
before, and it is below `smoke-validate.ps1` (8m37s), so the step no longer bounds part 3. If the time is over the
budget, the implementer adds the mark, adds the step to `want_slows` (decision 8) and changes its note's last sentence
in the same pull request. The pull request then says which way it went. `smoke-check.sh` (1m16s), `smoke-drive.sh`
(36s) and every other step stay unmarked. With the marks the lines read `add ps smoke-drive.ps1 first slow`,
`add ps test-lintcopy-output.ps1 first slow` and `add bash test-lintcopy-output.sh slow`. The `first` marks do not
change.

**5. Where a slow step runs.**

1. **A selective `--affected` run** leaves out every selected step that is marked slow. That holds with and without
   `--within`, whatever `verification.platform` says, and even when its own file or its script changed. A left-out
   step does not run, is not counted in `<k>` of the first and last line (iteration 59 decision 6; with `--within` the
   steps of the list, iteration 60 decision 2 rule 2), and has no section and no line in the `Times:` block. A slow
   step that also carries a skip reason (no PowerShell) is listed as left out, not as `SKIPPED:`.
2. **Everything else runs slow steps as it runs any step.** That covers the full check (`tests/check.sh` with no mode),
   `--only` naming them, the fallback of `--affected` to the full check (iteration 59 decision 5) and the fallback of
   `--within` to `--only <list>` (iteration 60 decision 2 rule 3). So CI on a push to `main` (`--only`) runs every slow
   step, and so does the full check before a release. A pull request that falls back (a `shared` or unknown path) runs
   them too.
3. `--quick` does not change. It still runs the lint and every `bash` step, `test-lintcopy-output.sh` included.

**6. Before a release: `shared .claude-plugin/plugin.json`.** The map gets the line `shared .claude-plugin/plugin.json`
after `shared .github/workflows/*`. A release pull request always changes that file (the version bump of decision
0002), so its CI runs every step of every list (iteration 60 decision 2 rule 3), slow ones included, and a local
`--affected` on the release branch runs the full check. Lint rule 6 of iteration 59 (the pinned lines) gets this sixth
line. The existing `map .claude-plugin/plugin.json ...` line stays; `shared` wins (iteration 59 decision 3).
`scripts/release.*` do not change.

**7. CI does not change.** The `--only` lists of `ci.yml` keep naming every step, the slow ones included, so a push to
`main` runs them. On a pull request, `--affected --within` leaves them out by decision 5. The lint rules that keep the
lists equal to the step list (iteration 42 decision 11 rule 6, iteration 55 decision 5, iteration 60 decision 8) stay
as they are; the parts, the timeouts and the job names stay.

**8. The lint.** In `== the check runs every smoke script` (inside the range that `tests/smoke-check.*` cut out):

1. The step-list pattern becomes `^add (lint|bash|ps) [A-Za-z0-9._-]+( first)?( slow)?$`. The text on a miss is today's
   `the step list ... is missing or malformed`.
2. The steps marked slow, as `<kind> <name>` in list order, are exactly
   `want_slows="bash test-lintcopy-output.sh|ps test-lintcopy-output.ps1|ps smoke-drive.ps1|"` (list order; when
   decision 4 marks `smoke-check.ps1`, `ps smoke-check.ps1|` goes before `ps test-lintcopy-output.ps1|`). Otherwise:
   `FAIL: tests/check.sh: the steps marked slow are not exactly the slow steps (docs/specs/iteration-62-slow-tests-out-of-check.md, decision 4): <got>`.
   A `lint` line with `slow` fails this rule too.
3. Each profiled step of decision 1 (`tests/smoke-check.ps1`, `tests/smoke-drive.ps1`, `tests/test-lintcopy-output.ps1`
   and every step marked slow) has a line that begins `# Time: ` among the lines at its top that begin with `#`.
   Otherwise: `FAIL: tests/<name> has no '# Time: ' note in its header (docs/specs/iteration-62-slow-tests-out-of-check.md, decision 1)`.
   It is one `awk` pass per file, with no process per line (bug #270).

In `== the check starts the longest steps first`, the extraction becomes `/ first( slow)?$/` with a trailing ` slow`
removed before the compare, so `want_firsts` and its text stay as they are. In `== every script and every test step is
in the map`, rule 6 checks the line of decision 6 too.

**9. The output of a selective run.** After the `SKIPPED:` lines and before the verdict, there is one line per
left-out step, in list order:

```
LEFT OUT: <name> (a slow step; the full check and CI on the base branch run it)
```

The `affected: <path> -> <steps>` lines do not change; they still name a slow step that the path selects. The first
line and the verdict keep their form, with `<k>` as in decision 5. With `--summary` and `--within`, when at least one
step of the list was left out as slow (`<s>` of them), the `Selection:` sentence of iteration 60 decision 6 becomes
`Selection: --affected against <ref>: <k> of <n> steps ran, <n-k> left out (<s> slow, <n-k-s> selected by no changed path).`
After the `Left out:` line comes the line `Slow steps left out: <names> (a push to the base branch runs them).` (each
name in backticks, comma-separated, in list order). With `<s>` = 0 the section is exactly iteration 60's. A plain
`--affected` run writes no selection section, as today.

**10. The README.** Under `## Developing nightmill`, after the sentence on `--affected`: "A step marked `slow` in the
step list of `tests/check.sh` does not run in a selective `--affected` run, which lists it as `LEFT OUT:`. The full
check, `--only` and CI on a push to `main` run it, and a release pull request runs every step (it changes
`.claude-plugin/plugin.json`)."

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | For each of the slowest steps of the check's `Times:` block a short note says where the time goes | Decision 1 (the `# Time: ` note, the measurements in the pull request); decision 8 rule 3; Facts (the reading it starts from) |
| 2 | Each of them is either made faster with the same cases, or marked as a slow step | Decision 3 (`smoke-check.*` faster), decision 4 (the three marked slow, and the 5m00s budget for `smoke-check.ps1`) |
| 3 | Slow steps do not run in the per-change check; they run in CI on the base branch and before a release, and the check lists them as left out | Decision 5 (where they run), decision 6 (the release pull request), decision 7 (CI on push), decision 9 (`LEFT OUT:` and the summary) |
| 4 | A step is marked slow in the step list itself, and the lint keeps the list and CI in step as today | Decision 2 (the mark), decision 7 (the CI lists unchanged), decision 8 (rules 1 and 2, the `first` extraction) |
| 5 | No case is dropped without a line in the pull request saying which and why | Decision 3 (no case removed); Tests (the pull request's `Cases dropped:` line) |

## Tests

**`tests/smoke-check.sh` and `tests/smoke-check.ps1`**, in the case `== affected`, with its fixture steps (`l`, `b1`,
`b2`, `p1`, `p2`, `c`), its map, `NIGHTMILL_CHECK_PATHS` and `--jobs 1`. A variant of the steps file gives `p1` the
sixth field `slow`; the `.ps1` builds the same file.

- Criterion 3, selective: the path `scripts/foo.ps1` gives the log `l`, `b1`, the first line
  `check: AFFECTED, 1 at a time (--jobs 1): 2 of 6 steps, changed paths: 1 (against NIGHTMILL_CHECK_PATHS); the full check does not run`,
  the line `affected: scripts/foo.ps1 -> b1,p1`, the line
  `LEFT OUT: p1 (a slow step; the full check and CI on the base branch run it)`, no `== p1` section and no `p1` in the
  `Times:` block, and the last line
  `AFFECTED CHECK PASSED (2 of 6 steps, changed paths: 1; the full check has not run)`, exit 0. The same run with `p1`
  also given the reason `no pwsh here` prints the `LEFT OUT:` line and no `SKIPPED: no pwsh here`.
- Criterion 3, with `--within b1,p1`: the log `b1`, `1 of 2 steps`, the `LEFT OUT:` line, and with `--summary` the lines
  ``Selection: --affected against NIGHTMILL_CHECK_PATHS: 1 of 2 steps ran, 1 left out (1 slow, 0 selected by no changed path).``
  and ``Slow steps left out: `p1` (a push to the base branch runs them).``. The iteration 60 summary cases keep their
  expected text (no slow step).
- Criterion 3, where slow steps run: `--only p1` gives the log `p1`. The full check (no mode) gives the log of every
  step, `p1` included, and no `LEFT OUT:` line. The fallback `scripts/lib/x.sh` with `--affected` runs `p1` (the full
  check). With `--affected --within b2,p1` it gives `check: only b2,p1, ...` and the log `b2`, `p1`. No run prints
  `LEFT OUT:` unless it is a selective `--affected` run.
- Decision 2, usage: a fixture line whose sixth field is `fast` gives
  `check: <file>: the sixth field is slow or empty, not fast` on standard error, exit 2, and an empty log.
- `== the slowest steps of the real list start first`: a trailing ` slow` is removed from the real list's lines before
  the whole-line match, so the eight `first` steps are still found.

**The lint** (criteria 1 and 4; decision 8), as `lint_break` / `Lint-Break` cases in both files, with the same expected
text. `slowformat` turns `add ps smoke-drive.ps1 first slow` into `add ps smoke-drive.ps1 slow first` and expects
`the step list between '# steps: begin' and '# steps: end' is missing or malformed`. `slowset` removes ` slow` from
that line and expects `the steps marked slow are not exactly the slow steps`. `slownote` deletes the `# Time: ` line(s)
of `tests/smoke-drive.ps1` in the copy and expects `tests/smoke-drive.ps1 has no '# Time: ' note in its header`.
`mapplugin` removes `shared .claude-plugin/plugin.json` and expects
`the map does not have the line shared .claude-plugin/plugin.json`. The `lint-ok` copy stays free of any `FAIL`.

**`tests/test-lintcopy-output.sh`** (criterion 2, decision 3; counted, not timed, as for #293). The `cp` shim run of
`tests/smoke-check.sh` gets a second shim in the same folder, named `bash`. It logs every call whose first argument
ends in `tests/test-lint-agreement-cases.sh` or `tests/test-lint-agreement-cost.sh` and passes every call to the real
bash unchanged. Control: `bash tests/test-lint-agreement-cases.sh "$here"` run through the shim logs exactly 1 call,
else `FAIL: the bash shim logged <n> calls of one direct run, so the count proves nothing`. Bound: the smoke-check.sh
run logs 0 calls, else
`FAIL: tests/smoke-check.sh starts the agreement cases or cost test <n> times on its lint copies; 0 expected (the lint runs them once, #340)`.
The `.ps1` half is the existing text check that `tests/smoke-check.ps1` exports `NIGHTMILL_CI_PARTS_RULES_ONLY=1` in
its `run-section.sh`; it covers the same cause.

**The pull request** (criteria 1, 2 and 5; the issue's Verification):

- the `Times:` block before (run 45020727310, Facts) and after: the blocks of every job of the pull request's CI run
  (a fallback, so every step runs), with `smoke-check.ps1` against its 5m00s budget and the way decision 4 went;
- per profiled step, the parts and their share of its time on this machine and in CI (decision 1);
- the first line, the `LEFT OUT:` lines and the last line of one local selective run, made with
  `NIGHTMILL_CHECK_PATHS` holding `scripts/drive.ps1` on this repository: it runs `smoke-drive.sh` and the other tests
  of the driver, and it lists `LEFT OUT: smoke-drive.ps1 (...)`;
- a line `Cases dropped: none`, or one line per dropped case naming it and why.

**The full check on the branch**: `bash tests/check.sh` is green.

## Files touched

- `tests/check.sh`: the `slow` word in `add` and in the step list (decisions 2, 4), the sixth fixture field, the
  selection of decision 5, the `LEFT OUT:` lines and the summary lines (decision 9), the map line (decision 6), the header
  comment.
- `tests/lint.sh`: the two guards (decision 3), the rules of decision 8, the sixth pinned map line.
- `tests/smoke-check.sh`, `tests/smoke-check.ps1`: the cases under Tests, the real-list match, the four lint cases.
- `tests/smoke-drive.ps1`, `tests/test-lintcopy-output.ps1`, `tests/test-lintcopy-output.sh`, `tests/smoke-check.ps1`:
  the `# Time: ` notes (decision 1).
- `tests/test-lintcopy-output.sh`: the agreement count.
- `README.md`: decision 10.
- `CHANGELOG.md`, one bullet under `Unreleased`:

  ```
  - Iteration 62 (#340): the slowest tests are profiled and the slow ones leave the per-change check. A step line of
    tests/check.sh can end in slow; a selective --affected run (with or without --within) leaves every slow step out
    and lists it as LEFT OUT, while the full check, --only, the fallbacks and CI on a push to main still run it, and a
    release pull request runs every step (shared .claude-plugin/plugin.json). smoke-drive.ps1 and
    test-lintcopy-output.sh/.ps1 are slow; smoke-check.sh/.ps1 no longer run the agreement cases on each lint copy.
    Each profiled test says in its header where its time goes. No config key.
  ```

Not touched: `.github/workflows/ci.yml`, `tests/check.ps1`, every script in `scripts/` (`release.*` included), every
skill, the schema, the example config, `CONTRIBUTING.md`.

## Risks

- **A change that breaks a slow step merges green.** A pull request that changes `scripts/drive.ps1` no longer runs
  `smoke-drive.ps1`, locally or in CI, unless it falls back. The push to `main` then goes red after the merge. The
  `LEFT OUT:` line names the step, and `--only <step>` runs it on demand. That is the trade the issue asks for (see
  Left).
- **`smoke-check.ps1` misses its budget.** Then it is marked slow too (decision 4). That is the issue's other branch,
  and a change to `README.md`, which selects it, no longer waits for it.
- **The guard hides a broken agreement case** in the copies only. The lint step still runs every agreement case and the
  cost test once, so a broken case still fails the check.
- **Slow steps grow unnoticed**, because only the push to `main` runs them. The summary of every push run lists the
  five slowest steps (iteration 55), and the epic's time budget is a story of its own.

## Size estimate

`M`: about 260 changed lines. `tests/check.sh` about 45, `tests/lint.sh` about 30, the two smoke-check files about 70
each, `tests/test-lintcopy-output.sh` about 25, the four `# Time: ` notes about 20, README about 4, CHANGELOG about 7.

## Not done

- No test rewritten in another language (out of scope), no case removed, and no fake of `smoke-drive.ps1` replaced.
- No other step profiled or marked: `smoke-slot.ps1` (11m34s), `smoke-validate.ps1` (8m37s) and `smoke-release.ps1`
  (7m07s) are longer in CI than `test-lintcopy-output.ps1`, but the issue names only the three. `smoke-release.ps1` and
  `smoke-validate.ps1` also run the whole lint on a copy without the guard of decision 3.
- No change to `--quick`, `--only`, the full check, `verification.platform`, the `first` marks or the CI parts and
  timeouts.
- No change to `scripts/release.*`, to the workflow or check skills, or to `/next` and `/fix`.
- No option or config key to run the slow steps in a selective run.
- No time budget for the loop as a whole (the epic lists it as its own item).

## Left

- **Slow steps whose own code changed.** Criterion 3 says slow steps do not run in the per-change check, so decision 5
  leaves a slow step out even when a changed path is its script or its own test file. The other reading, run a slow
  step when a changed path selects it and leave it out otherwise, would test a driver change before the merge, but a
  change to `README.md` would still pay for `smoke-check.ps1`. The maintainer may choose it.
- **The release runs the full check.** The issue's agent notes say that `scripts/release.*` run the full check; they
  do not (Facts). Decision 6 makes the release pull request's CI run every step instead and leaves the scripts alone.
  If the maintainer wants the script to run `tests/check.sh` itself, that is a change to `scripts/` in both shells and
  belongs in a story of its own.
- **The per-change check of `/next` and `/fix`.** Their prompts still tell the implementer and the fixer to run the
  check (iteration 59, Left), which is the full check and runs the slow steps. Only the affected check and CI on a pull
  request leave them out until those prompts name `--affected`.
