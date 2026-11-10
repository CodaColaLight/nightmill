# Iteration 47: the harness refuses what the hard rules forbid: /init writes deny rules, and a PreToolUse hook refuses Ready, Approved and a merge without --auto

Status: draft, awaiting approval (#110)

Story #110, no epic (it comes from the code review of 0.2.0, finding HI-2, like the stories of epic #107). Today the
allow rules `/init` writes (`Bash(gh pr:*)`, `Bash(gh api:*)`, `Bash(gh issue:*)`, `Bash(gh project:*)`) let an agent run
`gh pr merge --admin`, any GraphQL mutation, `gh issue delete` and `gh project delete`; "never set Ready or Approved" and
"never merge any other way" are kept by the model alone. After this iteration `/nightmill:init` has a new plan line,
**Deny rules**, that writes 18 rules to `permissions.deny` of `.claude/settings.json`: `gh pr merge` with `--admin`,
`gh issue`, `gh project` and `gh repo delete`, `gh api` with the method `DELETE`, force pushes and pushes to
`git.baseBranch` (as `git push ...`). The plugin ships a `PreToolUse` hook, `scripts/guard.sh` with its twin
`scripts/guard.ps1`, that refuses a board status edit to Ready or Approved, every merge that is not
`gh pr merge ... --auto`, and a force push or a push to the base branch in every `git` form, the slot form
`git -C <slot path> push` included, which no deny rule can name without also matching the skills' own commands. Changes
`hooks/hooks.json`, `scripts/guard.sh` (new), `scripts/guard.ps1` (new), `skills/init/SKILL.md`,
`skills/workflow/SKILL.md`, `README.md`, `SECURITY.md`, `tests/smoke-guard.sh` (new), `tests/smoke-guard.ps1` (new),
`tests/lint.sh`, `tests/check.sh`, `.github/workflows/ci.yml` and `CHANGELOG.md`.

## Story trigger and manual check

**Not a story trigger** (it is a story anyway). Of `escalation.storyTriggers`:

- *A change to the status flow or who sets a status*: no. The eight statuses and who sets them stay as the workflow
  skill's table has them; the hook enforces the existing rule that only the maintainer sets Ready and Approved. No
  decision record is needed, and none of `docs/decisions/` 0001 to 0003 is contradicted (0002 already says that the
  release script never uses the admin bypass).
- *A new, renamed or removed config key*: no. The hook reads keys that exist (`github.owner`,
  `github.projectNumber`, `board.statusField`, `board.statuses.ready`, `board.statuses.approved`, `git.baseBranch`); the
  deny rules use `git.baseBranch`. `git.mergeFlags` keeps its name, type and default; decision 7 narrows what works in
  it, which is not a new, renamed or removed key. `permissions.deny` is a key of Claude Code's settings file, not of `.claude/nightmill.json`. The
  option ids are looked up at run time, not stored (decision 6). Invariant "Compatible" holds.
- *A change to the slot marker format*: no. No slot script changes.

**The manual check applies**: `skills` (init, workflow) and `hooks` (`hooks/hooks.json`) are in
`verification.manualCheckPaths`. Its steps are under Tests.

**Both shells** (invariant ticked in the issue): the hook script exists as `scripts/guard.sh` and `scripts/guard.ps1`
with the same behaviour, each with a smoke test in its own shell. `hooks/hooks.json` wires the bash one only, as
iteration 3 did for `session-start` (decision 8).

**Order with open specs.** Iteration 39 (#159, draft) has README rows "not enforced yet: #110" for these refusals; its
lint reads only the `- **Permissions**:` bullet, which this iteration does not change. Whichever merges second sets
those two rows to the state this iteration gives them. Iteration 45 (#213, draft) changes only the D script rules of
**Run permissions**; it touches neither the deny rules nor the hook.

## Facts this rests on

Read on `main` at b49b92c (0.6.0, iteration 46 merged), read only; nothing was run against the board or GitHub.
Claude Code's documentation read on 2026-11-10: `https://code.claude.com/docs/en/permissions`,
`https://code.claude.com/docs/en/permission-modes`, `https://code.claude.com/docs/en/hooks` and
`https://code.claude.com/docs/en/plugins-reference`.

**The finding still holds.** `skills/init/SKILL.md`, **Permissions**, writes `Bash(gh project:*)`, `Bash(gh issue:*)`,
`Bash(gh pr:*)`, `Bash(gh api:*)`, the three read-only git rules and the check's rule to `permissions.allow` of
`.claude/settings.json`; **Edit permission** and **Run permissions** (iteration 43) write only allow rules and an
additional directory to `.claude/settings.local.json`. No line writes `permissions.deny`. `hooks/hooks.json` has one
`SessionStart` entry (`scripts/session-start.sh`) and the pane module `./panel.tsx`; no `PreToolUse` entry. The workflow
skill's **Hard rules** ("Never set Ready or Approved ... Never push to the base branch. Never merge any other way than
with `git.mergeFlags`.") and the "Never forced" lines of `/spec`, `/next` and `/fix` are text only. `gh pr merge 5
--admin --squash` matches `Bash(gh pr:*)`, so it runs without a prompt.

**Option ids.** `/init` reads the Status field's option ids with `gh project field-list` while it builds the board, and
keeps none of them: no key in the schema holds an id, and the workflow skill says "Look option ids up at runtime
(`gh project field-list`); never keep them in notes". The skills set a status with `gh project item-edit` and an
option id (`skills/spec`, `next`, `fix`: "`gh project field-list` for the field and option ids, then `gh project
item-edit`"). The merge is written `gh pr merge <pr> <git.mergeFlags>` everywhere; the default `git.mergeFlags` is
`--auto --squash`, and the schema does not require `--auto` in it. No skill runs `gh api` with `DELETE`, a `delete`
subcommand of `gh`, `gh pr merge --disable-auto`, or a push other than `git push -u origin <branch>` /
`git -C <slot path> push -u origin <branch>`. The word `push` also stands in `git stash push` and
`git -C <slot> stash push` / `git -C <slot path> stash push`, whose `-m "...: <title>"` holds the issue title
(`skills/next/SKILL.md` lines 84 and 426, `skills/fix/SKILL.md` lines 84, 326, 764 and 769), and free text reaches
`git -C <slot path> commit -m "<message>"`. Titles and messages are free text: they can hold ` push`, ` main`, ` -f`,
` +` or `--force`. A branch name cannot hold a space or a colon (git refuses both in a ref name).

**Permission rules** (documentation, in substance):

- Rules are evaluated deny, then ask, then allow; the first match decides, and specificity does not change the order.
  "An allow rule can't carve an exception out of a deny rule." Deny rules "block in every mode, including
  `bypassPermissions`"; allow rules have no effect in `bypassPermissions`.
- A Bash rule matches the whole command text; `*` stands for any text including spaces, anywhere in the rule
  (`Bash(git * main)` matches `git push origin main`); a trailing ` *` also matches the bare command; `:*` is the same as
  a trailing ` *` and only at the end.
- Deny rules apply when any subcommand of a compound command matches, also inside a subshell or a command
  substitution, and they match past any leading variable assignment.
- A rule "doesn't match the same program invoked in a different form ... a deny or ask rule covers the invocation
  Claude usually produces and isn't a security boundary": `Bash(git push *)` does not stop `git -C . push origin main`
  or `git -c push.default=current push origin main`, nor `/usr/bin/...` or `sh -c '...'`. The page points to a
  `PreToolUse` hook for inspecting the full command text.
- A plugin cannot ship permissions: a plugin's `settings` (and its `settings.json`) honour only `agent` and
  `subagentStatusLine`. So the deny rules are written by `/init`, as the issue says.

**Hooks** (documentation, in substance):

- A plugin's `hooks/hooks.json` merges with the user's and the project's hooks. A command hook gets the event as JSON
  on stdin; for `PreToolUse` on the Bash tool that includes `tool_name` (`"Bash"`), `tool_input.command`, `cwd` and
  `permission_mode`. `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PROJECT_DIR` are in the hook's environment.
- Exit code 2 blocks the call; the stderr text is shown to Claude as the reason. "A hook that exits with code 2 stops
  the tool call before permission rules are evaluated, so the block applies even when an allow rule would otherwise
  let the call proceed." Any other non-zero exit, a hook that does not start, or a timeout is a non-blocking error:
  the call goes ahead. "If your hook is meant to enforce a policy, use `exit 2`."
- A `PreToolUse` hook's decision never bypasses deny rules. Among several hooks, deny wins over ask and allow.
- The matcher is the tool name; letters, digits and `|` make an exact list, so `Bash|PowerShell` matches both tools.
- A command hook runs through `sh -c` on macOS and Linux, Git Bash on Windows, and PowerShell on Windows when Git Bash
  is not installed; `"shell"` may be `bash` or `powershell`. The default timeout of a command hook is 600 seconds.
- Iteration 3 ("As built") measured that a second hook entry for PowerShell printed twice or failed, and wired only
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh"`; `session-start.ps1` is smoke-tested but not wired.

**Not verified from this machine** (no PowerShell here; nothing may be run against the live board): whether a `PreToolUse`
hook's exit 2 also refuses in `bypassPermissions` and in auto mode (the pages read do not say; the exit-2 text above
says the block comes before the permission rules); whether project `settings.json` deny rules apply before the
workspace is trusted; the canonical name of Claude Code's PowerShell tool (`PowerShell` assumed); whether the hook fires
for a subagent's Bash calls; `guard.ps1` in Windows PowerShell 5.1 and PowerShell 7. The manual check and CI settle
them (Tests, Left).

## Decisions

**1. Two parts, as the issue splits them.** The deny rules refuse the actions whose usual text is fixed (a delete
subcommand, a flag, a branch name). The hook refuses the two actions a rule cannot recognise: a status edit names an
option id, not the word Ready, and a merge without `--auto` is the absence of a flag, which a deny rule cannot express.
The deny rules are not the only line of defence for the merge: the hook also refuses `--admin` (decision 7). The hook
also refuses a force push and a push to the base branch in every `git` form, because the slot form
`git -C <path> push` has no deny rule that would not also match the skills' own commands (decision 3); the deny rules
keep the `git push` form, so that form is refused even where the hook does not run (decision 8).

**2. The deny rules go to the shared `.claude/settings.json`.** They only take permissions away, they hold no
machine path, and every collaborator's session runs the `gh` allow rules of that same file. They are written to
`permissions.deny` (created as an array when missing), merged without removing or reordering an entry.

**3. The rule list.** `<B>` is `git.baseBranch` (default `main`). Every rule begins, after `Bash(`, with a fixed
command prefix and has no `*` before the end of it: `gh pr merge `, `gh issue delete `, `gh project delete `,
`gh repo delete `, `gh api ` or `git push `. There is **no rule for the slot form** `git -C <path> push`: in a rule a
`*` matches any text, spaces included, so `git -C * push * main *` or `git -C * push * -f*` also matches
`git -C <slot> stash push --include-untracked -m "Unmet tests for #<issue>: <title>" -- <the paths>` and
`git -C <slot path> commit -m "<message>"` whenever the title or message holds ` push` and then ` main`, ` -f`, ` +`
or `--force` (Facts), and no rule text can restrict a `*` to one word. The guard refuses those pushes instead
(decision 5.5); this is the "rules that cannot match those forms" choice, not a lint that only reports the collision.

| # | Rule(s) | Refuses |
|---|---|---|
| R1 | `Bash(gh pr merge *--admin*)` | a merge through the admin bypass, `--admin` anywhere after `merge` |
| R2 to R4 | `Bash(gh issue delete *)`, `Bash(gh project delete *)`, `Bash(gh repo delete *)` | the three deletes the issue names |
| R5 to R8 | `Bash(gh api *-X DELETE*)`, `Bash(gh api *-XDELETE*)`, `Bash(gh api *--method DELETE*)`, `Bash(gh api *--method=DELETE*)` | a REST `DELETE`, the flag before or after the path |
| R9, R10 | `Bash(git push --force*)`, `Bash(git push * --force*)` | `--force`, `--force-with-lease`, `--force-if-includes`, as the first or a later option |
| R11 | `Bash(git push -f*)` | `-f` as the first option |
| R12 | `Bash(git push * -f*)` | `-f` as a later option |
| R13 | `Bash(git push * +*)` | a forcing refspec, `+<src>:<dst>` or `+<branch>` |
| R14 | `Bash(git push * <B>)` | `git push origin <B>` |
| R15 | `Bash(git push * <B> *)` | the same with options after it |
| R16 | `Bash(git push *:<B>)` | `git push origin HEAD:<B>`, `<branch>:<B>` |
| R17 | `Bash(git push *:<B> *)` | the same with options after it |
| R18 | `Bash(git push *:refs/heads/<B>*)` | the full ref name |

18 rules for any `<B>`. Written with the space form of the documentation; the `--force`, `-f`, `+` and `<B>` parts of
R9 to R15 carry a space before them, and R16 to R18 a colon, so that a branch name such as `fix/47-foo`, `a-f`,
`feat/5-x--force` or `feat/5-main` does not match. **Why none can match a command the skills write, for any title or
message:** a rule matches a command only when the command, or one of its subcommands, begins with the rule's prefix.
The skills' commands that begin with one are `git push -u origin <branch>`, `gh pr merge <pr> <git.mergeFlags>`,
`gh api graphql ...` and `gh api repos/...` without `DELETE`; none of them carries a title or a message, and a branch
cannot hold the space or colon each git rule needs. The commands that carry free text, `git stash push`,
`git -C <slot> stash push`, `git -C <slot path> stash push`, `git -C <slot path> commit`, `git commit`,
`gh pr comment`, `gh issue create`, begin with no rule's prefix. The lint checks both halves of this (Tests).

**4. What `/init` does with the line.** A new plan line **Deny rules**, directly after **Permissions** (same file):

1. **Detect.** A rule is present when it is in `permissions.deny` of `.claude/settings.json` or of
   `.claude/settings.local.json` (string equality). **exists** when all 18 are present, else **create** (no
   `settings.json`) or **change**. `defaultMode` does not make it **exists**: deny rules hold in every mode.
2. **Show the exact text** in the plan message with the other settings texts: for a missing file the whole file, for a
   present file the diff (the missing rules appended to `permissions.deny` in the order of decision 3, every other byte
   unchanged). Above it one sentence: these rules refuse, in every permission mode, a merge with `--admin`, deleting an
   issue, a board or the repository, an API `DELETE`, a force push and a push to `<B>`; they match the usual spelling of
   a command, not every spelling, and the base branch's ruleset stays the backstop.
3. **Apply** with the other settings changes, in the order: the permissions, the deny rules, the edit permission, the
   run permissions; merge without removing or reordering an entry; read the file back. A read-back that lacks a rule
   is **failed**, naming the first missing one.
4. **Declined.** `settings.json` gets none of them; the report says
   `Deny rules: declined (the forbidden actions are refused only by the plugin's guard hook and the skills' text)`.
5. **Report row**, one of: `added to .claude/settings.json (<k> rules)`, `exists`, `declined (...)`,
   `failed: <reason>`. After an add the report says that the rules follow `git.baseBranch` and that `/init` is run
   again after it changes (old rules are kept).
6. **The guard line.** The report also prints, with no plan line and nothing asked (the hook comes with the plugin):
   `Guard hook: refuses a status edit to <ready> or <approved> and any merge without --auto (scripts/guard.sh)`. When
   `git.mergeFlags` does not contain the word `--auto`, it adds:
   `git.mergeFlags is "<value>", without --auto: the guard refuses the skills' merge step; add --auto`.

**5. The hook.** `hooks/hooks.json` gets a `PreToolUse` entry next to the `SessionStart` one:

```json
"PreToolUse": [
  {
    "matcher": "Bash|PowerShell",
    "hooks": [
      { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/guard.sh\"", "timeout": 30 }
    ]
  }
]
```

No `; exit 0`: the exit code 2 must reach Claude Code. The script, the same rule in both shells:

1. Read the event from stdin (bash: `scripts/lib/json.sh`, no `jq`; PowerShell: `ConvertFrom-Json`). Input that is not
   valid JSON, a `tool_name` other than `Bash` or `PowerShell`, or an empty `tool_input.command`: exit 0, no output.
2. **Off without nightmill.** No `$CLAUDE_PROJECT_DIR/.claude/nightmill.json` (current directory when the variable is
   unset): exit 0, no output, as `session-start` is silent in a configured project. A plugin enabled at user scope
   thus does not judge other projects.
3. **Split** the command into segments at `&&`, `||`, `;`, `|`, `&` and newlines that stand **outside quotes**, and
   each segment into words at white space outside quotes, with the quotes then removed from a word. Inside single
   quotes nothing is special; inside double quotes and outside quotes a backslash escapes the next character (for
   `tool_name` `PowerShell` a backtick does instead). A command substitution, `$(` ... `)` (bash and PowerShell) or
   `` ` `` ... `` ` `` (bash only), also inside double quotes, is judged as a command of its own, because the shell runs
   it. An unclosed quote runs to the end of the command. So `git commit -m "x; gh pr merge 5 --squash"` is one segment
   whose first word is `git`, and `echo "$(gh pr merge 5 --squash)"` holds a `gh` segment. No other shell parsing.
   Leading `NAME=value` words are dropped. A segment is a `gh` call when its first word is `gh`, ends in `/gh`, or is
   `gh.exe`, and a `git` call when its first word is `git`, ends in `/git`, or is `git.exe`.
4. **Merges** (any `gh` segment):
   - `pr` directly followed by `merge` among its words: refused unless a word is `--auto`; refused when a word is
     `--admin` or starts with `--admin=`. A segment with the word `--disable-auto` is not a merge (it turns
     auto-merge off).
   - `api` among its words and a word that contains `pulls/<digits>/merge`: refused (the REST merge).
   - `api` and `graphql` among its words and the text `mergePullRequest` in the segment: refused (the GraphQL merge;
     `enablePullRequestAutoMerge` is not matched).
5. **Pushes** (any `git` segment). The subcommand is the first word after `git` (the first word) that does not
   start with `-` and is not the value of `-C`, `-c`, `--git-dir` or `--work-tree` written as a separate word. Only a segment
   whose subcommand is `push` is a push: `git -C <slot> stash push ...` (subcommand `stash`) and
   `git -C <slot path> commit -m "... push --force main"` (subcommand `commit`) are not, whatever their message holds.
   The words after `push` are judged:
   - a **force push** when a word starts with `--force`, is `-f`, is a cluster of short options after one dash that
     contains `f` (`-uf`), or starts with `+`;
   - a **push to `<B>`** (`git.baseBranch`, default `main`) when a word that does not start with `-`, and is not the
     value of `-o`, `--push-option`, `--repo`, `--receive-pack` or `--exec` written as a separate word, equals `<B>`,
     ends in `:<B>`, or equals or ends in `refs/heads/<B>`.
   `git push -u origin <branch>` and `git -C <slot path> push -u origin <branch>` pass. A bare `git push` or
   `git push origin` is not judged (Not done).
6. **Status edits** (any `gh` segment with `project` followed by `item-edit`, or with `api` and `graphql` and the text
   `updateProjectV2ItemFieldValue`): the script reads the option ids once per call with
   `gh project field-list <github.projectNumber> --owner <github.owner> --format json --jq '<expr>'`, where `<expr>`
   selects the field named `board.statusField` and prints `<name><TAB><id>` for the options named
   `board.statuses.ready` and `board.statuses.approved` (defaults from the schema when a key is absent). Refused when,
   for `item-edit`, the option-id argument (the word after `--single-select-option-id`, or the text after
   `--single-select-option-id=`) equals either id; for the GraphQL mutation, when either id occurs in the segment's
   text as a whole word (the character before it and the one after it, where there is one, is not a letter, a digit,
   `_` or `-`). An item, field or project id that merely contains an option id does not count. When the lookup fails
   (gh exits non-zero, prints neither id, or a key it needs is missing) a status edit is refused too (decision 6). A
   command with no status edit never calls `gh`.
7. **Refusal**: one line on stderr, exit 2. The lines, exactly:
   - `nightmill guard: refused: a merge without --auto. Merge only with gh pr merge <pr> <git.mergeFlags>; git.mergeFlags must contain --auto.`
   - `nightmill guard: refused: gh pr merge with --admin. Never merge past the checks.`
   - `nightmill guard: refused: a merge through gh api. Merge only with gh pr merge <pr> <git.mergeFlags>.`
   - `nightmill guard: refused: a force push. Push only with git push -u origin <branch>, never forced.`
   - `nightmill guard: refused: a push to <B>. Never push to the base branch.`
   - `nightmill guard: refused: setting <name> on the board. Only the maintainer sets <ready> and <approved>.`
   - `nightmill guard: refused: a status edit, because the <ready> and <approved> option ids could not be read (<reason>). Read the board and try again; never set <ready> or <approved>.`
   The segments are judged in order and the first refusal found is printed; the rest of the command is not judged.
8. Everything else: exit 0, no output, so the normal permission flow decides.

**6. Option ids at run time, not stored.** The issue notes that the hook needs the Ready and Approved option ids,
"which `/init` already reads from the board". `/init` reads them but keeps none, and the workflow skill forbids keeping
them; storing them would add a config key (a story trigger) and go stale when the options are replaced. So the guard
reads them itself, only for a command that edits a status, with the `gh` the skills already use. It fails closed for
that command only: a status edit it cannot judge is refused, every other command is unaffected.

**7. `--auto` is required always.** The issue asks to refuse "a merge without `--auto`", so the guard does not read
`git.mergeFlags`. **This narrows the contract of `git.mergeFlags`:** the workflow skill ("Never merge any other way than
with `git.mergeFlags`") and the schema (a free string, default `--auto --squash`) let a project choose its merge flags
freely; after this iteration the skills' merge step works only when they contain `--auto`. The key, its type, its
default and its schema description stay, so it is not a config-key trigger; the workflow skill says it in decision 9's
sentence ("any merge without `--auto`"). A project whose `git.mergeFlags` lacks `--auto` has its merge step refused,
and `/init`'s report says so (decision 4.6). The same holds for any merge the maintainer asks of the agent, also the
release pull request of decision 0002, which is merged without auto-merge: the guard refuses that merge when the agent is asked
to run it, and the maintainer merges it, not the agent (Files touched, README). `--admin` is refused even next to `--auto`: auto-merge with the admin bypass would still merge past
the checks.

**8. The bash script is wired, the PowerShell one is a twin.** As iteration 3 measured, two entries cannot be made to
run exactly one script on every machine. The wired command runs `bash`; on macOS, Linux and Windows with Git Bash it
works. `scripts/guard.ps1` has the same behaviour and the same lines, and is smoke-tested in PowerShell; it is not
wired. On a Windows machine without Git Bash the hook fails to start, which Claude Code treats as a non-blocking
error: there the deny rules and the skills' text remain, so the slot form of a force push or a push to the base
branch is refused by neither and the base branch's ruleset is the backstop (Risks, Left). The README says so.

**9. The skills.** The workflow skill's **Hard rules** get two sentences after the existing ones:
"Part of this is enforced: `/init`'s deny rules refuse a merge with `--admin`, deleting an issue, a board or the
repository, an API `DELETE`, a force push and a push to the base branch, and the plugin's guard hook refuses a status
edit to Ready or Approved, any merge without `--auto`, and a force push or a push to the base branch in any `git`
form. A refused command is final: report it and never try it in another form." No other skill changes; their own "never" lines stay.

The sentences name `--admin` on its own and write no command, as the skills' existing "never with `--admin`" lines do:
the joined text `gh pr merge --admin` in any `skills/*/SKILL.md` fails `tests/test-watch-checks.sh` (iteration 46,
"forces a merge or re-runs a check"), and a backticked command `gh pr merge --admin` would match R1 in this
iteration's collision lint. The same holds for every text this iteration adds to `skills/init/SKILL.md` (decision 4):
the plan sentence says "a merge with `--admin`", and the rule texts are written whole, as `Bash(gh pr merge *--admin*)`
and so on, whose joined text does not contain `gh pr merge --admin`. None of the added texts contains `gh run rerun`,
`gh run view`, `--log-failed`, `` `sleep `` or `git -C <checkout>`, so `tests/test-watch-checks.sh` stays green
unchanged.

## Criteria and rules

The issue is written in the bug form and has no "Acceptance criteria" heading. Its "What should happen" is taken as the
criteria, one numbered criterion per enforced action group, in its order; criterion 8 comes from the Evidence ("Confirm
that it still holds").

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | `/init` writes a deny rule that refuses `gh pr merge --admin` | Decisions 2, 3 (R1), 4; the hook too, decision 5.4 |
| 2 | `/init` writes deny rules that refuse `gh issue delete`, `gh project delete` and `gh repo delete` | Decisions 2, 3 (R2 to R4), 4 |
| 3 | `/init` writes deny rules that refuse `gh api -X DELETE` | Decisions 2, 3 (R5 to R8), 4 |
| 4 | `/init` writes deny rules that refuse a force push | Decisions 2, 3 (R9 to R13), 4; the slot form by the hook, decision 5.5 |
| 5 | `/init` writes deny rules that refuse a push to the base branch | Decisions 2, 3 (R14 to R18), 4; the slot form by the hook, decision 5.5 |
| 6 | The plugin ships a `PreToolUse` hook that refuses a project item edit to Ready or Approved | Decisions 5, 6, 8 |
| 7 | The hook refuses a merge without `--auto` | Decisions 5, 7, 8 |
| 8 | The finding is confirmed against the current code | Facts ("The finding still holds") |

## Tests

**`tests/smoke-guard.sh`** and **`tests/smoke-guard.ps1`**, the same cases, each against its own script, in a temporary
project with `.claude/nightmill.json` (`github.owner` `o`, `github.projectNumber` 7, default statuses) and a stub `gh`
first on the PATH (bash: an executable script; PowerShell: `gh.cmd`) that logs its arguments and, for
`project field-list`, prints `Ready<TAB>RID1` and `Approved<TAB>AID2` (or fails when the test sets a flag file). Each
case feeds one event JSON on stdin and asserts the exit code and, for a refusal, the stderr line of decision 5.7:

- Criterion 7: `gh pr merge 5 --auto --squash` 0; `gh pr merge 5 --squash` 2; `gh pr merge 5` 2;
  `gh -R o/r pr merge 5 --squash` 2; `gh pr merge 5 --disable-auto` 0; `gh api -X PUT repos/o/r/pulls/5/merge` 2;
  `gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: "x"}) { clientMutationId } }'` 2;
  `gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {pullRequestId: "x"}) { clientMutationId } }'` 0;
  `git status && gh pr merge 5 --squash` 2; `git commit -m "gh pr merge 5 --squash"` 0.
- Decision 5.3, quotes: `git commit -m "x; gh pr merge 5 --squash"` 0; `git commit -m 'a && gh pr merge 5 | b'` 0;
  `git commit -m "a \" ; gh pr merge 5"` 0; `gh pr merge 5 --squash; echo "a;b"` 2; `echo "$(gh pr merge 5 --squash)"`
  2; `tool_name` `PowerShell` with `git commit -m "x; gh pr merge 5"` 0.
- Criterion 1 (hook side): `gh pr merge 5 --auto --admin --squash` 2 with the `--admin` line.
- Criteria 4, 5 (hook side, decision 5.5), no `git.baseBranch` in the test config (default `main`):
  `git -C /w/slot-1 push --force origin feat/5-x` 2 with the force line; `git -C /w/slot-1 push -f origin feat/5-x` 2;
  `git push -uf origin feat/5-x` 2; `git -C /w/slot-1 push origin +feat/5-x` 2; `git -C /w/slot-1 push origin main`
  2 with the `main` line; `git -C /w/slot-1 push origin HEAD:refs/heads/main` 2; `git -c x=y push origin HEAD:main` 2;
  `git -C /w/slot-1 push -u origin feat/5-x` 0; `git push -u origin feat/5-main` 0; and the forms with free text:
  `git -C /w/slot-1 stash push --include-untracked -m "Unmet tests for #5: push main -f +x --force" -- t.sh` 0,
  `git stash push --include-untracked -m "Tester files for #5: push to main -f" -- t.sh` 0,
  `git -C /w/slot-1 commit -m "fix push --force to main; gh pr merge 5"` 0. With `git.baseBranch` `trunk` in the
  config: `git push origin trunk` 2, `git push origin main` 0.
- Criterion 6: `gh project item-edit --id I --project-id P --field-id F --single-select-option-id RID1` 2 naming
  Ready; the same with `AID2` 2 naming Approved; with `--single-select-option-id=AID2` 2; with `SID3` 0; with
  `--id XRID1Y --project-id AID2X --single-select-option-id SID3` 0 (ids that contain an option id);
  `gh api graphql -f query='mutation {
  updateProjectV2ItemFieldValue(input: {projectId: "P", itemId: "I", fieldId: "F", value: {singleSelectOptionId:
  "AID2"}}) { clientMutationId } }'` 2; the same with `itemId: "XAID2"` and `singleSelectOptionId: "SID3"` 0; the stub
  failing, an `item-edit` 2 with the "could not be read" line.
- Decision 5, the rest: `gh pr view 5` 0 and the stub log empty (no lookup); `tool_name` `Edit` 0; `tool_name`
  `PowerShell` with `gh pr merge 5 --squash` 2; invalid JSON 0; no `.claude/nightmill.json` and
  `gh pr merge 5 --admin` 0; the command `hooks/hooks.json` wires, run once with `CLAUDE_PLUGIN_ROOT` set to the checkout
  (bash only), 2 for `gh pr merge 5 --squash`.

Both are added to `tests/check.sh` (`add bash smoke-guard.sh`, `add ps smoke-guard.ps1`) and to the two `--only` lists
of `.github/workflows/ci.yml`.

**`tests/lint.sh`**, new section `== the guard and the deny rules`, after `== init installs the run permissions`. Each
miss prints `FAIL: <file>: <what>` and sets `fail=1`:

- Criteria 6, 7: `hooks/hooks.json` has `"PreToolUse"`, `"matcher": "Bash|PowerShell"` and the command
  `bash \"${CLAUDE_PLUGIN_ROOT}/scripts/guard.sh\"`, and no `exit 0` on that line; `scripts/guard.sh` and
  `scripts/guard.ps1` exist and each contains the seven refusal lines of decision 5.7 (the parts without placeholders)
  and `field-list`. The existing `== session-start hook is wired` and panel checks keep passing.
- Criteria 1 to 5: `skills/init/SKILL.md` has a `- **Deny rules**` bullet that contains `permissions.deny`,
  `.claude/settings.json`, each of the 18 rule texts of decision 3 written with `<B>`, `without removing or reordering
  an entry` and the declined line of decision 4.4, and no rule text that contains `git -C`; step `## 4. Confirm
  once` and step `## 5. Apply` name the deny rules.
- Decision 3, no collision, in two checks; the choice is rules that cannot match the free-text forms, and the lint
  shows it:
  1. *The prefixes.* Each of the 18 rule texts, after `Bash(`, begins with one of `gh pr merge `, `gh issue delete `,
     `gh project delete `, `gh repo delete `, `gh api `, `git push `, and has no `*` before the end of that prefix;
     otherwise `FAIL: tests/lint.sh: the deny rule <rule> has no fixed prefix`.
  2. *The commands.* The lint takes every backticked span in `skills/*/SKILL.md` and `agents/*.md` that begins (right
     after the backtick) with `git ` or `gh `, so `git -C <slot path> push ...`, `git -C <slot> stash push ...`,
     `git -C <slot path> stash push ...`, `git stash push ...` and `git -C <slot path> commit -m "<message>"` are all
     taken. A span that begins with `Bash(` is a rule text, not a command, and is not taken, so the **Deny rules**
     bullet's own rules are not checked against themselves. It splits each span into subcommands at `&&`, `||`, `;`
     and `|` outside quotes and fills the placeholders: `<slot path>`, `<slot>` and `<absolute slot path>` as
     `/w/slot-1`; a branch (`<branch>`, and `<git.featurePrefix><N>-<slug>` and the other prefix forms) as each of
     `spec/47-x`, `feat/47-x`, `fix/12-x`; `<git.mergeFlags>` as `--auto --squash`; `<git.baseBranch>` as `main`;
     `<pr>`, `<n>`, `<N>`, `<issue>`, `<k>`, `<job>` as `5`; `<owner>`, `<repo>`, `<login>` as `o`, `r`, `u`; a
     placeholder whose name ends in `id` as `I_1`; and **every other placeholder** (`<title>`, `<message>`,
     `<the paths>`, `<text>` and any added later) as the free text
     `x push main -f +x --force :main :refs/heads/main --admin -X DELETE --method DELETE x`, so a title or message
     that holds any rule's variable part is tried. Each subcommand is checked against the 18 rules with `main` for
     `<B>` (a `*` as any text, spaces included); a match is `FAIL: <file>: <command> matches the deny rule <rule>`.
     Before the scan the lint tries its matcher on `git push --force origin x` (must match R9) and on
     `git -C /w/slot-1 stash push -m "x push main -f"` (must match none); a wrong result is
     `FAIL: tests/lint.sh: the deny-rule matcher is wrong`.
- Decision 9: `skills/workflow/SKILL.md`, **Hard rules**, contains `A refused command is final` and the
  text "deny rules refuse a merge with `--admin`"; `tests/test-watch-checks.sh` is not changed and keeps passing (no
  `skills/*/SKILL.md` contains the joined text `gh pr merge --admin`).
- README: contains `### The deny rules and the guard`, `permissions.deny`, `scripts/guard.sh`, `Git Bash`, `0002`,
  and no longer contains `base branch still prompts` (the text is wrapped there; that part stands on one line).
  Iteration 43's
  README check (`### The run permissions`, `additionalDirectories`, `Run permissions`, `#110`, `#160`) stays as it is
  and keeps passing.

What the tests cannot show: that Claude Code applies the rules and the hook to a real call, in every mode and for a
subagent. That is the manual check.

**Manual check by the maintainer**, with nightmill loaded from a separate checkout of the branch
(`claude --plugin-dir <that checkout>`, started in another folder, decision 0003), in a throwaway repository with a
board, a ruleset on `main`, one Ready story with an open spec pull request and a board item at Spec:

1. `/nightmill:init`, "apply all": the plan shows **Deny rules** with the 18 rules; `.claude/settings.json` then has
   them under `permissions.deny`, the report rows `added to .claude/settings.json (18 rules)` and the guard line. A
   second run: `exists`, files unchanged.
2. In a new session, ask the agent to run each of: `gh pr merge <n> --admin --squash`, `gh issue delete <n>`,
   `gh api -X DELETE repos/<o>/<r>/labels/x`, `git push --force origin <branch>`, `git push origin main`,
   `git push origin HEAD:main`: each is refused without a prompt, naming a deny rule (criteria 1 to 5).
3. Ask it to run `gh pr merge <n> --squash` and to set the Spec item to Ready (and then Approved) with
   `gh project item-edit`: each is refused with the guard's line; setting it to Spec review works (criteria 6, 7).
   Ask it to run, in a slot, `git -C <slot path> push --force origin <branch>` and `git -C <slot path> push origin main`:
   each is refused with the guard's line (criteria 4, 5). Ask it to commit in a slot with
   `git -C <slot path> commit -m "fix push -f to main; gh pr merge 5"` and to run
   `git -C <slot path> stash push -m "push main --force" -- <a file>`: neither is refused.
4. `/nightmill:spec` on the Ready story to its pull request: no refusal; auto-merge is enabled.
5. Steps 2 and 3 again with `--permission-mode bypassPermissions` and in auto mode, and once from a subagent (ask for an
   Agent call that runs `gh pr merge <n> --squash`): the refusals still hold and the slot commit and stash still pass.
   Each result goes into "How verified".
6. On Windows with Git Bash: steps 1 to 3 once; `powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke-guard.ps1`
   green.

## Files touched

- `hooks/hooks.json`: the `PreToolUse` entry of decision 5.
- `scripts/guard.sh` (new) and `scripts/guard.ps1` (new): decision 5, with a header comment as the other scripts have.
- `skills/init/SKILL.md`: the **Deny rules** line of decisions 3 and 4 after **Permissions**; `## 4. Confirm once`
  and `## 5. Apply` name it; `## 6. Report` gets the guard line of decision 4.6; the **Run permissions** sentence
  "Refusing the forbidden actions is the deny rules' job (#110), not this line's." points to **Deny rules**.
- `skills/workflow/SKILL.md`: the two sentences of decision 9.
- `README.md`: a subsection `### The deny rules and the guard` after `### The run permissions`: the 18 rules in
  groups, why in `settings.json`, that they match the usual spelling only (`git push ...`, not the slot form
  `git -C <path> push`, which the guard judges) and the ruleset is the backstop, the guard's refusals (a status edit
  to Ready or Approved, a merge without `--auto` or with `--admin`, a force push and a push to the base branch in any
  `git` form), that it reads the option ids with `gh` when a status is edited, that it is off without
  `.claude/nightmill.json`, that it needs Git Bash on Windows (a PowerShell-only machine has the deny rules only;
  `scripts/guard.ps1` can be wired by hand in the user's hooks), that `git.mergeFlags` must contain `--auto` (decision
  7 narrows that key's contract), that a merge without `--auto` the maintainer asks of the agent is refused too, so
  the release pull request of `docs/decisions/0002`, which is merged without auto-merge, is merged by the maintainer
  (the GitHub page or the maintainer's own terminal), not by the agent, and how to take the rules back (delete them;
  the hook goes with the plugin). In the run permissions' "What it leaves out" bullet, the text
  "every push that is not `-u origin <prefix>...` (so a push to the base branch still prompts)" becomes
  "every push that is not `-u origin <prefix>...` (a force push and a push to the base branch are refused, see
  The deny rules and the guard)", and its last sentence points to the new subsection and keeps the issue number:
  "Refusing the forbidden actions outright is the deny rules and the guard (#110), not this line." The README keeps its mention of `#110`, which iteration 43's pin in `tests/lint.sh`
  (`== init installs the run permissions`, the README list) requires; that pin is not changed.
- `SECURITY.md`: "one hook" becomes "two hooks"; the scope list names the `PreToolUse` guard (`scripts/guard.*`).
- `tests/smoke-guard.sh` (new), `tests/smoke-guard.ps1` (new), `tests/lint.sh`, `tests/check.sh`,
  `.github/workflows/ci.yml`: Tests.
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 47 (#110): the harness refuses what the hard rules forbid. /init
  writes deny rules to .claude/settings.json for gh pr merge --admin, gh issue, project and repo delete, gh api DELETE,
  force pushes and pushes to the base branch, and the plugin ships a PreToolUse hook (scripts/guard.sh, twin
  guard.ps1) that refuses a board status edit to Ready or Approved, any merge without --auto, and a force push or a
  push to the base branch in any git form. git.mergeFlags must contain --auto. No config key.`
  (paths, keys and commands in backticks).

Not touched: the schema, the example config, the templates, `agents/`, the other skills and scripts, this repository's
own `.claude/settings.json` and `.claude/settings.local.json`.

## Risks

- **Other spellings.** Deny rules match the usual text only: `git -C <path> push ...`, `git -c x=y push --force`,
  `/usr/bin/git push`, `sh -c '...'`, `git push -uf ...` (combined short flags), a lower-case `-X delete`, `gh` through
  an alias or a `bash -c` wrapper are not refused by a rule. The guard refuses the `git` ones of these (decision 5.5)
  where it runs, but not `sh -c '...'`, `bash -c`, an alias, `eval` or a variable that holds the command: it splits
  outside quotes and does no other shell parsing. The base branch's ruleset (no force push, no deletion, required
  checks) is the backstop; the README says so.
- **False refusals.** No deny rule has a `git -C` form and every rule begins with a fixed prefix, so a slot path, an
  issue title or a commit message cannot make a rule match the skills' `stash push` or `commit`; the git rules'
  variable part follows a space or a colon, which a branch name cannot hold (decision 3, lint). The guard judges a
  push only when the subcommand is `push`, and splits outside quotes, so a quoted `; gh pr merge 5` or
  ` push --force main` in a message is not judged. Not covered: a title or message that breaks out of its own quotes
  (one holding `"`), which already makes the command something the skill did not mean; and a word after `git push`
  that is the value of an option the guard does not list and equals `<B>` (refused, a false refusal on the safe side).
  A segment that only quotes `gh pr merge` inside another program's argument is not judged (first word only).
- **Fail open.** A guard that crashes (exit 1), times out (30 s) or cannot start (no bash) lets the call through, as
  Claude Code treats any exit but 2. The smoke tests cover the paths; the lookup is the only network step and runs
  only for status edits.
- **A board lookup per status edit.** Each `item-edit` costs one `gh project field-list` call (well under GitHub's
  limits at a few edits per story).
- **Config edits.** An agent that renamed `board.statuses.ready` in `.claude/nightmill.json` would blind the guard;
  `.claude/` is a protected path and still prompts, and #111 is about a pull request changing that config.
- **`git.mergeFlags` without `--auto`.** Such a project's merge step is refused until the flags change; `/init`'s
  report names it.

## Size estimate

`L`: about 180 lines each in `guard.sh` and `guard.ps1`, 150 each in the two smoke tests, 45 in
`skills/init/SKILL.md`, 4 in the workflow skill, 45 in the README, 90 in `tests/lint.sh`, 12 in `hooks/hooks.json`,
10 across `check.sh`, `ci.yml`, `SECURITY.md` and `CHANGELOG.md`: about 870 changed lines in fourteen files.

## Not done

- No deny rule or hook for other deletes: `gh project item-delete`, `field-delete`, `gh label delete`, `gh release
  delete`, `git push --delete` / `git push origin :<branch>`, `git branch -D`, local file deletes ("Never delete files
  without asking" stays text). The issue names only `gh issue`, `project` and `repo delete` and `gh api -X DELETE`.
- No refusal of a bare `git push` or `git push origin` while the base branch is checked out (the target is not in the
  text); no `PowerShell(...)` deny rules (as iterations 43 and 45); no "Never close an epic" enforcement.
- No new config key, no stored option ids, no off switch for the guard, no change to `git.mergeFlags` or its schema.
- No change to the rules **Permissions**, **Edit permission** and **Run permissions** allow; no rule is removed from any
  file.
- No check of who set Approved (#177), no separate identity for the agent (#178), no sandbox or `defaultMode` (#169).

## Left

- **Option ids.** The issue's evidence says the hook needs the ids "which `/init` already reads". This spec has the
  guard read them at run time (decision 6), because storing them would be a new key and contradict the workflow skill's
  "never keep them". If the maintainer wants them written by `/init` instead, that is a config key and a story trigger.
- **`git.mergeFlags` without `--auto`.** The issue says "a merge without `--auto`", while the workflow skill lets a
  project choose `git.mergeFlags`. This spec requires `--auto` (decision 7); whether the schema should then require it
  too is for the maintainer.
- **The slot form of a push is refused by the hook, not by a deny rule.** The issue asks `/init` to write deny rules
  for a force push and a push to the base branch; this spec writes them for `git push ...` (R9 to R18) and leaves the
  slot form `git -C <path> push ...` to the guard (decisions 3, 5.5), because a `git -C * push` rule matches the
  skills' `stash push` and `commit` lines whenever a title or message holds the right words. A slot-form deny rule
  that cannot collide would have to name each absolute slot path (`git -C <R>/slot-1 push * <B> *` and so on, nine
  rules per slot), which belongs in `.claude/settings.local.json` and contradicts decision 2's "no machine path" for
  these rules; it is not written. If the maintainer wants it, it is an addition to `/init`'s **Run permissions**-style
  per-machine rules and changes decision 2.
- **The guard line in `/init`'s report** (decision 4.6) names the status and `--auto` refusals but not the push
  refusals the guard now has; it is left as it stands, as the maintainer asked.
- **PowerShell-only Windows.** With no Git Bash the wired hook does not run, so the status and `--auto` refusals are
  absent there (decision 8, as iteration 3 accepted for its hint). Wiring `guard.ps1` would need the two-entry design
  iteration 3 measured and dropped.
- **Not verified by a run:** the hook's exit 2 in `bypassPermissions` and auto mode and for a subagent's call; whether
  project deny rules apply before workspace trust; the PowerShell tool's name in the matcher; `guard.ps1` in both
  PowerShell versions (no PowerShell on the machine that wrote this; CI runs it on Windows). Manual check step 5 and CI
  settle them. Should step 5 show that a mode or a subagent escapes the hook, the implementer reports it in "How
  verified" and the iteration is `partial` for that part; nothing else in the spec changes.
