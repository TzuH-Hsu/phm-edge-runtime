# Project views setup

GitHub's REST/GraphQL API cannot create Project views, so that part of this
setup is always done by hand after `scripts/bootstrap.sh` creates the
Project. The `Status` field's options, however, are
set automatically (via the GraphQL `updateProjectV2Field` mutation) when
`scripts/bootstrap.sh` phase 4 creates the Project itself — you only need
section 1 below if the project pre-existed the bootstrap run, if its
options were customized (bootstrap warns and skips in both cases), or if
you're setting things up by hand for some other reason (e.g. you ran with
`--skip-project`).

Mirror the single-home contract in `.github/PROJECT_FIELDS.md`: this Project
carries exactly these custom fields: `Status`, `Estimate`, `Start`, `Target`
and `Checkpoint`. `Effort` is retired. Do **not** add
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

## 2. Confirm the planning fields

Confirm these four fields exist on the board; add any that are missing on
the board via **+** next to the field headers → **New field**:

| Field | Type | Meaning |
| --- | --- | --- |
| `Estimate` | Number | Rough estimate in person-days (1 person-day = 5 hours) |
| `Start` | Date | Scheduled start |
| `Target` | Date | Committed finish date (a milestone's due date is a different layer) |
| `Checkpoint` | Iteration | Internal checkpoint, one level finer than a milestone |

`Effort` is retired: if the board still has an `Effort` field, delete it.

## 3. Create views

Use **+ (new view)** at the top of the Project for each of these.

### View 1 — "Now"

- Layout: **Board**
- Group by: `Status`
- Purpose: the default working view — everything by workflow state.

### View 2 — "Roadmap"

- Layout: **Roadmap**, dates from `Start` / `Target`
- Group by: `Assignees`
- Markers: `Checkpoint` and `Milestone`
- Purpose: who is doing what, when, against the checkpoints.

### View 3 — "Checkpoint"

- Layout: **Table**
- Group by: `Checkpoint`, with the `Estimate` sum shown per group
- Purpose: what each checkpoint carries and whether it fits.

### View 4 — "Milestone"

- Layout: **Table**
- Group by: `Milestone`
- Purpose: what is committed to each milestone versus the backlog (no
  milestone).

### View 5 — "By area"

- Layout: **Table**
- Slice by: the `area:*` labels
- Purpose: one area's items at a time.

### View 6 — "Blocked"

- Layout: **Table**
- Filter: `status:Blocked`
- Purpose: everything waiting on something else.

Priority is a label, not a field: filter any view with `label:"priority:p0"`
rather than adding a Priority field.

## Checklist

- [ ] `Status`: Backlog / Ready / In Progress / In Review / Blocked / Done
- [ ] `Estimate` (number), `Start` and `Target` (date), `Checkpoint` (iteration); no `Effort` and no other custom fields
- [ ] View: Now (board, grouped by Status)
- [ ] View: Roadmap (Start / Target, grouped by Assignees, Checkpoint and Milestone markers)
- [ ] View: Checkpoint (table, grouped by Checkpoint, Estimate sum)
- [ ] View: Milestone (table, grouped by Milestone)
- [ ] View: By area (table, sliced by `area:*`)
- [ ] View: Blocked (table, `status:Blocked`)

## See also

- `.github/PROJECT_FIELDS.md` — the metadata single-home contract (why no
  Priority/Area/Type fields belong here)
- `docs/setup/bootstrap.md` — phase 4 (`Project`) and the rest of the
  bootstrap flow
