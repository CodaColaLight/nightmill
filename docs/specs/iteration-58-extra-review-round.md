# Iteration 58: when the review rounds run out on fixable findings, the skills propose one extra round

Status: draft, awaiting approval (#332)

Story #332, epic #163 (closing the gaps to comparable tools). Today, when `review.maxFixRounds` fix rounds are used up
and the last review still has a blocking finding, `/spec`, `/next` and `/fix` open the pull request with the findings
listed, keep auto-merge off and end. This iteration keeps that hand-over in every case and adds a judgement after it:
the session sorts every open blocking finding by one rule into *fixable* (it names a concrete fix) or *needs a
decision* (a choice between designs, a story trigger, a conflict with a decision or a spec, a test the tester stands
by, no fix named). When every open finding is fixable and the rounds are used up, the final message proposes one extra
review round, says what it would fix, and runs it when the maintainer answers `extra round`; otherwise it names the
decision that is needed. The final message never offers a merge while fixable findings are open. Because the pull
request is already open when the proposal is made, a run with nobody to answer (a headless `claude -p` run, a driver
step, `/fix all`) ends exactly as today. At most one extra round runs per pull request, and the `## Review` section
marks it. The default of `review.maxFixRounds` goes from 2 to 3. Changes `skills/workflow/SKILL.md`,
`skills/spec/SKILL.md`, `skills/next/SKILL.md`, `skills/fix/SKILL.md`, `schema/nightmill.schema.json`,
`templates/nightmill.example.json`, `README.md`, `tests/lint.sh`, `tests/smoke-validate.sh`,
`tests/smoke-validate.ps1`, the new `tests/test-extra-round.sh` and `CHANGELOG.md`. No script under `scripts/`, no
agent file and this repository's `.claude/nightmill.json` do not change.

## Story trigger and manual check

**No story trigger.** Taking `escalation.storyTriggers` one at a time:

- *A change to the status flow or who sets a status*: no. No status is set, added or moved by the extra round. It
  runs while the item is at Spec review (`/spec`) or Review (`/next`, `/fix`), where the pull request already put it,
  as the check fix rounds of iteration 46 do. `docs/decisions/` 0001 to 0003 stay as they are.
- *A new, renamed or removed config key*: no. `review.maxFixRounds` keeps its name, type, minimum and meaning; only
  its schema `default` changes (2 to 3), and no key is added. A default that changes is not in the list. **Compatible**
  (ticked): the previous version reads every configuration the new one reads, unchanged. A configuration that sets the
  key keeps its value in both versions; one without it gets 3 rounds from the new version and 2 from the old one.
- *A change to the slot marker format*: no. No script changes. The extra round reports the step names a normal round
  already reports (`test-finding-<k>`, `fix-round-<k>`, `code-review`), with `<k>` one higher than today's highest
  (decision 6), which `slot.sh --report` already accepts (1 to 40 letters, digits or `-`).

So `/next` may enable auto-merge on the implementation pull request, unless another rule of step 7 withholds it.

**The manual check applies**: `skills` is in `verification.manualCheckPaths`, and four files under `skills/` change.
The issue's Verification asks for it; its steps are under Tests. No path under `agents` or `hooks` changes.

**Both shells** (invariant not ticked by the issue, and not touched): no script under `scripts/` changes. The test
change in `tests/smoke-validate.sh` is mirrored in `tests/smoke-validate.ps1` with the same cases and texts.

**Hot files.** `skills/workflow/SKILL.md` and `schema/nightmill.schema.json` are in `parallel.hotFiles`;
`parallel.doNotPair` forbids pairing this story with another that changes the schema.

## Facts this rests on

Read on `main` at 830095f (iteration 57 spec merged), on 2026-11-19, read only.

- **The rounds today** (workflow skill, **Findings and fix rounds**): round 0 is the first review; while blocking
  findings remain and fewer than `review.maxFixRounds` fix rounds were used, a fresh producer fixes exactly the blocking
  findings and the reviewer runs again, so a story is reviewed at most `1 + review.maxFixRounds` times. In `/next` and
  `/fix` a dispute exchange, an undone round and a round for test findings each cost one round; a round in which the
  tester answered every test finding `stands:`, added no file and there is no code finding ends the rounds early.
- **The hand-over today**: the pull request is opened all the same, its `## Review` section lists the open findings,
  and its body says `Auto-merge is not enabled: blocking review findings are still open (see Review).` `/spec` adds a
  fixed tail to its issue comment (`Blocking review findings are still open (<b> blocking, <a> advisory): auto-merge is
  off, see the Review section of the pull request.`). Only a pull request with auto-merge on is watched.
- **The final messages today.** `/next` and `/fix` (one bug): "Your final message to the maintainer says whether
  auto-merge is on and, if not, that blocking findings are open." `/spec` step 6: "say that auto-merge is off and that
  the pull request waits for the maintainer's merge (when the spec is accepted) or revision". That last sentence is the
  one that made a merge read like an option in the run the issue describes.
- **The check fix rounds** (iteration 46, #145) are counted per pull request from comments that start
  `Check fix round `, apart from the review rounds, and bounded by the same `review.maxFixRounds`.
- **Nobody answers a headless run** (README, `### Before the first run` and the limits after it). The driver
  (`scripts/drive.sh`, `drive.ps1`, iteration 52) runs `/nightmill:fix all` and `/nightmill:next <N>` with
  `claude -p`, reads each step's final message from its JSON `result`, and takes from it only a `Stopped:` line and,
  for `/fix all`, the `Cause or reason` column of the final table. `/fix all` "fixes every Ready bug without asking
  the maintainer anything". `/story` has the one existing rule for a question nobody can answer (`No one to answer`).
  A skill cannot reliably tell from inside a session whether a person is at the terminal.
- **Who pins the default 2**: `schema/nightmill.schema.json` (`review.maxFixRounds` `default` 2),
  `templates/nightmill.example.json` (`"maxFixRounds": 2`), `tests/lint.sh` (`schema: review.maxFixRounds default is
  not 2` and `review.maxFixRounds is not the schema default 2` for the example), `README.md`
  (`` `review.maxFixRounds` (default 2) `` under `### Agent roles and models`), and `tests/smoke-validate.sh` and
  `.ps1`, whose three cases `fix rounds negative`, `fix rounds a string` and `zero fix rounds` edit the example by the
  text `"maxFixRounds": 2`. No skill, agent, script or fixture names the number. This repository's
  `.claude/nightmill.json` sets `"review": { "maxFixRounds": 2 }`.
- **No script reads the `## Review` section** of a pull request (`scripts/`, `agents/`: no match for `Fix rounds used`
  or `Findings still open`). `scripts/history.*` counts fix rounds per issue as the highest `<k>` of the
  `fix-round-<k>` steps in the ledger. `gh pr edit` is covered by `/init`'s rule `Bash(gh pr:*)`.

## Decisions

**1. The default is 3.** As the maintainer asked: three fix rounds after round 0, so at most 4 reviews per story. It
changes in the schema, the example configuration, the README (both mentions, below) and the tests that pin it; a
configuration that sets the key keeps its value. The check fix rounds read the same key, so their default bound becomes
3 as well; their rule does not change (decision 9). This repository's `.claude/nightmill.json` keeps its explicit 2: it
sets the key, and a change under `.claude/` is never auto-merged (Left).

**2. The rule that tells the two cases apart.** It runs after the **last review** of the run's review rounds, when that
review has at least one blocking finding, and is applied by the session (never by the reviewer, so the findings format
does not change). Each blocking finding of the last review, in order, **needs a decision** when at least one of these
holds, checked in this order; its reason is the first that holds:

| # | Holds when | Reason, as printed |
|---|---|---|
| a | its text names more than one way to resolve it, or asks which, or its fix needs a value, behaviour or design that neither the issue, the spec (in `/next`, the approved spec; in `/fix`, the bug report) nor a decision settles | `a choice between designs` |
| b | its fix is one of `escalation.storyTriggers` (in `/fix` also: the fix would make the bug a story) | `a story trigger: <the trigger, as configured>` |
| c | it says the work, the issue or the spec conflicts with a decision in `iterations.decisionsDir`, with an existing spec, with the approved spec, or that the issue is unclear or contradicts itself | `a conflict with <the decision's or spec's path, or the issue>` |
| d | it is a test finding (text beginning `test: `) that the tester answered `stands:` in this run | `the tester stands by the test` |
| e | its text does not name what to change: neither the missing piece nor the wrong thing and its right form | `no concrete fix named` |

Every other blocking finding is **fixable**. A dispute over the tester's tests still open (`## Disputed tests`) counts
as one more finding that needs a decision, with the reason `a dispute over <file>: <test name>`. The run is then in
exactly one case:

- **the decision case**: at least one finding (or open dispute) needs a decision;
- **the fixable case**: every finding is fixable and the fix rounds are used up (`Fix rounds used` equals
  `review.maxFixRounds`, 0 included). The rounds end short of that with a blocking finding open only by row d, which is
  the decision case, so the two cases cover every run with an open blocking finding.

When the session cannot tell a finding's kind, it needs a decision (row e or a): a stop is the safe side.

**3. The proposal comes after the pull request is open.** The pull request, its `## Review` section, the withheld
auto-merge and (in `/spec`) the issue comment are made exactly as today, in every case; the judgement and the proposal
are only the final message. So nothing waits for an answer before the work is pushed and visible: a run that nobody
answers (a headless `claude -p` run, a driver step) ends with today's hand-over plus a message, and no rule has to
detect whether a person is present (Facts). The only reply that runs the round is the maintainer's next message in the
same session; trimmed and lower-cased it equals `extra round`. Any other reply is no acceptance: the session prints
`No extra round: PR #<pr> stays as it was opened, with auto-merge off and the findings listed in its Review section.`
and runs nothing of the round (what else that reply asks is the maintainer's own instruction, outside these steps).

**4. The bound: at most one extra round per pull request.** Only the run that ran the review rounds itself (round 0 in
this run) makes a proposal, once, in its final message: `/spec` through "The spec review" (rows S4 to S6 and a fresh
run), `/next` through "The code review" (a fresh run, rows N8 and N9), `/fix` with one bug. No proposal is made by
`/fix all` (it asks nothing; decision 8), by a run resumed at an open or merged pull request (`/spec` S1, S2, R1, R2,
`/next` N1), or after an extra round. A later session never gets one for the same pull request: the proposal lives
only in the session that made it. More rounds without asking, or more than one extra round, are not done.

**5. The final messages**, defined once in the workflow skill and used by the three skills. `<r>` is `Fix rounds used`,
`<m>` is `review.maxFixRounds`, `<b>` the count of open blocking findings, `<finding is | findings are>` by `<b>`.
`<producer>` is `specWriter`, `implementer` or `fixer`, `<reviewer>` `specReviewer` or `codeReviewer`, each with the
model passed in the run.

The fixable case:

```
PR #<pr> is open with auto-merge off: <b> blocking review <finding is | findings are> still open after <r> of <m> fix rounds, and each names a concrete fix. A revision is the next step, not a merge.
Proposed: one extra review round, the <producer> role on <model> and then the <reviewer> role on <model>, to fix:
- blocking <file>:<line> <text>
Answer `extra round` to run it now; any other answer leaves the pull request as it is for the maintainer.
```

The decision case (the `Also open, fixable:` block only when a finding is fixable):

```
PR #<pr> is open with auto-merge off: <b> blocking review <finding is | findings are> still open after <r> of <m> fix rounds, and a decision by the maintainer is needed, so no extra round is proposed.
Decision needed:
- <file>:<line> <text> (<the reason of decision 2>)
Also open, fixable:
- blocking <file>:<line> <text>
```

After an extra round whose review still has a blocking finding, the case is judged again and no new proposal is made:

```
PR #<pr> is open with auto-merge off: <b> blocking review <finding is | findings are> still open after the extra review round. <fixable: Each names a concrete fix; a revision is the next step, not a merge. No further round is proposed. | decision: A decision by the maintainer is needed:>
```

followed, in the decision case, by the `Decision needed:` and `Also open, fixable:` blocks above, and in the fixable
case by the finding lines. After an extra round whose review has no blocking finding:
`The extra review round fixed the blocking findings of PR #<pr>; auto-merge is <on | off: <the line that withheld it>>.`

The `<file>:<line> <text>` parts are the reviewer's lines of the last review, as written. In `/spec` the message comes
after the `Decisions` and `Left` lines that step 6 shows. No message of a run with an open blocking finding speaks of a
merge other than in `not a merge`. A run resumed at an open pull request (decision 4) that finds blocking findings open
in its body says `PR #<pr> has blocking review findings still open (see its Review section), so auto-merge is off; this run did not hold the review and proposes no extra round.`
in place of `/spec` step 6's sentence about the merge.

**6. The extra round runs the same cycle as a normal round.** It is fix round `review.maxFixRounds + 1` (`<k>` below),
and it follows the skill's "Read the block" rules for round `<k>` unchanged: the blocking lines of the last review go to
a fresh producer of the same role and model (in `/next` and `/fix`: test findings first to the `tester`, a test finding
answered `stands:` not again, then the producer; the tester's files guarded by rule 3, an undone round by rule 4), the
producer runs the check and commits (in `/spec` the session commits), and then one fresh review by the same reviewer
role and model, with the same prompt (the pairing is not checked again). The count of agents, the room on the machine
and the gate (**The pause and the limits**, points 3 to 5) apply at every launch and before the push, as for any
round. A dispute the producer raises in the extra round is not sent to the tester (no round is left): it stays open as
today. The reports are those of a normal round: `test-finding-<k>`, `fix-round-<k>` and `code-review` (`/next`,
`/fix`; `/spec` reports nothing). The steps around it, per skill:

- **`/next` and `/fix` (one bug).** The checkout is the slot that holds the branch (held until the merge, as today);
  without slots the session's checkout on the branch, its tree clean (`git status --porcelain --untracked-files=all`
  prints nothing). After the review: push with `git -C <slot path> push -u origin <branch>` (in the session's checkout
  without `-C`), never forced, whether or not the extra review has a blocking finding; build the body again as step 6
  of `/next` (step 5 of `/fix`) builds it, from what the run holds, now with the extra round in `## Review` (decision
  7), the `How verified` lines of round `<k>` and `## Disputed tests` as the rules give them; set it with
  `gh pr edit <pr> --body-file <file>`. Then the auto-merge step (`/next` step 7, `/fix` step 6) runs again with its
  rule and its two merge-step checks unchanged; the blocking-findings line is in the body only when the extra review
  has a blocking finding. With auto-merge on, watch the checks (`/next` step 9, `/fix` step 7) as after the first
  opening. The manual check is not run again, as in a check fix round.
- **`/spec`.** Switch to the spec branch (`git switch <branch>`; the tree must be clean); the fresh `specWriter` gets
  the writer's prompt plus the blocking lines and "Fix exactly these blocking findings in the spec file and nothing
  else"; the form check of "The spec writer" step 4 runs on its result; then the review. The session commits the spec
  file only, `git add <spec file>` and `git commit -m "docs: iteration <N> spec (#<issue>), extra review round"`, pushes
  with `git push -u origin <branch>`, never forced, and switches back to the branch it came from. The body is built
  again as step 4 and "The spec review" step 5 build it and set with `gh pr edit <pr> --body-file <file>`; the merge
  step of step 4 runs again (with no blocking finding left: its two checks, then `gh pr merge <pr> <git.mergeFlags>`),
  and with auto-merge on, the watch of step 5. One comment on the issue, only when no comment of the maintainer's login
  on it starts with `Extra review round on PR #<pr>:`:
  `Extra review round on PR #<pr>: <no blocking review finding is open; auto-merge is on. | <b> blocking review <finding is | findings are> still open; auto-merge is off, see the Review section of the pull request.>`
  (an auto-merge withheld by another line: `no blocking review finding is open; auto-merge is off: <the line>.`). The
  status stays Spec review.
- **A round that does not finish** (a `Stopped:` line of one of its launches, a `failed` or wrong-form result, an
  undone round, a review that cannot be had, a checkout that is not clean, a rejected push or a failed `gh pr edit`):
  the round's `Stopped:` line when it has one, then
  `The extra review round did not finish: <the reason>. PR #<pr> stays as it was opened, with auto-merge off; <the slot <s> | the branch <branch>> keeps the round's work, not pushed.`
  (after a rejected push or a failed `gh pr edit` the last part reads `the round's work is pushed` when the push went
  through). Nothing is reverted, the status stays, `/next` and `/fix` report `stopped` to the slot. In `/spec` an
  uncommitted change of the spec file is committed to the local branch with
  `-m "docs: iteration <N> spec (#<issue>), extra review round, unfinished"`, not pushed, and the session switches
  back. A gate exit 1, 2, 3 or 4 is handled as the workflow skill says, and the line above follows its own line.

**7. The `## Review` section marks the extra round.** Only when an extra round ran, the section gets one line directly
after `- Fix rounds used: <r> of <review.maxFixRounds>`, exactly:

```
- Extra rounds used: 1 of 1, accepted by the maintainer
```

`Fix rounds used` stays `<m> of <m>`: the extra round is counted on its own line, not in it. A blocking finding the
extra round fixed (sent back to it and not repeated in the extra review with the same file and text) gets the line
`fixed in the extra round: blocking <file>:<line> <text>` after the `fixed in round <k>:` lines and is counted in
`Findings fixed`; `Findings still open` and the open finding lines are those of the extra review. A pull request
without an extra round has the section exactly as today.

**8. `/fix all` proposes nothing.** It asks nothing by its own rule. Its final table's `PR` cell for a pull request
whose last review has a blocking finding names the case instead of `auto-merge off: <why>`:
`#<pr>, auto-merge off: blocking review findings are still open, fixable: a revision is the next step` or
`#<pr>, auto-merge off: blocking review findings are still open, a decision is needed: <file>:<line> (<the reason>)`
(several joined by `; `). The columns and their order do not change, so the driver's reading of the table (the
`Cause or reason` column) is unaffected.

**9. The check fix rounds do not change.** Their count (comments starting `Check fix round `), their bound
(`review.maxFixRounds`, now 3 by default), their hand-over and their texts stay. An extra round is not a check fix
round: it posts no `Check fix round` comment and uses none of them, and a check fix round never leads to a proposal.

**10. The documentation.** `README.md`: `` `review.maxFixRounds` (default 2) `` becomes
`` `review.maxFixRounds` (default 3) ``; the configuration table's `review.maxFixRounds` row ends with `(default 3)`;
the paragraph on the spec review (after "back to the writer for at most `review.maxFixRounds` rounds") and the one on
the code review (after "for at most `review.maxFixRounds` rounds") each gain:
"When the rounds are used up and every open blocking finding names a concrete fix, the final message proposes one
extra review round (at most one per pull request), which runs only when the maintainer answers `extra round`; a
finding that needs a decision ends the run as before, and the message names the decision. A run nobody answers ends
with the pull request as it was opened." The schema's description of `review.maxFixRounds` gains, after its last
sentence: "When the rounds are used up and every open blocking finding names a concrete fix, /spec, /next and /fix
propose one extra round to the maintainer, at most one per pull request (workflow skill, Findings and fix rounds)."

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | When the rounds are used up and every open blocking finding names a concrete fix, `/spec`, `/next` and `/fix` end with a proposal for one more round that says what it would fix, and run it when the maintainer agrees | Decisions 2 (the fixable case), 3 (the reply `extra round`), 5 (the proposal lists the findings it would fix), 6 (the round) |
| 2 | When an open blocking finding needs a human decision (a choice between designs, a story trigger, a conflict with a decision or a spec), the skill stops as today and says which decision is needed | Decisions 2 (rows a to e), 3 (today's hand-over), 5 (`Decision needed:` with the reason) |
| 3 | The skill tells the two cases apart by a rule the spec states, and its final message names which case applies | Decision 2 (the rule), 5 (each message names its case), 8 (`/fix all`) |
| 4 | An accepted extra round runs the same producer and reviewer cycle as a normal round and is counted and marked as an extra round in the `## Review` section of the pull request | Decisions 6, 7 |
| 5 | When the maintainer declines, or nobody can answer (an unattended run), the pull request is opened as today with auto-merge off and the open findings listed | Decisions 3 (the pull request is opened first; the decline line), 4, 8 |
| 6 | The final message of a run with open blocking findings never presents merging as an option without saying that a revision is the next step when the findings are fixable | Decision 5 (`A revision is the next step, not a merge.`; the resumed-run line replaces `/spec` step 6's sentence) |
| 7 | The default of `review.maxFixRounds` is raised and the schema, the documentation and the tests that pin the default agree; a configuration that sets the key keeps its value | Decisions 1, 10; Tests (lint, smoke-validate) |

## Tests

The skills are conversations, so as in `tests/test-watch-checks.sh` the new **`tests/test-extra-round.sh`** pins the
wording the behaviour depends on: each file is joined (newlines to spaces, runs of spaces made one) and searched for
fixed texts; a missing text prints `FAIL: <file> does not say the extra round item: <text>`, and a text that must be
gone prints `FAIL: <file> still says: <text>`. It takes the repository path as `$1` (default: its parent folder) and
is run by `tests/lint.sh` in a new section `== an extra review round is proposed` with
`bash tests/test-extra-round.sh "$PWD" || fail=1`, so CI runs it in the lint job and `.github/workflows/ci.yml` does not
change. `W` is the section `## Findings and fix rounds` of the workflow skill (read as the lint reads it, code fences
skipped), `S`, `N`, `F` the skills `spec`, `next`, `fix`.

- Criterion 1: `W` says `**When the rounds are used up.**`, `each names a concrete fix`,
  `Proposed: one extra review round, the <producer> role on <model> and then the <reviewer> role on <model>, to fix:`
  and ``Answer `extra round` to run it now``; `S`, `N` and `F` each say `When the rounds are used up` and
  `review.maxFixRounds + 1`; `S` says `docs: iteration <N> spec (#<issue>), extra review round`; `N` and `F` say
  `gh pr edit <pr> --body-file` and `fix-round-<k>`.
- Criterion 2: `W` says `Decision needed:`, `so no extra round is proposed` and each reason of decision 2:
  `a choice between designs`, `a story trigger:`, `a conflict with`, `the tester stands by the test`,
  `no concrete fix named`, `a dispute over`.
- Criterion 3: `W` says `needs a decision` and `fixable` in the rule's paragraph and `a stop is the safe side`; `F`
  says `blocking review findings are still open, fixable: a revision is the next step` and
  `blocking review findings are still open, a decision is needed:`.
- Criterion 4: `W` says `- Extra rounds used: 1 of 1, accepted by the maintainer` and
  `fixed in the extra round: blocking <file>:<line> <text>`, and still says every line the lint's
  `== the review is recorded in the pull request` checks (`- Fix rounds used: <r> of <review.maxFixRounds>`,
  `fixed in round <k>:` and the rest), so a pull request without an extra round keeps today's form; `S` says
  `Extra review round on PR #<pr>:`.
- Criterion 5: `W` says `No extra round: PR #<pr> stays as it was opened, with auto-merge off and the findings listed in its Review section.`,
  `at most one extra round per pull request` and `The extra review round did not finish:`; `F` says, in
  `## Batch mode: /fix all`, `proposes no extra round`; the lint's existing pin of
  `Auto-merge is not enabled: blocking review findings are still open (see Review).` stays green in `W`, `N` and `F`.
- Criterion 6: `W` says `A revision is the next step, not a merge.` and
  `this run did not hold the review and proposes no extra round`; `S` no longer says
  `the pull request waits for the maintainer's merge (when the spec is accepted) or revision`.
- Decision 9 (the check fix rounds unchanged, the issue's Out of scope): `W` says `An extra round is not a check fix round`;
  `tests/test-watch-checks.sh` runs unchanged and stays green.
- Criterion 7: in `tests/lint.sh` the two default pins read 3 (`FAIL: schema: review.maxFixRounds default is not 3`,
  `FAIL: <f>: review.maxFixRounds is not the schema default 3`); `tests/test-extra-round.sh` checks that `README.md`
  says `` `review.maxFixRounds` (default 3) `` and does not say `` `review.maxFixRounds` (default 2) ``, and that the
  schema description says `propose one extra round`. In `tests/smoke-validate.sh` and `.ps1` the three cases edit
  `"maxFixRounds": 3` (else their edit would no longer apply), and a new case in both, `two fix rounds` (edit
  `"maxFixRounds": 3` to `"maxFixRounds": 2`), expects exit 0 and `0 errors, 0 warnings`: a configuration that sets
  the old value is valid and keeps it.

**Only the manual check can show** that the session sorts real findings by the rule, waits for the reply in an
interactive session and not in a headless one, that the extra round runs and updates the pull request in `/spec`,
`/next` and `/fix`, and that `/fix all` names the case in its table. Its steps,
in a scratch project with `/init` done, a board, and `review.maxFixRounds` set to 0 on its base branch (so the first
review's blocking findings use the rounds up), started with `claude --plugin-dir <this checkout>`:

1. `/spec` on a Ready story whose acceptance criterion leaves a number open that only one value fits. When the review
   has a fixable blocking finding: the spec pull request is open with auto-merge off and the issue comment has its
   tail, then the final message is the fixable message of decision 5. Answer `extra round`: a fresh `specWriter` and
   a fresh `specReviewer` run, the commit `..., extra review round` is pushed, the body has
   `- Extra rounds used: 1 of 1, accepted by the maintainer`, and the issue gets one `Extra review round on PR #...`
   comment. (A review with no blocking finding proves nothing: run it again on another story.)
2. `/spec` on a Ready story whose criterion contradicts a decision record in the project's decisions directory: the
   final message is the decision case with `a conflict with <that path>`, and no proposal.
3. `/spec` as in step 1, answering `no`: the decline line, and the pull request unchanged.
4. Headless: `claude -p "/nightmill:next <N>" --plugin-dir <this checkout> --permission-mode manual` on an Approved
   story whose review ends with a fixable blocking finding: the run exits on its own with the pull request open,
   auto-merge off, and the fixable message as its last output; nothing waits.
5. `/next <N>` (interactive) on an Approved story whose code review ends with a fixable blocking finding: the pull
   request is open with auto-merge off, then the final message is the fixable message of decision 5. Answer
   `extra round`: the `tester` runs first when a finding begins `test: `, then a fresh `implementer` and a fresh
   `codeReviewer`; the slot reports `fix-round-1` (`review.maxFixRounds + 1` with 0) and `code-review`; the branch is
   pushed, not forced; the body (set by `gh pr edit`) has `- Extra rounds used: 1 of 1, accepted by the maintainer`
   and the `How verified` lines of round 1; and the auto-merge step ran again: on when the extra review has no
   blocking finding and no other line withholds it, else off with the blocking-findings line. (A review with no
   blocking finding proves nothing: run it again on another story.)
6. `/fix <N>` (one bug, interactive) on a Ready bug whose code review ends with a fixable blocking finding: as step 5,
   with the `fixer` in place of the `implementer`.
7. Headless `/fix all` (`claude -p "/nightmill:fix all" --plugin-dir <this checkout> --permission-mode manual`) with
   a Ready bug whose code review ends with a blocking finding: the run asks nothing and proposes nothing, and that
   bug's `PR` cell in the final table is one of the two cells of decision 8 (`..., fixable: a revision is the next step`
   or `..., a decision is needed: <file>:<line> (<the reason>)`), matching the case of its findings.

## Files touched

- `skills/workflow/SKILL.md`: **Findings and fix rounds** gets the paragraph **When the rounds are used up.** after
  the spec pull request's paragraph: the rule of decision 2 (its table as a list), decisions 3, 4, 5 (the three
  messages, the decline and the resumed-run line), the common part of 6 (round `review.maxFixRounds + 1`, the same
  cycle, the does-not-finish line) and 9 (`An extra round is not a check fix round`); the paragraph **The pull
  request** gets the `Extra rounds used` and `fixed in the extra round:` lines of decision 7.
- `skills/spec/SKILL.md`: "The spec review" step 4 (with blocking findings and no round left: **When the rounds are
  used up**), step 5 (the extra round in the section); the numbered step 6 (the final message of decision 5 in place
  of the sentence about the maintainer's merge); a new subsection `## The extra review round`, between "The spec
  review" and "The checks of the spec pull request", with the `/spec` steps of decision 6.
- `skills/next/SKILL.md`: "The code review" step 4 and step 5 (the final message, the extra round in the section); a
  new subsection `## The extra review round` after "The code review", with the `/next` steps of decision 6; the
  report table's `fix-round-<k>` row says `<k>` is `review.maxFixRounds + 1` in the extra round.
- `skills/fix/SKILL.md`: the same as `/next` for one bug (its steps 5 to 7); `## Batch mode: /fix all` says it
  `proposes no extra round` and gives the two `PR` cells of decision 8 in its table.
- `schema/nightmill.schema.json`: `review.maxFixRounds` `default` 3; the description's sentence of decision 10.
- `templates/nightmill.example.json`: `"maxFixRounds": 3`.
- `README.md`: the four changes of decision 10.
- `tests/lint.sh`: the two default pins 2 to 3 (texts as under Tests); the new section calling
  `tests/test-extra-round.sh`.
- `tests/test-extra-round.sh`: new, the pins under Tests.
- `tests/smoke-validate.sh`, `tests/smoke-validate.ps1`: the three edits read `"maxFixRounds": 3`; the case
  `two fix rounds`.
- `CHANGELOG.md`, under `Unreleased`:

  ```
  - Iteration 58 (#332): when the review rounds run out and every open blocking finding names a concrete fix,
    /spec, /next and /fix keep today's hand-over (the pull request open, auto-merge off, the findings listed) and
    then propose one extra review round in their final message; it runs, with the same producer and reviewer, only
    when the maintainer answers `extra round`, at most once per pull request, and the Review section marks it with
    `Extra rounds used`. A finding that needs a decision (a choice between designs, a story trigger, a conflict with
    a decision or a spec, a test the tester stands by, no fix named) ends the run as before and the message names the
    decision; a run nobody answers ends as before. The default of review.maxFixRounds is 3 (was 2); a configuration
    that sets it keeps its value. No new key, no marker change.
  ```
- `docs/specs/iteration-58-extra-review-round.md`: the status line at delivery.

## Risks

- **The judgement is the session's.** Rows a and e need reading, not matching; a session may call a design choice
  fixable. The extra round is then still only proposed, the maintainer answers, and its review catches a wrong fix;
  an unclear finding falls to the decision case by rule.
- **Three rounds cost more.** A project without the key now pays for up to one more fix round and one more review
  per story, and up to one more check fix round per pull request (decision 9); `limits.turnsPerRole`,
  `limits.costPerIssueUsd` and `limits.minutesPerIssue` still bound a run.
- **The body is rewritten once.** The extra round is the first step that edits an open pull request's body; it is built
  from what the run holds, the same way as at opening, so nothing the maintainer added by hand in between survives.
  The window is the time between the proposal and the answer in one session.
- **History counts the extra round.** `scripts/history.*` reads the highest `fix-round-<k>`, so a story with an extra
  round shows `review.maxFixRounds + 1` fix rounds, which is what happened.
- **A merge in between.** When the pull request merges (by hand) before the maintainer answers, the push of the round
  goes to a merged branch; the round then ends with the does-not-finish line after its push, and the maintainer
  decides. The session does not check the pull request's state again before the push beyond what the gate does.

## Size estimate

M: about 290 changed lines. The workflow skill about 45, `/spec` about 40, `/next` about 35, `/fix` about 40, the
schema 1, the example 1, the README 6, `tests/lint.sh` about 8, the two smoke-validate files about 8, the new test
about 90, the CHANGELOG 9.

## Not done

- No round runs without the maintainer's `extra round`; no second extra round on the same pull request; no extra round
  in `/fix all`, in a headless run that nobody answers, or in a run resumed at an open pull request.
- No change to the findings format, the definitions of blocking and advisory, the pairing rule, the role models or the
  reviewer agents; the reviewer does not classify its own findings.
- No change to the check fix rounds of the watch (#145): their count, bound, comment and hand-over stay.
- No new config key (for example a separate bound for check fix rounds or for extra rounds), no new slot step name,
  no new status, label or decision record.
- No question asked before the pull request opens, and no detection of whether a person is at the terminal.
- This repository's `.claude/nightmill.json` keeps `"maxFixRounds": 2`.
- The manual check is not run again after an extra round of `/next` or `/fix`.

## Left

- **The check fix rounds' default moves with the key.** The issue keeps the check fix rounds out of scope, but they
  share `review.maxFixRounds`, so raising its default to 3 also gives them 3 by default. Keeping them at 2 would need a
  key of their own, which is a story trigger and out of scope; this spec accepts the shared default (decision 9). The
  maintainer may want that confirmed.
- **This repository's value.** `.claude/nightmill.json` sets 2 explicitly and keeps it; if nightmill itself should
  work with 3, the maintainer changes it by hand (a `.claude/` change is never auto-merged).
- **The proposal after the pull request, not before.** The issue's wording ("the pull request is opened as today"
  when the maintainer declines) reads as if the question could come first; decision 3 opens it first in every case so
  that a run nobody answers needs no detection. The maintainer may prefer asking before the pull request in an
  interactive session.
