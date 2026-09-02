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

## Secret hygiene

`gitleaks` runs in CI (`make lint-secrets`) to catch committed secrets before
merge. Never commit API keys, tokens, or credentials — use `.env.example` as
a placeholder and keep real values in `.env` (gitignored). If a secret is
ever exposed, rotate it immediately regardless of how it was discovered.
