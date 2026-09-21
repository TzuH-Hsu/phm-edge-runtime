# Runner selection

Every workflow in this repository resolves its runner from a repository
variable, one per workflow so a lint job and a release job can differ:

| Workflow | Variable |
| --- | --- |
| `.github/workflows/ci.yml` | `CI_RUNNER_LABELS` |
| `.github/workflows/issue-labeler.yml` | `AUTOMATION_RUNNER_LABELS` |
| `.github/workflows/maintenance.yml` | `MAINTENANCE_RUNNER_LABELS` |
| `.github/workflows/release-please.yml` | `RELEASE_RUNNER_LABELS` |

```yaml
runs-on: ${{ fromJSON(vars.CI_RUNNER_LABELS || '["ubuntu-latest"]') }}
```

Leave a variable unset and that workflow behaves exactly as if `ubuntu-latest`
were hardcoded. (The upstream template uses a single `RUNNER_LABELS`; this
repository split it deliberately. Everything below applies to each variable.)

This is the single sanctioned exception to "customize the Makefile, never the
workflows" (`AGENTS.md`). It has to be an exception because GitHub resolves
`runs-on` when it schedules the job — before any `make` target exists to be
called — so it is the one adopter-facing knob the Makefile cannot own.

## Setting it

Before setting it to a self-hosted runner, read the security note below — on a
public repository that combination lets anyone who opens a pull request run code
on your machine.

The value is a **JSON array**, not a bare string:

```bash
gh variable set CI_RUNNER_LABELS --body '["ubuntu-latest-4-cores"]'
gh variable set CI_RUNNER_LABELS --body '["self-hosted","linux","x64"]'
gh variable delete CI_RUNNER_LABELS      # back to the default
```

## Get this wrong and the repository stops being mergeable

The tempting mistake is the bare string:

```bash
gh variable set CI_RUNNER_LABELS --body 'ubuntu-latest'    # WRONG - not an array
```

Measured upstream with a throwaway probe workflow, not assumed:

```text
workflow run  : completed, conclusion = failure
run message   : "This run likely failed because of a workflow file issue."
jobs created  : 0
check runs    : 0
```

`fromJSON` fails while the job is being scheduled, so **no job and no check run
are ever created.** For the `ci` workflow that is the worst case available: `ci`
is this repository's only required status check, so the pull request sits on
"Expected — waiting for status to be reported" forever, cannot merge, and the
only evidence is a failed run in the Actions tab whose message never mentions
the variable.

A valid-but-unknown label fails the same way from the other direction: the job
queues for a runner that never appears, for up to 24 hours.

**Recovery, which is not obvious from the symptom:**

```bash
gh variable delete CI_RUNNER_LABELS   # or whichever variable you set
```

Then push any commit to re-trigger. Because of this, change the variable and
immediately open a throwaway pull request to confirm `ci` still reports, before
you rely on it.

## Hard constraint: linux x86_64 only

`scripts/install-ci-tools.sh` installs actionlint, gitleaks and lychee as
checksum-verified `linux_amd64` tarballs, and `require_supported_platform`
hard-fails on anything else. Point any of the variables at `macos-latest` or an arm64
runner and `make ci-tools` fails at runtime with a message about `uname -m`,
which reads like a broken script rather than a misconfigured variable.

Supporting other architectures means adding per-tool asset names to that script,
not relaxing the guard.

## Self-hosted runners: do not use them on a public repository

**This is a security boundary, not a preference.** `.github/workflows/ci.yml`
triggers on every `pull_request`. On a **public** repository that includes pull
requests from forks, and the job checks out the pull request's own tree and then
runs `make ci-tools` and `make ci-pr` from it. Anyone on the internet who opens
a pull request therefore executes their own `Makefile` and their own
`scripts/` on your machine — with your filesystem, your network position, and
any credentials reachable from that host. Ephemeral cleanup does not help: the
damage happens while the job is running.

GitHub's default "require approval for first-time contributors" narrows the
window; it does not close it, because approval is per-contributor, not
per-diff, and a returning contributor's next pull request runs unreviewed.

So: **on a public repository, leave all four variables unset.** If you genuinely
need self-hosted CI on public code, the only safe shapes are to make the
repository private, or to split the workflow so that fork pull requests stay on
GitHub-hosted runners and self-hosted runners only ever run on `push` to
branches you control. That second option is a real workflow change, not a
variable.

On a **private** repository, where every contributor already has write access,
the rest of this section applies.

### Operational caveats, private repositories

Even a *compatible* self-hosted Linux x86_64 runner behaves differently from a
hosted one, because a hosted runner is destroyed after every job and yours is
not:

- `install_npm_global` and `install_python_tool` install **globally**, escaping
  `INSTALL_DIR` entirely.
- `require_install_consent` waves those through whenever `CI` is set, and GitHub
  Actions always sets it.
- `place_binary` uses `sudo` when `/usr/local/bin` is not writable, so the
  runner account needs passwordless sudo.

In practice: every run performs a real global `npm install -g` and
`pip install --user` on the runner host. That is fine on a throwaway container
and a slow accumulating mess on a long-lived VM. Prefer an ephemeral
self-hosted runner, or pre-install the five pinned tools into the image and
accept that `make ci-tools` will reinstall them anyway.

## Sizing: do not downsize to save money

The instinct to move CI onto a smaller, cheaper runner is usually wrong for a
repository shaped like this one, and `ci.yml`'s header already explains why for
the skip-CI case. The same arithmetic applies here:

- On a **public** repository, GitHub-hosted runners are free. A smaller runner
  saves exactly nothing.
- On a **private** repository, Actions minutes are billed **rounded up to the
  whole minute**. This template's lint job finishes in well under a minute, so
  it already bills the one-minute floor. A smaller, slower runner cannot go
  below that floor — it can only push the job over it and start billing two.
- Minimal images reinstall at runtime what a standard image preinstalls.
  Measured by an adopter on a 1 vCPU runner: the same lint job took 32 seconds
  to 2 minutes 7 seconds, against 21 to 45 seconds on `ubuntu-latest` — mostly
  spent installing markdownlint-cli2 via npm and yamllint via pip on one core.

Downsize only when a job **materially exceeds a minute** *and* you are past your
plan's included minutes. For a lint-shaped job neither is usually true.

Upsizing is the more common real need: a big test suite, or a compliance
requirement that builds run on your own hardware. That is what this variable is
for.

## See also

- `docs/setup/bootstrap.md` — the rest of the GitHub-side configuration
- `` `skills/github-actions-hygiene/SKILL.md` `` — why workflows stay thin
- upstream `docs/adr/ADR-0005-runner-selection-variable.md` (<https://github.com/TzuH-Hsu/github-project-os/blob/main/docs/adr/ADR-0005-runner-selection-variable.md>) — why this is a variable; this repository's `docs/adr/` numbers its own decisions
