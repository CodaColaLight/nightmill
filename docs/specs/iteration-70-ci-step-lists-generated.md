# Iteration 70: CI takes every smoke job's steps from the step list of tests/check.sh

Status: draft, awaiting approval (#343)

Story #343, epic #337 (fast verification loop). Today a new test is one line in the step list of `tests/check.sh`
and one name in each of two long lines of `.github/workflows/ci.yml` (the Ubuntu job's list and the packed Git Bash
part). Two pull requests that add a test conflict on those lines, and lint rules exist only to keep the lists in
step. After this iteration the step list is the only list. A step's line can carry three new marks, `jq`, `nogitbash`
and `alone`. `tests/check.sh` learns three kinds of group, `@with-jq`, `@without-jq` and `@gitbash-<k>`, which it
expands from those marks. The workflow names groups, never a step. The bash lines of the step list are kept in name
order, so two new tests usually go in at different places. The lint rules that compared the workflow's lists with the
step list are removed. In their place: no step name may appear in the workflow; the marks are pinned to the steps that
earlier specs chose; and any test file that runs nowhere fails. Changes `tests/check.sh`, `.github/workflows/ci.yml`,
`tests/lint.sh`, `tests/test-ci-parts.sh`, `tests/smoke-check.sh`, `tests/test-ci-run-steps.sh` (one header line),
`README.md` and `CHANGELOG.md`.

**Never auto-merged.** The pull request changes `.github/workflows/ci.yml`, so `/next` opens it without `--auto` (its
rule for `.claude/` and `.github/`), and the maintainer merges it by hand with `gh pr merge <n> --auto --squash`.

## Story trigger and manual check

**Not a story trigger.** *Status flow*: no status, no board call and no decision record changes. *Config key*: none is
added, renamed or removed. The marks and the groups belong to this repository's `tests/check.sh`. They are not keys of
`.claude/nightmill.json` or of the schema. *Slot marker*: no script under `scripts/` changes, so no marker changes.
**Compatible** holds: `--only` and `--within` with plain step names behave as before, and a project reads nothing that
changes.

**The manual check does not apply.** `verification.manualCheckPaths` is `skills`, `agents`, `hooks`, and no file under
them changes.

**Shells.** Bash only. No file under `scripts/` changes, and no `.ps1` file is added or changed (`tests/check.ps1`, the
wrapper, stays as it is). The smoke steps involved are `tests/smoke-check.sh` (the check's groups on fixture steps, and
the lint's rules on copies) and the lint, which starts `tests/test-ci-parts.sh` once.

## Facts this rests on

Read on branch `spec/70-ci-step-lists-generated` at 4395b13 ("docs: iteration 69 spec, timeout decision settled (#390)
(#397)"), equal to `main`, on 2026-11-27. No network call was made.

- **The story text is older than #365.** "The PowerShell steps" and the invariant "Both shells" refer to the PowerShell
  CI parts and twins that iteration 68 removed. Today CI has the lint job, the Ubuntu job `smoke-bash`, the Git Bash
  part job `smoke-gitbash-part` (a matrix of `part`/`only` pairs on `windows-latest`) and the final job `smoke-gitbash`.
  The invariant is "Bash only" (decision record 0004).
- **The step list** (`tests/check.sh` lines 92 to 142, between `# steps: begin` and `# steps: end`): `add lint lint`,
  then 48 `add bash` lines in the order the tests were added. Two lines carry `first` (`smoke-slot.sh`,
  `test-spec-template.sh`) and one carries `slow` (`test-lintcopy-output.sh`). `add()` (lines 78 to 89) accepts the
  marks `""`, `first`, `slow` and `first slow`. The fixture format `NIGHTMILL_CHECK_STEPS` (header lines 38 to 41,
  reader lines 241 to 261) has six tab fields: name, command, kind, reason, first, slow. `--only` and `--within` take
  step names only (lines 263 to 281 and 390 to 401), and an unknown name prints `check: no step named <x>` and exits
  with code 2.
- **The workflow names 95 steps** (`.github/workflows/ci.yml`). In `smoke-bash`, line 39 runs `$CHECK_SELECT smoke-json.sh`
  before the step `Hide jq` (line 40), and line 44 runs `$CHECK_SELECT` followed by the other 47 bash steps in step-list
  order. In `smoke-gitbash-part` (lines 46 to 77), the name line is `Git Bash smoke part ${{ matrix.part }} of 7`, the
  matrix (lines 55 to 70) has seven `- part: <k>` / `only: <list>` pairs, and the check step (lines 75 to 77) is
  `- shell: bash`, `continue-on-error: true`, `run: ... $CHECK_SELECT ${{ matrix.only }}`. Parts 1 to 6 each hold one
  step (`smoke-slot.sh`, `smoke-status.sh`, `smoke-check.sh`, `test-guard-rules.sh`, `smoke-release.sh`,
  `smoke-validate.sh`). Part 7 holds the other 41. `test-lintcopy-output.sh` is in no part (iteration 66 decision 3).
- **The lint rules that compare the lists** (`tests/lint.sh`):
  - `chk_only` (lines 1321 to 1337) and its call (lines 1353 to 1356) check that line 44's list is exactly the step
    list's bash steps except `smoke-json.sh`, named once each and in list order.
  - The two-line rule (lines 1338 to 1352) checks that line 39's list is exactly `smoke-json.sh`.
  - Rule 11 of `tests/test-ci-parts.sh` (lines 181 to 235, with the lists `gitbash_out` and `gitbash_alone` at lines 26
    to 35) checks that every bash step except `gitbash_out` is in exactly one part, that each part is in list order,
    and that each step on `gitbash_alone` has a part of its own.
  - `tests/smoke-check.sh` breaks these rules in its cases `cibash`, `cijson`, `ciswap` and `cijsondirect` (lines 654
    to 666). `tests/test-ci-parts.sh` breaks rule 11 in `gbnoguard`, `gbgate2`, `gbnewstep`, `gbnostep`, `gborder`,
    `gblintcopy`, `gbalone`, `gbout` and `gbalonenope` (lines 368 to 403).
- **Rules that stay, but read the line format** (`tests/lint.sh`): `firsts` (line 1230, `/ first( slow)?$/`), the
  step-list pattern (line 1250, `^add (lint|bash) [A-Za-z0-9._-]+( first)?( slow)?$`), `chk_slows` and the `# Time: `
  loop (lines 1256 and 1264, `$NF == "slow"`), and `tests/smoke-check.sh` lines 601 to 609 (`sed 's/ slow$//'`, then
  whole-line matches) together with its cases `slowformat` and `slowset` (lines 700 and 701). Each of them breaks once
  a new mark follows `first` or `slow` on a line.
- **A test file in no list.** The lint fails on a `tests/smoke-*.sh` that is not a step (lines 1276 to 1282). It checks
  no `tests/test-*.sh`. On this commit, each of the 52 `tests/test-*.sh` is either a step of the list (28) or started
  by a `bash tests/<file>` line of `tests/lint.sh` (24). None runs nowhere.
- **The affects map** (lines 163 to 237) and its lint rule 3 (`tests/lint.sh` lines 1415 to 1421: every bash step is
  named by a map line). Because of this rule, a new test today also edits a map line. The map decides which steps a
  pull request runs, and the story puts that out of scope.
- **The conflict**: two pull requests that each append a step before `# steps: end` add different lines at the same
  place, which git cannot merge. This happens with the step list as it is too, not only with the workflow's lines.
- **#390 (iteration 69)** is approved, and its pull request is being implemented but is not merged. It changes the same
  files, at these places:
  - `ci.yml` lines 47 to 49 (comment), 52 (`timeout-minutes: 51`), 76 (deletes `continue-on-error: true`), 80 and 81
    (comment and the name `Git Bash scripts smoke tests`);
  - `tests/test-ci-parts.sh` rule 10a (lines 103 to 158: a `continue-on-error:` flag, and the run-step text, which ends
    `in a step with shell: bash`), rule 10b (line 166) and the cases `gbcoe`, `gbshell` and `gbfname`;
  - `tests/lint.sh` lines 1365 and 1371 (a third required name), the heredoc of rule 4 and its count, and the comments
    at lines 1497 and 1695;
  - the sentence on the Git Bash jobs in `README.md` (lines 1116 to 1118).

  It keeps the part job's name, matrix and run line.
- **Iteration 55 decision 3** says "`tests/check.sh` does not learn parts ... no group field in the step list". This
  story's criterion 2 asks for the opposite (decision 7).

## Decisions

**1. The step-list line and its marks** (the implementer's, `tests/check.sh`). A line is
`add <kind> <name>[ first][ slow][ jq][ nogitbash][ alone]`: the marks appear in this order, each at most once.
`jq`, `nogitbash` and `alone` go on `bash` lines only, and a line never carries both `nogitbash` and `alone`. Any other
line makes `add()` print `check: the step list is malformed: add <args>` and exit with code 2, as today. The marks mean:

- `jq`: in the Ubuntu job, the step runs in `@with-jq`, before jq is hidden (iteration 60 decision 5). In Git Bash it
  runs like any other step.
- `nogitbash`: the step runs in no Git Bash part. The Ubuntu job runs it (iteration 66 decision 3).
- `alone`: the step gets a Git Bash part of its own (iteration 66 decision 5, rule 1).

Exactly these eight lines change their marks, and every other line keeps its own:

```
add bash smoke-check.sh alone
add bash smoke-json.sh jq
add bash smoke-release.sh alone
add bash smoke-slot.sh first alone
add bash smoke-status.sh alone
add bash smoke-validate.sh alone
add bash test-guard-rules.sh alone
add bash test-lintcopy-output.sh slow nogitbash
```

A new test is one line, `add bash <file>`, with no mark: it then runs in the Ubuntu job's `@without-jq` and in the
packed Git Bash part. It still needs a map line (map rule 3, decision 11). A mark is added only when a spec says so,
and the pins of decision 6 then change with it.

**2. The bash lines are in name order** (the implementer's, `tests/check.sh`). `add lint lint` stays the first line.
The 48 `add bash` lines are sorted by name in `LC_ALL=C` order (the order of the table in decision 3), and a new line
goes in at its place. *Why*: when every new line goes in at the end, two pull requests that add a test always conflict,
just as they did on the workflow's lines. In name order they conflict only when both new names fall between the same
two existing names (Risks). The order has no other effect: lines marked `first` still start first, and the check still
prints its results in list order.

**3. The groups and the parts** (the implementer's, `tests/check.sh`). Before `--only` or `--within` reads its list,
`tests/check.sh` replaces each element that begins with `@` by the steps of that group, in list order. Every other
element stays a step name, as today. A group holds `bash` steps only, never the lint or a claude step:

- `@with-jq`: the bash steps marked `jq`.
- `@without-jq`: the bash steps not marked `jq` (the `nogitbash` steps included).
- `@gitbash-<k>`: Git Bash part `<k>`. **The parts are derived from the marks.** Let A be the number of steps marked
  `alone`. Parts 1 to A are those steps, one each, in list order. Part A + 1 holds every other bash step that is not
  marked `nogitbash`, in list order, provided there is at least one. N, the number of parts, is A or A + 1. There is
  one packed part, never more: this replaces iteration 66 decision 5 rules 2 and 3 (decision 7, which quotes them).

The errors, each followed by the usage line and exit code 2, as `no step named` is today:

- an `@` name that is none of these groups, `@gitbash-0` and `@gitbash-x` included: `check: no group named <x>`;
- `@gitbash-<k>` with a whole number k > N: `check: no Git Bash part <k> (the step list makes <N>)`;
- a group with no step, such as `@with-jq` in a fixture with no `jq` line: `check: the group <x> has no step`.

A name in both a group and the list, or in two groups, counts once (sel and `w_in` are set once, as for a name given
twice today). The fallback of `--affected --within` (`mode=only; only=$within`) expands the groups in the same way.
The `check: only <names>` line and the `Selection:` section name the expanded steps.

With the list of decision 1, N is 7, as the name `of 7` already says:

| Part | Steps |
|---|---|
| 1 | `smoke-check.sh` |
| 2 | `smoke-release.sh` |
| 3 | `smoke-slot.sh` |
| 4 | `smoke-status.sh` |
| 5 | `smoke-validate.sh` |
| 6 | `test-guard-rules.sh` |
| 7 | the other 41, from `smoke-control.sh` to `test-worker-merge.sh`, in name order, without `test-lintcopy-output.sh` |

Iteration 66 numbered the alone parts by measured time, largest first. From this iteration on, they are numbered in
list order. The 47 steps and the parts' contents stay the same; only the numbers 1 to 6 change.

*Fixtures.* `NIGHTMILL_CHECK_STEPS` gets a seventh tab field: the CI marks, a space-separated subset of
`jq nogitbash alone` in that order (empty: none). Any other value prints
`check: <file>: the seventh field is a subset of jq nogitbash alone, in that order, not <x>` and exits with code 2.
`add()` then applies decision 1's rules to the fixture line, so a mark on a lint fixture line, or `nogitbash alone`
together, is malformed. The header comment (lines 1 to 44) is updated as follows:

- the usage names `<step or @group>`;
- `--only` says CI runs its smoke jobs with groups;
- the line format gains the three marks;
- a paragraph says what the groups and parts are;
- the fixture field is described;
- "tests/lint.sh reads it and fails on a smoke script that is not in it" becomes "fails on a test file that runs
  nowhere".

`USAGE` (line 50) becomes
`usage: tests/check.sh [--quick | --only <step|@group>[,...] | --affected [--within <step|@group>[,...]]] [--jobs <1-16>] [--summary <file>]`.

**4. The workflow** (the implementer's, `.github/workflows/ci.yml`). Exactly:

- `smoke-bash`, line 39:
  `      - run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT @with-jq`. Line 44:
  `      - run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT @without-jq`. The step `Hide jq` between
  them stays.
- `smoke-gitbash-part`: the lines from `        include:` to the last `only:` line (lines 56 to 70) become the two lines
  `        # Part <k> runs the group @gitbash-<k> of tests/check.sh: its steps marked alone, one part each, then the rest.`
  and `        part: [1, 2, 3, 4, 5, 6, 7]`. In the run line (line 77), `${{ matrix.only }}` becomes
  `@gitbash-${{ matrix.part }}`.
- Nothing else in the file changes: no job name, no comment line 47 to 49 or 80, no timeout and no
  `continue-on-error` line. Those lines are #390's (decision 8).

This replaces iteration 66 decision 5's jobs block "written exactly so", its `include:` / `only:` lists and its run
line with `${{ matrix.only }}` (decision 7). No step name is left in the file. The part count is still written in the workflow (`of 7` and the matrix line), and the
lint compares it with the count derived from the step list (decision 6). It changes only when a spec changes the
`alone` marks.

**5. The lint** (the implementer's, `tests/lint.sh`).

*Removed* (they only compared the two lists):

- `chk_only` (lines 1321 to 1337) and its call (lines 1353 to 1356);
- the list part of the two-line rule (lines 1338 to 1352).

*Changed*:

- **The bash job's two lines.** The `smoke-bash` job has exactly two lines whose text, after the indent and an optional
  `- `, begins with `chk_sel`. The first is `chk_sel` followed by `@with-jq` and comes before the `- name: Hide jq` line.
  The second is `chk_sel` followed by `@without-jq` and comes after it. Otherwise:
  `FAIL: .github/workflows/ci.yml: the bash smoke job does not run tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT @with-jq, then @without-jq after it hides jq`.
- **The step-list pattern** (line 1250) becomes
  `^add (lint|bash) [A-Za-z0-9._-]+( first)?( slow)?( jq)?( nogitbash)?( alone)?$`. A line that begins `add lint ` and
  carries `jq`, `nogitbash` or `alone`, or a line with both `nogitbash` and `alone`, also makes the list "missing or
  malformed" (the existing text).
- **`firsts`, `chk_slows` and the `# Time: ` loop** read a mark as any field from the fourth on, not as the end of the
  line. `firsts` becomes the names of the lines that carry `first`, joined with `|`, and `want_firsts` becomes
  `smoke-slot.sh|test-spec-template.sh|`; the FAIL text stays. `chk_slows` and the loop take the lines that carry
  `slow`. The texts and `want_slows` stay.
- **Smoke files and test files.** The loop at lines 1276 to 1282 now covers every `tests/smoke-*.sh` and every
  `tests/test-*.sh`:
  - a name that is a bash step more than once still fails with `FAIL: tests/check.sh runs tests/<b> more than once`;
  - a `smoke-*.sh` that is no step still fails with `FAIL: tests/check.sh does not run tests/<b>`;
  - a `test-*.sh` that is no step fails only when no line of `tests/lint.sh` that is not a comment (its first non-blank
    character is not `#`) contains `bash tests/<b>`. The text is
    `FAIL: tests/<b> runs nowhere: it is no step of tests/check.sh and tests/lint.sh does not start it`.

  The names `tests/lint.sh` starts are collected in one `awk` pass (bug #270).

*New*, in `== the check runs every smoke script`:

- **No step name in the workflow** (criterion 1). Each bash step name of the step list (`$3` of `chk_block`) that occurs
  anywhere in `.github/workflows/ci.yml`, comments included, gives
  `FAIL: .github/workflows/ci.yml names the step <name> (CI takes its steps from the step list of tests/check.sh)`, once
  per name. One `awk` pass reads the workflow, and the names are passed in a variable.
- **Name order** (decision 2). Walking the bash lines of `chk_block` in order, the first line whose name is not after
  the previous name in `LC_ALL=C` order gives
  `FAIL: tests/check.sh: the bash steps of the step list are not in name order: <name> comes after <previous>`, once.
  The comparison is done in `awk` with `LC_ALL=C`, with no process per line.

*Comments.* The section comment (lines 1238 to 1242) says that CI runs its smoke jobs through the groups, that no step
is named in the workflow, that the bash lines are in name order, and that a test file must run somewhere. The comment of
`== the CI parts are well formed` (lines 1475 to 1478) says that rule 11 pins the marks and the part count.

*Kept as they are*: the `--only|--affected` rule (lines 1357 to 1360), the rule against running a smoke file outside
the check (lines 1361 to 1364), the required-name loops (lines 1365 to 1375, #390's), map rule 3 and every other rule of
the map, and `== CI selects the steps a pull request affects`. No `lint_break` is added to `tests/lint.sh` itself: the
cases are in `tests/smoke-check.sh` (decision 9).

**6. `tests/test-ci-parts.sh`** (the tester's).

- **Rule 10a, the matrix.** The rule reads the lines of the part job from `      matrix:` up to the next line indented by
  six spaces or fewer. Leaving out comment lines, this block must be exactly one line
  `        part: [<k1>, <k2>, ...]`: whole numbers, each separated by a comma and one space. Otherwise `<what>` is
  `the matrix is not one line 'part: [1, 2, ..., <N>]'`; an `include:` or `only:` line also gives this text. `<N>` is
  not literal: it is replaced by the number of parts derived from the step list (n of rule 11b), so on today's list the
  text reads `the matrix is not one line 'part: [1, 2, ..., 7]'`. The checks
  `fewer than two parts`, `the name says <n> parts, the matrix has <m>` and `the part numbers are not 1 to <m> in order`
  now read that list. The `part`/`only` pair parsing and the text `the part and only lines are not in pairs` go. This
  replaces iteration 66 decision 7 rule 10a's `- part:` / `only:` pairs (decision 7).
- **Rule 10a, the run line.** `GBRUN` becomes
  `run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT @gitbash-${{ matrix.part }}`. In the text
  `the run step is not a run: <the line> in a step with ...`, `<the line>` is that new line. Everything after
  `in a step with` is whatever the rule says when this iteration is implemented (decision 8). This replaces iteration
  66 decision 7 rule 10a's run line `... $CHECK_SELECT ${{ matrix.only }}` (decision 7).
- **Rule 11, replaced.** It reads the bash lines of the step list. The texts start `FAIL: tests/check.sh: ` unless
  marked otherwise.
  - *11a, the pins.* The variables become `gitbash_jq='smoke-json.sh'`, `gitbash_out` (unchanged) and
    `gitbash_alone`, which holds the six names of decision 1 in name order. For each mark (`jq`, `nogitbash`, `alone`),
    when the set of steps carrying it is not exactly its variable:
    `the steps marked <mark> are not exactly <the variable's names, comma-separated> (<source>): <the marked names, comma-separated, or none>`.
    The source is `docs/specs/iteration-60-ci-affected-jobs.md, decision 5` for `jq`,
    `docs/specs/iteration-66-gitbash-job-time.md, decision 3` for `nogitbash`, and
    `docs/specs/iteration-66-gitbash-job-time.md, decision 5` for `alone`.
  - *11b, the count.* Only when the matrix parses: n is the number of `alone` steps, plus 1 when some bash step is
    neither `alone` nor `nogitbash`. When the matrix has m parts and m differs from n:
    `FAIL: .github/workflows/ci.yml: the matrix has <m> parts, the step list of tests/check.sh makes <n>`.

  The texts that name a part's list go with the lists: `runs in no Git Bash part`, `more than one Git Bash part`,
  `names tests/<x>, which is not a bash step`, `not in the order of the step list`, `which the Git Bash job leaves out`,
  `shares its part`, `the Git Bash job leaves out tests/<x>, which is not a bash step` and `is to run alone, but`.
- **The header** (lines 2 to 18) says what 10a, 10b and the new rule 11 pin, naming iteration 70.

**7. What this replaces in earlier specs** (those specs are not edited; from now on, this spec is the rule):

- iteration 55 decision 3 ("`tests/check.sh` does not learn parts ... no group field in the step list"), and its echo
  in iteration 66 decision 5 ("`tests/check.sh` does not change: no part option, no group field"). The story's criterion
  2 asks for the opposite.
- iteration 42 decision 11 rule 6, iteration 55 decision 5 (first bullet) and iteration 60 decision 8 rule 5: the rules
  on the `--only` lists of `smoke-bash` (decision 5);
- iteration 66 decision 5's jobs block, "written exactly so" (`docs/specs/iteration-66-gitbash-job-time.md` lines
  400 to 426: "`<N>` the number of parts, one `- part:` / `only:` pair per part, `<list k>` part `k`'s steps
  comma-separated"), with its `include:` line (line 415), its `- part: <k>` / `only: <list k>` pairs (lines 416 to 419)
  and its run line `run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT ${{ matrix.only }}` (line
  426). Replaced by decision 4: the matrix is the one line `part: [1, 2, ..., <N>]` (on today's list
  `part: [1, 2, 3, 4, 5, 6, 7]`) under one comment line, and the run line ends `$CHECK_SELECT @gitbash-${{ matrix.part }}`.
  The rest of the block stays as it is on `main` (with #390's changes, decision 8);
- iteration 66 decision 7 rule 10a (lines 497 to 508), its matrix and run-line parts: "at least two parts, the
  `- part:` and `only:` lines in pairs, `<n>` equal to the number of parts" (lines 499 and 500), the run line
  "`run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT ${{ matrix.only }}`" (line 502), and the
  `<what>` texts `the part and only lines are not in pairs` (line 506) and the run-step text (line 508). Replaced by
  decision 6's rule 10a: the matrix is exactly one line `part: [<k1>, <k2>, ...]`, the `<what>`
  `the matrix is not one line 'part: [1, 2, ..., <N>]'` takes the place of the pairs text, and the run line is
  `run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT @gitbash-${{ matrix.part }}`. Its other
  checks (the name line, `fewer than two parts`, `the name says <n> parts, the matrix has <m>`, the part numbers 1 to
  `<m>` in order, one run step) stay, reading the one-line list;
- iteration 55 decision 3's jobs, "written exactly so" (`docs/specs/iteration-55-ci-parallel-powershell.md` lines 141
  to 168, an `include:` matrix of `- part: <k>` / `only: <list>` pairs and the run line `... --only ${{ matrix.only }}`),
  and its decision 5 rule 1 ("M pairs of lines `- part: <k>` / `only: <list>`", lines 238 to 240): the pattern that
  iteration 66 copied for the Git Bash parts. The PowerShell job went with iteration 68 (#365); with this iteration the
  pattern goes from the Git Bash parts too, replaced by decisions 4 and 6 as above;
- iteration 66 decision 7, rule 11, and decision 5's numbering of the alone parts "in order of `t`, largest first"
  (decisions 3 and 6). Decision 5's choice of which steps run alone, and decision 3's choice of which step is off Git
  Bash, stay: they are pinned in rule 11a;
- iteration 66 decision 5 rules 2 and 3 (`docs/specs/iteration-66-gitbash-job-time.md` lines 388 to 395). Rule 2:
  "**Packed.** The other steps go into `P` further parts, by largest first: sorted by `t`, largest first (equal `t`:
  list order), each step goes into the packed part with the smallest sum of `t` so far (equal sums: the lower part
  number). `P` is the smallest number from 1 up for which every packed part's sum of `t` is at most **48m00s** (4 steps
  at a time for 12 minutes) and its largest `t` below 12m00s." Rule 3: "**How many.** `N` is the number of alone parts
  plus `P`, at least 2 and at most **10**. When the rule gives more than 10, `P` becomes `10` minus the alone parts and
  step 2 runs again with that `P` and no 48m00s limit. When it gives 1, `P` is 2." Both are replaced by the rule of
  decision 3: **one packed part, so N is the number of alone steps or that plus one.** On today's list the two agree
  (the measurement of iteration 66 gave `P` = 1 and `N` = 7, its `## Measurements`, lines 232 to 234), so no part
  changes its steps. The consequence: the marks can no longer express more than one packed part. When a measured chain
  needs a second packed part (the packed part's sum of `t` over 48m00s, or the Git Bash chain over its budget because of
  it), that is a change to this rule, in a spec of its own; it cannot be done by moving marks (Not done). The bounds of
  rule 3 go with it: N is no longer raised to 2 or capped at 10 by a rule of the split; rule 10a's `fewer than two parts`
  still fails a matrix of one part;
- iteration 62 decision 7 (the `--only` lists name every step): there are no lists left.

**8. #390 (iteration 69) and the order of the merges.** This spec does not depend on #390, and #390 does not depend on
it. Each states its rules by content; the line numbers in this spec are those of `main` at 4395b13. The pull request
that merges second is rebased on `main`, and its implementer reads again every place this spec names, finding it by
content.

- **#390 merges first.** The run step's text ends `in a step with shell: bash` (iteration 69 decision 1), and the rule
  fails on any `continue-on-error:` line in the part job. This iteration then changes only the part of the text before
  `in a step with`. Its cases leave alone #390's `gbcoe`, `gbjobcoe`, `gbcoeexpr`, `gbcoefalse`, `gbshell`, `gbfname`
  and `gbfrename`; their sed lines match the step's `- shell: bash` line, not the run line or the matrix. In `ci.yml`,
  the line `continue-on-error: true` is already gone, so decision 4 changes the matrix and the run line only. The
  sentence in `README.md` (decision 10) is applied to #390's new sentence.
- **This iteration merges first.** The part job then has `part: [1, ..., 7]` and the run line
  `... $CHECK_SELECT @gitbash-${{ matrix.part }}`. Iteration 69's decision 1 text and its `Facts` name
  `${{ matrix.only }}`. When #390 is rebased, its rule's text is
  `the run step is not a run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT @gitbash-${{ matrix.part }} in a step with shell: bash`,
  and its `ci.yml` change removes `continue-on-error: true` above the new run line. That rebase is #390's work. This spec
  does not change iteration 69's spec, its required name, the final job, the parts' name or the timeout.
- **Either way**: the required names are not touched here (criterion 5), so #390's third name and its lint loops stand.
  The part count stays 7 and the parts' name stays `Git Bash smoke part <k> of 7`, so the budget comment of iteration 69
  decision 8 (seven parts, 47 steps, `of 51 steps`) holds unchanged. Only the step behind each of the part numbers 1 to 6
  changes (decision 3).
- An expected conflict: in `ci.yml`, #390's deleted line 76 is next to this iteration's changed line 77. In
  `tests/test-ci-parts.sh`, both change rule 10a's `gstep_end` and its text (lines 107 to 110 and 157). In `README.md`,
  both change the same paragraph. Each conflict is resolved by applying both rules, as above, never by dropping one.

**9. Who writes which file** (the tester guard: a file the tester wrote is the tester's as a whole, and the implementer
does not touch it).

- **The tester** writes `tests/test-ci-parts.sh` (decision 6 and its cases), `tests/smoke-check.sh` (the cases of
  Tests) and line 3 of `tests/test-ci-run-steps.sh`'s header (`--only ${{ matrix.only }}` becomes
  `$CHECK_SELECT @gitbash-${{ matrix.part }}`; its cases stay). On `main` the tests fail because the behaviour is
  missing. Rule 11a finds no marks and 11b's count, and 10a finds the `include:` matrix and the old run line. The new
  cases of `tests/smoke-check.sh` hit `no step named @with-jq` and the lint rules that do not exist yet.
- **The implementer** writes `tests/check.sh` (decisions 1 to 3), `.github/workflows/ci.yml` (decision 4),
  `tests/lint.sh` (decision 5) and `README.md` (decision 10), and never the tester's files or `CHANGELOG.md`. A dispute
  over a test goes back to the tester.
- **The `/next` session** adds the `CHANGELOG.md` bullet of Files touched (step 5 of `/next`, only when the changelog
  has no entry for iteration 70 yet).
- No new test file, so no new map line or lint start is needed.

Files whose text a lint rule or a test reads, and which this change alters: `tests/check.sh` (read by the lint, by
`tests/test-ci-parts.sh`, `tests/test-ci-run-steps.sh` and `tests/smoke-check.sh`), `.github/workflows/ci.yml` (read by
the lint, `tests/test-ci-parts.sh`, `tests/test-ci-run-steps.sh`, `tests/test-ci-job-times.sh`,
`tests/test-ci-smoke-bash-timeout.sh` and `tests/smoke-check.sh`), `tests/lint.sh` (its sections are copied by
`tests/smoke-check.sh`, and it is read by the new rule of decision 5), and `CHANGELOG.md` (read by
`tests/test-changelog-refs.sh` and `tests/test-changelog-coverage.sh`). `tests/test-ci-job-times.sh` and
`tests/test-ci-smoke-bash-timeout.sh` read only the final job's steps and `smoke-bash`'s timeout, and pass unchanged.

**10. The README** (the implementer's). In `## Developing nightmill` (line 1118), the clause "the lint fails when a bash
step runs in no Git Bash part or in two" becomes "the marks on the lines of the step list in `tests/check.sh` say which
steps run alone and which run on Ubuntu only, and every CI job takes its steps from that list, so a new test is one
line there (and one line in the map of `tests/check.sh`)". The rest of the paragraph stays (#390 rewrites the clause
before it).

**11. Criterion 3 is met only in part, and the rest is a story of its own** (accepted by the maintainer in the review
of this spec: "Accept partial, file a story"). A new test is one line in the step list and nothing in `ci.yml`. Map
rule 3 (`tests/lint.sh` lines 1415 to 1421, "every bash step is named by a map line") still asks for a map line, so a
pull request that adds a test changes two lines outside the test, and the story's verification ("changes one line
outside the test") is not met. The map decides which steps a pull request runs, which the story puts out of scope, so
this spec does not change map rule 3. *Rejected*: taking map rule 3 in here (a default map entry for a step no map line
names, or the rule dropped), which would widen the story into the map.

How criterion 3 is carried through `/next` (its steps 3, 5, 7 and 8):

- **The tester** writes no test for criterion 3. Its `Criteria` line for it reads
  `3. A new test file is added in one place, one line per test -> not tested: the map line of a new test is out of scope (decision 11)`.
  The part this spec meets (one line in the step list, nothing in `ci.yml`) is tested under criterion 1
  (`gbnewstep`, `steporder`; Tests).
- **The implementer** writes no test for criterion 3 either (the `not tested` line asks for one, but there is no
  behaviour of this spec to protect: the rest is the map line, out of scope) and reports `Result: partial`, with the
  `Criteria` line `3 not met (decision 11: the map line)` and under Left the line
  `criterion 3: the map line of a new test (map rule 3) is a story of its own (decision 11)`. There is no `unmet:` path
  (no test of it to set aside) and no `Disputes:` line (`Disputes: none`). Every other criterion is met and committed,
  so the tree check of step 3 finds a clean tree and a commit.
- **The `/next` session** reads that `partial`: step 5 stashes nothing; step 7 enables no auto-merge (it is withheld
  for `ci.yml` and for the partial result alike); step 8 files the rest with `/story` as a new story under epic #337,
  "A new test needs no line in the map of `tests/check.sh`", whose criterion is that a pull request that adds a test
  changes one line outside the test, unless the maintainer has filed one already (then it links that one). Both issues
  are linked, and the pull request says so and still closes #343.
- **The pull request body** never ticks criterion 3. Its "How verified" carries the tester's line as written, with
  `; tested by the implementer: none (decision 11)`, and the body carries the open line
  `- [ ] 3. A new test file is added in one place, one line per test: not met: a new test is one line in the step list and nothing in ci.yml, but map rule 3 still asks for a line in the map of tests/check.sh (#<new story>)`.
- `complete` is not reported: the skill forbids ticking a criterion that was not met, and an open criterion with a
  rest to file is the `partial` case.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | CI takes the steps of each job from the check's step list; no step name is written in the workflow file | Decisions 3 and 4; decision 5 (no step name in the workflow, the bash job's two lines) |
| 2 | The split of the steps into the Git Bash parts is derived, or stated in the step list itself (the story's "PowerShell steps", read for the CI of today: Facts) | Decisions 1 and 3 (the marks `alone` and `nogitbash`, the parts derived from them); decision 6 (rule 11a pins the marks, rule 11b the count); decision 7 |
| 3 | A new test file is added in one place, one line per test | **Met in part, as the maintainer accepted in the review of this spec** (decision 11). Met: a new test is one unmarked line in the step list, in name order, and nothing in `ci.yml` (decisions 1 and 2), tested under criterion 1. Not met: it still needs one map line in `tests/check.sh` (map rule 3, which belongs to the map, out of scope). The tester's line is `not tested: the map line of a new test is out of scope (decision 11)`; the implementer reports `Result: partial` with `3 not met (decision 11: the map line)`, no `unmet:` path and no dispute; `/next` files the map line as a story under epic #337 and never ticks criterion 3 (decision 11, Left 2) |
| 4 | The lint rules that only compared the two lists are removed; a test file that is in no list still fails the lint | Decision 5 (removed and changed rules, test files that run nowhere); decision 6 (rule 11 replaced) |
| 5 | The required job names do not change | Decision 4 (no `name:` changes); decision 8 (#390's name, in either order) |

## Tests

- Criterion 1:
  - **`tests/lint.sh`** on the checkout: no step name in `ci.yml`, and the bash job's two lines name `@with-jq` and
    `@without-jq`.
  - **`tests/smoke-check.sh`**, in `== the lint: the check runs every smoke script`. The cases `cibash`, `cijson`,
    `ciswap` and `cijsondirect` go. New cases:
    - `cistepname`: `ci.yml` `s/\$CHECK_SELECT @with-jq$/$CHECK_SELECT smoke-json.sh/`, which expects
      `FAIL: .github/workflows/ci.yml names the step smoke-json.sh`;
    - `cistepcomment`: `ci.yml` `$a\` `# smoke-hook.sh`, which expects `names the step smoke-hook.sh`;
    - `cigroups`: in `ci.yml`, swap the two groups on the two lines (`s/@with-jq$/@X/; s/@without-jq$/@with-jq/; s/@X$/@without-jq/`),
      which expects `the bash smoke job does not run tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT @with-jq, then @without-jq after it hides jq`.
  - **`tests/smoke-check.sh`**, a new section `== groups`, on fixture steps (`NIGHTMILL_CHECK_STEPS`, `--jobs 1`). The
    fixture has seven lines: `a` (kind lint), `b` (marked `jq`), `c` (`alone`), `d` (no mark), `e` (`nogitbash`), `f`
    (`alone`) and `g` (no mark). The cases:
    - `--only @with-jq` runs `b` only;
    - `--only @without-jq` runs `c d e f g`, not `a`;
    - `--only @gitbash-1` runs `c`, `@gitbash-2` runs `f`, and `@gitbash-3` runs `b d g`;
    - `--only @gitbash-1,d` runs `c d`;
    - `--only @gitbash-4` exits with code 2 and prints `check: no Git Bash part 4 (the step list makes 3)`;
    - `--only @nope` exits with code 2 and prints `check: no group named @nope`;
    - `--affected --within @gitbash-3`, with a map line that selects `d` and a changed path on it
      (`NIGHTMILL_CHECK_MAP`, `NIGHTMILL_CHECK_PATHS`), runs `d` only;
    - a fixture with no `jq` line: `--only @with-jq` exits with code 2 and prints `check: the group @with-jq has no step`;
    - seventh fields `nogitbash alone`, `alone jq`, and `jq` on a lint line each exit with code 2;
    - on the real list, `bash tests/check.sh --only @gitbash-8` exits with code 2 and prints
      `check: no Git Bash part 8 (the step list makes 7)`.

    CI shows that the jobs run the expanded groups: each part's `check: only ...` line or `Selection:` section.
- Criterion 2: **`tests/test-ci-parts.sh`**. The rules pass on the checkout. Each case goes through `gb_case`, `mkcase`
  with `changed`, and `expect_gb`, as today:
  - `gbnumbers`: `s/part: \[1, 2,/part: [2, 1,/`, which expects `the Git Bash parts are malformed`;
  - `gbinclude`: after the `part:` line, add `        include:`, which expects `the matrix is not one line`;
  - `gbonlyback`: after the `part:` line, add `        only: x`, with the same expectation;
  - `gbeight`: the name `of 8` and `part: [1, 2, 3, 4, 5, 6, 7, 8]`, which expects
    `the matrix has 8 parts, the step list of tests/check.sh makes 7`;
  - `gbonlyrun`: the run line back to `${{ matrix.only }}`, which expects `the Git Bash parts are malformed`;
  - `gbnewalone`: in `tests/check.sh`, add `add bash smoke-new.sh alone`, which expects
    `the steps marked alone are not exactly` and `makes 8`;
  - `gbunalone`: in `tests/check.sh`, `s/^add bash smoke-check\.sh alone$/add bash smoke-check.sh/`, which expects
    `the steps marked alone are not exactly` and `makes 6`;
  - `gbnojq`: in `tests/check.sh`, remove ` jq`, which expects `the steps marked jq are not exactly smoke-json.sh`;
  - `gbout` (`gitbash_out=smoke-nope.sh`) and `gbalonenope` (`smoke-nope.sh` added to `gitbash_alone`) now expect the
    texts of rule 11a for `nogitbash` and `alone`.

  `gbgone`, `gbubuntu`, `gbdepth`, `gbif`, `gbcoe`, `gbshell`, `gbtwo`, `gbname`, `gbneeds`, `gbfailfast` and `gbof`
  stay, with #390's changes if it merged first. The cases of 10b stay. `gbnoguard`, `gbgate2`, `gbnostep`, `gborder`,
  `gblintcopy` and `gbalone` go. `tests/test-ci-run-steps.sh` passes with only its header line changed. The check's
  derivation of each part's steps is tested by `== groups` (criterion 1).
- The part of criterion 3 this spec meets (one line in the step list, nothing in `ci.yml`), tested under criterion 1
  in the tester's `Criteria` lines: **`tests/test-ci-parts.sh`**, `gbnewstep` becomes: add `add bash smoke-new.sh` (no
  mark) in name order in the copy of `tests/check.sh`. The rules then print exactly what they print for the checkout
  (`o` equals `out`), so one line in the step list puts a test in the check and in every CI job.
  **`tests/smoke-check.sh`**, in the lint section:
  - `steporder`: delete `add bash smoke-check.sh alone` and add it again before `# steps: end`, which expects
    `the bash steps of the step list are not in name order: smoke-check.sh comes after test-worker-merge.sh`;
  - the real-list section (lines 598 to 609) matches the whole lines `add bash smoke-slot.sh first alone`,
    `add bash test-spec-template.sh first` and `add bash test-lintcopy-output.sh slow nogitbash`, and the `sed` strip
    goes.

  The code reviewer checks, with `git diff origin/main -- tests/check.sh`, that the step list holds the same 49 steps
  with the marks of decision 1.
- Criterion 3: **not tested** (decision 11). The tester's line is
  `3. A new test file is added in one place, one line per test -> not tested: the map line of a new test is out of scope (decision 11)`,
  and neither the tester nor the implementer writes a test for it: map rule 3 stays, so the story's "one line outside
  the test" stays unmet, and no test claims it. The implementer's `Criteria` line is
  `3 not met (decision 11: the map line)`.
- Criterion 4: **`tests/smoke-check.sh`**, in the lint section:
  - `slowformat`: `s/^add bash test-lintcopy-output\.sh slow nogitbash$/add bash test-lintcopy-output.sh nogitbash slow/`,
    which expects `missing or malformed`;
  - `slowset`: `s/^\(add bash test-lintcopy-output\.sh\) slow nogitbash$/\1 nogitbash/`, which expects
    `the steps marked slow are not exactly`;
  - `marklint`: `s/^add lint lint$/add lint lint jq/`, which expects `missing or malformed`;
  - `markboth`: `s/^add bash smoke-check\.sh alone$/add bash smoke-check.sh nogitbash alone/`, which expects
    `missing or malformed`;
  - `testtwice`: `/^add bash test-json-bom\.sh$/p`, which expects `runs tests/test-json-bom.sh more than once`;
  - `testnowhere` (like `mapscript`): `: > tests/test-zz-nowhere.sh` in the copy, which expects
    `FAIL: tests/test-zz-nowhere.sh runs nowhere`;
  - `missing`, `twice`, `nofile`, `cidirect`, `cirename` and `cibegins` stay.

  The removed rules appear in no case: the code reviewer checks that `chk_only` is gone from `tests/lint.sh`.
- Criterion 5: `tests/lint.sh` on the checkout (the required-name loops, unchanged), and `cirename` and `cibegins`. The
  code reviewer checks that the diff of `ci.yml` touches no `name:` line and only the lines of decision 4.
- **The tester** runs `bash tests/test-ci-parts.sh` and `bash tests/smoke-check.sh`, which fail on `main` as decision 9
  says. **The implementer** runs both, then `bash tests/lint.sh` and the full check before the commit (`tests/check.sh`
  and `ci.yml` are shared paths, so `--affected` would run the full check anyway). On the pull request's run, every
  job's log shows the expanded groups, and `Lint (generic, JSON, skills, shell)` and `bash scripts smoke tests` are
  green.

## Files touched

- `tests/check.sh` (the implementer): the marks in `add()`, the sorted step list with the eight marked lines, the
  expansion of the groups, the derived parts, the seventh fixture field, `USAGE` and the header (decisions 1 to 3).
  About 200 changed lines, half of them from the sort.
- `.github/workflows/ci.yml` (the implementer): lines 39 and 44, the matrix, and the run line (decision 4). About 20
  changed lines (the 15 matrix lines become 2).
- `tests/lint.sh` (the implementer): the removed list rules, the changed and new rules, and two comments (decision 5).
  About 100 changed lines.
- `tests/test-ci-parts.sh` (the tester): rules 10a and 11, the header, and the cases (decision 6, Tests). About 180
  changed lines.
- `tests/smoke-check.sh` (the tester): the lint cases, the real-list section and `== groups` (Tests). About 100 changed
  lines.
- `tests/test-ci-run-steps.sh` (the tester): header line 3.
- `README.md` (the implementer): one clause (decision 10).
- `CHANGELOG.md` (the `/next` session, step 5 of `/next`; the implementer does not touch it): one bullet under
  `## Unreleased`, below the newest iteration bullet:

  ```
  - Iteration 70 (#343): CI takes every smoke job's steps from the step list of tests/check.sh: the Ubuntu job runs the
    groups @with-jq and @without-jq, Git Bash part k the group @gitbash-k, and the marks jq, nogitbash and alone on a
    step's line say where it runs; the bash lines of the list are in name order, so a new test is one line in the
    step list and none in the workflow (it still needs a map line). The lint no longer compares the workflow's lists with the step list; it fails on a step name in the
    workflow and on a test file that runs nowhere. No config key.
  ```

Not touched: `tests/check.ps1`, the affects map and map rule 3, `tests/test-ci-job-times.sh`,
`tests/test-ci-smoke-bash-timeout.sh`, `tests/test-ci-summary.sh` and its fixtures, every job name, comment, timeout
and `continue-on-error` line of `ci.yml`, `.claude/CLAUDE.md`, `CONTRIBUTING.md`, every file under `scripts/`,
`skills/`, `agents/`, `hooks/`, `templates/` and `schema/`, `.claude/nightmill.json`, `docs/decisions/`, and the specs
of iterations 42 to 69.

## Risks

- **Two new tests can still conflict.** This happens when their names fall between the same two existing names in name
  order. That is much rarer than today's every time, but it can happen. The conflict is one line in a sorted list and is
  resolved by keeping both lines in order.
- **The map line.** A new test still needs a map line (rule 3), and two pull requests that map tests to the same script
  edit the same map line. Criterion 3 is therefore met only in part, as the maintainer accepted: the pull request is
  `partial`, so it is not auto-merged for that reason too, and the map line becomes a story of its own under epic #337
  (decision 11, Left 2).
- **The sort changes the start order** of the local check after the steps marked `first`: the long `smoke-*` steps now
  start before the `test-*` steps. With L = 4 the total can move by a few seconds either way. CI's parts start their
  steps in the same derived order.
- **The part numbers move.** A reader who compares part times with runs before this iteration sees other steps behind
  parts 1 to 6 (decision 3, table). The steps themselves and their total stay the same.
- **A group typo in the workflow** (`@gitbash-${{ matrix.part }}` with a part beyond N) fails the part with exit code 2
  instead of running nothing. Rule 11b keeps the matrix equal to N.
- **The rebase against #390** (decision 8): three files conflict. The rules are stated by content, and the second pull
  request rebases and re-reads.

## Size estimate

`L`: about 600 changed lines (`tests/check.sh` 200, `tests/test-ci-parts.sh` 180, `tests/lint.sh` 100,
`tests/smoke-check.sh` 100, `ci.yml` 20, README 3, CHANGELOG 5). The sort alone accounts for about 100 of them.

## Not done

- Which steps a pull request runs: the affects map, its lint rule 3 (a new test still names itself in a map line), and
  the `shared tests/check.sh` line that makes a pull request adding a test run every step. The story puts this out of
  scope; the map line is the rest of criterion 3 that `/next` files as a story of its own (decision 11).
- Deriving the number of parts in the workflow (a planning job with a dynamic matrix). It would add a job before every
  part, which the chain's 17-minute budget (iteration 66 decision 2, iteration 69) cannot afford. The count stays
  written in the workflow and is checked by rule 11b.
- Rebalancing the parts. Rebalancing by the old rules (iteration 66 decision 5 rules 2 and 3: `P` packed parts, largest
  first, under 48m00s) is not possible with the marks, which express one packed part only (decision 7). A second packed
  part is a change to decision 3's rule and a story of its own. Changing which steps run alone or off Git Bash, or
  measuring times, is a story of its own too.
- Anything of #390: `continue-on-error`, the final job's name, the timeout, the ruleset, the budget measurement.
- A `--list` option to print a group's steps, and parts for the Ubuntu job.
- Editing the specs of iterations 42, 55, 60, 62 and 66 (decision 7 replaces their rules), or the story's text (Left 1).

## Left

1. **The story's text is stale.** Its criterion 2 says "the PowerShell steps", and it ticks the invariant "Both shells".
   Both predate #365: there are no PowerShell steps left, and the invariant is "Bash only". This spec reads criterion 2
   as the split of the steps into the Git Bash parts (Facts, Criteria row 2). The maintainer may want to edit the issue
   to match.
2. **Criterion 3 is met only in part, accepted by the maintainer in the review of this spec** ("Accept partial, file a
   story"). A new test is one line in the step list for the check and every CI job, and nothing in `ci.yml`. Map rule 3
   still asks for a map line, so a pull request that adds a test changes two lines outside the test, not the one the
   story's verification names. The map decides which steps a pull request runs, which the story puts out of scope, so
   this spec leaves it alone (decision 11). The tester's line for criterion 3 is
   `not tested: the map line of a new test is out of scope (decision 11)`; the implementer reports `Result: partial`
   with `3 not met (decision 11: the map line)` and, under Left,
   `criterion 3: the map line of a new test (map rule 3) is a story of its own (decision 11)`, with no `unmet:` path and
   no dispute; `/next` never ticks criterion 3, the pull request body carries its open line, and step 8 files (or
   links) the story for the map line under epic #337, said so in the pull request, which still closes #343.
3. **Test files started by the lint.** Decision 5 extends the "in no list" rule from `tests/smoke-*.sh` to
   `tests/test-*.sh`, counting a start from `tests/lint.sh` as a list. Today a `test-*.sh` can run nowhere unnoticed;
   none does on this commit. If the maintainer reads criterion 4's "still" as "only the existing rule", the rule
   `runs nowhere` and its case `testnowhere` can be dropped.
4. **Name order** (decision 2) is this spec's choice for the goal's "do not conflict". It reorders the list once. If the
   maintainer prefers the list's current order, two pull requests that each add a test at the end will keep conflicting
   on the step list.
