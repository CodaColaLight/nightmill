# Iteration 12: /init installs the edit permission a lights-out run needs

Status: delivered in iteration 12 (PR #58)

Story: #48, epic #47 (Unattended runs). Adds one line to the plan of `/nightmill:init`: the rule `Edit(**)` in
`permissions.allow` of the project's `.claude/settings.local.json`, so that `/spec`, `/next` and `/fix` write files
inside the project without a permission prompt. Changes `skills/init/SKILL.md` and `README.md`, adds a lint
section. No config key, no script, no change to the status flow or the slot marker: none of
`escalation.storyTriggers` applies, so the PR may auto-merge. The change is in `skills/`, so the manual check of
`verification.manualCheckPaths` applies.

## Goal

After `/nightmill:init`, a session in the project edits and writes files inside the project directory without a
prompt. The maintainer sees the exact text that will be written before the one confirmation, can decline the line,
and a second run changes nothing.

## Facts this rests on

All checked on 2026-11-05 with `claude -p` in scratch projects (Windows, Claude Code as installed here), each run
asked to write `./a.txt`, `./.claude/x.txt` and `../outside-test.txt` with the Write tool and to change `./a.txt`
with the Edit tool.

| Permission set | `./a.txt` | `./.claude/x.txt` | `../outside-test.txt` | Edit of `./a.txt` |
|---|---|---|---|---|
| `permissions.defaultMode: acceptEdits` | allowed | denied | denied | allowed |
| `permissions.allow: ["Edit(**)"]` | allowed | denied | denied | allowed |
| `permissions.allow: ["Edit(/**)"]` | allowed | denied | **allowed** | allowed |
| `permissions.allow: ["Edit"]` | denied | denied | denied | denied |

- One `Edit(**)` rule covers the Write tool as well as the Edit tool. It is relative to the directory of the
  session, so it does not reach a path outside it.
- `Edit(/**)` is **not** scoped to the project on this platform: it let a file be written next to the project. The
  spelling `Edit(**)` is the one to write, and the lint rejects the other.
- A bare `Edit` rule did not allow anything in that run, so it is not used.
- Under every spelling a write inside `.claude/` is still denied (a protected directory); `.git/` was not tested. `/spec`,
  `/next` and `/fix` do not write there; `/init` writes `.claude/nightmill.json` and `.claude/settings*.json` in its
  own confirmed apply step, as before.
- A project's `permissions.allow` is ignored by `claude -p` until the workspace is trusted (the message names the
  file and the trust dialog). `defaultMode` was not ignored. So a headless run needs one interactive session in the
  project, where the trust dialog is accepted, before the rule takes effect.
- Today `/init` writes `Bash(gh ...)`, three read-only `git` rules and one rule for the check command to
  `permissions.allow` of `.claude/settings.json`, merging into the array without removing or reordering an entry
  (`skills/init/SKILL.md`, "Permissions"), and a rule already present is **exists**. This repository's own
  `.claude/settings.json` allows only `Write(docs/specs/**)`.
- `/next` and `/fix` work in a slot, a worktree under `worktrees.root` (`../<repo>-wt` by default), which is
  **outside** the project directory. `Edit(**)` does not cover it (the third column above). The story puts paths
  outside the project directory out of scope; see "Not done".

## Decisions

**1. A path rule, not `defaultMode: acceptEdits`.** The two behaved the same in every case tested. The rule is
chosen because it is one more entry in an array that `/init` already merges without touching what is there, and
the "exists" check is a string match. `defaultMode` is a single value that may already hold another one (`plan`,
`default`), so writing it would either overwrite the project's choice or need a conflict rule, and it changes the
mode of every session in the project, not only the permission to edit.

**2. `.claude/settings.local.json`, not `.claude/settings.json`.** Letting an unattended run edit files is a
choice of the person who runs it, not of everyone who clones the repository: in the committed file the rule would
also silence the prompts of every collaborator's interactive session. The local file is personal and not
committed. The Bash rules that `/init` writes today stay in `.claude/settings.json`, unchanged.
Consequence: a second machine, or a fresh clone, has no local file, so on it the line is an **add**, not
**exists**; one `/init` run, one confirmation.

## What `/init` does

A new line in the plan, **Edit permission**, after **Permissions** and before **Board workflows**.

1. **Detect.** The line is **exists** when `Edit(**)` is in `permissions.allow` of `.claude/settings.local.json` or
   of `.claude/settings.json`, or when `permissions.defaultMode` is `acceptEdits` or `bypassPermissions` in either
   file (the project already covers it; the plan names which). Otherwise it is an **add**.
2. **Show the exact text** in the plan message, next to the CLAUDE.md and settings texts, before the one question:
   - file missing: the whole file that will be created, `{ "permissions": { "allow": [ "Edit(**)" ] } }` written with
     2-space indentation, LF endings;
   - file present: the diff, one added line `"Edit(**)"` at the end of `permissions.allow` (the array is created
     when the file has none), every other byte of the file unchanged.
   The plan line also says, in one sentence, what is granted (file edits and writes inside the project directory,
   not Bash, not other directories) and that `.claude/` still prompts.
3. **Git.** When `.claude/settings.local.json` is not ignored by git (`git check-ignore -q` fails) the plan says so
   on the line: "not ignored by git; add it to .gitignore, it is personal". `/init` does not edit `.gitignore`.
4. **Apply** with the other settings changes: merge into the existing array without removing or reordering an
   entry (the same rule as **Permissions**), create the file as `{}` plus the array when missing. Read the file
   back; a line whose read-back does not show `Edit(**)` is **failed**, with the reason.
5. **Declined.** A line the user skips is **declined**: neither settings file is touched, and the report says
   `Edit permission: declined (edits will prompt)`. It is not asked again in this run.
6. **Report row**, one of: `added to .claude/settings.local.json`, `exists (<file or defaultMode>)`, `declined`,
   `failed: <reason>`. After an add the report also says that the slots under `worktrees.root` are outside the
   project directory and still prompt, and that a headless run needs the workspace trusted once.

The plan stays one table with one question; "apply all, or name the lines to skip" now covers one more line.
When every line is **exists**, nothing is asked (unchanged).

## README

- The sentence "Hooks, permissions and environment variables stay in the project's own `.claude/settings.json`; a
  plugin cannot set them" gets `.claude/settings.local.json` named beside it.
- In the `/nightmill:init` paragraph, "the permission rules in `.claude/settings.json`" becomes "the permission
  rules in `.claude/settings.json` and the edit permission in `.claude/settings.local.json`".
- A short subsection "The edit permission" under it: what `Edit(**)` grants (edits and writes inside the project
  directory, which is what `/spec`, `/next` and `/fix` do; not Bash, not other directories; `.claude/`
  still prompts), where it is written (`.claude/settings.local.json`, personal, not committed) and why not in the
  committed file, how to take it back (delete the line), that the slots under `worktrees.root` are outside the
  project directory and not covered, and that a project's allow rules apply only after the workspace is trusted.

## Tests

`/init` is a conversation, not a script: what it does with the file is done by the model following the skill. So the
lint pins the wording the behaviour depends on, and the manual check below does the behaviour, one scenario per
acceptance criterion of #48.

**`tests/lint.sh`**, new section "== init installs the edit permission":

- `skills/init/SKILL.md` has the plan line **Edit permission**, names `Edit(**)` and `.claude/settings.local.json`,
  says `git check-ignore`, and has the report wordings `declined (edits will prompt)` and `exists`;
- it says the text is shown before the single confirmation (the "Confirm once" step names
  `.claude/settings.local.json` next to the CLAUDE.md and `settings.json` edits);
- it says the entries of an existing file are not removed or reordered, in the edit-permission line itself;
- neither `skills/init/SKILL.md` nor `README.md` contains `Edit(/**)` (the spelling that left the project);
- `README.md` contains `Edit(**)`, `.claude/settings.local.json` and the heading `The edit permission`.

`bash tests/check.sh` stays green.

## Verification

The change touches `skills`, so the manual check applies: run `/nightmill:init` in a real project with
`claude --plugin-dir <checkout>`. The project is a clone whose workspace is trusted. Scenarios:

1. **The plan shows the text.** The plan has the line **Edit permission** and, in the same message and before the
   question, the file text (or the diff for an existing local file).
2. **No prompt for an edit.** Answer "apply all". In a new session in the project, ask for an edit and a new file
   inside the project (for example run `/spec` on a Ready story): no permission prompt appears. A write under
   `.claude/` still prompts.
3. **Decline.** Run again on a clean clone and skip the line: neither settings file changes (`git status` and a
   file hash before and after), and the report says `declined (edits will prompt)`.
4. **Re-run.** Run `/init` on the project from scenario 2: nothing is asked, nothing changes, the line says
   `exists (.claude/settings.local.json)`.
5. **Nothing removed or reordered.** Start from a `.claude/settings.local.json` with `allow` holding three
   entries in a known order and a `deny` array: after "apply all" the three entries keep their order, `Edit(**)` is
   last, and `deny` is unchanged.
6. **Covered by a mode.** With `permissions.defaultMode: "acceptEdits"` in the local file the line is `exists
   (defaultMode acceptEdits)` and nothing is written.

The PR's "How verified" lists the six results and the check.

## Not done

- **Slots are not covered.** `/next` and `/fix` edit in a slot under `worktrees.root`, outside the project directory,
  and their edits still prompt after this story. Covering them (for example `permissions.additionalDirectories` for
  `worktrees.root`) is a path outside the project directory, which the story rules out. It is the next story to file
  for the unattended-runs epic; without it a fully unattended `/next` is not reached.
- No Bash rule beyond the ones `/init` already writes; no rule for a path outside the project directory.
- No edit of `.gitignore`; `/init` only says when the local file is not ignored.
- No change to `defaultMode`, to the deny or ask lists, or to any entry already in a settings file.
- No change to the committed `.claude/settings.json` rules, and none to this repository's own settings.
- No script, no new config key, no change to the status flow.
