# Iteration 46: after its pull request opens, /next, /fix and /spec watch its checks and fix a red one within review.maxFixRounds

Status: draft, awaiting approval (#145)

Story #145, epic #107 (Hardening from the code review), finding HI-9 of the review of 0.2.0. Today `/next`, `/fix`
and `/spec` open the pull request, decide auto-merge and stop, so a red pull request waits until the maintainer
notices it. After this iteration each of the three skills, once its pull request is open and auto-merge is decided,
watches the pull request's checks for at most 30 minutes per push (a fixed bound, no config key).
Green ends the run with one line and nothing else. Red starts a **check fix round**: the producer of the change (the
implementer, the fixer, the spec writer) gets the failing job's log, fixes the cause, runs the check and commits; the
reviewer of that role reviews the round; the session pushes and watches again. At most `review.maxFixRounds` check
fix rounds run. When they are used up, the session comments the failing job on the issue, adds the label `blocked`
and stops; it never forces a merge. The shared rule is in `skills/workflow/SKILL.md`, the role-specific steps in
`skills/next/SKILL.md`, `skills/fix/SKILL.md` and `skills/spec/SKILL.md`. Also changed: `README.md`,
`tests/test-watch-checks.sh` (new), `tests/check.sh`, `.github/workflows/ci.yml` and `CHANGELOG.md`. No script,
agent, hook, schema or config change.

## Story trigger and manual check

**Not a story trigger.** Of `escalation.storyTriggers`:

- *A change to the status flow or who sets a status*: no. The eight statuses, their order and who sets each stay as
  the table in `skills/workflow/SKILL.md` has them. A watched pull request stays at Review the whole time, whatever
  the checks show; the hand-over adds a label, which is not a status. No decision record is needed ("Fixed flow").
- *A new, renamed or removed config key*: no. The time bound is a fixed 30 minutes per watch (decision 1); the
  round bound is the existing `review.maxFixRounds`. The schema, `templates/nightmill.example.json` and the README's
  configuration table stay as they are.
- *A change to the slot marker format*: no. The new step names `watch-checks`, `check-fix-<k>`, `check-review-<k>`
  and `handed-over` (decision 9) are values of the existing `step` key, which `--report` already accepts (1 to 40
  letters, digits or `-`) and the previous version prints as it is.

**The manual check applies**: `skills` is in `verification.manualCheckPaths`, and four skills change. Its steps are
under Tests; because it applies, the implementation pull request does not enable auto-merge (`/next` step 7). No script in `scripts/` changes, so no smoke step is added and "Both shells" is not touched: every
command the skills run here is `gh` or `git`, the same in bash and PowerShell. `skills/workflow/SKILL.md` and
`schema/nightmill.schema.json` are in `parallel.hotFiles`: this story is not run at the same time as another story
that changes either.

## Facts this rests on

Read on `main` at 4407bd4 (iteration 40 merged). The issue was read against d13c9b5; the finding still holds on
4407bd4: no skill, agent or script outside `/status` reads a pull request's checks (`grep -rn "pr checks" skills
agents scripts` finds nothing; only `scripts/status.*` read `statusCheckRollup`, to show CI in `/status`).

- **What the skills do after the pull request opens.** `/next` step 6 opens it and sets Review, step 7 enables
  auto-merge or says why not, step 8 files the rest of a partial story, then the session reports `done` and ends.
  `/fix` step 6 does the same in one step. `/spec` step 4 opens the spec pull request and enables auto-merge (not with
  a blocking finding open), switches back to the branch it came from, step 5 sets Spec review and comments, step 6
  stops. The workflow skill, "CI and merging": "A red PR is fixed, never forced." No step does it.
- **Not every pull request gets auto-merge.** `/next` step 7 withholds it for a story trigger, a partial result, a
  required manual check that was skipped, blocking findings or an open dispute. A pull request that changes `skills`,
  `agents` or `hooks` needs the manual check and in practice waits for the maintainer: #247 (iteration 40, changes
  `skills/spec/SKILL.md` and `agents/spec-reviewer.md`) has `autoMergeRequest` null and was merged by the maintainer.
  So "after enabling auto-merge" alone would leave those pull requests unwatched (decision 2).
- **How long CI takes here.** `.github/workflows/ci.yml` runs four jobs on every pull request: the lint
  (`timeout-minutes: 5`), the bash smoke tests (7), the PowerShell smoke tests on `windows-latest` (38) and
  `claude plugin validate` (`continue-on-error: true`, 5). On #247 they took 25 s, 3 min 51 s, 6 min 8 s and 11 s.
  The failed PowerShell jobs of the runs of 2026-11-08 and 2026-11-09 took 6 to 8.5 min. The repository's runs say
  "up to about 10 minutes", the Windows job being the long one.
- **Red pull requests here** came from steps the machine that ran the skill could not run: ShellCheck and Windows
  PowerShell 5.1. `tests/check.sh` "runs what the machine can run and lists what it skipped" (0001), so a local green
  check does not prove a CI fix; only the next CI run does (decision 6).
- **`gh` 2.103.3** (installed, `gh pr checks --help`, read only): `--watch` "Watch checks until they finish",
  `--fail-fast` "Exit watch mode on first check failure", `-i, --interval int` "Refresh interval in seconds in watch
  mode (default 10)", `--required` "Only show checks that are required", `--json` with the fields `bucket,
  completedAt, description, event, link, name, startedAt, state, workflow`; `bucket` is one of `pass`, `fail`,
  `pending`, `skipping`, `cancel`. "Additional exit codes: 8: Checks pending"; `gh help exit-codes`: 0 success, 1
  failure, 2 cancelled, 4 authentication. `gh pr checks 247` printed four `pass` rows and exited 0; `--json` gave
  one object per check with `link` `https://github.com/<owner>/<repo>/actions/runs/<run>/job/<job>`. `gh run view`
  has `--job <id>` and `--log-failed` ("the log for any failed steps in a run or specific job").
- **Not checked here** (no pull request without checks was at hand, and nothing was pushed): what `gh pr checks`
  prints in the seconds after a push, before the new head has any check. gh's source prints
  `no checks reported on the '<branch>' branch` and exits 1 in that case; decision 4 does not depend on the exit
  code.
- **The Bash tool of Claude Code** runs one foreground call for at most 10 minutes (600000 ms). A watch longer than
  that is several calls (decision 4); no `timeout` command is needed, which macOS and PowerShell lack.
- **The label.** `/init`'s label table creates `blocked` (`000000`, "Waiting on another issue (name it in the
  body)") as a literal name; `labels` in the config and the schema have no key for it (`epic`, `story`, `bug`,
  `needsSpec`, `areaPrefix`, `priorityPrefix`). `gh label list` on this repository shows `blocked`. This spec uses
  the literal name as `/init` does (decision 8; Left, item 2).
- **`review.maxFixRounds`** (schema: integer, minimum 0, default 2; this repository 2) bounds the fix rounds after a
  review; the workflow skill's "Rounds" make a story reviewed at most `1 + review.maxFixRounds` times.
- **Iteration 44** (delivered): `/next N` at Review with an open pull request (row N1) sets Review, enables
  auto-merge when it is missing and reports `done`; `/spec N` rows S1 and R1 do the same for a spec pull request.
  A resumed run's review rounds start at round 0 with the full `review.maxFixRounds` (its decision 8).
- **The stage record** (iteration 41) shows every reported step name as its own stage and `ci-and-merge` from the
  pull request's open to its merge; new step names need no change there.

## Decisions

**1. The bound in time: 30 minutes per watch.** One **watch** waits at most 30 minutes, counted from the moment the
watch starts (after the pull request opened, or after a check fix round pushed). The number is written in the
workflow skill's rule, not in the config: the issue asks for a bounded time and names no key, and a new key would
be scope it does not ask for and a story trigger (Left, item 1). Why 30: three times the longest CI run this
repository sees, so a queued Windows runner does not end a watch early. Why per watch and not per run: each push
starts a new CI run, so the longest run of the skill is `(1 + review.maxFixRounds) × 30` minutes of watching (90 min
with `review.maxFixRounds` 2) plus the fix rounds. There is no way to turn the watch off.

**2. Which pull requests are watched.** Every pull request that `/next`, `/fix` (one bug) or `/spec` opened or, in a
resumed run (iteration 44 rows N1, S1, R1), reused, whether auto-merge is on or not. Why: a pull request without
auto-merge (a manual check, a story trigger, a partial result, blocking findings) waits for the maintainer's merge,
and the maintainer can merge only a green one; the issue's Goal is every red pull request opened by a skill. The
watch starts after the last step that today ends the run: `/next` after step 8, `/fix` after step 6, `/spec` after
step 5 (before the stop of step 6). Not watched: `/fix all` (Not done; Left, item 3), and a pull request whose
state is not `OPEN` when the watch starts (`gh pr view <pr> --json state`): `MERGED` prints the green line of
decision 5, `CLOSED` prints `PR #<pr> is closed; checks not watched.`

**3. Which checks count.** All checks that `gh pr checks <pr> --json name,bucket,link,workflow` lists for the pull
request's head, not only `--required` ones. A check whose `bucket` is `fail` or `cancel` is **red**; `pass` and
`skipping` are **done**; `pending` is **pending**. Why all: the skill fixes what it caused, and a project without
required checks would show none with `--required`. A non-blocking job that fails (this repository's validate job
has `continue-on-error: true`, so it reports `pass`) is still red; the producer may answer that it is not caused by
the change (decision 6, `failed`).

**4. One watch, exactly.** Before it, the session checks that the pull request's head is its own last commit:
`gh pr view <pr> --json headRefOid --jq .headRefOid` equals `git -C <checkout> rev-parse refs/heads/<branch>`, the
ref of the pull request's branch (not `HEAD`: `/spec` has switched its checkout back to the branch it came from);
otherwise it hands over at once (decision 8) with the reason `the branch on origin is not this run's last commit`. Then, while the
watch's time is not used up, one foreground shell call:
`gh pr checks <pr> --watch --fail-fast --interval 30`, with the shell tool's timeout set to the smaller of 10 minutes
and the minutes left. When the call returns (any exit code, or the tool's timeout), the session reads the verdict
with one call `gh pr checks <pr> --json name,bucket,link,workflow` and decides only from that JSON (never from an
exit code):

| JSON | Verdict |
|---|---|
| at least one red check | red: decision 6 with the first red check in the listing's order |
| no check at all (the output is `no checks reported ...` or `[]`) | pending |
| every check done | green: decision 5 |
| otherwise | pending |

Pending with time left: the next call. Pending with no time left: decision 7. A pending verdict whose watch call
returned in less than 30 s (no check exists yet after a push) is followed by `sleep 30` in the next call, before
`gh pr checks`, so the loop does not spin. Before each watch call the session reports `watch-checks` (decision 9),
so a slot shows `running` while it watches (`worktrees.stalledAfterMinutes` is at least 1 and every call is at most
10 minutes). The watch commits, pushes and changes nothing.

**5. Green.** Print `Checks of PR #<pr> are green (<n> checks); auto-merge <is on | is off: <the reason the pull
request gives>>.` and end the run as it ended before this iteration (`/next` and `/fix` report `done`; `/spec` goes
on with step 6). Nothing else: no comment, no label, no status, no merge, no slot release. A pull request with
auto-merge then merges by itself, and its `Closes #<issue>` / `Fixes #<issue>` sets Done as today (criterion 4).

**6. Red: one check fix round.** Check fix rounds are counted from 1 per run, apart from the review's fix rounds:
the review's rounds were spent on the review's findings before the pull request opened, and the issue bounds the CI
fixes by `review.maxFixRounds` on their own. When `k - 1` check fix rounds have run and `k ≤ review.maxFixRounds`,
round k is:

1. **The log.** From the red check's `link`, take `<job>` (the number after `/job/`) and `<run>` (after `/runs/`).
   `gh run view <run> --job <job> --log-failed`, its last 200 lines, is `<the log>`. A link that is not an Actions
   job link (another CI) gives `<the log>` = `not available: <the link>`.
2. **The checkout.** `/next` and `/fix` use the slot that holds the branch (it is held until the merge, as today).
   `/spec` switches its checkout back to the spec branch (`git switch <branch>`; the tree must be clean, else the
   hand-over of decision 8 with the reason `the checkout is not clean`) and switches back to the branch it came from
   at the end of the round.
3. **The producer.** Count the agents, check the room on the machine and report `check-fix-<k>`, as for every
   launch. Launch the producer of the role as a fresh agent, on its role's model, passed explicitly: in `/next` the
   implementer, with its prompt and, at the end, the paragraph below; in `/fix` the fixer, the same; in `/spec` the
   spec writer, with its prompt (saying "the spec file exists; change only what the failing check needs") and the
   paragraph. The paragraph:

   ```markdown
   The pull request #<pr> is open and its check <name> (<workflow>) is red (check fix round <k> of
   <review.maxFixRounds>). The log of its failed steps, last 200 lines:
   <the log>
   Fix the cause in this change, run the check, commit. The local check may skip the step that failed in CI (it runs
   what the machine can run); say so under Left when it did. If the failure is not caused by this change (the base
   branch, the CI runner, a flaky check), change nothing and return `failed` with the reason under Left.
   ```

   Then read the result as each skill reads its producer today: in `/next` and `/fix`, the tester's files first
   ("The tester's files", rule 3; a changed tester file undoes the round by rule 4, and the round counts), then the
   `Result:` block; in `/spec`, the form check of "The spec writer" step 4. A `Disputes:` line that is not `none` is
   not sent to the tester in a check fix round: it is a hand-over (decision 8, reason `the producer disputes the
   tester's test: <the Disputes line>`). `Result: failed`, no block, nothing committed, or an undone round is a
   hand-over with the reason `<Left, or why>`.
4. **The review.** Report `check-review-<k>`; one launch of the role's reviewer (`codeReviewer` in `/next` and `/fix`,
   `specReviewer` in `/spec`), as in "The code review" / "The spec review" step 2, with the prompt of step 3 there and
   the change given as `git diff <the pull request's head>..HEAD` (the round's commits only). The pairing is not
   checked again. No findings or advisory only: go on. A blocking finding: nothing is pushed; while a round is left,
   round k + 1 starts at step 3 with the same red check and, added to the paragraph, "Fix exactly these blocking
   findings too: <the lines>"; with no round left, the hand-over (decision 8) with the reason
   `the fix of round <k> has blocking review findings: <the lines>`. Why a review: a fix pushed to a pull request with
   auto-merge on merges as soon as it is green, so it must be reviewed before the push.
5. **The push** (no force): `git -C <checkout> push origin <branch>`. A rejected push is a hand-over with the reason
   `the push was rejected: <first line of git's message>`.
6. **The record.** One comment on the pull request:
   `gh pr comment <pr> --body "<text>"` with
   `Check fix round <k> of <review.maxFixRounds>: <name> was red. Fixed by the <role> role on <model>; reviewed by the <reviewer> role on <model>: <no findings | advisory findings: <the lines>>.`
   The pull request's body is not rewritten.
7. **Watch again**: a new watch (decision 4), with the full 30 minutes.

With `review.maxFixRounds` 0, or when round `review.maxFixRounds` was the last and its watch is red again, no round
runs: decision 8 with the reason `the rounds are used up`.

**7. The time runs out.** Pending at the end of a watch is not red, so nothing is labelled. The session comments on
the issue `Checks of PR #<pr> were still running after 30 min (pending: <names,
comma-separated>); <the skill> no longer watches them.` (only when no comment of the maintainer's login on the issue
already starts with `Checks of PR #<pr> were still running`), prints the same line, and ends the run as on green
(`done`; `/spec` step 6). Auto-merge, when on, still merges a pull request that goes green later.

**8. The hand-over.** In this order:

1. A comment on the issue, posted once (only when no comment of the maintainer's login on the issue starts with
   `Checks of PR #<pr> are red`):
   `Checks of PR #<pr> are red after <r> check fix rounds (review.maxFixRounds is <m>): <name> (<workflow>), <link>. <the reason>. Labelled blocked; the pull request is left as it is for the maintainer.`
   `<r>` is the number of rounds that ran; `<the reason>` is the reason named where the hand-over starts (decision 4
   or 6), for used-up rounds exactly `the rounds are used up`.
2. `gh issue edit <issue> --add-label blocked`. When it fails (the label does not exist in the repository), print
   `The label blocked could not be added: <the first line of gh's message>; /init creates it.` and go on.
3. Print the comment's text, report `handed-over`, and end the run. The board status stays Review; the slot stays
   taken, with the round's work as it is (an unpushed commit stays local); auto-merge is left as it is (a red pull
   request does not merge under the checks); nothing is reverted or deleted.

The skill never runs `gh pr merge` other than `gh pr merge <pr> <git.mergeFlags>` (as today, in the steps before the
watch), never with `--admin`, never retries or re-runs a CI job (`gh run rerun`), and never disables a check
(criterion 3).

**9. The slot reports.** In `/next` and `/fix`, rows added to "Reporting the steps":

| When | Role | Step |
|---|---|---|
| before each watch call (decision 4) | `session` | `watch-checks` |
| just before the producer's launch of check fix round k | `implementer` / `fixer` | `check-fix-<k>` |
| just before the reviewer's launch of check fix round k | `codeReviewer` | `check-review-<k>` |
| after the hand-over (decision 8) | `session` | `handed-over` |

The row `done` moves to "after the watch ends green or out of time (decision 5, 7)". `/spec` takes no slot and
reports nothing, as today.

**10. Resumed runs.** Iteration 44's rows N1 (`/next`), S1 and R1 (`/spec`) end with the watch of decision 4, with
round 1 and the full 30 minutes: the rounds of a dead run are not known, as for its review rounds.
A `blocked` label already on the issue does not stop the run and is not removed (only the maintainer removes it).

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | After enabling auto-merge the skill watches the PR's checks for a bounded time | Decisions 1, 2, 3, 4, 7, 10 |
| 2 | On a red check it fixes the cause and pushes, at most `review.maxFixRounds` times | Decision 6 |
| 3 | When the rounds are used up it comments the failing job on the issue, labels it `blocked` and stops; it never forces a merge | Decision 8 |
| 4 | A PR that goes green and merges needs no further action | Decision 5 |

## Tests

The skills are conversations; as in iterations 40 and 44, a test script pins the wording the behaviour depends on,
and the manual check runs the behaviour.

**`tests/test-watch-checks.sh`** (new, bash, built like `tests/test-resume-stuck.sh`: each file joined, `tr '\n' ' '`,
runs of spaces made one, then searched for fixed strings). Section `== a red pull request is fixed within bounds`.
Each missing text prints `FAIL: <file> does not say the watch item: <text>` and the script exits 1.

- Criterion 1, `skills/workflow/SKILL.md` ("CI and merging"): `at most 30 minutes`,
  `gh pr checks <pr> --watch --fail-fast --interval 30`, `gh pr checks <pr> --json name,bucket,link,workflow`,
  `whether auto-merge is on or not`, `were still running after`. `skills/next/SKILL.md`, `skills/fix/SKILL.md`,
  `skills/spec/SKILL.md`: `Watching the checks`. `skills/next/SKILL.md` and
  `skills/fix/SKILL.md`: `| \`session\` | \`watch-checks\` |`.
- Criterion 2: `skills/workflow/SKILL.md`: `check fix round`, `at most \`review.maxFixRounds\` check fix rounds`,
  `--log-failed`; each of the three skills: `Check fix round <k> of <review.maxFixRounds>`, the paragraph's
  `is red (check fix round <k> of`; `skills/next/SKILL.md` and `skills/fix/SKILL.md`: `check-fix-<k>`,
  `check-review-<k>`.
- Criterion 3: `skills/workflow/SKILL.md`: `Checks of PR #<pr> are red after <r> check fix rounds`,
  `--add-label blocked`, `never with \`--admin\``; `skills/next/SKILL.md` and `skills/fix/SKILL.md`: `handed-over`.
  `skills/workflow/SKILL.md`: `never retries or re-runs a CI job (\`gh run rerun\`)`; `skills/next/SKILL.md`,
  `skills/fix/SKILL.md` and `skills/spec/SKILL.md`: `never \`gh run rerun\``. No file in `skills/` contains
  `gh pr merge --admin`, and in each file of `skills/` the number of `gh run rerun` equals the number of those two
  "never" texts, so the command appears only where it is forbidden
  (`FAIL: <file> forces a merge or re-runs a check`).
- Criterion 4: `skills/workflow/SKILL.md`: `Checks of PR #<pr> are green`.
- No key: no file of `skills/`, `schema/nightmill.schema.json`, `templates/nightmill.example.json` or `README.md`
  contains `watchChecksMinutes` (`FAIL: <file> names a watch key`).

`tests/check.sh` gets `add bash test-watch-checks.sh` in its step list, and the `--only` list of the bash job in
`.github/workflows/ci.yml` gets `test-watch-checks.sh`, so `== the check runs every smoke script` stays green. The
existing sections and tests stay green, among them `== slots report what their agent does` (`done` stays),
`tests/test-resume-stuck.sh` (rows N1, S1, R1 keep their text; the watch is added after it) and `== config
validates`. `bash tests/check.sh` stays green.

What only the manual check shows: that the watch really waits and stops, that a red check reaches the producer with
its log, and that the hand-over leaves the pull request as it is.

**The manual check** (`verification.manualCheckText`), in a scratch project with its own board, two slots, a CI
workflow with one job `t` that runs `test -f ok`, a ruleset or none, and `claude --plugin-dir <a separate checkout of
this branch>` (0003). Each step names the criterion it shows.

1. *Criteria 1 and 4*: `/next` on a story whose change keeps `ok`: the run opens the pull request, enables
   auto-merge, prints `watch-checks` reports in `/status`, then `Checks of PR #<pr> are green (1 checks); auto-merge
   is on.`, reports `done` and ends; the pull request merges by itself; no comment and no label on the issue.
2. *Criterion 2*: a story whose change deletes `ok` (the spec says so, the job then fails): the watch ends red, check
   fix round 1 launches the implementer with the log, the code reviewer reviews, the pull request gets the comment
   `Check fix round 1 of 2: ...`, the push starts a new run, the watch goes green.
3. *Criterion 3*: set `review.maxFixRounds` to 1 and make `t` always fail (`exit 1`): one round runs, then the issue
   gets `Checks of PR #<pr> are red after 1 check fix rounds ...`, the label `blocked`, the slot shows `handed-over`,
   the status is Review, `gh pr view <pr> --json state,autoMergeRequest` shows `OPEN` and auto-merge as before. With
   `review.maxFixRounds` 0: no round, the comment says 0.
4. *Criterion 1, time*: make `t` sleep 2400 s (`timeout-minutes: 45`): after about 30 minutes the issue gets
   `Checks of PR #<pr> were still running after 30 min ...`, no label, and the run ends.
5. *Decision 2*: a `/spec` run whose spec pull request has a blocking finding (no auto-merge) is watched too; `/fix`
   on a bug watches its pull request the same way.

## Files touched

- `skills/workflow/SKILL.md`, "CI and merging": after "A red PR is fixed, never forced." a paragraph **Watching the
  checks** with decisions 1 to 8 in short: which pull requests (decision 2), the watch and its verdict table
  (decisions 3, 4), green (5), the check fix round and its bound (6, without the role details), the time running out
  (7), the hand-over with its comment, the label and the "never" list (8). "Findings and fix rounds", "Rounds": one
  sentence that check fix rounds are counted apart and bounded by the same key.
- `skills/next/SKILL.md`: a new step 9 "Watch the checks" pointing to the workflow rule, with the implementer and
  `codeReviewer` as the round's roles and the slot as the checkout; the paragraph of decision 6; the rows of decision
  9 and the `done` row's new "When"; rows N1 (watch at the end), N8 and N9 ("steps 4 to 9"); "Hard rules": never
  `--admin`, never `gh run rerun`.
- `skills/fix/SKILL.md`: a new step 7 "Watch the checks" (the fixer and `codeReviewer`, the slot), the rows of
  decision 9, "Batch mode": one sentence that `/fix all` watches no pull request (Not done); "Hard rules" as in
  `/next`.
- `skills/spec/SKILL.md`: step 5 ends with "then watch the checks (**Watching the checks** in the `workflow` skill)",
  with the spec writer and `specReviewer` as the round's roles and the checkout switch of decision 6, step 2; rows S1
  and R1 end with the watch (S2 and R2 find a merged spec pull request and stay unchanged);
  "Hard rules" as in `/next`.
- `README.md`: the configuration table's `review.maxFixRounds` row says it also bounds the fix rounds after a red
  check of the pull request; the paragraph on the review rounds gets one sentence on the watch (at most 30 minutes
  per push) and the hand-over (label `blocked`).
- `tests/test-watch-checks.sh` (new), `tests/check.sh` (one step line), `.github/workflows/ci.yml` (one name in the
  bash job's `--only` list): the Tests above.
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 46 (#145): after its pull request opens, /next, /fix and /spec
  watch its checks for at most 30 minutes per push, with or without auto-merge. A red check goes back to the producer with the failing job's log, is reviewed, pushed
  and watched again, at most review.maxFixRounds times; then the issue gets a comment naming the failing job and the
  label blocked, and the run stops without forcing a merge. A green pull request needs nothing more.` Paths, keys
  and commands in backticks.

Not touched: `scripts/`, `agents/`, `hooks/`, `/status`, `/init` (its label table already has `blocked`), the
release script, `schema/nightmill.schema.json`, `templates/nightmill.example.json`, this repository's
`.claude/nightmill.json`.

## Risks

- **A long run.** A watched run holds the session for up to `(1 + review.maxFixRounds) × 30` minutes of waiting (90
  with `review.maxFixRounds` 2) plus the fix rounds. Limits: the fixed bound and the rounds, and the reports keep the
  slot `running` while it waits.
- **A fixed bound.** A project whose CI takes longer than 30 minutes is handed a pending pull request every time
  (decision 7, a comment, no label). Limits: auto-merge, when on, still merges it; Left, item 1.
- **A fix that CI alone can test.** A ShellCheck or Windows PowerShell 5.1 failure cannot be reproduced on the
  machine; the producer fixes from the log and the next run is the test. Limits: the review before each push, and
  the rounds.
- **A fix pushed while auto-merge is on merges unseen by the maintainer** once it is green. Limits: it was reviewed by
  the role's reviewer (decision 6, step 4), and a story trigger or a manual check had already withheld auto-merge.
- **The first red check only.** Several red jobs with one cause are fixed in one round; with different causes the
  next round takes the next. Limits: the rounds.
- **A failure not caused by the change** (a red base branch, a runner outage) is handed over after the producer says
  so, which costs one launch. Limits: the producer's `failed` ends it at once.
- **The seconds after a push.** If `gh` still shows the previous head's checks right after a push, a stale green
  could end the watch early. Limits: decision 4's head check runs before the first call of each watch; see Left,
  item 4.

## Size estimate

M: about 30 lines in `skills/workflow/SKILL.md`, 35 in `skills/next/SKILL.md`, 30 in `skills/fix/SKILL.md`, 20 in
`skills/spec/SKILL.md`, 3 in the README, 70 in `tests/test-watch-checks.sh`, 2 in
`tests/check.sh` and `ci.yml`, 5 in `CHANGELOG.md`: about 195 changed lines.

## Not done

- `/fix all` watches no pull request: its slots are freed once the pull request is open, and its loop does not wait
  (Left, item 3).
- No change to the board status, no new status, no move back from Review; nothing removes the label `blocked`.
- No re-run of a CI job, no disabling of a check, no change to CI, the ruleset or required checks, no merge without
  `git.mergeFlags`, no `--admin`.
- No rebase or conflict resolution when the base branch moves; a pull request that is green but not mergeable is
  not handled.
- No watch of pull requests the skills did not open (release pull requests, the maintainer's own).
- No new config key: no key for the time bound (fixed at 30 minutes), no way to turn the watch off.
- No `labels.blocked` config key (the literal `blocked`, as `/init` writes it).
- No change to `/status` (it already shows CI per pull request) and no new flag text there.
- No release of the slot after the merge: as today.
- No circuit breaker across runs (the gap story the Agent notes name).

## Left

1. **The fixed bound.** The issue asks for a bounded time and names no key, so this spec fixes it at 30 minutes per
   watch in the workflow skill and adds no key (a key would be a story trigger the issue does not ask for). How long
   CI takes differs between projects, so the "Config-driven" invariant may call for a key such as
   `review.watchChecksMinutes`; whether to add one is for the maintainer, as its own story.
2. **The label `blocked` is literal.** `/init` already creates it by that name and the config has no key for it.
   A `labels.blocked` key would be the config-driven form; it is not added here because the issue does not ask for
   it.
3. **`/fix all`.** The Context names `/fix`; in batch mode a watch would hold a slot that the run frees for the next
   bug, or delay the end of the run by up to the bound per bug. Whether batch mode should watch, and how, is for the
   maintainer; it would be its own story.
4. **The moment after a push** was not observed with `gh` 2.103.3 (nothing was pushed for this spec). Decision 4
   treats "no checks" as pending and checks the head before the watch; the implementer confirms in the manual check
   (step 2) that the first verdict after a push is about the new head, and if it is not, waits for a check whose
   `startedAt` is after the push.
5. **Separate rounds.** Criterion 2 says "at most `review.maxFixRounds` times"; this spec counts the check fix rounds
   apart from the review's fix rounds (decision 6). Sharing one budget would leave no CI fix after a review that used
   its rounds.
