# ADR-0007: Retire the `agent-ok` / `by-agent` label mechanism

- **Status**: Accepted
- **Date**: 2026-09-07

## Context

The template shipped two labels for its AI-collaboration layer: `agent-ok` ("AI agents may pick this up self-service when Status is Ready") and `by-agent` ("authored by an AI agent, audit trail"). ADR-0003 listed agent eligibility among the facts labels own, and `AGENTS.md`, four skills, the issue forms, the labeler, and a hand-built "Agent queue" Project view all referred to them.

Two months of dogfooding showed both labels were write-only:

- `agent-ok` had exactly one producer — `issue-labeler.yml` copying a form checkbox — and no consumer. No workflow, ruleset, or Project automation read it. The queue view it fed cannot be created by bootstrap and was never verified to exist. In practice every piece of agent work was dispatched explicitly by a human; nothing was ever self-served from the queue.
- `by-agent` had neither producer nor consumer. It relied on the agent remembering a manual `gh pr edit --add-label` after opening the PR, which `skills/pr-authoring` itself named as the most common omission. Provenance already existed twice elsewhere: the `Co-Authored-By` commit trailer and the PR author account.

The labeler's ownership of `agent-ok` also had a side effect: because form-managed labels are removed when the form no longer selects them, a human who granted `agent-ok` by hand during triage lost it silently on the next issue edit — contradicting the skill text that described post-hoc granting.

## Decision

1. **Remove both labels with no successor.** They leave `.github/labels.yml`, the labeler, the issue forms, `PROJECT_FIELDS.md`, and every doc and skill that referenced them. The "Agent queue" view is dropped from `docs/setup/project-views.md`.
2. **The start-work rule is explicit human assignment.** An agent works an issue when a human assigns it or names it in the conversation. Project `Status` `Ready` means "scoped"; it no longer implies "claimable by agents".
3. **Provenance is the commit trailer and the PR author.** No label, and no attribution line in the PR body — the body carries validation claims, not authorship.
4. **ADR-0003 is not edited.** Its line listing "agent eligibility" among label-owned facts is historical; this ADR supersedes that clause only.

Principle 7 in `docs/template/design-principles.md` ("AI agents are first-class, humans stay in control") survives reworded: agents share the same issue, PR, and validation contract as humans and load the same skills; humans decide what agents work on and gate merges, releases, and destructive operations.

## Consequences

- Six downstream repositories carry the labels. They pick up the change by cherry-picking the template commit and then deleting the two labels with `gh label delete`. `scripts/bootstrap.sh --prune` is **not** the sync path: it deletes every label absent from `labels.yml`, including ones a downstream repo added by hand.
- Existing Projects keep the old `Ready` option description ("agent-ok issues are self-service here") until bootstrap is re-run against them; the text is cosmetic.
- The silent-removal bug in the labeler disappears with the label; `isFormManaged` now covers only `priority:*`, `area:*`, and the four form-owned `type:*` subtypes.
- The template no longer promises a self-service queue it never operated. Whoever later needs one has a clean slate and this record of why the label form of it failed.

## Alternatives considered

- **Keep both, fix the bugs** (remove `agent-ok` from `isFormManaged`, add a `by-agent` checkbox to the PR template). Rejected: fixing producers does not create a consumer; the labels would still gate nothing and record nothing another mechanism does not already record.
- **Replace `agent-ok` with a Project single-select field.** Rejected: a field has the same zero-consumer problem and adds a dual-home risk with `Status`. There is no self-service scenario to serve; YAGNI.
- **Replace `by-agent` with a fixed provenance line in the PR body.** Rejected: duplicates the commit trailer, and conflicts with the repository's rule that PR bodies carry no AI attribution.
