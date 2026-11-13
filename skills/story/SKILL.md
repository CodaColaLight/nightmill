---
name: story
description: Turn the maintainer's one-line idea into a story issue on the board, filed from the story form under the right epic. Use when asked to file, write or create a story.
argument-hint: <one-line idea>
allowed-tools: Bash(git symbolic-ref -q --short refs/remotes/origin/HEAD *), Bash(git for-each-ref --count=1 *), Bash(MSYS_NO_PATHCONV=1 git show origin/*:.claude/nightmill.json *), Bash(echo "NO BASE CONFIG*"), Bash(cat .claude/nightmill.json *)
---

Turn this one-line idea into a story issue: $ARGUMENTS

Project configuration on the base branch (`origin/HEAD:.claude/nightmill.json`; the first line names the base ref; see **The configuration** in the `workflow` skill):

!`git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || git for-each-ref --count=1 --format="NO origin/HEAD, but %(refname)" refs/remotes/origin; MSYS_NO_PATHCONV=1 git show origin/HEAD:.claude/nightmill.json 2>/dev/null || echo "NO BASE CONFIG: read .claude/nightmill.json of the working tree (cat .claude/nightmill.json); without it, run /nightmill:init first"`

Read the configuration first. *The maintainer* is `maintainer.name`; `<owner>`, `<repo>`, `<project>` come
from `github`; label names from `labels`; areas from `areas`. Where this text and the configuration
disagree, the configuration wins.

1. **Look for an existing issue first.** Do this before anything else: before the epic is looked for and before a
   draft is written, so no work is done for a duplicate.
   - **Two searches.** The first runs now, on the idea. The second runs in step 4, right before the issue is created, on
     the accepted draft's title: everything below holds for it with the title in place of the idea; it asks only about
     similar issues the first search did not show, and with none it creates the issue. Each search runs
     at most once per run, so nothing loops.
   - **Key words.** A text (the idea, or an issue's title) is reduced to key words: a leading `[...] ` (`[Story] `,
     `[Bug] `, `[Epic] `, `[Idea] `) is removed, the text is lower-cased, every character that is not a letter or a
     digit becomes a space, it is split on spaces, words of 1 character and these 53 stop words are dropped: `a an the
     and or but of to in on at by for from with without into onto is are was were be been it its this that these those
     as not no when then than if so do does can has have one all every any before after story bug epic idea`, and
     duplicates are dropped. For comparing, a word longer than 3 characters that ends in `s` but not `ss` loses the
     `s` (`looks` becomes `look`, `issues` becomes `issue`, `class` stays).
   - **What GitHub searches.** The first 8 key words of the idea, in the idea's order, each as written and in its
     other form (the word without its `s` when the `s` rule removed one, else the word with `s` added), joined with
     ` OR `, at most 16 words:
     `gh issue list --state all --search "<w1> OR <w1'> OR ... OR <w8'> in:title" --limit 100 --json number,title,state,stateReason,labels,url`
     No label filter and no state filter beyond `--state all`: open and closed issues of every label come back.
     GitHub returns the candidates; you decide which are similar. An idea with no key word is not searched: ask for
     the idea in more words and file nothing until it has one.
   - **Similar.** A candidate is similar when either holds. *Same title:* its title, reduced up to the split (prefix
     removed, lower-cased, non-letters and non-digits as spaces, spaces collapsed, nothing dropped), equals the idea
     reduced the same way. *Shared words:* it shares at least 2 key words with the idea (after the `s` rule) and at
     least half of the idea's key words, rounded up. An idea of 1 key word is therefore matched only by the same
     title.
   - **What is shown.** At most 5 similar issues, ordered: same title first, then more shared words, then open before
     closed, then the higher number. One line each:
     `#<number> <title> — <open | closed as completed | closed as not planned> — <labels, comma-separated> — <url>`.
     More than 5 similar issues adds one line `... and <k> more`. A closed issue's line says how it was closed; every
     line lists the issue's labels, whatever they are. No similar issue prints
     `No similar issue found (open and closed, any label).` and you go on; no question is asked.
   - **The limit.** When a search returns exactly 100 issues, its limit, print
     `The search hit its limit of 100 issues: older issues may not have been checked.` With no similar issue among
     them, go on as when nothing similar was found: no question is asked and the issue is filed as usual. With similar
     ones, show them and ask as below. This holds for the first and the second search alike.
   - **The question.** When similar issues are shown, ask:
     ``Similar issues exist (above). Answer `file anyway`, `use #<n>` or `do not file`.``
     The whole reply, trimmed and lower-cased:
     - equals `file anyway`: at the first search, go on with step 2, the draft and the rest; at the second search,
       create the issue now: no third search, no return to the epic or the draft.
     - equals `use #<n>` with a shown number: nothing is created and nothing is changed on #<n>; print
       `Not filed: #<n> is the existing issue.` and stop, at either search.
     - equals `do not file`, or no answer: print `Not filed: possible duplicate of #<n>.` and stop, at either search.
     - any other reply, `yes` included: ask once more; a second such reply counts as `do not file`, at either search.

     Only `file anyway` files. The draft is still shown before creating (step 3).
   - **The search fails.** `gh` is missing, not logged in, offline, rate-limited or exits non-zero: print
     `Not filed: the search for existing issues failed: <gh's message>. Nothing was created; run /story again when gh works.`
     and stop. Do not offer to file without the search.
   - **No one to answer.** When the question would be asked and no person can answer (a headless run such as
     `claude -p "/story ..."`, or an agent that follows these steps), do not file; print
     `Not filed: no one to answer whether #<n> is the same story. Run /story in a session with the maintainer.`
     With no similar issue, go on as usual.
   - **The epic step is not checked:** proposing a new epic in step 2 gets no search.
2. **Find the parent epic:** `gh issue list --label <labels.epic> --state open --json number,title`. If it
   is not clear which epic fits, ask; if none fits, propose a new epic (form: `.github/ISSUE_TEMPLATE/epic.yml`)
   and ask before creating it.
3. **Fill every field of `.github/ISSUE_TEMPLATE/story.yml`**, in its order and with its `###` headings:
   Area (from `areas`), Epic (`#number`), Context (link specs and decisions, do not repeat them), Goal (one
   sentence a user would understand), Acceptance criteria (testable checkboxes, **no numbers**: numbers go in
   the spec), Invariants (tick the ones that apply), Out of scope, Verification, Agent notes (files likely
   touched, known gotchas, related issues). Show the draft to the maintainer and adjust.
   **The pause and the limits** (the `workflow` skill): right before step 4 run the gate, `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh"`
   or `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/gate.ps1"`. Exit 0: go on. Exit 1 or 2: stop with
   its `Stopped:` line and create nothing.
4. **Create it:** first run the second search of step 1 on the accepted draft's title, then
   `gh issue create --title "[Story] <title>" --label <labels.story>,<labels.needsSpec>,<labels.areaPrefix><area>,<labels.priorityPrefix><prio> --body-file <file>`.
   Priority is one of `board.priorities`, lower-cased for the label.
5. **Attach it to the epic as a sub-issue**
   (`gh api graphql -f query='mutation($p:ID!,$c:ID!){ addSubIssue(input:{issueId:$p, subIssueId:$c}){ issue { number } } }' -f p=<epic node id> -f c=<story node id>`,
   node ids from `gh issue view N --json id`), make sure it is on the board with status **Backlog**
   (`gh project item-add <project> --owner <owner> --url <issue url>` if it is not there yet), and set its
   `board.areaField` and `board.priorityField` fields. Read the item back and report its status.

Never set Ready or Approved; only the maintainer does. New stories start in Backlog.
