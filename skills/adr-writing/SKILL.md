---
name: adr-writing
description: Use when a decision needs a durable record — triggers, format, lifecycle.
category: governance
---

# ADR Writing

## Purpose

Decisions made in a PR thread or a chat session evaporate — the context window closes, the thread scrolls away, and six weeks later the same debate reopens or an agent "helpfully" reverts something that was deliberate. An ADR is the cheap countermeasure, but only for decisions that clear a real bar.

## Rules

1. **Write an ADR when a decision meets any of three triggers**: it **crosses boundaries** (affects more than one part of the system or process), it's **hard to reverse** (undoing it later is expensive or disruptive), or it **keeps coming back** (the same debate has happened more than once). One trigger is enough.
2. **Below the bar, don't write one.** A library patch bump, a wording tweak, a one-off implementation choice with no lasting consequence — decide it in the issue or PR thread and move on. Writing an ADR for everything dilutes the signal of the ones that matter.
3. **Write the ADR in the same PR that implements (or proposes) the decision.** A decision record written after the fact, in a separate PR, tends not to get written at all.
4. **Use `docs/adr/template.md`** — Status / Date / Issue / Context / Decision / Consequences / Alternatives. Specifically:
   - **Context** states the forces at play — why this needed a decision at all, not just background.
   - **Decision** is written as a fact ("We use X for Y"), not a proposal or a debate summary.
   - **Consequences** names what becomes easier *and* what becomes harder — an ADR that only lists benefits is marketing, not a decision record. Include accepted costs explicitly.
   - **Alternatives considered** names each real alternative and *why not*, not just "we could have also...".
5. **Status lifecycle is one-directional**: `Proposed` → `Accepted` → (eventually) `Superseded by ADR-XXXX` or `Deprecated`. **Never edit an old ADR's Decision/Consequences to reflect a new choice, and never delete one.** Write a new ADR that supersedes it and update the old one's status line to point at the new number. History has to stay legible.
6. **Keep it under a page.** If the Context section needs subheadings, the decision is probably two decisions — split it.
7. **Update `docs/adr/README.md`'s index table in the same PR.** An ADR not in the index is functionally undiscoverable.
8. **Agents: read the relevant ADRs before changing behavior adjacent to one.** An ADR is a "do not helpfully fix this" fence — if a decision looks locally suboptimal but an ADR explains why it's that way on purpose, that's a signal to stop and ask, not to improve it silently.

## How

Start a new ADR from the template, numbered sequentially:

```bash
cp docs/adr/template.md docs/adr/ADR-0004-short-slug.md
# fill in Status: Proposed, Date, and the four sections
```

Check for an existing decision before assuming one is needed:

```bash
ls docs/adr/
grep -ril "release" docs/adr/   # e.g. before writing a new release-process ADR
```

Supersede an existing ADR instead of editing it:

```markdown
<!-- in ADR-0002, change only the Status line -->
- **Status**: Superseded by ADR-0007
```

Add the new ADR to the index in the same PR:

```markdown
| [ADR-0004](ADR-0004-short-slug.md) | Short title | Accepted |
```

Before touching code adjacent to a documented decision, check whether an ADR governs it:

```bash
grep -ril "<the area you're about to change>" docs/adr/
```

## Pitfalls

- Writing an ADR for a decision nobody will re-litigate — it adds ceremony without adding durability where it isn't needed; use the three-trigger test, not "seems important."
- Editing an old ADR's Decision section to match a new approach — this destroys the historical record; supersede instead.
- An ADR with only upside in Consequences — if there's no accepted cost, the analysis is incomplete, not the decision perfect.
- Forgetting the `docs/adr/README.md` index update — the most common reason an ADR silently stops being found by future readers (human or agent).
- An agent "fixing" code that contradicts an ADR without reading the ADR first — the deviation may be intentional; read before changing, and flag a conflict rather than resolving it unilaterally.
- Letting Context balloon into multi-paragraph history — two or three paragraphs at most; if it needs more, the decision needs splitting.

## Related

- `` `docs/adr/template.md` `` — the exact section structure to copy
- `` `docs/adr/README.md` `` — trigger criteria (source for this skill's Rule 1) and the ADR index
- `` `docs/adr/ADR-0001-adopt-adr.md` `` — the ADR that establishes this process (read it as a worked example)
- `` `docs/adr/ADR-0002-release-flow.md` ``, `` `docs/adr/ADR-0003-metadata-single-home.md` `` — further worked examples of Context/Decision/Consequences/Alternatives
- `` `skills/incident-response/SKILL.md` `` — when a postmortem's prevention step should be promoted to an ADR
