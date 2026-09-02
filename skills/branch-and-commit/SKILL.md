---
name: branch-and-commit
description: Use when starting work — branch naming, Conventional Commits, issue linkage.
category: delivery
---

# Branch and Commit

## Purpose

Branch names and commit messages are the mechanical link between an issue and the
code that closes it. Getting the format right keeps `git log`, the changelog, and
`gh` queries all machine-readable — no archaeology required later.

## Rules

1. Never commit directly to `main`. Branch first, always: `<type>/<issue#>-<slug>`
   (e.g. `feat/42-label-sync`). The type mirrors the Conventional Commit type.
2. Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/):
   `<type>: <description>`, English, imperative mood, subject line ≤72 chars.
3. Pick the type deliberately — release-please reads it directly into the changelog:

   | Type | Meaning | Changelog / version impact |
   | --- | --- | --- |
   | `feat` | New capability | Minor bump, "Features" section |
   | `fix` | Bug fix | Patch bump, "Bug Fixes" section |
   | `perf` | Performance improvement | Patch bump |
   | `refactor` | Restructure, no behavior change | Patch bump |
   | `docs` | Documentation only | No version bump |
   | `chore` | Maintenance, tooling | No version bump |
   | `ci` | CI/CD workflow changes | No version bump |
   | `test` | Test-only changes | No version bump |

4. Breaking changes append `!` after the type (`feat!:`) or add a `BREAKING CHANGE:`
   footer — either triggers a major bump. Use whichever is more visible for the
   change; don't rely on prose in the body alone.
5. One logical change per commit. A commit that mixes a `fix` and an unrelated
   `refactor` forces release-please to miscategorize part of the diff no matter which
   type you pick — split it instead.
6. Squash merge is the merge strategy for this repo: the PR title, not any individual
   commit message, becomes the commit on `main`. Individual commits on the branch can
   be loose checkpoints; the PR title is what must be a clean Conventional Commit
   (see `pr-authoring`).

## How

```bash
# Branch from an issue
git checkout -b feat/42-label-sync

# Conventional commit, imperative, scoped
git commit -m "feat: add label sync phase to bootstrap"

# Breaking change, explicit footer
git commit -m "feat!: drop support for legacy label schema" \
  -m "BREAKING CHANGE: type:* labels renamed; run scripts/bootstrap.sh to resync"

# Verify branch naming before pushing
git branch --show-current  # expect <type>/<issue#>-<slug>
```

## Pitfalls

- Typing `fix:` for what is actually a `feat:` (or vice versa) — this silently
  miscategorizes the changelog entry; release-please trusts the type literally.
- Committing straight to `main` "because it's a one-liner" — there is no exception;
  every change goes through a branch and a PR.
- Cramming unrelated changes into one commit because splitting feels slower — it
  costs more later when the changelog entry doesn't match what actually shipped.
- Using past tense or a period at the end of the subject ("Added label sync.")
  instead of imperative, no trailing period ("add label sync").
- Forgetting the issue number in the branch slug — it's the cheapest possible link
  between branch and issue and costs nothing to include.

## Related

- `CONTRIBUTING.md` — branch and commit conventions
- `` `docs/adr/ADR-0002-release-flow.md` `` — why commit type discipline matters for release-please
- `` `skills/issue-writing/SKILL.md` `` — the issue a branch should trace back to
- `` `skills/pr-authoring/SKILL.md` `` — turning a branch into a mergeable PR
