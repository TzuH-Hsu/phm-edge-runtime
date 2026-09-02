---
name: validation-ladder
description: Use when choosing how much validation a change needs — ladder levels, stages, extensions.
category: quality
---

# Validation Ladder

## Purpose

Not every change deserves the same scrutiny — a typo fix and a schema migration are not the same risk. The ladder gives a shared vocabulary for "how much validation" so agents and humans pick a depth deliberately instead of by habit or by skipping checks quietly.

## Rules

1. The ladder has four canonical levels, defined in `AGENTS.md` and executed by the `Makefile`:
   - **L0 static** — `make lint` (markdown/YAML lint, actions lint, secret scan, self-consistency checks). Every PR, no exceptions.
   - **L1 unit** — `make test`. Every PR once a real test suite is wired in.
   - **L2 integration** — adopter-defined (component boundaries, API contracts, DB migrations). Required when the change touches a boundary between components.
   - **L3 e2e / manual preview** — adopter-defined (browser flows, CLI smoke tests, staging deploy). Required for user-visible changes.
2. `make verify` = L0 + L1. This is the canonical, non-negotiable local gate before opening or updating any PR.
3. **L4+ extensions** are named, documented, and owned by the adopter — a simulator run, hardware-in-the-loop test, install/provisioning check, load test. They are not generic; each adopter defines what "L4" means for their domain and wires it into the Makefile as its own target.
4. Pick the depth by **blast radius**, not by how the change felt to write:

   | Change shape | Minimum levels |
   | --- | --- |
   | Docs-only, comments, typo fixes | L0 |
   | Internal logic, single-module change | L0 + L1 |
   | Crosses a component boundary (API shape, schema, contract) | L0 + L1 + L2 |
   | User-visible behavior (UI, CLI output, public API) | L0 + L1 + L3 |
   | Domain-critical path an adopter has defined L4+ for | all of the above + L4 |

5. Stage mapping: every PR runs L0 + L1 always, plus L2/L3 when blast radius requires it. Pre-release runs every core level (L0–L3) regardless of individual PR history — a release is a checkpoint, not a rubber stamp on the last PR's choices.
6. If a level applies but genuinely cannot run (no staging environment, flaky hardware, missing fixture), say so in the PR body as a `RISK:` line — never skip it silently. See the exact convention below.
7. Extension levels (L4+) fail **loud** when not implemented: a missing L4 target should error with a clear message, not silently report success. A green check that didn't check anything is worse than no check.

## How

Declare a skipped-but-applicable level in the PR body:

```text
RISK: L2 not run — no staging DB available in this environment, migration reviewed manually instead.
```

Wire a domain-specific L4 target so it fails loud instead of no-op passing:

```makefile
verify-l4: ## L4 - hardware-in-loop smoke test (adopter-defined)
    @command -v hil-runner >/dev/null 2>&1 || { echo "FAIL: hil-runner not installed, cannot verify L4"; exit 1; }
    hil-runner --suite smoke
```

Check blast radius quickly before picking a depth:

```bash
git diff --stat origin/main...HEAD   # which files/dirs changed?
gh pr view --json files -q '.files[].path'
```

## Pitfalls

- Treating `make test` passing as proof a user-visible change works — L1 does not substitute for L3 when the change is UI/CLI-visible.
- Writing an L4 target that echoes "OK" when the required tool is missing. That is a fake pass; it must fail.
- Silently skipping L2/L3 because they're inconvenient in the current sandbox — always add the `RISK:` line instead.
- Running full L0–L3 on a one-line docs fix — over-verification wastes cycles that should go to actually risky changes.
- Confusing "L4 doesn't exist yet" with "L4 doesn't apply" — if the domain needs it and it's unbuilt, that itself is a `RISK:` line, not silence.

## Related

- `AGENTS.md` — canonical ladder table and operating rules 4/5
- `Makefile` — `lint`, `test`, `verify`, `ci-pr` targets
- `` `.github/workflows/ci.yml` `` — runs `make ci-pr` (= L0 + L1) on every PR and push to `main`
- `` `skills/github-actions-hygiene/SKILL.md` `` — how CI wires into make targets
- `` `skills/incident-response/SKILL.md` `` — what to do when a shipped change turns out to have skipped a level it needed
