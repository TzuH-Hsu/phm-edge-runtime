---
name: milestone-planning
description: Use when planning releases or process phases — milestone discipline and scope control.
category: planning
---

# Milestone Planning

## Purpose

A milestone is the only home for "what ships when" — assigning one is a commitment,
not a wishlist entry. This skill keeps milestones small, honest, and resistant to the
scope creep that turns a release date into a moving target.

## Rules

1. Milestones are exactly `M1`–`M4`, the delivery checkpoints, created by hand with
   their due dates (`.github/PROJECT_FIELDS.md`). No milestone means backlog — not
   yet committed to anything. Do not create other milestones: release versions
   belong to release-please, not to milestones.
2. Assigning a milestone is a commitment, not a bucket for someday-maybe work. Only
   attach an issue once the team actually intends to finish it by that
   checkpoint. Pull backlog items in when capacity opens up; don't pre-load a milestone
   with wishes.
3. When a milestone's date is fixed, the date is the constant and scope is the
   variable. If a milestone is at risk, cut issues out of it (back to backlog or a
   later milestone) — never quietly extend the deadline to protect the original
   scope.
4. Refactors get their own milestone, later. Never cram a refactor into a release
   train that is already under deadline pressure — mixing "ship a deadline" with
   "restructure the code" is how both go badly. Give the refactor its own issue
   in a later checkpoint, or keep it in backlog.
5. Define exit criteria before opening a milestone, not while closing it. Write down
   what "done" means for the checkpoint — which issues, which validation levels —
   so scoping decisions during the milestone have a fixed target to check against.
6. Plan against the current checkpoint and the next one. Later checkpoints hold
   only issues already committed to them; anything else stays in backlog.

## How

```bash
# List the checkpoints and their due dates
gh api "repos/<owner>/<repo>/milestones?state=all" --jq '.[] | "\(.title) \(.due_on)"'

# See what's committed to a milestone right now
gh issue list --repo <owner>/<repo> --milestone "M2"

# Cut scope: move an at-risk issue back to backlog (clear the milestone)
gh issue edit 87 --repo <owner>/<repo> --milestone ""

# Move it to a later milestone instead of dropping it
gh issue edit 87 --repo <owner>/<repo> --milestone "M3"
```

## Pitfalls

- Assigning every open Feature issue to the next milestone "to keep options open" —
  this is exactly the wishlist anti-pattern rule 2 forbids; assign only real
  commitments.
- Sliding a milestone's due date instead of cutting scope when the deadline
  approaches — the timebox exists to force scope decisions, not to be renegotiated.
- Bundling a large refactor into the same release as feature work under deadline
  pressure — this is the specific failure this skill exists to prevent; split it out.
- Opening a milestone with no written exit criteria, then arguing about "done" at the
  end — define it up front.
- Creating a milestone outside `M1`–`M4` (a `vX.Y.Z` or `gov-*` one) — release
  versions belong to release-please, and a stray milestone splits the plan.

## Related

- `CONTRIBUTING.md` — milestone taxonomy summary
- `` `.github/PROJECT_FIELDS.md` `` — milestone as the single home for target version
- `` `docs/adr/ADR-0002-release-flow.md` `` — how milestones connect to release-please
- `` `skills/issue-writing/SKILL.md` `` — scoping issues before they enter a milestone
- `` `skills/pr-authoring/SKILL.md` `` — landing the work a milestone commits to
