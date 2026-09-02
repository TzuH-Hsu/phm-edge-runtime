# Contributing

This file is for humans. It covers the same contract as `AGENTS.md`, which is
canonical for AI agents working in this repository — if the two ever seem to
disagree, `AGENTS.md` wins and this file should be corrected to match.

This guide is for anyone adopting **GitHub Project OS** as a template, or
contributing back to the template itself: solo developers and small teams
(1–3 people) running their engineering process on GitHub.

## Getting started

```bash
git clone <your-repo-url>
cd <your-repo>
```

Install the lint tools used by `make lint-docs`:

| Tool | Install |
| --- | --- |
| markdownlint-cli2 | `npm install -g markdownlint-cli2` |
| yamllint | `brew install yamllint` (or `pip install yamllint`) |
| lychee | `brew install lychee` |
| actionlint | `brew install actionlint` |
| gitleaks | `brew install gitleaks` |

Then:

```bash
make help    # list all targets
make verify  # L0 (lint) + L1 (test) — run this before every PR
```

See `AGENTS.md` for the full validation ladder (L0–L4+) and how to declare a
skipped level.

## Issues

- Always use the issue forms — never open a blank issue. The form you pick
  sets the native GitHub issue type (Bug, Feature, Task).
- Priority and area labels are applied automatically by the labeler workflow;
  you don't set them by hand.
- Every piece of issue/PR metadata (type, priority, area, status, version)
  lives in exactly one place. See `.github/PROJECT_FIELDS.md` for the
  single-home contract — never dual-write the same attribute in two places.

## Branches & commits

- Branch name: `<type>/<issue#>-<slug>`, e.g. `feat/42-label-sync`.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/):
  `feat`, `fix`, `docs`, `chore`, `refactor`, `ci`, `test`, `perf`.
- Titles are English, imperative mood: `feat: add label sync phase to bootstrap`.
- Breaking changes: append `!` after the type (`feat!: ...`) or add a
  `BREAKING CHANGE:` footer.

## Pull requests

- PR title is a Conventional Commit — it becomes the squash commit message on
  `main`, so make it count.
- Fill in the PR template: summary, linked issue (`Closes #N`), validation
  ladder checkboxes, and rollback notes.
- If a validation level applies but you can't run it, say so explicitly:
  `RISK: <level> not run — <reason>`. Never skip a level silently.
- Solo maintainers may self-merge once CI is green.
- Keep each PR scoped to one issue — don't bundle unrelated changes.

## Releases

[release-please](https://github.com/googleapis/release-please) maintains an
always-up-to-date release PR on `main`. A human reviews and merges that PR —
it is never auto-merged. Merging it cuts the GitHub release and updates the
CHANGELOG. After merge, the maintainer adds a short hand-written TLDR to the
top of the release notes so readers get the "why" before the changelog list.

Details: `skills/release-management/` (coming) and
`docs/adr/ADR-0002-release-flow.md`.

## Milestones

- `vX.Y.Z` — a release commitment; issues attached to it are meant to ship in
  that release.
- `gov-*` — process and governance work, not tied to a release.
- No milestone — backlog; not yet committed to a release.

## What not to commit

- Secrets of any kind (API keys, tokens, credentials).
- `.env*` files — except `.env.example`.
- `*.local.md` files (session handoff notes and other local-only scratch
  files; see `AGENTS.md` for the handoff convention).

`make lint-secrets` (gitleaks) runs in CI and should also be run locally
before pushing anything you're unsure about.

## Pointers

- Agent-canonical instructions: `AGENTS.md`
- Metadata contract: `.github/PROJECT_FIELDS.md`
- Decisions and rationale: `docs/adr/`
- Security policy: `SECURITY.md`
