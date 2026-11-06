# Iteration 29: the code reviewer checks the tests against the spec and that none was weakened

Status: draft, awaiting approval (#45)

Story: #45, epic #41 (Independent test writing). The code reviewer of iteration 18 judges the tests as part of its
review: for every acceptance criterion a test covers it and would fail for a wrong implementation; no test of the
tester's was removed, skipped, loosened or made conditional, compared with what the tester first wrote; and an
assertion that is always true, a test that never fails and a test of only a mock are reported. The session gives the
reviewer the tester's files and the tester's own revisions (from the pristine copies iteration 27 keeps in git's object
store), never the producer's or the tester's account. A blocking finding about a missing or weak test, or about the
tester's tests, is marked `test: ` in its text, inside the fixed findings format; the session sends it to the tester and a code finding to the implementer
(or the fixer), both in the same fix round of `review.maxFixRounds`. Changes `agents/code-reviewer.md`,
`skills/next/SKILL.md`, `skills/fix/SKILL.md`, two sentences of `skills/workflow/SKILL.md`, `README.md`,
`tests/lint.sh` and `CHANGELOG.md`.

**Not a story trigger.** No config key is added, renamed or removed: the rounds are `review.maxFixRounds` (iteration 18),
the tester's model is `roles.tester.model` and the reviewer's `roles.codeReviewer.model` (iteration 10). The status flow,
who sets a status and the slot marker format do not change; the new report step `test-finding-<k>` is a value the
report command of iteration 23 already accepts. The findings block keeps its format lines byte for byte. No script
changes. The PR may auto-merge. The change touches `skills` and `agents`, so the manual check of
`verification.manualCheckPaths` applies.

**Order.** #36 and #37 (iterations 18 and 19: the code reviewer, the fix rounds, the findings format, the `## Review`
section), #42 (iteration 25) and #43 (iteration 26) are delivered and on `main`. #44 (iteration 27) is merged as a spec
and is being implemented in another slot; its code is **not** on `main` yet. This iteration builds on its text: the
section "The tester's files" with `<tester blobs>`, `<dispute base>` and the dispute launch, the `Disputes:` and
`Answers:` lines, the shared fix-round budget (its decision 9). So this iteration is implemented **after #44 has
merged**, rebased on it. `skills/workflow/SKILL.md` is in `parallel.hotFiles`, and #81 (iteration 28, spec merged) also
changes it, `skills/next/SKILL.md` and `skills/fix/SKILL.md`; the two are never implemented in parallel, and whichever
comes second rebases on the other. Iteration 28's pointer sentences sit in the "Count" steps; the one new launch of this
iteration counts "as for a dispute launch", so it follows whatever rule 5 of "The tester's files" says at that time. No
step is renumbered, so every "step N" reference in the skills and in iteration 23's tables stays valid.

## Goal

The code reviewer judges the tests as part of the review: they cover the spec, they would catch a wrong
implementation, and none was weakened; what is wrong in a test goes back to the tester.

## Facts this rests on

- Iteration 18 (`agents/code-reviewer.md`, tools `Read, Grep, Glob`, `model: opus`): the reviewer reads only; it
  cannot run code, git or a script. It checks, among others, that "every acceptance criterion of the issue has a test
  that would fail without the change". Its prompt (`/next` and `/fix`, "The code review", step 3) carries facts: the
  criteria (or the bug report), the spec's path, the invariants, the producer's `Check:` line and the diff
  `git diff <base>...<branch>`, replaced by the `--stat` and the instruction to read the files when it is longer than
  2000 lines. It never carries the producer's own account (decision 2 there; "A reviewer is a fresh agent every time and
  never sees the producer's own account of its work" in the workflow skill).
- The findings format ("Findings and fix rounds" in the workflow skill, repeated in `agents/code-reviewer.md` and
  `agents/spec-reviewer.md`): `- blocking <file>:<line> <what is wrong, one line>` and
  `- advisory <file>:<line> <what is wrong, one line>`. The lint compares, in the three files, every line that matches
  `^(Review: findings \| no findings|Blocking: <n>|Advisory: <n>|- blocking <file>:<line> .*|- advisory <file>:<line> .*)$`;
  they must be equal. "**Blocking** is a finding that breaks something the story promised or the project requires: a
  criterion without a test, ...". Advisory findings are never sent back.
- Iteration 19: the `## Review` section, `- Fix rounds used: <r> of <review.maxFixRounds>`, one line
  `fixed in round <k>: blocking <file>:<line> <text>` per fixed finding (a blocking finding sent back and not repeated
  in the last review with the same file and text), the open findings of the last review verbatim, and
  `Auto-merge is not enabled: blocking review findings are still open (see Review).`
- Iterations 25 and 26: the tester (`agents/tester.md`) writes the tests before the code, uncommitted; the session
  records `<tester files>`; the implementer (or the fixer) commits them with its code once the check is green. A
  `partial` implementer leaves the test file of an unmet criterion uncommitted. Iteration 25's tester row of
  "Agent roles and models": reviewed by "`codeReviewer`, with the change".
- Iteration 27 (spec, #44): after the tester's first launch the session records `<tester blobs>`, one line
  `<path> <blob> <head> <mode>` per tester file, `<blob>` from `git -C <slot> hash-object -w -- <path>`: the tester's
  text, kept as a pristine copy in the object store (never in the stash, never in a file of the slot). After every
  producer result the session checks that each tester file still holds `<blob>` and undoes a change. The implementer
  may not edit the tester's files; tests of its own go in other files (decision 4: a tester file is the tester's as a
  whole). A disputed test goes back to the tester in a second launch (rule 5 of "The tester's files"): the session
  records `<dispute base>`, launches `nightmill:tester` with the dispute prompt, checks the launch (HEAD still
  `<dispute base>`, only test paths, the files not named unchanged, the named files decided by hash: kept, `revised:`,
  or the stop `it changed <path> but answered every test in it stands:`), replaces the line of `<tester blobs>` of a
  revised file by a new one recorded the same way, and adds new files. The tester's rule 6 answers "a dispute" with one
  `Answers:` line per disputed test, `revised:` or `stands:`. A dispute exchange and an undone round each cost one fix
  round (decision 9: "The fix rounds of a run are the launches of the producer after its first one ... At most
  `review.maxFixRounds` are used"). Its "Not done" leaves to #45: "A test of the implementer's own that skips or
  overrides a tester's test, in a file that is not the tester's, is not detected here", and says that in iteration 27
  "the tester never answers a review finding".
- Iteration 23: a step is 1 to 40 characters of `A-Z`, `a-z`, `0-9` and `-`, starting with a letter or digit; a failed
  report never stops a run; the session reports the tester's launches (`write-tests`, `dispute-<k>`).
- `git diff <blob> <blob>` prints the difference of the raw contents of two blob objects; it needs no working tree and is
  the same in bash and PowerShell. Because of iteration 27's guard, every tester file in the slot holds, at the time of
  every review, exactly the `<blob>` of its line of `<tester blobs>`, committed or not.

## Decisions

**1. The reviewer gets the tester's files and the tester's revisions as text in its prompt; no file is written.** The
reviewer can read the slot but not the object store. It needs two things to compare "the tester's tests" with "the
tests at the end": the tests at the end are the files in the slot (it reads them, and the change's diff shows what the
producer did around them); the tester's first text differs from them only where the tester itself revised a file after
a dispute or a test finding (iteration 27's guard rules out any other change to a tester file). So the session keeps
`<tester originals>`, one line `<path> <blob> <round>` per tester file with the blob first recorded for it (never
replaced), and puts into the prompt the list
of tester files, each `committed` or `not committed`, and for every file whose blob changed the diff
`git -C <slot> diff <original blob> <blob>`. Nothing is written into the slot (its tree stays as the tree checks of
iterations 25 and 27 expect) or outside it (a read outside the project may prompt, iteration 18's Facts). The tester's
part of a committed tester file is visible in the change's diff (every line the change adds to a tester file is the
tester's, iteration 27 decision 4).

**2. Size.** The revision diffs are given in full and never cut: they exist nowhere the reviewer can read, they are
exactly what rule 2 compares, and they are the tester's own edits of named tests, which are short. The 2000-line rule
of the change's diff is unchanged and counts the change's diff alone; when it applies, the list of tester files tells
the reviewer which files to read for the tests.

**3. The reviewer gets no account, neither the producer's nor the tester's.** The tester is now reviewed like a
producer, so its `Criteria`, `Failing` and `Answers` lines are not passed, nor any `Disputes:` line of the producer; the
reviewer maps criteria to tests itself, which is the independent check criterion 1 asks for. Which files are the
tester's, whether each is committed and how the tester revised it are facts the session reads from git; the fix round
in which the tester added or revised a file is one the session remembers from its own launches (git does not record it).

**4. Which findings about tests are blocking.** The workflow skill: "Blocking is a finding that breaks something the
story promised or the project requires". The Definition of done requires that every acceptance criterion is a test.
- Rule 1 (a criterion with no test, or only tests that would pass for a wrong implementation): the criterion is
  effectively untested, so **blocking** (criterion 1).
- Rule 2 (a tester's test removed, skipped, loosened or made conditional): the criterion the test protected is no
  longer protected as the tester wrote it, so **blocking** (criterion 2).
- Rule 3 (an always-true assertion, a test that never fails, a test of only a mock): **blocking when a criterion relies
  on it** (it is the criterion's only test, or every test of the criterion is like it), because then the criterion is
  untested; **advisory otherwise**, because an extra test that cannot fail beside a good one breaks no promise, it only
  misleads (criterion 3 says "as findings", not "blocking").

**5. A test finding is marked in the text, and the marker alone routes it; the format does not change.** A finding
whose fix belongs in the tester's tests begins its text with `test: `, so a line reads
`- blocking tests/x.sh:12 test: <what is wrong>`. The format lines stay byte for byte (the text is free), the lint's
equality keeps passing, and the `## Review` lines carry the marker as the reviewer wrote it. Two kinds of finding are
test findings: a criterion with no test or only weak tests (rule 1), which is by nature the tester's to fix whoever
wrote the weak tests (the tests are written by the tester, epic #41), and a rule 2 or 3 finding on one of the tester's
files. For these the reviewer names as `<file>` one of the tester's files, or a path on a test path that does not exist
yet, where the missing test belongs (with `-` as the line, as the findings format says of something missing), never an
existing file that is not the tester's. A test path is a path that matches the `Test paths:` line of iterations 25 and
26; the session puts that line, verbatim, into the reviewer's prompt, and the reviewer's file does not define a test
path in words. The session's rule is mechanical and does not look at the file: a blocking line whose text begins with
`test: ` is a **test finding**, whatever file it names, and goes to the tester; every other blocking line is a **code
finding**. For the tester's launch the session sorts each named path into one of three kinds (decision 6): (a) a path
of `<tester files>`, which exists; (b) a path that does not exist in the slot; (c) an existing file that is not in
`<tester files>` (the reviewer is told not to name one; the rule does not depend on it). A rule 2 or 3 finding on a test the producer wrote
itself, and a change outside the tester's files that weakens the tester's tests (a skip, an override, a runner that
stops running them), are the producer's work: no prefix, and the producer undoes them.

**6. A test finding goes to the tester through the dispute launch of iteration 27.** The launch, its checks, the
recording of revised and new files in `<tester blobs>` and the stop lines are rule 5 of "The tester's files"; only the
named paths and the prompt differ. The named paths of the test findings take the place of the disputed files by kind
(decision 5):
- a named path of kind (a) is a disputed file in the sense of iteration 27: it exists, and its hash is decided by
  iteration 27's three hash cases against its line of `<tester blobs>`; the tester may revise it or leave it;
- a named path of kind (b) is **not** a disputed file: it is exempt from iteration 27's check "every disputed file
  exists" and from every check that it is unchanged. The tester may create it, or write the missing test in any other
  new file on a test path; either is a new file, checked by iteration 27's checks of new files (a test path, untracked)
  and recorded in `<tester blobs>` and `<tester originals>` by the new-file rule. It may also answer `stands:` for it
  and create nothing;
- a named path of kind (c) is not a disputed file either: the tester may not change it, and iteration 27's check that
  every listed path not in `<tester files>` is untracked holds it; the tester writes the missing test in a new file on a
  test path or answers `stands:`.

The tester's agent file is not changed: the prompt reads "a dispute" as these findings and "the implementer" as the code reviewer, as `/fix`'s
first tester prompt maps "story" to the bug (decision 9). The tester answers each finding with one `Answers` line,
`revised:` (it changed or wrote the test) or `stands:` (the test is right, or no test can be written, and why).

**7. A test finding the tester answers `stands:` is not sent to it again, and a disagreement goes to the maintainer.**
After a `stands:` answer the test is unchanged; when a later review of the run repeats a test finding with the same file
and text (the line is not compared, as for "Findings fixed"), it is not sent to the tester again: it stays open. When a
round has only test findings and the tester answered every one `stands:` and added no file, no producer is launched and no review runs
again: the review before is the last review, its blocking findings are open, and auto-merge is off by the existing
sentence. The reviewer and the tester do not argue in a loop; the maintainer decides, with the tester's answer in How
verified.

**8. One round, whatever the mix.** A fix round k is: first the tester's launch for the test findings (when there are
any to send), then one launch of the producer, which gets the tester's answers (when the tester was launched) and the
code findings (when there are any). The producer is launched when there is a code finding or the tester revised or
wrote a test (an `Answers` line is `revised:`, or the tester added a new file beside answers that are all `stands:`, so
that the file is committed and reviewed) (it commits the tester's uncommitted files and makes them pass, as after a dispute). The round costs one of
`review.maxFixRounds`, however many findings of each kind it has. This extends iteration 27 decision 9 by one case: a
round is also a tester's launch for test findings that is not followed by a producer launch (decision 7). A round runs
only while fewer than `review.maxFixRounds` rounds have been used, as today; the run still has at most
`1 + review.maxFixRounds` reviews. A dispute the producer reports in round k is answered in round k + 1, by iteration 27.

**9. The tester's agent file is not changed.** The issue names the reviewer's file and the two skills; rule 6 of
`agents/tester.md` (iteration 27: revise or say why it stands, never weaken, change only the named files, add new test
files, run each revised test, commit nothing, one `Answers` line each) already says all a test finding needs, and the
prompt maps the words. A rule of its own in the agent would repeat rule 6.

**10. The workflow skill gets the minimum: two sentences of "Findings and fix rounds".** The definition of blocking
names the two test cases (rules 1 and 2), because the blocking rule is defined there and a reviewer's file must agree
with it; and one sentence at the end of "**Rounds.**" says that a test finding goes to the tester in the same round.
The procedure lives in `/next` and `/fix`. "CI and merging", "Agent roles and models" (the tester row already says
"Reviewed by `codeReviewer`, with the change") and the `## Review` format are not changed.

**11. Reporting: one new step, made by the session.** The tester's launch for the test findings of fix round k is
reported as role `tester`, step `test-finding-<k>` (13 characters plus the digits of k), just before it; the producer's
launch of the same round reports `fix-round-<k>` as every fix round does. The tester's prompt carries no report command
(iteration 25 decision 9).

**12. The PR shows a test finding through the existing lines.** A test finding fixed is a `fixed in round <k>:` line
with its `test: ` text, an open one a `- blocking` line, as today. Each answer of the tester to the code review is added
to How verified, next to iteration 27's line for revised tests, as
`- tester's answer to the code review in fix round <k>: <the Answers line, as the tester wrote it>`, so a `stands:` is
visible to the maintainer. The rule of "Findings fixed" is unchanged: a finding the tester answered `stands:` that the
last review does not repeat counts as fixed, and its How verified line says why.

## The agent

`agents/code-reviewer.md`: `name`, `description`, `tools: Read, Grep, Glob`, `model: opus`, the first paragraph and the
paragraph and block after "End your last message" stay byte for byte. The text between them becomes exactly this (each
phrase the lint pins is on one line, as here):

```markdown
Check each of these and report a finding when one fails:

- every acceptance criterion of the issue has a test that would fail without the change (rule 1 below);
- the tests can fail and none of the tester's was weakened (rules 2 and 3 below);
- the change does what the spec says and nothing beyond it;
- no item of the spec's "Not done" list was done;
- every invariant of the project holds;
- the `Check:` line in your prompt reports a green check. A missing line, or a red one, is a blocking finding.

The tests are the tester's, written before the code, and any the producer added. Your prompt lists the tester's files
and the tester's revisions after its first launch; every line the change adds to a tester's file is the tester's. Read
the tests themselves in the checkout, not only the diff. For a bug, the one acceptance criterion is that it is fixed.

1. **Every criterion has a test that would catch a wrong implementation.** For every acceptance criterion find the
   tests that cover it and judge whether at least one of them would fail for a plausible wrong implementation of it (a
   wrong value, a case the criterion names left out, the old behaviour kept), not only for a missing one. A criterion
   with no test, or with only tests that would pass for a wrong implementation, is a blocking finding.
2. **No test of the tester's was weakened.** Compare the tester's tests as it first wrote them with the tests at the
   end: its revisions in your prompt, and every change outside its files that reaches them (a skip or a filter, a
   fixture or helper overridden, a mock in the place of the code under test, a check or test runner that no longer
   runs them). A test removed, skipped, loosened (a weaker assertion, a wider tolerance, a case removed, an expectation
   changed to what the code does instead of what the spec says) or made conditional (it runs only when something holds
   that the check does not ensure) is a blocking finding. A revision that brings a test closer to the spec is not a
   weakening. A tester's file your prompt lists as not committed is not removed: its criterion is not met, and the
   session handles that.
3. **A test that cannot fail.** Report an assertion that is always true, a test that never fails whatever the code
   does, and a test that checks only a mock or a stub instead of the code under test. Such a finding is blocking when a
   criterion relies on the test (it is the criterion's only test, or all of its tests are like it), and advisory
   otherwise. When the tests a criterion relies on are only the producer's and cannot fail, rule 1 wins: report it
   once, under rule 1, as a `test: ` finding (the tester writes the missing test), not here as a code finding.
4. **Test findings.** A finding whose fix belongs in the tester's tests begins its text with `test: ` and goes to the
   tester: every finding of rule 1 (a missing or weak test is the tester's to write, whoever wrote the weak one), and a
   finding of rule 2 or 3 whose file is one of the tester's files. As `<file>` of such a finding name one of the tester's files, or a path on a test path that does not exist yet, where the missing test belongs, with `-` as the line, never an existing file that is not the tester's.
   A test path is a path that matches the `Test paths:` line in your prompt. Every other finding has no prefix and is a
   code finding, also a finding of rule 2 or 3 about a test the producer wrote or about a change outside the tester's
   files that weakens the tester's tests.

A finding is **blocking** when it breaks one of the points above (rule 3 says when its findings are), and **advisory**
for anything else (naming, small style, a possible simplification). Do not pad: report what you can point at, with its
file and line.
```

No line of the agent file other than the block's own format lines may begin with `- blocking <file>:<line> ` or
`- advisory <file>:<line> ` (the lint's equality would fail); the example in decision 5 is not copied into it.

## `/next`

All changes are in `skills/next/SKILL.md`. The picking section, steps 1 to 3 and 5 of "2. Implement the approved
story", "The tester", "The implementer", the code review's steps 1, 2 and 5 and "Hard rules" stay as they are (as
iteration 27 leaves them), except where named.

### Step 4

"let the implementer fix what is blocking" becomes "let the implementer fix what is blocking in the code and the tester
what is blocking in its tests".

### The tester's files (iteration 27's section)

- Rule 1 (**Record**) gains one sentence: "Keep `<tester originals>` beside them: one line `<path> <blob> <round>`
  per tester file, with the `<path>` and `<blob>` of its line here and round 0; a line of it is never replaced. A file a
  later launch of the tester adds gets its line there too, with the blob first recorded for it and the fix round it was
  added in."
- Rule 5 (**A dispute**) gains a paragraph at its end: "The tester's launch for test findings of the code review
  ("The code review", step 4) is checked and recorded by this rule, with the paths named in the test findings in the
  place of the disputed files, by kind. A named path in `<tester files>` is a disputed file: it exists, and the three
  hash cases decide it. A named path that does not exist in the slot is not a disputed file: it is exempt from the check that every disputed file exists and from every check that it is unchanged; the tester may create it, or write the missing test in another new file on a test path, or create nothing, and every file it creates is checked and recorded as a new file.
  A named path that exists and is not in `<tester files>` is not a disputed file: the check that every listed path not
  in `<tester files>` is untracked keeps it unchanged."

### The code review, step 3 (the prompt)

The sentence before the prompt becomes: "It carries facts, not the implementer's own account (its `Criteria`, `Left`,
`Decisions` and `Disputes` lines) and not the tester's (its `Criteria`, `Failing` and `Answers` lines): the reviewer
shares no context with either." After the prompt, one paragraph: "The session fills in the tester's part from git: a
tester file is `committed` when `git -C <slot> rev-parse -q --verify HEAD:<path>` prints its `<blob>` of
`<tester blobs>`, else `not committed`; for every tester file whose `<blob>` differs from its line of
`<tester originals>`, the diff `git -C <slot> diff <original blob> <blob>`, headed by the path and the fix rounds in
which the tester revised it (the session remembers the round of each of its launches that revised the file); a file
the tester added in fix round k is listed as added, without a diff (the reviewer reads it), and when the tester revised
it in a later round, the added line is followed by the diff from the blob it was added with. These diffs are given in full and never cut; the 2000-line rule counts the change's diff alone. With no
tester file both lines say `none`. The test paths line is filled in with the `Test paths:` line of "The tester", step 3, pasted verbatim, and the values of the three keys it names."

The skill file holds the `Test paths:` line once, as now: the prompt template only refers to it (the phrase
``the `Test paths:` line of "The tester", step 3``), and the session pastes the line when it fills in the prompt. No
line of the template starts with `Test paths:`, so the lint's pins of iterations 25 and 26 (exactly one line starting
with `Test paths:` in `skills/next/SKILL.md` and in `skills/fix/SKILL.md`, equal to the one of `agents/tester.md`) stay
true and are not changed.

The prompt becomes (the three new lines after the check line; everything else unchanged):

```markdown
Review the change on branch <branch> in the checkout at <absolute slot path> (use that path for every file you
read) for story #<issue> "<title>".

The acceptance criteria of the issue: <verbatim>.
The spec: <path in the slot> (read it).
The invariants of the project: <config invariants, one per line>.
The implementer's check: <its Check: line>.

The tester's files, written before the code: <one line per path of <tester files>: <path>: committed | not committed; none>.
The tester's revisions after its first launch, as `git diff <original blob> <blob>`: <per revised file: `<path>, revised in fix round <k>[, <k>]:` and the diff; per added file: `<path>: added by the tester in fix round <k>`, and when revised later, `revised in fix round <k>:` and the diff; none>.
The test paths: <the `Test paths:` line of "The tester", step 3, pasted verbatim>; in this project iterations.specDir is <iterations.specDir>, iterations.decisionsDir is <iterations.decisionsDir> and iterations.changelog is <iterations.changelog>.

The change, as `git diff <base>...<branch>`: <the diff; when it is longer than 2000 lines, the --stat and the
instruction to read the files>.

End with the findings block of the workflow skill, and nothing after it.
```

### The code review, step 4

Step 4 ("Read the block"), as iteration 27 leaves it, becomes:

4. **Read the block.** `no findings`, or advisory findings only: go on and keep the advisory lines. With blocking
   findings, while fewer than `review.maxFixRounds` fix rounds have been used (a dispute exchange, an undone round and a
   round for test findings count too), sort the blocking lines. A blocking line is a test finding when its text begins with `test: `, whatever file it names;
   every other blocking line is a code finding. A test finding with the same file and text as one the tester answered `stands:` earlier in this run is not sent to the tester again; it stays open.
   Then fix round k:
   - **Test findings first.** With test findings to send: report `test-finding-<k>`, count the agents as for a dispute
     launch (iteration 28's pointer `Then check the room on the machine (**Parallel work** in the `workflow` skill).`
     stands directly after "count the agents" here, as in rule 5), record `<dispute base>`, launch `nightmill:tester`
     (on `roles.tester.model`, passed explicitly, not a fork) with the test-finding prompt below, and check and record
     its result by rule 5 of "The tester's files", each named path by its kind: a path in `<tester files>` is decided by
     hash; a path that did not exist may be created or left absent; an existing file outside `<tester files>` stays
     unchanged. Every file the tester created is recorded as new in `<tester blobs>` and `<tester originals>` (round
     k). Its `Answers` lines come one per test finding, in their order. A model that cannot be used stops with the line of **Agent roles and models** for
     `tester`, adding that the status of #<issue> is In progress and the slot is taken.
   - **Then the implementer.** When there is a code finding or the tester revised or wrote a test (an `Answers` line is
     `revised:`, or it added a new file beside answers that are all `stands:`): report
     `fix-round-<k>` and launch the fix (a fresh implementer, as in "The implementer", with its prompt and, added at the
     end, the paragraph "The tester has answered the code review" below when the tester was launched in this round, and
     "Fix exactly these blocking findings and nothing else, run the check, commit": the code findings' lines, when there
     are any), read its `Result:` block as in "The implementer", step 3 (the tester's files first, then a dispute), and
     review again from step 2 (the pairing is checked once, not again).
   - **Otherwise** (every test finding was answered `stands:` or stays open, the tester added no file, and there is no
     code finding): launch no
     implementer and review no more; this review is the last.
   Round k is one fix round when the tester or the implementer was launched in it, whatever the number and kinds of
   findings. No valid block, or an error: stop with
   `Stopped: the code review could not be had: <the reason>. Nothing was opened.`

The two long sentences of the sorting rule stay each on one line of the skill (the lint pins them).

The tester's test-finding prompt, with the placeholders filled in:

```markdown
Answer the code review's findings on your tests for story #<issue> "<title>" in <owner>/<repo>.

The slot: <absolute slot path>, branch <branch>. Use that absolute path for every file and `git -C <slot path>` for
every git command; your working directory is not the slot. The code exists now, committed on the branch.
Do not commit: leave every file you change uncommitted in the slot.

The spec: <path in the slot> (read it completely; it is the contract).
The acceptance criteria of the issue, in order: <the criteria, verbatim>.

The code reviewer reported these findings on your tests (`<file>:<line> test: <what is wrong>`):
<the test findings, one per line, without the leading "- blocking ">

In your instructions read "a dispute" as these findings, "the disputed tests" as the tests they name (for a missing test, the test to write), and "the implementer" as the code reviewer.
A finding that asks for a missing test is answered by writing it (`revised:`) or by saying why no test can be written
(`stands:`). Never weaken a test to answer a finding.

Your tests are at: <tester files, one per line>. Change only those of them the findings name; you may add new files on
the test paths. The paths the findings name, one per line, each with the one sentence of its kind:
<path>: this file exists: revise it or say why it stands.
<path>: this path does not exist yet: create it, or write the missing test in another new file on a test path, or say why none is needed.
<path>: this file is not yours: leave it unchanged; write the missing test in a new file on a test path, or say why none is needed.

The project's testing rules:
- the check: <verification.check>
- the bench rule: <verification.benchRule, or "none">
- the invariants: <config invariants, one per line>

In this project iterations.specDir is <iterations.specDir>, iterations.decisionsDir is <iterations.decisionsDir> and
iterations.changelog is <iterations.changelog>.

End with the result block of your instructions, with one Answers line per finding, in their order, and nothing after it.
```

It carries no line of the implementer's result and no advisory finding.

The paragraph added to the implementer's prompt in a round in which the tester answered test findings, at the end of
the prompt, before the code findings when there are any:

```markdown
The tester has answered the code review's findings on its tests:
<the tester's Answers lines>
A revised or new test is in its file, uncommitted; a test that stands is unchanged. Make them pass without changing
them, run the check, commit. If you believe a test is wrong, report it under Disputes.
```

### Step 6: "How verified"

After iteration 27's sentence on `- revised by the tester after a dispute in fix round <k>: ...`, one sentence: "Each
answer of the tester to a test finding follows as
`- tester's answer to the code review in fix round <k>: <the Answers line, as the tester wrote it>`."

### Step 7

Unchanged: an open test finding is an open blocking finding, so "has blocking review findings left" and the sentence
`Auto-merge is not enabled: blocking review findings are still open (see Review).` of "The code review", step 5, apply
as they are.

### Reporting the steps

One row, before the row "just before the launch of fix round k":

| When | Role | Step |
|---|---|---|
| just before the tester's launch for the test findings of fix round k ("The code review", step 4) | `tester` | `test-finding-<k>` |

## `/fix`

All changes are in `skills/fix/SKILL.md`, the same as in `/next` with "fixer" for "implementer", the one regression
test, and these differences.

- **Step 5**: "the fixer fixes what is blocking" becomes "the fixer fixes what is blocking in the code and the tester
  what is blocking in its regression test".
- **The tester's files**: the same two sentences as in `/next` (rules 1 and 5).
- **The code review, step 3**: the sentence before the prompt becomes "It carries facts, not the fixer's own account
  (its `Cause`, `Fix`, `Left` and `Disputes` lines) and not the tester's (its `Criteria`, `Failing` and `Answers`
  lines): the reviewer shares no context with either." The same paragraph on how the tester's part is filled in. The
  prompt gains, after "The bug report: <verbatim>.", the line `The one acceptance criterion: 1. <title> is fixed.`
  (`<title>` without a leading `[Bug] `, as in the tester's prompt), and after "The fixer's check", the same three
  lines as in `/next` ("The tester's files, written before the code", "The tester's revisions after its first launch",
  "The test paths: <the `Test paths:` line of "The tester", step 3, pasted verbatim>; ..."), the `Test paths:` line
  referred to and pasted when the prompt is filled in, never copied into the skill file, as in `/next`.
- **The code review, step 4**: the same text as in `/next`, with "a fresh fixer, as in "The fixer"", "as in "The
  fixer", step 3". The sentence "In "Batch mode" this is a stop of that bug, handled like a `failed` fixer (skipped),
  except for a model that cannot be used, which ends the run." stays and gets: "A `Stopped:` line of the tester's launch
  for test findings is a skip of that bug in the same way; "Commit what exists" does not apply to it (the tester's
  uncommitted files stay as they are in the bug's slot)."
- **The test-finding prompt**: `/next`'s, with "Answer the code review's findings on your regression test for bug
  #<issue> "<title>"", "The bug report, in full: <body>." and "The one acceptance criterion: 1. <title> is fixed."
  instead of the spec and the criteria, and the mapping sentence of the first tester prompt ("In your instructions read
  "story" as this bug, ...") before the sentence that maps "a dispute".
- **The fixer's added paragraph**: the same as the implementer's ("The tester has answered the code review's findings
  on its tests"). The fixer's prompt sentence "In a fix round the test may already be committed with your earlier fix:
  then run it and the check, and fix exactly the blocking findings." is unchanged; the session's check that every path
  of `<tester files>` is in `git -C <slot> diff --name-only origin/<git.baseBranch>..HEAD` covers a file the tester
  added for a finding, as for a dispute.
- **Step 6**: How verified gets the same `- tester's answer to the code review in fix round <k>: ...` lines after the
  test's diff. The auto-merge rule ("not for a partial fix, one that has blocking review findings left, ...") is
  unchanged.
- **Reporting the steps**: the same row, `test-finding-<k>`, role `tester`.

## The workflow skill

Two sentences of "Findings and fix rounds", nothing else (decision 10):

- **"Blocking"**: "a criterion without a test," becomes "a criterion without a test or with only tests that would not
  fail for a wrong implementation, a tester's test removed, skipped, loosened or made conditional,"; the rest of the
  paragraph is unchanged. The words `loosened or made conditional` stay on one line.
- **"Rounds."**, at the end of the paragraph, after iteration 27's sentence: "In `/next` and `/fix` a blocking finding
  of the code reviewer whose text begins with `test: ` is a test finding, whatever file it names: it goes to the
  `tester`, the others to the producer, in the same fix round, which costs one of `review.maxFixRounds` whatever it
  holds; a test finding the tester answered `stands:` is not sent to it again, and a round in which the tester answered
  every test finding `stands:`, added no file and there is no code finding ends the rounds." The words
  `is a test finding` stay on one line.

The format block, "**The pull request.**" and every line the lint pins there are unchanged.

## README

After the paragraph "Before a pull request opens, `/next` and `/fix` have a `codeReviewer` subagent ...", one paragraph:
"The code reviewer also judges the tests: for every acceptance criterion a test that would fail for a wrong
implementation, no test of the tester's removed, skipped, loosened or made conditional (compared with what the tester
first wrote, from the copies `git hash-object` kept), and no assertion that is always true, test that never fails or
test of only a mock that a criterion relies on. It sees the tester's files and the tester's own revisions, never the
implementer's or the tester's account. A blocking finding on a missing or weak test, or on the tester's tests, begins
with `test: ` and is a test finding: it goes back to the tester, the other findings to the implementer or fixer, in the same fix round. A tester
that says why its test stands is shown in How verified, and the finding stays open for the maintainer."

## CHANGELOG

One bullet under `Unreleased`, above the newest iteration's, in the form of the others:
`- Iteration 29 (#45): the code reviewer checks the tests against the spec and that none was weakened. ...`, naming
the four rules of `agents/code-reviewer.md` (a test per criterion that would fail for a wrong implementation, no
tester's test removed, skipped, loosened or made conditional, always-true assertions, never-failing tests and mock-only
tests, blocking when a criterion relies on them, and the `test: ` marker), the three prompt lines with the tester's files,
its revisions (`git diff <original blob> <blob>` from `<tester originals>`) and the `Test paths:` line, that the reviewer gets no account of
the producer or the tester, the routing (test findings to the tester through iteration 27's dispute launch, code
findings to the producer, one fix round of `review.maxFixRounds` for both, a `stands:` answer not sent again), the How
verified line `tester's answer to the code review in fix round <k>`, the report step `test-finding-<k>`, the two
sentences of the workflow skill, and that no config key, status, slot marker, script, findings format or
`agents/tester.md` changes.

## Tests

`/next` and `/fix` are conversations, and the reviewer is an agent, so the lint pins the wording the behaviour depends
on (each pinned phrase on one line of its file; the lint greps line by line), and the manual check does the behaviour.

**`tests/lint.sh`**, new section "== the code reviewer reviews the tests", after iteration 27's "== the tester's tests
are guarded" (it reuses `cr`, `nx`, `fx`, `wf` and `fsection`, or reads them again the same way):

- `agents/code-reviewer.md` contains `would fail for a plausible wrong implementation`, `No test of the tester's was
  weakened`, `removed, skipped, loosened`, `made conditional`, `is not removed`, `always true`, `never fails`,
  `only a mock`, `begins its text with`, `` `test: ` ``, `rule 1 wins`,
  `never an existing file that is not the tester's` and ``matches the `Test paths:` line in your prompt``, and does
  not contain `or the like` (criteria 1 to 4);
- both `skills/next/SKILL.md` and `skills/fix/SKILL.md` contain `<tester originals>`,
  `diff <original blob> <blob>`, `The tester's files, written before the code`,
  `The tester's revisions after its first launch`, `and not the tester's`,
  `A blocking line is a test finding when its text begins with`,
  `` `test: `, whatever file it names ``, `is not sent to the tester again`, `test-finding-<k>`,
  `Answer the code review's findings on your`, `read "a dispute" as these findings`,
  `The tester has answered the code review`, `tester's answer to the code review in fix round`,
  ``the `Test paths:` line of "The tester", step 3``, `exempt from the check that every disputed file exists`,
  `this file exists: revise it or say why it stands`,
  `this path does not exist yet: create it, or write the missing test in another new file on a test path, or say why none is needed`
  and `this file is not yours: leave it unchanged` (criteria 1, 2, 4); and each still has exactly one line starting
  with `Test paths:`, by the unchanged pins of iterations 25 and 26 (the reviewer's prompt only refers to it);
- `skills/fix/SKILL.md` contains `The one acceptance criterion: 1. <title> is fixed.` at least twice (the tester's and
  the reviewer's prompts) (criterion 1);
- the section "Findings and fix rounds" of `skills/workflow/SKILL.md` contains `loosened or made conditional` and
  `is a test finding` (criteria 2, 4);
- `README.md` contains `test finding`.

The existing pins keep passing and are not changed: iteration 18's (the reviewer's `name:`, its `tools:` exactly
`Read, Grep, Glob`, its `model:` equal to the schema default, `changes nothing`, `acceptance criterion`, `Not done`,
`invariant`, `Check:`, `blocking`, `advisory`, `no findings`; the format lines of the findings block equal in the
workflow skill and the reviewer's file, and iteration 20's equality with `agents/spec-reviewer.md`; the code review
items of `/next` and `/fix`), iteration 19's (the `## Review` lines, `fixed in round <k>:` and
`Auto-merge is not enabled: blocking review findings are still open (see Review).`), iteration 23's report items,
iterations 25 and 26's tester items and iteration 27's guard items. `bash tests/check.sh` stays green.

## Verification

The change touches `skills` and `agents`, so the manual check applies. In a throwaway project with nightmill loaded from
a separate checkout of this branch (`claude --plugin-dir <checkout>`; never `--plugin-dir .` in the checkout being
edited, decision 0003), a board, slots, `review.maxFixRounds` 2, and an Approved throwaway story with two criteria that
ask for a small script change, and its spec:

1. **A planted too-weak test** (the issue's own verification). The spec's Tests section tells the tester to test
   criterion 2 only for a non-empty output (it fails before the code, and passes for any wrong value). Run `/next`. The
   reviewer reports `- blocking <the test file>:<line> test: ...` under rule 1; the session reports `test-finding-1`,
   launches `nightmill:tester` with the test-finding prompt (it names no `Criteria`, `Left` or `Disputes` line of the
   implementer); the tester answers `revised: ...`; the line of `<tester blobs>` for that file holds the new blob, and
   `<tester originals>` still the first; the session reports `fix-round-1` and launches the implementer with "The
   tester has answered the code review's findings on its tests", which commits the revised test, green. The second
   review's prompt lists the file `committed` and shows `<path>, revised in fix round 1:` with the diff; it reports no
   finding on the test. The pull request: `fixed in round 1: blocking ... test: ...`, `Fix rounds used: 1 of 2`, How
   verified `- tester's answer to the code review in fix round 1: ... revised: ...` (criteria 1, 4).
2. **Weakened tests and tests that cannot fail.** An agent cannot be made to weaken a test on demand, so the reviewer
   is launched by hand on prepared branches of the slot, with the prompt of "The code review", step 3, filled in as the
   skill says (the tester's files and revisions from the recorded blobs): (a) a branch whose producer's own file skips
   one of the tester's tests (a skip marker or a filter in a shared helper): a blocking code finding, no `test: `
   prefix; (b) a tester revision, given as the diff, that removes a case: a blocking `test: ` finding on the tester's
   file; (c) the same with a wider tolerance, and with the test made conditional on an environment variable the check
   does not set: blocking; (d) an extra test `assert true` beside a good test of the same criterion: an advisory
   finding; the same assertion as the criterion's only test: blocking; (e) a test that checks only a mock: as (d)
   (criteria 2, 3). Record each block.
3. **A mixed review.** As in iteration 18's verification, a spec with a planted detail the implementer is likely to miss,
   plus the weak test of step 1: the review has a code finding and a test finding; round 1 launches the tester
   (`test-finding-1`), then one implementer (`fix-round-1`) with the tester's answers and the code finding;
   `Fix rounds used: 1 of 2` (criterion 4).
4. **A test that stands.** A test finding the tester answers `stands: ...` with no code finding: no implementer is
   launched and no review runs again; the pull request opens with the finding under `Findings still open`, the sentence
   `Auto-merge is not enabled: blocking review findings are still open (see Review).`, auto-merge off, How verified
   `- tester's answer to the code review in fix round 1: ... stands: ...`. With a code finding beside it, the next review
   repeats the test finding: it is not sent to the tester again (criterion 4).
5. **Rounds used up.** `review.maxFixRounds` 0 and the weak test of step 1: no tester is launched, the pull request has
   the `test: ` finding open and auto-merge off (criterion 4).
6. **A test finding on a file that is not the tester's, and a code finding on a test.** By hand, as in step 2: a
   criterion covered only by a weak test the implementer wrote in its own file: the reviewer reports one `test: `
   finding (no code finding for the same test) naming a tester's file, or a path that does not exist yet and matches
   the `Test paths:` line, which the reviewer's prompt shows verbatim. Then, in `/next`, a review block whose `test: `
   finding names a test path that does not exist yet: the tester's prompt says `this path does not exist yet: ...`; the
   tester creates it (or another new file on a test path), the check passes although the path did not exist before,
   and the file is recorded as new in `<tester blobs>` and `<tester originals>`; a second run in which the tester
   answers `stands:` and creates nothing passes the check too (no "every disputed file exists" stop). Then a review
   block with a `test: ` finding that names the implementer's own existing test file: the session reports
   `test-finding-<k>` and sends it to the tester with `this file is not yours: leave it unchanged; ...`, which writes
   the test in a new file on a test path (`revised:`) or answers `stands:`; the implementer's file is unchanged after
   the launch. A finding without the prefix on the implementer's own test goes to the implementer (criterion 4).
7. **`/fix`.** A throwaway bug whose report asks only that the command "does not crash", so the tester's regression test
   is weak: the reviewer's prompt has `The one acceptance criterion: 1. <title> is fixed.` and the tester's file; it
   reports a `test: ` finding; the tester revises the test; the next fixer commits it with the fix;
   `git diff --name-only` lists it; the pull request shows the answer in How verified (criteria 1, 4).
8. **The report step.** While the tester answers a test finding, the slot's marker has role `tester`, step
   `test-finding-1`.

The PR's "How verified" lists the eight results and the check.

## Not done

- Mutation testing or coverage tools (out of scope): the reviewer judges by reading.
- The implementer's side of the rule (#44): the guard, the undo, the disputes, `## Disputed tests` are iteration 27's
  and are not changed.
- No change to `agents/tester.md` (decision 9), to the first tester launch, to the `Test paths:` line or to the tester's
  model or its pairing; the validator still does not compare the tester's model with the reviewer's (epic #41).
- No config key, no separate budget for test findings, no new role, status or slot marker field; no script, no smoke
  step; no decision record.
- No change to the findings block's format lines, to the `## Review` lines, to "CI and merging", to "Agent roles and
  models", to the spec reviewer or to `/spec`.
- No file written for the reviewer: the tester's original text stays in the object store and reaches the reviewer only
  as the revision diffs in its prompt.
- No re-run of the reviewer to settle a `stands:` answer, and no review of the tester's `Answers` by the reviewer: a
  disagreement goes to the maintainer (decision 7).
- No change to `skills/check/SKILL.md`, `/status` or `/models`.
