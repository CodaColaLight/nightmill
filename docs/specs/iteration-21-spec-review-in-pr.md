# Iteration 21: the spec review is recorded in the spec pull request and open blocking findings stop auto-merge

Status: draft, awaiting approval (#40)

Story: #40, epic #30 (Independent spec review). Replaces the plain interim text that iteration 20 (#39) has `/spec`
write into the spec pull request with the `## Review` section that iteration 19 (#37) defines for code pull requests,
adds the matching variant of the comment on the issue, and makes an open blocking finding a named reason not to enable
auto-merge for a spec pull request. Changes `skills/spec/SKILL.md`, `skills/workflow/SKILL.md` (the paragraph "The pull
request" of "Findings and fix rounds" and "CI and merging"), the lint sections of iterations 19 and 20, and one README
sentence. No config key, no script, no change to the status flow, to who sets a status or to the slot marker: none of
`escalation.storyTriggers` applies, so the PR may auto-merge. The change is in `skills/`, so the manual check applies.
`skills/workflow/SKILL.md` is a hot file: no other task may change it while this one is in flight.

**Depends on #39 (iteration 20) and #37 (iteration 19).** It rewrites text and lint phrases that #39 introduces, and it
extends a paragraph and a sentence of the workflow skill that #37 introduces, so it is implemented after both have
merged.

## Goal

The spec pull request shows what the internal review found and what is still open, and blocking findings that remain
stop auto-merge, with the maintainer told on the issue.

## Facts this rests on

- Iteration 20, decision 7, as an interim: when the rounds are used up and blocking findings remain, `/spec` still
  opens the spec pull request, lists them under `Open review findings`, lists advisory findings under `Review notes`,
  adds the line `Reviewed by the specReviewer role on <model> after <r> fix round(s).` and does not enable auto-merge.
  Its lint pins `Open review findings` and `Reviewed by the specReviewer role on`. It said that this story replaces that
  text.
- Iteration 19 (#37) defines, once, in the paragraph "The pull request" of "Findings and fix rounds" in
  `skills/workflow/SKILL.md`, the section `## Review` of a pull request: the lines `- Reviewer: codeReviewer role on
  <model>`, `- Author: <producer> role on <model>` (`implementer` or `fixer`), `- Fix rounds used: <r> of
  <review.maxFixRounds>`, `- Findings fixed: <n>`, `- Findings still open: <b> blocking, <a> advisory`, one line per fixed
  finding (`fixed in round <k>: ...`) and one per open finding as the reviewer wrote it in its last review. Open findings
  are those of the last review; fixed ones are the blocking findings sent back in an earlier round and not repeated with the
  same file and text. It also defines the sentence `Auto-merge is not enabled: blocking review findings are still open
  (see Review).` and adds `has a blocking review finding still open` to the reasons in "CI and merging". Its lint pins
  those phrases.
- A spec pull request has the title `docs: iteration <N> spec (#<issue>)` and the body `Spec for #<issue>.`; since
  iteration 14 a second line `Written by the specWriter role on <model>.`; it has no "How verified" section. `/spec` opens
  it, enables auto-merge (a spec pull request is docs only), sets Spec review and comments on the issue
  `Spec: <path> (PR #<pr>). Waiting for approval.`
- `/next` finds the spec by that comment: `Spec: <path> (PR #<pr>)`; the text after the closing parenthesis is free. It
  reads the file at `<path>` in the repository, so a spec whose pull request is not merged is not on the base branch
  yet.
- The workflow skill's status table says of Spec review: "The spec is written and merged; waiting for the maintainer",
  set by the agent "when the spec PR is open". With open blocking findings the pull request stays open until the
  maintainer merges it. The table is not changed by this story (see "Not done").
- The workflow skill's "CI and merging" runs `gh pr merge <n> <git.mergeFlags>` "when it is a story whose spec was
  approved, a spec PR, or a complete bug fix" and lists the cases in which a skill does not.

## Decisions

**1. The same section, the roles substituted.** A spec pull request gets the `## Review` section of iteration 19 with the
reviewer `specReviewer` and the author `specWriter`. The template lines of the workflow skill stay as #37 wrote them; a
sentence is added under them saying how a spec pull request differs, so that #37's lint phrases stay valid and the format
is still defined once.

**2. Where it goes.** In the body of the spec pull request, under the two existing lines (`Spec for #<issue>.` and
`Written by the specWriter role on <model>.`), because a spec pull request has no "How verified" to follow. The body
keeps `Spec for`, never `Closes`.

**3. The interim text is replaced.** `Open review findings`, `Review notes` and `Reviewed by the specReviewer role on` go;
the section carries everything they carried.

**4. The same sentence withholds auto-merge.** With a blocking finding in the last review the pull request is opened, the
section lists it, `gh pr merge` is not run, and the body says
`Auto-merge is not enabled: blocking review findings are still open (see Review).`, the sentence of iteration 19, so one
sentence means one thing for both kinds of pull request.

**5. The story still goes to Spec review, and the comment says what is open.** The status and the comment happen as
before, in the same order. The comment keeps its prefix, which `/next` reads, and gets a fixed tail when blocking
findings are open:
`Spec: <path> (PR #<pr>). Waiting for approval. Blocking review findings are still open (<b> blocking, <a> advisory): auto-merge is off, see the Review section of the pull request.`
Without an open blocking finding the comment is the one of today, unchanged.

**6. The maintainer merges it.** A spec pull request that auto-merge did not take is merged by the maintainer when they
accept the spec, or revised when they do not; the skill says so in its last message. Nothing in `/next` changes: it still
needs the spec on the base branch, which is the maintainer's merge.

**7. Advisory findings never withhold auto-merge.** With only advisory findings, or none, `/spec` enables auto-merge as
before and the section is there all the same (a missing section would mean no review ran).

## The workflow skill

1. In "Findings and fix rounds", the paragraph "The pull request" (iteration 19) gets one sentence at its end:

   > A spec pull request has the same section with `specReviewer role on <model>` as the reviewer and `specWriter role on
   > <model>` as the author, after the two lines `Spec for #<issue>.` and `Written by the specWriter role on <model>.`
   > (it has no "How verified"); when a blocking finding is still open the comment on the issue says so (see `/spec`).

2. In "CI and merging", the words `has a blocking review finding still open` (iteration 19) become
   `has a blocking review finding still open (a spec PR too)`.

## `/spec`

In `skills/spec/SKILL.md`, "The spec review" of iteration 20:

- its step 5 ("After the last review") is replaced: the session builds the `## Review` section as the workflow skill
  describes (from the blocks of all reviews, the fix rounds used and the models passed to the Agent calls) and puts it in
  the body of the spec pull request under the two existing lines;
- when the last review has a blocking finding the session does **not** run `gh pr merge` and the body carries the sentence
  of decision 4; otherwise it enables auto-merge as before;
- step 5 of the numbered flow (Spec review and the comment) writes the comment of decision 5 when a blocking finding is
  open and the comment of today otherwise;
- step 6 (stop) says, when a blocking finding is open, that auto-merge is off and that the pull request waits for the
  maintainer's merge or revision.

The headings `Open review findings` and `Review notes` and the line `Reviewed by the specReviewer role on <model> after
<r> fix round(s).` of iteration 20 are removed, not kept beside the section. Nothing else changes: the picking, the
branch, the writer, the reviewer, the rounds, the clean-up after a stop, the hard rules.

## README

In "Agent roles and models", the clause added in iteration 20 for `/spec` gets one more: the spec pull request has the
same Review section, and a blocking finding that is still open keeps auto-merge off and is said on the issue.

## Tests

Each acceptance criterion of #40 is a test or a manual scenario. The skills are conversations, so the lint pins the
wording and the manual check does the behaviour.

**`tests/lint.sh`**: the section of iteration 20 ("a separate spec reviewer reviews the spec") loses the phrases `Open
review findings` and `Reviewed by the specReviewer role on` from its list for `skills/spec/SKILL.md`; the section of
iteration 19 ("the review is recorded in the pull request") is extended; and a section "== the spec review is recorded in
the spec pull request" is added:

- the workflow section "Findings and fix rounds" contains `A spec pull request has the same section`, `specReviewer role
  on <model>` and `specWriter role on <model>`; the section "CI and merging" contains `(a spec PR too)`;
- `skills/spec/SKILL.md` contains `## Review`, `Findings fixed`, `Findings still open`,
  `Auto-merge is not enabled: blocking review findings are still open (see Review).` and `Blocking review findings are
  still open (`, and does not contain `Open review findings`, `Review notes` or `Reviewed by the specReviewer role on`;
- the comment `Spec: <path> (PR #<pr>). Waiting for approval.` is still in the skill, unchanged, so that `/next` keeps
  finding the spec.

`bash tests/check.sh` stays green.

## Verification

The change touches `skills`, so the manual check applies. In a throwaway project with nightmill installed from this
checkout (`claude --plugin-dir <checkout>`), a board and Ready throwaway stories:

1. **Clean.** A trivial story: the spec pull request body has `Spec for #N.`, the writer's line and `## Review` with
   `Fix rounds used: 0 of 2`, `Findings fixed: 0`, `Findings still open: 0 blocking, 0 advisory`; auto-merge is enabled; the
   comment is `Spec: <path> (PR #<pr>). Waiting for approval.`
2. **Fixed in a round.** A planted defect the writer can fix: `Fix rounds used: 1 of 2`, one `fixed in round 1:` line, `0
   blocking` open; auto-merge enabled; the plain comment.
3. **Blocking left.** A contradiction the rounds cannot clear: the pull request is opened, the section lists the open
   blocking finding as the last review wrote it, the body carries the sentence of iteration 19, auto-merge is **not**
   enabled (`gh pr view` shows no auto-merge request), the story is at Spec review and the comment ends with `Blocking
   review findings are still open (1 blocking, 0 advisory): ...`.
4. **`/next` still finds it.** After the maintainer merges that pull request and sets Approved, `/next` reads the path
   from that comment and finds the spec.
5. **Advisory only.** The section lists the advisory findings under still open, `0 blocking`; auto-merge is enabled and
   the comment is the plain one.
6. **`review.maxFixRounds` at 0.** One review, `Fix rounds used: 0 of 0`; a blocking finding stays open and auto-merge is off.
7. **A code pull request is unaffected.** `/next` on a story still produces the section with `codeReviewer` and
   `implementer`.

The PR's "How verified" lists the seven results and the check.

## Not done

- No change to the status table of the workflow skill, to the statuses or to who sets one: the story stays at Spec review
  while its pull request waits for the maintainer's merge. If the table's wording ("written and merged") should say that
  the pull request may still be open, that is a separate decision.
- No new board status or label for open findings, and no change to `/next` (it still needs the spec on the base branch).
- No change to what the reviewer checks, to the findings format, to the number of rounds or to the models.
- No review section on code pull requests (that is #37), no script, no config key.
- No automatic comparison of findings across rounds beyond the file and the exact text, as in iteration 19.
