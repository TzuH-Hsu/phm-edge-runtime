---
name: labels-and-taxonomy
description: Use when adding, renaming, or retiring labels — taxonomy governance.
category: governance
---

# Labels and Taxonomy

## Purpose

Labels are cheap to create and expensive to keep meaningful — every unused or duplicated label is a small tax on every triage session forever. This skill keeps `.github/labels.yml` as the one source of truth and the label set small enough to actually scan.

## Rules

1. **`.github/labels.yml` is the source of truth. The GitHub UI is a projection of it, not an editable copy.** Never create, rename, or recolor a label directly in the GitHub UI — edit the file, then sync:

   ```bash
   scripts/bootstrap.sh
   ```

   A label that exists on GitHub but not in the file is drift; the file wins on the next sync (see `.github/PROJECT_FIELDS.md`, "this file wins").
2. **Single-home check before adding any label** (ADR-0003): ask "does this fact already have a home?" — native issue type, a Project field, a milestone, or an existing label. If yes, do not add a label that duplicates it. Consult the authority map in `.github/PROJECT_FIELDS.md` first.
3. **Label budget**: this template ships 14 labels. A healthy small repo stays under roughly 25. Label-count creep is the single most common taxonomy failure — it happens one "just this once" label at a time, never as one bad decision.
4. **Add a label only if you will filter or automate on it.** If you can't name the `gh issue list --label` query or the workflow condition that would use it, it's documentation dressed up as taxonomy — write a sentence in the issue instead.
5. **Retiring a label is three steps, not one**: remove it from `.github/labels.yml`, delete it on GitHub (via the next `scripts/bootstrap.sh` sync or `gh label delete`), and note the removal in the PR description so the history is discoverable later.
6. **`area:*` labels are the intended adopter customization point.** The starter set (`area:docs`, `area:skills`, `area:ci`, `area:governance`) exists to be renamed to the adopter's real domains — keep the `area:` prefix so tooling and queries keep working, but the values are meant to change.
7. **Never encode workflow status in a label.** `Backlog`/`Ready`/`In Progress`/`In Review`/`Blocked`/`Done` belongs to the Project `Status` field — that's a single field with defined transitions; N status labels would be N independently-driftable booleans on the same fact.

## How

Add a label — edit the file, don't touch the UI:

```yaml
# .github/labels.yml
  - name: area:billing
    color: 1d76db
    description: Billing and payments domain
```

```bash
scripts/bootstrap.sh   # syncs GitHub labels to match the file
```

Audit for drift between the file and GitHub before assuming they match:

```bash
gh label list --json name,color,description --limit 200 > /tmp/github-labels.json
# diff against .github/labels.yml by eye or with a small script
```

Retire a label cleanly:

```bash
# 1. remove the entry from .github/labels.yml
# 2. delete on GitHub
gh label delete "area:legacy-name" --yes
# 3. mention it in the PR body: "Retires area:legacy-name — superseded by area:billing"
```

Check whether a candidate label already has a home before adding it:

```bash
grep -i "<the attribute you're about to label>" .github/PROJECT_FIELDS.md
```

## Pitfalls

- Creating a label in the GitHub UI "just to unblock triage right now" — it silently diverges from `.github/labels.yml` and gets wiped or conflicts on the next sync.
- Adding a `status:*` label set because a board view feels slow — that's a Project view problem, not a taxonomy problem; fix the view, not the labels.
- A second `priority` or `type` field appearing on the Project board that mirrors the labels — this is the exact ADR-0003 violation the contract file exists to catch in review.
- Letting `area:*` sprawl past a handful of values — if every PR needs a new `area:*` label, the domains are sliced too fine; consolidate.
- Deleting a label from GitHub without removing it from `.github/labels.yml` first — the next bootstrap run silently recreates it.

## Related

- `` `.github/labels.yml` `` — the declarative label source of truth
- `` `.github/PROJECT_FIELDS.md` `` — the metadata single-home authority map
- `` `docs/adr/ADR-0003-metadata-single-home.md` `` — the rationale and rejected alternatives
- `` `scripts/bootstrap.sh` `` — syncs labels, Project fields, and repo settings from the declared source
- `` `skills/adr-writing/SKILL.md` `` — when a repeated labeling debate should become an ADR instead of a one-off decision
