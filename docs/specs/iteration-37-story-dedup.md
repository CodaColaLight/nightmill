# Iteration 37: /story looks for an existing issue before it files one

Status: delivered in iteration 37 (PR #245)

Story: #148, epic #107 (Hardening from the code review), finding MD-S14. Before `/story` drafts anything and before it
creates, it searches every issue of the repository, open and closed and with any label, for a similar title, shows
what it found and asks; it files only when the person says `file anyway` or nothing similar exists. Changes `skills/story/SKILL.md`, `README.md`, `tests/lint.sh` and `CHANGELOG.md`. Nothing else.

**The finding still holds** on `main` (598224f): `skills/story/SKILL.md` finds the epic, drafts and runs
`gh issue create` without any search.

**Not a story trigger.** No config key is added, renamed or removed (the search filters on no label, so the skill
names no label and needs no key for one). The status flow, who sets a status and the slot marker do not change. No
decision record. The change touches `skills`, so **the manual check applies** (see Verification).

## Goal

A story that already exists is not filed twice.

## Facts this rests on

Checked for this spec on this repository with `gh` (read only).

- `gh issue list --search` takes GitHub's issue search syntax; `gh issue list` adds `is:issue` itself, so pull
  requests never come back (an `is:pr` qualifier is refused). `--state all` returns open and closed issues; without
  `--label` every label is returned (this repository's triage label, `idea`, `bug`, `epic` included). `--json` offers `number`, `title`,
  `state`, `stateReason`, `labels` and `url`. `--limit` caps it; there is no paging flag.
- Words separated by spaces are ANDed: `story looks existing issue in:title` found #148, `look existing in:title` found
  nothing. `a OR b ... in:title` returns titles with any of the words; a query of 16 words joined by 15 `OR`s worked,
  and so did 25. A title that does not exist (`zebra quantum frobnicate in:title`) returns `[]` with exit 0.
- GitHub does not stem: `look` does not find `looks`, `file` does not find `files`, `exists` does not find `existing`.
  Punctuation splits words: `/story` finds titles with `[Story]`, so `story` matches every story title.
- `disable-model-invocation: true` on `/story` (bug #119): the Skill tool refuses it, so today `/story` runs only when a
  person types it, in an interactive session or as the prompt of a headless run (`claude -p`).

## Decisions

**1. Two searches: the idea first, the title last.** The first runs as the new step 1, after `$ARGUMENTS` is known and
before the epic is looked for or a draft is written, so no work is done for a duplicate. The second runs right before
`gh issue create`, on the accepted draft's title, by decisions 2 to 9 with the title in place of the idea; it asks only
about issues the first did not show, and with none it creates (at its limit of 100 too, after the line of decision 3); its answers do what decision 7 says for the second
search (no loop: decision 7). Idea `dedup stories` filed as
`/story looks for an existing issue before it files one`, run again: only the second finds it (same title).

**2. Key words.** A text (the idea, or an issue's title) is reduced to key words: a leading `[...] ` (`[Story] `,
`[Bug] `, `[Epic] `, `[Idea] `) is removed, the text is lower-cased, every character that is not a letter or a digit
becomes a space, it is split on spaces, words of 1 character and these 53 stop words are dropped: `a an the and or but
of to in on at by for from with without into onto is are was were be been it its this that these those as not no
when then than if so do does can has have one all every any before after story bug epic idea`, and duplicates are
dropped. For comparing, a word longer than 3 characters that ends in `s` but not `ss` loses the `s` (`looks` → `look`,
`issues` → `issue`, `class` stays).

**3. What GitHub searches.** The first 8 key words of the idea, in the idea's order, each as written and in its other
form (the word without its `s` when decision 2 removed one, else the word with `s` added), joined with ` OR `:

`gh issue list --state all --search "<w1> OR <w1'> OR ... OR <w8'> in:title" --limit 100 --json number,title,state,stateReason,labels,url`

At most 16 words, no `--label`, no `--state open`. GitHub returns the candidates; the skill decides which are similar.
An idea with no key word is not searched: the skill asks for the idea in more words and files nothing until it has one.
At exactly 100 the list may be incomplete: the skill prints
`The search hit its limit of 100 issues: older issues may not have been checked.` With no similar issue among the 100
it then goes on as when nothing similar was found (it files at the second search) and does not claim that similar
issues exist; with similar ones it shows them and asks decision 7. This holds for the first and the second search alike.

**4. Similar, decided by the skill.** A candidate is similar when either holds:

- **Same title:** its title, reduced as in decision 2 up to the split (prefix removed, lower-cased, non-letters and
  non-digits as spaces, spaces collapsed, nothing dropped), equals the idea reduced the same way.
- **Shared words:** it shares at least 2 key words with the idea (after the `s` rule) and at least half of the idea's
  key words, rounded up. An idea of 1 key word is therefore matched only by the same title.

**5. What is shown.** At most 5 similar issues, ordered: same title first, then more shared words, then open before
closed, then the higher number. One line each:
`#<number> <title> — <open | closed as completed | closed as not planned> — <labels, comma-separated> — <url>`.
More than 5 similar issues adds one line `... and <k> more`. No similar issue among fewer than 100 prints
`No similar issue found (open and closed, any label).` and the skill goes on; no question is asked.

**6. Closed issues and every label are shown.** A closed issue's line says how it was closed; every line lists the
issue's labels, whatever they are. The criterion's triage label is only an example of an issue that must not be
filtered out, and the search has no label filter; the skill does not name that label because it ships to every
project and the label is the maintainer's own (Config-driven).

**7. The question and the answers.** The skill asks:
``Similar issues exist (above). Answer `file anyway`, `use #<n>` or `do not file`.``
The whole reply, trimmed and lower-cased:
- equals `file anyway`: at the first search, the skill goes on with the epic step, the draft and the rest; at the
  second search, it creates the issue now: no third search, no return to the epic or the draft.
- equals `use #<n>` with a shown number: nothing is created and nothing is changed on #<n>; the skill prints
  `Not filed: #<n> is the existing issue.` and stops, at either search.
- equals `do not file`, or no answer: `Not filed: possible duplicate of #<n>.` and the skill stops, at either search.
- any other reply, `yes` included: the question is asked once more; a second such reply counts as `do not file`, at
  either search.

Only `file anyway` files. Each search runs at most once per run, so nothing loops. The draft is still shown before creating, as today (step 2 of the old text).

**8. The search fails.** `gh` is missing, not logged in, offline, rate-limited or exits non-zero: the skill prints
`Not filed: the search for existing issues failed: <gh's message>. Nothing was created; run /story again when gh works.`
and stops. It does not offer to file without the search.

**9. No one to answer.** When decision 7 would ask and no person can answer (a headless run such as
`claude -p "/story ..."`, or an agent that follows these steps), the skill does not file and prints
`Not filed: no one to answer whether #<n> is the same story. Run /story in a session with the maintainer.`
With no similar issue it goes on as today. With `disable-model-invocation: true` (unchanged here) a person always
typed `/story`, so in an interactive session there is always someone to ask; only the headless run reaches this
rule. If #119 removes the flag, an agent that runs `/story` reaches it too and reports the `Not filed:` line instead of
filing; if #119 instead copies the filing steps into `/next`, those copied steps do not search unless #119 says so.

**10. The epic step is not checked.** Proposing a new epic (step 2 of the new text) gets no search: the criteria name
stories only.

## `skills/story/SKILL.md`

A new step 1 **Look for an existing issue first**, holding decisions 2 to 9 in the skill's own words, with the command
of decision 3, the stop word list, the numbers 53, 8, 16, 100, 2 and 5, the line format, the sentences and the question
exactly as written above. The old steps 1 to 4 become 2 to 5, their text unchanged except the step that runs
`gh issue create`, which first runs the second search of decision 1. The frontmatter, the description line, the
configuration preamble and "Never set Ready or Approved" do not change. No other file refers to the step numbers of
`/story`.

## README

The row of `/nightmill:story <idea>` becomes: `Turns a one-line idea into a story issue under the right epic, in
Backlog, after it has shown any open or closed issue with a similar title and asked.`

## CHANGELOG

Under `Unreleased`: `- Iteration 37 (#148): /story searches open and closed issues of any label for a similar title
before it files, shows up to 5 and, if any is similar, files only on "file anyway"; a failed search or a headless run files nothing.`

## Tests

`/story` is a conversation, so the lint pins the wording the behaviour depends on and the manual check shows the
behaviour. **`tests/lint.sh`**, new section `== /story looks for an existing issue first`, before
`== bash files do not use jq`, on the text of `skills/story/SKILL.md` joined into one line (as in
`== text from issues is data`):

- it contains `gh issue list --state all --search`, `in:title`, `--limit 100` and
  `--json number,title,state,stateReason,labels,url` (criteria 1 and 3);
- the backticked command that contains `--state all --search` contains neither `--label` nor `--state open`: no
  label filter, so issues of any label come back (criterion 3);
- the first line of the file that contains `--state all --search` comes before the first that contains
  `gh issue create` (criterion 1: before creating);
- it contains `at least 2 key words`, `At most 5`, `No similar issue found`, `The search hit its limit of 100`,
  `closed as not planned`, `whatever they are` (criteria 1 and 3);
- it contains `` `file anyway` ``, `` `use #<n>` ``, `` `do not file` ``, `trimmed and lower-cased`,
  `no third search`, `at most once per run`,
  ``Only `file anyway` files``, `Not filed: #<n> is the existing issue.`, `Not filed: possible duplicate of #<n>.`,
  `Not filed: the search for existing issues failed`, `Not filed: no one to answer` (criterion 2);
- `README.md`'s `/nightmill:story` row contains `similar title`.

`disable-model-invocation` is not pinned, so #119 can change it. The existing pins keep passing; `bash tests/check.sh`
stays green. No script changes, so no smoke step.

What only the manual check shows: that the match is actually found and shown (criterion 1), that the question is
asked and each answer does what decision 7 says at each search, with nothing created otherwise (criterion 2), and
that closed issues and an issue with a label like step 6's come back (criterion 3). Every criterion has a lint pin on the text; none can be shown working
without the manual check.

## Verification

In a throwaway repository with a board and nightmill loaded from a separate checkout of this branch
(`claude --plugin-dir <checkout>`; never the checkout being edited, decision 0003), and one open epic:

1. `/story a slot report shows the agent's last step`: `No similar issue found ...`, then the usual draft; filed as #A.
2. The same idea again: #A is listed first, with `open`, its labels and its URL, and the question is asked.
   Answer `do not file`: `Not filed: possible duplicate of #A.`; `gh issue list --state all` shows no new issue.
3. Again, answer `use #A`: `Not filed: #A is the existing issue.`; #A is unchanged.
4. Again, answer `yes`, then `hmm`: asked once more, then not filed.
5. Again, answer `File Anyway `: the epic step and the draft follow, then filed as #B; #A is not asked twice.
6. Close #B as not planned, create the label `needs-triage` in the throwaway repository, and create #C by hand with the
   title `Slot reports show the last step of the agent` and that label. `/story slot reports show the agent step`: #A,
   #B and #C are listed; #B's line says `closed as not planned`, #C's lists `needs-triage`.
7. `/story dedup stories`, filed with its draft title as #D; `/story dedup stories` again, and the tester edits the
   second draft's title to #D's exact title: only the second search shows #D, and asks. Answer `file anyway`: filed
   at once, with no third search and no new draft.
8. Start the session with `GH_TOKEN=invalid`: `Not filed: the search for existing issues failed: ...`; nothing created.
9. `claude -p --plugin-dir <checkout> "/nightmill:story a slot report shows the agent's last step"`:
   `Not filed: no one to answer ...`; nothing created. Record what happens if the headless run cannot start the skill.

The PR's "How verified" lists the nine results and the check.

## Not done

- No search before a new epic is proposed (decision 10), none in `/fix` or for bugs.
- No change to an existing issue: `use #<n>` changes nothing on it; no comment, no reopening, no `duplicate` label.
- No search of issue bodies, no fuzzy matching beyond decision 2's `s` rule, no other repository.
- No change to `disable-model-invocation` or to `/next` and the workflow skill (bug #119).
- No config key (the stop words and numbers live in the skill), no script, no schema, no status, no decision record.
