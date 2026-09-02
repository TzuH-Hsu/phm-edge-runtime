---
name: code-review
description: Use when reviewing a PR or deciding whether to self-merge — tiny-team review practice.
category: delivery
---

# Code Review

## Purpose

A one-to-three-person team can't run heavyweight, multi-approver review on every PR.
This skill defines a review practice that scales to a solo maintainer while staying
honest about risk — especially for PRs an AI agent wrote.

## Rules

1. Match review depth to blast radius and reversibility, not to a fixed checklist
   length. A docs typo fix and a change to the metadata contract do not deserve the
   same scrutiny.
2. Solo-maintainer self-merge is legitimate once CI is green and the PR's validation
   ladder is honest (checkboxes plus any required `RISK:` lines). The RISK section is
   the discipline substitute for a second approver — treat it as load-bearing, not
   decorative.
3. When reviewing an AI-authored PR, verify claims against the diff — don't take the
   PR description at face value. Agents over-report success; "all tests pass" is a
   claim to check (run it, or read the CI log), not a fact to accept.
4. Check that tests added or changed actually assert behavior, not just execute code
   without meaningful assertions. A test that can't fail is not coverage.
5. Check that nothing outside the linked issue's scope changed. Scope drift is easy
   for an agent to introduce quietly (an unrelated "while I was in there" edit) and
   easy for a human reviewer to miss if they're only skimming the summary.
6. Prefer cross-family review when available: have a different model or agent family
   review a PR than the one that authored it. Same-model review shares the same
   blind spots as same-model authorship; a different reviewer catches what the
   author's own assumptions hid.
7. Review comments are actionable and severity-tagged — `blocking` or `non-blocking`
   — so the author (human or agent) knows what must change before merge versus what
   can be a follow-up issue.
8. If a review thread keeps re-litigating the same design decision across multiple
   PRs, stop arguing it inline — write an ADR instead and link to it. A recurring
   disagreement is a sign the decision needs a durable, citable answer.

## How

```bash
# Pull PR diff and description for review
gh pr view <PR#> --json title,body,files
gh pr diff <PR#>

# Verify a test claim instead of trusting the PR body
make test  # or the specific target the PR claims passed

# Leave a severity-tagged, actionable comment
gh pr comment <PR#> --body "blocking: the new label-sync fn has no test for empty label sets"

# Self-merge once ladder + RISK lines check out
gh pr merge <PR#> --squash
```

## Pitfalls

- Rubber-stamping an agent-authored PR because the summary reads well — read the
  diff; the summary is the agent's claim about the diff, not the diff itself.
- Treating a green CI badge as sufficient when the PR's own RISK lines admit a level
  was skipped — the badge only covers what actually ran.
- Accepting tests that assert `expect(true).toBe(true)`-style non-assertions as
  coverage — check that a failing implementation would actually fail the test.
- Letting scope drift through because the unrelated change "seemed fine" — fine or
  not, it belongs in its own issue and PR.
- Re-arguing the same architectural point in review comments on PR after PR instead
  of writing it down once as an ADR.
- Using self-merge as an excuse to skip the RISK-line discipline — self-merge assumes
  the ladder was honest, not that review was skipped entirely.

## Related

- `CONTRIBUTING.md` — solo-maintainer self-merge policy
- `AGENTS.md` — agent capability boundaries and audit trail conventions
- `` `skills/pr-authoring/SKILL.md` `` — the RISK convention this review practice depends on
- `` `skills/branch-and-commit/SKILL.md` `` — commit hygiene that makes diffs reviewable
