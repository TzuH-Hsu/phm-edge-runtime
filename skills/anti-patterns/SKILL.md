---
name: anti-patterns
description: Use when reviewing repository health or designing process — named failure modes and their fixes.
category: ai-collaboration
---

# Anti-Patterns

## Purpose

A catalog of the specific ways a GitHub-native, agent-driven repo rots. Each
entry names the failure, its symptom, why it recurs, and the mechanism in this
template that prevents it. Use it as a review lens and as the "why" behind the
template's opinionated defaults.

## Rules

1. Treat every entry as a review checkpoint, not trivia — if you can name the
   symptom in the repo, the fix already exists here; apply it.
2. When you catch a new recurring failure, add it here with a fix that points at
   a concrete mechanism, not a good intention.

## How

Each entry: symptom → why it happens → the fix (this repo's mechanism).

| Anti-pattern | Symptom | Why it happens | Fix (mechanism) |
| --- | --- | --- | --- |
| Label explosion | 40+ labels, half never used | Every ad-hoc need spawns a label; none retired | `labels.yml` budget + single-home + retire ritual (`labels-and-taxonomy`) |
| Dual-home metadata | Same fact in a label *and* a Project field | Two tools each feel natural; nobody picks one | `PROJECT_FIELDS.md` authority map — one home per attribute (ADR-0003) |
| Workflow sprawl | Near-duplicate workflows, setup steps drift | Copy-paste a workflow to tweak one step | Logic in `make` targets; workflow-count budget + justification rule (`github-actions-hygiene`) |
| Handoff bloat | Append-only session memory, 600+ lines | Appending feels safer than rewriting | One `HANDOVER.local.md`, ~150-line cap, rewrite (`context-handoff`) |
| Documentation drift | Docs describe the system that used to exist | Code changed; the doc two folders away didn't | One-home-per-fact linking, CI link checks, delete-in-obsoleting-PR (`docs-hygiene`) |
| Silent validation skip | "tests didn't apply" said nowhere | Skipping is quiet; declaring feels like admitting fault | `RISK:` line convention — every skipped level is stated (`validation-ladder`) |
| Deadline refactor cramming | Big refactor jammed into a release under pressure | "While we're in here" scope-creep near a cut | Refactors get their own milestone; timebox kills scope, not the deadline (`milestone-planning`) |
| Agent over-trust | Merging agent PRs on the agent's own success claim | Green-looking summary reads like proof | `by-agent` label + claims-are-claims review + cross-family review (`agent-workflow`) |

Reading an entry in the wild:

```text
Symptom : board filters on `priority:p1` but the "Priority" Project field says p2
Name    : Dual-home metadata
Fix     : delete the Project Priority field; label is the single home (ADR-0003)
```

Agent over-trust is the one that scales with agent adoption — the same model
that wrote the code is the worst judge of whether it works. The counter is
structural: a `by-agent` label flags provenance, review treats the PR body as
claims to verify, and a *different* agent family (or a human) does the check.

## Pitfalls

- Fixing the symptom without the mechanism — deleting three labels by hand but
  not adopting the budget, so they grow back next month.
- Adding a ninth entry that prescribes "be careful" instead of a mechanism; a
  fix that cannot be reviewed is not a fix.
- Reading this as a one-time audit. These accrete continuously; the lens is for
  every review, not a spring cleaning.

## The meta-rule

Every one of these is a **ratchet**: cheap to prevent on day one, expensive to
undo at month six. One extra label costs nothing; retiring forty after they have
grown board filters, saved searches, and muscle memory costs a migration. That
asymmetry — trivial to prevent, painful to reverse — is the entire reason this
template ships opinionated defaults instead of leaving them to taste.

## Related

- `` `.github/PROJECT_FIELDS.md` `` — the single-home authority map
- `` `docs/adr/ADR-0003-metadata-single-home.md` `` — dual-home rationale
- `` `skills/labels-and-taxonomy/SKILL.md` `` — label budget and retire ritual
- `` `skills/github-actions-hygiene/SKILL.md` `` — workflow-count budget
- `` `skills/docs-hygiene/SKILL.md` `` — documentation-drift prevention
- `` `skills/validation-ladder/SKILL.md` `` — the `RISK:` convention
- `` `skills/agent-workflow/SKILL.md` `` — agent over-trust countermeasures
- `` `skills/context-handoff/SKILL.md` `` — handoff-bloat rules
