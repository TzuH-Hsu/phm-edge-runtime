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

A second L4 shape — dependency licence policy. Deliberately **not** a `make`
target in this template: a repository with no dependency manifest has nothing to
scan, and a target that greenlights an empty scan is exactly the fake pass rule 7
forbids. Wire it when your project acquires dependencies, preferring your
ecosystem's own checker (`pip-licenses`, `go-licenses check`, `cargo-deny`) over
a generic scanner:

```makefile
# MANIFESTS: set to whatever your ecosystem actually locks.
MANIFESTS ?= package-lock.json go.sum requirements.txt Cargo.lock poetry.lock
SBOM_TMP  ?= .sbom.json

lint-licenses: ## L4 - reject copyleft dependencies (adopter-defined)
	@command -v syft >/dev/null 2>&1 || { echo "FAIL: syft not installed, cannot verify L4"; exit 1; }
	@found=""; for m in $(MANIFESTS); do [ -s "$$m" ] && found=1; done; \
	  [ -n "$$found" ] || { echo "FAIL: none of ($(MANIFESTS)) present - refusing to report a clean scan of nothing"; exit 1; }
	syft dir:. -o json -q > $(SBOM_TMP)
	scripts/check-licenses.py < $(SBOM_TMP)
```

Three things here are load-bearing. The manifest assertion, without which the
target passes forever on an empty set — and `MANIFESTS` has to list what *your*
ecosystem locks, or the guard fails honest repositories. Writing the SBOM to a
file instead of piping it, because a shell pipeline reports only the last
command's status, so `syft ... | checker` reports success when `syft` itself
fails (`set -o pipefail` is the alternative, but it is not portable to every
adopter's `SHELL`). And an SBOM artifact is subject to the same rule as the
check — an empty one is worse than none, because it looks like evidence.

If you write the checker yourself, two things fail open by default: an SPDX `OR`
is a *choice*, so `MIT OR GPL-2.0` must pass rather than fail, and `NOASSERTION`
or an empty licence field must fail loudly, since that is what scanners emit for
every package they could not resolve.

## Pitfalls

- Treating `make test` passing as proof a user-visible change works — L1 does not substitute for L3 when the change is UI/CLI-visible.
- Writing an L4 target that echoes "OK" when the required tool is missing. That is a fake pass; it must fail.
- Silently skipping L2/L3 because they're inconvenient in the current sandbox — always add the `RISK:` line instead.
- Running full L0–L3 on a one-line docs fix — over-verification wastes cycles that should go to actually risky changes.
- Wiring a licence or SBOM scan into `lint` on a repository with no dependency manifest — it scans an empty set and passes forever, which is the fake pass above wearing a compliance badge.
- Confusing "L4 doesn't exist yet" with "L4 doesn't apply" — if the domain needs it and it's unbuilt, that itself is a `RISK:` line, not silence.

## Related

- `AGENTS.md` — canonical ladder table and operating rules 4/5
- `Makefile` — `lint`, `test`, `verify`, `ci-pr` targets
- `` `.github/workflows/ci.yml` `` — runs `make ci-pr` (= L0 + L1) on every PR and push to `main`
- `` `skills/github-actions-hygiene/SKILL.md` `` — how CI wires into make targets
- `` `skills/incident-response/SKILL.md` `` — what to do when a shipped change turns out to have skipped a level it needed
