# ADR-0003: Metadata single-home policy

- **Status**: Accepted
- **Date**: 2026-07-03

## Context

GitHub offers at least five places to store the same fact about an issue: labels, native issue types, Projects fields, milestones, and free text. Repos naturally accrete duplicates — a `type:bug` label *and* a native `Bug` type *and* a Project "Type" field. Once a fact has two homes, they diverge: boards filter on the stale copy, agents write one and not the other, and audits become manual. One of the reference projects paid a full migration to undo exactly this.

Small teams and AI agents both need the same property: **one write, one read location per attribute**, cheap to script via `gh`.

## Decision

Every metadata attribute has exactly one home, recorded in `.github/PROJECT_FIELDS.md` (the authority map). Highlights:

- **Native issue types** (`Bug`/`Feature`/`Task`) are the coarse type — set by issue forms, not labels. `type:*` labels exist only as Task subtypes (`chore`/`ops`/`docs`/`security`).
- **Labels** hold facts an agent can write in one `gh` call: priority, area, subtype, agent eligibility.
- **Project fields** hold board workflow state only: `Status`, `Effort`. No Priority/Area/Type fields on the Project — those would mirror labels.
- **Milestones** are the only home for target version/phase; no milestone means backlog.
- **Native relationships** (blocked-by, sub-issues) replace `blocked`/`epic:*` labels.

Labels themselves are declared in `.github/labels.yml`; syncing them is a re-run of `scripts/bootstrap.sh`, so the file in git stays the source of truth.

## Consequences

- Filtering and automation are deterministic: every query has exactly one predicate per attribute.
- The Project stays at two custom fields, which is what keeps board maintenance near zero.
- Discipline point: well-meaning contributors adding a "Priority" Project field is the most likely violation — the contract file exists to make that a reviewable offense, and `skills/labels-and-taxonomy/` explains the reasoning.

## Alternatives considered

- **Labels for everything (including status)** — status churn generates label noise on the timeline and requires N status labels; Projects boards already model workflow state natively.
- **Project fields for everything** — fields aren't visible on the issue list, aren't one-call scriptable (GraphQL item mutations), and don't survive repo forks; labels are the cheaper write path.
- **Convention without a contract file** — proven insufficient in the reference projects; the drift happened precisely because no file said "this is the only home".
