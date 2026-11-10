# Iteration 51: the lint keeps the README's list of smoke tests and the shell twins in agreement with the files

Status: delivered in iteration 51 (PR #263)

Story #157, epic #107 (Hardening from the code review), finding MD-T6. Of the four criteria, two already hold on main
and one holds in part: CI and `tests/check.sh` are tied to the smoke files by the lint since iteration 42, the
executable bit of `scripts/*.sh` is enforced by `tests/test-script-modes.sh` (bug #114, closed), and bare `mktemp` is
rejected by the lint and `tests/test-mktemp-template.sh` (bug #115, closed). What is missing is that the README lists
every smoke file, that every `tests/smoke-*.sh` has a `.ps1` twin (with an explicit list of exceptions) and that
every `scripts/*.sh` has a `.ps1` twin. These rules go into a new `tests/test-lint-agreement.sh [<root>]`, which a new
`tests/lint.sh` section calls, so that `tests/check.sh`'s step list and `.github/workflows/ci.yml` do not change. The
README gets the four lines it lacks today. Changes `tests/test-lint-agreement.sh` (new), `tests/lint.sh`, `README.md`
and `CHANGELOG.md`.

## Story trigger and manual check

**Not a story trigger** (it is a story anyway). Of `escalation.storyTriggers`:

- *A change to the status flow or who sets a status*: no. No skill, status or board step changes. No decision record
  is needed and none of `docs/decisions/` 0001 to 0003 is contradicted.
- *A new, renamed or removed config key*: no. The list of twin exceptions describes this repository's tests, not a
  project's values, so it lives in the test file and not in `.claude/nightmill.json` (invariant "Config-driven"
  holds). Invariant "Compatible" holds.
- *A change to the slot marker format*: no. No slot script changes.

**The manual check does not apply**: nothing under `skills`, `agents` or `hooks` (`verification.manualCheckPaths`)
changes.

**Both shells** (invariant ticked in the issue): no script in `scripts/` changes, so no smoke step is added in either
shell. The new file is a bash test of the repository's own files, called from the lint (which is bash only), as
`tests/test-security-model.sh` (iteration 39), `tests/test-unattended-docs.sh` (iteration 49) and
`tests/test-config-from-base.sh` (iteration 48) are. The lint's `== the check runs every smoke script` requires only
`tests/smoke-*` files in the step list, so a `tests/test-*` file the lint calls needs no step and no `--only` entry.

**Order with other work.** Iteration 48 (#111) is merged on main (f02614f, PR #258); this spec is written against
it, and its `scripts/lib/baseconfig.sh` and `.ps1` sit in `scripts/lib/`, which the twin rule for `scripts/*.sh` does
not read. Iteration 50 (#253, in implementation) changes `scripts/guard.*`, `tests/smoke-guard.*`,
`tests/test-guard-rules.sh` and the README, but adds no smoke file and no script, so the rules below hold before
and after it merges. Its README change is in the guard text, not in the list under `## Developing nightmill`; if
both touch neighbouring lines, the merge conflict is textual only. Neither iteration needs to land before this one,
and this one changes nothing they change except `README.md` and `tests/lint.sh` (iteration 50 does not touch the
lint). `.github/workflows/ci.yml` does not change, so this pull request is not held back from auto-merge by
iteration 48's rule for `.github/`.

## Facts this rests on

Read on main at f02614f (2026-11-10); `bash tests/lint.sh` ends `LINT OK` and `bash tests/test-script-modes.sh`
ends `OK: script modes and skill calls` there.

- **Files.** `tests/` has 17 `smoke-*.sh` and 16 `smoke-*.ps1`; the only `.sh` without a `.ps1` twin is
  `smoke-json.sh`, and no `.ps1` lacks a `.sh`. `scripts/` has 16 `*.sh`, each with a `.ps1` twin. `scripts/lib/`
  has 4 `*.sh` (`baseconfig`, `json`, `ledger`, `load`); `json.sh` has no `.ps1` twin (the PowerShell scripts read
  JSON with `ConvertFrom-Json`, iteration 7). No tracked `.sh` lies outside `scripts/` and `tests/`.
- **README.** The code block under `## Developing nightmill` lists 15 `bash tests/smoke-*.sh` lines and 14
  `powershell -ExecutionPolicy Bypass -File tests/smoke-*.ps1` lines. It lacks `smoke-stages.sh` and `.ps1`
  (added in iteration 41) and `smoke-guard.sh` and `.ps1` (added in iteration 47). No other line of the README
  starts with either form; line 327 names `tests/smoke-guard.sh` inside a sentence.
- **Modes.** All 16 `scripts/*.sh` are `100755` in the index. The 4 `scripts/lib/*.sh` and 35 files in `tests/` have
  a shebang and are `100644`; all of them are sourced or run with `bash <file>`, never directly.
- **Issues.** #114 ("Skills call slot.sh and other scripts directly, but they are committed non-executable") and #115
  ("Bare mktemp fails on sandboxed macOS") are closed.

**The finding still holds**, part by part:

1. *A test missing from `ci.yml` never runs in CI*: no longer holds. Iteration 42 decision 11 (`tests/lint.sh`,
   `== the check runs every smoke script`) requires every `tests/smoke-*.sh` exactly once as `add bash` and every
   `tests/smoke-*.ps1` exactly once as `add ps` in the step list of `tests/check.sh`, every name in the list to exist,
   CI's two `tests/check.sh --only` lists to equal the step list in order (the bash one without `smoke-json.sh`),
   `smoke-json.sh` to run in CI on its own line exactly once, and no other smoke file to run outside
   `tests/check.sh`.
2. *The README is not tied to the files*: holds. Nothing reads the README's list, and it is already four lines short.
3. *Nothing enforces a `.ps1` twin for each `.sh`*: holds, for `tests/smoke-*.sh` and for `scripts/*.sh`. The
   lint's per-script sections name both twins of some scripts (status, models, slot, load, room, control, ...), but
   no rule covers a new file.
4. *Executable bit*: no longer holds for `scripts/*.sh`. `tests/test-script-modes.sh` part (a) (#114) fails when a
   `scripts/*.sh` (not `scripts/lib/`) has a shebang and is not `100755` in the git index; it is a step of
   `tests/check.sh` and in CI's bash `--only` list.
5. *Bare `mktemp`*: no longer holds. `tests/lint.sh` `== temporary files have a template` (#115) fails on a call
   without a template in `scripts/*.sh`, `scripts/lib/*.sh` and `tests/*.sh` outside a comment line, and
   `tests/test-mktemp-template.sh` part (a) checks the same files with its own scanner and part (b) runs four
   scripts against a `mktemp` that refuses a bare call.

## Decisions

**1. The rules live in a test file the lint calls.** `tests/test-lint-agreement.sh [<root>]` (default: this
checkout, `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)`), `set -euo pipefail`, needs bash and awk, no jq and
no network. A new section in `tests/lint.sh`, directly after `== the check runs every smoke script` and before
`== text from issues is data`:

```
echo "== the lists and the shell twins agree"
# Iteration 51 (#157): the README lists every smoke file, every tests/smoke-*.sh has a .ps1 twin (except the listed
# ones), every scripts/*.sh has a .ps1 twin. The rules live in tests/test-lint-agreement.sh.
bash tests/test-lint-agreement.sh "$PWD" || fail=1
```

Reason: the lint already reads `ci.yml` and `tests/check.sh` (finding 1), so nothing in either file changes; a test
file that takes a root can be run against scratch trees (decision 6), as iterations 39, 48 and 49 do.

**2. The README lists every smoke file (criterion 1).** In `<root>/README.md`, with a trailing carriage return
stripped from each line:

1. A *list line* is a line that starts with `bash tests/smoke-` or with
   `powershell -ExecutionPolicy Bypass -File tests/smoke-`. Its *name* is the longest run of `[A-Za-z0-9._-]`
   after `tests/`; after the name the line ends or continues with one or more blanks (space or tab) and then `#`.
   A list line in any other form (for example a word after the name without `#`) is
   `FAIL: README.md: malformed smoke line: <line>`.
2. Every file `<root>/tests/smoke-*.sh` has exactly one list line `bash tests/<file>`, and every
   `<root>/tests/smoke-*.ps1` exactly one list line `powershell -ExecutionPolicy Bypass -File tests/<file>`; none is
   `FAIL: README.md does not list tests/<file>`, more than one is `FAIL: README.md lists tests/<file> more than once`.
3. Every list line names a file that exists in `<root>/tests/`; else
   `FAIL: README.md lists tests/<name>, which does not exist`. A `bash` line whose name does not end in `.sh`, or a
   `powershell` line whose name does not end in `.ps1`, is `FAIL: README.md runs tests/<name> in the wrong shell`
   (and does not count for rule 2).

The lines are counted anywhere in the README, not only in the block under `## Developing nightmill`; a mention in a
sentence (not at the start of a line) is not a list line. The order of the lines is free.

**3. Every smoke script has a PowerShell twin, with a list of exceptions (criterion 2).**

1. The list is one variable at the top of `tests/test-lint-agreement.sh`, one file name per line, each with a comment
   that says why; it holds exactly `smoke-json.sh` (it tests `scripts/lib/json.awk` and `json.sh`, the JSON reader of
   the bash scripts; the PowerShell scripts read JSON with `ConvertFrom-Json`, iteration 7).
2. Every file `<root>/tests/smoke-<x>.sh` whose name is not on the list has a file `<root>/tests/smoke-<x>.ps1`; else
   `FAIL: tests/smoke-<x>.sh has no PowerShell twin tests/smoke-<x>.ps1`.
3. The list stays exact: a name on it that is not a file in `<root>/tests/` is
   `FAIL: the twin exceptions name tests/<file>, which does not exist`, and a name whose `.ps1` twin exists is
   `FAIL: the twin exceptions name tests/<file>, which has a PowerShell twin`.

**4. Every script has a PowerShell twin (criterion 3).** Every file `<root>/scripts/<x>.sh` (the top level only, not
`scripts/lib/`) has a file `<root>/scripts/<x>.ps1`; else `FAIL: scripts/<x>.sh has no PowerShell twin
scripts/<x>.ps1`. There is no list of exceptions: none is needed today and the criterion names none. The executable
bit stays with `tests/test-script-modes.sh` part (a) (finding 4), unchanged.

**5. Output and exit.** Each problem is one `FAIL:` line on stderr; all rules run before the script exits (one
problem does not hide the next). The script then runs the self-test (decision 6). It exits 1 if any `FAIL:` line was
printed and 0 with the line `OK: lists and twins agree` on stdout otherwise. A missing `<root>/README.md` is
`FAIL: README.md missing`.

**6. A self-test of the rules.** As `== specs follow the template` does (iteration 40), the script checks the rules
of decisions 2 to 4 on trees it builds under `mktemp -d "${TMPDIR:-/tmp}/nightmill-agree.XXXXXX"` (removed on exit by
a trap). The rules are one function `agree <root>` that prints the `FAIL:` lines of decisions 2 to 4 and that both the
real check and the self-test call. The base tree holds `tests/smoke-a.sh`, `tests/smoke-a.ps1`,
`tests/smoke-json.sh`, `scripts/a.sh`, `scripts/a.ps1` and a `README.md` with the three list lines
`bash tests/smoke-a.sh   # a`, `bash tests/smoke-json.sh` and
`powershell -ExecutionPolicy Bypass -File tests/smoke-a.ps1`. The cases, each a copy of the base with one change, and
the text the output of `agree` must contain:

| Case | Change | Expected |
|---|---|---|
| clean | none | no output at all |
| unlisted | drop the line of `smoke-a.sh` | `README.md does not list tests/smoke-a.sh` |
| twice | add the line of `smoke-a.ps1` again | `README.md lists tests/smoke-a.ps1 more than once` |
| missing | add `bash tests/smoke-nope.sh` | `README.md lists tests/smoke-nope.sh, which does not exist` |
| shell | add `bash tests/smoke-a.ps1` | `README.md runs tests/smoke-a.ps1 in the wrong shell` |
| malformed | add `bash tests/smoke-a.sh now` | `README.md: malformed smoke line` |
| no twin | add `tests/smoke-b.sh` and its line | `tests/smoke-b.sh has no PowerShell twin tests/smoke-b.ps1` |
| exception gone | remove `tests/smoke-json.sh` and its line | `the twin exceptions name tests/smoke-json.sh, which does not exist` |
| exception twinned | add `tests/smoke-json.ps1` and its line | `the twin exceptions name tests/smoke-json.sh, which has a PowerShell twin` |
| script | add `scripts/b.sh` | `scripts/b.sh has no PowerShell twin scripts/b.ps1` |

A case whose output lacks its text (or, for `clean`, is not empty) is
`FAIL: the agreement self-test: <case>: expected <text>, got: <output>`.

**7. The README gets the missing lines.** In the code block under `## Developing nightmill`:
`bash tests/smoke-stages.sh  # stages.sh: the stage record against a fixture ledger` after the line of
`smoke-panel.sh`; `bash tests/smoke-guard.sh   # guard.sh: what the PreToolUse guard refuses` after the line of
`smoke-check.sh`; `powershell -ExecutionPolicy Bypass -File tests/smoke-stages.ps1` after the line of
`smoke-panel.ps1`; `powershell -ExecutionPolicy Bypass -File tests/smoke-guard.ps1` after the line of
`smoke-check.ps1`. Nothing else in the README changes.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | Every `tests/smoke-*` file is listed in `ci.yml`, `tests/check.sh` and the README | `ci.yml` and `tests/check.sh`: already enforced (Facts, finding 1; iteration 42 decision 11), unchanged. README: decisions 2 and 7 |
| 2 | Every `smoke-*.sh` has a `.ps1` twin, with an explicit list of exceptions | Decision 3 |
| 3 | Every `scripts/*.sh` has a `.ps1` twin and every script with a shebang is executable | Twin: decision 4. Executable: already enforced by `tests/test-script-modes.sh` part (a) (Facts, finding 4), unchanged |
| 4 | Bare `mktemp` is rejected | Already enforced by `== temporary files have a template` and `tests/test-mktemp-template.sh` (Facts, finding 5), unchanged |

## Tests

- Criterion 1 (README): `tests/test-lint-agreement.sh`, rules of decision 2, through the lint section
  `== the lists and the shell twins agree`; self-test cases `clean`, `unlisted`, `twice`, `missing`, `shell`,
  `malformed`. On main before the README change it prints `FAIL: README.md does not list tests/smoke-stages.sh` and the
  same for `smoke-stages.ps1`, `smoke-guard.sh` and `smoke-guard.ps1`, which is the failing test before the fix;
  after decision 7 it passes. The `ci.yml` and `tests/check.sh` part keeps its existing section
  (`== the check runs every smoke script`), which must still pass.
- Criterion 2: the same file, decision 3; self-test cases `no twin`, `exception gone`, `exception twinned`. Passes on
  main with `smoke-json.sh` as the one exception.
- Criterion 3: the same file, decision 4; self-test case `script`. The executable part keeps
  `tests/test-script-modes.sh`, which must still pass.
- Criterion 4: `== temporary files have a template` and `tests/test-mktemp-template.sh`, unchanged, must still pass;
  the new file uses a templated `mktemp -d` (decision 6) and so passes both.
- The whole: `bash tests/check.sh` green. Before the pull request the implementer also breaks each rule once in a
  scratch copy of the repository (`tar` without `.git`) and runs `bash tests/test-lint-agreement.sh <copy>`: delete the
  README line of `smoke-hook.sh`, add `tests/smoke-zz.sh`, delete `scripts/room.ps1`; each gives its `FAIL:` line,
  recorded in "How verified".
- No smoke step in either shell: no script changes. No manual check (no path of `verification.manualCheckPaths`).

## Files touched

- `tests/test-lint-agreement.sh` (new): decisions 1 to 6.
- `tests/lint.sh`: the section of decision 1 (four lines), nothing else.
- `README.md`: the four lines of decision 7.
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 51 (#157): the lint keeps the README's list of smoke tests and the
  shell twins in agreement with the files: every tests/smoke-* file is listed in the README, every tests/smoke-*.sh
  has a .ps1 twin (smoke-json.sh is the one listed exception) and every scripts/*.sh has a .ps1 twin
  (tests/test-lint-agreement.sh, called from the lint). The README lists smoke-stages and smoke-guard in both shells.
  No config key.` (paths and names in backticks).

Not touched: `.github/workflows/ci.yml`, `tests/check.sh`, `tests/check.ps1`, `tests/test-script-modes.sh`,
`tests/test-mktemp-template.sh`, every script in `scripts/`, the skills, the agents, the hooks, the schema, the
templates, `CONTRIBUTING.md`.

## Risks

- **A new smoke file now needs three more lines.** Adding `tests/smoke-x.sh` fails the lint until it has a `.ps1`
  twin (or an entry in the exception list), a README line in its shell, a step in `tests/check.sh` and a name in the
  right `--only` list of `ci.yml`. That is the goal; each `FAIL:` line names the file and the place.
- **A `ci.yml` edit is still needed for a new smoke file**, as today (iteration 42); this iteration adds no new
  reason to edit it. Such a pull request is not auto-merged since iteration 48; that is unchanged.
- **The README form is fixed.** A future rewording of the README's block (another prefix, `pwsh` instead of
  `powershell`) fails the lint until the rule changes with it. The forms are the ones the README and
  `.claude/CLAUDE.md` use today.
- **The exception list can grow quietly.** A name added to the list with a reason passes; review of the pull request
  is the only check on the reason. Rule 3 of decision 3 keeps the list from naming files that are gone or twinned.

## Size estimate

`S`: about 80 lines in `tests/test-lint-agreement.sh` (the rules about 40, the self-test about 40), 4 in
`tests/lint.sh`, 4 in `README.md` and 5 in `CHANGELOG.md`: about 93 changed lines in four files.

## Not done

- No change to how `ci.yml` and `tests/check.sh` are tied to the smoke files (iteration 42 decision 11 holds), to
  the executable check (`tests/test-script-modes.sh`) or to the `mktemp` checks; they already meet criteria 1, 3 and
  4 in those parts.
- `tests/test-*` files are not required in the README or as twins; the criteria name only `tests/smoke-*`.
- A `tests/smoke-*.ps1` or `scripts/*.ps1` without a `.sh` twin is not checked (none exists; the criteria name the
  `.sh` side only).
- `scripts/lib/` is not checked for twins (`json.sh` has none by design), and `scripts/lib/*.sh` and `tests/*.sh` are
  not required to be executable (Left).
- `CONTRIBUTING.md` and other documents that name smoke tests are not checked.
- The `mktemp` scanners are not widened to other flags (`-q`, `-t`, `-u`) or redirections after a bare call.

## Left

- **"Every script with a shebang is executable"** is read as every `scripts/*.sh`, the subject of the criterion's
  line, which `tests/test-script-modes.sh` already enforces. Read literally over the repository it would also cover
  the 4 `scripts/lib/*.sh` and 35 files in `tests/` that have a shebang and are `100644` today (all sourced or run
  with `bash <file>`); that would mean a mode change on 39 files and a wider rule. If the maintainer wants that, it is
  a change to decision 4 and part (a) of `tests/test-script-modes.sh`, not made here.
- **"Fails the lint"** (the Goal): the executable rule fails `tests/check.sh` and CI's bash job, not the lint job,
  because it lives in `tests/test-script-modes.sh`; the `mktemp` rule fails both. This spec does not move it into the
  lint, since the criterion already holds through the check.
