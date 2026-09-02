# Project views setup

GitHub's REST/GraphQL API cannot create Project views, so that part of this
setup is always done by hand after `scripts/bootstrap.sh` creates the
Project and its `Effort` field. The `Status` field's options, however, are
set automatically (via the GraphQL `updateProjectV2Field` mutation) when
`scripts/bootstrap.sh` phase 4 creates the Project itself — you only need
section 1 below if the project pre-existed the bootstrap run, if its
options were customized (bootstrap warns and skips in both cases), or if
you're setting things up by hand for some other reason (e.g. you ran with
`--skip-project`).

Mirror the single-home contract in `.github/PROJECT_FIELDS.md`: this Project
carries exactly two custom fields, `Status` and `Effort`. Do **not** add
`Priority`, `Area`, or `Type` fields — those already live as labels /
native issue type, and a mirrored field is a contract violation (see
`docs/adr/ADR-0003-metadata-single-home.md`).

## 1. Set Status field options (manual fallback)

`scripts/bootstrap.sh` sets this automatically only on a Project that the
same bootstrap run just created (a fresh board with no items, its Status
still holding GitHub's defaults `Todo`/`In Progress`/`Done`). It
deliberately never touches a pre-existing project's Status field — even
when the options look like the untouched defaults — because rewriting
options assigns new option IDs and would silently orphan the Status values
of any items already on the board. The same hands-off rule applies when
the options were customized. In those cases bootstrap prints a WARN and a
MANUAL note, and you finish the job here:

1. Open the Project (`<repo> board`) → **⋯ (top right) → Settings**, or
   click the `Status` column header → **Edit field**.
2. Replace the current options with:
   - `Backlog`
   - `Ready`
   - `In Progress`
   - `In Review`
   - `Blocked`
   - `Done`
3. Delete any leftover options that aren't in the list above.
4. Pick colors if you want them — not required, purely visual.

If you skipped Project setup entirely (`--skip-project`) and are creating
the Project by hand, do this step after creating the `Status` field's
default options (every Project v2 board ships with one).

## 2. Confirm the Effort field

`scripts/bootstrap.sh` creates this automatically; confirm it's there:

- Field name: `Effort`
- Type: single select
- Options: `S`, `M`, `L`

If it's missing (e.g. you ran with `--skip-project`), add it by hand: on the
board, click **+** next to the field headers → **New field** → name
`Effort`, type **Single select**, options `S`, `M`, `L`.

## 3. Create views

Use **+ (new view)** at the top of the Project for each of these.

### View 1 — "Board"

- Layout: **Board**
- Group by: `Status`
- Purpose: the default working view — see everything by workflow state.

### View 2 — "Milestones"

- Layout: **Table**
- Group by: `Milestone`
- Purpose: release/phase planning — what's committed to `vX.Y.Z` or `gov-*`
  versus sitting in the backlog (no milestone).

### View 3 — "Agent queue"

- Layout: **Table** (or **Board** grouped by `Status`, either works)
- Filter: `label:agent-ok status:Ready`
- Sort: by `priority:*` label (`p0` first) — GitHub sorts labels
  alphabetically by default, so a manual sort or a saved custom sort by
  label name gets `priority:p0` ahead of `priority:p1`, etc.
- Purpose: this is the literal work queue described in `AGENTS.md` — "issues
  labeled `agent-ok` with Project status `Ready` are self-service". An agent
  should be able to open this view and know exactly what it may pick up
  without asking.

### View 4 — "Stakeholder" (optional)

- Layout: **Table**
- Filter: current milestone (e.g. `milestone:"v0.1.0"`)
- Columns: minimal — title, status, assignee. Hide `Effort`, labels, and
  other implementation-detail fields.
- Purpose: a non-technical-readable view of "what's shipping in this
  release and how it's tracking" — link this view for anyone outside the
  core contributors who wants a status check without spelunking labels.

## Checklist

- [ ] `Status`: Backlog / Ready / In Progress / In Review / Blocked / Done
- [ ] `Effort`: S / M / L (no other custom fields)
- [ ] View: Board (grouped by Status)
- [ ] View: Milestones (table, grouped by Milestone)
- [ ] View: Agent queue (`label:agent-ok status:Ready`, sorted by priority)
- [ ] View: Stakeholder (optional, current-milestone filter, minimal columns)

## See also

- `.github/PROJECT_FIELDS.md` — the metadata single-home contract (why no
  Priority/Area/Type fields belong here)
- `docs/setup/bootstrap.md` — phase 4 (`Project`) and the rest of the
  bootstrap flow
