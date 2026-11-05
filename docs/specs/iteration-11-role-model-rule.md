# Iteration 11: the workflow skill defines the agent roles and how a skill picks a role's model

Status: draft, awaiting approval (#33)

Story: #33, epic #28 (Agent roles and models). Adds one section, "Agent roles and models", to
`skills/workflow/SKILL.md` and replaces the one sentence in "Parallel work" that says which model to pass. Adds a
lint section and one smoke case in both shells. No config key (it reads the keys of iteration 10), no change to
the status flow, no script, no slot marker: none of `escalation.storyTriggers` applies, so the PR may auto-merge.
The change is in `skills/`, so the manual check of `verification.manualCheckPaths` applies.

## Goal

Every skill that launches an agent role resolves its model the same way: the role's model from the
configuration, else the default in the schema, passed explicitly on every launch and never inherited from the
session. When that model cannot be used, the run stops and says which role and which model.

## Facts this rests on

- Iteration 10 put `roles.<role>.model`, `models.ranking` and `review.maxFixRounds` in the schema, the example and
  this repository's config. Nothing reads them yet; this iteration is the first reader, and it is a rule in text,
  not code: the workflow skill is what every other skill follows.
- The schema holds the default of every role in `properties.roles.properties.<role>.properties.model.default`.
  The skill points at that key instead of repeating the seven defaults, so there is one place to change one.
- The Agent tool takes a `model` for the launch; it takes precedence over the `model:` in the agent
  definition's frontmatter, and a fork ignores it (a fork runs on the session's model). In the Claude Code
  version this spec was written with (checked 2026-11-05) the parameter lists four aliases (`haiku`, `sonnet`,
  `opus`, `fable`); whether a full model id is accepted is not assumed here. A name the tool refuses is a model
  that "cannot be used", handled by the rule below.
- Today only the `worker` agent is launched by a skill (`agents/worker.md`, `model: haiku`). `/spec`, `/next`
  and `/fix` do their work in the session. The stories that hand work to a subagent (#35, #38, and the review
  epics) follow this rule; until then it governs every launch that exists and the ones that will.
- `tests/lint.sh` already reads the schema and the configs with `scripts/lib/json.sh` (`json_keys`, `json_get`,
  `json_has`) and checks wording of skills with `grep -qF`.

## The section

Added to `skills/workflow/SKILL.md` between "Verify before every commit" and "Parallel work", under the exact
heading `## Agent roles and models`. The text is the contract; the phrases the lint looks for are listed under
"Tests".

```markdown
## Agent roles and models

Seven roles do the work of a story. Each runs as a subagent on the model the configuration gives it
(`roles.<role>.model`); the model of the session that orchestrates does not decide who writes or who reviews.

| Role | Does | Produces | Reviewed by |
|---|---|---|---|
| `specWriter` | writes the spec of a Ready story | the spec file | `specReviewer` |
| `specReviewer` | reviews a spec before it goes to Spec review | findings on the spec | the maintainer |
| `tester` | writes the failing tests from the approved spec, before the implementer | the tests | `codeReviewer`, with the change |
| `implementer` | writes the code of an Approved story | the change | `codeReviewer` |
| `codeReviewer` | reviews the change before the pull request opens | findings on the change | the maintainer |
| `fixer` | fixes a bug | the fix and its regression test | `codeReviewer` |
| `worker` | does a mechanical, fully specified job | the job's result, read back by the caller | the caller |

A reviewer ranks at least as high as each role it reviews: `specReviewer` over `specWriter`, `codeReviewer` over
`implementer` and `fixer`. `models.ranking` holds the order.

**Which model.** The model of a role R is `roles.R.model` when the configuration has it as a non-empty string;
otherwise the `default` of `properties.roles.properties.R.properties.model` in
`${CLAUDE_PLUGIN_ROOT}/schema/nightmill.schema.json`. Pass it explicitly as the `model` of the Agent call on every
launch of a role; a model is never inherited from the session, and a launch without one would run on it. A role
is never launched as a fork: a fork runs on the session's model whatever is passed. The `worker` agent follows
the same rule; the `model:` in `agents/worker.md` is only the default for a project without configuration and
equals the schema default.

**When the model cannot be used** (the launch is refused, the model is unknown, or this account cannot run it),
stop. Print `Stopped: the <role> role cannot run on <model>: <the reason>. Nothing was started on another model.`
and change nothing further; a status or file already changed stays, and the line says which. The maintainer fixes
`roles.<role>.model`. A skill never falls back to another model, not to the session's, not to a model of the same
level, not to the `worker`, because a reviewer must not drop below its producer unnoticed.

Work the session does itself is not a role. A role's work goes to a subagent only where a skill's own steps say so.
```

In "Parallel work", the bullet

> Prefer a fresh agent with a short, specific prompt over a fork. Always pass a model: the `worker`
> agent (cheap model) for mechanical, fully specified jobs; a strong model for specs and implementation.

becomes

> Prefer a fresh agent with a short, specific prompt over a fork. Give a role's agent the model that **Agent roles
> and models** gives it.

The other bullets of "Parallel work", including "queue or do the work inline otherwise", stay as they are: work
done inline is the session's own work, not a role (see the last line of the section).

## README

In the paragraph "Agent roles and models" (iteration 10), one sentence added at its end: the workflow skill
defines how a skill picks a role's model: the configured model, else the default of the schema, passed
explicitly; a model that cannot be used stops the run and is reported, never replaced.

## Tests

Each acceptance criterion of #33 is a test. Names are the behaviour protected.

**`tests/lint.sh`**, new section "== agent roles are defined in the workflow skill":

- `skills/workflow/SKILL.md` has a line that is exactly `## Agent roles and models`;
- that section (from the heading to the next `## ` line) names every key of the schema's
  `properties.roles.properties` in backticks, read with `json_keys`, so a role added to the schema and not to the
  skill fails the lint; this covers "names every role", the tester included;
- the section contains these phrases: `roles.<role>.model`, `properties.roles.properties.R.properties.model`,
  `schema/nightmill.schema.json`, `explicitly`, `never inherited from the session`, `never launched as a fork`,
  `Stopped: the <role> role cannot run on <model>`, `never falls back`, `Reviewed by`;
- the skill no longer contains `a strong model for specs and implementation` or `Always pass a model` (the old
  rule is replaced, not kept beside the new one);
- the `model:` line in the frontmatter of `agents/worker.md` equals the schema default of
  `roles.worker.model`, so "only the default for a project without configuration" stays true.

**`tests/smoke-validate.sh` and `tests/smoke-validate.ps1`**, one case each in the existing section that copies
the repository and runs its lint: "the lint notices a role the workflow skill does not name". In a fresh copy the
word `fixer` is replaced by `fix-er` in `skills/workflow/SKILL.md`; the lint must exit non-zero and its output
must name `fixer`. (The PowerShell test uses the bash it already finds for the existing lint case and skips like
that case when there is none.)

`bash tests/check.sh` stays green.

## Verification

The change touches `skills`, so the manual check applies. In a project that has nightmill installed from this
checkout (`claude --plugin-dir <checkout>`), load `/nightmill:workflow` and read the new section as a worker
would, then:

1. **Without config for the role.** The project config has no `roles` block. Ask the session to launch the
   `specWriter`; it names `opus` (the schema default) and passes it as the `model`.
2. **With config.** Set `roles.specWriter.model` to `sonnet`; the launch names `sonnet`. Set it to an empty string;
   the launch names `opus` again.
3. **The worker.** Ask for a mechanical job (move a board status and read it back); the `worker` agent is launched
   with `roles.worker.model` or `haiku`, explicitly.
4. **A model that cannot be used.** Set `roles.worker.model` to `no-such-model`; ask for the same job. The session
   prints the `Stopped:` line naming `worker` and `no-such-model`, and does not retry on another model.

The PR's "How verified" lists the four results and the check.

## Not done

- No skill other than the workflow skill changes. `/spec`, `/next` and `/fix` still do their work in the session;
  handing it to a subagent is #35, #38 and the review epics.
- No check that a reviewer ranks at least as high as its producer (#32), no `/models` table (#34).
- No translation of a full model id to an alias, and no probe that tests a model before a launch: the refusal at
  launch is the signal.
- `agents/worker.md` is not edited; the lint keeps its `model:` in step with the schema default.
- No change to the status flow, to who sets a status, or to any config key.
