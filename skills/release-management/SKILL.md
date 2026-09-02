---
name: release-management
description: Use when cutting a release or changing release cadence — release-please flow and alternatives.
category: release
---

# Release Management

## Purpose

A release must never ship from an unverified state, and version/changelog bookkeeping should never depend on someone remembering to do it by hand. This skill covers the default automated flow and the documented manual fallback, per `docs/adr/ADR-0002-release-flow.md`.

## Rules

1. **Default flow: release-please, human-gated.**
   1. `release-please` watches `main` and maintains a running release PR (version bump + `CHANGELOG.md`, generated from Conventional Commits).
   2. **A human merges the release PR — never auto-merge.** The branch ruleset requires the `ci` status check to be green before merge is even possible; this is the mitigation for the fact that both CI and release-please trigger on `push:main`, so an unverified commit could otherwise reach the release PR.
   3. Merging the release PR cuts the git tag and GitHub Release automatically.
   4. The maintainer then edits the published release notes to add a short, hand-written TLDR **above** the generated changelog. Release notes have non-technical readers — the generated bullet list alone is not the message.
2. **Version bump is derived, not chosen.** It comes from Conventional Commit types accumulated since the last release: `fix` → patch, `feat` → minor, any commit with `!` or a `BREAKING CHANGE:` footer → major. This is exactly why commit type discipline matters (see `CONTRIBUTING.md`).
3. **Pre-1.0 semantics**: a minor bump may contain breaking changes. Don't assume `0.x` minor bumps are safe to blindly consume — read the changelog.
4. **Documented alternative — manual tag-first.** Use this instead of release-please when release cadence is near-zero or the team wants zero release automation:
   1. Decide the version by hand.
   2. Update `CHANGELOG.md` in a normal PR, reviewed like any other change.
   3. `git tag vX.Y.Z` on the merged commit.
   4. `gh release create --generate-notes`, then add the hand-written TLDR.
   Trade-off: fewer moving parts and no bot to maintain, but CHANGELOG/version consistency now depends entirely on human discipline — this is the exact failure mode release-please exists to remove.
5. **Define release exit criteria per milestone before opening it**, not while triaging what's left. A typical criterion: zero open `priority:p0`/`priority:p1` issues attached to the milestone. Write the criteria into the milestone description.
6. **Never cut a release with red or skipped CI.** If a validation level was skipped with a `RISK:` line during development, resolve or explicitly accept that risk before the release — don't let it ride silently into a tagged version.

## How

Check whether the milestone is release-ready:

```bash
gh issue list --milestone "v0.2.0" --label "priority:p0,priority:p1" --state open
# empty output = exit criterion met
```

Merge the release-please PR (never squash-merge it manually outside its own flow; let release-please's merge produce the tag):

```bash
gh pr view --search "head:release-please--branches--main" --json number,statusCheckRollup
gh pr merge <release-pr#> --merge
```

Add the human TLDR after the release is cut:

```bash
gh release edit vX.Y.Z --notes "$(printf '%s\n\n%s' \
  "TLDR: <one paragraph, plain language, for non-technical readers>" \
  "$(gh release view vX.Y.Z --json body -q .body)")"
```

Manual tag-first alternative, end to end:

```bash
# after CHANGELOG.md PR is merged to main
git tag v0.2.0
git push origin v0.2.0
gh release create v0.2.0 --generate-notes
gh release edit v0.2.0 --notes "TLDR: ...\n\n$(gh release view v0.2.0 --json body -q .body)"
```

## Pitfalls

- Enabling auto-merge on the release-please PR "to save a click" — this defeats the entire point of the human gate described in ADR-0002; the `push:main` race is only closed because a human reviews before merge.
- Shipping release notes with only the generated Conventional Commit list and no TLDR — accurate for engineers, meaningless for the actual audience of a release announcement.
- Running both release-please and the manual tag-first flow at once — pick one per repo; running both produces duplicate or conflicting tags.
- Treating a `0.x` minor bump as automatically non-breaking because "it's not a major" — pre-1.0, minor can break; read the changelog before upgrading dependents.
- Opening a milestone with no stated exit criteria, then improvising "is this done?" at cut time — define it up front so the decision is a lookup, not a debate.
- CI on the release PR may sit un-run (`action_required` / no checks) because workflows don't auto-trigger on PRs created with the default `GITHUB_TOKEN` (GitHub's recursion guard); nudge it by closing and reopening the release PR, or configure release-please with a Personal Access Token (PAT) that has workflow trigger permission.

## Related

- `` `docs/adr/ADR-0002-release-flow.md` `` — the decision record and alternatives considered
- `CONTRIBUTING.md` — Conventional Commit types and release summary for humans
- `AGENTS.md` — commit/branch/PR conventions that feed the changelog
- `` `skills/github-actions-hygiene/SKILL.md` `` — hygiene rules for the `release-please.yml` workflow itself
- `` `skills/validation-ladder/SKILL.md` `` — why CI must be green before a release PR can merge
