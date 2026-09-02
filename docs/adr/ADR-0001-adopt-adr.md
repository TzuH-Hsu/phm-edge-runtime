# ADR-0001: Adopt Architecture Decision Records

- **Status**: Accepted
- **Date**: 2026-07-03

## Context

Small teams and AI agents share one failure mode: decisions evaporate. A choice gets made in a PR thread or a chat session, the context window closes, and six weeks later the same debate reopens — or worse, an agent "fixes" something that was deliberate. Written decision records are the cheapest known countermeasure, but only if the bar for writing one is clear enough that they actually get written.

## Decision

We keep Architecture Decision Records in `docs/adr/`, numbered `ADR-NNNN-short-slug.md`, using `template.md` (Status / Date / Context / Decision / Consequences / Alternatives).

An ADR is required when a decision meets any of: **crosses boundaries**, **hard to reverse**, or **keeps coming back**. Anything below that bar stays in the issue or PR that decided it.

ADRs are immutable history: they get superseded, never edited into a different decision or deleted.

## Consequences

- New contributors and AI agents can read *why* before changing *what* — `AGENTS.md` and skills link to ADRs instead of restating rationale.
- Writing an ADR adds ~15 minutes to qualifying decisions; the trigger criteria keep this rare.
- The index in `docs/adr/README.md` must be updated with each ADR (enforced by review, and by the docs link check).

## Alternatives considered

- **Decision log in one big file** — append-only files bloat, get skimmed, and merge-conflict; per-decision files link cleanly from issues and skills.
- **Decisions live in issues only** — issues are where debate happens, but they're unstructured and hard to find after closure; ADRs are the distilled output.
- **No formal records** — proven failure mode in the reference projects this template distills: re-litigated choices and agent-reverted intentional trade-offs.
