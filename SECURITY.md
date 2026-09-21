# Security Policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting: open the **Security**
tab on this repository and select **Report a vulnerability**. This creates a
private advisory visible only to maintainers, so no personal contact address
is published here. If you fork or adopt this template for your own project,
consider adding your own contact method for reports.

Please do not open a public issue for a suspected vulnerability.

## Scope

This repository is a **template** — configuration, documentation, and
scripts, not a running application. The most likely sources of a real
vulnerability are:

- `scripts/bootstrap.sh` (and other setup scripts) — anything that shells
  out, handles tokens, or writes repo/GitHub configuration.
- GitHub Actions workflow configuration under `.github/workflows/` —
  permissions, pinned actions, and secret handling.

## Response expectations

This is a small-team template maintained on a best-effort basis. Expect an
acknowledgment within a few business days. There is no formal SLA.

## Supported versions

Only the latest release and `main` are supported. Older tagged releases do
not receive backported fixes — update to the latest release or rebase your
adoption on `main`.

## Repository security settings

The upstream template's `scripts/bootstrap.sh` (phase 6 there; this repository's
copy predates it) reports, and offers to enable, four repository-level protections: secret scanning, push protection, Dependabot
alerts, and Dependabot security updates. Two things worth knowing about how it
behaves:

- **It only ever enables what is free.** On a public repository secret scanning
  and push protection cost nothing, so it offers them. On a private or internal
  repository they require a paid GitHub Advanced Security / Secret Protection
  seat, and bootstrap will not commit your account to a per-committer charge —
  it reports the state and hands you a manual step instead.
- **Making a repository public does not enable them for you.** Going public
  grants *access* to those features; it does not switch them on. Push
  protection in particular has to be enabled explicitly, which is exactly how a
  public repository ends up without it.

The upstream script's `--dry-run` performs every read for real and no writes at
all, so it works as a zero-risk audit of an existing repository; for this
repository, check the state directly with `gh api repos/{owner}/{repo} --jq
.security_and_analysis`.

## Secret hygiene

`gitleaks` runs in CI (`make lint-secrets`) to catch committed secrets before
merge. Never commit API keys, tokens, or credentials — use `.env.example` as
a placeholder and keep real values in `.env` (gitignored). If a secret is
ever exposed, rotate it immediately regardless of how it was discovered.
