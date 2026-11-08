# Changelog

## Unreleased

- Iteration 38 (#154): CI runs with a read-only token, a timeout on every job (5 to 38
  minutes), cancels superseded runs of a pull request only (every push to main gets its own result), says on each
  required job name that the ruleset requires it, and pins its actions by commit SHA, kept current by Dependabot.

- Iteration 34 (#186): a take claims its slot atomically and a failed take leaves no half-taken slot. The take now
  claims the slot before it fetches, switches the worktree or warms up: it writes a marker with `"state": "taking"` and
  its process id (`"pid"`) and gives it the marker's name only when no marker exists (`ln` in bash, `File.Move` in
  PowerShell), so two takes, in either shell, never get the same slot. The finished marker is unchanged (the same keys
  as before). The fetch is tried up to 3 times, 1 s apart, so two takes that fetch at the same moment both succeed.
  A failed fetch, switch or warm-up puts the slot back as it was, frees the claim and prints `<step> failed (exit N);
  slot N is free again`, in both shells (bash now exits 1 as well, where it used to exit with the command's code
  silently, and PowerShell no longer throws); when the failed warm-up left changed or new files in the slot, the slot
  keeps its claim instead, so nothing is lost, and `--abandon` frees it. A claim whose process has ended is dead:
  `--status` shows it as `taking: ... (process N has ended; free it with --abandon N)` and the porcelain step field as
  `take-died`; only `--abandon` frees it, and it keeps the branch. A live claim shows as `taking` and is skipped by
  the take, refused by `--release`, `--abandon` and `--report` and skipped by the reap, which makes no `gh` call for it.
  The porcelain keeps its ten fields, so `status`, the dashboard, the panel, `load` and `control` need no change; the
  previous version reads a taking marker as a busy slot. New helper `json_marker_taking` in `scripts/lib/json.sh`. The
  test hook `NIGHTMILL_CLAIM_GATE` (tests only, not a config key) holds a take at the publish. Supersedes bug #113.
  Retries of the take's own marker changes and the cleanup of an interrupted take are #189 and #190.

- Iteration 33 (#182): `/fix all` fixes Ready bugs in parallel and runs until every bug is processed. It runs one bug
  per slot, as many at a time as the free slots, the live agent limit and the room on the machine allow, and takes the
  slots one at a time so two starts never get the same one. Bugs start by priority, then issue number; a bug that
  becomes Ready during the run is picked up. A bug for which nothing is free waits instead of ending the run. A slot is
  freed with `-Abandon` once the bug's branch is the head of its open pull request (the local branch is kept), and the
  slot of a skipped bug stays held with its files. Bugs that overlap (a file named in both issues, the same
  `parallel.hotFiles` entry, `parallel.doNotPair`) do not run at the same time. The fixed cap of five bugs is gone; the
  new key `parallel.fixAllMaxBugs` (default 0: no limit, ignored by the previous version) limits the bugs one run
  starts. A stop prints a `Not started:` and `Stopped in flight:` line, and the run ends with one table.

- Iteration 32 (#69): a pane beside the Claude chat shows the slots and the agents in them. The plugin ships a Claude
  Code mod, `hooks/panel.tsx`, named under `modules` in `hooks/hooks.json` next to the `SessionStart` hook. It is off
  until asked: `/nightmill-slots` opens the pane, `/nightmill-slots off` (or the pane's close mark) closes it, and
  nothing runs before that. While it is open the pane shows every slot (free or busy, the agent as running, stalled or
  unknown, branch, skill and step, age of the last report), reads them again every `worktrees.panelRefreshSeconds`
  seconds and shows the time of the last read. A slot or a read that cannot be understood is shown as `unknown` with
  the reason and no rows, never as free. The pane is read-only (it draws only text and runs only `scripts/panel.sh` /
  `scripts/panel.ps1`, which run only `slot --status --porcelain`, with no `gh` and no network); it needs Claude Code
  2.1.287 or later (terminal, Desktop app Code tab, VS Code extension 2.1.299 or later) and is not drawn in `claude -p`,
  cloud sessions or on claude.ai. The new key `worktrees.panelRefreshSeconds` (default 15, 5 to 3600) is ignored by the
  previous version.

## 0.4.0 (2026-11-06)

- Iteration 31 (#68): a page in the browser shows the slots and what waits for the maintainer. `scripts/dashboard.sh` /
  `scripts/dashboard.ps1` write one self-contained HTML page to the temporary folder
  (`nightmill-dashboard-<owner>-<repo>.html`) and rewrite it every `worktrees.dashboardRefreshSeconds` seconds until
  Ctrl-C; the page reloads itself, so there is no server and nothing listens. `--once` / `-Once` renders once and prints
  the `file://` address; the script opens no browser. The page holds the slot table (state running, stalled, unknown or
  free as a word as well as a colour, branch, skill, step, last report, pull request and CI, the `stale:` flag) and the
  items at Spec review and Approved with their pull requests and CI. What cannot be read (no `gh`, logged out, no
  network) is shown as `unknown` with the reason, never as free or as nothing waiting; after three intervals without a
  rewrite the page says it is out of date. Every value from outside is escaped, and the page has no link, form or
  button, so it changes nothing. New `status.sh --porcelain` / `status.ps1 -Porcelain` print the tables of `/status`
  tab-separated for programs (record kinds `item`, `note`, `slot`, `capacity`); the text form is unchanged. The new key
  `worktrees.dashboardRefreshSeconds` (default 60, at least 10) is ignored by the previous version.

- Iteration 30 (#82): an opt-in controller adjusts the agent limit from the measured load. One pass is one call of
  `scripts/control.sh` / `scripts/control.ps1` (no argument, nothing left running); the skill `/nightmill:control` runs
  one pass, so `/loop 5m /nightmill:control` is the session's controller and an orchestrator calls the script. The new
  key `parallel.controlMode` (the first `enum` of the schema) is `off` by default; `report` prints what a pass would
  change and changes nothing; `apply` changes. A pass measures over `parallel.loadWindowSeconds` with the library of the
  load command, takes its suggestion as the target, keeps it between `controlMinAgents` (default 1) and `controlMaxAgents`
  (default 4), and applies its own rules: up one step only when the whole window had room and `controlCooldownMinutes`
  (default 15) have passed since the last change (read from `since` of `capacity.json`), down at once to the target when
  memory is short, down one step per cooldown when the CPU or the ceiling is the limit. It changes the live numbers only
  by running `slot --capacity` as a child: the agent limit, and the slot count raised to the new limit when that exceeds
  it, never lowered; it never edits the config or a marker, stops an agent or frees a slot. Every pass prints one line
  (old value, new value, the rule and the measure) and `control: next pass in <controlIntervalMinutes> min`; a pass that
  cannot measure changes nothing, says so and exits 1. The five keys are ignored by the previous version.

- Iteration 29 (#45): the code reviewer checks the tests against the spec and that none was weakened.
  `agents/code-reviewer.md` gets four rules: for every acceptance criterion a test that would fail for a plausible wrong
  implementation (a criterion with no test, or only weak ones, is blocking); no test of the tester's removed, skipped,
  loosened or made conditional, compared with what the tester first wrote; an assertion that is always true, a test that
  never fails and a test of only a mock are reported (blocking when a criterion relies on them, advisory otherwise);
  and a finding whose fix belongs in the tester's tests begins its text with `test: `. The reviewer's prompt in `/next`
  and `/fix` gains three lines: the tester's files, each `committed` or `not committed`, the tester's own revisions
  after its first launch as `git diff <original blob> <blob>` (from the new `<tester originals>`, never replaced) and the
  `Test paths:` line, pasted when the prompt is filled in; the reviewer gets no account of the producer or of the tester.
  The findings format is unchanged. A blocking line that begins with `test: ` is a test finding whatever file it names:
  it goes to the tester through the dispute launch of iteration 27 (named paths sorted into three kinds: a tester file,
  a path that does not exist yet, an existing file that is not the tester's), the other blocking lines go to the
  implementer or the fixer, in the same fix round, which costs one of `review.maxFixRounds` whatever it holds; a test
  finding the tester answers `stands:` is not sent again and stays open, so auto-merge stays off by the existing
  sentence; a different number of `Answers` lines than findings is a failed tester result. How verified shows the
  tester's answer (`tester's answer to the code review in fix round <k>`); the report step is `test-finding-<k>` (role
  `tester`); the workflow skill gets two sentences in "Findings and fix rounds". No config key, status, slot marker,
  script or change to `agents/tester.md`.

- Iteration 28 (#81): a skill waits for room on the machine before it starts an agent. The new check
  `scripts/room.sh` / `scripts/room.ps1` (with `--since` / `-Since`) measures free memory and CPU load over 3
  one-second samples with the library of iteration 24 and answers whether the machine has room for one more agent: free
  memory at least `parallel.roomMinFreeMB` (default 2000) and CPU load at most `parallel.roomMaxCpuPercent` (default
  90). Exit codes: 0 start, 1 no room yet (the script has printed the `room: waiting` line and paused
  `parallel.roomPauseSeconds`, default 60; the skill calls it again with the printed `--since`), 2 error, 3 the longest
  wait (`parallel.roomMaxWaitMinutes`, default 30) ran out. The rule is written once, as the bullet "Room on the machine"
  in "Parallel work" of the workflow skill; `/next`, `/spec` and `/fix` point to it at every step where they count the
  agents before a start (a subagent, a take with its warm-up, a manual check, the session's own run of the check), and
  when the longest wait runs out the skill prints `Stopped: no room on this machine ...` and starts nothing (in
  `/fix all` it ends the run; `/spec` does its own clean-up). A measure that cannot be read is not checked and said
  once; a check that fails starts the agent. The check never changes the agent limit, stops an agent or frees a slot.
  Five new keys under `parallel` (`roomCheck`, the first boolean of the schema, switches it off; `roomMinFreeMB`,
  `roomMaxCpuPercent`, `roomPauseSeconds`, `roomMaxWaitMinutes`) are ignored by the previous version. The library
  `scripts/lib/load.*` gains an optional message prefix and `room_settings` / `Get-RoomSettings`; what `scripts/load.*`
  prints does not change.

- Iteration 27 (#44): the implementer may not change the tester's tests, and a doubtful test goes back to the tester.
  The prompts of the implementer in `/next` and of the fixer in `/fix` forbid editing, renaming, moving, overwriting or
  deleting the tester's files; they may add tests of their own only in files that are not the tester's. The check is git
  commands written into the two skills, not a script: when the tester returns the session records `<tester blobs>` (the
  tester's text stored with `git hash-object -w`, what HEAD held, the file mode), and after every result of the
  implementer or the fixer it compares each tester file with its record. A change is a failed round that is undone: the
  round's commits are taken back with `reset --mixed`, the tester's text is written back from the object store with
  `update-index --cacheinfo` and `checkout-index`, and the producer's other work stays in the working tree. A producer
  that believes a test is wrong or cannot be satisfied reports it on the new `Disputes:` line and does not change it; the
  session launches the tester again (`agents/tester.md` gets a rule for a dispute and an `Answers:` line, `revised:` or
  `stands:`), decides each disputed file by its hash, replaces the record of a revised file and launches the producer
  again. A dispute exchange and an undone round each cost one of `review.maxFixRounds`, shared with the review fix
  rounds; a dispute still open when the rounds are used up is listed in the pull request under `## Disputed tests` and
  keeps auto-merge off, and How verified lists the tests the tester revised. The report step `dispute-<k>` (role
  `tester`) is new. No config key, status, slot marker or script changes; the code reviewer's check of the tests is #45's.

- Iteration 26 (#43): a tester agent writes the failing regression test before `/fix` fixes. `/fix` now launches
  `nightmill:tester` (the agent of iteration 25) on `roles.tester.model` after the bug is In progress and the slot is
  taken, and before the fixer, in a new section "The tester" inside step 4 (no step is renumbered). The bug report is the
  one criterion (`1. <title> is fixed.`); the tester writes a regression test into the slot, runs it, confirms that it
  fails for the reason in the report and leaves it uncommitted. The session records `<tester files>`, checks them with the
  `Test paths:` rule and `git status --porcelain --untracked-files=all`, and stops with `Stopped: the tester changed
  files that are not tests` or `Stopped: the tester returned failed` as `/next` does. Only a `Result: complete` counts as
  reproduced: otherwise `Stopped: the tester could not reproduce bug #<issue>: <reason>. The fixer was not started.`
  (a skip in `/fix all`, with nothing committed and `not reproduced: <reason>` in the final table). The fixer's step 1
  becomes "Run the tester's test and watch it fail for the reason in the issue"; it commits the test with the fix once the
  check is green (the session checks the test is in `git diff --name-only`), so no red commit is ever made and "never
  commit red" is unchanged. The pull request's How verified begins with `Reproduced first by the tester role on <model>,
  failing before the fix:`, the tester's lines and the test's diff (or a pointer to the files when it is longer than 60
  lines). `/fix` reports the step `write-tests` (role `tester`) with `slot --report`; batch mode runs one producer at a
  time. The body of `agents/tester.md` is unchanged (only its `description:` names `/fix`); no config key, status or slot
  marker changes. The rule that the fixer may not edit the test is #44's, the code reviewer's check of the tests is #45's.

- Iteration 25 (#42): a tester agent writes the failing tests before `/next` implements. The new agent
  `agents/tester.md` (tools `Read, Grep, Glob, Write, Edit, Bash`, no `Agent`; its `model:` is kept equal to the schema
  default `sonnet` by the lint) is launched by `/next` as `nightmill:tester` on `roles.tester.model` after the story is
  In progress and the slot is taken, and before the implementer. It writes at least one test for every acceptance
  criterion, named for the behaviour it protects, reports which test covers which criterion and reports a criterion it
  cannot test as `not tested`; it runs the tests, confirms that they fail because the behaviour is missing, and leaves
  them uncommitted in the slot. It writes only test files and fixtures: the fixed `Test paths:` rule, identical in the
  agent file and the skill, and the session's `git status --porcelain --untracked-files=all` check, which stops the run
  with `Stopped: the tester changed files that are not tests` otherwise. The implementer's step 1 now runs the tester's
  tests, writes a test for each `not tested` criterion and commits the tests with the code once the check is green, so no
  red commit is ever made and "never commit red" is unchanged. For a partial result the tests of unmet criteria stay
  uncommitted, are set aside under the stash message `Unmet tests for #<issue>: <title>` (found by that message, because
  every worktree shares one stash) before the CHANGELOG commit, are named in the pull request and are carried to the new
  story. The pull request's "How verified" begins with `Tests written first by the tester role on <model>, failing
  before the code:` and the criterion-to-test list. `/next` reports the step `write-tests` (role `tester`) with
  `slot --report`. No config key, status, slot marker or script changes; `/fix` and the rules for the implementer and the
  code reviewer on the tests are the separate stories #43, #44 and #45.

- Iteration 24 (#80): a command shows CPU and memory load and suggests an agent limit. The new read-only command
  `scripts/load.sh` / `scripts/load.ps1` (with `--porcelain` / `-Porcelain`) measures the CPU load and the free memory
  over a window of one-second samples (`parallel.loadWindowSeconds`, default 10): the mean of the CPU samples and the
  lowest free memory, never a single reading. It shows the agent limit and the slots in use from the slot script, the
  agents running (counted from the busy slots) and a suggested agent limit with one line saying why: the smaller of a
  memory bound (one agent per `parallel.memoryPerAgentGB`, default 8, of the total and of the free memory, one fewer when
  under 10% is free) and a CPU bound (the agents in the slots scaled to 80% busy), at least 1 and at most
  `parallel.maxSuggestedAgents` (default 4). A measurement it cannot take is shown as `unavailable` with the reason and no
  suggestion (exit 1); errors exit 2. The measurement and the suggestion are in the libraries `scripts/lib/load.sh` and
  `scripts/lib/load.ps1` for the later stories: `/proc/stat` and `/proc/meminfo` on Linux and in Git Bash, the raw
  processor counter and `Win32_OperatingSystem` on Windows, `top`, `vm_stat` and `sysctl` on macOS. The smoke tests use
  `NIGHTMILL_LOAD_FIXTURE`, a file of samples, instead of the machine. The command changes nothing; `slot -Capacity
  -AgentLimit N` applies a suggestion. The three new keys are ignored by the previous version.

- Iteration 23 (#67): slots record what their agent is doing and `/status` shows it. The new command
  `slot.sh --report <step> --slot N --skill <s> --role <r>` / `slot.ps1 -Report <step> -Slot N -Skill <s> -Role <r>`
  adds four keys to the slot marker after `slot`, `branch` and `since`: `skill`, `role`, `step` and `reported` (the
  local time of the report); both shells write the same bytes, and a report never brings back a slot that was released.
  `/next` and `/fix`, and the implementer and fixer they launch, report at each step (the step tables are in the two
  skills; `/spec` takes no slot and reports nothing). The new config key `worktrees.stalledAfterMinutes` (integer, at
  least 1, default 30; an unusable value falls back to 30 with a note on standard error) sets how old the last report
  may be: an agent state is `running` while the report is at most that old, `stalled` after that and `unknown` when the
  slot has no report (a marker of the previous version, a take by hand). `slot --status --porcelain` has ten fields for a
  busy slot (fields 1 to 4 unchanged, field 5 `retiring` or empty, then the agent state, skill, role, step and
  `reported`). `/status` prints one Slots section that lists every slot, free and busy, with the agent state, skill and
  role, step, the age of the last report, the pull request and the existing `stale:` flags; `slots: none busy` is gone.
  A slot that waits for its merge after its last report shows `stalled` once the threshold has passed. The marker and the
  config stay readable by the previous version. The change is a story trigger (a new config key and a change to the slot
  marker format).

- Iteration 22 (#78): the slot count and the agent limit can be changed during a session. The new command
  `slot.sh --capacity` / `slot.ps1 -Capacity` shows the numbers, sets them (`--slot-count N`, `--agent-limit M`, or
  `-SlotCount` / `-AgentLimit`), clears them (`--clear`) and prints them for a program (`--porcelain`). The values are
  kept in the untracked `<worktrees.root>/.slots/capacity.json` beside the slot markers, win over `WORKER_SLOTS` and
  over the configuration, do not expire until cleared and never edit `.claude/nightmill.json`; the previous version
  ignores the file. A value must be a whole number from 1 to 99 and an invalid one changes nothing. Lowering the slot
  count touches no busy slot, marker or worktree: a busy slot above the count is `retiring` (a fifth field in
  `--status --porcelain`), is no longer handed out and goes on being released, reaped and abandoned; raising it
  brings the slots back. `slot --status` and `/status` print a `capacity:` line that says when the numbers are live.
  `/next`, `/spec`, `/fix` and the workflow skill read the agent limit with `--capacity --porcelain` at every
  decision to start an agent, not once per session; a lowered limit stops no running agent. No config key, no change
  to the slot marker or the status flow.

## 0.3.0 (2026-11-06)

- Iteration 21 (#40): the spec review is recorded in the spec pull request and open blocking findings stop
  auto-merge. The body of the spec pull request, under `Spec for #<issue>.` and the writer's line, now has the
  `## Review` section that iteration 19 defined for code pull requests, with `specReviewer` as the reviewer and
  `specWriter` as the author (one added sentence in "The pull request" of the workflow skill keeps the format defined
  once). It replaces the interim text of iteration 20 (`Open review findings`, `Review notes` and the `Reviewed by`
  line). With a blocking finding still open the spec pull request is opened, `gh pr merge` is not run and the body
  says `Auto-merge is not enabled: blocking review findings are still open (see Review).`; the story still goes to
  Spec review and the comment on the issue gets the tail `Blocking review findings are still open (<b> blocking, <a>
  advisory): auto-merge is off, see the Review section of the pull request.` after the unchanged
  `Spec: <path> (PR #<pr>). Waiting for approval.` that `/next` reads. With only advisory findings, or none,
  auto-merge is enabled as before. The workflow skill's "CI and merging" says `(a spec PR too)`. The lint pins the
  wording and checks that the interim text is gone. No config key, script or status change.

- Iteration 20 (#39): a separate spec reviewer reviews the spec before it goes to Spec review. The new agent
  `agents/spec-reviewer.md` (tools `Read, Grep, Glob`, `model:` kept equal to the schema default by the lint) checks
  that every acceptance criterion is covered and testable, that exact rules and numbers are in the spec, that it
  contradicts no decision and no existing spec, that it has a "Not done" list, that it states whether the change is
  one of the escalation triggers and whether the manual check applies, that it adds no scope the issue does not ask
  for and that its title and status line have the form the skill checks, and reports findings in the block of
  "Findings and fix rounds". `/spec` launches it as `nightmill:spec-reviewer` on `roles.specReviewer.model` after the
  writer's result and before the commit, as a fresh agent that gets the story, the epic, the decisions and specs
  directories, the escalation triggers, the manual-check paths and the invariants but not the writer's own account;
  blocking findings go back to a fresh spec writer for at most `review.maxFixRounds` rounds; the pairing is checked
  with `validate-config`; a review that cannot be had stops the run and leaves the story at Spec. Blocking findings
  left after the last round are listed in the spec pull request under `Open review findings` and keep auto-merge off
  (an interim until #40). The lint pins the wording and the format lines (now the same in three files) and allows
  exactly the worker and the two reviewers under `agents/`. No config key, script or status change.

- Iteration 19 (#37): the review is recorded in the pull request and open blocking findings stop auto-merge. A pull
  request of a story or a bug that went through the code review has a `## Review` section after "How verified",
  defined once in the paragraph "The pull request" of "Findings and fix rounds" in the workflow skill: the reviewer's
  and the author's role and model, `Fix rounds used: <r> of <review.maxFixRounds>`, `Findings fixed`, `Findings still
  open` (blocking and advisory), one line per fixed finding (`fixed in round <k>:`) and one per open finding as the
  last review wrote it. The section replaces the interim text of iteration 18 (`Open review findings`, `Review
  notes` and the `Reviewed by` line). With a blocking finding still open the pull request is opened all the same and
  says `Auto-merge is not enabled: blocking review findings are still open (see Review).`; the workflow skill's "CI and
  merging" names an open blocking review finding as a reason not to enable auto-merge, and advisory findings change
  nothing. `/next` and `/fix` build the section the same way. The lint pins the wording, checks that the interim
  text is gone, and its section extraction now ignores a `## ` line inside a code fence. No config key, script or
  status change.

- Iteration 18 (#36): a separate code reviewer reviews the change before the pull request opens. The new agent
  `agents/code-reviewer.md` (tools `Read, Grep, Glob`, so it cannot change anything; `model:` kept equal to the schema
  default by the lint) checks that every acceptance criterion has a test, that the change does what the spec says and
  nothing beyond it, that the "Not done" list and the invariants hold and that the check is green, and reports
  findings in one fixed block. The format, the definition of blocking and advisory, the fix rounds (at most
  `1 + review.maxFixRounds` reviews, only blocking findings go back, to a fresh implementer or fixer) and the pairing
  rule (checked with `validate-config`, never by comparing ranks) are written once in a new section "Findings and fix
  rounds" of the workflow skill, for the spec review to reuse. `/next` and `/fix` launch the reviewer as
  `nightmill:code-reviewer` on `roles.codeReviewer.model` after the producer's result and before the manual check, as
  a fresh agent that gets the criteria, the spec, the invariants, the diff and the check line but not the producer's
  own account; a review that cannot be had stops the run. Blocking findings left after the last round are listed in
  the pull request under `Open review findings` and keep auto-merge off (an interim until #37). The lint pins the
  wording, keeps the agent's tools and format in step, and now allows exactly the worker and the code reviewer under
  `agents/`. No config key, script or status change.

- Iteration 17 (#60): a slot whose pull request has merged is freed without a manual release. `slot.sh --take` and
  `slot.ps1 -Take` now first free every busy slot whose pull request has merged, and the new `--reap` / `-Reap` does
  only that. A slot is freed only when its worktree is clean and `gh pr list --state merged --head <branch>` lists a
  pull request whose `headRefOid` is the tip of the local branch (a stricter check than `--release`, so a reused
  branch name or commits made after the merge keep the slot busy and nothing is deleted); freeing is what
  `--release` does (switch to a detached `origin/<base>`, delete the local branch, remove the marker) and each freed
  slot is reported in one line, `Slot 1 is free (was feat/a, PR #12), released automatically.` A slot that cannot be
  judged (no `gh`, `gh` failing or logged out, no fetch) stays busy with a note on standard error and never makes a
  take fail; `--reap` prints `No slot freed.` when nothing was freed. `--release`, `--abandon`, `--status`, the slot
  marker and every config key are unchanged. Twelve smoke cases run in both shells against a fake `gh`, the lint
  checks that both scripts carry the rule and that the README says so, and the README describes when a slot is
  freed on its own and when it is not.

- Iteration 16 (#34): `/nightmill:models` prints one table of the model of every agent role. The scripts
  `scripts/models.ps1` and `scripts/models.sh` (with `scripts/lib/models.awk`, no `jq`) read the config and the
  schema and print, per role, what it does, the model it runs on, whether that comes from the config or from the
  default of the schema, its 1-based rank in `models.ranking` and whether its pairing holds (`ok`,
  `BELOW <producers>` for a reviewer ranked below a role it reviews, `NOT RANKED` for a model that is not in the
  ranking; `tester` and `worker` are never flagged), then the ranking, a `pairings:` summary and, when the config sets
  nothing, a line that says these are the defaults. An invalid ranking is reported instead of compared. The
  scripts only read, find the config of the main checkout from any worktree, and exit 0 once the table is printed.
  The new skill runs the script and adds at most two lines; the README lists the command. Thirteen smoke cases run
  in both shells, among them one that requires the counts of the table to agree with `validate-config`, and the
  lint checks that the skill, both scripts and both tests exist, that the scripts only read, and that CI and the
  check run the tests. No config key, status or slot change.

- Iteration 15 (#32): the validator rejects a reviewer ranked below its producer. `validate-config` (PowerShell and
  bash, in `scripts/lib/validate.awk`) checks, after the schema walk, that `specReviewer` ranks at least as high as
  `specWriter` and `codeReviewer` at least as high as `implementer` and `fixer`, judged by `models.ranking`, on the
  effective models (the configured model, else the default of the schema) and the effective ranking (the configured
  one, else the default). A reviewer ranked below a producer is an error that names both roles and both models
  (`specReviewer on "sonnet" ranks below specWriter on "opus"`); a model of one of those roles that is not in the
  ranking is a warning that names the role; `tester` and `worker` are never compared; models of one level share a
  ranking entry (`"opus=claude-opus-5-5"`) and pass. The rule is skipped when `models.ranking` is not a non-empty
  array (the walk already reports that), so a config without the keys is unaffected. Fourteen smoke cases run in
  both shells, the lint checks that both carry the rule and that the validator it uses has it, and the README and
  the description of `roles` in the schema say that the validator checks it. No config key, flag or status change.

- Iteration 14 (#38): `/spec` hands the writing to a spec writer subagent on the configured model. The spec file
  is written by a `specWriter` subagent, launched as a fresh agent (not a fork, not the `worker`) on
  `roles.specWriter.model` or the schema default, passed explicitly, after the session created the spec branch from
  the up-to-date base and counted the agents against `parallel.maxAgents`. The prompt carries the story, its epic
  and the specs and decisions they reference, forbids committing, pushing, board changes and further agents, and
  ends with a result block (`Result: complete | partial | failed`). The session checks the form (one changed file,
  the title and the status line), commits the spec only and keeps the pull request, the statuses and every hard
  rule; the spec pull request says `Written by the specWriter role on <model>.` A `partial` or `failed` result, a
  wrong form or an unusable model leaves the story at Spec, opens no pull request and moves nothing to Spec
  review; the unfinished file is kept in a local commit and an empty branch is removed. The README says so in one
  sentence and the lint pins the wording. No config key, script or status change.

- Iteration 13 (#35): `/next` and `/fix` hand the coding to a subagent on the configured model. The tests and the
  code of a story are written by an `implementer` subagent, the failing test and the fix of a bug by a `fixer`
  subagent, each launched as a fresh agent (not a fork, not the `worker`) on `roles.<role>.model` or the schema
  default, passed explicitly, after the session counted the agents against `parallel.maxAgents`. The prompt names
  the slot's absolute path, forbids pushing, board changes and further agents, and ends with a result block
  (`Result: complete | partial | failed`). The subagent commits when the check is green; the session keeps the
  picking line, the statuses, the slot, the manual check, the CHANGELOG entry, the pull request and every hard
  rule. A `partial` result follows the existing partly-done rule (no auto-merge, the rest filed as a story); a
  `failed` one opens no pull request and leaves the story In progress; a model that cannot be used stops the run
  with the line of the workflow skill (in `/fix all` it ends the run, a failed bug is skipped). The pull request
  says `Written by the implementer role on <model>.` or `Fixed by the fixer role on <model>.` The README says so in
  one sentence and the lint pins the wording. No config key, script or status change.
- Iteration 12 (#48): `/nightmill:init` installs the edit permission a lights-out run needs. A new plan line,
  **Edit permission**, adds the rule `Edit(**)` to `permissions.allow` of the personal
  `.claude/settings.local.json`, so `/spec`, `/next` and `/fix` write files inside the project without a prompt
  (not Bash, not other directories; `.claude/` still prompts). The plan shows the exact text or diff before the
  one confirmation, says when the local file is not ignored by git, reports a skipped line as `declined (edits
  will prompt)` and a covered project (the rule in either file, or `defaultMode` `acceptEdits` or
  `bypassPermissions`) as `exists`, and never removes or reorders an entry. The README has a section "The edit
  permission". The slots under `worktrees.root` are outside the project directory and are not covered; that is
  the next story of the unattended-runs epic. The lint has a section that pins the wording, including that
  `Edit(/**)`, which reaches outside the project, is never written. No script and no config key changed.

## 0.2.0 (2026-11-05)

- Iteration 11 (#33): the workflow skill defines the agent roles and how a skill picks a role's model. A new
  section "Agent roles and models" lists the seven roles with what each produces and which role reviews which,
  and states the rule: the model of a role is `roles.<role>.model`, else the default in the schema, passed
  explicitly on every launch, never inherited from the session and never through a fork. A model that cannot be
  used stops the run with a line naming the role and the model; no skill falls back to another model. The old
  "always pass a model" sentence in "Parallel work" is replaced by a pointer to the section, and the README says
  the same in one sentence. The lint checks that the section names every role of the schema, carries the rule's
  wording, and that `agents/worker.md` has the schema default; a smoke case in both shells shows the lint fails
  when a role is missing.
- Iteration 10 (#31): three optional config keys name the agent roles and their models. `roles.<role>.model` sets
  the model of `specWriter`, `specReviewer`, `tester`, `implementer`, `codeReviewer`, `fixer` and `worker` (a role
  that is absent or empty takes the default in the schema), `models.ranking` lists models weakest first (models of
  one level share an entry joined by `=`) and `review.maxFixRounds` is how many fix rounds a producer gets after a
  review (default 2). All three are in the schema with descriptions and defaults, in the example config, in this
  repository's own config and in the README. Nothing reads them yet, so a project without them behaves as before.
  The lint checks the schema, the example, the repository's config and the README for them; both validate smoke
  tests cover the new keys.
- Iteration 9 (#10): `/nightmill:init` copies nightmill's template board when a project has none, so the views
  (filters, grouping, sorting) and the workflows come configured and nothing is left for the browser. It links
  the repository, replaces only the Area options (and Priority when `board.priorities` differs) and keeps the
  Status options and their ids. `scripts/template-board.ps1` and `scripts/template-board.sh` check, read only,
  whether the template is usable for a candidate config and print one line; when it is not (none published, not
  reachable, a renamed field or status) `/init` says why in the plan and builds the board field by field as
  before. The template's location is `templates/board-template.json`, not a config key; its number stays `null`
  until the maintainer publishes the template. Smoke tests run both scripts against fixtures and a fake `gh`; the
  lint checks the wiring and that the scripts only read.
- Iteration 8 (#9): `/nightmill:status` prints one table of what waits for the maintainer and what is stuck:
  board items with their pull request and CI state, the busy slots, and stale states flagged (Review with a
  merged PR, In progress or Spec with nothing behind it, a busy slot whose PR is merged or closed). It reads only.
  `scripts/status.ps1` and `scripts/status.sh` print the same table (the bash one needs no `jq`); `slot --porcelain`
  lists the slots for scripts. Smoke tests run both against fixtures and a fake `gh`.
- Iteration 7 (#7): the bash scripts read JSON without `jq`. `scripts/lib/json.awk` is a strict JSON parser in
  POSIX awk and `scripts/lib/json.sh` the functions on top of it (`json_get`, `json_len`, `json_keys`, `json_has`,
  `json_quote`, `json_marker`); `slot.sh`, `new-worktree.sh`, `render-templates.sh` and `validate-config.sh` use
  them, the validator's walk is now `scripts/lib/validate.awk`, and the slot marker is byte for byte what it was.
  The bash smoke tests run on a machine with only git, gh and bash; CI cross-checks the reader against `jq`, then
  hides `jq` for the other bash tests, and the lint fails if a bash file starts using `jq` again.
- Iteration 6 (#8): `scripts/validate-config.ps1` and `scripts/validate-config.sh` check a config against the
  schema: required keys, types, `minimum`, `minItems`, `enum`, closed objects, and a warning for an unknown key
  with a hint for a likely typo (`worktree` for `worktrees`). One line per finding names the key; the bash version
  needs `jq`. `/init` validates the candidate config before it shows the plan, and the lint validates the example
  and this repository's own config and fails if the schema gains a keyword the validator does not understand.
- Iteration 5 (#6): `scripts/release.sh` and `scripts/release.ps1` cut a release in two steps: prepare a
  `release/vX.Y.Z` pull request (version bump, changelog cut, README line), then `--publish` after the merge
  to tag the release commit and create the GitHub Release. `--dry-run` shows the plan. The lint fails when
  `plugin.json`, the newest changelog heading and the README's `Version` line disagree; the README line now
  reads `Version 0.1.1.`. Decision 0002 records why a release goes through a pull request.
- Iteration 4 (#5): `CONTRIBUTING.md`, two issue forms for outsiders (`nightmill-bug.yml` and
  `nightmill-idea.yml`, next to the rendered workflow forms), a pull request template, and a README line on
  what a stranger needs before installing. The lint checks that they exist and say what the spec requires;
  the render smoke tests check that rendering leaves other forms alone; the lint job in CI passes the
  `FORBIDDEN_WORDS` secret to the generic-words check when the repository has one.
- Iteration 3 (#12): a `SessionStart` hook (`hooks/hooks.json`, `scripts/session-start.sh` and `.ps1`)
  makes Claude offer `/nightmill:init` in a project that has the plugin enabled but no
  `.claude/nightmill.json`; in a configured project it is silent. `NIGHTMILL_HINT=off` silences it for
  people who enabled the plugin at user scope.
- Iteration 2 (#14): `/spec` and `/next` are two commands. `/spec [N]` writes the spec for a Ready story
  and stops at Spec review; `/next [N]` implements an Approved story only and, with nothing Approved,
  lists the Ready stories and points to `/spec`. Both print `Picking #N ...` before they change anything
  (rule: "Picking an issue" in the `workflow` skill). **`/next` no longer writes specs**: a project note
  or habit that calls `/next` for a Ready story must call `/spec`.
- Iteration 1 (#10): `/init` is an install chat. It detects owner, repo, board, check command and areas,
  asks the rest one question at a time with a proposed default, shows one plan, and after one
  confirmation creates or completes the board (eight Status options with existing ids kept, Priority and
  Area, four views (Board, Ready, Epics, Bugs) with filters and visible fields so the statuses are columns,
  the repository link), the labels, the config, the issue forms, the CLAUDE.md snippet and the permission
  rules in `.claude/settings.json`; it ends with a table of created, changed, already there, declined and
  failed lines. Re-running changes nothing. The board workflows cannot be set through the API: `/init`
  reads whether the ten it needs are enabled and always ends with the table to set by hand in the board's
  Workflows settings (item added > Backlog, item closed and pull request merged > Done, pull request
  linked, code review approved and code changes requested > Review, item reopened > In progress, auto-add
  and auto-add sub-issues on, auto-archive of closed items after one day, kept short to limit the items
  fetched and the GitHub rate limits). A view's grouping and sorting cannot be set through the API either;
  both are listed in the same closing section.
- nightmill develops itself: `.claude/nightmill.json`, issue forms, `.claude/CLAUDE.md`, `tests/check.sh`
  (one check command that runs what the machine can and lists what it skipped) and decision 0001.
- Plugin icon (`.claude-plugin/icon.png`): a white windmill and crescent moon on dark purple,
  rendered by `tools/make-icon.ps1`.

## 0.1.1 (2026-11-03)

- The PowerShell scripts read the config, templates and markers as UTF-8. Windows PowerShell 5.1
  otherwise used the ANSI code page, which turned an em dash in an invariant into mojibake in the
  rendered issue forms.

## 0.1.0 (2026-11-03)

First extraction of the workflow out of the project it grew up in, as a Claude Code plugin.

- Skills `next`, `fix`, `story`, `check`, `init` and the `workflow` rules; every project-specific value
  moved to `.claude/nightmill.json` (schema in `schema/`).
- The status flow gained two states: **Spec review** (the spec is written and merged, waiting for the
  maintainer) and **Approved** (any worker may implement). The spec is now a PR of its own, so a
  different agent can pick the story up after approval.
- `worker` agent for mechanical jobs.
- Slot scripts in PowerShell and bash, configured from the project file (root, slot count, ports,
  warm-up commands with lockfile-hash skip, run hints); new `-Abandon` to free a slot without a merged PR.
- Issue-form templates rendered from `areas` and `invariants`.
- Tests: generic-words lint, JSON and skill checks, slot smoke tests in both shells; CI for all of them.
- Licensed under the Apache License 2.0.
