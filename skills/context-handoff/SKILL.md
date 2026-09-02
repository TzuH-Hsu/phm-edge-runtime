---
name: context-handoff
description: Use when pausing, resuming, or handing off work across sessions — handoff file discipline.
category: ai-collaboration
---

# Context Handoff

## Purpose

Session context evaporates between agent runs, so work needs a bridge. The
trap is that the bridge becomes a landfill: append-only handoff files that grow
until reading them costs more than they save. This skill keeps the handoff a
tight, rewritten buffer and pushes durable knowledge into GitHub.

## Rules

1. **Exactly one handoff file.** `HANDOVER.local.md` at the repo root,
   gitignored. Never a second file, never an `ARCHIVE.local.md` — archives are
   the failure mode, not the fix.
2. **Hard cap ~150 lines.** Over the cap means you are storing, not handing off.
   Cut or promote until it fits.
3. **Rewrite at session end, never append.** Replace the whole file with the
   current picture. Append-only files balloon to 600+ lines and 200KB of stale
   history that is net-negative to read — that is the exact anti-pattern.
4. **Write only the five things worth handing off** (see How). If a line does
   not change what the next session does, it does not belong.
5. **Promote durable knowledge, then delete it from the handoff.** A decision →
   ADR; reusable know-how → a skill edit; a work item → an issue. The handoff is
   a buffer between sessions, not a store of record.
6. **Resume by verifying, not trusting.** The file records intentions; reality
   may have moved. Check claims against `git status` and `gh issue view` before
   acting, and rewrite stale parts first.
7. **GitHub is the real memory.** Anything that must survive lives in an issue,
   PR, or ADR — searchable, team-visible, durable. Anything only in a local
   file or a chat session is one `rm` or one expiry from gone.

## How

The content contract — the only five things a handoff should carry:

```markdown
# Handover
Goal: <one line> (#123)
In flight: branch feat/123-slug — parser done + unit-tested; wiring NOT done.
Next: wire parser into make target, then run `make verify`.
Blocked: waiting on human decision re: output format (commented on #123).
Surprises: the labeler workflow runs on `pull_request_target`, not `pull_request`.
```

The promotion ladder in practice — the handoff shrinks as knowledge lands:

```text
"we decided to keep status on the board, not labels" -> write ADR, delete line
"the trick to sync labels is re-run bootstrap.sh"    -> edit skill, delete line
"still need to add the e2e level"                    -> open issue, delete line
```

Resume ritual, every session:

```bash
git status && git log --oneline -5     # what actually happened
gh issue view 123 --json state,labels  # did the world move under the file?
# reconcile: rewrite any handoff line reality contradicts, THEN start working
```

## Pitfalls

- Appending "Session 4 notes" under "Session 3 notes" — that is how a 150-line
  cap becomes a 600-line archive nobody reads.
- Treating the handoff as the record of a decision instead of promoting it to an
  ADR — the decision dies with the file.
- Committing `HANDOVER.local.md` — it is scratch, gitignored, and full of
  half-truths; it must never reach `main`.
- Resuming straight from the file's "Next" line without checking `git`/`gh`,
  then redoing work that already landed or acting on a closed issue.
- Keeping a "just in case" `ARCHIVE.local.md` — there is no just in case; the
  durable copy is in GitHub or it does not exist.

## Related

- `AGENTS.md` — the one-handoff-file, rewrite-don't-append convention
- `` `skills/agent-workflow/SKILL.md` `` — claiming and reporting on work
- `` `skills/adr-writing/SKILL.md` `` — promoting a decision out of the handoff
- `` `skills/issue-writing/SKILL.md` `` — promoting a work item out of the handoff
- `` `skills/anti-patterns/SKILL.md` `` — handoff bloat as a named failure mode
