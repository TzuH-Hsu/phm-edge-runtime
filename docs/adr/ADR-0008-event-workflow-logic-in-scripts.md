# ADR-0008: Event-driven workflow logic lives in `scripts/`, behind a thin `github-script` caller

- **Status**: Accepted
- **Date**: 2026-09-21
- **Issue**: #14 (ported from github-project-os #49 / #56)

## Context

`AGENTS.md` and `skills/github-actions-hygiene` rule 1 say workflows call `make` targets and never contain logic. The issue labeler was always the exception: an event handler that needs the `GITHUB_TOKEN` and the `issues` payload, which no `make` target can own, so ~150 lines of JavaScript lived inline in `.github/workflows/issue-labeler.yml`. The exception was undocumented, and the only way to test the script was to extract it from the YAML by hand. A repository whose rule is "the template obeys its own rules" cannot leave its one stateful workflow untestable and unnamed.

## Decision

1. **The logic moves to `scripts/issue-labeler.js`**, a plain Node module with pure functions (`parseSections`, `matchAllowed`, `parseAllowedAreas`, `computeChanges`) and one I/O entry point (`run({github, context, core})`). The workflow checks out the default branch (`actions/checkout`, pinned, `persist-credentials: false`, `fetch-depth: 1`) and its `github-script` step is two lines: `require` the module, `await run(...)`.
2. **`labels.yml` is read from the checkout, not the API.** On `issues` events `GITHUB_SHA` is the head of the default branch, so the checkout holds exactly the merged declarations — the same trust boundary the API read had, without the extra request.
3. **The script is tested by `make check`** (`scripts/check-node-tests.sh` → `node --test scripts/*.test.js`, node built-ins only). A missing `node` fails with an install hint, the way every other tool `make` needs does — never a green skip (validation-ladder rule 7).
4. **Rule 1 names the shape.** Event-driven workflows that genuinely need the token or the payload keep their logic in `scripts/*.js`, called through `github-script` after a checkout; the workflow stays a thin caller and carries no adopter values.

The second instance is `scripts/pr-lint.js` (upstream #56, ported in the same change): the `Lint the pull request` step in `ci.yml` fails the required check when a PR's branch is not `<type>/<issue#>-<slug>` or its body links no issue. It needs the payload, not the token, and follows the same shape.

## Consequences

- The labeler is readable in one file and has a durable test; a change to its matching rules is a normal PR with a failing test first.
- The workflow file stays replaceable whole on upgrade — the property adopters already rely on — but now travels with `scripts/issue-labeler.js`; upstream's `docs/template/upgrading.md` says so.
- One more pinned action to keep bumped (Dependabot covers it) and a checkout on every issue event (a few seconds).
- `node` becomes a dependency of `make check`; CI already has it for markdownlint.
- The logic is now protected by whatever protects `scripts/` on the default branch, not by GitHub's rule that tokens without the `workflows` scope cannot write under `.github/workflows/`. The blast radius is unchanged (the job holds `issues: write` and nothing else), and `main` already requires a PR plus green `ci`; adopters who want a review barrier add `/scripts/issue-labeler.js` and `/.github/workflows/` to `.github/CODEOWNERS` (the commented example there shows the line) and set `require_code_owner_review` in the ruleset.

## Alternatives considered

- **Record the exception and keep the script inline.** Rejected: it leaves the only stateful workflow untestable, and the next change to it repeats the extract-by-hand validation.
- **Keep reading `labels.yml` through the API and skip the checkout.** Rejected: the checkout is needed for the script anyway, and a second copy of the same data by a second route is a second thing to keep consistent.
- **A `make labeler` target invoked from a `run:` step.** Rejected: the payload would have to reach the shell through the environment, and the token through `gh` — more surface, no gain over `github-script`'s sandbox.
