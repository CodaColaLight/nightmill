# Iteration 2: `/spec` writes the spec, `/next` implements the approved story

Status: draft, awaiting approval (#14)

Story: #14, epic #4. Splits `skills/next/SKILL.md` in two. No new config key, no change to the status
flow or to who sets a status, no change to the slot marker: none of `escalation.storyTriggers` applies, so
the PR may auto-merge.

## Goal

Writing a spec and implementing an approved story are two commands. Each says which issue it picked and why
before it changes anything on the board or in the repository.

## The two skills

| | `/nightmill:spec [N]` (new, `skills/spec/SKILL.md`) | `/nightmill:next [N]` (`skills/next/SKILL.md`) |
|---|---|---|
| Takes | a story at **Ready** | a story at **Approved** |
| Does | today's step 2: Spec, milestone, spec file, spec PR, Spec review, comment, stop | today's step 3: In progress, slot, tests, implementation, check, PR, Review, auto-merge |
| Frontmatter | `disable-model-invocation: true`, `argument-hint: [issue-number]`, same configuration preamble as `next` | unchanged apart from the description |

The bodies of the two procedures are today's steps 2 and 3, moved, not rewritten. Their hard rules are
copied into both skills: never set Ready or Approved, never close an epic, never delete files without
asking, merge only with `git.mergeFlags`.

## Picking the issue (shared rule)

The rule is written once, as a section **Picking an issue** in `skills/workflow/SKILL.md`; step 1 of each
skill states its status and refers to that section, and keeps its own `gh` commands. The rule:

1. With a number: take that issue. If it is an epic or a bug, refuse and point to `/fix` for bugs. If its
   board status is not the skill's status (Ready for `/spec`, Approved for `/next`), refuse with one line
   that names the status found and the skill that takes it, for example
   `#12 is at Spec review, not Ready; /spec only takes Ready stories.` Nothing is changed.
2. Without a number: list the board (`gh project item-list`), keep open issues that are not epics and not
   bugs and are at the skill's status, take the highest `board.priorityField` (order of `board.priorities`;
   an item without a priority ranks last). On a tie ask the maintainer which, listing the tied issues.
3. Before the first change (board, branch, file, slot) print one line:
   `Picking #N "<title>": <status>, <priority>, <reason>` where the reason is `named by number`,
   `only <status> story` or `highest priority of K <status> stories`.

## `/next` with nothing Approved

`/next` without a number and with no Approved story changes nothing. It prints the Ready stories as
`#N "<title>" (<priority>)` lines, one per story, ordered as in the rule above, followed by
`Nothing is Approved. Run /spec N to write a spec.`. With no Ready story either it prints
`Nothing is Approved or Ready.` and stops. It never starts a spec.

`/spec` without a number and with no Ready story prints `Nothing is Ready.` and, when Approved stories
exist, `Approved: #N ... Run /next to implement.`; it changes nothing.

## Places that change

- `skills/spec/SKILL.md` (new); `skills/next/SKILL.md` (spec steps removed, description and step 1 updated).
- `skills/workflow/SKILL.md`: the section above, and the sentence under "Stories and bugs" that says
  `/next` takes a story now says `/spec` writes the spec for a Ready story, `/next` implements an Approved
  one.
- `README.md` (command table gets a `/nightmill:spec [N]` row and `/next`'s row is shortened; the line about
  bare commands lists `/spec`), `templates/CLAUDE.snippet.md`, `.claude/CLAUDE.md` (the process paragraph and
  the Layout list of skills), `.claude-plugin/marketplace.json` (description lists `/spec`).
- `docs/decisions/`: no decision record, because no status and no setter changes.
- `CHANGELOG.md`: a bullet under `Unreleased` for iteration 2 (#14). The entry notes that `/next` no longer
  writes specs, since a project's habit or notes may call `/next` for a Ready story.

## Tests

Skills are prose, so the tests protect what the prose must keep saying; the manual check proves behaviour.

- `tests/lint.sh` check `spec and next stay split`: `skills/spec/SKILL.md` exists with frontmatter and
  contains `Spec review` and `Ready`; `skills/next/SKILL.md` contains `Approved` and does not contain the
  heading of the spec-writing procedure (`## 2. A Ready story`); `skills/workflow/SKILL.md` contains
  `Picking an issue`; both skills contain `Picking #`.
- The existing lint (frontmatter, forbidden words, JSON) and `claude plugin validate --strict` accept the
  new skill.
- Manual check (`skills` path changed, so required), with `claude --plugin-dir <this checkout>` on a board
  with a Ready, an Approved, and finally neither:
  1. `/next` with only a Ready story: lists it, tells to run `/spec N`, board unchanged;
  2. `/spec` with a Ready story: prints the picking line, then follows the spec procedure;
  3. `/spec N` on an Approved story and `/next N` on a Ready story: each refuses naming the status found;
  4. `/next` with an Approved story: prints the picking line, then follows the implementation procedure.

  The PR describes what was seen. Steps 2 and 4 are stopped after the picking line when running against a
  real board that must not be touched.

## Not done

- Changing what a spec contains, how it is merged, or the implementation steps.
- Any change to statuses, who sets them, or config keys.
- A combined command that does either job by status; `/next` does not fall back to `/spec`.
- Migrating projects: they get the new command with the next version, and the CHANGELOG says so.