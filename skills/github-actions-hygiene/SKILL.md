---
name: github-actions-hygiene
description: Use when writing or reviewing GitHub Actions workflows — security and maintainability rules.
category: quality
---

# GitHub Actions Hygiene

## Purpose

Workflows are the highest-privilege, least-reviewed code in most repositories — they run with repo secrets and are easy to skim past in review. This skill keeps them thin, pinned, and safe by construction rather than by vigilance.

## Rules

1. **Workflows call `make` targets; they never contain logic.** All branching, tool installation flags, and conditionals belong in the `Makefile`. A workflow step should read as `run: make lint`, not a shell script with real decisions in it. Adopters customize the Makefile — never the workflow YAML — to change what runs.
2. **Least privilege by default.** Set `permissions: contents: read` at the workflow (top) level; escalate only inside the specific job that needs more, and only to the exact scope needed (e.g. `pull-requests: write` on a labeler job, not on the whole workflow).
3. **Pin every third-party action to a full commit SHA**, with the human-readable version as a trailing comment — never a floating tag like `@v4`:

   ```yaml
   uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
   ```

4. **Concurrency groups on every workflow.** Cancel in-progress runs for PR events (a new push obsoletes the old run); never cancel-in-progress on `main` (a cancelled release or deploy run mid-flight is worse than a slow one).
5. **`timeout-minutes` on every job**, always. An unbounded job is an unbounded bill and an unbounded hang.
6. **Never interpolate untrusted `${{ }}` expressions directly into `run:`.** Issue titles, PR titles, branch names, and commit messages are attacker-controlled strings — interpolating them into a shell step is a script-injection vector. Pass them through `env:` and reference the env var instead.
7. **Destructive or irreversible dispatch workflows require a typed-confirmation guard** — the operator must type an exact phrase (e.g. the repo name) as a `workflow_dispatch` input, checked before anything destructive runs.
8. **Checksum-verify any binary downloaded and installed in a workflow** (release tools, linters) — download the checksums file alongside the asset and verify before `chmod +x` / `install`.
9. **Anti-sprawl**: a new workflow file needs a justification that no existing workflow already covers. This template's target set is four: CI (verification), issue labeling, link maintenance, release PRs. Adding a fifth is a deliberate decision, not a default — prefer adding a job or a `make` target to an existing workflow first.
10. **Every pinned tool version lives in one file, and something watches it.** SHA-pinning actions (rule 3) only covers `uses:`. Dependabot reads manifests, so a version pinned inside a `run:` step or an install script is invisible to it and will rot silently — no alert, no PR, no signal at all. Keep those pins in a single file (`scripts/install-ci-tools.sh` here) and run a scheduled check that diffs them against upstream (`make check-tool-versions`, a step in the weekly maintenance workflow). A pin nobody is watching is a pin that stays put for years.

## How

Script-injection-safe pattern for untrusted text:

```yaml
- name: Check issue title
  env:
    ISSUE_TITLE: ${{ github.event.issue.title }}
  run: |
    echo "Title was: $ISSUE_TITLE"
    # never: run: echo "Title was: ${{ github.event.issue.title }}"
```

Typed-confirmation guard for a destructive `workflow_dispatch`:

```yaml
on:
  workflow_dispatch:
    inputs:
      confirm:
        description: 'Type the repo name to confirm this destructive action'
        required: true

jobs:
  destroy:
    steps:
      - name: Verify confirmation phrase
        run: |
          set -euo pipefail
          [ "${{ github.event.inputs.confirm }}" = "${{ github.repository }}" ] || {
            echo "Confirmation phrase did not match. Aborting."; exit 1; }
```

Checksum verification, adapted from `scripts/install-ci-tools.sh` (which both
`ci.yml` and `maintenance.yml` reach via `make ci-tools` — this logic used to be
duplicated verbatim inside each workflow, which is what rule 1 prevents):

```bash
verify_checksum() {
  local asset="$1" checksums="$2" hash
  hash="$(grep -F "$asset" "$checksums" | grep -Eo '[A-Fa-f0-9]{64}' | head -n1)"
  printf '%s  %s\n' "$hash" "$asset" | sha256sum -c -
}
```

## Pitfalls

- Putting a conditional (`if: contains(github.event.head_commit.message, ...)`) or a multi-branch shell script directly in the workflow — that logic silently diverges from what `make lint`/`make test` do locally, so `make verify` stops being a truthful preview of CI.
- Floating action tags (`@v4`, `@main`) — a compromised or force-pushed upstream tag becomes an instant supply-chain hole; SHA pinning is the only real mitigation.
- A workflow-level `permissions: write-all` "to be safe" — this is the opposite of safe; grant per-job, per-scope only.
- String-building a shell command from `github.event.pull_request.title` or similar — classic GitHub Actions script injection, exploitable by anyone who can open a PR or issue.
- Adding a workflow per one-off task ("just for this migration") instead of a temporary `make` target run locally — workflow sprawl accumulates permissions surface that nobody audits later.

## Related

- `` `.github/workflows/ci.yml` `` — reference implementation of pinned actions, top-level `permissions: read`, concurrency group, `timeout-minutes`, and `persist-credentials: false`; also carries the header warning explaining why its `on:` block must never gain a path filter (the `ci` job is the only required status check)
- `Makefile` — where all workflow logic actually lives (`lint`, `test`, `verify`, `ci-pr`, `ci-tools`)
- `` `scripts/install-ci-tools.sh` `` — checksum-verified tool installs and the single home for all five CI tool version pins, shared by `ci.yml` and `maintenance.yml`
- `` `scripts/check-tool-versions.sh` `` — rule 10's watcher: diffs those pins against upstream weekly and fails on drift
- `AGENTS.md` — "The Makefile is the only executable contract in this repository"
- `` `skills/validation-ladder/SKILL.md` `` — what `make lint`/`make test` are expected to cover
- `` `skills/release-management/SKILL.md` `` — the release-please workflow this hygiene applies to
