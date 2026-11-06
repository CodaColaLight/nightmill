# Iteration 27: the implementer may not change the tester's tests, and a doubtful test goes back to the tester

Status: draft, awaiting approval (#44)

Story: #44, epic #41 (Independent test writing). Guards the tests that the tester of iterations 25 and 26 writes: the
implementer's prompt in `/next` and the fixer's prompt in `/fix` forbid editing or deleting the tester's files; after
every result of the implementer or the fixer the session checks with git, file by file, that each of the tester's files
still holds what the tester left, and undoes a change as a failed round; and a test the implementer or the fixer
believes is wrong or cannot be satisfied is reported as a dispute, which the session hands back to the tester, who
revises the test or answers why it stands. A dispute and an undone round each use one of `review.maxFixRounds`; a
dispute still open when the rounds are used up is listed in the pull request and keeps auto-merge off. Changes
`skills/next/SKILL.md`, `skills/fix/SKILL.md`, `agents/tester.md` (one rule and one result line), one sentence of
`skills/workflow/SKILL.md`, `README.md`, `tests/lint.sh` and `CHANGELOG.md`.

**Not a story trigger.** No config key is added, renamed or removed: the rounds are `review.maxFixRounds` (iteration 18),
the tester's model is `roles.tester.model` (iteration 10). The status flow, who sets a status and the slot marker format
do not change; the new report step `dispute-<k>` is a value the report command of iteration 23 already accepts. No
script changes (decision 1). The PR may auto-merge. The change touches `skills` and `agents`, so the manual check of
`verification.manualCheckPaths` applies.

**Order.** #42 (iteration 25) and #43 (iteration 26) are delivered and on `main`; #36 and #37 (iterations 18 and 19,
the code review, the fix rounds and the `## Review` section) too. The changes below are written against
`skills/next/SKILL.md`, `skills/fix/SKILL.md`, `agents/tester.md` and `skills/workflow/SKILL.md` on `main` today. No step
is renumbered, so every "step N" reference in the skills and in iteration 23's tables stays valid.
`skills/workflow/SKILL.md` is in `parallel.hotFiles`.

## Goal

The implementer (or the fixer) makes the tester's tests pass without touching them, and a test it believes is wrong
returns to the tester instead of being changed.

## Facts this rests on

- Iteration 25: the tester (`agents/tester.md`, tools `Read, Grep, Glob, Write, Edit, Bash`) writes only test paths
  (the `Test paths:` line), does not delete files, and leaves its files **uncommitted** in the slot. The session records
  `<tester files>`, the paths of `git -C <slot> status --porcelain --untracked-files=all` after the tester returned (the
  tree was clean before it), so a tester file is either a new file or a change to a file that exists on the base branch.
  The implementer commits the tester's tests with its code once the check is green (decision 4). A `partial`
  implementer leaves the test file of an unmet criterion uncommitted, lists it under Left as `unmet: <path> (criterion
  <n>)`, and sets it aside to run the check and commit with
  `git -C <slot path> stash push --include-untracked -m "Unmet tests for #<issue>: <title>" -- <the paths>`, popping that
  entry by its message afterwards, never the top entry blindly (every worktree shares one stash). The session's tree
  check accepts exactly those paths; step 5 stashes them before the rebase so the tree is clean for the session's
  commit, the rebase and the slot's release (decision 10). Its "Not done": the no-editing rule and the way back to the
  tester are #44's; "nothing in the workflow detects an edit yet"; no re-run of the tester in a fix round.
- Iteration 26: the same tester writes one regression test before the fixer; the fixer commits it with the fix once
  the check is green, and the session checks that every path of `<tester files>` is in
  `git -C <slot> diff --name-only origin/<git.baseBranch>..HEAD`. The fixer's prompt says "A fix that does not make this
  test pass is not a fix: then commit nothing, report `failed`". Its decision 7: the no-editing rule is #44's and applies
  to the fixer through the same prompt paragraph as to the implementer.
- Iterations 18 and 19 ("Findings and fix rounds" in the workflow skill): the first review is round 0; while blocking
  findings remain and fewer than `review.maxFixRounds` fix rounds have been used, a fresh producer of the same role and
  model fixes them, runs the check and commits, and the reviewer runs again; at most `1 + review.maxFixRounds` reviews.
  The pull request has a `## Review` section after "How verified" with `- Fix rounds used: <r> of <review.maxFixRounds>`;
  with a blocking finding still open the pull request is opened all the same and says
  `Auto-merge is not enabled: blocking review findings are still open (see Review).` `review.maxFixRounds` has the
  default 2 and the minimum 0.
- Iteration 23: `/next` and `/fix` report steps with `slot --report <step> --slot <n> --skill <s> --role <r>`; the session
  reports `fix-round-<k>` (role `implementer` or `fixer`) just before the launch of fix round k and `write-tests` (role
  `tester`) just before the tester. A step is 1 to 40 characters of `A-Z`, `a-z`, `0-9` and `-`, starting with a letter
  or digit; a failed report never stops a run.
- The session pushes the branch only when it opens the pull request (`/next` step 6, `/fix` step 6), so every commit of
  the implementer or the fixer before that is local to the slot. The only commit the session makes itself is `/next`
  step 5's (the CHANGELOG entry and the spec's status line), on a tree made clean first.
- `git hash-object -w -- <path>` stores the file's content, after the clean filters a commit would apply, as a blob in
  the repository's object store and prints its id; the store is shared by every worktree, and a blob stays there for the
  run (git prunes loose unreachable objects only after `gc.pruneExpire`, two weeks by default).
  `git rev-parse -q --verify HEAD:<path>` prints the id of the blob HEAD holds at that path, or nothing.

## Decisions

**1. The guard is git commands in the skills, not a script.** The check is three git commands per file and the undo four,
all run by the session in the slot. A script would need a `.ps1` and a `.sh` with smoke steps in both, for commands the
session can run as they are; the skills already run their checks (`status --porcelain`, `log`, `diff --name-only`) the
same way. So the guard is skill text, written once per skill (as "The tester" is), and the lint pins its commands. The
price: the commands are not run by a smoke test; the manual check runs them by hand (Verification, step 4).

**2. A tester file is guarded by its content, recorded as a blob.** When the tester's result has passed the session's
checks, the session records for every path of `<tester files>` one line of `<tester blobs>`: `<path> <blob> <head>
<mode>`, where `<blob>` is printed by `git -C <slot> hash-object -w -- <path>` (the content the tester left, written
into the object store as the pristine copy), `<head>` by `git -C <slot> rev-parse -q --verify HEAD:<path>` (`none` when
it prints nothing: the file is new), and `<mode>` is the first field of `git -C <slot> ls-tree HEAD -- <path>` when
`<head>` is not `none`, else the mode of the line `new file mode <mode>` that
`git -C <slot> diff --no-index -- /dev/null <path>` prints (git alone, the same in bash and PowerShell; its exit code 1
means only that the files differ). A
tester file whose file is missing when it is recorded (the tester deleted a file, which its agent forbids) stops the run
with `Stopped: the tester returned failed: it deleted <path>`. The pristine copy lives only in the object store, never in
the stash (shared by all worktrees) and never in a file of the slot.

**3. "Unchanged" means: the file holds the tester's text, and HEAD holds either that text or what it held before.** A
tester file is unchanged when both hold:
- `git -C <slot> hash-object -- <path>` prints `<blob>` (the file exists and holds the tester's text), and
- `git -C <slot> rev-parse -q --verify HEAD:<path>` prints `<blob>` (committed as the tester wrote it) or prints
  `<head>` (not committed: still as before the tester; for `<head>` `none`, it prints nothing).

Anything else is a change: an edited, emptied, moved or deleted file, or a commit that holds other content at that path.
So a tester file left uncommitted and byte for byte unchanged (the test of an unmet criterion of iteration 25 decision
10, or a disputed test) is **not** a change, and a file committed with the tester's text is not either. The rule looks
at the result, not the history: a commit that changed the file and a later commit of the same round that put the
tester's text back leave it unchanged. The hashes are taken with git's filters (never `--no-filters`), so a line-ending
conversion on checkout is not a change.

**4. A new test file is told apart by its path alone.** The tester's files are exactly the paths of `<tester files>` (and
those a dispute adds, decision 8); every other path is not the tester's. "Tests of their own in separate files" means
files that are not in `<tester files>`: a new file, or an existing test file the tester did not touch. A tester file is
the tester's as a whole: when the tester added its tests to an existing file (in this repository, often
`tests/lint.sh`), the implementer adds no test of its own to that file, but writes it in another one (and wires it into
the check where the project needs that). The issue says "in separate files"; a line-by-line rule inside a shared file
cannot be checked mechanically.

**5. When the session checks.** After every result of the implementer or the fixer (the first launch and every fix
round, whatever the `Result:` says, also `failed` and a missing block) and before any other check of that result, the
session checks every line of `<tester blobs>` by decision 3. Before every launch of the implementer or the fixer it
records `<round base>`, the output of `git -C <slot> rev-parse HEAD`.

**6. A change is a failed round, undone without losing the producer's other work.** When one or more tester files
changed, the session undoes the round, in this order:
1. `git -C <slot> merge-base --is-ancestor <round base> HEAD` must succeed (the branch still contains the round's
   start); otherwise stop with `Stopped: the <role> returned failed: the branch no longer contains <round base>`.
2. `git -C <slot> reset --mixed -q <round base>`: the round's commits are taken back; their changes, and everything else
   the round left in the working tree, stay in the working tree, uncommitted. Nothing is deleted, nothing is pushed
   (nothing was pushed yet), no stash entry is popped or dropped.
3. For every changed tester file, from its line of `<tester blobs>`:
   `git -C <slot> update-index --add --cacheinfo <mode>,<blob>,<path>`, then `git -C <slot> checkout-index -f -- <path>`
   (writes the tester's text into the working tree, creating its directory, with git's filters), then
   `git -C <slot> reset -q -- <path>` (the index at that path is HEAD's again; the file is uncommitted, as the tester
   left it). Git writes the file; no shell redirection is used, so the bytes are the same in bash and PowerShell.
4. Check every line of `<tester blobs>` again by decision 3; one that still fails stops with
   `Stopped: the <role> returned failed: the tester's file <path> could not be restored`.

The round is then failed: it counts as one fix round (decision 9). Its `Disputes:` line is not passed to the tester; a
later round may report it again. With `Result: failed` or no result block, the existing stop line follows, with
`; its change to the tester's tests was undone: <the paths>` added after `<Left>`. Otherwise, while a fix round is
left, the next round is launched with the prompt and the paragraph "The previous round changed ..." (below), and when
the undone round was a review fix round, the blocking findings it was to fix are passed again in that prompt, and when
it followed a dispute exchange, the tester's answers are passed again as well ("The tester has answered the dispute",
below); when none
is left the session prints
`Stopped: the implementer changed the tester's tests: <the paths, comma-separated>. The change was undone and no fix round is left.`
(`/fix`: `Stopped: the fixer changed the tester's tests: ...`) with the branch and the slot, leaves the status at In
progress, the slot taken and the round's work uncommitted in the slot, and pushes nothing. The undo itself makes no
commit, so "Verify before every commit" is not touched.

**7. A dispute is reported in the result block, and the disputed test is set aside like the test of an unmet
criterion.** The producer's result block gains the line
`Disputes: <one line per disputed test: <test name> (<file>): <why it is wrong or cannot be satisfied, one line>; none>`.
A producer that disputes a test does not change it: it leaves the file as it is (uncommitted when it is not committed
yet), sets it aside with the files of unmet criteria to run the check and commit the rest (the stash command and message
of iteration 25 in `/next`; in `/fix` the message `Disputed test for #<issue>: <title>`), pops that entry by its message,
and reports `Result: partial`. It may commit its other work once the check is green, or nothing when nothing else is
ready (then the log check accepts an empty log). In `/fix` this is the one exception to "A fix that does not make this
test pass is not a fix": a fixer that disputes the test may commit its fix when the check is green with the test set
aside. The session's tree check accepts, as dirty, exactly the `unmet:` paths (in `/next`) and the files of the
`Disputes:` lines, when they are in `<tester files>`. A disputed test whose file was already committed in an earlier
round (it passed then) cannot be set aside: the producer leaves it committed and unchanged and commits nothing that
turns it red.

**8. The tester answers a dispute in a second launch, in the same slot, and writes only the disputed files and new
test files.** The session launches `nightmill:tester` again (counted, on `roles.tester.model`, passed explicitly, never
a fork) with the dispute prompt (below). The agent gains one rule: with a dispute in its prompt it reads the spec (or
the bug report), the disputed test and the reason, and for each disputed test either revises it (the test still checks
what the criterion promises; never weakened to let code pass) or leaves it and says why it stands; it changes only the
files named in the disputes and may add new files on test paths; it runs each revised test and reports under `Failing`
whether it passes or fails against the code now in the slot (the rule "confirm that they fail because the behaviour is
missing" does not apply to a dispute); it commits nothing. Its block gains the line `Answers:`, with one line per
disputed test, `<test name> (<file>): revised: <what changed and why, one line>` or `<test name> (<file>): stands: <why
the test is right, one line>`; `none` on a first launch. `Result: complete` means every disputed test has its line.

Just before each dispute launch the session records `<dispute base>`, the output of `git -C <slot> rev-parse HEAD` (the
disputing producer may have committed its other work, decision 7, so this is not `<round base>`). The session checks the
dispute launch, in this order: `git -C <slot> rev-parse HEAD` is still `<dispute base>` (the tester committed nothing);
every path of `git -C <slot> status --porcelain --untracked-files=all` is a test path by the `Test paths:` line; every
line of `<tester blobs>` whose file is not named in a dispute is unchanged by decision 3; every listed path that is not
in `<tester files>` is untracked (`??`, a new file); every disputed file exists. Then the session decides each disputed
path by its hash alone, `git -C <slot> hash-object -- <path>` against the `<blob>` of its line of `<tester blobs>`; the
three cases exclude each other:
- a disputed path whose hash equals its <blob> keeps its old line;
- a disputed path whose hash differs from its <blob> and has a revised: answer is revised: its new line replaces the old line of <tester blobs> for that path;
- a disputed path whose hash differs from its <blob> and whose answers are all stands: fails the check, with `Stopped: the tester returned failed: it changed <path> but answered every test in it stands:`.

A revised path's new line is recorded by decision 2, so the check of decision 5 after the next round compares against
the revised text and an undone round restores it. A file with both a revised and a standing test is revised (its hash
changed); its standing tests keep their `stands:` lines under `Answers:`. The session also records, by decision 2, a
line of `<tester blobs>` for every new file and adds the new files to `<tester files>`. A `Result:` other than
`complete`, a missing block or `Answers:` line, or a failed check stops with
`Stopped: the tester returned failed: <Left, or the check that failed>` with the branch and the slot (status In
progress, slot taken; commit, push and revert nothing).

**9. One budget: a dispute exchange and an undone round each cost one fix round.** The fix rounds of a run are the
launches of the producer after its first one, numbered 1, 2, ... in order, whatever the cause: blocking review findings,
a dispute exchange (the tester's dispute launch and the producer's launch after it are one round, k), or an undone round
(decision 6). At most `review.maxFixRounds` are used; `- Fix rounds used: <r> of <review.maxFixRounds>` of the `## Review`
section counts all of them. A dispute that arrives while no fix round is left is not sent to the tester; it stays open.
The code review runs after every producer result that is not undone and not answered by a dispute exchange, so the last
result is always reviewed and a run still has at most `1 + review.maxFixRounds` reviews.

**10. An open dispute: the pull request is opened, lists it and does not auto-merge.** A dispute is open when the last
producer result's `Disputes:` line is not `none`. The run goes on to the code review, the manual check and the pull
request as usual, and the status goes to Review. The disputed files are set aside before the pull request (in `/next`
by step 5 with the unmet paths, so the session's own commit runs on a clean tree; in `/fix` by the session with the
message `Disputed test for #<issue>: <title>`). The pull request gets a section `## Disputed tests` after `## Review`
(below) and the sentence `Auto-merge is not enabled: a dispute over the tester's tests is still open (see Disputed
tests).` where it says why auto-merge was withheld. The result is `partial`, so in `/next` steps 7 and 8 apply as to any
partial result (the disputed criterion is not ticked; the new story's body carries the disputed test), and in `/fix` the
pull request says what is left. When the producer committed nothing at all and the dispute is still open, there is
nothing to open: the existing line `Stopped: the <role> returned failed: nothing committed and the dispute is still
open: <the Disputes lines>` stops the run before the code review (status In progress, slot taken, the files left as
they are). The issue asks for the dispute to be listed "as for open review findings";
the separate section keeps the fixed format of the `## Review` section (iteration 19), which the spec pull request
shares, unchanged.

**11. The workflow skill gets one sentence, nothing more.** "Findings and fix rounds" says that the same rounds pay for
a dispute and an undone round. "CI and merging" is not changed: an open dispute always makes the result `partial`, which
that section already names among the reasons to withhold auto-merge; criterion 4's auto-merge rule is carried by the
sentences added to `/next` step 7 and `/fix` step 6. The procedure itself lives in `/next` and `/fix`, as "The tester"
does.

**12. Reporting: one new step, made by the session.** The dispute launch of the tester is reported as role `tester`,
step `dispute-<k>`, just before it, where k is the fix round the exchange uses; the producer's launch after it is
reported as `fix-round-<k>` like every fix round. An undone round needs no step of its own: the next launch reports
`fix-round-<k>`. The tester's prompt carries no report command (iteration 25 decision 9).

**13. The tester's agent file changes, though the issue names only skills.** The answer to a dispute is the tester's
work, and its standing rules and result block live in `agents/tester.md` (iteration 25 decision 1). One rule and one
result line are added; nothing that iterations 25 and 26 pinned is removed.

## The agent

`agents/tester.md`:

- The `description:` line becomes:

  ```
  description: Writes the failing tests for every acceptance criterion of an approved spec before any code exists, runs them and reports why they fail. Writes only test files and test fixtures, leaves them uncommitted in the slot, and reports in one fixed block. Used by /next and by /fix (for a bug's regression test) on the tester model, and again when the implementer or the fixer disputes one of its tests.
  ```

- Between rule 5 ("Do not commit.") and the result block, a new rule 6; the result block's rule becomes 7:

  ```markdown
  6. **A dispute.** When your prompt carries a dispute, the code exists and the implementer (or the fixer) believes one
     of your tests is wrong or cannot be satisfied. Read the spec (or the bug report), the disputed test and the reason.
     For each disputed test either revise it, so that it checks what the criterion promises, or leave it as it is and
     say why it stands; never weaken a test to let the code pass. Change only the files named in the dispute; you may
     add new files on the test paths above. Run each revised test and report under `Failing` whether it passes or fails
     against the code now in the slot; the rule to confirm that a test fails does not apply here. Rule 5 applies: commit
     nothing.
  ```

- The block gains one line, after `Files:` and before `Left:`:

  ```
  Answers: <only for a dispute, one line per disputed test: <test name> (<file>): revised: <what changed and why, one line> | <test name> (<file>): stands: <why the test is right, one line>; none otherwise>
  ```

  and the paragraph after the block gains: "For a dispute, `complete` means every disputed test has its `Answers` line."

`name`, `tools`, `model`, rules 1 to 5 and the `Test paths:` line stay byte for byte as they are.

## `/next`

All changes are in `skills/next/SKILL.md`. The picking section, steps 1, 2, 3, 4 and 6 of "2. Implement the approved
story" (except where named), "The tester" (except its step 3), the code review's steps 1 to 3 and "Hard rules" stay as
they are.

### The tester, step 3

After "Keep the tester's `Criteria` and `Failing` lines, `<tester files>` and the model passed, for the implementer's
prompt and the pull request.", one sentence: "Then record `<tester blobs>` (see "The tester's files" below); a path whose
file is missing stops with `Stopped: the tester returned failed: it deleted <path>`."

### The tester's files (new section, after "The implementer", before "The code review")

The section holds decisions 2, 3, 5, 6 and 8 in this order, as numbered rules, with every command written out as in
those decisions:

1. **Record** (decision 2): `<tester blobs>`, one line `<path> <blob> <head> <mode>` per path of `<tester files>`, with
   `git -C <slot> hash-object -w -- <path>`, `git -C <slot> rev-parse -q --verify HEAD:<path>` and
   `git -C <slot> ls-tree HEAD -- <path>` (for a new file, `git -C <slot> diff --no-index -- /dev/null <path>`).
2. **Before every launch of the implementer** record `<round base>` with `git -C <slot> rev-parse HEAD`.
3. **Check** (decisions 3 and 5) after every result of the implementer, before any other check of that result.
4. **Undo** (decision 6), the four steps with `merge-base --is-ancestor <round base> HEAD`,
   `reset --mixed -q <round base>`, `update-index --add --cacheinfo <mode>,<blob>,<path>`, `checkout-index -f --` and
   `reset -q -- <path>`, then what follows (the stop line
   `Stopped: the implementer changed the tester's tests: <the paths, comma-separated>. The change was undone and no fix round is left.`,
   or the next round).
5. **A dispute** (decisions 7, 8 and 9): while a fix round is left, report `dispute-<k>`, count the agents, record
   `<dispute base>` with `git -C <slot> rev-parse HEAD`, launch the tester with the dispute prompt below, read and check
   its result (decision 8; the skill writes these words verbatim, each on one line:
   `git -C <slot> rev-parse HEAD is still <dispute base>`,
   `a disputed path whose hash equals its <blob> keeps its old line`,
   `a disputed path whose hash differs from its <blob> and has a revised: answer is revised: its new line replaces the old line of <tester blobs> for that path`,
   `a disputed path whose hash differs from its <blob> and whose answers are all stands: fails the check`,
   `Stopped: the tester returned failed: it changed <path> but answered every test in it stands:`), then report `fix-round-<k>` and
   launch the implementer with its prompt and the paragraph "The tester has answered the dispute" (below). When no fix
   round is left, the dispute stays open (decision 10); when the implementer committed nothing at all, the run stops
   with `Stopped: the implementer returned failed: nothing committed and the dispute is still open: <the Disputes lines>`
   (in `/fix`, "the fixer"), the pinned words on one line of the skill.

The tester's dispute prompt, with the placeholders filled in:

```markdown
Answer a dispute over your tests for story #<issue> "<title>" in <owner>/<repo>.

The slot: <absolute slot path>, branch <branch>. Use that absolute path for every file and `git -C <slot path>` for
every git command; your working directory is not the slot. The code exists now, partly committed on the branch.
Do not commit: leave every file you change uncommitted in the slot.

The spec: <path in the slot> (read it completely; it is the contract).
The acceptance criteria of the issue, in order: <the criteria, verbatim>.

The implementer disputes these tests (<test name> (<file>): <its reason>):
<the producer's Disputes lines, verbatim>

Your tests are at: <tester files, one per line>. Change only the files named above; you may add new files on the
test paths.

The project's testing rules:
- the check: <verification.check>
- the bench rule: <verification.benchRule, or "none">
- the invariants: <config invariants, one per line>

In this project iterations.specDir is <iterations.specDir>, iterations.decisionsDir is <iterations.decisionsDir> and
iterations.changelog is <iterations.changelog>.

End with the result block of your instructions, with one Answers line per disputed test, and nothing after it.
```

The tester's dispute prompt carries no reason of the implementer beyond its `Disputes` lines, and none of its other
lines.

### The implementer

- Step 3 (Read the result) begins: "First check the tester's files (see "The tester's files"); a change is undone there
  before anything below." Its `Result: partial` sentence on the tree check becomes: "For a `Result: partial`, the tree
  check accepts exactly the paths the result lists under Left as `unmet: <path> (criterion <n>)` and the files its
  `Disputes:` lines name, when they are in `<tester files>`: `git -C <slot> status --porcelain --untracked-files=all`
  may list those paths and no other, and `git -C <slot> log origin/<git.baseBranch>..HEAD` may be empty only when the
  `Disputes:` line is not `none`. Any other dirty path fails the check as it does today." Then one bullet before
  `Result: failed`: "- A `Disputes:` line that is not `none`: answer it (see "The tester's files", rule 5) before the
  code review."
- **The prompt.** After the paragraph that begins "The tester has written the tests for the acceptance criteria" and
  before "Do this:", one paragraph is added; each sentence below that the lint pins stays on one line of the skill:

  ```markdown
  The tester's files are not yours: do not edit, rename, move, overwrite or delete any of them, not even to add a test.
  You may add tests of your own, in files that are not the tester's (new files, or test files the tester did not touch).
  The session checks every tester file against what the tester left after you return; a change to one fails your round, and the round is undone.
  If you believe a tester's test is wrong or cannot be satisfied, do not change it: list it under Disputes as
  `<test name> (<file>): <why, one line>`, leave its file as it is, set it aside with the files of unmet criteria (the
  same stash command and message) to run the check and commit the rest, put it back, and report `partial`. The session
  passes the dispute to the tester.
  ```

  The result block gains, before `Left:`:

  ```
  Disputes: <one line per disputed test: <test name> (<file>): <why it is wrong or cannot be satisfied, one line>; none>
  ```

  Steps 1 to 3 of "Do this:", the report paragraph, the forbidden actions and the other lines of the block are
  unchanged.
- **The added paragraph of a fix round after a dispute**, at the end of the prompt, after any blocking findings of an
  earlier review that are still to fix (both are passed):

  ```markdown
  The tester has answered the dispute:
  <the tester's Answers lines>
  A revised test is in its file, uncommitted; a test that stands is unchanged. Make them pass without changing them, run
  the check, commit. If you still believe a test is wrong, report it under Disputes again.
  ```

- **The added paragraph of a fix round after an undone round**, at the end of the prompt:

  ```markdown
  The previous round changed the tester's files <the paths, comma-separated>; that change is undone: the files hold the
  tester's text again, and the commits of that round are back in the working tree, uncommitted. Finish the work without
  changing the tester's files, run the check, commit.
  ```

### The code review

- Step 4 ("Read the block"): "read its `Result:` block as before" becomes "read its `Result:` block as in "The
  implementer", step 3 (the tester's files first, then a dispute)". The sentence "while fewer than
  `review.maxFixRounds` fix rounds have been used" gets "(a dispute exchange and an undone round count too)".

### Step 5

The first sentence keeps its first words, which the lint pins, and becomes "When the implementer's result is
`partial` and lists `unmet:` paths under Left or a dispute that is still open (its last result counts), first copy the
text of each of those paths and of each disputed file ...", the rest unchanged (the same stash command and message
`Unmet tests for #<issue>: <title>`), so the session's commit runs on a clean tree.

### Step 6: "How verified" and `## Disputed tests`

- After the line "Each `unmet:` path of a partial implementer result follows as `- not committed: criterion not met:
  <path> (criterion <n>)`.", one sentence: "Each test the tester revised after a dispute follows as
  `- revised by the tester after a dispute in fix round <k>: <test name> (<file>): <what changed>`, from its `Answers`
  line."
- After the `## Review` sentence, one paragraph: "When a dispute is still open (see "The tester's files"), add after
  `## Review`:"

  ```
  ## Disputed tests

  - Disputes still open: <d>
  - disputed <file>: <test name>: <the producer's reason, as it wrote it>; tester: <stands: <why> | not asked: no fix round left>
  - set aside, not committed: <the paths, comma-separated> (stash "<the stash's message>")
  - committed as it was, disputed: <the paths, comma-separated>
  ```

  with one `disputed` line per open dispute; `tester:` is the tester's last `Answers` line for that test, `stands: ...`,
  or `not asked: no fix round left`. A disputed file that was already committed and left committed (decision 7) goes on
  the line `committed as it was, disputed`, not on the `set aside` line; each of the two lines appears only when it has
  a path.

### Step 7

The list of reasons ("when the PR changes one of `escalation.storyTriggers`, is partial, skipped a required manual check,
or has blocking review findings left") gets ", or has a dispute over the tester's tests still open", and one sentence:
"Then say `Auto-merge is not enabled: a dispute over the tester's tests is still open (see Disputed tests).`"

### Step 8

The sentence on the tests set aside in step 5 gets: "a disputed test also carries the producer's reason and the
tester's last answer".

### Reporting the steps

One row, before the row "just before the launch of fix round k":

| When | Role | Step |
|---|---|---|
| just before the tester's dispute launch for fix round k ("The tester's files", rule 5) | `tester` | `dispute-<k>` |

The row "just before the launch of fix round k" stays and now covers every fix round (decision 9).

## `/fix`

All changes are in `skills/fix/SKILL.md`, the same as in `/next` with "fixer" for "implementer", one test for a bug, and
these differences.

- **The tester, step 3**: the same sentence as in `/next` (record `<tester blobs>`; `it deleted <path>`).
- **The tester's files** (new section, after "The fixer", before "The code review"): rules 1 to 5 as in `/next`, with
  `Stopped: the fixer changed the tester's tests: <the paths, comma-separated>. The change was undone and no fix round is left.`
  The dispute prompt is `/next`'s with "Answer a dispute over your regression test for bug #<issue> "<title>"", "The
  bug report, in full: <body>." instead of the spec and the criteria, the mapping sentence of the first tester prompt
  ("In your instructions read "story" as this bug, ..."), and "The fixer disputes this test".
- **The fixer, step 3**: begins with the tester's files check; the tree check accepts exactly the files of the
  `Disputes:` lines that are in `<tester files>`; the check that every path of `<tester files>` is in
  `git -C <slot> diff --name-only origin/<git.baseBranch>..HEAD` skips those files; the log may be empty only when the
  `Disputes:` line is not `none`. One bullet as in `/next`: a `Disputes:` line that is not `none` is answered before the
  code review.
- **The prompt.** After the paragraph that ends "In a fix round the test may already be committed with your earlier
  fix: then run it and the check, and fix exactly the blocking findings.", one paragraph:

  ```markdown
  The tester's files are not yours: do not edit, rename, move, overwrite or delete any of them, not even to add a test.
  You may add tests of your own, in files that are not the tester's (new files, or test files the tester did not touch).
  The session checks every tester file against what the tester left after you return; a change to one fails your round, and the round is undone.
  If you believe a tester's test is wrong or cannot be satisfied, do not change it: list it under Disputes as
  `<test name> (<file>): <why, one line>` and leave its file as it is. This is the one exception to the rule above: you
  may commit your fix once the check is green with the test set aside with
  `git -C <slot path> stash push --include-untracked -m "Disputed test for #<issue>: <title>" -- <the paths>`; put it back
  after the commit: find the entry with that message in `git -C <slot path> stash list` and pop that one, never the top
  entry without looking. Report `partial`. The session passes the dispute to the tester.
  ```

  The result block gains, before `Left:`, the same `Disputes:` line as in `/next`. The two fix-round paragraphs ("The
  tester has answered the dispute", "The previous round changed the tester's files") are the same as in `/next`.
- **The code review**, step 4: the same two changes as in `/next`.
- **Step 6**: "How verified" gets the same `revised by the tester after a dispute in fix round <k>` lines after the
  test's diff; before the pull request is opened with a dispute still open, the session sets the disputed file aside with
  `git -C <slot> stash push --include-untracked -m "Disputed test for #<issue>: <title>" -- <the paths>` (the tree is
  clean for the slot's release; the session commits nothing in `/fix`); the `## Disputed tests` section is the same; the
  auto-merge rule ("not for a partial fix, one that has blocking review findings left, ...") gets "or one with a dispute
  over the tester's test still open", and the same sentence
  `Auto-merge is not enabled: a dispute over the tester's tests is still open (see Disputed tests).`
- **Reporting the steps**: the same row, `dispute-<k>`, role `tester`.
- **Batch mode**: the stop `Stopped: the fixer changed the tester's tests: ...` is a skip of that bug, like a `failed`
  fixer (one sentence in "A bug that cannot be done is skipped"); "Commit what exists" does not apply to it (the round's
  work stays uncommitted in the bug's slot). The same holds for the stop
  `Stopped: the fixer returned failed: nothing committed and the dispute is still open: ...`: a skip, exempt from "Commit
  what exists", so the red disputed test is never committed.

## The workflow skill

One sentence, nothing else (decision 11):

- **"Findings and fix rounds"**, at the end of the paragraph "**Rounds.**": "In `/next` and `/fix` the same rounds also
  pay for a dispute over a tester's test (the tester answers, then a new producer runs) and for a round undone because
  the producer changed the tester's tests: each costs one of `review.maxFixRounds`, and `Fix rounds used` counts them."

"CI and merging" is not changed (decision 11).

## README

After the paragraph "`/fix` does the same before the fixer: ...", one paragraph: "The implementer and the fixer may not
edit or delete the tester's files; they add tests of their own only in other files. After each of their results the
session compares every tester file with what the tester left (`git hash-object`) and undoes a change as a failed round.
A test the implementer or the fixer believes is wrong goes back to the tester as a dispute: the tester revises it or
says why it stands. A dispute and an undone round each use one of `review.maxFixRounds`; a dispute still open when the
rounds are used up is listed in the pull request under Disputed tests and keeps auto-merge off, and How verified names
the tests the tester revised."

## CHANGELOG

One bullet under `Unreleased`, above iteration 26's, in the form of the others:
`- Iteration 27 (#44): the implementer may not change the tester's tests, and a doubtful test goes back to the tester.
...`, naming the forbidding paragraph in the implementer's and the fixer's prompts (tests of their own only in files
that are not the tester's), `<tester blobs>` recorded with `git hash-object -w` and the check after every result
(`hash-object`, `rev-parse HEAD:<path>`), the undo (`reset --mixed` to the round's start, the tester's text written back
from the object store), the `Disputes:` line, the tester's dispute launch and its `Answers:` line (`revised:` or
`stands:`), one fix round per dispute exchange or undone round from `review.maxFixRounds`, the `## Disputed tests`
section and the sentence that keeps auto-merge off, the How verified line for revised tests, the report step
`dispute-<k>`, and that no config key, status, slot marker or script changes.

## Tests

`/next` and `/fix` are conversations, so the lint pins the wording the behaviour depends on (each pinned phrase on one
line of its file; the lint greps line by line), and the manual check does the behaviour.

**`tests/lint.sh`**, new section "== the tester's tests are guarded", after "== a tester reproduces the bug before
/fix" (it reuses `ta`, `nx`, `fx`):

- `agents/tester.md` contains `A dispute`, `revised:`, `stands:`, `never weaken a test to let the code pass`,
  `Change only the files named in the dispute` and `Answers:`, and its `description:` line contains `disputes`
  (criterion 3);
- both `skills/next/SKILL.md` and `skills/fix/SKILL.md` contain `<tester blobs>`, `<round base>`, `<dispute base>`,
  `is still <dispute base>`, `replaces the old line of <tester blobs> for that path`, `keeps its old line`,
  `whose answers are all stands: fails the check`, `but answered every test in it stands:`,
  `nothing committed and the dispute is still open`, `diff --no-index -- /dev/null <path>`,
  `hash-object -w -- <path>`, `rev-parse -q --verify HEAD:<path>`, `merge-base --is-ancestor <round base> HEAD`,
  `reset --mixed -q <round base>`, `update-index --add --cacheinfo <mode>,<blob>,<path>`, `checkout-index -f --`,
  `Stopped: the tester returned failed: it deleted <path>`, `do not edit, rename, move, overwrite or delete any of them`,
  `You may add tests of your own, in files that are not the tester's`,
  `a change to one fails your round, and the round is undone`,
  `If you believe a tester's test is wrong or cannot be satisfied, do not change it`,
  `Disputes: <one line per disputed test`, `Answer a dispute over your`, `The tester has answered the dispute`,
  `that change is undone`, `dispute-<k>`, `## Disputed tests`, `- Disputes still open: <d>`,
  `revised by the tester after a dispute in fix round` and
  `Auto-merge is not enabled: a dispute over the tester's tests is still open (see Disputed tests).` (criteria 1 to 5);
- `skills/next/SKILL.md` contains `Stopped: the implementer changed the tester's tests`, and `skills/fix/SKILL.md`
  contains `Stopped: the fixer changed the tester's tests` and `-m "Disputed test for #<issue>: <title>"` (criterion 2,
  3);
- the section "Findings and fix rounds" of `skills/workflow/SKILL.md` contains `a dispute over a tester's test`
  (criterion 4);
- `README.md` contains `Disputed tests`.

The existing pins keep passing and are not changed: iteration 13's (`Stopped: the implementer returned failed`,
`Stopped: the fixer returned failed`, `never writes the code itself`, `Do not push`, `do not launch other agents`),
iterations 18 and 19's (the findings format lines, which stay equal in the workflow skill and the code reviewer's file;
the `## Review` lines and `Auto-merge is not enabled: blocking review findings are still open (see Review).`), iteration
23's report items, iteration 25's (the `Test paths:` line, still exactly once in each of the three files and equal; the
tester's `Do not stage, stash or commit anything` and the block lines; `-m "Unmet tests for #<issue>: <title>"`,
`stash list`, `stash pop stash@{<n>}`, and step 5 still beginning ``5. When the implementer's result is `partial` ``)
and iteration 26's (`A fix that does not make this test pass is not a fix`,
`In a fix round the test may already be committed with your earlier fix`, `diff --name-only origin/<git.baseBranch>..HEAD`,
`description:` naming `/fix`). `bash tests/check.sh` stays green.

## Verification

The change touches `skills` and `agents`, so the manual check applies. In a throwaway project with nightmill loaded from
a separate checkout of this branch (`claude --plugin-dir <checkout>`; never in the checkout being edited, decision
0003), a board, slots, `review.maxFixRounds` 2, and an Approved throwaway story with two criteria that ask for a small
script change, and its spec:

1. **A wrong test goes back** (the issue's own verification). Approve a spec whose Tests section tells the tester to
   expect a value that contradicts the spec's own rule for criterion 2 (a planted wrong test). Run `/next`. The
   implementer does not change the test: its block has `Disputes: <test> (<file>): <why>` and `Result: partial`; the
   test file is unchanged (`git -C <slot> hash-object -- <file>` equals the recorded blob). The session reports
   `dispute-1`, launches `nightmill:tester` with the dispute prompt; the tester returns `Answers: ... revised: ...`;
   the session reports `fix-round-1` and launches the implementer, which commits the revised test with the code, green.
   Before that launch the session recorded `<dispute base>` and checked that HEAD is still it; the line of
   `<tester blobs>` for the revised file now holds the revised blob (`git -C <slot> hash-object -- <file>` equals it) and
   the old line for that path is gone, so the check after fix round 1 passes and is not an undo.
   The pull request's How verified has `- revised by the tester after a dispute in fix round 1: ...`, and the `## Review`
   section says `Fix rounds used: 1 of 2` (or more, when the review sent findings back) (criteria 1, 3, 4, 5).
2. **A test that stands.** A dispute over a test that is right (plant a misleading comment in the spec's Tests
   section, not in its rules): the tester answers `stands: ...`, the file's hash still equals its recorded blob (the
   line of `<tester blobs>` is kept), the next implementer makes the test pass unchanged. Record what happened. Then, by
   hand as in step 4, change that file after a `stands:` answer and run the session's comparison of decision 8: the hash
   differs from the blob and the answers are all `stands:`, so the check fails with
   `Stopped: the tester returned failed: it changed <path> but answered every test in it stands:` (criterion 3).
3. **Rounds used up.** Set `review.maxFixRounds` to 0 and repeat step 1: no tester is launched for the dispute; the
   pull request is opened with the work committed, the disputed file set aside (`git stash list` in the slot shows
   `Unmet tests for #<issue>: <title>`, the tree is clean), a `## Disputed tests` section with
   `- Disputes still open: 1` and `tester: not asked: no fix round left`, the sentence
   `Auto-merge is not enabled: a dispute over the tester's tests is still open (see Disputed tests).`, auto-merge off,
   the status at Review, criterion 2 not ticked and the rest filed as a new story naming the test (criterion 4). Then
   repeat with a story whose only criterion is the disputed one, so the implementer commits nothing: the session stops
   with `Stopped: the implementer returned failed: nothing committed and the dispute is still open: ...`, the status
   stays In progress, the slot stays taken and the disputed file is left as it is (criterion 4).
4. **An edit is detected and undone.** An agent cannot be made to break its prompt on demand, so the guard's commands
   are run by hand in a slot, as the skill writes them: let the tester run (stop the session after "The tester"), record
   `<tester blobs>` with the skill's commands, then edit one tester file, commit it with a code change, and run the
   check of decision 3: the file is reported changed. Run the undo of decision 6: the commit is gone from the branch,
   its code change is in the working tree, the tester file holds the tester's text again (the hash equals the blob) and
   is uncommitted. Repeat with the file deleted and committed, and with the file only edited in the working tree. Then,
   in a real run, read the next fix round's prompt: it carries "The previous round changed the tester's files ...".
   With `review.maxFixRounds` 0 the session prints `Stopped: the implementer changed the tester's tests: <path>. The
   change was undone and no fix round is left.` (criterion 2).
5. **An unmet criterion is not an edit.** A story whose second criterion the implementer cannot meet (as in iteration 25,
   Verification step 8): the test file stays uncommitted and unchanged, the check of decision 3 passes (no undo, no
   extra round), and the run goes on as iteration 25 says (criterion 2).
6. **`/fix`.** A throwaway bug whose report contradicts itself so that the tester's regression test expects the wrong
   value: the fixer reports `Disputes:`, commits its fix with the test set aside by the message
   `Disputed test for #<issue>: <title>` and popped by message; the tester is launched with the dispute prompt; the next
   fixer commits the revised test with the fix; `diff --name-only` then lists the test file; the pull request lists the
   revised test. With `review.maxFixRounds` 0 the pull request has `## Disputed tests`, the test is in the stash with that
   message, the tree is clean and auto-merge is off (criteria 1 to 5).
7. **The report step.** While the tester answers a dispute, the slot's marker has role `tester`, step `dispute-1`.

The PR's "How verified" lists the seven results and the check.

## Not done

- The code reviewer's check of the tests against the spec and that none was weakened (#45): its prompt and agent file are
  not changed. A test of the implementer's own that skips or overrides a tester's test, in a file that is not the
  tester's, is not detected here; that is #45's review.
- Locking files at the filesystem level (out of scope): the guard is a check after the fact and an undo, not a lock.
- No script, no smoke step (decision 1); no change to `slot`, `validate-config` or any other script.
- No config key (the rounds are `review.maxFixRounds`), no separate budget for disputes, no new role, no change to
  `roles.tester.model`'s default, to the validator or to the pairing.
- No change to the `## Review` section's format lines, to the findings block or to the spec pull request (decision 10).
- No line-by-line rule inside a shared test file: a tester file is the tester's as a whole (decision 4).
- No re-run of the tester in a review fix round other than for a dispute; the tester never answers a review finding.
- No change to the `Test paths:` line, to the tester's first launch, to "never commit red" or "Verify before every
  commit", to the status flow, to who sets a status or to the slot marker; no decision record.
- No change to `skills/spec/SKILL.md`, `skills/check/SKILL.md` or `/status`.
