---
name: issue-writing
description: Use when creating or triaging an issue — forms, metadata contract, acceptance criteria.
category: planning
---

# Issue Writing

## Purpose

Every unit of work starts as an issue with unambiguous scope and a metadata footprint
that has exactly one home per attribute. A well-formed issue is what makes an item
safe to hand to an AI agent without a live conversation.

## Rules

1. Always use an issue form (Bug / Feature / Task) — never open a blank issue. The
   form you pick sets the native GitHub issue type; that type is authoritative.
2. Never hand-add a label the form already captures. Priority (`priority:*`) and area
   (`area:*`) come from the form's own fields — duplicating them manually creates a
   second, driftable copy of the same fact.
3. Respect the single-home contract in `.github/PROJECT_FIELDS.md` for every other
   attribute too: status lives on the Project board, version on the milestone,
   dependencies and epics as native relationships. Don't invent a label or field that
   mirrors one of those homes.
4. Every issue needs, at minimum: a one-line summary, enough context for a reader with
   no prior conversation, and testable acceptance criteria as a `- [ ]` checklist.
   "Testable" means each line has an unambiguous pass/fail, not a vibe.
5. Express dependencies with native blocked-by/blocking relationships, not a
   `blocked` label or a sentence buried in the description. Express epics with native
   sub-issues, not an `epic:*` label.
6. Triaging an existing issue means tightening it to meet rules 1–5, not just
   re-labeling it. If acceptance criteria are missing or untestable, add them before
   moving status off `Backlog`.

## How

```bash
# Create via form (interactive) — always prefer this over `gh issue create` freehand
gh issue create --repo <owner>/<repo>

# Inspect an issue's current metadata footprint before triaging
gh issue view 42 --repo <owner>/<repo> --json title,labels,milestone,body
```

Good acceptance criteria read like a test plan:

```markdown
- [ ] `make verify` passes on a fresh clone
- [ ] `gh issue create` via the Feature form produces a native `Feature` type issue
- [ ] No `type:*`, `priority:*`, or `area:*` label is missing after form submission
```

Bad acceptance criteria ("works correctly", "improve performance") give an agent or a
reviewer nothing to check against — rewrite before handing the issue to anyone.

## Pitfalls

- Adding a `priority:p1` label by hand "just to be safe" when the form already set it
  — now there are two sources and they can disagree.
- Writing acceptance criteria as a restatement of the summary instead of a checklist
  a reviewer can tick off one by one.
- Handing an agent an issue whose "acceptance criteria" is really "figure out the
  right approach" — that is a human-judgment task; resolve it in the issue first.
- Using an `epic:*` label or a "blocked by #12" sentence instead of native sub-issues
  and blocked-by links — invisible to automation and easy to let go stale.
- Opening a blank issue to "save time" — it skips native type assignment and the
  priority/area fields entirely, pushing the cleanup onto triage later.

## Related

- `` `.github/PROJECT_FIELDS.md` `` — the authority map this skill enforces
- `` `docs/adr/ADR-0003-metadata-single-home.md` `` — rationale for single-home metadata
- `CONTRIBUTING.md` — human-facing issue workflow summary
- `` `skills/milestone-planning/SKILL.md` `` — what happens after an issue is scoped
- `` `skills/branch-and-commit/SKILL.md` `` — starting work once an issue is ready
