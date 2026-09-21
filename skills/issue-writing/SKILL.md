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
   Non-interactively (an agent, a script — anything that cannot answer the form's
   prompts), write the body in the shape the form would have rendered (see
   "Non-interactive: no form" below). The labeler reads that shape, not the form.
2. Never hand-add a label the form already captures. Priority (`priority:*`) and area
   (`area:*`) come from the form's own fields — duplicating them manually creates a
   second, driftable copy of the same fact. It also does not stick: the labeler owns
   those families and removes any `priority:*` / `area:*` it cannot derive from the
   body's `### Priority` / `### Area` sections on the next edit.
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

### Non-interactive: no form

`gh issue create --title … --body …` skips the form entirely: no native type, and a
body with none of the form's sections, so the labeler has nothing to sync and the
issue ends up with no labels at all. Compose the body the way the form would have
rendered it — a `### <Field label>` heading per field, the option text exactly as
the form lists it — and the labeler applies `priority:*` / `area:*` / `type:*` on
the `opened` event:

```bash
gh issue create --repo <owner>/<repo> --title "Task: …" --body "$(printf '%s\n' \
  '### Summary' '' 'One line.' '' \
  '### Subtype' '' 'docs — Documentation' '' \
  '### Context' '' 'Enough for a reader with no prior conversation.' '' \
  '### Acceptance criteria' '' '- [ ] `make verify` passes' '' \
  '### Priority' '' 'p2 — Important, scheduled' '' \
  '### Area' '' '- [x] <area:name — description, exactly as the Area option reads in .github/ISSUE_TEMPLATE/task.yml>')"
```

The headings are the forms' `label:` values (`Priority`, `Area`, `Subtype` — pinned by
`scripts/check-label-forms.sh`); the option lines are the forms' own, so the labeler
resolves them against its allowlists. `### Subtype` exists only on the Task form.

The native issue type is separate. On an **organization** repository add
`--type Task` (or `--type Bug` / `--type Feature`, matching the form you are imitating) — that is what the form would have set. On a **personal**
account leave it out: `gh` **creates the issue, then fails** to set the type and
exits 1 with `type "Task" not found; available types:` and no URL (GitHub reports
no types there — see `.github/PROJECT_FIELDS.md`, "When native issue types are
unavailable"), so a script that retries on failure opens duplicates. There the default is no coarse Type at all; only if the
adopter has uncommented the `type:bug` / `type:feature` block in `labels.yml` and
re-run bootstrap do you apply one of those by hand — the one label family the
labeler leaves alone.

Good acceptance criteria read like a test plan:

```markdown
- [ ] `make verify` passes on a fresh clone
- [ ] `gh issue create` via the Feature form produces a native `Feature` type issue
- [ ] No `type:*`, `priority:*`, or `area:*` label is missing after form submission
- [ ] An issue opened with `--body` in the form's shape carries `priority:*` and
      `area:*` after the labeler run
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
- An agent opening issues with `--body` prose and no `### Priority` / `### Area`
  sections — every such issue is label-less, and adding the labels by hand only lasts
  until the next edit. Use the form-shaped body above.

## Related

- `` `.github/PROJECT_FIELDS.md` `` — the authority map this skill enforces
- `` `docs/adr/ADR-0003-metadata-single-home.md` `` — rationale for single-home metadata
- `CONTRIBUTING.md` — human-facing issue workflow summary
- `` `skills/milestone-planning/SKILL.md` `` — what happens after an issue is scoped
- `` `skills/branch-and-commit/SKILL.md` `` — starting work once an issue is ready
