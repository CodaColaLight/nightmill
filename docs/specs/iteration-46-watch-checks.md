# Iteration 46: after enabling auto-merge, /next, /fix and /spec watch the pull request's checks and fix a red one within review.maxFixRounds

Status: draft, awaiting approval (#145)

Story #145, epic #107 (Hardening from the code review), finding HI-9 of the review of 0.2.0. Today `/next`, `/fix`
and `/spec` open the pull request, decide auto-merge and stop, so a red pull request waits until the maintainer
notices it. After this iteration each of the three skills, once it has enabled auto-merge on its pull request,
watches the pull request's checks for at most `review.watchChecksMinutes` minutes per push (a new config key,
default 30). A pull request without auto-merge is not watched, as today.
Green ends the run with one line and nothing else. Red starts a **check fix round**: the session records the round
on the pull request, the producer of the change (the implementer, the fixer, the spec writer) gets the failing job's
log, fixes the cause and runs the check; the implementer and the fixer commit, the spec writer leaves its change
uncommitted; the reviewer of that role reviews the round; in `/spec` the session then commits; the session pushes and
watches again. At most `review.maxFixRounds` check fix rounds run on one pull request, counted over every run from
those records. When they are used up, the session comments the failing job on the issue, adds the label `blocked` and
stops; it never forces a merge. The shared rule is in `skills/workflow/SKILL.md`, the role-specific steps in
`skills/next/SKILL.md`, `skills/fix/SKILL.md` and `skills/spec/SKILL.md`. Also changed:
`schema/nightmill.schema.json`, `templates/nightmill.example.json`, `README.md`, `tests/test-watch-checks.sh` (new),
`tests/check.sh`, `.github/workflows/ci.yml` and `CHANGELOG.md`. No script, agent or hook change, and no change to
`/init`'s permissions: every command the watch and the rounds add already has a rule (decision 11; Left, item 6
names the one command of a resumed run, already in `/next` today, that has none).

## Story trigger and manual check

**A story trigger**, by one of `escalation.storyTriggers`:

- *A change to the status flow or who sets a status*: no. The eight statuses, their order and who sets each stay as
  the table in `skills/workflow/SKILL.md` has them. A watched pull request stays at Review the whole time, whatever
  the checks show; the hand-over adds a label, which is not a status. No decision record is needed ("Fixed flow").
- *A new, renamed or removed config key*: **yes**. The time bound is the new key `review.watchChecksMinutes`
  (decision 1, by the maintainer's decision for this revision); the round bound is the existing
  `review.maxFixRounds`. The key goes into `schema/nightmill.schema.json` with a description and a default, into
  `templates/nightmill.example.json` and into the README's configuration table (`.claude/CLAUDE.md`, "Config keys
  are a contract"). What follows: the implementation pull request of this story changes a story trigger, so
  `/next` step 7 does not enable auto-merge on it and says why in the pull request; the maintainer merges it. The
  previous version ignores the key, and its validator, with its own schema, warns `unknown key` for it (not an
  error; with `--strict` the warning fails), as for `worktrees.stalledAfterMinutes` in iteration 23 ("Compatible").
- *A change to the slot marker format*: no. The new step names `watch-checks`, `check-fix-<k>`, `check-review-<k>`
  and `handed-over` (decision 9) are values of the existing `step` key, which `--report` already accepts (1 to 40
  letters, digits or `-`) and the previous version prints as it is.

**The manual check applies**: `skills` is in `verification.manualCheckPaths`, and four skills change. Its steps are
under Tests. The session does it in `/next` step 4, before the pull request opens; a manual check that was done does
not withhold auto-merge: `/next` step 7 withholds it only for a required manual check that was skipped, and the
specs of iterations 18 and 20, which also change `skills` and `agents`, say "the PR may auto-merge". The
implementation pull request of this story still gets no auto-merge, for the story trigger above (`/next` step 7). No
script in `scripts/` changes, so no smoke step is added and "Both shells" is not touched: every
command the skills run here is `gh` or `git`, the same in bash and PowerShell (decision 11). `skills/workflow/SKILL.md` and
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
  Criterion 1 watches after enabling auto-merge, so those pull requests stay unwatched (decision 2; Not done).
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
  one object per check with `link` `https://github.com/<owner>/<repo>/actions/runs/<run>/job/<job>`.
- **A job's log through `gh api`** (read on 2026-11-10, job 129330645196 of #247, read only):
  `gh api repos/CodaColaLight/nightmill/actions/jobs/129330645196/logs` printed `the response contains terminal escape
  sequences; pass --allow-escape-sequences to output it anyway` and nothing else; with `--allow-escape-sequences` it
  exited 0 and printed the job's whole log as text (618 lines, every step, ending with the post-job clean-up lines).
  The endpoint has no filter for failed steps, as `gh run view --log-failed` has.
- **The run permissions** (iteration 43, `skills/init/SKILL.md`): **Permissions** writes `Bash(gh project:*)`,
  `Bash(gh issue:*)`, `Bash(gh pr:*)`, `Bash(gh api:*)`, `Bash(git status:*)`, `Bash(git diff:*)`, `Bash(git log:*)`;
  **Run permissions** writes the rules A (main checkout, among them `Bash(git fetch origin)`, `Bash(git switch *)`,
  `Bash(git add *)`, `Bash(git commit *)`, `Bash(git push -u origin <Sp>*)`, `<Fe>*`, `<Fx>*`,
  `Bash(git rev-parse *)`) and B (per slot, among them `Bash(git -C <S> rev-parse *)`, `Bash(git -C <S> diff *)`,
  `Bash(git -C <S> push -u origin <Fe>*)`, `<Fx>*`). No rule covers `gh run`, `sleep` or a `git` command written
  `git -C` with a path that is not a slot; its decision 5 writes each command in one form: in a slot
  `git -C <absolute slot path> <subcommand> ...`, in the main checkout `git <subcommand> ...` without `-C`.
- **Not checked here** (no pull request without checks was at hand, and nothing was pushed): what `gh pr checks`
  prints in the seconds after a push, before the new head has any check. gh's source prints
  `no checks reported on the '<branch>' branch` and exits 1 in that case; decision 4 does not depend on the exit
  code.
- **The Bash tool of Claude Code** runs one foreground call for at most 10 minutes (600000 ms). A watch longer than
  that is several calls (decision 4); no `timeout` command is needed, which macOS and PowerShell lack. The Bash
  tool of the Claude Code session that wrote this revision (2026-11-10) says of itself "Foreground `sleep` is
  blocked", so a `sleep` call would fail there even with a rule.
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

**1. The bound in time: `review.watchChecksMinutes` per watch, default 30.** One **watch** waits at most
`<w>` minutes, counted from the moment the watch starts (after the pull request opened, or after a check fix round
pushed). `<w>` is `review.watchChecksMinutes` of `.claude/nightmill.json`, read when the watch starts:

- **The key.** In `schema/nightmill.schema.json` under `review.properties`, after `maxFixRounds`:
  `"watchChecksMinutes": { "type": "integer", "minimum": 1, "default": 30, "description": "Minutes /next, /fix and
  /spec watch a pull request's checks after enabling auto-merge, per push, before they stop watching and leave it to
  auto-merge. The watch cannot be turned off." }`. In `templates/nightmill.example.json`:
  `"review": { "maxFixRounds": 2, "watchChecksMinutes": 30 }`. In the README's configuration table, after the
  `review.maxFixRounds` row: `` | `review.watchChecksMinutes` | Minutes a skill watches its pull request's checks
  after enabling auto-merge, per push (default 30) | ``. This repository's `.claude/nightmill.json` does not set it.
- **The fallback.** When the key is absent or `null`, or `review` is absent, `<w>` is 30 and nothing is said. Any
  other value that is not a whole number of at least 1 (`0`, `-5`, `2.5`, `"30"`, `true`) gives 30 and one printed
  line, `review.watchChecksMinutes must be a whole number of at least 1; using 30`, and the watch goes on.
- **An older version** ignores the key (no skill of it reads it) and watches nothing, as before this iteration; its
  validator warns `unknown key` for it (Story trigger and manual check).

The issue asks for a bounded time and names no key; the maintainer decided for this revision that the bound is a
key, because how long CI takes differs per project ("Config-driven"). Why 30 as the default: three times the longest
CI run this repository sees, so a queued Windows runner does not end a watch early. Why per watch and not per run:
each push starts a new CI run, so the longest run of the skill is `(1 + review.maxFixRounds) × <w>` minutes of
watching (90 min with `review.maxFixRounds` 2 and the default) plus the fix rounds. There is no way to turn the watch
off (`minimum` 1).

**2. Which pull requests are watched.** Only a pull request with auto-merge on is watched: one that `/next`, `/fix`
(one bug) or `/spec` opened or, in a resumed run (iteration 44 rows N1, S1, R1), reused, and whose
`gh pr view <pr> --json autoMergeRequest` is not empty after the skill's auto-merge step (the step enabled it, or a
resumed run found it on). Why: criterion 1 starts the watch "after enabling auto-merge", and the issue puts anything
else out of scope. A pull request whose auto-merge was withheld (`/next` step 7, `/spec` step 4: a story trigger, a
partial result, a skipped manual check, blocking findings, an open dispute) ends the run as before this iteration,
unwatched (Not done). The watch starts after the last step that today ends the run: `/next` after step 8, `/fix`
after step 6, `/spec` after step 5 (before the stop of step 6). Not watched either: `/fix all` (Not done; Left,
item 3), and a pull request whose state is not `OPEN` when the watch starts (`gh pr view <pr> --json state`):
`MERGED` prints the green line of decision 5, `CLOSED` prints `PR #<pr> is closed; checks not watched.`

**3. Which checks count.** All checks that `gh pr checks <pr> --json name,bucket,link,workflow` lists for the pull
request's head, not only `--required` ones. A check whose `bucket` is `fail` or `cancel` is **red**; `pass` and
`skipping` are **done**; `pending` is **pending**. Why all: the skill fixes what it caused, and a project without
required checks would show none with `--required`. A check counts by its `bucket` alone, whether it blocks the merge
or not: a job that does not block (this repository's validate job, `continue-on-error: true`) is red when its
`bucket` is `fail` and done when it is `pass`. For a red one the producer may answer that it is not caused by the
change (decision 6, `failed`).

**4. One watch, exactly.** Before it, the session runs three checks, in this order; each hand-over here starts
before any watch call, so no check is red yet and decision 8 uses its comment without a failing check:

1. `<checkout>` is the slot that holds the branch, else the session's checkout.
2. A resumed `/next` (row N1) whose branch has no local ref first creates it, after `git fetch origin`, with
   `git branch --no-track <branch> origin/<branch>`, as "Resuming a story" does before a take. When the fetch or the
   `git branch` fails, it hands over at once (decision 8) with the reason `the branch could not be created: <the first
   line of git's message>`.
3. The pull request's head is its own last commit: `gh pr view <pr> --json headRefOid --jq .headRefOid` equals
   what `git -C <slot path> rev-parse refs/heads/<branch>` prints when `<checkout>` is a slot, and
   `git rev-parse refs/heads/<branch>` (no `-C`) when it is the session's checkout (decision 11), the ref of the pull
   request's branch (not `HEAD`: `/spec` has switched its checkout back to the branch it came from). When the two differ, it hands over at once (decision 8)
   with the reason `the branch on origin is not this run's last commit`.

Then, while the
watch's time is not used up, one foreground shell call:
`gh pr checks <pr> --watch --fail-fast --interval 30`, with the shell tool's timeout set to the **call limit**: the
smallest of 10 minutes, the time left, and, in a run that reports to a slot (decision 9), `worktrees.stalledAfterMinutes`
minus 30 seconds (the value as `slot --status` reads it: the config's whole number of at least 1, else 30). So every
gap between two `watch-checks` reports is below the threshold, and a slot that watches never shows `stalled` (with
`worktrees.stalledAfterMinutes` 1 a call lasts 30 s). When the call returns (any exit code, or the tool's timeout), the session reads the verdict
with one call `gh pr checks <pr> --json name,bucket,link,workflow` and decides only from that JSON (never from an
exit code):

| JSON | Verdict |
|---|---|
| at least one red check | red: decision 6 with the first red check in the listing's order |
| no check at all (the output is `no checks reported ...` or `[]`) | pending |
| every check done | green: decision 5 |
| otherwise | pending |

Pending with time left: the next call. Pending with no time left: decision 7. A watch call that finds no check at
all (right after a push, before the new head has one) returns at once, and the next call follows at once; nothing
sleeps (no `sleep`, decision 11). So that this cannot spin for the whole bound, a watch whose calls found no check at
all **10 times in a row** ends as in decision 7, with `<names>` = `no check reported`; one call that finds a check
starts the count again. Before each watch call the session reports `watch-checks` (decision 9), so a slot
shows `running` while it watches, and `/next` never resumes a watching run as `stalled` (`skills/next/SKILL.md`,
"A run that is visibly at work is never joined"; iteration 44). The watch commits, pushes and changes nothing.

**5. Green.** Print `Checks of PR #<pr> are green (<n> <check | checks>); auto-merge is on.`, with `check` when `<n>` is 1 and `checks` otherwise, and end the run as it ended before this iteration (`/next` and `/fix` report `done`; `/spec` goes
on with step 6). Nothing else: no comment, no label, no status, no merge, no slot release. The pull request then
merges by itself under auto-merge (criterion 4). After that, as today: in `/next` and `/fix` its `Closes #<issue>` /
`Fixes #<issue>` sets Done; in `/spec` the spec pull request's body is `Spec for #<issue>.` (not `Closes`), so its
merge closes nothing and the issue stays at Spec review until the maintainer sets Approved.

**6. Red: one check fix round.** Check fix rounds are counted per pull request, over every run that worked on it,
apart from the review's fix rounds: the review's rounds were spent on the review's findings before the pull request
opened, and the issue bounds the CI fixes by `review.maxFixRounds` on their own.

**The count.** On a red verdict, and again before a round starts over at step 3 (step 4), the session reads
`<done>`, the check fix rounds already recorded on the pull request: the number of lines that
`gh api repos/<owner>/<repo>/issues/<pr>/comments --paginate --jq '.[] | select(.body | startswith("Check fix round ")) | .id'`
prints. `k` is `<done> + 1`. When `k ≤ review.maxFixRounds`, round k runs; otherwise no round runs: decision 8 with
the reason `the rounds are used up`. Each round records itself just before its producer's launch (step 3), so every
round whose producer started counts, in this run and in any later run on the same pull request, on any machine: one
pull request gets at most `review.maxFixRounds` check fix rounds in total (criterion 2). Comments of every author count, not only the
maintainer's login: a round run under another login still counts, and a stray comment can only lower the rounds left.
Why a comment and not the commits on the branch: the implementer's and the fixer's commit messages are theirs, and a
round that pushed nothing (a blocking review finding, a run that died) leaves no commit, so commits would count too few.

Round k is:

1. **The log.** From the red check's `link`, take `<owner>/<repo>` (after `https://github.com/`) and
   `<job>` (the number after `/job/`). `gh api --allow-escape-sequences repos/<owner>/<repo>/actions/jobs/<job>/logs`
   prints the job's whole log; its last 200 lines, taken by the session from the output (from the file the Bash tool
   saved a long output to, with the Read tool), are `<the log>`. A link that is not an Actions job link (another CI),
   or a call that fails, gives `<the log>` = `not available: <the link>`.
2. **The checkout.** The first case that holds decides:
   - `/next` and `/fix`, a slot holds the branch: that slot (it is held until the merge, as today).
   - `/next` and `/fix` in a run without slots (no `worktrees`; `/next` step 2 or `/fix` step 3 switched the session's
     checkout to the branch, and nothing switched it away): the session's checkout. Every git command of the round
     runs there without `-C <slot path>`, as `/next` step 5 and `/fix` step 6 do without slots, and the producer's
     prompt gets the checkout's absolute path where it says `<absolute slot path>`. Its tree must be clean (`git status
     --porcelain --untracked-files=all` prints nothing), else the hand-over with the reason `the checkout is not clean`.
   - A resumed `/next` (row N1) whose branch no slot holds: before the producer of its first round the session gets a
     checkout as "The slot" of row N6 does: with slots, `--take <branch>` (`-Take <branch>`; the local branch exists by
     decision 4), then the report `resumed` (role `session`); the slot is then held until the merge and released as
     today. A take that fails is the hand-over with the reason `the slot could not be taken: <the take's line>`.
     Without slots, `git switch <branch>` in the session's checkout (the tree clean, else the hand-over with the
     reason `the checkout is not clean`), and from there as in the case above.
   - `/spec` switches its checkout back to the spec branch (`git switch <branch>`; the tree must be clean, else the
     hand-over of decision 8 with the reason `the checkout is not clean`) and switches back to the branch it came from
     at the end of the round, after the push or the hand-over.
3. **The producer.** Count the agents, check the room on the machine and report `check-fix-<k>`, as for every
   launch. In `/next` and `/fix` the round guards the tester's files as "The tester's files" does: it uses the run's
   `<tester files>`, `<tester blobs>` and `<tester originals>` as the review rounds and disputes left them, and before
   every launch of the producer records `<round base>` by rule 2 there. A resumed `/next` (row N1) does not know them;
   before the producer of its first round it builds them as row N9 does ("The tester's files in a resumed code review"):
   `<tester files>` is every path of `git -C <slot path> diff --name-only origin/<git.baseBranch>...HEAD` (in the
   session's checkout `git diff --name-only origin/<git.baseBranch>...HEAD`) that is a test path by the `Test paths:` line of "The tester", and `<tester blobs>` and `<tester originals>` are recorded for
   them by rule 1 (round 0). An empty `<tester files>` is allowed there and leaves nothing to check. In that run the
   implementer's prompt lists those paths as its tests, committed, and gives `not known (resumed run)` for the
   tester's `Criteria` lines. Just before the launch, the session records the round on the pull request:
   `gh pr comment <pr> --body "Check fix round <k> of <review.maxFixRounds>: <name> (<workflow>) is red; the <role> role on <model> fixes it."`
   This is the only pull request comment of the watch; it is kept because the count above reads it. When the
   comment fails, the producer is not launched: the hand-over (decision 8) with the reason `the round could not be
   recorded: <the first line of gh's message>`. Launch the producer of the role as a fresh agent, on its role's model, passed
   explicitly: in `/next` the implementer, with its prompt and, at the end, the paragraph below; in `/fix` the fixer,
   the same; in `/spec` the spec writer, with its prompt (saying "the spec file exists; change only what the failing
   check needs"; its "Do not commit" stays) and the paragraph. The paragraph, whose `<what to do>` is
   `Fix the cause in this change, run the check, commit.` in `/next` and `/fix` and
   `Fix the cause in the spec file and run the check; do not commit, the session commits.` in `/spec`:

   ```markdown
   The pull request #<pr> is open and its check <name> (<workflow>) is red (check fix round <k> of
   <review.maxFixRounds>). The last 200 lines of its job's log:
   <the log>
   <what to do> The local check may skip the step that failed in CI (it runs
   what the machine can run); say so under Left when it did. If the failure is not caused by this change (the base
   branch, the CI runner, a flaky check), change nothing and return `failed` with the reason under Left.
   ```

   Then read the result as each skill reads its producer today: in `/next` and `/fix`, the tester's files first
   ("The tester's files", rule 3; a changed tester file undoes the round by rule 4, and the round counts), then the
   `Result:` block; a round that committed nothing (`git -C <slot path> rev-parse HEAD`, in the session's checkout
   `git rev-parse HEAD`, is still `<round base>`) is a
   hand-over with the reason `the <role> committed nothing`. In `/spec`, the form check of "The spec writer" step 4
   as it stands (the tree has exactly one change, the spec file, its first heading starts `# Iteration <N>:` and it
   has the status line `Status: draft, awaiting approval (#<issue>)`); no change at all is a hand-over with the reason
   `the specWriter changed nothing`, a wrong form one with the reason `the spec file has a wrong form: <what is
   wrong>`. A `Disputes:` line that is not `none` is not sent to the tester in a check fix round: it is a hand-over
   (decision 8, reason `the producer disputes the tester's test: <the Disputes line>`). `Result: failed`, no block, or
   an undone round is a hand-over with the reason `<Left, or why>`; in `/spec`, `Result: partial` is one too.
4. **The review.** Report `check-review-<k>`; one launch of the role's reviewer (`codeReviewer` in `/next` and `/fix`,
   `specReviewer` in `/spec`), as in "The code review" / "The spec review" step 2, with the prompt of step 3 there and
   the change given as `git diff <the pull request's head>..HEAD` in `/next` and `/fix` (the round's commits only) and
   as `git diff <the pull request's head>` in `/spec` (the uncommitted spec file against the pull request's head; the
   spec reviewer reads the file in the working tree, as "The spec review" does before its commit). The pairing is not
   checked again. No findings or advisory only: go on. A blocking finding: nothing is committed by the session and
   nothing is pushed; while a round is left (the count above, read again, gives `k + 1 ≤ review.maxFixRounds`),
   round k + 1 starts at step 3, with its own record, with the same red check and, added to the
   paragraph, "Fix exactly these blocking findings too: <the lines>" (in `/spec` the writer finds its uncommitted
   change in place, and the form check of step 3 applies again); with no round left, the hand-over (decision 8) with
   the reason `the fix of round <k> has blocking review findings: <the lines>`. Why a review: a fix pushed to a pull
   request with auto-merge on merges as soon as it is green, so it must be reviewed before the push.
5. **The commit and the push.** The commit is `/spec`'s only (the implementer and the fixer committed in step 3):
   the session commits the spec file only, `git add <spec file>`, then
   `git commit -m "docs: iteration <N> spec (#<issue>), check fix round <k>"`. Then the push (no force), in the form
   of iteration 43 decision 5: in a slot `git -C <slot path> push -u origin <branch>`, in the session's checkout
   (`/spec`, a run without slots) `git push -u origin <branch>`. `-u` keeps the upstream `origin/<branch>`, or sets it on a
   branch that a resumed run created with `--no-track`; it is written so that the rules `Bash(git -C <S> push -u origin <Fe>*)` / `<Fx>*` and
   `Bash(git push -u origin <Sp>*)` / `<Fe>*` / `<Fx>*` match. A rejected push is a hand-over with the reason
   `the push was rejected: <first line of git's message>`.

   A hand-over in `/spec` after the switch of step 2 (from step 3, 4 or 5) first commits an uncommitted change of the
   spec file to the local branch with `-m "docs: iteration <N> spec (#<issue>), check fix round <k>, unfinished"`
   (no commit when the spec file has no uncommitted change), does not push it, and switches back to the branch it
   came from, as the clean-up of "The spec writer" step 5 does; when that switch fails, the printed text of the
   hand-over ends with `The checkout stays on <branch>.`
6. **Watch again**: a new watch (decision 4), with the full `<w>` minutes. No comment after the round (the record
   of step 3 is the round's only comment) and the pull request's body is not rewritten.

With `review.maxFixRounds` 0, or when `<done>` already is `review.maxFixRounds` at a red verdict (in this run or an
earlier one), no round runs: decision 8 with the reason `the rounds are used up`.

**7. The time runs out.** Pending at the end of a watch is not red, so nothing is labelled and nothing is commented
(no criterion asks for a comment here, and no rule of this spec reads one). The session prints
`Checks of PR #<pr> were still running after <w> min (pending: <names, comma-separated>); <the skill> no longer watches them.`
and ends the run as on green (`done`; `/spec` step 6). After 10 calls in a row without a check (decision 4) the line
is the same, with `<names>` = `no check reported` and `<w>` the bound. Auto-merge still merges a pull request that
goes green later.

**8. The hand-over.** In this order:

1. A comment on the issue, posted once. A hand-over with a red check (decision 6, from a watch whose verdict was
   red) posts, only when no comment of the maintainer's login on the issue starts with `Checks of PR #<pr> are red`:
   `Checks of PR #<pr> are red after <r> <check fix round | check fix rounds> (review.maxFixRounds is <m>): <name> (<workflow>), <link>. <the reason>. Labelled blocked; the pull request is left as it is for the maintainer.`
   `<r>` is `<done>` read by the count of decision 6 at the hand-over (the check fix rounds recorded on the pull
   request, over every run), followed by `check fix round` when `<r>` is 1 and `check fix rounds`
   otherwise; `<name>`, `<workflow>` and `<link>` are those of the red check the round fixes (the last red verdict);
   `<the reason>` is the reason named where the hand-over starts (decision 6), for used-up rounds exactly
   `the rounds are used up`. A hand-over from the checks of decision 4 (before a watch call, so with no red check of
   this watch) posts, only when no comment of the maintainer's login on the issue starts with
   `Checks of PR #<pr> are not watched`:
   `Checks of PR #<pr> are not watched after <r> <check fix round | check fix rounds> (review.maxFixRounds is <m>): <the reason>. Labelled blocked; the pull request is left as it is for the maintainer.`
   with `<r>` as above (0 when no round was ever recorded) and `<the reason>` the reason of decision 4, check 2 or 3.
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
reports nothing, as today; a run without slots reports nothing either, and a resumed N1 run that takes a slot for its
round (decision 6, step 2) reports from that take on.

**10. Resumed runs.** Iteration 44's rows N1 (`/next`), S1 and R1 (`/spec`) end with the watch of decision 4, with
the full `<w>` minutes. Their check fix rounds go on from the count of decision 6: the rounds recorded on the pull
request by earlier runs, dead or handed over, count, so a resumed run gets only the rounds that are left, and none
when they are used up (a red verdict then hands over at once, and the issue comment of decision 8 is not posted a
second time). This differs from the review rounds, which a resumed run starts at round 0 (iteration 44 decision 8):
those are counted per run and not recorded, these are recorded. A `blocked` label already on the issue does not stop
the run and is not removed (only the maintainer removes it).

**11. The commands and their permissions.** Every command the watch and the rounds add has a rule that `/init`
already writes, so an unattended run does not prompt for them; `/init` is not changed (the one exception, a command
of a resumed run that `/next` already runs today, is the last item below). Avoiding the two commands
without a rule was smaller than extending `/init` (which would change its rule list A, its count `24 + 21 ×
worktrees.slots`, the README's run-permissions subsection and the `tests/lint.sh` section of iteration 43):

- **The job log** is read with `gh api --allow-escape-sequences repos/<owner>/<repo>/actions/jobs/<job>/logs`
  (rule `Bash(gh api:*)`), not with `gh run view --log-failed`, which no rule covers. The cost: the whole job log
  instead of its failed steps; its last 200 lines hold the end of the failed step and the post-job steps (Facts).
- **No `sleep`**: the watch loop of decision 4 does not wait between calls that find no check, and ends after 10 of
  them in a row. No rule covers `sleep`, and the Bash tool blocks a foreground one (Facts).
- **`gh`** only as `gh pr checks`, `gh pr view`, `gh pr comment` (rule `Bash(gh pr:*)`), `gh issue comment`,
  `gh issue edit` (`Bash(gh issue:*)`) and `gh api` (`Bash(gh api:*)`).
- **`git`** in the one form of iteration 43 decision 5: in a slot `git -C <absolute slot path> <subcommand> ...`
  (rules B: `status`, `diff`, `log`, `add`, `commit`, `rev-parse`, `push -u origin <Fe>*` / `<Fx>*`, and the tester
  files' commands of "The tester's files" as today); in the session's checkout `git <subcommand> ...` without `-C`
  (`git status`, `git diff`, `git log` of **Permissions**; `git fetch origin`, `git switch *`, `git add *`,
  `git commit *`, `git rev-parse *`, `git push -u origin <Sp>*` / `<Fe>*` / `<Fx>*` of rules A). `<checkout>` in this
  spec names the place; it is never written as `git -C <checkout>`. The check runs as `cd <absolute slot path> && <C>`
  in a slot, as there.
- **One command of a resumed run has no rule**: `git branch --no-track <branch> origin/<branch>` (decision 4, check 2),
  which "Resuming a story" of `/next` already runs before a take (iteration 44) and which iteration 43's list does not
  have. It runs only in a `/next N` that the maintainer starts by number, and it prompts there as it does today
  (Left, item 6).

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | After enabling auto-merge the skill watches the PR's checks for a bounded time | Decisions 1, 2, 3, 4, 7, 10, 11 |
| 2 | On a red check it fixes the cause and pushes, at most `review.maxFixRounds` times | Decisions 6, 10, 11 |
| 3 | When the rounds are used up it comments the failing job on the issue, labels it `blocked` and stops; it never forces a merge | Decision 8 |
| 4 | A PR that goes green and merges needs no further action | Decision 5 |

## Tests

The skills are conversations; as in iterations 40 and 44, a test script pins the wording the behaviour depends on,
and the manual check runs the behaviour.

**`tests/test-watch-checks.sh`** (new, bash, built like `tests/test-resume-stuck.sh`: each file joined, `tr '\n' ' '`,
runs of spaces made one, then searched for fixed strings). Section `== a red pull request is fixed within bounds`.
Each missing text prints `FAIL: <file> does not say the watch item: <text>` and the script exits 1.

- Criterion 1, `skills/workflow/SKILL.md` ("CI and merging"): `` at most `review.watchChecksMinutes` minutes ``,
  `review.watchChecksMinutes must be a whole number of at least 1; using 30`, `10 times in a row`,
  `gh pr checks <pr> --watch --fail-fast --interval 30`, `gh pr checks <pr> --json name,bucket,link,workflow`,
  `Only a pull request with auto-merge on is watched`, `` `worktrees.stalledAfterMinutes` minus 30 seconds ``,
  `were still running after`. `skills/next/SKILL.md`, `skills/fix/SKILL.md`,
  `skills/spec/SKILL.md`: `Watching the checks`. `skills/next/SKILL.md` and
  `skills/fix/SKILL.md`: `| \`session\` | \`watch-checks\` |`.
- Criterion 2: `skills/workflow/SKILL.md`: `check fix round`, `at most \`review.maxFixRounds\` check fix rounds`,
  `actions/jobs/<job>/logs`, `--allow-escape-sequences`, `startswith("Check fix round ")`,
  `the round could not be recorded:`; each of the three skills: `Check fix round <k> of <review.maxFixRounds>`, the paragraph's
  `is red (check fix round <k> of`; `skills/next/SKILL.md` and `skills/fix/SKILL.md`: `check-fix-<k>`,
  `check-review-<k>`, `Fix the cause in this change, run the check, commit.`; `skills/spec/SKILL.md`:
  `Fix the cause in the spec file and run the check; do not commit, the session commits.`,
  `docs: iteration <N> spec (#<issue>), check fix round <k>`; `skills/next/SKILL.md`: `not known (resumed run)`.
- Criterion 3: `skills/workflow/SKILL.md`: `Checks of PR #<pr> are red after <r> <check fix round | check fix rounds>`,
  `Checks of PR #<pr> are not watched after <r> <check fix round | check fix rounds>`,
  `the branch on origin is not this run's last commit`, `the branch could not be created:`, `--add-label blocked`, `never with \`--admin\``; `skills/next/SKILL.md` and `skills/fix/SKILL.md`: `handed-over`.
  `skills/workflow/SKILL.md`: `never retries or re-runs a CI job (\`gh run rerun\`)`; `skills/next/SKILL.md`,
  `skills/fix/SKILL.md` and `skills/spec/SKILL.md`: `never \`gh run rerun\``. No file in `skills/` contains
  `gh pr merge --admin`, and in each file of `skills/` the number of `gh run rerun` equals the number of those two
  "never" texts, so the command appears only where it is forbidden
  (`FAIL: <file> forces a merge or re-runs a check`).
- Criterion 4: `skills/workflow/SKILL.md`: `Checks of PR #<pr> are green (<n> <check | checks>)`.
- The key (criterion 1): `schema/nightmill.schema.json` contains
  `"watchChecksMinutes": { "type": "integer", "minimum": 1, "default": 30, "description": "Minutes /next, /fix and`; `templates/nightmill.example.json` has `"watchChecksMinutes": 30` under `review`; `README.md` has
  `` | `review.watchChecksMinutes` | `` (`FAIL: <file> does not carry the key review.watchChecksMinutes`).
- The command forms (decision 11): no file of `skills/` contains `gh run view`, `--log-failed`, `` `sleep `` or
  `git -C <checkout>` (`FAIL: <file> runs a command that has no run permission: <text>`); `skills/workflow/SKILL.md`
  contains `git -C <slot path> push -u origin <branch>` and `git push -u origin <branch>`.
- Only the comments the criteria and the count need: no file of `skills/` contains
  `--body "Checks of PR #<pr> were still running` (the line is printed, not commented) or `Fixed by the <role> role`
  (the removed after-round comment) (`FAIL: <file> comments where no rule asks for it`).

`tests/check.sh` gets `add bash test-watch-checks.sh` in its step list, and the `--only` list of the bash job in
`.github/workflows/ci.yml` gets `test-watch-checks.sh`, so `== the check runs every smoke script` stays green. The
existing sections and tests stay green, among them `== slots report what their agent does` (`done` stays),
`tests/test-resume-stuck.sh` (rows N1, S1, R1 keep their text; the watch is added after it) and `== config
validates` (the example with the new key validates against the new schema). `bash tests/check.sh` stays green.

What only the manual check shows: that the watch really waits and stops, that a red check reaches the producer with
its log, and that the hand-over leaves the pull request as it is.

**The manual check** (`verification.manualCheckText`), in a scratch project with its own board, two slots, a CI
workflow with one job `t` that runs `test -f ok`, a ruleset or none, and `claude --plugin-dir <a separate checkout of
this branch>` (0003). Each step names the criterion it shows.

1. *Criteria 1 and 4*: `/next` on a story whose change keeps `ok`: the run opens the pull request, enables
   auto-merge, prints `watch-checks` reports in `/status`, then `Checks of PR #<pr> are green (1 check); auto-merge
   is on.`, reports `done` and ends; the pull request merges by itself; no comment and no label on the issue.
2. *Criterion 2*: a story whose change deletes `ok` (the spec says so, the job then fails): the watch ends red, check
   fix round 1 first comments `Check fix round 1 of 2: t (<workflow>) is red; ...` on the pull request, then launches
   the implementer with the end of the job's log, the code reviewer reviews, the push starts a new run, the watch
   goes green; no other comment on the pull request, and no prompt for the log, the push or the watch (decision 11).
3. *Criterion 3*: set `review.maxFixRounds` to 1 and make `t` always fail (`exit 1`): one round runs, then the issue
   gets `Checks of PR #<pr> are red after 1 check fix round ...`, the label `blocked`, the slot shows `handed-over`,
   the status is Review, `gh pr view <pr> --json state,autoMergeRequest` shows `OPEN` and auto-merge as before. With
   `review.maxFixRounds` 0: no round, the comment says `after 0 check fix rounds`. *Criterion 2, across runs*: with
   `review.maxFixRounds` 1 after that hand-over, `/next <n>` on the story at Review (row N1) runs no round: the
   pull request already has one `Check fix round` comment, the red verdict hands over with `the rounds are used up`,
   and the issue gets no second comment.
4. *Criterion 1, time*: set `review.watchChecksMinutes` to 5 and make `t` sleep 600 s (`timeout-minutes: 15`):
   after about 5 minutes the run prints `Checks of PR #<pr> were still running after 5 min ...` and ends; no comment,
   no label. Without the key (removed from the config) the same run waits about 30 minutes. With
   `"watchChecksMinutes": 0` the run prints `review.watchChecksMinutes must be a whole number of at least 1; using 30`.
   A workflow that does not run on pull requests (no check at all): the run prints the line with
   `pending: no check reported` after 10 calls and ends.
5. *Decision 2*: a `/spec` run whose spec pull request has a blocking finding (no auto-merge) ends as before, with no
   `watch-checks` report and no watch; `/fix` on a bug watches its pull request (auto-merge on) as `/next` does.
   *Decision 4, the call limit*: with `worktrees.stalledAfterMinutes` 2 and `t` sleeping 300 s, `/status` shows the
   watching slot `running` at every look, and `/next <n>` on the story in a second session is refused with the
   `is running` line.
6. *Criterion 2, the checkout*: a `/spec` run whose spec makes `t` fail: the spec writer's change stays uncommitted
   until the review, the session commits it as `docs: iteration <N> spec (#<issue>), check fix round 1` and pushes,
   and the checkout is back on the branch it came from. A `/next <n>` on a story at Review whose pull request is red
   and whose branch no slot holds (row N1): the round takes a slot for the branch, reports `resumed`, guards the test
   paths on the branch as tester files, and fixes the check there.

## Files touched

- `skills/workflow/SKILL.md`, "CI and merging": after "A red PR is fixed, never forced." a paragraph **Watching the
  checks** with decisions 1 to 8, 10 and 11 in short: the bound `review.watchChecksMinutes` and its fallback (decision
  1), which pull requests (decision 2, auto-merge on only), the watch, its call limit, the 10 calls without a check
  and its verdict table (decisions 3, 4), green (5), the check fix round, its count over every run and its record
  (6, 10, without the role details), the time running out (7), the hand-over with its comment, the label and the
  "never" list (8), the command forms (11). "Findings and fix rounds", "Rounds": one
  sentence that check fix rounds are counted apart and bounded by the same key.
- `skills/next/SKILL.md`: a new step 9 "Watch the checks" pointing to the workflow rule, with the implementer and
  `codeReviewer` as the round's roles, the checkout of decision 6, step 2 (the slot, the single checkout, the take of
  a resumed N1 run) and the tester's files of decision 6, step 3 (built for N1 as N9 builds them); the paragraph of
  decision 6; the rows of decision
  9 and the `done` row's new "When"; rows N1 (watch at the end), N8 and N9 ("steps 4 to 9"); "Hard rules": never
  `--admin`, never `gh run rerun`.
- `skills/fix/SKILL.md`: a new step 7 "Watch the checks" (the fixer and `codeReviewer`, the slot or the single
  checkout of decision 6, step 2, the run's tester's files), the rows of
  decision 9, "Batch mode": one sentence that `/fix all` watches no pull request (Not done); "Hard rules" as in
  `/next`.
- `skills/spec/SKILL.md`: step 5 ends with "then watch the checks (**Watching the checks** in the `workflow` skill)",
  with the spec writer and `specReviewer` as the round's roles, the checkout switch of decision 6, step 2, the form
  check of step 3, the review of the uncommitted file of step 4 and the session's commit of step 5; rows S1
  and R1 end with the watch (S2 and R2 find a merged spec pull request and stay unchanged);
  "Hard rules" as in `/next`.
- `schema/nightmill.schema.json`: the `review.watchChecksMinutes` entry of decision 1.
- `templates/nightmill.example.json`: `"review": { "maxFixRounds": 2, "watchChecksMinutes": 30 }`.
- `README.md`: the configuration table's `review.maxFixRounds` row says it also bounds the fix rounds after a red
  check of the pull request, over every run; a new row `review.watchChecksMinutes` (decision 1); the paragraph on
  the review rounds gets one sentence on the watch (at most `review.watchChecksMinutes` minutes per push, default 30)
  and the hand-over (label `blocked`).
- `tests/test-watch-checks.sh` (new), `tests/check.sh` (one step line), `.github/workflows/ci.yml` (one name in the
  bash job's `--only` list): the Tests above.
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 46 (#145): after enabling auto-merge, /next, /fix and /spec
  watch the pull request's checks for at most review.watchChecksMinutes minutes per push (new key, default 30). A red
  check goes back to the producer with the failing job's log, is reviewed, pushed and watched again, at most
  review.maxFixRounds times per pull request over every run; then the issue gets a comment naming the failing job and the
  label blocked, and the run stops without forcing a merge. A green pull request needs nothing more.` Paths, keys
  and commands in backticks.

Not touched: `scripts/`, `agents/`, `hooks/`, `/status`, `/init` (its label table already has `blocked`), the
release script, `scripts/validate-config.*` (they read the schema), this repository's `.claude/nightmill.json` (the
default applies).

## Risks

- **A long run.** A watched run holds the session for up to `(1 + review.maxFixRounds) × review.watchChecksMinutes`
  minutes of waiting (90 with the defaults) plus the fix rounds. Limits: the bound and the rounds, and the reports
  keep the slot `running` while it waits.
- **A bound too short for the project.** A project whose CI takes longer than `review.watchChecksMinutes` gets a
  pending pull request every time (decision 7, a printed line, no comment, no label). Limits: auto-merge still merges
  it; the project raises the key.
- **Checks that appear late.** A CI that registers its checks only after 10 calls without a check (decision 4) is
  treated as out of time: a later red check is not fixed. Limits: auto-merge does not merge it red; Left, item 4.
- **A record without a fix.** A round whose producer fails or whose run dies after the record still counts. Limits:
  that only lowers the rounds left, never raises them (criterion 2).
- **A shorter log.** The job's whole log replaces `--log-failed`; when the post-job steps fill most of the last 200
  lines, the producer sees less of the failure. Limits: the producer may read the check's `link`, and its `failed`
  hands over.
- **A fix that CI alone can test.** A ShellCheck or Windows PowerShell 5.1 failure cannot be reproduced on the
  machine; the producer fixes from the log and the next run is the test. Limits: the review before each push, and
  the rounds.
- **A fix pushed under auto-merge merges unseen by the maintainer** once it is green. Limits: it was reviewed by
  the role's reviewer (decision 6, step 4), and a pull request whose auto-merge a story trigger, a partial result, a
  skipped manual check, blocking findings or an open dispute withheld (`/next` step 7) is not watched (decision 2). A manual check that was done does not
  withhold it and ran before the first push, not on the round's fix; the round's record on the pull request
  (decision 6, step 3) names the red check and the round for the maintainer.
- **The first red check only.** Several red jobs with one cause are fixed in one round; with different causes the
  next round takes the next. Limits: the rounds.
- **A failure not caused by the change** (a red base branch, a runner outage) is handed over after the producer says
  so, which costs one launch. Limits: the producer's `failed` ends it at once.
- **The seconds after a push.** If `gh` still shows the previous head's checks right after a push, a stale green
  could end the watch early. Limits: decision 4's head check runs before the first call of each watch; see Left,
  item 4.

## Size estimate

M: about 40 lines in `skills/workflow/SKILL.md`, 35 in `skills/next/SKILL.md`, 30 in `skills/fix/SKILL.md`, 20 in
`skills/spec/SKILL.md`, 1 in the schema, 1 in the example, 4 in the README, 90 in `tests/test-watch-checks.sh`, 2 in
`tests/check.sh` and `ci.yml`, 5 in `CHANGELOG.md`: about 230 changed lines.

## Not done

- `/fix all` watches no pull request: its slots are freed once the pull request is open, and its loop does not wait
  (Left, item 3).
- No change to the board status, no new status, no move back from Review; nothing removes the label `blocked`.
- No re-run of a CI job, no disabling of a check, no change to CI, the ruleset or required checks, no merge without
  `git.mergeFlags`, no `--admin`.
- No rebase or conflict resolution when the base branch moves; a pull request that is green but not mergeable is
  not handled.
- No watch of a pull request without auto-merge (withheld by `/next` step 7 or `/spec` step 4): a red one still
  waits for the maintainer, as today (criterion 1 and Out of scope).
- No watch of pull requests the skills did not open (release pull requests, the maintainer's own).
- No config key other than `review.watchChecksMinutes`, and no way to turn the watch off (its `minimum` is 1).
- No change to `/init`'s permissions (decision 11); no `sleep` and no `gh run view`.
- No `labels.blocked` config key (the literal `blocked`, as `/init` writes it).
- No change to `/status` (it already shows CI per pull request) and no new flag text there.
- No release of the slot after the merge: as today.
- No circuit breaker across runs (the gap story the Agent notes name).

## Left

1. **The bound is a key now.** By the maintainer's decision for this revision the time bound is
   `review.watchChecksMinutes` (default 30, decision 1), not a fixed number, because how long CI takes differs between
   projects ("Config-driven"). That makes this story a story trigger ("a new config key"), so its implementation pull
   request gets no auto-merge (`/next` step 7) and the maintainer merges it. Nothing about the bound is left open.
2. **The label `blocked` is literal.** `/init` already creates it by that name and the config has no key for it.
   A `labels.blocked` key would be the config-driven form; it is not added here because the issue does not ask for
   it.
3. **`/fix all`.** The Context names `/fix`; in batch mode a watch would hold a slot that the run frees for the next
   bug, or delay the end of the run by up to the bound per bug. Whether batch mode should watch, and how, is for the
   maintainer; it would be its own story.
4. **The moment after a push** was not observed with `gh` 2.103.3 (nothing was pushed for this spec). Decision 4
   treats "no checks" as pending, follows it at once with the next call (no `sleep`, decision 11) and ends after 10
   such calls in a row; the number 10 is this spec's choice, not the issue's or the maintainer's. The implementer
   confirms in the manual check (step 2) that the first verdict after a push is about the new head, and if it is
   not, waits for a check whose `startedAt` is after the push; and that the checks of the scratch project appear
   within those 10 calls. If they do not, the number is for the maintainer to raise (or to make a key, which would
   be another story trigger).
5. **Separate rounds.** Criterion 2 says "at most `review.maxFixRounds` times"; this spec counts the check fix rounds
   apart from the review's fix rounds (decision 6). Sharing one budget would leave no CI fix after a review that used
   its rounds.
6. **`git branch --no-track` has no run permission.** Decision 4, check 2 creates a missing local branch in a
   resumed `/next` (row N1) with the command "Resuming a story" already uses (iteration 44); iteration 43's rules
   A and B do not cover it, so that step prompts, as the take of iteration 44 does today. A rule for it would be a
   change to `/init`, which this spec does not make (decision 11); whether to add one is for the maintainer.
