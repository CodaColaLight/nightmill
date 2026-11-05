# Iteration 17: a slot whose pull request has merged is freed without a manual release

Status: delivered in iteration 17 (PR #79)

Story: #60, epic #47 (Unattended runs). Makes `slot.ps1 -Take` and `slot.sh --take` free every busy slot whose pull
request has merged before they look for a free slot, and adds `-Reap` / `--reap` to do just that by hand. The freeing
is `--release` with one extra safety check. Changes `scripts/slot.ps1`, `scripts/slot.sh`, `tests/smoke-slot.ps1`,
`tests/smoke-slot.sh`, `tests/lint.sh` and the README. No config key, no change to the slot marker, the status flow
or any skill: none of `escalation.storyTriggers` applies, so the PR may auto-merge. The change touches no path in
`verification.manualCheckPaths`, so no manual check applies. Both slot scripts are in `parallel.hotFiles`; no other
task may change them while this one is in flight.

## Goal

A slot whose pull request has merged is freed without a person running a command, so that the next `/next` or
`/fix` finds a free slot.

## Facts this rests on

- A slot is busy from `--take` to `--release` or `--abandon`: a marker file `slot-N.json` (keys `slot`, `branch`,
  `since`) in `<worktrees.root>/.slots`. `/next` and `/fix` end when the pull request opens; the merge comes later,
  so no skill is running when it happens and nothing frees the slot. On 2026-11-05 slots were still busy long after
  their pull requests had merged, and `/status` flagged them `stale: busy, PR merged`.
- `--release N` refuses when the worktree has uncommitted files (`git status --porcelain` not empty) or when
  `gh pr list --state merged --head <branch>` finds nothing; otherwise it fetches the base branch, switches the slot
  to a detached `origin/<git.baseBranch>`, deletes the local branch with `git branch -D`, removes the marker and
  prints `Slot N is free (was <branch>, PR #<n>).`
- `--release` trusts any merged pull request with that head **name**. By hand that is the maintainer's judgement.
  Done automatically it is not safe: a branch name that was used before (a merged PR on `feat/a` from last week) or a
  branch with commits made after the merge would match, and `git branch -D` would delete work that is in no
  pull request. The automatic path therefore also requires that the branch's tip is the last commit of the merged
  pull request (`gh pr list --json number,headRefOid`, compared with `git rev-parse refs/heads/<branch>`).
- `--take` today needs no `gh` and no network beyond its own `git fetch`. The freeing must not make a take fail where
  it used to work: a missing or logged-out `gh`, no network or an unexpected answer leaves the slot busy.
- `--status` is read-only and `/status` reads it (`slot.sh --status --porcelain`); neither changes.
- `tests/smoke-slot.*` run against a throwaway repository and do not cover `--release` ("needs gh and a merged PR").
  `tests/smoke-status.*` fake `gh` with a script on the `PATH` that answers from variables and logs every call; the
  same technique covers the freeing here.
- The slot marker is read by the previous version of the scripts; its format stays as it is.

## Decisions

**1. The freeing is in `--take`, not in a skill.** Both `/next` and `/fix` take their slot with `--take`, so no skill
changes and a person who takes a slot by hand gets the same. `/status` stays read-only.

**2. It runs on every take, not only when all slots are busy.** A merged slot freed early keeps `/status` free of a
flag that is no longer true, and the cost is one `gh pr list` per busy slot, none when no slot is busy.

**3. A separate flag exists for the same work.** `--reap` (`-Reap`) frees what can be freed and exits, so the
behaviour can be tried and tested without taking a slot. It is the only new flag; `--take` calls the same code.

**4. Never configurable.** A key to switch it off would be a new config key (a story trigger of its own); the safety
checks below are what keep it from freeing a slot in use.

**5. The automatic path is stricter than `--release`.** It adds the tip check. `--release` and `--abandon` stay
exactly as they are, same checks and same texts, for the maintainer who knows better.

**6. A slot that cannot be judged stays busy.** Never guessed free.

## The rule

`slot.sh --reap` and `slot.ps1 -Reap`, and the first step of every take, look at each busy slot (a marker exists, in
slot order) and free it when **all** of these hold; otherwise they leave it exactly as it is:

1. its worktree directory exists and `git status --porcelain` there is empty;
2. `gh` is on the `PATH` and `gh pr list --state merged --head <branch> --json number,headRefOid` succeeds and
   lists at least one pull request whose `headRefOid` equals the tip of the local branch
   (`git rev-parse refs/heads/<branch>` in the slot); the first such pull request, by the order `gh` prints, is the
   one named in the report;
3. `git fetch origin <git.baseBranch>` succeeded (done once per run, only when some busy slot passes 1 and 2).

Freeing is what `--release` does: `git -C <slot> switch --detach origin/<git.baseBranch>`, then
`git branch -D <branch>`, then remove the marker. The marker is removed only after the switch succeeded. A failing
`git branch -D` (the branch is checked out elsewhere, or already gone because another run was faster) does not stop
the run: the slot is still freed. Nothing else is deleted; the remote branch and everything on GitHub stay.

A slot that is **not** freed: uncommitted files; no merged pull request; only an open pull request or one closed
without a merge; a merged pull request whose last commit is not the branch's tip (work after the merge, a reused
branch name, or a head moved by "update branch"); `gh` missing, failing or not logged in; the fetch failed.
`/status` keeps flagging such a slot as before.

### Output

On standard output, one line per freed slot, in slot order, the text of `--release` plus a suffix:

```
Slot 1 is free (was feat/a, PR #12), released automatically.
```

A slot that passed 1 but could not be judged because `gh` or the fetch failed gets one line on standard error:
`slot 1: not checked for a merged PR (<first line of the reason>)`. A slot that is simply not freed prints nothing.
`--reap` alone, when nothing was freed, prints `No slot freed.`; `--take` never prints that.

### Exit codes and the take

`--reap` exits 0 whenever it ran, whether or not it freed anything; a usage error or a missing config is as for every
other flag. Inside `--take` the freeing never changes the outcome: whatever it prints, the take goes on with the slot
logic as before, so a take that would have worked without it still works, and a take with every slot busy still
fails with its existing message when nothing could be freed. The freed lines come before the take's own output.

## README

- "Why slots": the sentence "A slot is busy from `-Take` to `-Release` (after the PR merged) or `-Abandon`" says that
  a take also frees every busy slot whose pull request has merged, when its worktree is clean and its branch tip is
  the last commit of that pull request, and that `-Reap` / `--reap` does only that; anything else stays busy until
  `-Release` or `-Abandon`.
- Where the slot commands are listed, `-Reap` / `--reap`.

## Tests

Each acceptance criterion of #60 is a test. Names are the behaviour protected.

**`tests/smoke-slot.sh` and `tests/smoke-slot.ps1`**, the same cases in both, new section "== automatic release", in
the throwaway repository the file already builds, with a fake `gh` on the `PATH` (as `smoke-status` does) that
answers `gh pr list --state merged --head <branch> --json number,headRefOid` from variables (the number and the
`headRefOid` per branch, or an empty list), answers `--state open` with an empty list, fails when told to, and logs
every call:

1. **Merged and clean is freed by `--reap`**: a slot on `feat/a`, one commit pushed as the pull request's head, the
   fake `gh` says merged with that commit: the output is `Slot 1 is free (was feat/a, PR #12), released automatically.`,
   the marker is gone, the slot is on a detached `origin/main`, the local branch is gone, the remote branch is still
   there, `--status` shows the slot free.
2. **A take frees it first**: both slots busy, slot 1 merged and clean: `--take feat/x` succeeds, prints the freed
   line before `Slot 1 is yours`, and slot 1 is on `feat/x`. Without a freeable slot the same take still fails with
   `all 2 slots are busy; see slot.sh --status`.
3. **Uncommitted files keep it busy**: an untracked file in the slot with a merged pull request: nothing printed,
   marker and branch stay, no `gh` call for that slot (the check order is cheap first).
4. **No merged pull request keeps it busy**: the fake `gh` returns an empty list (an open or closed-unmerged pull
   request looks the same to the merged query): marker and branch stay, nothing printed.
5. **Work after the merge keeps it busy**: a merged pull request whose `headRefOid` is an older commit than the
   branch's tip: marker stays and the branch, with its newer commit, is still there.
6. **A reused branch name keeps it busy**: a merged pull request whose `headRefOid` is a commit that is not on the
   branch at all: the slot stays busy.
7. **`gh` failing keeps it busy and does not break a take**: the fake `gh` fails: a `--reap` prints nothing on
   standard output, exits 0 and writes `slot 1: not checked for a merged PR (...)` on standard error; with one slot
   free a `--take` still succeeds.
8. **`--status` is read-only**: after a `--status` and a `--status --porcelain` the fake `gh` log has no call and no
   marker changed.
9. **`--release` and `--abandon` are unchanged**: `--release` of a merged, clean slot prints exactly
   `Slot 1 is free (was feat/a, PR #12).` (no suffix) and refuses a slot without a merged pull request with its old
   message; `--abandon` as in the existing cases.
10. **The marker format is unchanged**: a marker written by `--take` has exactly the keys `slot`, `branch` and
    `since`, in that order.
11. **A marker without a worktree** (written by hand) is left alone and does not stop the run.
12. **Nothing to free**: `--reap` with no busy slot prints `No slot freed.`, exit 0, and the fake `gh` log is empty.

**`tests/lint.sh`**, new section "== slots free themselves": both `scripts/slot.sh` and `scripts/slot.ps1` contain
`released automatically` and `headRefOid`, and the README mentions `--reap` and `-Reap`.

`bash tests/check.sh` stays green, on this machine the PowerShell smoke test runs too.

## Verification

No path of `verification.manualCheckPaths` changes, so no manual check applies. The PR's "How verified" lists the
smoke cases of both shells and the check, and shows one real run: in a scratch repository with two slots, a merged
pull request is not available offline, so the real-`gh` path is the one thing the fake covers; the PR says so.

## Not done

- No config key to switch the behaviour off or to change what counts as merged.
- No change to `--release` or `--abandon`, to `/status`, or to any skill; the skills' sentence "`-Release N` after
  the merge" stays and is now only the manual way.
- No freeing of a slot whose pull request is open, or closed without a merge, or whose branch has newer commits:
  that stays a decision of the maintainer (`--abandon` or `--release`).
- No deletion of a remote branch and nothing on GitHub; no change to the board or to a status.
- No change to the slot marker format, to the warm-up, to the ports or to the number of slots.
- No handling of a pull request merged by rebase or by "update branch" whose head moved: the tip check keeps such a
  slot busy, and the maintainer frees it with `--release`.
