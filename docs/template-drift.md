# Template drift

This file lists every place this repository deliberately differs from the
github-project-os template, measured against template v0.6.0 on 2026-09-28 (re-baselined when v0.6.0 was taken).
On a sync, keep these differences; when a new deliberate difference is
introduced, update this file in the same PR.

The rule that keeps this file current lives in AGENTS.md (Build and validation):
a PR that adds or removes a deliberate difference updates this file.

The comparison ref is not a normal tag. Fetch it once into its own namespace, so
template tags never collide with this repository's version tags:

```bash
git remote add template https://github.com/TzuH-Hsu/github-project-os.git  # once
git config remote.template.tagOpt --no-tags
git fetch template '+refs/tags/v0.6.0:refs/template-tags/v0.6.0'
```

To re-check:

```bash
git diff refs/template-tags/v0.6.0 HEAD -- <file>
git ls-tree -r --name-only refs/template-tags/v0.6.0 > /tmp/template-files.txt
git ls-tree -r --name-only HEAD > /tmp/repo-files.txt
diff /tmp/template-files.txt /tmp/repo-files.txt
```

## Adopter-owned files

Files every adopter owns. They always differ and are never copied from the template.

| File | What is ours |
| --- | --- |
| README.md | Project description, badges and usage for this library |
| CHANGELOG.md | release-please-generated history for this repository |
| LICENSE | Apache-2.0 full text (template ships MIT) — this repo's licence choice |
| NOTICE | Apache-2.0 attribution plus MIT attribution for the template-derived scaffolding |
| .release-please-manifest.json | This repository's own release version |
| CONTRIBUTING.md | Tool install table order and one wording tweak; process content matches the template |
| AGENTS.md project sections | The "Repository policy" section (public-library commit rules) and the runner-variable list |
| .github/CODEOWNERS | No active owner lines (comment-only example block, plus one added example) |
| .github/labels.yml area:\* set | `area:update`, `area:health`, `area:docs`, `area:ci` — this library's own domains |
| .github/ISSUE_TEMPLATE Area options | Mirrors the area:\* set above in all three forms |
| .github/PROJECT_FIELDS.md project specifics | Personal-account Type-label section, Owner/assignee row, rule 5 |
| docs/adr/README.md index | Lists only the ADRs this repo has (no ADR-0004/0005/0006 rows) |
| docs/setup/ content | See "Kit files with local changes" below — largely rewritten for this repo's own bootstrap history |

## Template files not taken

Files in the template that this repo does not have.

| File | Why |
| --- | --- |
| docs/adr/ADR-0004-adopter-licence-choice.md | Not copied; referenced by URL from docs/setup/licensing.md instead |
| docs/adr/ADR-0005-runner-selection-variable.md | Not copied; referenced by URL from docs/setup/runners.md instead |
| docs/adr/ADR-0006-coarse-type-fallback.md | Not copied; this repo's PROJECT_FIELDS.md documents the personal-account Type handling directly |
| docs/template/README.starter.md | Template-authoring doc, removed at de-template |
| docs/template/architecture.md | Template-authoring doc, removed at de-template |
| docs/template/design-principles.md | Template-authoring doc, removed at de-template |
| docs/template/upgrading.md | Template-authoring doc, removed at de-template |
| scripts/check-license-marker.sh | Not taken; this repo's licence hygiene runs through `scripts/check-licenses.py` instead (`make lint-licenses`) |

## Kit files with local changes

| File | Difference from the template | Why | Since |
| --- | --- | --- | --- |
| .github/CODEOWNERS | Extra commented example line for `/scripts/pr-lint.js` | Keeps the example list in step with the PR-lint script added alongside it | #15 |
| .github/ISSUE_TEMPLATE/bug_report.yml, feature_request.yml, task.yml | Area options list `area:update`/`area:health`/`area:docs`/`area:ci` instead of the template's `area:docs`/`area:skills`/`area:ci`/`area:governance` | This repo's own domain split, kept in sync with `.github/labels.yml` | #10 |
| .github/PROJECT_FIELDS.md | Coarse Type row points at `type:bug`/`type:feature` labels, not native issue type; adds Owner/assignee row and rule 5 | This repo is a personal-account repo, so native issue types are unavailable | #18 (personal-account rewrite), bootstrap (Owner/assignee row and rule 5) |
| .github/labels.yml | `type:bug`/`type:feature` active (not commented out); `area:*` set is `update`/`health`/`docs`/`ci` instead of `docs`/`skills`/`ci`/`governance` | Personal-account Type fallback is in use; areas renamed to this library's own domains | #18 |
| .github/workflows/ci.yml | `runs-on` reads `vars.CI_RUNNER_LABELS`; header comments trimmed to the shorter public-repo runner-cost rationale; PR-lint step comment moved next to the step | Split the single `RUNNER_LABELS` into one variable per workflow so jobs can run on different runners | #20 |
| .github/workflows/issue-labeler.yml | `runs-on` reads `vars.AUTOMATION_RUNNER_LABELS` | Same per-workflow runner-variable split | #15 |
| .github/workflows/maintenance.yml | `runs-on` reads `vars.MAINTENANCE_RUNNER_LABELS` | Same per-workflow runner-variable split | bootstrap |
| .github/workflows/release-please.yml | `runs-on` reads `vars.RELEASE_RUNNER_LABELS` | Same per-workflow runner-variable split | bootstrap |
| .gitignore | Adds `dist/` | `make sbom` writes SBOM/licence output there | #39 (licence tooling) |
| SECURITY.md | Rewords the bootstrap-phase-6 paragraph to say this repo's copy of `scripts/bootstrap.sh` predates that phase, and points at `gh api ... security_and_analysis` instead | This repo's bootstrap script is older than the phase the template text describes | #18 |
| Makefile | `check` target runs `scripts/test_check_licenses.py` via `unittest` instead of `check-license-marker.sh`; adds `lint-licenses` and `sbom` targets (syft-based licence check and SBOM/licence-list output); neither target is wired into `lint`/`ci-pr` yet | This library ships no dependencies to scan yet, and syft is not in the pinned CI tool list; both wire in with the first real dependency | #15, #23, #29, #32, #37, #39 |
| AGENTS.md | Runner-variable line lists four per-workflow variables instead of one; adds a "Repository policy" section (public-library commit rules: no org/site/equipment names, no captured data, SPDX headers, licence allowlist, no CLA) | Per-workflow runner split, and rules specific to a public standalone library | #15 (runners), #37 (policy section, licence allowlist line) |
| docs/adr/ADR-0008-event-workflow-logic-in-scripts.md | Issue number and date point at this repo's own issue (#14) instead of upstream's (#49); wording says the PR-lint script was "ported" from upstream #56 rather than written fresh; the upgrading-doc reference is qualified as upstream's | Ported from upstream in one change rather than authored incrementally here | #15 |
| docs/setup/bootstrap.md | Reduced to the phases this repo's `scripts/bootstrap.sh` actually has | Only the phase-5 merge-settings block was ever synced from upstream after bootstrap; the rest are this repo's original, older phases (no phase 6/9, phase 2 misreports on personal accounts) | #13, bootstrap |
| docs/setup/licensing.md | Adds an "Adopter note" pointing out this repo predates upstream's phase 9 and has carried MIT attribution in `NOTICE` since bootstrap; "See also" links ADR-0004 by upstream URL | Explains why the phase-9 prompt described on the page never ran here | #18 |
| docs/setup/runners.md | Documents four variables (`CI_RUNNER_LABELS`, `AUTOMATION_RUNNER_LABELS`, `MAINTENANCE_RUNNER_LABELS`, `RELEASE_RUNNER_LABELS`) with a table, instead of the template's single `RUNNER_LABELS`; "measured" failure example is attributed to upstream, not this repo; ADR-0005 referenced by upstream URL | Per-workflow runner-variable split | #18 |
| scripts/bootstrap.sh | ~700 lines shorter than the template; only the phase-5 merge-settings block matches upstream | Same as docs/setup/bootstrap.md — this repo's copy predates most later upstream phases | #18, #13, #3, bootstrap |
| scripts/install-ci-tools.sh | `RUNNER_LABELS` comment updated to `*_RUNNER_LABELS`; markdownlint-cli2 pin kept current with upstream | Per-workflow runner-variable split | #20 |
| skills/anti-patterns/SKILL.md | Inherited-licence-leak row says this repo chose Apache-2.0 and has carried template attribution in `NOTICE` since bootstrap, instead of describing the generic bootstrap-phase-9 mechanism | Documents this repo's actual licence outcome | #18 |
| skills/github-actions-hygiene/SKILL.md | Rule 1 lists the four per-workflow runner variables instead of one `RUNNER_LABELS` | Per-workflow runner-variable split | #18 |
| skills/issue-writing/SKILL.md | Area example is a generic placeholder (`<area:name — description, exactly as the Area option reads in .github/ISSUE_TEMPLATE/task.yml>`) instead of the template's literal `area:docs`/`area:ci` example | Same placeholder in all six sibling repos: four of them have no `area:docs`/`area:ci`, so the template v0.5.2 sync replaced the example everywhere to keep one patch applicable to all six | #18 |
| skills/labels-and-taxonomy/SKILL.md | Notes that this repo's older bootstrap phase 2 does not flag the coarse-Type-fallback-on-an-org-repo mistake, unlike upstream's | This repo's `scripts/bootstrap.sh` predates that phase-2 check | #18 |

## Local additions in template directories

Repo-only files under .github/, scripts/, skills/, docs/setup/, docs/adr/ and Makefile targets the template does not have.

| File or target | Purpose | Since |
| --- | --- | --- |
| scripts/check-licenses.py | Enforces the dependency licence allowlist (MIT/Apache-2.0/BSD/ISC plus notice-only licences) against `syft` JSON output | bootstrap |
| scripts/licence-exceptions.json | Named exceptions to the licence allowlist, each with a recorded reason | #37 |
| scripts/licence-table.tmpl | `syft` output template that adds a licence column to the third-party licence list `make sbom` writes | #39 |
| scripts/test_check_licenses.py | Unit tests for `scripts/check-licenses.py`, run by `make check` | #37 |
| Makefile `lint-licenses` | Runs `scripts/check-licenses.py` against the repo tree and every image in `SBOM_IMAGES` | #23 |
| Makefile `sbom` | Writes an SPDX SBOM and the third-party licence list to `dist/` | bootstrap |
| docs/template-drift.md | This inventory of deliberate differences from the template | #41 |

## Local rules that conflict with kit files

Local rules that the byte-identical kit files do not follow, kept that way on purpose so syncs stay byte-identical.

| Rule | Where it is stated | Kit files affected | Why not patched locally |
| --- | --- | --- | --- |
| Every source file starts with an SPDX identifier | AGENTS.md, "Repository policy" | Kit scripts under `scripts/` | No longer a conflict: since template v0.5.7 the kit scripts carry `SPDX-License-Identifier: MIT`, and the rule says template scripts keep that identifier while this library's own code uses Apache-2.0. Row kept so a sync does not re-stamp them |

## Updating this file

- Add a row in the same PR that introduces a deliberate difference from the template.
- Remove the row when the difference is dropped (the file matches the template again).
- Re-run the two commands above and re-baseline the tag reference when a new template release is taken.
