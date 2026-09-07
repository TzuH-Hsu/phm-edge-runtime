---
name: agent-workflow
description: Use when an AI agent picks up, executes, or hands off repository work — assignment, boundaries, honest reporting.
category: ai-collaboration
---

# Agent Workflow

## Purpose

Defines the contract that lets an AI agent operate here without a human
babysitting every step: when it may start, where its authority stops,
and how its work stays auditable. Trust is granted one issue at a time, never
blanket across the repository.

## Rules

1. **Work only what a human handed you.** An issue is yours when a human
   assigns it or names it in the conversation. There is no self-service queue:
   Project `Status` `Ready` means "scoped", not "claimable by agents". Anything
   you were not given needs an explicit human request naming the work.
2. **Claim before working.** Claiming = set Status `In Progress` and comment on
   the issue that you are taking it. No silent claims; two agents must never
   discover mid-flight they grabbed the same issue.
3. **Refuse work that is not safe to hand off.** Ambiguous scope, untestable
   acceptance criteria, security-sensitive or destructive changes, or a
   judgment call the human has not yet made — push those back to the issue
   before starting, rather than guessing.
4. **Stay inside capability boundaries.** Free via `gh`: issues, labels,
   milestones, Project items, branches, PRs. Forbidden without in-conversation
   human approval: force-push, history rewrite, deleting Project fields or
   labels repo-wide, repo settings changes, cutting releases.
5. **Leave an audit trail.** Provenance is the commit trailer
   (`Co-Authored-By`) and the PR author account — no labels, no attribution
   line in the PR body. What the body must carry is exactly what you validated
   (see rule 6). Reviewers read agent success as a *claim*, not a fact.
6. **Report honestly, including what you did not do.** Never over-claim success
   — that is the canonical agent failure. A skipped validation level is a
   `RISK:` line, never silence.
7. **Stop after the second failure.** Stuck twice on the same task, stop and
   report what you tried. Do not spend a third attempt in the same loop.
8. **One checkout per agent.** Parallel agents each work in their own
   worktree/branch; never share a checkout. Conflicting PRs land sequentially.

## How

Start on an issue you were handed:

```bash
gh issue view 42 --json title,body,labels,assignees   # confirm scope and acceptance criteria
gh issue comment 42 --body "Claiming — starting work on a feat/42 branch."
# set Project Status -> In Progress, branch feat/42-<slug>, open the PR
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

- Starting on an issue nobody handed you because it "looks easy" — the human's
  assignment is the gate, not your read of difficulty.
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
- `` `.github/PROJECT_FIELDS.md` `` — where `Status` and the other metadata live
- `` `skills/context-handoff/SKILL.md` `` — pausing and resuming work across sessions
- `` `skills/pr-authoring/SKILL.md` `` — PR body and `RISK:` conventions
- `` `skills/validation-ladder/SKILL.md` `` — the L0–L4+ validation levels
