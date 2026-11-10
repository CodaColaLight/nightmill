# Iteration 48: the skills and the slot script read the config from the base branch, git.mergeFlags must hold --auto and never --admin, and a change under .claude/ or .github/ is never auto-merged

Status: draft, awaiting approval (#111)

Story #111, no epic (it comes from the code review of 0.2.0, finding HI-3, like the stories of epic #107; the issue
was filed as a bug and relabelled story on 2026-11-10, its title still starts `[Bug]`). Today every skill injects
`.claude/nightmill.json` from the working tree of the session's checkout, and `scripts/slot.sh` / `slot.ps1` read the
main checkout's working-tree file and run its `worktrees.warmup[].command` at the next take, so a branch that changes
the config governs the run that works on it. After this iteration the run's configuration is the one on the base
branch (`origin/HEAD`, then `git.baseBranch`), read with `git show`, and the working tree's file is used only when the
repository has no remote-tracking branch or the base branch has no config yet. The schema gives `git.mergeFlags` a
`pattern` (the word `--auto`) and a `not` (no word `--admin`), the validator learns both keywords, and the skills'
merge step checks the same before it runs. Auto-merge is withheld for a pull request that changes a path under
`.claude/` or `.github/`, and a check fix round that would add one is not pushed. Changes `schema/nightmill.schema.json`,
`scripts/lib/validate.awk`, `scripts/validate-config.sh`, `scripts/validate-config.ps1`, `scripts/lib/baseconfig.sh`
(new), `scripts/lib/baseconfig.ps1` (new), `scripts/slot.sh`, `scripts/slot.ps1`, `skills/workflow/SKILL.md`,
`skills/spec/SKILL.md`, `skills/next/SKILL.md`, `skills/fix/SKILL.md`, `skills/story/SKILL.md`,
`skills/check/SKILL.md`, `README.md`, `tests/smoke-slot.sh`, `tests/smoke-slot.ps1`, `tests/smoke-validate.sh`,
`tests/smoke-validate.ps1`, `tests/test-skill-config-fallback.sh`, `tests/lint.sh` and `CHANGELOG.md`.

## Story trigger and manual check

**Not a story trigger** (it is a story anyway). Of `escalation.storyTriggers`:

- *A change to the status flow or who sets a status*: no. No status, no board call and no actor changes; withholding
  auto-merge is an existing outcome of the Review step ("Do not, and say why in the PR"), given two more cases. No
  decision record. None of `docs/decisions/` 0001 to 0003 is contradicted: the release pull request of 0002 changes
  `.claude-plugin/`, not `.claude/` (decision 6 matches the prefix with its slash), and is merged by the maintainer
  anyway (iteration 47 decision 7).
- *A new, renamed or removed config key*: no. `git.mergeFlags` keeps its name, type and default and gains a
  `pattern`, a `not` and a description; the issue says "A `pattern` on an existing key is not a new key". No key is
  added for the base ref or for the two directories: `origin/HEAD` is git's, and `.claude/` and `.github/` are the
  fixed directories of Claude Code and GitHub, not project values (invariant "Config-driven" holds). Invariant
  "Compatible": the config file is read by the previous version as before, slot markers, `capacity.json` and the
  ledger are written as before. A config the previous version accepted with `git.mergeFlags` lacking `--auto` or
  holding `--admin` is now an error of the validator; iteration 47's guard already refuses its merge step.
- *A change to the slot marker format*: no. `slot.sh` and `slot.ps1` change where they read the config, not what they
  write.

**The manual check applies**: `skills` is in `verification.manualCheckPaths` (workflow, spec, next, fix, story, check
change). No agent and no hook changes. Its steps are under Tests.

**Both shells** (an invariant of the project, not ticked in the issue): every script change is made in both twins with
the same behaviour and the same lines: `scripts/lib/baseconfig.sh` and `scripts/lib/baseconfig.ps1` (new),
`scripts/slot.sh` and `slot.ps1`, `scripts/validate-config.sh` (with `lib/validate.awk`) and `validate-config.ps1`;
each with smoke steps in `tests/smoke-slot.*` and `tests/smoke-validate.*`. The machine that wrote this has no
PowerShell; CI's Windows job runs the `.ps1` smoke tests. The skills' config injection runs in the Bash tool (Git Bash on
Windows), as the `cat` injection of #127 does today; it has no PowerShell form.

## Facts this rests on

Read on `main` at cb53cae (iterations 39 and 47 merged), read only; nothing was run against the board or GitHub.

**The finding still holds**, part by part:

- `schema/nightmill.schema.json`: `"mergeFlags": { "type": "string", "default": "--auto --squash" }`, no description,
  no constraint. `scripts/lib/validate.awk` and `validate-config.ps1` support `type`, `properties`, `required`,
  `items`, `minimum`, `minItems`, `additionalProperties` and `enum`; `tests/lint.sh`, section
  `== schema keywords are supported`, fails on `pattern` and `not` among others, and `tests/smoke-validate.sh` / `.ps1`
  prove that lint by adding `"pattern": "x"` to a schema copy.
- Every skill but `/init` injects `` !`cat .claude/nightmill.json 2>/dev/null || echo "NO CONFIG: run /nightmill:init first"` ``
  (workflow, spec, next, fix, story, check; the fallback of #127), which the harness runs in the session's
  directory. The pairing check of `/spec`, `/next` and `/fix` validates `<project>/.claude/nightmill.json`. The
  workflow skill reads `review.watchChecksMinutes` "from `.claude/nightmill.json` when it starts".
- `scripts/slot.sh` reads `$main/.claude/nightmill.json` (the main checkout's working tree, `main` the parent of the
  common git dir) before any mode, takes `git.baseBranch` from it, and at `--take` runs each
  `worktrees.warmup[].command` with `bash -c`; `slot.ps1` reads `Join-Path $main ".claude\nightmill.json"` and runs
  `Invoke-Expression $w.command`.
- The workflow skill's **CI and merging** withholds auto-merge for a story trigger, a partial change, a skipped manual
  check, an open blocking finding or the maintainer's wish; no case looks at the paths a pull request changes.
  `escalation.storyTriggers` names a new, renamed or removed key, not a changed value.
- What iteration 47 already refuses at run time: the guard refuses any `gh pr merge` without the word `--auto` and any
  with `--admin`, and deny rule R1 `Bash(gh pr merge *--admin*)` refuses `--admin`. So a `git.mergeFlags` of
  `--admin --squash` no longer merges past the checks, as the maintainer's comment of 2026-11-10 says; the schema, the
  validator and the skills' own check are what is left of that part. The guard itself still reads the working-tree
  config (`$CLAUDE_PROJECT_DIR/.claude/nightmill.json`), as iteration 47's Risks note.
- In this repository `git symbolic-ref -q --short refs/remotes/origin/HEAD` prints `origin/main`, and
  `git show origin/HEAD:.claude/nightmill.json` prints the config. `tests/smoke-slot.sh` builds its origin with
  `git remote add` and `git push`, so its repository has no `origin/HEAD`, and its `write_cfg` changes the working-tree
  file only.
- Tried on this machine (macOS awk 20200816, `LC_ALL=C`): the pattern `^(.* )?--auto( .*)?$` matches `--auto --squash`,
  `--squash --auto`, `--auto`, and not `--squash`, `--autox --squash`, `x--auto`, nor `--auto<TAB>--squash`; the pattern
  `^(.* )?--admin(( |=).*)?$` matches `--auto --admin`, `--admin=true --auto`, `--squash --admin`, and not
  `--administrator --auto` or `--auto --squash`. Both use only syntax that ECMA-262 (JSON Schema, editors), POSIX ERE
  (awk) and .NET (PowerShell) read the same way.

## Decisions

**1. The base configuration, one rule for the skills and the scripts.** `<C>` is `.claude/nightmill.json`.

1. **The base ref.** When `refs/remotes/origin/HEAD` exists (`git symbolic-ref -q --short refs/remotes/origin/HEAD`
   prints `origin/<X>`), the base ref is `origin/HEAD`. `origin/HEAD` is local repository state set by a clone or by
   `git remote set-head`; no pull request can change it.
2. **No `origin/HEAD`.** When the repository has a remote-tracking branch of `origin`
   (`git for-each-ref --count=1 refs/remotes/origin` prints a line) but no `origin/HEAD`, stop:
   `origin/HEAD is not set, so the base branch's configuration cannot be found; run git remote set-head origin --auto once`.
   Taking `git.baseBranch` from the working tree instead would let a branch name its own base (Risks, Left).
   When there is no remote-tracking branch at all (no `origin`, never fetched: the offline case of the issue), use the
   working tree's `<C>` and say `nightmill: no branch of origin is known; the configuration is read from the working tree.`
3. **The read.** `git show origin/HEAD:<C>`. It reads the last fetched state and needs no network. When it fails
   because the file is not on that branch (a project whose `/init` pull request has not merged yet), use the working
   tree's `<C>` and say `nightmill: origin/HEAD has no .claude/nightmill.json; the configuration is read from the working tree.`
   Text that is not valid JSON stops: `the configuration on <ref> is not valid JSON: <the parser's message>`.
4. **The base branch.** `<B>` is `git.baseBranch` of the configuration read in step 3 (default `main`). When the base
   ref is `origin/HEAD` and `<X>` is not `<B>`, the configuration is `git show origin/<B>:<C>` instead; when that fails,
   stop: `origin/<B> has no .claude/nightmill.json (git.baseBranch of the configuration on origin/HEAD)`. No further
   step: `git.baseBranch` of that second file is not followed.
5. **No fetch** is added. A configuration change takes effect once it is on `origin/<B>` in this repository: after it
   merged and was fetched (every take fetches the base branch; a push of the base branch updates it too). An edit
   that is not committed, or committed on another branch, no longer governs a run.

The lines in steps 2 to 4 are the same in every place; a script prints them on standard error, a skill prints them once
per run. A stop in a skill is `Stopped: <the line>. Nothing was changed.`; in `slot.*` exit 1, in `validate-config.*`
`--base` exit 2.

**2. The skills' injection.** In workflow, spec, next, fix, story and check, the block

```
Project configuration (`.claude/nightmill.json`):

!`cat .claude/nightmill.json 2>/dev/null || echo "NO CONFIG: run /nightmill:init first"`
```

becomes

```
Project configuration on the base branch (`origin/HEAD:.claude/nightmill.json`; the first line names the base ref; see **The configuration** in the `workflow` skill):

!`git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || git for-each-ref --count=1 --format="NO origin/HEAD, but %(refname)" refs/remotes/origin; git show origin/HEAD:.claude/nightmill.json 2>/dev/null || echo "NO BASE CONFIG: read .claude/nightmill.json of the working tree (cat .claude/nightmill.json); without it, run /nightmill:init first"`
```

(in the workflow skill "see **The configuration** below"). Its output is one of: `origin/<X>` and the configuration
(step 3); `NO origin/HEAD, but refs/remotes/origin/...` and the `NO BASE CONFIG` line (step 2, stop); only the
`NO BASE CONFIG` line (step 2, no remote branch, or step 3, no file: the working tree). Outside a git repository it
prints the `NO BASE CONFIG` line and exits 0, so the `/nightmill:init` hint of #127 stays. `allowed-tools` of each of
the six skills becomes exactly
`Bash(git symbolic-ref -q --short refs/remotes/origin/HEAD *), Bash(git for-each-ref --count=1 *), Bash(git show origin/*:.claude/nightmill.json *), Bash(echo "NO BASE CONFIG*"), Bash(cat .claude/nightmill.json *)`
(the last one for the working-tree read the fallback asks for; `Bash(echo "NO CONFIG* run /nightmill:init first")`
goes, as no injection runs it). `/init` keeps its `cat` injection: it creates and edits the working tree's file.

**3. The workflow skill's rule.** A paragraph **The configuration** directly after the paragraph under the injection
(before `## What lives where`), in substance: the configuration that governs a run is the base configuration of
decision 1, shown above; a skill never takes a value from the working tree's file except in the fallbacks of steps 2
and 3, and then says the fallback's line once. It names step 4 with its command
`git show origin/<git.baseBranch>:.claude/nightmill.json` and the stop lines, and step 5 in one sentence. Where a
skill reads the config again, it reads this one: **Watching the checks** "read from `.claude/nightmill.json` when it
starts" becomes "read from the run's configuration (**The configuration**) when it starts". The data rule is not
changed: the base configuration is the project's, not text from an issue or a pull request.

**4. The pairing check validates the base configuration.** `validate-config.sh` gets `--base` and
`validate-config.ps1` `-Base`: the configuration of decision 1, resolved from the current directory's repository,
instead of a file. With a config argument (`--base <file>`, `-Base -Config <file>`) it is a usage error (exit 2). It
prints `validating <ref>:.claude/nightmill.json against <schema>` (`origin/HEAD` or `origin/<B>`), or, after a
fallback, the fallback's line on standard error and `validating <path> against <schema>`; the stops exit 2 with their
line. Findings, summary and exit codes as today. `/spec` "The spec review" step 1, `/next` and `/fix` "The pairing"
pass `--base` / `-Base` instead of `<project>/.claude/nightmill.json`; the rest of those steps is unchanged (exit 2 is
"the pairing could not be checked"). `/init` still validates the file it writes, without `--base`.

**5. `git.mergeFlags` must contain `--auto` and never `--admin`.**

- *Schema*: `"mergeFlags": { "type": "string", "default": "--auto --squash", "pattern": "^(.* )?--auto( .*)?$", "not": { "pattern": "^(.* )?--admin(( |=).*)?$" }, "description": "The flags of the skills' merge step, gh pr merge <pr> <mergeFlags>. Must contain the word --auto and never --admin, words separated by single spaces: auto-merge waits for the required checks, the admin bypass would not. The guard hook refuses a merge without --auto or with --admin." }`.
  Words are separated by spaces; a tab between words fails the pattern (stricter than the guard, on the safe side).
- *Validator*: two keywords, the same in both shells. `pattern` (a string): a string value that does not match it is
  `error: <path>: must match the pattern <pattern>, got <value as JSON text>`. `not`: supported only as an object
  whose one key is `pattern`; a string value that matches that pattern is
  `error: <path>: must not match the pattern <pattern>, got <value as JSON text>`. A value that is not a string is not
  judged by either (the `type` error comes first). The match is a search, case-sensitive: awk `~` under `LC_ALL=C`,
  PowerShell `-cmatch`. For `--squash`: `error: git.mergeFlags: must match the pattern ^(.* )?--auto( .*)?$, got "--squash"`.
- *Lint* (`== schema keywords are supported`): `pattern` and `not` leave the forbidden list; the lint fails when a
  `not` in the schema has any key but `pattern`, and when a schema `pattern` holds a character outside letters, digits,
  space and `-=_.*()?|^$` (no backslash, no class: the three regex flavours of the Facts read those the same way).
  The smoke tests' proof of that lint uses `"format": "x"` instead of `"pattern": "x"`.
- *Skills*: the merge step of `/spec` (step 4), `/next` (step 7) and `/fix` (step 6, one bug and `/fix all`) runs
  `gh pr merge <pr> <git.mergeFlags>` only when `git.mergeFlags`, split at spaces, has a word `--auto` and no word that
  is `--admin` or starts with `--admin=`; otherwise it withholds auto-merge with
  `Auto-merge is not enabled: git.mergeFlags is "<value>"; it must contain --auto and never --admin.` The text says
  `--admin` alone, never joined to `gh pr merge` (iteration 47 decision 9, `tests/test-watch-checks.sh`).

**6. A change under `.claude/` or `.github/` is never auto-merged.** Two new withholding cases in **CI and merging**,
and their steps in the skills:

1. **At the merge step**, before `gh pr merge`, the skill lists the paths the pull request changes:
   `git -C <slot path> diff --name-only --no-renames origin/<git.baseBranch>...<branch>` in a slot,
   `git diff --name-only --no-renames origin/<git.baseBranch>...<branch>` in the session's checkout (`/spec`). Three
   dots: the change since the merge base, which is what the pull request adds after the rebase the workflow already
   asks for; `--no-renames` lists both the old and the new path of a move. A path that starts with `.claude/` or
   `.github/` (the slash included, so `.claude-plugin/` does not count) withholds auto-merge with
   `Auto-merge is not enabled: it changes <the first such path>, under .claude/ or .github/, which is never auto-merged.`
   A `git diff` that fails withholds it too:
   `Auto-merge is not enabled: the changed paths could not be listed (<the first line of git's message>).`
2. **In a check fix round** (iteration 46, **Watching the checks**), after the review of step 4 and before the push of
   step 5: `git -C <slot path> diff --name-only --no-renames <the pull request's head>..HEAD` (in `/spec`
   `git diff --name-only --no-renames <the pull request's head>`, the uncommitted spec file). A path under `.claude/`
   or `.github/` is not pushed: the hand-over with the reason
   `the fix of round <k> changes <path>, under .claude/ or .github/, which is never auto-merged`. Nothing new is
   posted on the pull request; iteration 46's "only pull request comment of the watch" stays.

The line of case 1 goes where each skill already says why auto-merge was withheld (the pull request body at creation).
A resumed run that reuses an open pull request (`/spec` rows S1 and R1, `/next` row N1, which already skip the step
when the body has `Auto-merge is not enabled`) runs the same checks of decisions 5 and 6.1 before enabling it; when
one applies it does not enable auto-merge, prints the line and posts it once with `gh pr comment <pr> --body "<the line>"`
(only when no comment of the maintainer's login on the pull request starts with `Auto-merge is not enabled:`), and the
body is not rewritten. A spec pull request changes only its spec file, so case 1 never applies to a normal `/spec` run;
the check runs all the same.

**7. The slot script reads the base configuration.** `scripts/lib/baseconfig.sh` defines one function that runs
decision 1 for the repository whose main checkout is `$main` (`git -C "$main" ...`) and leaves the configuration in a
temporary file made with `mktemp "${TMPDIR:-/tmp}/nightmill-baseconfig.XXXXXX"` (removed by the caller), the ref or
path it came from, and the fallback or stop line; `scripts/lib/baseconfig.ps1` the same as a function that returns the
text. PowerShell decodes `git`'s output as UTF-8 (sets `[Console]::OutputEncoding` to UTF-8 for the call and restores
it) and removes a leading BOM as its other JSON readers do, so a non-ASCII value (the em dash in this repository's
`invariants`) survives. `slot.sh` and `slot.ps1` call it before any mode, where they read `$main/.claude/nightmill.json`
today; every key they use (`git.baseBranch`, `worktrees.*`, `parallel.maxAgents`, `worktrees.warmup`) comes from it.
The existing message `no <path> (run /nightmill:init)` stays for a fallback with no working-tree file. The take's fetch,
warm-up and marker are unchanged. `validate-config.*` `--base` (decision 4) uses the same function.

## Criteria and rules

The issue is written in the bug form and has no "Acceptance criteria" heading. Its "What should happen" is taken as the
criteria, one numbered criterion per requirement, in its order; criterion 4 comes from the Evidence ("Confirm that it
still holds when the fix is specified"), as iteration 47 did.

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | `git.mergeFlags` must contain `--auto` and never `--admin` (schema pattern, validator and skills) | Decision 5; at run time already iteration 47 (Facts) |
| 2 | The skills read the config from the base branch, not from the branch being changed | Decisions 1, 2, 3, 4, 7 |
| 3 | A change under `.claude/` or `.github/` is never auto-merged | Decision 6 |
| 4 | The finding still holds when the fix is specified | Facts ("The finding still holds") |

## Tests

**`tests/smoke-validate.sh`** and **`tests/smoke-validate.ps1`**, the same cases, each against its own validator:

- Criterion 1: the example (`--auto --squash`) is clean; `git.mergeFlags` `--squash` exit 1 with
  `error: git.mergeFlags: must match the pattern ^(.* )?--auto( .*)?$, got "--squash"`; `--auto --admin --squash` exit 1
  with `error: git.mergeFlags: must not match the pattern ^(.* )?--admin(( |=).*)?$, got "--auto --admin --squash"`;
  `--admin --squash` both lines, `2 errors, 0 warnings`; `--squash --auto` and `--auto --administrator` clean;
  `--admin=true --auto` the `not` line; `git.mergeFlags` `3` only `expected string, got integer`.
- Decision 5, the keywords on their own: a schema of the test's own with `{"type": "string", "pattern": "^a"}` and a
  value `b` gives the `must match` line; `{"not": {"pattern": "b$"}}` with `ab` the `must not match` line.
- Decision 4: in a temporary repository with a bare origin, `git remote set-head origin main`, a pushed config with
  `--squash` and a working-tree config with `--auto --squash`: `--base` (`-Base`) exit 1 with the `must match` line and
  the header `validating origin/HEAD:.claude/nightmill.json against ...`; the file argument on the working tree exit 0;
  `--base <file>` exit 2; without `origin/HEAD` but with `origin/main` exit 2 with the set-head line.
- The lint proof of an unsupported keyword uses `"format": "x"`.

**`tests/smoke-slot.sh`** and **`tests/smoke-slot.ps1`**: the test repository gets `git remote set-head origin main`
after its first push, and `write_cfg` (and every other step that edits the config) commits the file and pushes it to
`origin main`, so the existing cases run on the base configuration. New cases, criterion 2:

- **The warm-up comes from the base.** The working tree's config, changed and not committed, has the warm-up
  `echo evil > evil.txt`; a take runs the pushed warm-up (`warmed.txt` written) and writes no `evil.txt`.
- **The base branch hop.** `origin/HEAD` names `main`, whose config says `git.baseBranch` `trunk`; `origin/trunk` has a
  config whose warm-up writes `trunk.txt`: a take writes `trunk.txt`. With `git.baseBranch` `nope` (no `origin/nope`):
  exit 1 with the `origin/nope has no .claude/nightmill.json ...` line.
- **No `origin/HEAD`**: after `git remote set-head origin --delete`, `--status` exits 1 with the set-head line.
- **Offline**: a repository with no remote: `--status` works from the working-tree file and prints the
  `no branch of origin is known` line on standard error.
- **No file on the base**: `origin/HEAD` without `.claude/nightmill.json`: the working-tree file and the
  `origin/HEAD has no .claude/nightmill.json` line.
- **UTF-8** (PowerShell in particular): a base config whose `invariants` hold an em dash: `--status` works.

**`tests/test-skill-config-fallback.sh`** (criterion 2, #127 kept): for spec, next, fix, story, check and now workflow,
the first injection line that names `nightmill.json` is run with `bash -c`: in an empty directory (no git) exit 0 and
the output names `/nightmill:init`; in a repository whose `origin/HEAD` has a config with a marker and whose working
tree has a config with another marker, exit 0, the first line `origin/main`, the base marker printed and the working
tree's marker not; in a repository with `origin/main` and no `origin/HEAD`, the output has `NO origin/HEAD, but`. The
`allowed-tools` coverage check stays and covers the new parts.

**`tests/lint.sh`**, new section `== the config comes from the base branch`, after `== the guard and the deny rules`.
Each miss prints `FAIL: <file>: <what>` and sets `fail=1`:

- Criterion 1: the schema's `git.mergeFlags` has exactly the `pattern`, the `not` and a non-empty description of
  decision 5, and its default passes both (run through `validate-config.sh` on the example, which the lint already
  does). Decision 5's lint rules in `== schema keywords are supported`. The workflow skill's **CI and merging** and the
  merge steps of `skills/spec`, `next` and `fix` contain `it must contain --auto and never --admin`.
- Criterion 2: each of the six skills has the injection line of decision 2 exactly and the `allowed-tools` of decision
  2 exactly, and no line `` !`cat .claude/nightmill.json `` (`/init` excepted); the workflow skill has
  `**The configuration**`, `git remote set-head origin --auto` and `git show origin/<git.baseBranch>:.claude/nightmill.json`,
  and no longer `read from \`.claude/nightmill.json\` when it starts`; the pairing steps of spec, next and fix
  contain `validate-config.sh" --base` and `validate-config.ps1" -Base`; `scripts/slot.sh` and `slot.ps1` source
  `lib/baseconfig` and no longer contain `.claude/nightmill.json"` / `".claude\nightmill.json"` as their config path.
- Criterion 3: the workflow skill's **CI and merging** contains `--no-renames`, `.claude/` and `.github/` and the two
  lines of decision 6; `skills/spec`, `next` and `fix` contain `which is never auto-merged`.
- README: the Security model table's rows of "Files touched" are there; `tests/test-security-model.sh` stays as it is
  and keeps passing (#111 is still in a row).

What the tests cannot show: that the model uses the injected base configuration and the withholding rules in a real
run. That is the manual check.

**Manual check by the maintainer**, with nightmill loaded from a separate checkout of the branch
(`claude --plugin-dir <that checkout>`, started in another folder, decision 0003), in a throwaway repository with a
board, one Approved story and its spec on `main`:

1. Check out a branch `feat/x` in the main checkout, set `git.mergeFlags` to `--admin --squash` and the warm-up to
   `echo evil > evil.txt` in its `.claude/nightmill.json`, without committing. Run `/nightmill:next`: the take runs the
   base warm-up (no `evil.txt` in the slot), and the pull request is opened with `<base mergeFlags>`; nothing from the
   working tree is used (criterion 2).
2. Run `bash <checkout>/scripts/validate-config.sh .claude/nightmill.json` on that file: two errors (criterion 1).
3. A story whose change adds a file under `.github/`: its pull request says
   `Auto-merge is not enabled: it changes .github/..., under .claude/ or .github/, which is never auto-merged.` and has
   no auto-merge (criterion 3).
4. `git remote set-head origin --delete`, then `/nightmill:spec`: it stops with the set-head line; after
   `git remote set-head origin --auto` it runs.
5. On Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke-slot.ps1` and `tests/smoke-validate.ps1`
   green, and step 1 once. Each result goes into "How verified".

## Files touched

- `schema/nightmill.schema.json`: `git.mergeFlags` as decision 5.
- `scripts/lib/validate.awk`, `scripts/validate-config.sh`, `scripts/validate-config.ps1`: `pattern` and `not`
  (decision 5), `--base` / `-Base` (decision 4); the header comments' keyword lists and usage lines.
- `scripts/lib/baseconfig.sh` (new), `scripts/lib/baseconfig.ps1` (new): decisions 1 and 7, with a header comment.
- `scripts/slot.sh`, `scripts/slot.ps1`: decision 7; the header line "Configuration comes from .claude/nightmill.json in
  the main checkout" names the base branch.
- `skills/workflow/SKILL.md`: the injection and `allowed-tools` (decision 2), **The configuration** (decision 3), the
  watch's sentence (decision 3), and in **CI and merging** the cases of decisions 5 and 6 after "or the maintainer asked
  to review it", and the round check of decision 6.2 in the check fix round's step list.
- `skills/spec/SKILL.md`, `skills/next/SKILL.md`, `skills/fix/SKILL.md`: the injection and `allowed-tools`, the pairing
  with `--base`, the merge step's two checks (decisions 5, 6.1), the resumed rows' sentence (decision 6), and the
  round check in their check fix round paragraph (decision 6.2).
- `skills/story/SKILL.md`, `skills/check/SKILL.md`: the injection and `allowed-tools` only.
- `README.md`: `## Configuration` gets, after its first sentence, one paragraph: the skills and the slot script read the
  file from the base branch (`origin/HEAD`, then `git.baseBranch`), a change takes effect once merged and fetched, the
  working tree's file only without a remote branch or before the base has one, and `git remote set-head origin --auto`
  when `origin/HEAD` is missing. The table's `git` row: "Base branch, branch prefixes, merge flags (with `--auto`,
  never `--admin`)". In `### Who can influence it` the bullet "The files in the repository" says that a pull request's
  change to `.claude/nightmill.json` no longer governs a run before it merges and that a change under `.claude/` or
  `.github/` is not auto-merged; the specs, decisions, `CLAUDE.md` and the code the check runs still can steer it. In
  `### What is enforced` the row of #111 is replaced by four rows:
  - `` `git.mergeFlags` contains `--auto` and never `--admin` `` | `enforced by the schema and scripts/validate-config.*, and at run time by the guard hook, where it runs` (paths in backticks) | `[#111](...), [#110](...)`
  - `The skills, the slot script's warm-up and the pairing check use the config on the base branch, not the working tree` | `enforced by the skills' config injection, scripts/slot.* and scripts/validate-config.* --base; the working tree's file only without a remote branch or before the base has one` | `[#111](...)`
  - `` A change under `.claude/` or `.github/` is not auto-merged `` | `enforced by tests/lint.sh for the skills' text only; no mechanism checks it at run time` | `[#111](...)`
  - `The guard hook and the other scripts (status, room, control, models, the dashboard and the pane) read the config from the base branch` | `not enforced yet` | `none filed`
- `tests/smoke-validate.sh`, `tests/smoke-validate.ps1`, `tests/smoke-slot.sh`, `tests/smoke-slot.ps1`,
  `tests/test-skill-config-fallback.sh`, `tests/lint.sh`: Tests. No new test file, so `tests/check.sh` and
  `.github/workflows/ci.yml` do not change.
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 48 (#111): a pull request no longer changes the config that governs
  it. The skills, the slot script (its warm-up) and the pairing check read .claude/nightmill.json from the base branch
  (origin/HEAD, then git.baseBranch) with git show, the working tree's file only when no remote branch is known or the
  base has none yet. git.mergeFlags must contain --auto and never --admin (schema pattern and not, both now supported
  by validate-config, and the skills' merge step). A pull request that changes a path under .claude/ or .github/ is
  never auto-merged, and a check fix round that would add one is not pushed. No config key.` (paths, keys and commands
  in backticks).

Not touched: `scripts/guard.*`, the other scripts, `skills/init`, `agents/`, `hooks/`, `templates/`, `SECURITY.md`,
`.github/`, this repository's `.claude/` files.

## Risks

- **A stale base.** The base configuration is the last fetched one; a change merged since the last fetch applies from
  the next fetch. A take fetches the base branch, so the warm-up is at most one take behind.
- **A repository without `origin/HEAD`** (made with `git init` and `git remote add`) stops every skill and the slot
  script until `git remote set-head origin --auto` runs once. Chosen over taking `git.baseBranch` from the working
  tree, which a branch could point at a branch of its own on origin (decision 1.2); the stop line says the fix.
- **The fallbacks.** With no remote branch, or before the base has a config, the working tree governs, as today; the
  run says so. Neither state can be caused by a pull request.
- **What the base cannot cover.** The check command and the warm-up come from the base, but what they run (for
  example `tests/check.sh`, a test, a `package.json` script) is the branch's code; the sandbox of #169 is for that. The
  guard and the other scripts still read the working tree (Not done).
- **False withholding.** A legitimate change to `.github/` or `.claude/` waits for the maintainer's merge; in this
  repository that includes the issue forms and CI. A check fix round that needs such a change hands over. That is what
  the issue asks.
- **Regex flavours.** The schema's patterns are kept to characters the three engines read alike (lint), and the
  validator matches case-sensitively in both shells.
- **The injection's length.** One line of about 280 characters in six skills; the lint pins it, so the six stay equal.

## Size estimate

`L`: about 60 lines each in `baseconfig.sh` and `baseconfig.ps1`, 15 each in `slot.sh` and `slot.ps1`, 25 in
`validate.awk`, 20 and 25 in the two validator scripts, 3 in the schema, 30 in the workflow skill, 15 each in spec,
next and fix, 6 each in story and check, 25 in the README, 80 each in the two slot smoke tests, 35 each in the two
validator smoke tests, 30 in `test-skill-config-fallback.sh`, 70 in `tests/lint.sh`, 8 in `CHANGELOG.md`: about 780
changed lines in 22 files.

## Not done

- The guard hook (`scripts/guard.*`) still reads `board.statuses`, `board.statusField`, `github.*` and `git.baseBranch`
  from the working tree; `status`, `room`, `control`, `load`, `models`, `dashboard`, `panel`, `stages`, `new-worktree`
  and `render-templates` too. The issue asks for the skills; the slot script is included because it runs the warm-up
  the issue names (decision 7). See Left.
- No sandbox for the code the check and the warm-up run (#169); no `CODEOWNERS` or ruleset change; no separate agent
  identity (#178).
- No new config key: neither the base ref nor the protected directories are configurable; no change to
  `escalation.storyTriggers`, which still names key changes only.
- No `git fetch` added to the injection or the scripts; no `git remote set-head` run by `/init`.
- No change to `/init`, which writes and validates the working tree's file; no change to its guard line.
- No check of pushes by anyone else to a pull request after auto-merge was enabled.

## Left

- **The guard and the other scripts.** Iteration 47's Risks name #111 for a config edit that would blind the guard
  (a renamed `board.statuses.ready`). This spec leaves the guard on the working tree, as the issue asks only for the
  skills; the README gets a row with `none filed`. Whether the guard should read the base configuration too (with the
  same `lib/baseconfig.sh`) is for the maintainer: an issue to file, or a widening of this story.
- **`origin/HEAD` instead of `git.baseBranch` from the working tree.** The issue's evidence writes
  `git show origin/<base>:.claude/nightmill.json`; this spec takes `<base>` from the configuration on `origin/HEAD`
  (decision 1), because the working tree's `git.baseBranch` is itself a value the branch can change. The cost is the
  stop for a repository without `origin/HEAD`. If the maintainer prefers the working tree's `git.baseBranch` as the
  lookup, decision 1 steps 1 and 2 change and Risks gain that hole.
- **"Offline".** The issue says "falling back to the file when offline". `git show` of a remote-tracking ref needs no
  network, so this spec reads "offline" as "no remote-tracking branch is known", and adds the fallback for a base
  without a config (decision 1, steps 2 and 3); it does not fall back when a fetch fails.
- **Not verified by a run:** that the harness runs the compound injection with the new `allowed-tools` without a
  prompt (the #127 test checks the coverage, not the harness), and the PowerShell twins (no PowerShell on this
  machine; CI runs them). Manual check steps 1 and 5 settle them.
