# Metadata single-home contract

Every issue/PR attribute lives in **exactly one place**. Never dual-write the same fact into a label *and* a Project field *and* a milestone — dual-homed metadata always drifts. This file is the authority map; if a tool or habit conflicts with it, this file wins (rationale: `docs/adr/ADR-0003-metadata-single-home.md`).

## Authority map

| Attribute | Home | Values / format |
| --- | --- | --- |
| Type (coarse) | `type:bug` / `type:feature` **labels** | 個人帳號沒有原生 issue type，Type 的家改成 label；兩者都沒有 = Task |
| Type (subtype) | `type:*` **labels** | `chore` / `ops` / `docs` / `security` — Task subtypes only |
| Priority | `priority:*` **labels** | `p0` critical / `p1` milestone-blocking / `p2` important / `p3` polish |
| Area | `area:*` **labels** | 本庫自身的領域，見 `.github/labels.yml` |
| Workflow status | **Project `Status` field** | `Backlog` / `Ready` / `In Progress` / `In Review` / `Blocked` / `Done` |
| Target version | **Milestone** | `vX.Y.Z` releases, `gov-*` process phases; **no milestone = backlog** |
| Effort | **Project `Effort` field** | `S` (≤ half a day) / `M` (≤ 2 days) / `L` (must be decomposed first) |
| Owner | **Assignee** | 一個 issue 一位主要負責人（協作可多人）；**人名不進標題、文件表格或文件標頭** |
| Agent eligibility | `agent-ok` **label** | present = AI agents may self-serve when Status is `Ready` |
| Agent authorship | `by-agent` **label** | on PRs authored by an AI agent (audit trail) |
| Dependencies | **Native issue relationships** | GitHub blocked-by / blocking |
| Epic membership | **Native sub-issues** | parent issue with sub-issues; no `epic:*` labels |

## Personal accounts

This repository lives under a personal account, so **native issue types are unavailable** (`repos/{repo}/issue-types` returns 404). Coarse Type is carried by the `type:bug` / `type:feature` labels instead; neither label present means Task. This is still single-home — labels are the *only* home for Type here, never alongside a native type.

The issue form you pick still matters (it decides the body template); GitHub simply ignores its `type:` key. Add `type:bug` or `type:feature` after the issue is created.

## Rules

1. **One home per attribute.** Adding a Project field that mirrors a label (or vice versa) is a contract violation — remove one.
2. **Labels are for facts an agent can write in one `gh` call.** Workflow state belongs to the Project board, not labels.
3. **Milestone = commitment.** Assigning a milestone means "this ships in that version/phase". Backlog items carry no milestone.
4. **Retire, don't accumulate.** When a label or field stops earning its keep, delete it everywhere (see `skills/labels-and-taxonomy/`).
5. **Owner 只住 assignee。** 文件裡要指出負責人時連到 issue，不要寫人名——人名會過期，連結還會同時帶出狀態。作者身分不需要欄位，git 已經記了；「誰負責審這塊」的機制是 `.github/CODEOWNERS`，不是 markdown 表格。

## Where things are defined

- Labels: `.github/labels.yml` (declarative source of truth; sync = re-run `scripts/bootstrap.sh`)
- Project fields: created by `scripts/bootstrap.sh`; views are set up manually — `docs/setup/project-views.md`
- Native issue types: set automatically by the issue forms in `.github/ISSUE_TEMPLATE/`
