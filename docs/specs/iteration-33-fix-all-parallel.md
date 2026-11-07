# Iteration 33: /fix all fixes Ready bugs in parallel and runs until every bug is processed

Status: draft, awaiting approval (#182)

Story: #182, epic #47 (Unattended runs). Rewrites "Batch mode: `/fix all`" in `skills/fix/SKILL.md`. The batch now
runs several bugs at the same time, one per slot, as far as the free slots, the live agent limit and the room on the
machine allow. It frees each bug's slot with the existing `--abandon` once the bug's branch is on its open pull request,
waits instead of stopping when nothing is free, and ends only when every Ready bug has a pull request, was skipped with a
reason, or is listed as not started (because of a limit or a stop). The fixed cap of five bugs goes. In its place there
is one optional config key, `parallel.fixAllMaxBugs` (default 0: no limit). Changes `skills/fix/SKILL.md`, one phrase of
`skills/workflow/SKILL.md` (Parallel work), `schema/nightmill.schema.json`, `templates/nightmill.example.json`,
`README.md`, `CHANGELOG.md`, `tests/lint.sh`, `tests/smoke-slot.sh` and `tests/smoke-slot.ps1`. No change to
`scripts/slot.*`, the slot marker, `capacity.json`, the room or load scripts, any agent file, how a single bug is fixed
(steps 1 to 6, the tester, the fixer, the code review), `/next`, `/status` or the status flow.

**This is a story trigger**: a new config key ("a new, renamed or removed config key"). The status flow, who sets a
status and the slot marker format do not change. The pull request therefore does **not** auto-merge, and it says so.
`skills` is in `verification.manualCheckPaths`, so **the manual check applies** (see Verification). The batch is prose
that a session carries out, and only a real run shows it.

**Order.** The issue's Related line names #113 (an atomic slot claim) as "must land first". This iteration does not
depend on #113's code. It changes no slot script, and it never runs two takes at once in one session (decision 4). The
race #113 fixes is between takes that overlap, which can then only be takes from two different sessions, the same race
as today. The implementation still starts **after #113 has merged**, as the issue asks: a parallel batch makes
overlapping takes from a second session more likely. #128 and #129 change the slot scripts and `tests/smoke-slot.*`.
This iteration changes only `tests/smoke-slot.*` (one new case at the end, see Tests); on a conflict both sides are kept.
The schema is a hot file, and `parallel.doNotPair` forbids two tasks that both change it. This iteration is therefore
never implemented at the same time as #164 or #165 (both add keys), or as any other schema change. Whichever is
Approved first is merged first. `skills/workflow/SKILL.md` is a hot file, and #176 changes it ("Picking an issue"), so
the two are never implemented at the same time. What this iteration assumes from the open stories:

- #165 (limits, kill switch, ledger) does not exist yet. Its pause flag and its limits are obeyed at **the gate**
  (decision 6), the one point before every start. This iteration adds no pause flag and no other limit, and it does
  not decide how #165's "issues per run" combines with `parallel.fixAllMaxBugs`. #165's spec decides that.
- #164 (the unattended driver) runs `/fix all` headless. This iteration gives it a run that ends by itself with one
  table and leaves no agent of the run running (decision 9).
- #176 (claim protocol) does not exist yet. Once it does, its claim is part of a bug's start, before the take
  (decision 5, step 4).

## Goal

One `/fix all` fixes several Ready bugs at the same time while slots and room allow, keeps going while anything can
still free up, and ends only when every Ready bug has been processed or is listed with the reason it was not started.

## Facts this rests on

- Batch mode today (`skills/fix/SKILL.md`, "Batch mode: `/fix all`") runs one bug after another ("One producer at a
  time"; the lint pins that phrase). It takes at most 5 bugs per run, starts each bug on a branch of its own from
  `origin/<git.baseBranch>`, skips a bug that cannot be done, and ends the run on a model that cannot be used or on a
  wait for room that runs out (iteration 28, decision 7). The cap of 5 is text in the skill, not a key.
- Every bug takes a slot (step 3), and the slot is released "after the merge". Nothing waits for a merge, so the slots
  stay busy and the third bug with two slots stops with `all 2 slots are busy; see slot.sh --status` (#117, closed in
  favour of this story). Iteration 17's reap frees a slot only when its PR has **merged**, and only at the next take.
- `slot --abandon N` (both shells) refuses with `slot N has uncommitted files: <dir> (commit, stash or discard them
  first)` when `git status --porcelain` of the slot is not empty. Otherwise it switches the slot to a detached
  `origin/<git.baseBranch>`, **keeps the local branch**, removes the marker and prints
  `Slot N is free (was <branch>; the local branch is kept, delete it yourself if unwanted).` It needs no `gh`. The
  README already says that a slot whose PR is open stays busy "until `-Release` or `-Abandon`".
- A take picks the lowest slot without a marker, writes the marker only at its end, and has no lock (#113). Run one
  after another, two takes get different slots; the smoke tests already show this ("take slot 2, third take fails").
- Worktrees of one repository share their branches and the stash, so a branch or a stash entry left by a slot is not
  lost when the slot is switched to another branch.
- A bug skipped at the tester, or by the stops "the fixer changed the tester's tests" and "nothing committed and the
  dispute is still open", leaves files uncommitted in its slot on purpose (iterations 26 and 27). A bug skipped
  elsewhere has "what exists" committed to the local branch and not pushed.
- Before the PR opens, step 6 sets aside an open dispute's uncommitted files with `git stash push`, "so the tree is
  clean for the slot's release". So after step 6 the slot's tree is clean in every case that opens a PR.
- The agent limit is read live before every launch (`slot --capacity --porcelain`, else `parallel.maxAgents`), and
  the room check runs after the count and before the step report of every launch and every take (iteration 28).
- Each bug already reports its steps to its own slot (iteration 23: "In batch mode each bug reports to its own slot").
  A report to a slot whose marker is gone fails with `slot N is not in use` and changes nothing.
- The validators know `type`, `properties`, `required`, `items`, `minimum`, `minItems`, `additionalProperties` and
  `enum`, and no `maximum`. `review.maxFixRounds` is an integer key with `minimum` 0.

## Decisions

**1. A slot is freed with the existing `--abandon` once its bug's branch is on its open pull request (option a).** The
issue's three options:

- **(a)** `--abandon` after the PR is open needs no new code. It keeps the local branch, and the commits are on the
  remote branch of an open PR, so nothing can be lost.
- **(b)** Waiting for the reap of merged PRs may never free anything while PRs wait for review, which is exactly the
  case the issue names.
- **(c)** A new slot flag would change two hot scripts and add a smoke step to each, and it would do what (a) already
  does.

So (a) is the smallest option, and it never loses work. Before the abandon, the session confirms three things itself
(decision 2), so `--abandon`'s own clean-tree check is a second guard, not the only one. The local branch that
`--abandon` keeps stays after the merge, because the reap only deletes branches of slots that still have a marker. The
skill's final table names it, and deleting it is Not done.

**2. When a slot may be freed, and how a held slot is told apart.** The session frees a bug's slot only when all of
these hold, checked in this order right after step 6 (PR open, status Review read back, auto-merge decided) and after
its `done` report:

1. no agent of this bug is running (every Agent call of the bug has returned);
2. `git -C <slot> status --porcelain --untracked-files=all` prints nothing;
3. `git -C <slot> symbolic-ref --short HEAD` prints the bug's branch;
4. `git -C <slot> rev-parse HEAD` equals the `headRefOid` that `gh pr view <pr> --json headRefOid --jq .headRefOid`
   prints (the branch's last commit is the head of the open PR, so it is pushed).

Then it runs `slot --abandon <n>` (`slot.ps1 -Abandon <n>`) and expects exit 0 and the line `Slot <n> is free`. When any
check fails, or the abandon exits non-zero, the slot is **held**: nothing is changed, the slot keeps its marker and its
files, and the final table names the check that failed. A bug that ends without a PR (skipped, or stopped in flight)
never has its slot freed. Its slot is held whether its tree is dirty (uncommitted tester files, a round's work) or
clean (local commits, not pushed), so `/status` keeps showing it with the step `stopped` for the maintainer.

So the run tells the two kinds of slot apart by the bug's outcome and by the four checks, not by guessing. Only a slot
that this run freed is reused by it, through the next take. A slot held by this run is never reused in this run. Once
a slot is freed, nothing more is reported to it, because its number may already belong to the next bug.

**3. The overlap rule: named files, `parallel.hotFiles` and `parallel.doNotPair`.** Before a bug starts, the session
records its **named files**. A named file is a token of the issue's title or body that, with surrounding backticks,
quotes, brackets, a trailing `:` `,` `.` `)` and a leading `./` removed, equals a path listed by
`git ls-tree -r --name-only origin/<git.baseBranch>`. Two bugs **overlap** when any of these holds:

- their named files share a path;
- each names a file inside the same entry of `parallel.hotFiles` (an entry is a file or a directory; a path is inside a
  directory entry when it starts with the entry followed by `/`);
- the session judges that the two bugs, by their named files and titles, are a pair `parallel.doNotPair` describes
  (it is prose, so this is a judgement, stated in the final table's reason when it delays a bug).

A bug that overlaps a bug started earlier in this run that is still in flight does not start. It waits until that bug
has its PR open or has ended (skipped or stopped), and bugs after it in the order may start before it. Files named in
the issues are taken as enough for this rule, with no guess about what a fix will touch beyond them: the issue asks for
"files named in both issues", and a wider guess would hold back bugs that do not conflict. An overlap that shows only
in the diff keeps the existing rule: a PR that changes a file an earlier PR of this run changed says
`overlaps #N, will conflict until that merges`.

**4. Slots are taken one at a time.** The session runs a take (`slot --take`) only as a foreground shell call, never in
the background and never in the same message as another take or an abandon. It runs the next slot command only after
the previous one has exited. Two starts of this run can therefore never get the same slot, with or without #113.

**5. The scheduling loop.** The session holds four lists: **waiting** (in order), **in flight** (bug, slot, next
step), **ended** (PR, skipped, stopped) and **not started**. The order of waiting is `board.priorities` (highest first;
no priority ranks last), then the issue number, lowest first. The loop runs once at the start and again after every
event: an agent of the run returned, a bug's session step ended, a slot was freed, a take failed. One pass:

1. **In flight first.** For each bug in flight whose next step is a launch (tester, fixer, code review, a dispute or
   fix round), in the order the bugs started, launch it by the bug's own rules: count the agents (the live limit), then
   the room, then the step report. A bug's own order stays: its tester has returned before its fixer is launched, and
   it never runs two of its agents at once. A launch that the count does not allow waits for the next event.
2. **Then new starts**, while all of these hold: the gate allows a start (decision 6); the number of agents running is
   below the live agent limit; the run limit is not reached (decision 7); and the last take of this run did not fail
   with `all <k> slots are busy` since the last event that could free a slot (a slot of this run freed, or a bug of
   this run ended).
3. **A start**, for the first waiting bug that overlaps no bug in flight:
   1. read it (`gh issue view N --json number,title,labels,body`) and record its named files;
   2. step 2 (is it a bug?). A story is skipped: `needs a story`, no status change, no slot. Then go on with the next
      waiting bug;
   3. check the room for the take (the take's warm-up is a slot build), then **take** (decision 4);
   4. on `Slot <n> is yours`: the claim of #176 once it exists, then set In progress and read it back, report
      `slot-taken`, and go on with "The tester" (count, room, launch). On `all <k> slots are busy`: the bug stays first
      in waiting, and no start is tried until an event that could free a slot. On any other failure of the take, the
      run stops (decision 8).
   Then try the next start, from step 2.
4. **The board again.** Before each start, and once more when waiting is empty, list the Ready bugs again (the step 1
   query). Every open `labels.bug` issue at Ready that this run has not seen yet joins waiting in its place in the
   order. Each issue is processed at most once per run: a bug skipped as `needs a story` stays Ready and is not taken
   again.
5. **Waiting.** When nothing can be launched or started, the session waits for the next agent of the run to return
   (it says once what it waits for, for example `waiting for a slot: #118 and #121 are in flight`).
6. **The end.** The run ends when waiting is empty after the last board read and nothing is in flight. It also ends
   when nothing of this run is in flight but bugs are still waiting: then the last take failed, and no slot can free in
   this run. Those bugs are listed as not started, with `no slot frees in this run: <each busy slot and what holds it,
   from slot --status>`. A busy slot therefore never ends the run while a bug of this run is still in flight. It ends
   the run only when nothing this run does can free one.

Agents go out without waiting on each other. The session launches each agent as a background agent where its Agent
tool runs agents in the background and says when one ends. Otherwise it puts the launches that are due at the same
moment into one message, so they run at the same time. The session's own work for a bug (the board, the slot commands,
the tester's-files checks, the manual check, the pull request) is done for one bug at a time, between events.

Without `worktrees` (one checkout, no slots), nothing runs in parallel. One bug at a time, as before, on its own branch
from up-to-date `origin/<git.baseBranch>`; after its PR is open, switch back to the base branch, `git pull --ff-only`,
and start the next. The order, the run limit, the board read, the gate, the stops and the table are the same.

**6. The gate.** Every new start passes one gate first (step 2 of the loop). Today it holds the run limit, the count
and the room. The pause flag and the limits of an unattended run (#165), once they exist, are checked there before
each start, by the rules #165 sets. A pause stops new starts. Whether it also stops the launches of bugs in flight is
#165's rule, not this one.

**7. The run limit is a config key: `parallel.fixAllMaxBugs`, integer, default 0, 0 means no limit.** It is the most
bugs one `/fix all` run starts. A bug counts when its take succeeds (or, without slots, when its step 3 begins); a bug
skipped as `needs a story` before a take does not count. With the limit reached, no new start happens. Bugs in flight
finish, and every bug still waiting (also one that became Ready later) is listed as not started with
`run limit of <k> reached`. The key goes under `parallel`, beside the other numbers of a parallel run, rather than in a
new section. 0 as "no limit" keeps it an integer with `minimum` 0, which the validators know (no `null` type, no
`maximum`). The session reads it from the configuration at the start of the run. It is used when it is a JSON number
written as a whole number from 0 without sign, fraction or exponent; absent or `null` means 0. Any other value (`-1`,
`2.5`, `"3"`, `true`) stops the run before anything is started:
`Stopped: parallel.fixAllMaxBugs must be a whole number of at least 0 (0: no limit), got <the value as JSON>. Nothing was started.`
A limit that cannot be read is never taken as "no limit" for an unattended run.

**8. Skips and stops.** A skip ends one bug and the run goes on. It covers every skip of today's batch mode: a story,
a bug the tester cannot reproduce, the other `Stopped:` lines of "The tester", a `failed` fixer, a check still red
after three honest attempts, a fix that grows into a story trigger, the two tester's-tests stops, and a code review
that could not be had. The bug's slot stays held (decision 2), its status stays (never Ready), and the session
reports `stopped` to its slot.

A **stop** ends the run. It covers a model that cannot be used (any role), a wait for room that runs out, an unusable
`parallel.fixAllMaxBugs`, a take that fails other than with `all <k> slots are busy`, and the existing whole-run stops
(a dirty working tree at the start, `git` or `gh` failing on authentication or network, the check red on a clean base
branch). After a stop:

- no new bug starts, and no agent is launched;
- every agent already running is waited for, and its result is read and checked by that bug's rules;
- a bug whose next step needs no agent, no manual check and no room (only opening the PR after its last review) opens
  its PR and is freed by decision 2;
- every other bug in flight stays where it is (status In progress, slot taken, files as they are) and reports
  `stopped`.

Then one line, the stop's own text followed by the two lists:

`<the Stopped: line of the cause> Not started: #<n>, #<n> | none. Stopped in flight: #<n> at <step>, #<n> at <step> | none.`

`<step>` is the bug's last reported step. The final table follows.

**9. The final table.** The run ends with one table and one count line, after the `Stopped:` line when there is one,
and after every agent of the run has returned:

```
| Bug | Result | PR | Slot | Cause or reason | Verified |
|---|---|---|---|---|---|
| #<n> <title> | pull request | #<pr>, auto-merge on | <s> freed | <the fixer's Cause line> | check green; manual check done |
| #<n> <title> | pull request | #<pr>, auto-merge off: <why> | <s> held: <the check of decision 2 that failed> | <Cause> | <...> |
| #<n> <title> | skipped | - | <s> held: uncommitted files | not reproduced: <the reason> | - |
| #<n> <title> | skipped | - | <s> held: local commits, not pushed | <why it was skipped> | <...> |
| #<n> <title> | skipped | - | - | needs a story | - |
| #<n> <title> | stopped | - | <s> held | stopped at <step> | - |
| #<n> <title> | not started | - | - | run limit of <k> reached / the run stopped / no slot frees in this run: <...> | - |

<a> with a pull request, <b> skipped, <c> stopped, <d> not started; local branches kept by freed slots: <branches | none>.
```

`<title>` is without a leading `[Bug] `. The rows are the started bugs in the order they started, then the skipped
`needs a story` bugs and the not-started bugs in the order of waiting. Verified is `check <green | red>`, then
`manual check done`, `manual check not done: <why>` or `manual check not needed`. A bug delayed by an overlap adds
`; waited for #<n> (overlap: <the shared path, the hot file entry, or doNotPair>)` to its Cause or reason.

**10. No new report step and no marker change.** The steps of "Reporting the steps" stay as they are. `done` is
reported before the abandon, and nothing is reported to a slot after it is freed. While a bug is in flight, its slot
shows it `running` or `stalled` in `/status`, the page and the pane, as every slot does. A bug that is waiting has no
slot and appears in none of them. That is the issue's "every bug of the batch", read as every bug that has started.

## The skill: `skills/fix/SKILL.md`

- The frontmatter description: `"all" fixes every Ready bug, several at once while slots and room allow.` in place of
  `"all" works through every Ready bug in turn.`; the first line: `(`all` = every Ready bug, in parallel, see "Batch
  mode")`.
- Step 3: after `-Release N` after the merge, add `(in "Batch mode" the slot is freed once its pull request is open)`.
- "Batch mode: `/fix all`" is rewritten from decisions 1 to 9 with these bullets, in this order:
  - **In parallel, one slot per bug**: the loop of decision 5, the agents in the background, the gate (decision 6).
  - **One producer at a time per bug** (keeps the lint's pinned phrase): the bug's own order; the count, the room and
    the report per launch, as "The tester", "The fixer" and "The code review" say.
  - **Order, the run limit and new Ready bugs**: decision 5 steps 3 and 4, decision 7, with `parallel.fixAllMaxBugs`
    and its `Stopped:` line verbatim.
  - **One take at a time**: decision 4.
  - **Overlapping bugs wait**: decision 3, with the `overlaps #N` PR sentence.
  - **Freeing the slot once the PR is open**: decision 2, with the four checks, the abandon command of both shells and
    the held cases. This replaces "After a bug's PR is open, switch back to the base branch, `git pull --ff-only`, and
    start the next" for slots, and that sentence stays only in the paragraph "Without `worktrees`".
  - **A bug that cannot be done is skipped, not stopped on** (today's text, unchanged, including "Commit what exists"
    and the stash lines for a single checkout), plus `its slot stays held`.
  - **The whole run stops** (today's three causes, plus the stops of decision 8), with the `Not started:` /
    `Stopped in flight:` line verbatim.
  - **Never** (today's text, unchanged: `git.mergeFlags` on a complete fix only, no push to the base branch, no issue
    closed or edited by hand), and never set Ready or Approved.
  - **End with a table**: decision 9's table and count line verbatim.
- `At most 5 per run; the rest go in the report for the next run.` is removed, and so is "the next bug starts only
  after the previous bug's fixer has returned or its run stopped". The skill does not say "One fixer at a time" (the
  lint forbids it).

## The workflow skill: `skills/workflow/SKILL.md`

One phrase in **Parallel work**, first bullet: `free it after the merge (`-Release N`)` becomes `free it after the
merge (`-Release N`), or, in `/fix all`, once its pull request is open and its branch pushed (`-Abandon N`; see
`/fix`)`. Nothing else in the workflow skill changes.

## The config key

`parallel.fixAllMaxBugs`: integer, default 0, minimum 0; 0 means no limit (decision 7).

- **Schema**, in `properties.parallel.properties` after `controlIntervalMinutes`, on one line in the form of its
  neighbours:
  `"fixAllMaxBugs": { "type": "integer", "minimum": 0, "default": 0, "description": "The most bugs one /fix all run starts (a bug counts when its slot is taken). 0: no limit, every Ready bug is taken. Bugs past the limit are listed as not started." }`
- **Example template**: `"fixAllMaxBugs": 0` in `parallel` of `templates/nightmill.example.json`, after
  `controlIntervalMinutes`. This repository's `.claude/nightmill.json` is not changed.
- **README**, the configuration table's `parallel` row (see README).
- **Read by** `/fix all` only, once at the start of the run. No script reads it.
- The previous version ignores the key; its validator warns `unknown key` for it (not an error).

## README

- "What is in the plugin", the `/nightmill:fix [N\|all]` row: `` `all` fixes every Ready bug, several at once (one per
  free slot, within the agent limit and the room), and ends with one table. `` in place of
  `` `all` works through every Ready bug. ``
- Configuration table, the `parallel` row, at the end: `; and for `/fix all` the most bugs one run starts
  (`fixAllMaxBugs`, default 0: no limit)`.
- "Why slots", after the paragraph on the automatic release, a paragraph: `/fix all` runs one bug per slot and frees a
  bug's slot itself once its branch is on its open pull request (`-Abandon`; the local branch is kept, so a few slots
  serve a long list); a slot whose bug was skipped stays busy with its files for the maintainer; overlapping bugs (a
  file named in both issues, the same `parallel.hotFiles` entry, `parallel.doNotPair`) do not run at the same time;
  the run ends when every Ready bug has a pull request, was skipped, or is listed as not started, with one table.
  The sentence "A slot whose pull request is open ... stays busy until `-Release` or `-Abandon`" gains `(`/fix all`
  abandons it itself)`.

## CHANGELOG

One bullet under `Unreleased`, in the form of the others: `- Iteration 33 (#182): /fix all fixes Ready bugs in
parallel and runs until every bug is processed. ...`. It names: one bug per slot within the live agent limit and the
room; slots taken one at a time; the order; a slot freed with `-Abandon` once the branch is the open PR's head, and a
skipped bug's slot held; the overlap rule; waiting instead of stopping on a busy slot; new Ready bugs picked up; no cap
of five; the key `parallel.fixAllMaxBugs` (default 0: no limit), ignored by the previous version; the `Not started:`
line; and the final table.

## Tests

The skill is prose that a session carries out. So the lint pins the wording the behaviour depends on, one smoke case
pins the slot behaviour the freeing relies on, and the manual check does the behaviour.

**`tests/lint.sh`**, new section "== /fix all runs bugs in parallel". Each phrase stands on one line of its file
(`grep -F`):

- `skills/fix/SKILL.md` contains `parallel.fixAllMaxBugs`, `Stopped: parallel.fixAllMaxBugs must be a whole number of
  at least 0`, `One producer at a time per bug`, `one take at a time`, `--abandon`, `-Abandon`,
  `--json headRefOid`, `--untracked-files=all`, `held: uncommitted files`, `Not started:`, `Stopped in flight:`,
  `run limit of <k> reached`, `no slot frees in this run`, `parallel.hotFiles`, `parallel.doNotPair`,
  `overlaps #N, will conflict until that merges`, `pause flag`, `| Bug | Result | PR | Slot | Cause or reason | Verified |`
  and `git.mergeFlags`; and does not contain `At most 5 per run` or `One fixer at a time`.
- `skills/workflow/SKILL.md` contains `once its pull request is open and its branch pushed`.
- The schema contains `"fixAllMaxBugs": { "type": "integer", "minimum": 0, "default": 0,`;
  `templates/nightmill.example.json` has `parallel.fixAllMaxBugs` equal to 0 (read with `json.sh`, as the other
  template checks do).
- `README.md` contains `fixAllMaxBugs` and `abandons it itself`.

The existing sections still pass (among them "a tester reproduces the bug before /fix", with `One producer at a time`
and `Tester files for #<issue>: <title>`, and "config validates"). The validator accepts the example template with the
key and warns on no other line.

**`tests/smoke-slot.sh` and `tests/smoke-slot.ps1`**, one new case at the end, before `SMOKE OK`, the same in both:
"13 a slot is freed once its branch is pushed, and a dirty slot is held". With every slot free and the gh log reset:

1. Take `feat/p1`: `Slot 1 is yours`. Take `feat/p2`, run after it: `Slot 2 is yours`. A third take `feat/p3` fails
   with `all 2 slots are busy`, and both markers are byte for byte as before it.
2. In slot 1, commit one file and `git push origin feat/p1`, keeping the tip. `--abandon 1` (`-Abandon 1`) exits 0 and
   prints exactly `Slot 1 is free (was feat/p1; the local branch is kept, delete it yourself if unwanted).` Then the
   marker of slot 1 is gone, `refs/heads/feat/p1` is the tip, the bare origin's `refs/heads/feat/p1` is the tip, and
   slot 1's HEAD is detached.
3. Take `feat/p3` again: `Slot 1 is yours` (the freed slot is reused).
4. Write an untracked file in slot 1. `--abandon 1` exits non-zero with `slot 1 has uncommitted files:` on standard
   error. The marker is byte for byte as before, the file is still there, and the branch is still `feat/p3`.
5. The gh log is empty (neither the take nor the abandon of this case asked `gh` for anything but the reap's merged
   query, which finds nothing). Clean up: remove the file, abandon slots 1 and 2.

`bash tests/check.sh` stays green and runs both cases where the machine can.

**What each criterion is checked by.** Criteria 1, 2, 3, 5, 8, 9, 10, 11 and 12 can be checked **only manually**,
because the skill is prose. The lint pins only their wording.

| Criterion | Lint | Smoke | Manual (Verification) |
|---|---|---|---|
| 1 in parallel, up to slots, live limit, room | `One producer at a time per bug` | - | step 2 (two at once), step 5 (limit 1 at a time) |
| 2 waits, a busy slot never stops the run | `no slot frees in this run` | - | step 2 (the third bug starts when a slot frees) |
| 3 priority, then number | - | - | step 2 (the start order) |
| 4 freed once on its PR, no work lost, never with uncommitted files | `--abandon`, `--json headRefOid`, `held: uncommitted files` | case 13, 2 to 4 | step 2 (freed slots reused; the skipped bug's slot held) |
| 5 overlapping bugs do not run at the same time | `parallel.hotFiles`, `parallel.doNotPair` | - | step 2 (B waits for A's PR) |
| 6 slots taken one at a time | `one take at a time` | case 13, 1 | step 2 (no two takes in one message) |
| 7 no cap of five; optional limit, default none | `parallel.fixAllMaxBugs`, no `At most 5 per run`, schema and template pins | - | step 3 (limit 1), step 2 (six bugs, no cap) |
| 8 a bug Ready during the run is picked up | - | - | step 2 (bug F) |
| 9 a skip does not stop the others; model and room end the run with `Stopped:` | `Not started:`, `Stopped in flight:` | - | step 2 (C skipped), step 4 (model) |
| 10 each bug reports to its own slot | - | - | step 2 (`/nightmill:status` during the run) |
| 11 one table at the end | the table header | - | steps 2 to 4 |
| 12 pause flag and limits at each start | `pause flag` | - | not checkable until #165 exists; step 3 shows the gate with the run limit |
| 13 `git.mergeFlags` only; no maintainer status | `git.mergeFlags` | - | step 2 (board and PRs afterwards) |

## Verification

`skills` changes, so the manual check applies, and it is the issue's own. Run it in a throwaway project with a board
and slots (not this repository), from another folder, with nightmill loaded from a separate checkout of this branch
(`claude --plugin-dir <checkout>`). The installed release must not be loaded in that session (decision 0003). The
config has `"worktrees": { "slots": 2 }` and `"parallel": { "maxAgents": 2 }`. The project has a check that passes and
a few small files with a defect each. Run `bash tests/check.sh` on the branch first and record its skipped list.

1. **Setup.** File six bugs and set them Ready by hand, except F:
   - A (High) names `src/a.txt`;
   - B (High) also names `src/a.txt`;
   - C (Medium) is not reproducible;
   - D (Medium);
   - E (Low);
   - F (Low), left in Backlog.
2. **The main run.** Run `/fix all`. Watch for each of these:
   - A and C start first (B overlaps A and waits; C is next in order), each in its own slot, and both run at the same
     time (two agents);
   - no two takes are in one message;
   - `/nightmill:status` in another session shows both slots busy and `running` with `fix` and their steps;
   - C is skipped at the tester, and its slot stays busy with the tester's files, step `stopped`;
   - when A's PR opens, its slot is freed (`Slot <n> is free`), and B starts in it;
   - while A is in flight, set F to Ready on the board, so F is taken before the run ends;
   - D, E and F follow in that order as the free slot comes back;
   - the run ends with the table: A, B, D, E and F with a pull request, C skipped (`not reproduced: ...`, slot held),
     B's reason naming `waited for #A`, and the count line naming the kept local branches;
   - afterwards every PR auto-merges only by `git.mergeFlags`, no status is Ready or Approved that was not set by hand,
     the free slots are clean and detached, and the held slot is unchanged.
3. **The run limit.** `"fixAllMaxBugs": 1`, two Ready bugs: one gets a PR, the other is `not started` with
   `run limit of 1 reached`. With `"fixAllMaxBugs": "2"` the run prints the `Stopped: parallel.fixAllMaxBugs ...` line
   and starts nothing.
4. **A stop.** `roles.fixer.model` set to `no-such-model`, two Ready bugs: the run ends with
   `Stopped: the fixer role cannot run on no-such-model: ...` followed by `Not started:` and `Stopped in flight:`, and
   then the table.
5. **One agent.** `slot --capacity --agent-limit 1` with two slots and two Ready bugs: never two agents at once; the
   second bug starts after the first bug's agents leave room.
6. **One checkout.** Without `worktrees`, two Ready bugs are fixed one after the other on their own branches.

Afterwards close the test PRs, abandon the slots, and clear the capacity. The PR's "How verified" lists each step's
result, the check and its skipped list, and says that auto-merge is off because the change is a story trigger (a new
config key).

## Not done

- No new slot flag, no change to `scripts/slot.*`, the slot marker, `capacity.json` or the reap. The local branches
  that `--abandon` keeps are not deleted after their merge.
- No freeing of a slot whose bug has no open PR, whether skipped or stopped, dirty or clean.
- No waiting for a merge and no merge. Parallel `/next` stories are out of scope, and how a single bug is fixed (steps
  1 to 6, the tester, the fixer, the code review, the reports) does not change.
- No pause flag, kill switch, ledger or other limit (#165), no driver (#164), no claim (#176). Only the gate where they
  will be checked.
- No guess at the files a fix will touch beyond those the issue names, `parallel.hotFiles` and `parallel.doNotPair`.
- No waiting on slots held by other sessions once nothing of this run is in flight.
- No change to the status flow or to who sets a status; no decision record.

## Left

- The issue says "a busy slot never stops the run". This spec reads it as "never while a bug of this run can still
  free a slot" (decision 5, step 6). When nothing of the run is in flight and every slot is held (by this run's
  skipped bugs or by other work), the run ends and lists the rest as not started, instead of waiting without end for
  slots that only the maintainer or a merge frees. The maintainer confirms this reading at Spec review.
