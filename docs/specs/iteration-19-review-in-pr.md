# Iteration 19: the review is recorded in the pull request and open blocking findings stop auto-merge

Status: delivered in iteration 19 (PR #77)

Story: #37, epic #29 (Independent code review). Replaces the plain interim text that iteration 18 (#36) has `/next` and
`/fix` write into the pull request with a full `## Review` section, defined once in the workflow skill, and makes an
open blocking finding a named reason not to enable auto-merge. Changes `skills/workflow/SKILL.md` (the section
"Findings and fix rounds" of iteration 18 and "CI and merging"), `skills/next/SKILL.md`, `skills/fix/SKILL.md`, the
lint section of iteration 18 and one README sentence. No config key, no script, no change to the status flow or the
slot marker: none of `escalation.storyTriggers` applies, so the PR may auto-merge. The change is in `skills/`, so the
manual check applies. `skills/workflow/SKILL.md` is a hot file: no other task may change it while this one is in
flight.

**Depends on #36 (iteration 18).** This story rewrites text that #36 introduces (its step 5 and the lint phrases that
pin it), so it is implemented after #36 has merged.

## Goal

The pull request shows what the reviewer found and what is still open, and blocking findings that remain stop
auto-merge, the same for `/next` and `/fix`.

## Facts this rests on

- Iteration 18, decision 7, as an interim: when the fix rounds are used up and blocking findings remain, the pull
  request is still opened, lists them under the heading `Open review findings` and auto-merge is not enabled; advisory
  findings go under `Review notes`; one line `Reviewed by the codeReviewer role on <model> after <r> fix round(s).`
  follows the producer's line. Its lint section pins `Open review findings` and `Reviewed by the codeReviewer role on`.
  It said that this story replaces that text with the full section and the rule in "CI and merging".
- The pull request body of `/next` has `Closes #<issue>`, the line `Written by the implementer role on <model>.` and a
  "How verified" section; that of `/fix` has `Fixes #<issue>`, `Fixed by the fixer role on <model>.` and the sections
  Cause, Fix and How verified. When auto-merge is withheld the skill says why in the pull request (`/next` step 7,
  `/fix` step 6).
- The reviewer's block (workflow skill, "Findings and fix rounds") gives `Blocking: <n>`, `Advisory: <n>` and one line
  per finding `- blocking|advisory <file>:<line> <text>`. A fix round sends the blocking lines of a review back to a
  fresh implementer or fixer, and the next review is a new, independent block. The session therefore holds, for every
  review of the run, its block, and the number of fix rounds used.
- The workflow skill's "CI and merging" names the cases in which a skill does not run `gh pr merge <n> <git.mergeFlags>`:
  a change to one of `escalation.storyTriggers`, a partial change, a skipped manual check, or a maintainer who asked to
  review it. An open blocking finding is not on that list.
- A pull request that is opened with Review status and no auto-merge waits for the maintainer; nothing else in the flow
  changes (no comment on the issue, no label, no new status: out of scope of the story).

## Decisions

**1. One section, defined once.** The format of the `## Review` section is a paragraph "The pull request" in the
workflow skill's "Findings and fix rounds", next to the block it summarises; `/next` and `/fix` point at it and carry
only the wording the lint pins. The spec review (#30, #40) can reuse it for spec pull requests.

**2. "Still open" is the last review, verbatim.** The findings still open are exactly the findings of the last review,
blocking and advisory, as the reviewer wrote them. That is unambiguous and cannot drift from what the reviewer
said last.

**3. "Fixed" is what was sent back and did not come back.** The findings fixed are the blocking findings of every
review that was followed by a fix round, grouped by the round that fixed them, minus those that the last review
repeats with the same file and the same text. The line number is not compared (a fix moves lines). A finding that the
reviewer rewords is counted as fixed and its new wording as open: the open list is the authority, the fixed list is
information.

**4. The section is always there.** Every pull request that goes through a review gets the section, also when the
review found nothing (all counts 0), so a missing section means no review ran. A pull request without it is not one of
this workflow's.

**5. Open blocking findings withhold auto-merge, and the pull request says so in one fixed sentence.** The sentence is
`Auto-merge is not enabled: blocking review findings are still open (see Review).`, in the place where a skill already
says why it did not enable auto-merge. The board goes to Review as usual.

**6. Advisory findings never withhold it.** With only advisory findings, or none, the existing rule applies unchanged,
all the other reasons not to enable auto-merge included.

## The `## Review` section

Added to the workflow skill, in "Findings and fix rounds" as a paragraph "The pull request". Its text:

```markdown
**The pull request.** A pull request that went through a review has a section `## Review`, after "How verified", in
this form (the lines are the same for a story and for a bug; `<producer>` is `implementer` or `fixer`):

## Review

- Reviewer: codeReviewer role on <model>
- Author: <producer> role on <model>
- Fix rounds used: <r> of <review.maxFixRounds>
- Findings fixed: <n>
- Findings still open: <b> blocking, <a> advisory

followed by one line per fixed finding, `fixed in round <k>: blocking <file>:<line> <text>`, and one line per open
finding exactly as the reviewer wrote it in its last review, `- blocking <file>:<line> <text>` or
`- advisory <file>:<line> <text>`. `<model>` is the exact string passed as `model` in the Agent call. The open
findings are those of the last review; the fixed findings are the blocking findings that were sent back in an earlier
round and are not repeated in the last review with the same file and text (the line is not compared). With no findings
the counts are 0 and there are no finding lines. With a blocking finding still open the pull request is opened all the
same, the section says so and the pull request says `Auto-merge is not enabled: blocking review findings are still open
(see Review).`
```

and "CI and merging" becomes (the added words in bold here only):

> ... Do not, and say why in the PR, when it changes one of `escalation.storyTriggers`, is partial, skips a required
> manual check, **has a blocking review finding still open**, or the maintainer asked to review it. ...

## `/next` and `/fix`

Iteration 18's step 5 ("After the last review") is replaced. The session, after the last review of the run:

1. builds the `## Review` section from what it held during the run (the blocks of all reviews, the fix rounds used,
   the models it passed to the Agent calls) as the workflow skill says;
2. puts it after "How verified" in the pull request body, and removes nothing else from the body;
3. when the last review has a blocking finding, does **not** enable auto-merge and puts the sentence of decision 5 where
   the skill says why auto-merge was withheld (`/next` step 7, `/fix` step 6);
4. otherwise lets the existing rule decide (`/next` step 7, `/fix` step 6), unchanged.

The headings `Open review findings` and `Review notes` and the line `Reviewed by the codeReviewer role on <model> after
<r> fix round(s).` of iteration 18 are removed, not kept beside the new section. The session's final message to the
maintainer says whether auto-merge is on and, if not, that blocking findings are open. Nothing else in the two skills
changes: the picking, the statuses (Review as usual), the slot, the manual check, the CHANGELOG, the hard rules.

## README

In "Agent roles and models", the sentence added in iteration 18 gets one more clause: the pull request has a Review
section with the reviewer's and the author's model, the rounds used and the findings fixed and still open, and a
blocking finding that is still open keeps auto-merge off.

## Tests

Each acceptance criterion of #37 is a test or a manual scenario. The skills are conversations, so the lint pins the
wording and the manual check does the behaviour.

**`tests/lint.sh`**, the section "== a separate code reviewer reviews the change" of iteration 18 is changed and a
section "== the review is recorded in the pull request" is added:

- `skills/workflow/SKILL.md`, section "Findings and fix rounds", contains `## Review`, `- Reviewer: codeReviewer role on
  <model>`, `- Author: <producer> role on <model>`, `- Fix rounds used: <r> of <review.maxFixRounds>`, `- Findings fixed:
  <n>`, `- Findings still open: <b> blocking, <a> advisory`, `fixed in round <k>:` and `Auto-merge is not enabled:
  blocking review findings are still open (see Review).`;
- the section "CI and merging" contains `blocking review finding`;
- `skills/next/SKILL.md` and `skills/fix/SKILL.md` each contain `## Review`, `Findings fixed`, `Findings still open` and
  `Auto-merge is not enabled: blocking review findings are still open (see Review).`, and neither contains `Open review
  findings`, `Review notes` or `Reviewed by the codeReviewer role on` any more (the interim text is replaced, not kept);
- the phrases of iteration 18 that pinned `Open review findings` and `Reviewed by the codeReviewer role on` are removed
  from its lint section, the others stay.

`bash tests/check.sh` stays green.

## Verification

The change touches `skills`, so the manual check applies. In a throwaway project with nightmill installed from this
checkout (`claude --plugin-dir <checkout>`), a board and Approved throwaway stories (and a Ready bug for `/fix`):

1. **Clean.** A trivial story: the pull request body has `## Review` with `Fix rounds used: 0 of 2`, `Findings fixed:
   0`, `Findings still open: 0 blocking, 0 advisory`, no finding lines; auto-merge is enabled as before.
2. **Fixed in a round.** A story with a planted blocking defect the implementer can fix: the section shows
   `Fix rounds used: 1 of 2`, one `fixed in round 1:` line, `0 blocking` open; auto-merge is enabled.
3. **Blocking left.** A defect the rounds cannot clear: the pull request is opened, the section lists the open blocking
   finding exactly as the last review wrote it, the pull request carries the sentence of decision 5, auto-merge is
   **not** enabled, and the board is at Review. `gh pr view` shows no auto-merge request.
4. **Advisory only.** The section lists the advisory findings under still open, `0 blocking`, and auto-merge is
   enabled as before.
5. **`review.maxFixRounds` at 0.** One review, `Fix rounds used: 0 of 0`; a blocking finding stays open and auto-merge
   is off.
6. **A reworded finding.** If the reviewer rewords a repeated finding, it appears once as fixed and once as open; the
   open list is the last review's.
7. **`/fix`** does the same with a bug and the fixer (`Author: fixer role on <model>`).
8. **Another reason still applies.** A story that changes a config key: no auto-merge, with the existing reason, whether
   or not blocking findings are open.

The PR's "How verified" lists the eight results and the check.

## Not done

- No comment on the issue and no board label or status for open findings: the pull request is where the maintainer
  looks.
- No review section on spec pull requests: that is #40.
- No change to what the reviewer checks or to the format of its block (iteration 18), to the number of rounds, or to
  the models.
- No script, no config key, no change to the status flow or to who sets a status, no change to the slot marker.
- No automatic comparison of findings across rounds beyond the file and the exact text; no merge of near-identical
  findings.
