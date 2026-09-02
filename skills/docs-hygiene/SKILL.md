---
name: docs-hygiene
description: Use when adding or restructuring documentation — placement, linking, drift prevention.
category: governance
---

# Docs Hygiene

## Purpose

Documentation rots by duplication, not by neglect — the first copy is fine, the second copy is where drift starts. This skill gives a placement decision tree and the rules that keep every fact in exactly one file.

## Rules

1. **Placement decision tree** — pick the first match:
   - Agent/contributor contract (what any agent or contributor must do) → `AGENTS.md`
   - Human-facing process (how a person works day to day) → `CONTRIBUTING.md`
   - Rationale for a specific decision → `docs/adr/`
   - Reusable know-how applicable across tasks → `skills/`
   - Setup steps or an operational runbook → `docs/setup/`
   - If it fits none of these, question whether it should exist as a doc at all — it may belong as a code comment, an issue, or nowhere.
2. **One home per fact. Link, never copy.** If a fact already lives somewhere (a rule in `AGENTS.md`, a decision in an ADR, a label rule in `.github/PROJECT_FIELDS.md`), reference it by relative link. The moment a fact exists in two files, one of them will go stale — drift starts at the *second* copy, not the tenth.
3. **Links are checked, not aspirational.** Internal links are validated offline by `lychee` in `make lint-docs` on every PR; external links are checked on a weekly schedule (see `lychee.toml`). A broken link is a failing build — fix the path or remove the link, don't leave it red.
4. **Every doc needs an implicit or explicit owner-of-truth statement**: which file wins if this doc and another one disagree. `AGENTS.md` is the global winner — it says so explicitly ("This file is the single source of truth. If guidance conflicts anywhere else, AGENTS.md wins"). Domain-specific docs (an ADR, a skill) win within their narrow domain but defer to `AGENTS.md` on anything it also covers.
5. **Docs die.** When a doc stops being read or stops being true, delete it in the same PR that makes it obsolete — don't leave it for a later cleanup pass that never comes. A stale doc actively misleads; a missing doc merely requires asking.
6. **Keep files under roughly 150 lines.** Split by audience, not by shaving topic depth — e.g. `AGENTS.md` (agents/contract) vs `CONTRIBUTING.md` (humans/process) covering the same territory from different angles, rather than one 300-line file trying to serve both.

## How

Before writing a new doc, run the placement check:

```text
Is this a rule every agent/contributor must follow?      -> AGENTS.md
Is this a human workflow step (not agent-binding)?        -> CONTRIBUTING.md
Am I explaining *why* a decision was made?                -> docs/adr/
Is this reusable knowledge for a recurring task type?      -> skills/<name>/SKILL.md
Is this "how to set up X" or "what to do when Y breaks"?   -> docs/setup/
None of the above -> reconsider whether it should exist
```

Link instead of copying a fact:

```markdown
<!-- wrong: restating the ladder -->
Run lint, then run tests, then...

<!-- right: point at the one true definition -->
See the validation ladder in `AGENTS.md` and `skills/validation-ladder/`.
```

Run the same link check CI runs, locally, before pushing:

```bash
make lint-docs   # markdownlint-cli2 + yamllint + lychee --offline
```

Delete a stale doc as part of the PR that obsoletes it, not a follow-up:

```bash
git rm docs/setup/old-flow.md
# ...and update any file that linked to it
```

## Pitfalls

- Restating `AGENTS.md` rules inside a skill "for convenience" — the copy immediately starts drifting the next time `AGENTS.md` changes; link to the section instead.
- Adding a new top-level doc when the fact belongs inside an existing one — check the placement tree before creating a file.
- Leaving a dead link after a file move/rename — `lychee --offline` catches this in CI; don't rely on catching it by eye.
- Writing a 400-line doc that tries to serve both agents and humans at once — split by audience (`AGENTS.md` vs `CONTRIBUTING.md`) instead of length-limiting a single sprawling file.
- Keeping an obviously stale doc around "in case someone needs it" — if it's wrong, it actively harms the next reader (human or agent) more than having no doc at all.
- A doc with no clear owner-of-truth when it overlaps another — silent conflicts between two docs are worse than one doc being wrong, because nobody knows which to trust.

## Related

- `AGENTS.md` — the global owner-of-truth; "This file is the single source of truth"
- `CONTRIBUTING.md` — the human-process counterpart to `AGENTS.md`
- `` `docs/adr/` `` — decision rationale placement, cross-referenced from `` `skills/adr-writing/SKILL.md` ``
- `Makefile` — `lint-docs` target (markdownlint, yamllint, lychee)
- `` `lychee.toml` ``, `` `.markdownlint.jsonc` ``, `` `.yamllint.yml` `` — the actual lint configuration enforcing these rules
- `` `skills/labels-and-taxonomy/SKILL.md` `` — a worked example of "one home per fact" applied to a different domain
