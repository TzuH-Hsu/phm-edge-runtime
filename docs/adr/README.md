# Architecture Decision Records

ADRs capture decisions that would otherwise be re-litigated, forgotten, or cargo-culted. They record **why**, not just what.

## When to write one

Write an ADR when a decision meets **any** of these criteria:

1. **Crosses boundaries** — affects more than one part of the system or process.
2. **Hard to reverse** — undoing it later would be expensive or disruptive.
3. **Keeps coming back** — the same debate has happened more than once.

Routine choices (a library patch bump, a wording tweak) do not get ADRs. When in doubt, see `skills/adr-writing/`.

## How

1. Copy `template.md` to `ADR-NNNN-short-slug.md` (next free number).
2. Write it in the PR that implements (or proposes) the decision.
3. Status lifecycle: `Proposed` → `Accepted` → (later) `Superseded by ADR-XXXX` or `Deprecated`. Never delete an ADR — supersede it.

## Index

| ADR | Title | Status |
| --- | --- | --- |
| [ADR-0001](ADR-0001-adopt-adr.md) | Adopt Architecture Decision Records | Accepted |
| [ADR-0002](ADR-0002-release-flow.md) | Release flow: release-please with human-gated release PRs | Accepted |
| [ADR-0003](ADR-0003-metadata-single-home.md) | Metadata single-home policy | Accepted |
