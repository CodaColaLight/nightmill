# Iteration 59: the check runs only the steps a change affects

Status: delivered in iteration 59 (PR #352)

Story #338, epic #337 (fast verification loop). `tests/check.sh` gains a mode, `--affected` (PowerShell `-Affected`),
that lists the paths changed against `origin/<git.baseBranch>`, maps each one to test steps through one map in
`tests/check.sh`, and runs the lint plus exactly those steps. Under that mode a changed script runs its tests in both
shells whatever `verification.platform` says. A change only under `docs/` runs the lint alone. A change to a shared
file (the libraries, the check itself), or to a path the map does not know, runs the full check instead. The lint
fails on a test step that no map line names and on a script that maps to no step. The workflow skill and the check
skill say where the affected check is enough (before a commit, in a fix round) and where the full check still runs
(CI on the base branch, before a release). Changes `tests/check.sh`, `tests/check.ps1`, `tests/smoke-check.sh`,
`tests/smoke-check.ps1`, `tests/lint.sh`, `skills/workflow/SKILL.md`, `skills/check/SKILL.md`, `README.md` and
`CHANGELOG.md`.

## Story trigger and manual check

**Not a story trigger.**

- *A change to the status flow or who sets a status*: no. No status and no board call changes, and no decision record
  is needed.
- *A new, renamed or removed config key*: no. The mode reads `git.baseBranch`, which already exists (default `main`).
  The map is this repository's test layout, not a project's value, so it lives in `tests/check.sh` and not in
  `.claude/nightmill.json` (decision 3; invariant **Config-driven** holds). The schema, the example config and the
  README's configuration table do not change.
- *A change to the slot marker format*: no. No script in `scripts/` changes. **Compatible** holds: no marker or key
  changes, and `tests/check.sh` without `--affected` prints exactly what it prints today.

**The manual check applies**: `skills` is in `verification.manualCheckPaths`, and `skills/workflow/SKILL.md` and
`skills/check/SKILL.md` change. Its steps are under Tests. Nothing under `agents` or `hooks` changes.

**Both shells**: no script in `scripts/` changes. `tests/check.sh` is the one runner in both shells, and
`tests/check.ps1` passes `-Affected` on as `--affected` (iteration 42 decision 8). `tests/smoke-check.sh` and
`tests/smoke-check.ps1` get the same new case and the same lint cases, with the same expected text.

**Hot file**: `skills/workflow/SKILL.md` is in `parallel.hotFiles`, so this story is not paired with another story
that changes it.

## Facts this rests on

Read on `main` at 81b05cf.

- The step list of `tests/check.sh` (`# steps: begin` to `# steps: end`) holds `add lint lint`, 48 `add bash` lines
  and 27 `add ps` lines. After the list, code adds the two `claude` steps (`claude plugin validate`,
  `claude plugin test`). The modes are full, `--quick` (the lint and the `bash` steps) and `--only` (the named steps,
  which does not read `verification.platform`). `verification.platform` `windows` skips every `bash` step and `unix`
  skips every `ps` step in a full or quick run (iteration 56). This repository sets `windows`.
- The check reads `.claude/nightmill.json` from the working tree with `scripts/lib/json.sh` (`checkJobs`,
  `platform`). It sources `scripts/lib/ledger.sh` and `scripts/lib/json.sh`.
- `ALL CHECKS PASSED` occurs once in `tests/check.sh`, and the lint pins that (iteration 42 decision 11 rule 4).
  `tests/smoke-check.sh` and `.ps1` run the lint section from `== the check runs every smoke script` to
  `== text from issues is data` on scratch copies (`mkcopy`, `lint_break`). `mkcopy` copies `scripts/lib` but no other
  file under `scripts/`.
- `scripts/` holds 19 pairs `<x>.sh` / `<x>.ps1` and `scripts/lib/` 15 files (`.sh`, `.ps1`, `.awk`).
- Bug #322 (from the issue): with `platform` `windows` the check was green while `smoke-slot.sh` was red, because the
  local check never ran the bash tests of a changed bash script.

## Decisions

**1. The mode: `--affected` (`tests/check.ps1 -Affected`).** It is a third selection mode beside `--quick` and
`--only`. Giving it with either of them, or twice, is the usage error (exit 2, before any step runs). It combines with
`--jobs`, `--powershell` and `--summary` as the other modes do. The usage line becomes
`usage: tests/check.sh [--quick | --only <step>[,<step>...] | --affected] [--jobs <1-16>] [--powershell powershell|pwsh] [--summary <file>]`,
and `tests/check.ps1` gets `[switch]$Affected`.

**2. The changed paths.**

- The base is `origin/<B>`, where `<B>` is `git.baseBranch` of `.claude/nightmill.json` at the repository root, read
  with `json_get` as the check reads `checkJobs`. When the key or the file is missing, `<B>` is `main`.
- The paths are the union, sorted (`LC_ALL=C sort -u`), of
  `git diff --name-only --no-renames <m>` (committed, staged and unstaged changes against the merge base, deletions
  included), where `<m>` is `git merge-base origin/<B> HEAD`, and `git ls-files --others --exclude-standard`
  (untracked files). Nothing is fetched.
- When `git merge-base` fails (not a repository, no `origin/<B>`, no common commit), the check runs the full check
  (decision 5) with the reason `the changed paths are unknown (no merge base with origin/<B>)`.
- For the tests only: when `NIGHTMILL_CHECK_PATHS` names a file, its lines are the paths (a trailing carriage return
  removed, empty lines skipped, then sorted and unique), git is not called, and `<ref>` in the lines of decision 6 is
  `NIGHTMILL_CHECK_PATHS`. CI does not set it.

**3. The map: one block in `tests/check.sh`.** It is a here-document between the lines `# affects: begin` and
`# affects: end`, outside the step list, so the step list's line format stays `add <kind> <name>[ first]`. The check
and the lint read the same lines. There are three kinds of line:

- `map <pattern> <step>[,<step>...]`: a path that matches the pattern selects the named steps. The step names are
  the rest of the line after the pattern, separated by commas, so the two `claude` step names, which have spaces,
  can be named too.
- `shared <pattern>`: a path that matches it runs the full check (decision 5).
- `lintonly <pattern>`: a path that matches it, and matches no `map` line, selects nothing but the lint.

A pattern is a bash `case` pattern matched against the whole path relative to the repository root, so `*` also
matches `/`. The map must hold these lines, and the lint pins them (decision 7):

```
shared scripts/lib/*
shared tests/check.sh
shared tests/check.ps1
lintonly docs/*
```

The `map` lines follow from the tests. Each `bash` and `ps` step gets a map line for every repository path its test
file names: a script, a skill, an agent, a hook, a template, the schema, a fixture folder, a workflow file, or a root
file such as `README.md` or `CHANGELOG.md`. A script `scripts/<x>.sh` or `scripts/<x>.ps1` that a test names is
always written with the pattern `scripts/<x>.*`, so both twins select the tests of both shells (decision 4). `skills/*`,
`agents/*`, `hooks/*` and `.claude-plugin/*` map to `claude plugin validate` and `claude plugin test` as well. A `map`
line whose pattern a `shared` line also matches is allowed, because `shared` wins.

**4. From paths to steps.** Every path is taken in sorted order:

1. When a `shared` pattern matches, the run is the full check (decision 5), and its reason names the first such path:
   `<path> is shared by many steps`.
2. Otherwise the path selects every step that a matching `map` line names, plus the step `<s>` itself when the path
   is `tests/<s>` and `<s>` is a step of the list (a changed test runs itself).
3. When that selects nothing and a `lintonly` pattern matches, the path selects nothing more than the lint.
4. When that selects nothing and no `lintonly` pattern matches, the run is the full check, and its reason names the
   first such path: `<path> is in no line of the map`.

The run takes the lint and the union of what every path selected. **The platform**: `--affected` does not apply
`verification.platform` to any step that a path selected, so a changed script runs its `bash` and `ps` tests whatever
the key says (criterion 5). A selected step that the machine cannot run keeps today's reason and is listed as
`SKIPPED:`, for example `PowerShell smoke tests (no pwsh or powershell)` or `claude plugin test not available`. With no
changed path at all, the run is the lint alone.

**5. The full check from `--affected`.** When decision 2 or 4 says so, the first line is
`check: AFFECTED: <reason>; running the full check`. After it comes the full check exactly as `tests/check.sh` with the
same options prints it: its header `check: full, <L> at a time (<why>)`, its sections, its `Times:` block, its
`SKIPPED:` lines, and its verdict `ALL CHECKS PASSED` or `CHECK FAILED: <names>` with the full check's exit code.
`verification.platform` applies as in a full run, except to the steps that a path selected by rule 2 of decision 4:
those run whatever the key says. So a run that changes `scripts/lib/json.sh` and `scripts/slot.sh` on `windows`
runs the full Windows check plus `smoke-slot.sh` and the other bash tests of the slot scripts. This is the full check,
so its last line is the full check's. The rule "the first and last line say it was not the full check" (criterion 6)
applies to a run that selected steps (decision 6).

**6. The lines of a selective run.** The first line is

```
check: AFFECTED, <L> at a time (<why>): <k> of <n> steps, changed paths: <c> (against <ref>); the full check does not run
```

`<L>` and `<why>` are those of iteration 42 decision 5. `<k>` is the number of steps selected, skipped ones included.
`<n>` is the number of steps in the list, the `claude` steps included (as in `--only`). `<c>` is the number of changed
paths. `<ref>` is `origin/<B>` or `NIGHTMILL_CHECK_PATHS`. Then comes one line per changed path, in sorted order:
`affected: <path> -> <the steps it selected, comma-separated, in list order>`, or `affected: <path> -> the lint only`.
After that come the sections, the `Times:` block and the `SKIPPED:` lines as in the other modes, and as its last line either

```
AFFECTED CHECK PASSED (<k> of <n> steps, changed paths: <c>; the full check has not run)
```

with exit 0, or

```
AFFECTED CHECK FAILED: <names> (the full check has not run)
```

with exit 1. A selective run never prints `ALL CHECKS PASSED` and never prints a line that starts `CHECK FAILED: `.
`--summary` writes its section as in the other modes. An interruption ends with `CHECK INTERRUPTED` and exit 130, as
today.

**7. The lint: a new section `== every script and every test step is in the map`**, in `tests/lint.sh` right after
`== the check runs every smoke script` (so inside the range that `tests/smoke-check.*` cut out). It runs in the lint's
own process and starts no process per path (bug #270). The rules and their texts:

1. `# affects: begin` and `# affects: end` each occur exactly once in `tests/check.sh`, the end after the begin, and
   every non-empty line between them matches `^(map [^ ]+ [^ ].*|shared [^ ]+|lintonly [^ ]+)$`. Otherwise:
   `FAIL: tests/check.sh: the map between '# affects: begin' and '# affects: end' is missing or malformed`.
2. Every name in a `map` line is a step of the step list or one of the two `claude` steps. Otherwise:
   `FAIL: tests/check.sh: the map names <x>, which is not a step`.
3. Every `bash` and `ps` step of the step list is named by at least one `map` line. A test's own file (rule 2 of
   decision 4) does not count. Otherwise: `FAIL: tests/check.sh: no path maps to the step <x>`.
4. Every file `scripts/*.sh`, `scripts/*.ps1` and `scripts/lib/*` matches a `map` or a `shared` pattern. Otherwise:
   `FAIL: tests/check.sh: scripts/<x> maps to no step`. A `lintonly` match does not count.
5. For every `scripts/<x>.sh` that has a `scripts/<x>.ps1`, the two paths select the same steps by decision 4.
   Otherwise: `FAIL: tests/check.sh: scripts/<x>.sh and scripts/<x>.ps1 map to different steps`.
6. The four lines of decision 3 are present. Otherwise: `FAIL: tests/check.sh: the map does not have the line <line>`.
7. `skills/workflow/SKILL.md` and `skills/check/SKILL.md` mention `--affected` and `check: AFFECTED`, and `README.md`
   mentions `--affected`. Otherwise: `FAIL: <file> does not mention <word>`, the form of the existing loop.

The matching is the bash `case` of decision 3, the same in the check and in the lint. `mkcopy` in
`tests/smoke-check.sh` and `.ps1` also copies `scripts/*.sh` and `scripts/*.ps1`, so the copy has scripts to check.

**8. The skills.**

- `skills/workflow/SKILL.md`, line 15: after the definition of *the quick check*, add "*the affected check* is the
  check with ` --affected` appended, for a check whose first line then starts with `check: AFFECTED`".
  "Verify before every commit" gains a paragraph after the quick-check paragraph: "Before a commit and in every fix
  round (a review's fix round, a check fix round, an extra round), the affected check may stand for the check. It runs
  the tests of what the branch changed against `origin/<git.baseBranch>`. Its last line `AFFECTED CHECK PASSED` is a
  green check for that commit, and a `Check:` line may report it. When its first line starts with `check: AFFECTED:`,
  it ran the full check, and its last line is the full check's. The full check still runs before a release, and CI
  runs every test on the base branch. A run counts as an affected check only when its first line starts with
  `check: AFFECTED`. When it does not (a check without the mode), the agent runs the check instead for the rest of its
  task." In the quick-check paragraph, "the check runs before every commit, before every pull request and in every fix
  round" becomes "the check or the affected check runs before every commit, before every pull request and in every
  fix round", and "a `Check:` line reports the check's last line, never the quick check's" becomes "a `Check:` line
  reports the last line of the check or of the affected check, never the quick check's".
- `skills/check/SKILL.md`: the run paragraph names `cd <absolute slot path> && <verification.check> --affected` beside
  the quick form. A new last paragraph: "`/nightmill:check affected` runs `<verification.check> --affected` (the
  affected check: the lint and the tests of the changed paths) and reports its last line. A last line
  `AFFECTED CHECK PASSED` is enough before a commit and in a fix round, never before a release. When its first line
  does not start with `check: AFFECTED`, say `the check command has no affected mode; running the check` and run
  `verification.check` as above." The fixing rules (at most three runs, environment versus code) apply to it
  unchanged.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The check has a mode that takes the changed paths (against the base branch) and runs exactly the steps mapped to them, plus the lint | Decisions 1, 2, 4, 6 |
| 2 | The mapping from paths to steps lives in one place, and the lint fails on a test step that no path maps to and on a script that maps to no step | Decision 3 (the block in `tests/check.sh`), decision 7 (rules 1 to 6) |
| 3 | A change only under the docs and specs folders runs the lint and nothing else | Decision 3 (`lintonly docs/*`), decision 4 (rule 3) |
| 4 | A change to a file shared by many steps (the libraries, the check itself) runs the full check | Decision 3 (the `shared` lines), decisions 4 (rules 1 and 4) and 5 |
| 5 | A changed script runs its tests in both shells where the machine can, whatever `verification.platform` says; what could not run is listed as skipped | Decision 3 (`scripts/<x>.*`), decision 4 (the platform), decision 5, decision 7 (rule 5) |
| 6 | The mode's first and last line say that it was not the full check, as the quick mode does | Decision 6; decision 5 for a run that became the full check |
| 7 | The workflow skill says where the affected-steps check is enough (before a commit, in a fix round) and where the full check still runs (CI on the base branch, before a release) | Decision 8 |

## Tests

**`tests/smoke-check.sh` and `tests/smoke-check.ps1`**, a new case `== affected`, after `== the platform from the
config`, in the same throwaway repository with its own `.claude/nightmill.json`. The `.ps1` runs `tests/check.ps1
-Affected`, and the expected text is the same in both. A steps file has the fixture steps `l` (`lint`), `b1`, `b2`
(`bash`), `p1`, `p2` (`ps`) and `c` (`claude`), each appending its name to one log. A map file (`NIGHTMILL_CHECK_MAP`,
below) holds `map scripts/foo.* b1,p1`, `map templates/t.md b2`, `shared scripts/lib/*` and `lintonly docs/*`. The
paths come from `NIGHTMILL_CHECK_PATHS`, and each run uses `--jobs 1`.

- Criterion 1: the paths `templates/t.md` and `tests/p2` give the log `l`, `b2`, `p2`, the first line
  `check: AFFECTED, 1 at a time (--jobs 1): 3 of 6 steps, changed paths: 2 (against NIGHTMILL_CHECK_PATHS); the full check does not run`,
  the lines `affected: templates/t.md -> b2` and `affected: tests/p2 -> p2`, the last line
  `AFFECTED CHECK PASSED (3 of 6 steps, changed paths: 2; the full check has not run)` and exit 0. An empty paths
  file gives the log `l` and a header with `1 of 6 steps, changed paths: 0`.
- Criterion 3: `docs/specs/x.md` alone gives the log `l` only and `affected: docs/specs/x.md -> the lint only`.
- Criterion 4: `scripts/lib/x.sh` gives the first line
  `check: AFFECTED: scripts/lib/x.sh is shared by many steps; running the full check`, the second line
  `check: full, 1 at a time (--jobs 1)`, the log of every step, and the last line `ALL CHECKS PASSED`. `other/thing`
  gives `check: AFFECTED: other/thing is in no line of the map; running the full check` and the same run.
- Criterion 5: `scripts/foo.ps1` gives the log `l`, `b1`, `p1` with `"platform": "windows"`, with `"platform": "unix"`
  and without the key, and never a `SKIPPED: ... verification.platform ...` line. With `p1` given the fixture reason
  `no pwsh here`, the log is `l`, `b1` and the line `SKIPPED: no pwsh here` is printed. With `"platform": "windows"`
  and the paths `scripts/lib/x.sh` and `scripts/foo.sh`, the log is `l`, `b1`, `p1`, `p2`, `c`, and
  `SKIPPED: bash tests (verification.platform is windows)` is printed for `b2` (decision 5).
- Criterion 6: with `b1` exiting 1 and the path `scripts/foo.sh`, the last line is
  `AFFECTED CHECK FAILED: b1 (the full check has not run)`, the exit code is 1, and the output has no `ALL CHECKS PASSED`
  and no line starting `CHECK FAILED: `.
- The changed paths from git (decision 2): in a throwaway repository with a bare `origin` and `main` pushed, a branch
  with one committed change (`templates/t.md`), one unstaged change (`scripts/foo.sh`) and one untracked file
  (`docs/n.md`), and `NIGHTMILL_CHECK_PATHS` unset, the three `affected:` lines appear in sorted order with
  `(against origin/main)`. With `"git": { "baseBranch": "trunk" }` and no `origin/trunk`, the first line is
  `check: AFFECTED: the changed paths are unknown (no merge base with origin/trunk); running the full check`.
- Usage: `--affected --quick`, `--affected --only l` and `--affected --affected` each give the usage line of
  decision 1 on standard error and exit 2, and the log stays empty. The `USAGE` constant of both files becomes the
  line of decision 1.

For the tests only, `NIGHTMILL_CHECK_MAP` names a file of map lines in the grammar of decision 3. It is read instead of
the block when `NIGHTMILL_CHECK_STEPS` is set. When it is unset in fixture mode, the map is empty, so every path other
than a `tests/<step>` path runs the full check. The header comment of `tests/check.sh` names it beside
`NIGHTMILL_CHECK_STEPS` and `NIGHTMILL_CHECK_PATHS`.

**The lint** (criterion 2; the rules of decision 7), as `lint_break` cases in both `tests/smoke-check.*`. The passing
case is the existing `lint-ok` copy, which must stay free of any `FAIL`. The failing cases each break one rule:
`mapstep` removes `smoke-hook.sh` from every `map` line and expects `no path maps to the step smoke-hook.sh`;
`mapscript` adds an empty file `scripts/zz-new.sh` to the copy and expects `scripts/zz-new.sh maps to no step`;
`mapname` adds `map README.md smoke-nope.sh` and expects `the map names smoke-nope.sh, which is not a step`;
`maptwin` adds `map scripts/slot.sh smoke-hook.sh` and expects
`scripts/slot.sh and scripts/slot.ps1 map to different steps`; `mapshared` removes `shared scripts/lib/*` and expects
`the map does not have the line shared scripts/lib/*`; `mapskill` replaces `check: AFFECTED` in
`skills/check/SKILL.md` and expects `skills/check/SKILL.md does not mention check: AFFECTED`.

**The full check on the branch**: `bash tests/check.sh` is green. `bash tests/check.sh --affected` on the branch
(whose paths include `tests/check.sh`) prints `check: AFFECTED: tests/check.sh is shared by many steps; running the
full check`. In "How verified" the implementer also gives the first and last line of one selective run, made by
`NIGHTMILL_CHECK_PATHS` with `scripts/slot.sh` on this repository.

**Manual check by the maintainer** (skills change; criteria 5 and 7). The branch itself changes the shared
`tests/check.sh`, so on it every `--affected` run is the full check. So: in a second clone, move its local
`origin/main` to the tip of the implemented branch (`git update-ref refs/remotes/origin/main origin/<branch>`; the
check fetches nothing, so it stays there) and create a throwaway branch from it. Its tests then have the mode, and its
changed paths are only what the maintainer changes. Load nightmill from a separate checkout of the implemented branch
(`claude --plugin-dir <that checkout>`, started in the second clone).

1. Change one line of `scripts/history.sh` and run `/nightmill:check affected`. It runs
   `bash tests/check.sh --affected`; the first line starts `check: AFFECTED, `, the line
   `affected: scripts/history.sh -> ...` names `smoke-history.sh` and `smoke-history.ps1`, both run though the config
   says `windows`, and the reported last line is `AFFECTED CHECK PASSED (...)`.
2. Undo that change, change one file under `docs/` alone and run it again: `affected: docs/<file> -> the lint only`,
   only the lint runs, and the last line is `AFFECTED CHECK PASSED (1 of <n> steps, changed paths: 1; the full check
   has not run)`.
3. Read the new paragraph of "Verify before every commit" in the loaded workflow skill: the affected check is enough
   before a commit and in a fix round, the full check runs before a release, and CI runs every test.

Delete the throwaway branch and the second clone afterwards.

## Files touched

- `tests/check.sh`: `--affected` (decisions 1, 2, 4 to 6), the map block (decision 3), `NIGHTMILL_CHECK_PATHS` and
  `NIGHTMILL_CHECK_MAP`, the usage line and the header comment.
- `tests/check.ps1`: `[switch]$Affected`, passed on as `--affected`, and its header comment.
- `tests/smoke-check.sh`, `tests/smoke-check.ps1`: the case `== affected`, the `USAGE` constant, `mkcopy` copying
  `scripts/*.sh` and `scripts/*.ps1`, and the six `lint_break` cases.
- `tests/lint.sh`: the section of decision 7.
- `skills/workflow/SKILL.md`, `skills/check/SKILL.md`: decision 8.
- `README.md`, under `## Developing nightmill`, in the paragraph on `tests/check.sh`: "`bash tests/check.sh
  --affected` runs the lint and the tests of the paths changed against `origin/<git.baseBranch>` (the map in
  `tests/check.sh`), the tests of a changed script in both shells; a change to `scripts/lib/` or the check itself, or
  to a path the map does not know, runs the full check. It is enough before a commit and in a fix round; the full
  check runs before a release, and CI runs every test."
- `CHANGELOG.md`, one bullet under `Unreleased`:

  ```
  - Iteration 59 (#338): the check runs only the steps a change affects. tests/check.sh --affected (check.ps1
    -Affected) maps the paths changed against origin/<git.baseBranch> to their test steps through one map in
    tests/check.sh and runs the lint plus those steps; a changed script runs its tests in both shells whatever
    verification.platform says, a change under docs/ runs the lint alone, and a shared file or an unknown path runs
    the full check. Its first and last line say the full check has not run. The lint fails on a test step no path
    maps to and on a script that maps to no step. The workflow and check skills say the affected check is enough
    before a commit and in a fix round. No config key.
  ```

Not touched: `.github/workflows/ci.yml` (#339), every script in `scripts/`, the schema, the example config,
`skills/next/SKILL.md`, `skills/fix/SKILL.md`.

## Risks

- **A map that misses a dependency.** A test that reads a file its source does not name (a path built at run time)
  is not selected when that file changes. The local run is then green and CI red. CI still runs every test on every
  pull request until #339, and the fix is a `map` line. An unknown path runs the full check, so a new file is never
  checked by the lint alone.
- **Bash tests on Windows.** A changed script now runs its bash tests in Git Bash on a `windows` machine. These are the
  tests that iteration 56 skipped for being slow there, and they can fail there for reasons that are not product
  bugs (#300, #302 to #304). That is the issue's intent (#322). Such a failure is handled as an environmental failure
  by `/nightmill:check`.
- **Too many full runs.** Every branch that changes `tests/check.sh` or `scripts/lib/` runs the full check, and so
  does every path missing from the map. The `affected:` lines show why.
- **The lint's cost inside the PowerShell steps** (bug #270): the new section matches patterns in its own process.
  About 50 files times about 100 lines is a few thousand `case` tests, with no process started.

## Size estimate

`L`: about 450 changed lines. `tests/check.sh` about 80 plus the map block (about 110 lines for 75 test steps and the
`claude` steps), `tests/check.ps1` about 4, the two smoke files about 180 together, `tests/lint.sh` about 50, the two
skills about 15, README about 5, CHANGELOG about 8.

## Not done

- No change to CI: what CI runs on a pull request and on the base branch is #339.
- No test is removed, moved, split or made faster (#340).
- No new config key: neither a key for the map nor one for the affected check's command. A project's own check gets
  the mode only by implementing `--affected` and its first line.
- No change to `/next`, `/fix`, their implementer and fixer prompts or their `Check:` lines. See Left.
- No map derived automatically from the tests (decision 3 fixes how the implementer writes the lines). No timing
  figure or budget for the mode (the epic's time budget is a story of its own).
- No change to `--quick`, `--only`, the full check or `verification.platform` outside `--affected`.
- No fetch of `origin` before the diff.

## Left

- **The skills that run the check.** The issue asks only that the workflow skill say where the affected check is
  enough, and its agent notes name only the workflow and check skills. The prompts of `/next` and `/fix` still tell
  the implementer and the fixer to "run the check" before a commit and in a fix round, so in practice they keep
  running the full check until those prompts name `--affected`. Whether that change belongs in this story or in one
  of its own is for the maintainer.
- **"The full check" for a shared file.** Decision 5 runs the full check under `verification.platform` and adds the
  steps the changed scripts select (criterion 5). The other reading, every step of both families, would make every
  library change on Windows a 2 to 3 hour run (iteration 56). The maintainer may choose otherwise.
