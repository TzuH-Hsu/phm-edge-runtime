---
name: pr-authoring
description: Use when opening or updating a pull request — structure, validation ladder, RISK lines.
category: delivery
---

# PR Authoring

## Purpose

A pull request is both a code change and a claim about how thoroughly it was
checked. This skill covers the structure that makes both parts verifiable — for a
human reviewer and for an agent reviewing another agent's work.

## Rules

1. The PR title is a Conventional Commit (`<type>: <description>`) — squash merge
   makes it the commit message on `main`. Get it right; see `branch-and-commit` for
   type selection.
2. Fill in every section of the PR template: summary, linked issue, validation
   ladder checkboxes, risk/rollback. An empty section is not an oversight a reviewer
   should have to chase — it's a blocked merge.
3. Pick validation depth by blast radius, not by habit:

   | Change | Minimum ladder |
   | --- | --- |
   | Docs-only | L0 |
   | Logic change, contained | L0 + L1 |
   | Crosses a component boundary | L0 + L1 + L2 |
   | User-visible behavior change | L0 + L1 + L3 |

4. A validation level that applies but could not run must appear as a `RISK:` line —
   silent skips are the cardinal sin. Exact format:

   ```text
   RISK: <level> not run — <reason>
   ```

   No level that applies to the change may simply be absent from both the checkbox
   list and the RISK lines.
5. Use `Closes #N` to link the issue — one issue per PR. Don't bundle unrelated
   changes just because they happened to be worked on together.
6. Agents label their own PRs `by-agent` for the audit trail. This is separate from
   `agent-ok` on the issue (eligibility to pick up work vs. authorship record).
7. Re-run `make verify` after every revision to the PR, not just before the first
   push. A review comment that changes code invalidates the previous green run.

## How

```bash
# Open a PR with a Conventional Commit title, linked issue, template intact
gh pr create --title "feat: add label sync phase to bootstrap" \
  --body-file .github/PULL_REQUEST_TEMPLATE.md

# Label agent authorship
gh pr edit <PR#> --add-label "by-agent"

# Re-verify before each push after review feedback
make verify && git push
```

A correctly declared skip looks like this in the PR body:

```text
RISK: L2 not run — no integration harness exists yet for this component; tracked in #58
Rollback: revert this PR; no migrations or external state changed
```

## Pitfalls

- Leaving a validation level unchecked with no `RISK:` line — indistinguishable from
  "forgot to run it," which is exactly the ambiguity the RISK convention exists to
  remove.
- Picking L0-only for a change that crosses a component boundary because L0 is fast —
  ladder depth follows blast radius, not convenience.
- Writing `RISK: L3 not run` with no reason — the reason is the point; it's what lets
  a reviewer judge whether the skip is acceptable.
- Scope creep: fixing an unrelated bug noticed along the way in the same PR — file a
  new issue instead, keep the PR mapped to one `Closes #N`.
- Pushing a fix in response to review and calling the ladder still green from the
  first run — re-run `make verify` after every revision.
- Forgetting the `by-agent` label on agent-authored PRs — breaks the audit trail this
  repo relies on in place of a heavier review gate.

## Related

- `` `.github/PULL_REQUEST_TEMPLATE.md` `` — the template this skill fills in
- `AGENTS.md` — validation ladder table (L0–L4+) and agent conventions
- `CONTRIBUTING.md` — human-facing PR expectations
- `` `skills/branch-and-commit/SKILL.md` `` — producing the branch and title this PR is built from
- `` `skills/code-review/SKILL.md` `` — what happens to this PR next
