# Skills

Skills are focused knowledge modules for humans and AI agents. Each skill covers a single recurring task type (writing issues, reviewing code, planning releases, etc.) and bundles its rules, worked examples, and pitfalls in one discoverable place.

Load a skill only when its "use when" condition matches your current task — do not bulk-load the entire catalog into your context. The index below and the AGENTS.md pointer tell you which skill to reach for right now.

Each skill lives in its own directory with a `SKILL.md` file containing frontmatter (name, description, category) and the skill content. The index below is wired with the frontmatter schema; [AGENTS.md](../AGENTS.md) is the canonical entry point for agents.

| Skill | Category | Use when |
| --- | --- | --- |
| [agent-workflow](agent-workflow/SKILL.md) | ai-collaboration | An AI agent picks up, executes, or hands off repository work — queue, boundaries, audit. |
| [anti-patterns](anti-patterns/SKILL.md) | ai-collaboration | Reviewing repository health or designing process — named failure modes and their fixes. |
| [context-handoff](context-handoff/SKILL.md) | ai-collaboration | Pausing, resuming, or handing off work across sessions — handoff file discipline. |
| [branch-and-commit](branch-and-commit/SKILL.md) | delivery | Starting work — branch naming, Conventional Commits, issue linkage. |
| [code-review](code-review/SKILL.md) | delivery | Reviewing a PR or deciding whether to self-merge — tiny-team review practice. |
| [pr-authoring](pr-authoring/SKILL.md) | delivery | Opening or updating a pull request — structure, validation ladder, RISK lines. |
| [adr-writing](adr-writing/SKILL.md) | governance | A decision needs a durable record — triggers, format, lifecycle. |
| [docs-hygiene](docs-hygiene/SKILL.md) | governance | Adding or restructuring documentation — placement, linking, drift prevention. |
| [labels-and-taxonomy](labels-and-taxonomy/SKILL.md) | governance | Adding, renaming, or retiring labels — taxonomy governance. |
| [issue-writing](issue-writing/SKILL.md) | planning | Creating or triaging an issue — forms, metadata contract, acceptance criteria. |
| [milestone-planning](milestone-planning/SKILL.md) | planning | Planning releases or process phases — milestone discipline and scope control. |
| [github-actions-hygiene](github-actions-hygiene/SKILL.md) | quality | Writing or reviewing GitHub Actions workflows — security and maintainability rules. |
| [incident-response](incident-response/SKILL.md) | quality | Something broke — triage, fix-forward, postmortem-lite. |
| [validation-ladder](validation-ladder/SKILL.md) | quality | Choosing how much validation a change needs — ladder levels, stages, extensions. |
| [release-management](release-management/SKILL.md) | release | Cutting a release or changing release cadence — release-please flow and alternatives. |

## Adding a skill

To add a new skill:

1. Copy an existing skill's directory structure as your template.
2. Create `skills/<name>/SKILL.md` with the frontmatter schema:

   ```markdown
   ---
   name: <name>
   description: Use when <condition> — <short summary>.
   category: <one of: planning, delivery, quality, release, governance, ai-collaboration>
   ---
   ```

3. Add the skill to this README's table (keep it sorted by category enum order, then alphabetically within category).
4. Add a row to the Skills index table in [`AGENTS.md`](../AGENTS.md) with the same format.
5. Run `make check` to validate that all frontmatter, index rows, and links are consistent.
