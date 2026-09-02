#!/usr/bin/env bash
# bootstrap.sh — one-time (and re-runnable) setup for a repo created from the
# "GitHub Project OS" template. Applies everything a template can't ship as
# files: labels, milestone, GitHub Project fields, repo settings, ruleset,
# and (once) converts the repo from template docs to your project docs.
#
# Idempotent: re-running syncs label state to what's declared in
# .github/labels.yml. The branch ruleset is create-once, not synced: if
# main-branch-protection already exists, phase 7 is skipped rather than
# updated — delete the ruleset on GitHub and re-run to pick up changes to
# .github/rulesets/main-branch.json.
#
# Usage: scripts/bootstrap.sh [--dry-run] [--yes] [--prune]
#                              [--skip-project] [--keep-template-docs] [--help]
#
# bash 3.2 portable (macOS default /bin/bash). No arrays-of-arrays, no
# associative arrays, no `mapfile`.

set -euo pipefail

# --- globals ---
DRY_RUN=0
ASSUME_YES=0
PRUNE_LABELS=0
SKIP_PROJECT=0
KEEP_TEMPLATE_DOCS=0
REPO=""       # owner/name
OWNER=""
REPO_NAME=""

# Phase result tracking (parallel newline-delimited lists; bash 3.2 has no
# associative arrays).
PHASE_NAMES=""
PHASE_RESULTS=""
MANUAL_STEPS=""

# --- colors (disabled when not a tty) ---
if [ -t 1 ]; then
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_RED=$'\033[31m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_RED=""; C_BOLD=""; C_RESET=""
fi

ok()     { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
doing()  { printf '%s→%s %s\n' "$C_BLUE" "$C_RESET" "$1"; }
skip()   { printf '%sskip%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
warn()   { printf '%sWARN%s %s\n' "$C_YELLOW" "$C_RESET" "$1" >&2; }
fail()   { printf '%sFAIL%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }
manual() { printf '%sMANUAL%s %s\n' "$C_BOLD" "$C_RESET" "$1"; MANUAL_STEPS="${MANUAL_STEPS}- ${1}
"; }

record_phase() {
  # record_phase <name> <result: ok|warn|fail|skip>
  PHASE_NAMES="${PHASE_NAMES}${1}
"
  PHASE_RESULTS="${PHASE_RESULTS}${2}
"
}

# run_or_dry is the single choke point for every mutating gh call. Every
# `gh` call that creates/updates/deletes state MUST go through this; in
# --dry-run mode it only prints the command and never executes it.
run_or_dry() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s[dry-run]%s would run: %s\n' "$C_YELLOW" "$C_RESET" "$*"
    return 0
  fi
  "$@"
}

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh [options]

One-time (and re-runnable) setup for a repo created from the
"GitHub Project OS" template. Requires the GitHub CLI (gh), authenticated.

Options:
  --dry-run             Print every action that would be taken; execute nothing.
  --yes                 Assume "yes" to all prompts; accept defaults, no interaction.
  --prune               Delete repo labels not declared in .github/labels.yml,
                         without prompting (implies the default prune behavior).
  --skip-project        Skip phase 4 (GitHub Project creation / field setup).
  --keep-template-docs  Skip phase 8 (de-templating); keep docs/template/ and
                         the starter README in place.
  --help                Show this help and exit.

Phases:
  0. Preflight          gh installed, authenticated, scopes, target repo
  1. Labels             sync .github/labels.yml, prompt to prune extras
  2. Issue types        check native Bug/Feature/Task availability
  3. Milestone          create v0.1.0 if missing
  4. Project            create Project v2 board + Effort field (see --skip-project)
  5. Repo settings       merge strategy, delete-branch-on-merge, wiki off
  6. Actions permission  enable Actions to create/approve PRs (release-please)
  7. Ruleset             import .github/rulesets/main-branch.json
  8. De-template         convert repo from template docs to your project (see --keep-template-docs)

Docs: docs/setup/bootstrap.md (manual fallback + reference for every phase).
EOF
}

# --- arg parsing ---
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes) ASSUME_YES=1 ;;
    --prune) PRUNE_LABELS=1 ;;
    --skip-project) SKIP_PROJECT=1 ;;
    --keep-template-docs) KEEP_TEMPLATE_DOCS=1 ;;
    --help|-h) usage; exit 0 ;;
    *)
      fail "unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

# confirm <prompt> <default: y|n> → returns 0 for yes, 1 for no. Always
# yes under --yes.
confirm() {
  local prompt="$1" default="$2" reply
  if [ "$ASSUME_YES" -eq 1 ]; then
    return 0
  fi
  if [ "$default" = "y" ]; then
    printf '%s [Y/n] ' "$prompt"
  else
    printf '%s [y/N] ' "$prompt"
  fi
  read -r reply || reply=""
  if [ -z "$reply" ]; then
    reply="$default"
  fi
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Phase 0 — Preflight ---

phase_preflight() {
  doing "Phase 0: preflight checks"

  if [ ! -f "AGENTS.md" ] || [ ! -d ".git" ]; then
    fail "must be run from the repository root (AGENTS.md and .git not found here)"
    exit 1
  fi
  if ! command -v gh >/dev/null 2>&1; then
    fail "GitHub CLI (gh) is not installed — https://cli.github.com/"
    exit 1
  fi
  ok "gh CLI found ($(gh --version | head -n1))"
  if ! gh auth status >/dev/null 2>&1; then
    fail "gh is not authenticated — run: gh auth login"
    exit 1
  fi
  ok "gh is authenticated"

  # Parse `gh auth status` for granted scopes, e.g.:
  #   "  Token scopes: 'repo', 'read:org', 'workflow'"
  local scopes_line
  scopes_line="$(gh auth status 2>&1 | grep -i 'Token scopes' || true)"
  if printf '%s' "$scopes_line" | grep -q "'project'"; then
    ok "token has 'project' scope"
  else
    warn "token scopes do not list 'project' — Project creation (phase 4) may fail"
    warn "fix: gh auth refresh -s project"
  fi
  if printf '%s' "$scopes_line" | grep -Eq "'repo'"; then
    ok "token has 'repo' scope"
  else
    warn "token scopes do not clearly list 'repo' — some phases may fail"
    warn "fix: gh auth refresh -s repo"
  fi

  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  if [ -z "$REPO" ]; then
    fail "could not detect target repo via 'gh repo view' — are you inside a GitHub-hosted git repo with a remote?"
    exit 1
  fi
  OWNER="${REPO%%/*}"
  REPO_NAME="${REPO##*/}"
  printf '\n%sTarget repository:%s %s\n\n' "$C_BOLD" "$C_RESET" "$REPO"
  [ "$DRY_RUN" -eq 1 ] && ok "dry-run mode — no mutations will be executed"

  if ! confirm "Proceed with bootstrap against ${REPO}?" "y"; then
    fail "aborted by user"
    exit 1
  fi
  record_phase "0. Preflight" "ok"
}

# --- Phase 1 — Labels ---

# parse_labels_yml reads .github/labels.yml (fixed structure) and emits
# "name<TAB>color<TAB>description" lines. No yq dependency — the file format
# is a flat list of `- name: / color: / description:` entries.
#
# Supported format ONLY: exactly one `- name:`, `color:`, `description:` key
# per entry, each on its own unquoted single line, in that order. YAML
# quoting (`name: "foo"`), multi-line block scalars (`description: |`),
# inline comments (`color: e4e669 # note`), and flow/inline mappings are
# NOT supported and will parse incorrectly or silently. Keep labels.yml to
# the flat format documented in its own header comment.
parse_labels_yml() {
  local file="$1"
  awk '
    /^[[:space:]]*-[[:space:]]*name:/ {
      if (name != "") { print name "\t" color "\t" desc }
      name = $0
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", name)
      color = ""; desc = ""
      next
    }
    /^[[:space:]]*color:/ {
      color = $0
      sub(/^[[:space:]]*color:[[:space:]]*/, "", color)
      next
    }
    /^[[:space:]]*description:/ {
      desc = $0
      sub(/^[[:space:]]*description:[[:space:]]*/, "", desc)
      next
    }
    END {
      if (name != "") { print name "\t" color "\t" desc }
    }
  ' "$file"
}

phase_labels() {
  doing "Phase 1: labels (.github/labels.yml)"

  local labels_file=".github/labels.yml"
  if [ ! -f "$labels_file" ]; then
    warn "no ${labels_file} found — skipping label sync"
    record_phase "1. Labels" "skip"
    return
  fi

  local parsed
  parsed="$(parse_labels_yml "$labels_file")"

  if [ -z "$parsed" ]; then
    warn "${labels_file} parsed to zero labels — check its format"
    record_phase "1. Labels" "warn"
    return
  fi

  local declared_names=""
  local name color description
  while IFS=$'\t' read -r name color description; do
    [ -n "$name" ] || continue

    # Cheap validation: catch entries the awk parser mis-split (e.g. quoted
    # values, inline comments, multi-line scalars — see the format note atop
    # parse_labels_yml). A malformed color/name here means the file drifted
    # from the supported flat format, not that gh should be asked to guess.
    if [ -z "$color" ]; then
      fail "label '${name}': empty color in ${labels_file} — check format (see parse_labels_yml comment)"
      record_phase "1. Labels" "fail"
      return 1
    fi
    case "$color" in
      [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) : ;;
      *)
        fail "label '${name}': color '${color}' is not 6 hex digits in ${labels_file} — check format (see parse_labels_yml comment)"
        record_phase "1. Labels" "fail"
        return 1
        ;;
    esac

    declared_names="${declared_names}${name}
"
    run_or_dry gh label create "$name" --color "$color" --description "$description" --repo "$REPO" --force \
      || { fail "gh label create failed for '${name}'"; record_phase "1. Labels" "fail"; return 1; }
    ok "label: $name"
  done <<EOF
$parsed
EOF

  # Find repo labels not declared in labels.yml (prune candidates).
  #
  # Tool-managed labels: exclude anything matching `autorelease:*` from
  # pruning. These are release-please's own PR-state labels (e.g.
  # `autorelease: pending`, `autorelease: tagged`) — release-please creates
  # and manages them itself as part of its release-PR lifecycle, they are
  # never declared in .github/labels.yml, and deleting them breaks
  # release-please's state tracking. A live dogfood run pruned
  # `autorelease: pending` here and it had to be recreated; without this
  # exclusion, every bootstrap re-run would delete it again.
  local existing_names extra_names skipped_managed
  existing_names="$(gh label list --repo "$REPO" --limit 200 --json name -q '.[].name' 2>/dev/null || true)"
  extra_names=""
  skipped_managed=""
  if [ -n "$existing_names" ]; then
    while IFS= read -r existing; do
      [ -n "$existing" ] || continue
      if ! printf '%s\n' "$declared_names" | grep -qxF "$existing"; then
        case "$existing" in
          autorelease:*)
            skipped_managed="${skipped_managed}${existing}
"
            ;;
          *)
            extra_names="${extra_names}${existing}
"
            ;;
        esac
      fi
    done <<EOF
$existing_names
EOF
  fi

  if [ -n "$skipped_managed" ]; then
    printf '%s\n' "$skipped_managed" | sed '/^$/d' | while IFS= read -r managed; do
      skip "prune candidate '${managed}' (tool-managed)"
    done
  fi

  if [ -n "$extra_names" ]; then
    printf '\nLabels present on the repo but not declared in %s:\n' "$labels_file"
    printf '%s\n' "$extra_names" | sed '/^$/d' | sed 's/^/  - /'
    echo "(GitHub's default labels are noise under this taxonomy — pruning is the default.)"

    local do_prune=1
    if [ "$PRUNE_LABELS" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
      if ! confirm "Delete these labels?" "y"; then
        do_prune=0
      fi
    fi

    local prune_had_failure=0
    if [ "$do_prune" -eq 1 ]; then
      while IFS= read -r extra; do
        [ -n "$extra" ] || continue
        if run_or_dry gh label delete "$extra" --repo "$REPO" --yes; then
          ok "pruned label: $extra"
        else
          fail "gh label delete failed for '${extra}'"
          prune_had_failure=1
        fi
      done <<EOF
$extra_names
EOF
    else
      skip "label pruning (kept extra labels)"
    fi
    if [ "$prune_had_failure" -eq 1 ]; then
      record_phase "1. Labels" "fail"
      return 1
    fi
  else
    ok "no undeclared labels found"
  fi

  record_phase "1. Labels" "ok"
}

# --- Phase 2 — Issue types ---

phase_issue_types() {
  doing "Phase 2: native issue types"

  # Check the gh exit code explicitly instead of relying on stdout
  # emptiness: on an HTTP error (e.g. the guaranteed 404 on personal-account
  # repos) `gh api` prints the raw JSON error body to STDOUT — only the
  # one-line summary goes to stderr — so a plain `2>/dev/null || true`
  # capture would hold the error body as if it were data and never reach
  # the unavailable branch below.
  local types
  if ! types="$(gh api "repos/${REPO}/issue-types" --jq '.[].name' 2>/dev/null)"; then
    types=""
  fi

  if [ -z "$types" ]; then
    warn "repos/${REPO}/issue-types returned 404/empty"
    warn "native issue types are an ORGANIZATION-only GitHub feature:"
    warn "  - on an org repo: enable/verify Bug/Feature/Task in org settings (Organization settings -> Repository -> Issue types)"
    warn "  - on a PERSONAL account: this feature does not exist — issue forms' 'type:' key is silently ignored"
    warn "  see .github/PROJECT_FIELDS.md for the documented fallback on personal accounts"
    manual "Org repos: enable/verify native Bug/Feature/Task issue types in org settings. Personal accounts: the feature does not exist — see the 'Personal accounts' note in .github/PROJECT_FIELDS.md for the fallback"
    record_phase "2. Issue types" "warn"
    return
  fi

  local missing=""
  for t in Bug Feature Task; do
    if printf '%s\n' "$types" | grep -qxF "$t"; then
      ok "issue type present: $t"
    else
      missing="${missing}${t} "
    fi
  done

  if [ -n "$missing" ]; then
    warn "missing native issue type(s): $missing"
    manual "Add missing native issue type(s) in org/repo settings: $missing"
    record_phase "2. Issue types" "warn"
  else
    record_phase "2. Issue types" "ok"
  fi
}

# --- Phase 3 — Milestone ---

phase_milestone() {
  doing "Phase 3: v0.1.0 milestone"

  # state=all: milestones default to state=open-only on this endpoint, which
  # would miss a closed v0.1.0 and attempt to recreate it.
  # Exit code checked explicitly: on HTTP errors `gh api` prints the JSON
  # error body to stdout, so `|| true` would leave error text in $existing
  # (same failure mode as phase 2's issue-types check).
  local existing
  if ! existing="$(gh api "repos/${REPO}/milestones?state=all" --jq '.[].title' 2>/dev/null)"; then
    existing=""
  fi

  if printf '%s\n' "$existing" | grep -qxF "v0.1.0"; then
    ok "milestone v0.1.0 already exists"
    record_phase "3. Milestone" "ok"
    return
  fi

  local do_create=1
  if [ "$ASSUME_YES" -eq 0 ]; then
    if ! confirm "Create milestone v0.1.0 ('First release')?" "y"; then
      do_create=0
    fi
  fi

  if [ "$do_create" -eq 1 ]; then
    run_or_dry gh api -X POST "repos/${REPO}/milestones" \
      -f title="v0.1.0" \
      -f description="First release" \
      || { fail "gh api milestone create failed"; record_phase "3. Milestone" "fail"; return 1; }
    ok "milestone v0.1.0 created"
    record_phase "3. Milestone" "ok"
  else
    skip "milestone creation"
    record_phase "3. Milestone" "skip"
  fi
}

# --- Phase 4 — Project ---

# Target Status options for a fresh project (single-home contract —
# .github/PROJECT_FIELDS.md). Order matters: it's compared positionally
# against both the live field and the pristine-default set below.
STATUS_TARGET_OPTIONS='Backlog
Ready
In Progress
In Review
Blocked
Done'

# GitHub's out-of-the-box Status options on a brand-new Project v2 board.
# Only a field still holding exactly this set is safe to overwrite
# automatically — anything else means a human already customized it.
STATUS_DEFAULT_OPTIONS='Todo
In Progress
Done'

# options_match <a> <b> — true if two newline-delimited option lists are
# identical, including order. Pure string comparison, no gh/network calls,
# so this is unit-testable in isolation (see the harness invoked from the
# validation step for this change).
options_match() {
  [ "$1" = "$2" ]
}

# status_options_decision <project_already_existed: 0|1> <current_options>
# — prints the action phase_project must take for the Status field:
#   target-skip        options already equal the target set (idempotent)
#   rewrite            project was created by THIS bootstrap run and still
#                      holds the pristine defaults — the only state safe to
#                      auto-rewrite (a just-created board cannot have items)
#   preexisting-manual project pre-existed this run: never auto-rewrite,
#                      even when its options look like the pristine
#                      defaults — it may already carry items whose Status
#                      values a rewrite would orphan (options get new IDs)
#   custom-manual      options are neither target nor defaults — a human
#                      customized them; hands off
# Pure string logic, no gh/network calls — unit-testable in isolation.
status_options_decision() {
  local already_existed="$1" opts="$2"
  if options_match "$opts" "$STATUS_TARGET_OPTIONS"; then
    printf 'target-skip'
  elif ! options_match "$opts" "$STATUS_DEFAULT_OPTIONS"; then
    printf 'custom-manual'
  elif [ "$already_existed" -eq 0 ]; then
    printf 'rewrite'
  else
    printf 'preexisting-manual'
  fi
}

phase_project() {
  if [ "$SKIP_PROJECT" -eq 1 ]; then
    skip "Phase 4: Project (--skip-project)"
    record_phase "4. Project" "skip"
    return
  fi

  doing "Phase 4: GitHub Project"

  local title="${REPO_NAME} board"
  local existing_titles
  existing_titles="$(gh project list --owner "$OWNER" --format json --jq '.projects[].title' 2>/dev/null || true)"

  local project_already_existed=0
  local project_number=""
  if printf '%s\n' "$existing_titles" | grep -qxF "$title"; then
    ok "project '${title}' already exists"
    project_already_existed=1
    project_number="$(gh project list --owner "$OWNER" --format json --jq ".projects[] | select(.title==\"${title}\") | .number" 2>/dev/null | head -n1 || true)"
  elif [ "$DRY_RUN" -eq 1 ]; then
    run_or_dry gh project create --owner "$OWNER" --title "$title" \
      || { fail "gh project create failed"; record_phase "4. Project" "fail"; return 1; }
    project_number="DRY-RUN"
    ok "project '${title}' created"
  else
    local created_json
    created_json="$(gh project create --owner "$OWNER" --title "$title" --format json)" \
      || { fail "gh project create failed"; record_phase "4. Project" "fail"; return 1; }
    project_number="$(printf '%s' "$created_json" | grep -o '"number":[0-9]*' | head -n1 | cut -d: -f2)"
    ok "project '${title}' created"
  fi

  if [ -z "$project_number" ]; then
    warn "could not determine project number — skipping link/field-create steps"
    manual "Link the '${title}' project to ${REPO} and add the Effort field manually"
    record_phase "4. Project" "warn"
    return
  fi

  # gh project link errors if the project is already linked to this repo —
  # that's a successful/idempotent outcome on re-run, not a failure. Only a
  # freshly-created project needs an unconditional link attempt guarded the
  # same way (an already-existing project may already be linked).
  local link_output link_status=0
  link_output="$(run_or_dry gh project link "$project_number" --owner "$OWNER" --repo "$REPO" 2>&1)" || link_status=$?
  if [ "$link_status" -eq 0 ]; then
    printf '%s\n' "$link_output"
    ok "project linked to ${REPO}"
  elif printf '%s' "$link_output" | grep -qi "already linked"; then
    ok "project already linked to ${REPO}"
  else
    printf '%s\n' "$link_output" >&2
    fail "gh project link failed"
    record_phase "4. Project" "fail"
    return 1
  fi

  # Skip field-create when an "Effort" field already exists (re-run safety —
  # gh project field-create has no --force/upsert and would create a
  # duplicate field on every re-run otherwise).
  local existing_fields
  existing_fields="$(gh project field-list "$project_number" --owner "$OWNER" --format json --jq '.fields[].name' 2>/dev/null || true)"
  if printf '%s\n' "$existing_fields" | grep -qxF "Effort"; then
    ok "Effort field already exists — skip create"
  elif [ "$project_already_existed" -eq 1 ] && [ "$DRY_RUN" -eq 0 ] && [ -z "$existing_fields" ]; then
    # field-list came back empty/unreadable for a pre-existing project —
    # do not risk a duplicate field; require a manual check instead.
    warn "could not list fields for existing project '${title}' — skipping Effort field-create to avoid a duplicate"
    manual "Verify the 'Effort' single-select field (S/M/L) exists on project '${title}'; add it manually if missing"
  else
    run_or_dry gh project field-create "$project_number" --owner "$OWNER" \
      --name "Effort" --data-type "SINGLE_SELECT" \
      --single-select-options "S,M,L" \
      || { fail "gh project field-create failed"; record_phase "4. Project" "fail"; return 1; }
    ok "Effort field created (S/M/L)"
  fi

  # Status options — set the single-home contract's target set
  # (Backlog/Ready/In Progress/In Review/Blocked/Done) via
  # updateProjectV2Field(singleSelectOptions:...). Auto-rewrite is only
  # safe on a project THIS run just created (still on pristine defaults,
  # guaranteed item-free): rewriting options assigns new option IDs, so on
  # any pre-existing project — even one whose options happen to look like
  # the untouched defaults — it could silently orphan the Status values of
  # items already on the board. Everything except the just-created case is
  # therefore skip (already target) or WARN + MANUAL (pre-existing or
  # customized). Decision logic lives in status_options_decision above.
  #
  # Skipped entirely for a project just created under --dry-run: its
  # "project_number" is the "DRY-RUN" placeholder (no real project exists
  # yet to query), matching the same fall-through the Effort field-create
  # step above relies on.
  if [ "$project_number" = "DRY-RUN" ]; then
    printf '%s[dry-run]%s would set Status options to the target set (Backlog/Ready/In Progress/In Review/Blocked/Done) on the newly created project\n' "$C_YELLOW" "$C_RESET"
  else
    local status_field_id status_options
    status_field_id="$(gh project field-list "$project_number" --owner "$OWNER" --format json --jq '.fields[] | select(.name=="Status") | .id' 2>/dev/null || true)"

    if [ -z "$status_field_id" ]; then
      warn "could not determine the Status field id on project '${title}' — skipping Status options"
      manual "Verify the Status field on project '${title}' has options Backlog/Ready/In Progress/In Review/Blocked/Done; set them by hand if not — see docs/setup/project-views.md"
    else
      status_options="$(gh project field-list "$project_number" --owner "$OWNER" --format json --jq '.fields[] | select(.name=="Status") | .options[].name' 2>/dev/null || true)"

      case "$(status_options_decision "$project_already_existed" "$status_options")" in
        target-skip)
          ok "Status options already match the target set — skip"
          ;;
        rewrite)
          # Single-quoted on purpose: $fieldId inside is a GraphQL variable
          # reference for gh to substitute via -f fieldId=..., not a shell
          # variable to expand here.
          # shellcheck disable=SC2016
          run_or_dry gh api graphql -f query='
            mutation($fieldId: ID!) {
              updateProjectV2Field(input: {
                fieldId: $fieldId,
                singleSelectOptions: [
                  {name: "Backlog", color: GRAY, description: "Not committed yet"},
                  {name: "Ready", color: GREEN, description: "Scoped and claimable (agent-ok issues are self-service here)"},
                  {name: "In Progress", color: YELLOW, description: "Being worked"},
                  {name: "In Review", color: ORANGE, description: "PR open, awaiting review"},
                  {name: "Blocked", color: RED, description: "Waiting on dependency or decision"},
                  {name: "Done", color: PURPLE, description: "Merged / completed"}
                ]
              }) {
                projectV2Field {
                  ... on ProjectV2SingleSelectField { id }
                }
              }
            }' -f fieldId="$status_field_id" \
            || { fail "gh api graphql updateProjectV2Field failed"; record_phase "4. Project" "fail"; return 1; }
          ok "Status options set to Backlog/Ready/In Progress/In Review/Blocked/Done"
          ;;
        preexisting-manual)
          warn "project '${title}' pre-existed this run — not rewriting its Status options (items may already reference them)"
          manual "Project '${title}' pre-existed bootstrap — set its Status options to Backlog/Ready/In Progress/In Review/Blocked/Done by hand (see docs/setup/project-views.md)"
          ;;
        *)
          warn "Status field on project '${title}' has custom options — not overwriting"
          manual "Project '${title}' Status field has non-default options — edit it by hand to Backlog/Ready/In Progress/In Review/Blocked/Done (see docs/setup/project-views.md) if that's what you want"
          ;;
      esac
    fi
  fi

  manual "GitHub's API cannot create views — follow docs/setup/project-views.md for the 3 views"

  record_phase "4. Project" "ok"
}

# --- Phase 5 — Repo settings ---

phase_repo_settings() {
  doing "Phase 5: repo settings"

  # rebase stays on: release-please merges its own PR via normal PR merge;
  # squash is the human default per AGENTS.md; wiki off = docs live in-repo.
  run_or_dry gh api -X PATCH "repos/${REPO}" \
    -F allow_squash_merge=true \
    -F allow_merge_commit=false \
    -F allow_rebase_merge=true \
    -F delete_branch_on_merge=true \
    -F has_issues=true \
    -F has_wiki=false \
    || { fail "gh api repo settings PATCH failed"; record_phase "5. Repo settings" "fail"; return 1; }

  ok "merge strategy: squash + rebase allowed, merge commits disabled"
  ok "delete_branch_on_merge=true, has_issues=true, has_wiki=false"

  record_phase "5. Repo settings" "ok"
}

# --- Phase 6 — Actions PR permission ---

phase_actions_permission() {
  doing "Phase 6: Actions PR creation/approval permission"

  cat <<'EOF'
release-please opens and updates its own release PR from a workflow run. By
default GitHub Actions cannot create or approve pull requests, which makes
release-please fail with:
  "GitHub Actions is not permitted to create or approve pull requests"
EOF

  local do_enable=1
  if [ "$ASSUME_YES" -eq 0 ]; then
    if ! confirm "Enable 'Actions can create and approve pull requests'?" "y"; then
      do_enable=0
    fi
  fi

  if [ "$do_enable" -eq 1 ]; then
    run_or_dry gh api -X PUT "repos/${REPO}/actions/permissions/workflow" \
      -f default_workflow_permissions=read \
      -F can_approve_pull_request_reviews=true \
      || { fail "gh api Actions permissions PUT failed"; record_phase "6. Actions permission" "fail"; return 1; }
    ok "Actions can now create and approve pull requests"
    record_phase "6. Actions permission" "ok"
  else
    skip "Actions PR permission (release-please will fail until this is enabled)"
    manual "Enable Settings → Actions → General → 'Allow GitHub Actions to create and approve pull requests', or release-please will fail"
    record_phase "6. Actions permission" "skip"
  fi
}

# --- Phase 7 — Ruleset ---

phase_ruleset() {
  doing "Phase 7: branch ruleset"

  local ruleset_file=".github/rulesets/main-branch.json"
  if [ ! -f "$ruleset_file" ]; then
    warn "no ${ruleset_file} found — skipping ruleset import"
    record_phase "7. Ruleset" "skip"
    return
  fi

  # Exit code checked explicitly: on HTTP errors `gh api` prints the JSON
  # error body to stdout, so `|| true` would leave error text in $existing
  # (same failure mode as phase 2's issue-types check).
  local existing
  if ! existing="$(gh api "repos/${REPO}/rulesets" --jq '.[].name' 2>/dev/null)"; then
    existing=""
  fi

  if printf '%s\n' "$existing" | grep -qxF "main-branch-protection"; then
    ok "ruleset 'main-branch-protection' already exists — rulesets are create-once, this run will NOT sync changes; delete it on GitHub (Settings → Rules → Rulesets) and re-run to update"
    record_phase "7. Ruleset" "skip"
    return
  fi

  run_or_dry gh api -X POST "repos/${REPO}/rulesets" --input "$ruleset_file" \
    || { fail "gh api ruleset POST failed"; record_phase "7. Ruleset" "fail"; return 1; }
  ok "ruleset 'main-branch-protection' created"
  record_phase "7. Ruleset" "ok"
}

# --- Phase 8 — De-template ---

CHANGELOG_SEED='# Changelog

All notable changes are recorded here by release-please (Conventional Commits
drive the entries — see docs/adr/ADR-0002-release-flow.md).

## Unreleased

No entries yet.
'

phase_detemplate() {
  if [ "$KEEP_TEMPLATE_DOCS" -eq 1 ]; then
    skip "Phase 8: de-template (--keep-template-docs)"
    record_phase "8. De-template" "skip"
    return
  fi

  doing "Phase 8: de-template"

  if [ ! -d "docs/template" ]; then
    ok "docs/template/ absent — repo is already de-templated, nothing to do"
    record_phase "8. De-template" "skip"
    return
  fi

  # Worktree guard: de-templating mutates/deletes README.md, CHANGELOG.md,
  # docs/template/, and .release-please-manifest.json with no undo. If any
  # of those paths already carry uncommitted changes, a failure partway
  # through (or just an unwanted mix of manual + generated edits) is
  # unrecoverable via git. Require a clean state on exactly these paths
  # before mutating anything — unconditionally, --yes does not bypass this.
  local dirty_paths
  dirty_paths="$(git status --porcelain -- README.md CHANGELOG.md docs/template .release-please-manifest.json 2>/dev/null || true)"
  if [ -n "$dirty_paths" ]; then
    warn "de-template skipped: affected paths have uncommitted changes — commit or stash first"
    printf '%s\n' "$dirty_paths" | sed 's/^/  /'
    record_phase "8. De-template" "skip"
    return
  fi

  local do_detemplate=1
  if [ "$ASSUME_YES" -eq 0 ]; then
    cat <<'EOF'
This converts this repo from the template product to YOUR project:
  - docs/template/README.starter.md becomes README.md
  - docs/template/ is removed
  - CHANGELOG.md is reset to its 8-line seed
EOF
    if ! confirm "Proceed with de-templating?" "y"; then
      do_detemplate=0
    fi
  fi

  if [ "$do_detemplate" -eq 0 ]; then
    skip "de-templating"
    record_phase "8. De-template" "skip"
    return
  fi

  # The rm -rf below must be unreachable unless the mv is verifiably safe:
  # either there was no starter README to move (nothing to lose), or the mv
  # ran and left a verified README.md with the source gone. Never fall
  # through to deleting docs/template/ on an unverified/failed mv — that is
  # exactly the "README lost" failure mode this guard exists to prevent.
  local readme_source="docs/template/README.starter.md"
  local safe_to_remove_template=0
  if [ -f "$readme_source" ]; then
    if run_or_dry mv "$readme_source" README.md; then
      if [ "$DRY_RUN" -eq 1 ]; then
        # dry-run never actually moves the file; trust the no-op contract.
        safe_to_remove_template=1
        ok "[dry-run] README.md would be replaced with ${readme_source}"
      elif [ -f "README.md" ] && [ ! -f "$readme_source" ]; then
        safe_to_remove_template=1
        ok "README.md replaced with ${readme_source}"
      else
        fail "mv reported success but README.md / ${readme_source} state is not as expected — refusing to remove docs/template/"
        record_phase "8. De-template" "fail"
        return 1
      fi
    else
      fail "mv ${readme_source} README.md failed — refusing to remove docs/template/"
      record_phase "8. De-template" "fail"
      return 1
    fi
  else
    warn "${readme_source} not found — leaving README.md as-is"
    safe_to_remove_template=1
  fi

  if [ "$safe_to_remove_template" -ne 1 ]; then
    fail "de-template: mv step did not verify as safe — aborting before docs/template/ removal"
    record_phase "8. De-template" "fail"
    return 1
  fi

  run_or_dry rm -rf docs/template \
    || { fail "rm -rf docs/template failed"; record_phase "8. De-template" "fail"; return 1; }
  ok "docs/template/ removed"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s[dry-run]%s would reset CHANGELOG.md to its 8-line seed\n' "$C_YELLOW" "$C_RESET"
  else
    printf '%s' "$CHANGELOG_SEED" > CHANGELOG.md \
      || { fail "writing CHANGELOG.md failed"; record_phase "8. De-template" "fail"; return 1; }
  fi
  ok "CHANGELOG.md reset to seed"

  local manifest='.release-please-manifest.json'
  local want='{".":"0.0.0"}'
  local have=""
  if [ -f "$manifest" ]; then
    have="$(tr -d '[:space:]' < "$manifest")"
  fi
  if [ "$have" = "$want" ]; then
    ok "${manifest} already at {\".\": \"0.0.0\"}"
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '%s[dry-run]%s would rewrite %s to {".": "0.0.0"}\n' "$C_YELLOW" "$C_RESET" "$manifest"
    else
      printf '{\n  ".": "0.0.0"\n}\n' > "$manifest" \
        || { fail "writing ${manifest} failed"; record_phase "8. De-template" "fail"; return 1; }
    fi
    ok "${manifest} rewritten to {\".\": \"0.0.0\"}"
  fi

  cat <<'EOF'

Note: release-as: 0.1.0 stays in release-please-config.json — your first
release is v0.1.0; remove that key afterwards so subsequent releases
follow normal Conventional Commit bumps.
EOF
  manual "Remove the 'release-as: 0.1.0' key from release-please-config.json after your first release ships"

  record_phase "8. De-template" "ok"
}

# --- Summary ---

print_summary() {
  printf '\n%s=== Bootstrap summary ===%s\n\n' "$C_BOLD" "$C_RESET"

  # Walk parallel newline-delimited lists.
  local names_left="$PHASE_NAMES" results_left="$PHASE_RESULTS"
  local name result
  while [ -n "$names_left" ]; do
    name="${names_left%%$'\n'*}"
    names_left="${names_left#*$'\n'}"
    result="${results_left%%$'\n'*}"
    results_left="${results_left#*$'\n'}"
    [ -n "$name" ] || continue

    case "$result" in
      ok)   printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$name" ;;
      warn) printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$name" ;;
      skip) printf '  %s-%s %s\n' "$C_YELLOW" "$C_RESET" "$name" ;;
      *)    printf '  %sx%s %s\n' "$C_RED" "$C_RESET" "$name" ;;
    esac
  done

  if [ -n "$MANUAL_STEPS" ]; then
    printf '\n%sRemaining MANUAL steps:%s\n' "$C_BOLD" "$C_RESET"
    printf '%s' "$MANUAL_STEPS" | sed '/^$/d' | sed 's/^- /  [ ] /'
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '\n%sDry run only — zero mutations were executed.%s\n' "$C_YELLOW" "$C_RESET"
  else
    printf '\nBootstrap does not commit anything. Next steps:\n'
    printf '  1. Review: git status\n'
    printf '  2. Commit: git add -A && git commit -m "chore: bootstrap repository"\n'
  fi
  echo ""
}

# --- Main ---

# run_phase <phase-fn> <phase-label> — every phase_* function now guards
# and records its own result on every exit path (mutating commands are
# guarded explicitly with `|| { fail ...; record_phase ...; return 1; }`
# rather than relying on `set -e`, which is suspended for the duration of a
# function invoked as the left side of `||` — see phase function bodies).
# This wrapper is a defensive fallback ONLY: it records a "fail" for the
# phase label if — and only if — the phase function returned non-zero
# without recording anything itself (e.g. an unexpected/unguarded error).
# It never double-records a phase that already recorded its own result.
run_phase() {
  local phase_fn="$1" phase_label="$2"
  local names_before="$PHASE_NAMES"
  if ! "$phase_fn"; then
    if [ "$PHASE_NAMES" = "$names_before" ]; then
      fail "${phase_label}: exited non-zero without recording a result — treating as fail"
      record_phase "$phase_label" "fail"
    fi
  fi
}

main() {
  phase_preflight

  # Phases 1-8: failures are collected, not fatal — preflight is the only
  # phase whose failure aborts the whole run.
  run_phase phase_labels "1. Labels"
  run_phase phase_issue_types "2. Issue types"
  run_phase phase_milestone "3. Milestone"
  run_phase phase_project "4. Project"
  run_phase phase_repo_settings "5. Repo settings"
  run_phase phase_actions_permission "6. Actions permission"
  run_phase phase_ruleset "7. Ruleset"
  run_phase phase_detemplate "8. De-template"

  print_summary
}

main "$@"
