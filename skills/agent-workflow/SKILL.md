---
name: agent-workflow
description: Use when an AI agent picks up, executes, or hands off repository work — queue, boundaries, audit.
category: ai-collaboration
---

# Agent Workflow

## Purpose

Defines the contract that lets an AI agent operate here without a human
babysitting every step: what it may claim unasked, where its authority stops,
and how its work stays auditable. Trust is granted one issue at a time, never
blanket across the repository.

## Rules

1. **Self-serve only the queue.** An issue is claimable without asking iff it
   carries the `agent-ok` label AND its Project `Status` is `Ready`. Everything
   else needs an explicit human request naming the work.
2. **Claim before working.** Claiming = set Status `In Progress` and comment on
   the issue that you are taking it. No silent claims; two agents must never
   discover mid-flight they grabbed the same issue.
3. **Grant `agent-ok` only when the work is safe to hand off.** Crisp scope,
   testable acceptance criteria, non-destructive. Withhold it for ambiguous
   scope, security-sensitive changes, destructive operations, or any judgment
   call the human has not yet made — labelling those `agent-ok` is the bug.
4. **Stay inside capability boundaries.** Free via `gh`: issues, labels,
   milestones, Project items, branches, PRs. Forbidden without in-conversation
   human approval: force-push, history rewrite, deleting Project fields or
   labels repo-wide, repo settings changes, cutting releases.
5. **Leave an audit trail.** Label every agent-authored PR `by-agent` and state
   in the body exactly what you validated (see rule 6). Reviewers read agent
   success as a *claim*, not a fact.
6. **Report honestly, including what you did not do.** Never over-claim success
   — that is the canonical agent failure. A skipped validation level is a
   `RISK:` line, never silence.
7. **Stop after the second failure.** Stuck twice on the same task, stop and
   report what you tried. Do not spend a third attempt in the same loop.
8. **One checkout per agent.** Parallel agents each work in their own
   worktree/branch; never share a checkout. Conflicting PRs land sequentially.

## How

Claim from the queue:

```bash
gh issue list --label agent-ok --json number,title   # find candidates
# confirm Status is Ready on the Project board, then:
gh issue comment 42 --body "Claiming — starting work on a feat/42 branch."
# set Project Status -> In Progress, branch feat/42-<slug>, open PR with by-agent
```

The honesty ladder in a PR body — claim only the rung you actually reached:

```text
Validated:
- L0 lint: make lint (green)
- L1 unit: make test (green)
RISK: L3 e2e not run — no preview environment available for this change.
```

Escalation is a change of tool, not a retry: after two failures a human moves
the task to a stronger model or a different agent family, feeding forward the
tried-and-failed notes — never the same agent, same prompt, third time.

Parallel agents queue conflicting PRs instead of ping-pong rebasing: land PR A,
then rebase and land PR B. Two agents force-pushing one branch is chaos.

## Pitfalls

- Claiming an issue that lacks `agent-ok` because it "looks easy" — the label is
  the gate, not your read of difficulty.
- Setting Status `In Progress` but never commenting, so a human cannot tell a
  live claim from a stale one.
- Burying a skipped validation level instead of writing the `RISK:` line — a
  reviewer who trusts silent success merges a hole.
- Retrying a failing task a third time instead of escalating to a different
  model or family.
- Two agents on one branch, or an agent deleting a shared label to "clean up"
  without approval.

## Related

- `AGENTS.md` — canonical agent conventions
- `` `.github/PROJECT_FIELDS.md` `` — where `agent-ok`/`by-agent`/`Status` live
- `` `skills/context-handoff/SKILL.md` `` — pausing and resuming work across sessions
- `` `skills/pr-authoring/SKILL.md` `` — PR body and `RISK:` conventions
- `` `skills/validation-ladder/SKILL.md` `` — the L0–L4+ validation levels
