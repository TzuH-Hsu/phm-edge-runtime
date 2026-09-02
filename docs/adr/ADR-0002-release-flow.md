# ADR-0002: Release flow — release-please with human-gated release PRs

- **Status**: Accepted
- **Date**: 2026-07-03

## Context

A release flow for a solo/small-team repo must satisfy three forces: (1) versioning and changelog upkeep should not depend on human memory; (2) a release must never be cut from an unverified state; (3) the human must stay in control of *when* a release happens and what its headline says — release notes have non-technical readers.

The two projects this template distills used opposite flows: one ran release-please (automated version PRs), the other ran manual tag-first releases (`git tag` → `gh release create --generate-notes` + a hand-written summary). Both worked; each has a known failure mode. release-please and CI both trigger on `push:main`, so an unverified commit can update the release PR; manual flows silently drift (forgotten CHANGELOG, inconsistent versions).

## Decision

We use **release-please** for this repository and as the adopter default:

1. release-please maintains a running release PR on `main` (version bump + `CHANGELOG.md` from Conventional Commits).
2. **A human merges the release PR — never auto-merge.** The branch ruleset requires the `ci` status check, so an unverified release PR cannot land. This is the mitigation for the `push:main` race.
3. Merging the release PR cuts the tag and GitHub Release automatically.
4. The maintainer then edits the release notes to add a short hand-written TLDR above the generated changelog — the human headline stays.

Conventional Commits are required (see `CONTRIBUTING.md`); they are what release-please parses.

**Documented alternative — manual tag-first**: for repos with very low release cadence or teams that want zero release automation, drop `release-please.yml` and instead: decide the version manually → update `CHANGELOG.md` in a PR → `git tag vX.Y.Z` → `gh release create --generate-notes`, then add the TLDR. The trade-off and mechanics live in `skills/release-management/`.

## Consequences

- CHANGELOG and version bumps become automatic and consistent; the human decision compresses to "merge the release PR now, or wait".
- The repo carries one more workflow (`release-please.yml`) and two config files — accepted maintenance cost.
- Commit discipline matters: a mistyped Conventional Commit type miscategorizes the changelog entry. CI lints commit format only via convention and review, not a hard gate (deliberate — see `skills/branch-and-commit/`).

## Alternatives considered

- **Manual tag-first as the default** — fewer moving parts, but relies on discipline for CHANGELOG/version consistency; kept as the documented alternative rather than the default.
- **semantic-release (auto-publish on every qualifying push)** — removes the human gate entirely; wrong fit for a template whose releases have human-written headlines and whose adopters are small teams.
- **No releases, rolling main** — adopters need stable reference points to pull template updates from; rejected.
