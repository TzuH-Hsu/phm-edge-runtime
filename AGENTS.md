# AGENTS.md

Canonical instructions for AI coding agents — and the humans working alongside them — in this repository.

Agent-specific entry files (`CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`) are thin pointers to this file. **This file is the single source of truth.** If guidance conflicts anywhere else, AGENTS.md wins.

## Operating rules (read first)

1. Work from an issue. If no issue exists for what you are about to do, create one first (see `skills/issue-writing/`).
2. Never commit directly to `main`. Branch as `<type>/<issue#>-<slug>` (e.g. `feat/42-label-sync`), open a PR.
3. Follow the metadata single-home contract in `.github/PROJECT_FIELDS.md` — every attribute (type, priority, area, status, version) lives in exactly one place. Never dual-write.
4. Run `make verify` before opening or updating a PR.
5. Declare skipped validation levels in the PR body: `RISK: <level> not run — <reason>`. Never skip silently.
6. Never commit `*.local.md` files, secrets, or `.env*` files (only `.env.example` is allowed).
7. Load skills on demand (see index below). Do not bulk-load every skill into context.

## Build and validation

The Makefile is the only executable contract in this repository. CI calls make targets; customize the Makefile, never the workflows.

| Level | Name | Command | When required |
| --- | --- | --- | --- |
| L0 | static | `make lint` | every PR |
| L1 | unit | `make test` | every PR |
| L2 | integration | adopter-defined | when the change touches component boundaries |
| L3 | e2e / preview | adopter-defined | user-visible changes |
| L4+ | extensions | adopter-defined | domain-specific (see `skills/validation-ladder/`) |

- `make verify` = L0 + L1 — the canonical local gate before any PR.
- `make help` lists all targets.
- Pick validation depth by blast radius; a level that applies but cannot run becomes a `RISK:` line in the PR.

## Repository layout

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | This file — canonical agent + contributor instructions |
| `.github/` | Governance: workflows, issue forms, PR template, `PROJECT_FIELDS.md`, `labels.yml`, rulesets |
| `skills/` | Reusable knowledge modules (one directory per skill, `SKILL.md` inside) |
| `docs/adr/` | Architecture Decision Records |
| `docs/setup/` | Bootstrap and GitHub configuration guides |
| `scripts/` | Bootstrap and self-consistency check scripts |
| `Makefile` | Canonical target contract (validation ladder entry points) |

## Workflow

1. **Issue** — created via issue forms; native type (Bug/Feature/Task) is set by the form; labels for priority/area follow `.github/PROJECT_FIELDS.md`.
2. **Branch** — `<type>/<issue#>-<slug>`; types mirror Conventional Commit types (`feat`, `fix`, `docs`, `chore`, `refactor`, `ci`).
3. **Commits** — Conventional Commits, English, imperative (`feat: add label sync phase to bootstrap`).
4. **PR** — English title in Conventional Commit format; body follows the PR template: summary, linked issue (`Closes #N`), validation ladder checkboxes, `RISK:` lines, rollback notes.
5. **Merge** — squash merge; the PR title becomes the commit message on `main`.

## AI agent conventions

- **Work queue**: issues labeled `agent-ok` with Project status `Ready` are self-service — an agent may pick one up without asking. Anything not labeled `agent-ok` needs an explicit human request.
- **Audit trail**: label PRs you author with `by-agent`.
- **Capability boundaries**: agents may manage issues, labels, milestones, and Project items via `gh`; agents must NOT perform destructive operations (deleting Project fields, force-pushing, rewriting history, changing repo settings) without explicit human approval in the conversation.
- **Session handoff**: long-running work may keep exactly one gitignored `HANDOVER.local.md` (hard cap ~150 lines, rewrite — don't append — at session end). Durable knowledge gets promoted to issues, ADRs, or skills, then deleted from the handoff file. See `skills/context-handoff/`.

## Skills index

Load a skill only when its "load when" condition matches your current task.

| Skill | Load when |
| --- | --- |
| [agent-workflow](skills/agent-workflow/SKILL.md) | An AI agent picks up, executes, or hands off repository work — queue, boundaries, audit. |
| [anti-patterns](skills/anti-patterns/SKILL.md) | Reviewing repository health or designing process — named failure modes and their fixes. |
| [context-handoff](skills/context-handoff/SKILL.md) | Pausing, resuming, or handing off work across sessions — handoff file discipline. |
| [branch-and-commit](skills/branch-and-commit/SKILL.md) | Starting work — branch naming, Conventional Commits, issue linkage. |
| [code-review](skills/code-review/SKILL.md) | Reviewing a PR or deciding whether to self-merge — tiny-team review practice. |
| [pr-authoring](skills/pr-authoring/SKILL.md) | Opening or updating a pull request — structure, validation ladder, RISK lines. |
| [adr-writing](skills/adr-writing/SKILL.md) | A decision needs a durable record — triggers, format, lifecycle. |
| [docs-hygiene](skills/docs-hygiene/SKILL.md) | Adding or restructuring documentation — placement, linking, drift prevention. |
| [labels-and-taxonomy](skills/labels-and-taxonomy/SKILL.md) | Adding, renaming, or retiring labels — taxonomy governance. |
| [issue-writing](skills/issue-writing/SKILL.md) | Creating or triaging an issue — forms, metadata contract, acceptance criteria. |
| [milestone-planning](skills/milestone-planning/SKILL.md) | Planning releases or process phases — milestone discipline and scope control. |
| [github-actions-hygiene](skills/github-actions-hygiene/SKILL.md) | Writing or reviewing GitHub Actions workflows — security and maintainability rules. |
| [incident-response](skills/incident-response/SKILL.md) | Something broke — triage, fix-forward, postmortem-lite. |
| [validation-ladder](skills/validation-ladder/SKILL.md) | Choosing how much validation a change needs — ladder levels, stages, extensions. |
| [release-management](skills/release-management/SKILL.md) | Cutting a release or changing release cadence — release-please flow and alternatives. |

## Repository policy

This is a standalone, reusable library published under Apache-2.0. Everything in it is public and permanent, and it is read by people with no context. Write accordingly.

**Never commit — not in code, tests, fixtures, sample configuration, documentation, commit messages, issues or pull requests:**

| Never | Why |
| --- | --- |
| Names of organisations, sites, plants or projects | This library is not about any one of them |
| Equipment models, enclosure layouts, point tables, register maps, real slave addresses | Deployment detail belongs to the deployment |
| Data samples, screenshots or logs captured from a real installation | Same reason, and captured data is rarely ours to publish |
| Credentials, endpoints, internal addresses | Public and permanent |
| Non-English user-facing text | The audience is not one team |

Documentation here describes the code. Use neutral, invented examples throughout.

**Two structural rules:**

- **No dependency on a downstream project.** The direction is one-way: applications depend on this library, never the reverse.
- **Treat every push as irreversible.** Rewriting history does not remove the objects — they stay reachable by SHA, and a public repository publishes that SHA in its events feed the moment you push. Pull request titles and bodies count: the squash setting writes the body into the commit message on `main`.

Other conventions:

- Every source file starts with `SPDX-License-Identifier: Apache-2.0`.
- Dependency licences: MIT, Apache-2.0, BSD, ISC. No GPL/AGPL or other copyleft — downstream users ship commercial products.
- Contributions are provided under Apache-2.0 by default (Apache-2.0 §5). No CLA.

## Pointers

- Process and conventions for humans: `CONTRIBUTING.md`
- Metadata contract: `.github/PROJECT_FIELDS.md`
- Decisions and rationale: `docs/adr/`
- Security policy: `SECURITY.md`
