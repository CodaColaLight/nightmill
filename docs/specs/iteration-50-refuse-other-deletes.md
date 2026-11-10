# Iteration 50: the harness refuses the other deletes: deny rules for board item, field, label and release deletes, and the guard refuses branch deletes and every GraphQL mutation no skill sends

Status: draft, awaiting approval (#253)

Story #253, epic #107 (Hardening from the code review). It closes the gap that iteration 47's "Not done" left and
iteration 39's security model lists as "not enforced yet" (#253). Today `Bash(gh project:*)` and `Bash(gh api:*)` let
an agent run `gh project item-delete`, `gh project field-delete` and any GraphQL mutation but `mergePullRequest`
without a prompt, and `gh label delete`, `gh release delete`, `git push --delete`, `git push origin :<branch>` and
`git branch -D` are refused by the skills' text only. After this iteration `/init`'s **Deny rules** line writes 23
rules instead of 18 (five `gh` deletes appended), and the guard (`scripts/guard.sh`, twin `scripts/guard.ps1`) also
refuses a remote branch delete in every `git` form, a forced local branch delete, and every GraphQL mutation whose
top-level fields are not on a fixed allow list of six. `/init` and `/spec` each name the command form they use, so that
no refusal can hit a step of theirs. Changes `scripts/guard.sh`, `scripts/guard.ps1`, `skills/init/SKILL.md`,
`skills/spec/SKILL.md`, `README.md`, `tests/smoke-guard.sh`, `tests/smoke-guard.ps1`, `tests/test-guard-rules.sh` and
`CHANGELOG.md`.

## Story trigger and manual check

**Not a story trigger** (it is a story anyway). Of `escalation.storyTriggers`:

- *A change to the status flow or who sets a status*: no. The status edit rule of iteration 47 (decision 5.6) is
  unchanged; `updateProjectV2ItemFieldValue` stays allowed and is still judged for Ready and Approved. No decision
  record; none of `docs/decisions/` 0001 to 0003 is contradicted (0002's release goes through `scripts/release.sh`,
  whose own `git` and `gh` calls the guard does not see, Facts).
- *A new, renamed or removed config key*: no. The guard reads the keys it read before. The mutation allow list is
  the plugin's behaviour, not a project value, so it lives in the two scripts, not in `.claude/nightmill.json`
  (invariant "Config-driven" holds). `permissions.deny` is Claude Code's key. Invariant "Compatible" holds.
- *A change to the slot marker format*: no. No slot script changes.

**The manual check applies**: `skills` (init, spec) is in `verification.manualCheckPaths`. `hooks/hooks.json` does not
change; the hook it wires does. Its steps are under Tests.

**Both shells** (invariant ticked in the issue): every guard rule below is made in `guard.sh` and `guard.ps1` with the
same refusal lines, and every smoke case goes into `tests/smoke-guard.sh` and `tests/smoke-guard.ps1`. No new smoke
file, so `tests/check.sh`'s step list and `.github/workflows/ci.yml` do not change (`test-guard-rules.sh`,
`smoke-guard.sh` and `smoke-guard.ps1` are already in both).

**Order with open specs.** Iteration 48 (#111, PR #258) changes `skills/spec/SKILL.md`, `next`, `fix`, `story` and
`workflow`, and replaces the README's #111 table row with four rows. Iteration 49 (#160) adds `## Running unattended`
to the README, which names "**Deny rules** (18 rules)". Neither touches the #253 row, the guard or
`tests/test-guard-rules.sh`. Whichever merges second: rebases the README and `skills/spec/SKILL.md` text, keeps both
sides' rows, sets any "18 rules" in the README to "23 rules", and runs `bash tests/test-guard-rules.sh`, whose collision
checks (Tests) then also cover every `gh` and `git` span the other iteration added. Story #254 (the commands the guard
cannot see) stays out of scope; its row is not touched.

## Facts this rests on

Read on `main` at 18fc961 (iteration 49's spec merged, iteration 47 delivered), read only; nothing was run against
GitHub or the board.

- **The gap holds.** `skills/init/SKILL.md` **Deny rules** writes the 18 rules of iteration 47 (decision 3); none names
  `item-delete`, `field-delete`, `label delete` or `release delete`. `scripts/guard.sh` judges `gh` segments for a
  merge, `mergePullRequest` and a status edit, and `git` segments only when the subcommand is `push`, and there only
  for a force push and a push to the base branch. README `### What is enforced` has the row "Other deletes and
  mutations (...) | not enforced yet | #253", and `### What an agent can do` says "`gh project item-delete` and
  `gh project field-delete` are not refused".
- **The GraphQL mutations the skills send** (every `mutation` in `skills/*/SKILL.md` and `agents/*.md`):
  `updateProjectV2Field` (`/init`, the Status, Priority and Area options), `createProjectV2View` and
  `updateProjectV2View` (`/init`, the views), `addSubIssue` (`/story`, the epic link). `/init` names
  `deleteProjectV2Workflow` only to say it is never used. No skill sends `updateProjectV2ItemFieldValue` or
  `enablePullRequestAutoMerge` (the skills use `gh project item-edit` and `gh pr merge <pr> <git.mergeFlags>`), but
  iteration 47 judges the first for Ready and Approved and its smoke test asserts that the second passes (exit 0).
  `/init` does not say how its mutations are sent; `/story` and `/next` send theirs as `gh api graphql -f query='...'`.
  The scripts (`status.*`) send queries only, from inside the script.
- **The skills' deletes.** No skill or agent writes a `gh ... delete` command, `git push --delete`, `-d`, `--prune`,
  `--mirror` or an empty-source refspec. The only branch delete a skill asks for is `/spec`'s clean-up after a stop:
  "When nothing was committed, delete the branch you created" (step 5), with no command; the branch was created with
  `git switch -c <git.specPrefix><N>-<slug> origin/<git.baseBranch>` and has no commit of its own, so `git branch -d`
  deletes it. `git branch -D` appears once, in `/init`'s **Run permissions** "Never broader" list, as a rule that is not
  written. `git branch --no-track <branch> origin/<branch>` (`/next`, workflow) creates a branch.
- **Scripts are not seen.** `scripts/slot.sh` and `scripts/release.sh` run `git branch -D` inside the script. The hook
  gets only the Bash tool's command text (`bash ".../slot.sh" ...`), so their internal calls are not judged and slot
  release and the release rollback are unaffected.
- **gh flag forms.** `gh api graphql` takes the query as a field: `-f`/`--raw-field` or `-F`/`--field` with
  `query=<text>`; `-F query=@<file>` reads it from a file, and `--input <file>` sends a whole request body from a file.
  `gh release` has both `delete` and `delete-asset`.
- **Collision lint.** `tests/test-guard-rules.sh` (`== no rule matches a command the skills write`) fills every
  backticked `git`/`gh` span of the skills and agents, the free text placeholders with
  `x push main -f +x --force :main :refs/heads/main --admin -X DELETE --method DELETE x`, and checks each against the
  rules; it requires exactly 18 rules. It does not run the guard.

## Decisions

**1. The `gh` deletes are deny rules, as in iteration 47.** The criterion allows either; iteration 47 decision 1 gives
deny rules the actions whose usual text is fixed, and a deny rule holds in every permission mode and where the hook
does not run. Five rules are appended after R18, in this order:

| # | Rule | Refuses |
|---|---|---|
| R19 | `Bash(gh project item-delete *)` | removing an item from the board |
| R20 | `Bash(gh project field-delete *)` | deleting a board field (Status, Priority, Area and their values) |
| R21 | `Bash(gh label delete *)` | deleting a label |
| R22 | `Bash(gh release delete *)` | deleting a release |
| R23 | `Bash(gh release delete-asset *)` | deleting a release's asset (`gh release delete *` does not match it) |

23 rules in all. Each begins with a fixed prefix (`gh project item-delete `, `gh project field-delete `,
`gh label delete `, `gh release delete `, `gh release delete-asset `) with no `*` before its end, and no skill writes a
command that begins with one (Facts), so no title or message can make one match. Their usual-spelling limit is the
same as iteration 47's (`gh -R o/r label delete x` is not matched; Risks). The REST forms
(`gh api -X DELETE repos/.../labels/x`, `.../releases/<id>`) are already refused by R5 to R8.

**2. `/init` with 23 rules.** **Deny rules** keeps every step of iteration 47 decision 4, with these changes only:
"add 18 rules" becomes "add 23 rules" and lists R19 to R23 after R18; **exists** when all 23 are present, so a project
set up with the 18 sees the line as **change** and gets the five appended (report `added to .claude/settings.json (5
rules)`); the **Why these** and the plan sentence say "deleting an issue, a board or the repository, a board item or
field, a label or a release". The declined line is unchanged.

**3. The guard refuses a remote branch delete** (any `git` segment whose subcommand is `push`, as iteration 47
decision 5.5 finds it, so the slot form `git -C <slot path> push` is judged and `stash push` and `commit` are not).
After the force check and before the base-branch check, the words after `push` are judged:

- a word is `--delete`, `-d`, `--prune` or `--mirror`, or is a cluster of short options after one dash that contains
  `d` (`-ud`); or
- a word that does not start with `-` and is not the value of `-o`, `--push-option`, `--repo`, `--receive-pack` or
  `--exec` written as a separate word starts with `:` and is longer than `:` (an empty source: `:<branch>`,
  `:refs/heads/<branch>`). A bare `:` (the matching push) is not a delete.

So `git push origin :main` gets the delete line, not the base line. `--prune` and `--mirror` are included because they
delete remote branches too; the issue names `--delete` and the empty source as the forms, not as the whole list.

**4. The guard refuses a forced local branch delete**: a `git` segment whose subcommand is `branch` and whose words
after it hold `-D` or a short cluster that contains `D`, or hold both a delete word (`--delete`, `-d`, a short cluster
with `d`) and a force word (`--force`, `-f`, a short cluster with `f`): `git branch -D x`, `git branch -df x`,
`git branch --delete --force x`, `git branch -d -f x`. `git branch -d <branch>` (merged only), `git branch -m`,
`git branch --no-track ...` pass.

**5. The guard refuses every GraphQL mutation that is not on the allow list.** For a `gh` segment with the words `api`
and `graphql`:

1. **The documents.** Every word that starts with `query=`, or with `-fquery=`, `-Fquery=`, `--raw-field=query=` or
   `--field=query=`, gives a document: the text after `query=` (the quotes already removed by the split of iteration
   47 decision 5.3).
2. **Unreadable.** A word that is `--input` or starts with `--input=`, or a document that starts with `@`: refused
   (the query is in a file the guard cannot read). The skills never send a query that way (Facts, decision 6).
3. **Scan** each document once, left to right: skip a string (`"` to the next `"` not escaped by `\`) and a comment
   (`#` to the end of the line); count parentheses `p`; count braces `b` only while `p` is 0; a name
   (`[_A-Za-z][_0-9A-Za-z]*`) read while `p` is 0 is the keyword `mutation` when `b` is 0, and a top-level field when
   `b` is 1. Names inside arguments, variables, nested selections and strings are not looked at.
4. **The rule.** A document with the keyword `mutation` is refused when one of its top-level fields is not one of:
   `addSubIssue`, `createProjectV2View`, `enablePullRequestAutoMerge`, `updateProjectV2Field`,
   `updateProjectV2ItemFieldValue`, `updateProjectV2View`. The refusal names the first such field. An alias
   (`a: deleteIssue(...)`), a fragment spread (`... on X`) or a directive at the top level gives a name that is not on
   the list, so it is refused too, on the safe side. A document with no `mutation` keyword (a query) is not judged.
   A mutation with no top-level field is not refused (GitHub rejects it).
5. **Order** within a segment: iteration 47's merge checks first (so `mergePullRequest` keeps its line), then this
   rule, then iteration 47's status edit check (so an allowed `updateProjectV2ItemFieldValue` to Ready or Approved is
   still refused with the status line). The rest of the guard (segments, command substitutions, first refusal wins,
   off without `.claude/nightmill.json`) is unchanged.

**Why these six.** The first four, `addSubIssue`, `createProjectV2View`, `updateProjectV2View` and
`updateProjectV2Field`, are the ones the skills send (Facts), and the criterion lets them through.
`updateProjectV2ItemFieldValue` is the API form of the `gh project item-edit` the skills run, and iteration 47 already
judges it; `enablePullRequestAutoMerge` is the API form of the skills' merge step, and iteration 47's smoke test
asserts that it passes, which this spec does not contradict. An allow list is used, as the issue suggests: it is six
names, where a deny list would have to name every other mutation GitHub has or adds.

**6. The skills name the command form.** So that no refusal hits a step whose command a skill leaves to the model:

- `skills/init/SKILL.md`, **Board, field by field**, after the sentence "Read ids with `gh project field-list ...`":
  "Send each mutation of this line and of **Board views** inline, one per call, as
  `gh api graphql -f query='mutation { ... }'`; never from a file or with `--input`, which the guard refuses."
- `skills/spec/SKILL.md`, step 5 (**Clean-up after a stop**): "delete the branch you created" becomes "delete the
  branch you created with `git branch -d <branch>` (it is empty and you made it; this is not the deletion of a file);
  if git refuses, leave it and say so, never force it". The rest of the step is unchanged.

**7. The refusal lines**, exactly, added to the seven of iteration 47 decision 5.7 in both scripts:

- `nightmill guard: refused: deleting a remote branch. Push only with git push -u origin <branch>; never --delete, --prune, --mirror or an empty source.`
- `nightmill guard: refused: a forced branch delete. Delete only a merged branch, with git branch -d <branch>.`
- `nightmill guard: refused: the GraphQL mutation <name>, which no skill sends.`
- `nightmill guard: refused: a GraphQL query the guard cannot read (--input or query=@<file>). Send it inline, as gh api graphql -f query='...'.`

`<name>` is the first top-level field not on the list. One line on stderr, exit 2, as before.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | `/init` writes deny rules, or the guard refuses, the remaining `gh` deletes: project items and fields, labels and releases | Decisions 1 (R19 to R23), 2 |
| 2 | The guard refuses a remote branch delete (`git push --delete`, a push of an empty source) and a forced local branch delete | Decisions 3, 4, 7 |
| 3 | The guard refuses a GraphQL mutation that no skill sends, and lets through the mutations the skills do send | Decisions 5, 6 (`/init`'s form), 7 |
| 4 | No rule or refusal matches a command the skills write, for any title or message they put into it | Decisions 1 (fixed prefixes), 3 to 5 (subcommand and top-level judging), 6; Tests, `tests/test-guard-rules.sh` |
| 5 | The README's security model row for these deletes says what enforces them | Files touched, `README.md` |

## Tests

**`tests/smoke-guard.sh`** and **`tests/smoke-guard.ps1`**, the same new cases in the existing harness (project
`$tmp/proj`, stub `gh`), each asserting the exit code and, for a refusal, the line of decision 7. All existing cases
stay and keep passing (`graphql auto merge` 0, `graphql other ids` 0, `graphql merge` 2 with the merge line).

- Criterion 2, remote (`DEL` = `deleting a remote branch.`): `git push origin --delete feat/5-x` 2 `DEL`;
  `git -C /w/slot-1 push --delete origin feat/5-x` 2; `git push -d origin feat/5-x` 2; `git push -ud origin feat/5-x`
  2; `git push origin :feat/5-x` 2; `git -C /w/slot-1 push origin :refs/heads/feat/5-x` 2;
  `git push origin :main` 2 `DEL`; `git push --prune origin feat/5-x` 2; `git push --mirror origin` 2;
  `git push -u origin feat/5-d` 0; `git push -u origin feat/5-x:feat/5-x` 0;
  `git -C /w/slot-1 commit -m "git push --delete origin x; git branch -D x"` 0;
  `git -C /w/slot-1 stash push --include-untracked -m "Unmet tests for #5: push --delete :x -D" -- t.sh` 0.
- Criterion 2, local (`FBD` = `a forced branch delete.`): `git branch -D feat/5-x` 2 `FBD`;
  `git -C /w/slot-1 branch -D feat/5-x` 2; `git branch -df feat/5-x` 2; `git branch --delete --force feat/5-x` 2;
  `git branch -d -f feat/5-x` 2; `git branch -d feat/5-x` 0; `git branch -m feat/5-x feat/5-y` 0;
  `git branch --no-track feat/5-x origin/feat/5-x` 0.
- Criterion 3, refused (`MUT` = `the GraphQL mutation`), each as `gh api graphql -f query='<doc>'` unless written out:
  `mutation { deleteIssue(input: {issueId: "x"}) { clientMutationId } }` 2 naming `deleteIssue`;
  `mutation { deleteProjectV2Item(input: {projectId: "P", itemId: "I"}) { deletedItemId } }` 2;
  `mutation { deleteProjectV2Workflow(input: {workflowId: "W"}) { deletedWorkflowId } }` 2;
  `mutation { clearProjectV2ItemFieldValue(input: {projectId: "P", itemId: "I", fieldId: "F"}) { clientMutationId } }` 2;
  `mutation Named { updateRepository(input: {repositoryId: "R", hasIssuesEnabled: false}) { clientMutationId } }` 2;
  `mutation { addSubIssue(input: {issueId: "a", subIssueId: "b"}) { issue { number } } deleteIssue(input: {issueId: "x"}) { clientMutationId } }`
  2 naming `deleteIssue`; `mutation { a: deleteIssue(input: {issueId: "x"}) { clientMutationId } }` 2;
  `query { viewer { login } } mutation { deleteIssue(input: {issueId: "x"}) { clientMutationId } }` 2;
  `gh api graphql -f 'query=mutation { deleteIssue(input: {issueId: "x"}) { clientMutationId } }'` 2;
  `gh api graphql --raw-field=query='mutation { deleteIssue(input: {issueId: "x"}) { clientMutationId } }'` 2;
  `tool_name` `PowerShell` with the first case 2;
  `gh api graphql --input m.json` 2 and `gh api graphql -F query=@m.graphql` 2, both with the "cannot read" line;
  `updateProjectV2ItemFieldValue` with `singleSelectOptionId: "AID2"` 2 with the status line (iteration 47, still).
- Criterion 3, passed: the skills' own mutations, written as in the skills with the placeholders filled:
  `/init`'s `updateProjectV2Field` with two options whose descriptions are `"Filed, not reviewed"` and
  `"Acceptance criteria reviewed; an agent may start (maintainer only)"` 0; `createProjectV2View` with
  `layout: BOARD_LAYOUT, configuration: { visibleFieldIds: ["T", "P", "A"] }` and the selection
  `{ projectV2View { id number layout verticalGroupByFields(first: 1) { nodes { ... on ProjectV2SingleSelectField { name } } } } }`
  0; `updateProjectV2View(input: { viewId: "V", filter: "-label:epic,bug" })` 0; `/story`'s
  `gh api graphql -f query='mutation($p:ID!,$c:ID!){ addSubIssue(input:{issueId:$p, subIssueId:$c}){ issue { number } } }' -f p=I_1 -f c=I_1`
  0; `/next`'s `lastEditedAt` query 0;
  `query { search(query: "mutation { deleteIssue }", type: ISSUE, first: 1) { issueCount } }` 0 (a string);
  and none of these calls the stub `gh` (the log stays empty).

**`tests/test-guard-rules.sh`**, changed sections (its collision check keeps passing):

- `== the guard scripts`: each script also contains the four lines of decision 7 up to their first placeholder
  (`nightmill guard: refused: deleting a remote branch.`, `nightmill guard: refused: a forced branch delete.`,
  `nightmill guard: refused: the GraphQL mutation `, `nightmill guard: refused: a GraphQL query the guard cannot read`)
  and each of the six allow-listed names.
- `== init: the Deny rules bullet` (criterion 1): `RULES` gets R19 to R23; the bullet contains
  `a board item or field, a label or a release`; the Board line contains `gh api graphql -f query='mutation { ... }'`.
- `== the rules have a fixed prefix`: the prefix list gets the five prefixes of decision 1.
- `== no rule matches a command the skills write` (criterion 4): the count is 23, not 18. The free text becomes
  `x push main -f +x --force :main :refs/heads/main --admin -X DELETE --method DELETE --delete -d -D --prune --mirror :x x`.
  The rest is unchanged.
- New `== no guard refusal matches a command the skills write` (criterion 4), after it: a temporary project
  (`mktemp -d` with a template, as `smoke-guard.sh` does) with `.claude/nightmill.json`
  `{ "github": { "owner": "o", "projectNumber": 7 } }` and a stub `gh` first on the PATH that prints
  `Ready<TAB>RID1` and `Approved<TAB>AID2` for `project field-list`. Every distinct span the previous section takes,
  filled the same way with `<branch>` as `feat/47-x` (the guard's verdict depends on a branch only when it is or ends
  in `main`, which none of the three is), is fed whole to `bash scripts/guard.sh` as a `Bash` event; and every
  `mutation` document of a `graphql` fence in `skills/*/SKILL.md` (a line that starts, after spaces, with `mutation`
  begins one; it runs to the next such line or the fence's end), filled the same way, is fed as
  `gh api graphql -f query='<document>'`. Each must exit 0; otherwise
  `FAIL: <file>: <command> is refused by the guard: <stderr>`. Two spans are exempt, exactly: `gh pr merge` (a name
  for the merge step, whose full form `gh pr merge <pr> <git.mergeFlags>` is checked) and `git branch -D` (`/init`'s
  list of rules it does not write). Before the scan the harness is tried: `git branch -D x` must exit 2 and
  `git branch -d x` 0, else `FAIL: tests/test-guard-rules.sh: the guard harness is wrong`. The section also fails when
  it found no `graphql` fence, so a moved fence does not pass by being skipped.
- `skills/spec/SKILL.md` contains `git branch -d <branch>`.
- `== the README` (criterion 5): the joined README contains each of R19 to R23 and `23 rules`, no longer contains
  the text `` `gh project field-delete` are not refused ``, and in the
  `## Security model` table: the row that contains `issues/253)` has a State that starts with `enforced by ` and
  contains `deny rules` and `guard`; a row whose Part starts with `Deleting a local file` has the State
  `not enforced yet`; no row holds both `issues/253)` and `not enforced yet`.

`tests/test-security-model.sh` is not changed and keeps passing: #253 stays in an Issue cell, the new file-delete row
uses the `none filed` form its pins 9 and 10 allow for a `not enforced yet` row, and every link keeps the link form.
`tests/test-watch-checks.sh` keeps passing (no added text contains `gh pr merge --admin` or `gh run rerun`).

What the tests cannot show: that Claude Code applies the five new rules and the new refusals to a real call, and that
`/init` and `/spec` take the forms of decision 6. That is the manual check.

**Manual check by the maintainer**, with nightmill loaded from a separate checkout of the branch
(`claude --plugin-dir <that checkout>`, started in another folder, decision 0003), in a throwaway repository with a
board, a ruleset on `main` and the 18 deny rules of iteration 47 in `.claude/settings.json`:

1. `/nightmill:init`, "apply all": **Deny rules** is **change** and the diff appends R19 to R23; the report says
   `added to .claude/settings.json (5 rules)`. A second run: `exists`, files unchanged.
2. In a new session, ask the agent to run `gh label delete <a throwaway label> --yes`,
   `gh release delete <a throwaway tag> --yes`, `gh project item-delete <n> --owner <o> --id <item id>` and
   `gh project field-delete --id <a throwaway field id>`: each is refused without a prompt, naming a deny rule.
3. Ask it to run `git push origin --delete <a pushed branch>`, `git push origin :<that branch>`,
   `git -C <slot path> push --delete origin <branch>` and `git branch -D <an unmerged branch>`: each is refused with the
   guard's line; `git branch -d <a merged branch>` deletes it.
4. Ask it to run a `gh api graphql` `deleteIssue` mutation on a throwaway issue: refused with the mutation line.
5. `/nightmill:story` filing a story under an epic (the `addSubIssue` link) and `/nightmill:init` in a second throwaway
   repository with no board, declining the template copy (field by field, then the views): no refusal; the board has
   the eight statuses and the four views. `/nightmill:spec` on a Ready story to its pull request: no refusal.
6. On Windows with Git Bash: steps 2 and 3 once; `powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke-guard.ps1`
   green. Each result goes into "How verified".

## Files touched

- `scripts/guard.sh`, `scripts/guard.ps1`: decisions 3, 4, 5 and 7; the header comment names the new refusals and
  iteration 50 (#253).
- `skills/init/SKILL.md`: **Deny rules** per decision 2 (23 rules, R19 to R23 after R18, the sentences); the
  **Board, field by field** sentence of decision 6.
- `skills/spec/SKILL.md`: step 5's clean-up sentence of decision 6.
- `README.md`:
  - `### The deny rules and the guard`: "18 rules" becomes "23 rules"; a group "the board, label and release deletes:"
    with R19 to R23; the guard's list gets "a remote branch delete (`git push --delete`, `-d`, `--prune`, `--mirror`, an
    empty source) and a forced branch delete (`git branch -D`), in any `git` form" and "a GraphQL mutation outside the
    six the skills need (`addSubIssue`, `createProjectV2View`, `enablePullRequestAutoMerge`, `updateProjectV2Field`,
    `updateProjectV2ItemFieldValue`, `updateProjectV2View`), and one sent from a file"; one sentence that a project set
    up before runs `/init` again to get the five new rules.
  - `### What an agent can do`: the `Bash(gh project:*)` bullet ends "a deny rule refuses `gh project delete`,
    `item-delete` and `field-delete`"; the `Bash(gh api:*)` bullet's refused list adds "a GraphQL mutation no skill
    sends".
  - `### What is enforced`: the row "Other deletes and mutations (...)" is split (iteration 39: "A row may be split,
    never dropped") into
    `| Deleting a board item or field, a label or a release, a remote branch delete, a forced branch delete, and a GraphQL mutation no skill sends, are refused | enforced by /init's deny rules (the gh deletes, when the line was applied) and the guard hook (the branch deletes and the mutations, where it runs) | [#253](https://github.com/CodaColaLight/nightmill/issues/253) |`
    and `| Deleting a local file without asking (the Edit and Write tools, a shell rm) | not enforced yet | none filed |`
    (`/init's` and `gh` in backticks as in the other rows).
- `tests/smoke-guard.sh`, `tests/smoke-guard.ps1`, `tests/test-guard-rules.sh`: Tests.
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 50 (#253): the harness refuses the deletes and board mutations the
  skills never run. /init writes five more deny rules (gh project item-delete and field-delete, gh label delete, gh
  release delete and delete-asset; 23 in all, run /init again to add them), and the guard refuses a remote branch
  delete (git push --delete, -d, --prune, --mirror or an empty source), a forced branch delete (git branch -D) and
  every GraphQL mutation outside the six the skills need. No config key.` (paths, commands and names in backticks).

Not touched: `hooks/hooks.json`, `skills/workflow/SKILL.md` (its **Hard rules** sentence stays true: "Part of this is
enforced"), the other skills, `agents/`, `SECURITY.md`, the schema, the templates, `tests/check.sh`,
`.github/workflows/ci.yml`, `tests/test-security-model.sh`, `tests/lint.sh`, this repository's own settings files.

## Risks

- **Other spellings.** The five deny rules match the usual text only: `gh -R o/r label delete x`,
  `gh release -R o/r delete v1`, an alias or `sh -c` pass them (as iteration 47's rules; #254 covers what the guard
  cannot see). The guard judges every `git` form, but not `sh -c`, `eval` or a variable that holds the command or the
  query (`-f query="$Q"`): a document the guard sees as `$Q` has no `mutation` keyword and passes. The base branch's
  ruleset (no deletion) stays the backstop for the base branch; other branches have none.
- **False refusals.** Branch deletes are judged only for subcommands `push` and `branch`, and the mutation rule only
  for `gh api graphql` with a `query=` document, so a title or message in a `commit`, `stash push`, `gh pr comment` or
  `gh issue create` cannot trigger them (the smoke cases and the new collision section show it). A GraphQL string or
  comment that holds `mutation` or a field name is skipped by the scan. `/init` sending a mutation from a file, or
  `/spec` forcing its branch delete, would be refused; decision 6 names their forms, and the refusal says what to do.
  A future skill that adds a mutation fails the new collision section until the name is added to the list in both
  scripts.
- **The allow list is wide where it must be.** `updateProjectV2Field` can replace a field's options and strip every
  item of its status; it stays allowed because `/init` needs it. `enablePullRequestAutoMerge` and
  `updateProjectV2ItemFieldValue` stay allowed as iteration 47 has them.
- **Upgrade.** The guard's new refusals come with the plugin; the five deny rules only after `/init` runs again. Until
  then the `gh` deletes are refused by nothing but the text; the README and the CHANGELOG say so.
- **Fail open.** As in iteration 47: a guard that crashes, times out or does not start lets the call through. The scan
  adds no network call.

## Size estimate

`M`: about 70 lines in `guard.sh` and 80 in `guard.ps1`, 45 each in the two smoke tests, 70 in
`tests/test-guard-rules.sh`, 12 in `skills/init/SKILL.md`, 2 in `skills/spec/SKILL.md`, 25 in the README and 5 in
the changelog: about 355 changed lines in nine files.

## Not done

- No local file delete refusal (out of scope in the issue): "Never delete files without asking" stays text; the README
  row says so with `none filed`.
- No guard refusal for the `gh` deletes in other spellings (`gh -R ... label delete`), and no deny rules for the branch
  deletes (the criterion asks the guard for those).
- No refusal of REST mutations other than `DELETE` (`gh api -X PATCH`, `POST`, `PUT`), of `gh project item-archive`,
  `gh project unlink`, `git update-ref -d` or `git tag -d`. (A remote tag delete by an empty source,
  `git push origin :refs/tags/<tag>`, is refused by decision 3, which does not look at the kind of ref.)
- No judging of a query held in a shell variable or built by a command (#254).
- No change to the workflow skill's **Hard rules**, to `/init`'s guard line in its report (iteration 47 Left), to
  `hooks/hooks.json`, or to any rule **Permissions** allows; no new config key; no off switch.

## Left

- **The allow list holds two names no skill sends.** `enablePullRequestAutoMerge` and `updateProjectV2ItemFieldValue`
  are kept because iteration 47 lets the first through (its smoke test) and judges the second; if the maintainer wants
  only the four the skills send, both go and iteration 47's `graphql auto merge` and `graphql other ids` cases change
  to 2.
- **`--prune`, `--mirror` and a query from a file** are refused beyond the forms the issue names (decisions 3 and
  5.2), as remote branch deletes and as mutations the guard cannot judge. Dropping either is a one-line change.
- **The skills' text changes** (decision 6) are in `skills/init` and `skills/spec`, which the issue's "Where" does not
  list; without them a model-chosen form could be refused, against criterion 4.
- **The file-delete row** has `none filed`; if an issue for the Edit and Write tools exists or is filed, the
  implementer links it there.
- **Not verified by a run** (nothing may be run against GitHub from here): gh's attached short form `-fquery=...`, and
  whether `gh release delete-asset` and `gh project field-delete` take the arguments the manual check uses. Manual check
  steps 2 and 5 settle them.
