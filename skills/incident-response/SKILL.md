---
name: incident-response
description: Use when something broke — triage, fix-forward, postmortem-lite.
category: quality
---

# Incident Response

## Purpose

Solo devs and small teams don't have an on-call rotation or an incident commander — the person who notices the break is also the one who fixes it. This skill keeps that single person from skipping the two steps that are easy to drop under pressure: recording evidence before diving in, and writing down the lesson before it evaporates.

## Rules

1. **Triage order is fixed**: stop the bleeding first, understand it second.
   1. Stop the bleeding — on `main`, a revert beats live debugging. Debugging in place while `main` is broken extends the blast radius to everyone pulling `main`.
   2. Scope the blast radius — what's affected, since when, who/what is exposed.
   3. File a `priority:p0` or `priority:p1` issue with the evidence you already have (error output, failing run URL, affected commit range) **before** deep-diving. If you get pulled away mid-investigation, the issue is the record — your head is not.
2. **Fix-forward vs. revert**: revert when the break is user-facing and the root cause is not yet clear. Fix-forward on `main` only when the cause is understood and the fix is smaller/safer than a revert (e.g. `main` has since accumulated other work you don't want to lose by reverting).
3. **Hotfix branches are the exception, not the default.** Use one only when `main` currently holds unreleasable/in-flight work that a straight fix-forward commit would drag into the next release. Otherwise, fix forward directly on `main` through the normal branch-and-PR flow — don't add hotfix ceremony to problems that don't need it.
4. **Postmortem-lite is mandatory, proportional to severity.** Before closing the incident issue, add a closing comment with five lines:

   ```text
   What broke:
   Detection:
   Root cause:
   Fix:
   Prevention:
   ```

   For `p0`/`p1` this is required. For lower severity, a shorter version is fine — but never zero.
5. **Durable lessons get promoted, not left in the issue.** If the prevention step implies a rule ("we should never do X"), that's an ADR candidate (see `skills/adr-writing/`) or a skill edit — not just a sentence in a closed issue nobody will re-read.
6. **Findings live in a durable artifact, never only in a chat session.** A chat transcript is not queryable, not linkable from a PR, and evaporates when the session ends. Write the evidence into the issue as you find it, not after you've already lost the details.

## How

Open the incident issue with evidence attached immediately, even before you know the cause:

```bash
gh issue create \
  --title "p0: production 500s on /checkout since deploy abc1234" \
  --label "priority:p0" \
  --body "Detected via: <link to alert/log>
Affected since: commit abc1234 / 2026-07-03 14:02 UTC
Evidence: <paste error, link failing CI run or trace>
Status: investigating"
```

Revert fast when cause is unclear and user-facing:

```bash
git revert --no-edit <bad-commit-sha>
git push
```

Close with the postmortem-lite template:

```bash
gh issue comment <issue#> --body "$(cat <<'EOF'
What broke: checkout POST returned 500 for all requests
Detection: alert fired 3 min after deploy
Root cause: migration dropped a column still read by v1 API handler
Fix: reverted commit abc1234, re-applied migration behind a flag in #57
Prevention: added L2 migration-compat check to validation ladder (see #58)
EOF
)"
```

Promote a recurring lesson to an ADR when it crosses boundaries or keeps coming back — don't leave it stranded in a closed issue (see `skills/adr-writing/` for the trigger criteria).

## Pitfalls

- Debugging live on `main` while it's broken "because the fix is almost done" — every minute extends who's affected; revert, then debug on a branch.
- Deep-diving for twenty minutes before filing the issue — if you get interrupted, that investigation state is gone; file first with whatever evidence you have, then keep digging.
- Reaching for a hotfix branch out of habit when `main` has nothing unreleasable on it — this just adds process overhead to a plain fix-forward.
- Closing the incident issue with no postmortem comment, or a one-word "fixed" — the next person (or agent) hitting the same class of bug has no record to search.
- Treating a repeated incident as three unrelated one-off fixes instead of noticing the pattern and writing an ADR or skill update after the second occurrence.

## Related

- `` `skills/adr-writing/SKILL.md` `` — promoting a prevention lesson into a durable decision record
- `` `skills/validation-ladder/SKILL.md` `` — adding a validation level that would have caught this class of incident
- `AGENTS.md` — branch/PR/label conventions used when filing the incident issue and its fix
- `` `.github/PROJECT_FIELDS.md` `` — `priority:*` label definitions (`p0` critical, `p1` milestone-blocking)
- `` `.github/labels.yml` `` — declared `priority:p0` / `priority:p1` label source
