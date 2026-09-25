#!/usr/bin/env bash
# check-label-forms.sh — label values repeated outside .github/labels.yml
# must still match it.
#
# .github/labels.yml is the taxonomy's single home (skills/labels-and-taxonomy
# rule 1), but three issue forms and the labeler source repeat some of its
# values as static text, and nothing else notices when they drift: the form
# still renders, the labeler still exits green, and ticking a box that names a
# label the repo no longer has applies nothing. A downstream adopter renamed
# area:* (as the template tells them to) and found out two weeks later.
#
# Verifies:
# Every *.yml / *.yaml in the forms directory except config.yml is a form —
# discovered, not listed, so a renamed or added form is checked too. A form
# is checked for whichever of the three managed fields (ids area, priority,
# subtype) it has.
#
#   a. a form's Area checkboxes    == the area:* set in labels.yml
#   b. a form's Priority dropdown  == the priority:* set in labels.yml
#   c. the labeler's ALLOWED_PRIORITIES == the priority:* set in labels.yml
#   d. a form's Subtype dropdown   == the type:* set in labels.yml minus
#      type:bug / type:feature, and the labeler's ALLOWED_SUBTYPES == the same
#   e. type:bug / type:feature never appear in a Subtype dropdown — the
#      labeler's subtype allowlist exists so an untrusted issue body cannot
#      mint a coarse Type (ADR-0006); this pins that property.
#   f. no `- name:` entry in labels.yml is quoted — the header forbids it,
#      and bootstrap would create a label with the quotes in its name.
#
# Option text convention: `<name> — <description>`. An option is resolved to
# a name the same way the labeler resolves it from the issue body: the
# longest declared name the option text starts with, followed by the end of
# the text or a dash (—, – or -) with whitespace on both sides. E.g.
# `- label: "area:docs — Documentation and guides"` resolves to area:docs and
# `- "p0 — Critical, drop everything"` to p0. Only the names are compared; the
# description is free. Names may contain spaces, punctuation, even a spaced
# dash (see h. for what older labelers can and cannot read). An option that
# resolves to no declared name is reported as `?<option text>`.
#
#   j. while a labeler exists, each managed field it reads must keep
#      the heading it reads — `label: Priority`, `label: Subtype`,
#      `label: Area` — because the issue body carries headings, not field
#      ids; renaming one blinds the labeler while ids and options still match.
#      An adopter who removed the labeler is free to rename headings.
#
# The labeler's area:* handling depends on its version, and this script may
# run in an adopted repo carrying an older copy, so it looks at the file:
#   g. if the labeler still declares a hardcoded ALLOWED_AREAS constant, that
#      constant must equal the area:* set (newer labelers read labels.yml at
#      run time and have no such constant — reported, not failed);
#   h. if the labeler still extracts area names with the `[a-z-]` grammar,
#      every area:* name must fit it, or the box would tick and apply nothing;
#      likewise the short-lived `area:\S+` grammar cannot read a name with
#      whitespace (current labelers match against the allowlist instead).
#   i. if the labeler still pre-filters priorities with /^(p[0-3])\b/ or
#      subtypes with a literal alternation, those must agree with the
#      allowlists — a consistently declared priority:p4 would otherwise pass
#      every set comparison and be ignored at run time (newer labelers match
#      the leading token and let the allowlist decide).
#
# Usage: scripts/check-label-forms.sh [labels-yml] [forms-dir] [labeler-source]
#   Defaults: .github/labels.yml .github/ISSUE_TEMPLATE, and for the labeler
#   source scripts/issue-labeler.js when it exists (the logic lives there
#   since ADR-0008), else .github/workflows/issue-labeler.yml (older copies
#   carry the script inline). The overrides exist so the parser can be
#   exercised against fixtures.
#
# Exit status: 0 if every check passes, 1 otherwise.

set -euo pipefail

cd "$(dirname "$0")/.."

LABELS_FILE="${1:-.github/labels.yml}"
FORMS_DIR="${2:-.github/ISSUE_TEMPLATE}"
LABELER_FILE="${3:-}"
WORKFLOW_FILE=.github/workflows/issue-labeler.yml
mixed_generations=0
if [ -z "$LABELER_FILE" ]; then
  if [ -f scripts/issue-labeler.js ]; then
    LABELER_FILE=scripts/issue-labeler.js
    # The script exists, but is the workflow the thin caller that runs it? An
    # adopter who took scripts/ and kept an inline workflow is still running
    # the inline copy — validate that, and say the set is torn.
    if [ -f "$WORKFLOW_FILE" ] && grep -qE 'const ALLOWED_' "$WORKFLOW_FILE"; then
      LABELER_FILE="$WORKFLOW_FILE"
      mixed_generations=1
    fi
  else
    LABELER_FILE="$WORKFLOW_FILE"
  fi
fi

FALLBACK_TYPES="type:bug type:feature"

fail_count=0
ok_count=0

fail() {
  echo "FAIL: $1"
  fail_count=$((fail_count + 1))
}

ok() {
  echo "OK: $1"
  ok_count=$((ok_count + 1))
}

# Every `- name:` entry in labels.yml, one per line. The same reading as
# parse_labels_yml in scripts/bootstrap.sh and the labeler: the name
# is the rest of the line, trimmed — no quote or comment stripping, so a
# quoted or inline-commented entry surfaces here as a mismatch, exactly as it
# would misbehave in bootstrap. Whole-line comments never match.
label_names() {
  awk '
    /^[[:space:]]*-[[:space:]]*name:/ {
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
    }
  ' "$1"
}

# Option texts of the form field whose `id:` is $2, in form $1, one per line,
# quotes stripped. The field block starts at its `id:` line and ends at the
# next `- type:` field. Inside it, option lines are `- label: <text>`
# (checkboxes) or `- <text>` (dropdown), quoted or plain.
form_option_texts() {
  awk -v want="$2" '
    /^[[:space:]]*-[[:space:]]*type:/ { inblock = 0 }
    /^[[:space:]]*id:[[:space:]]*/ {
      id = $0
      sub(/^[[:space:]]*id:[[:space:]]*/, "", id)
      sub(/[[:space:]]+$/, "", id)
      inblock = (id == want)
      next
    }
    inblock && /^[[:space:]]*-[[:space:]]*/ {
      opt = $0
      sub(/^[[:space:]]*-[[:space:]]*(label:[[:space:]]*)?/, "", opt)
      sub(/[[:space:]]+$/, "", opt)
      # quoted or plain scalar: strip one pair of matching outer quotes only
      if (opt ~ /^".*"$/ || opt ~ /^'"'"'.*'"'"'$/) { opt = substr(opt, 2, length(opt) - 2) }
      if (opt != "") print opt
    }
  ' "$1"
}

# resolve_option <text> <declared-names, newline-separated> — prints the
# longest declared name the text starts with, followed by end-of-text or a
# spaced dash; prints `?<text>` when none does.
resolve_option() {
  local text="$1" names="$2" name rest
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$text" in
      "$name")   printf '%s\n' "$name"; return 0 ;;
      "$name"*)  rest="${text#"$name"}"
                 if printf '%s' "$rest" | grep -qE '^[[:space:]]+(—|–|-)[[:space:]]+'; then
                   printf '%s\n' "$name"; return 0
                 fi ;;
    esac
  done <<EOF_NAMES
$(printf '%s\n' "$names" | awk '{ print length($0) "\t" $0 }' | sort -t"$(printf '\t')" -k1,1nr | cut -f2-)
EOF_NAMES
  printf '?%s\n' "$text"
}

# form_options <form> <field-id> <declared-names> [lower] — each option
# resolved. With `lower`, the option text is folded to lowercase first: the
# labeler lowercases dropdown answers before matching (so `P0 — Critical`
# still resolves to p0) but reads checkbox lines as written.
form_options() {
  local text
  form_option_texts "$1" "$2" | while IFS= read -r text; do
    [ -n "$text" ] || continue
    if [ "${4:-}" = lower ]; then text="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"; fi
    resolve_option "$text" "$3"
  done
}

# Does form $1 declare a field whose `id:` is $2?
has_field() { grep -qE "^[[:space:]]*id:[[:space:]]*$2[[:space:]]*$" "$1"; }

# The `label:` attribute (the heading the issue body will carry) of the form
# field whose `id:` is $2, in form $1.
form_heading() {
  awk -v want="$2" '
    /^[[:space:]]*-[[:space:]]*type:/ { inblock = 0 }
    /^[[:space:]]*id:[[:space:]]*/ {
      id = $0
      sub(/^[[:space:]]*id:[[:space:]]*/, "", id)
      sub(/[[:space:]]+$/, "", id)
      inblock = (id == want)
      next
    }
    inblock && /^[[:space:]]*label:[[:space:]]*/ {
      h = $0
      sub(/^[[:space:]]*label:[[:space:]]*/, "", h)
      sub(/[[:space:]]+$/, "", h)
      # strip one pair of matching outer quotes only; inner ones are content
      if (h ~ /^".*"$/ || h ~ /^'"'"'.*'"'"'$/) { h = substr(h, 2, length(h) - 2) }
      print h
      exit
    }
  ' "$1"
}

# Items of the `const NAME = [ ... ];` array in the labeler, one per line —
# collected from the opening bracket to the first closing bracket, so a
# formatter wrapping the array across lines changes nothing.
labeler_list() {
  awk -v name="$2" '
    index($0, "const " name " = [") { collecting = 1; sub(/.*\[/, "") }
    collecting {
      if (index($0, "]")) { sub(/\].*/, ""); print; exit }
      print
    }
  ' "$1" \
    | tr ',' '\n' \
    | sed -E "s/[[:space:]'\"]//g" \
    | grep -v '^$' || true
}

# stdin filter: prefix every non-empty line, sort, dedupe.
with_prefix() { sed "s/^/$1/" | grep -v "^$1\$" | sort -u || true; }

# compare <what> <expected-lines> <found-lines> <hint>
compare() {
  local what="$1" expected="$2" found="$3" hint="$4"
  if [ "$expected" = "$found" ]; then
    ok "$what"
  else
    fail "$what"
    echo "      expected: $(printf '%s\n' "$expected" | sed "s/.*/'&'/" | tr '\n' ' ')"
    echo "      found:    $(printf '%s\n' "$found" | sed "s/.*/'&'/" | tr '\n' ' ')"
    [ -n "$hint" ] && echo "      $hint"
  fi
}

if [ ! -f "$LABELS_FILE" ]; then
  fail "$LABELS_FILE not found — it is the single home for every label value"
  echo ""
  echo "Summary: $ok_count OK, $fail_count FAIL"
  exit 1
fi

all_names="$(label_names "$LABELS_FILE")"

# --- f: quoting that bootstrap would pass through verbatim
quoted="$(printf '%s\n' "$all_names" | grep -E '^["'"'"']' || true)"
if [ -n "$quoted" ]; then
  fail "$LABELS_FILE has quoted name entries — the header rules out YAML quoting, and bootstrap would create the label with the quotes in it: $(printf '%s\n' "$quoted" | tr '\n' ' ')"
else
  ok "$LABELS_FILE name entries are unquoted"
fi
areas="$(printf '%s\n' "$all_names" | grep '^area:' | sort -u || true)"
priorities="$(printf '%s\n' "$all_names" | grep '^priority:' | sort -u || true)"
subtypes="$(printf '%s\n' "$all_names" | grep '^type:' | grep -v -x -e 'type:bug' -e 'type:feature' | sort -u || true)"

# --- a/b/d/e/j: forms vs labels.yml
forms_seen=0
for path in "$FORMS_DIR"/*.yml "$FORMS_DIR"/*.yaml; do
  [ -f "$path" ] || continue
  form="$(basename "$path")"
  case "$form" in config.yml|config.yaml) continue ;; esac
  forms_seen=$((forms_seen + 1))
  if has_field "$path" area; then
    found_areas="$(form_options "$path" area "$areas" | with_prefix '')"
    compare "$form Area options match the area:* set in $LABELS_FILE" "$areas" "$found_areas" \
      "fix: one \`- label: \"<name> — <text>\"\` line per area:* entry, under the field whose id is 'area'"
  fi
  if has_field "$path" priority; then
    found_prio="$(form_options "$path" priority "$(printf '%s\n' "$priorities" | sed 's/^priority://')" lower | with_prefix 'priority:')"
    compare "$form Priority options match the priority:* set in $LABELS_FILE" "$priorities" "$found_prio" \
      "fix: one \`- \"<pN> — <text>\"\` line per priority:* entry, under the field whose id is 'priority'"
  fi
  if has_field "$path" subtype; then
    found_sub="$(form_options "$path" subtype "$(printf '%s\n' "$subtypes" | sed 's/^type://')" lower | with_prefix 'type:')"
    compare "$form Subtype options match the type:* set in $LABELS_FILE minus the coarse-Type fallback labels" "$subtypes" "$found_sub" \
      "fix: one \`- \"<subtype> — <text>\"\` line per subtype, under the field whose id is 'subtype' (never bug or feature)"
    # --- e: the security property
    leaked=""
    for t in $FALLBACK_TYPES; do
      if printf '%s\n' "$found_sub" | grep -qx "$t"; then leaked="$leaked $t"; fi
    done
    if [ -n "$leaked" ]; then
      fail "$form Subtype dropdown offers$leaked — the coarse-Type fallback labels are applied by hand only, never from a form field an untrusted body can spoof (ADR-0006)"
    else
      ok "$form Subtype dropdown offers neither type:bug nor type:feature"
    fi
  fi
  # --- j: the headings the labeler reads (only while there is a labeler)
  [ -f "$LABELER_FILE" ] || [ -f .github/workflows/issue-labeler.yml ] || continue
  for pair in "area:Area" "priority:Priority" "subtype:Subtype"; do
    fid="${pair%%:*}"; want="${pair#*:}"
    has_field "$path" "$fid" || continue
    got="$(form_heading "$path" "$fid")"
    if [ "$got" = "$want" ]; then
      ok "$form field '$fid' keeps the heading the labeler reads: $want"
    else
      fail "$form field '$fid' has label '${got:-<missing>}' — the labeler reads the '### $want' heading from the issue body, so this field must keep label: $want"
    fi
  done
done
if [ "$forms_seen" -eq 0 ]; then
  echo "SKIP: no issue forms in $FORMS_DIR"
fi

# --- c/d: labeler constants
if [ "$mixed_generations" -eq 1 ]; then
  fail "$WORKFLOW_FILE still carries the labeler inline while scripts/issue-labeler.js also exists — the running labeler is the inline one; take the workflow and the script together (upgrading guide: https://github.com/TzuH-Hsu/github-project-os/blob/main/docs/template/upgrading.md)"
fi
if [ ! -f "$LABELER_FILE" ]; then
  echo "SKIP: $LABELER_FILE not present"
elif case "$LABELER_FILE" in *.yml|*.yaml) true ;; *) false ;; esac && grep -qF 'issue-labeler.js' "$LABELER_FILE" && grep -qF 'require(' "$LABELER_FILE"; then
  # The workflow is the thin caller shape (ADR-0008) but the script it
  # requires is not here: the labeler would fail on every issue event.
  fail "$LABELER_FILE requires scripts/issue-labeler.js, which is missing — take the workflow and the script together (upgrading guide: https://github.com/TzuH-Hsu/github-project-os/blob/main/docs/template/upgrading.md)"
else
  lab_prio="$(labeler_list "$LABELER_FILE" ALLOWED_PRIORITIES | with_prefix 'priority:')"
  compare "labeler ALLOWED_PRIORITIES matches the priority:* set in $LABELS_FILE" "$priorities" "$lab_prio" \
    "fix: edit the ALLOWED_PRIORITIES constant in $LABELER_FILE"
  lab_sub="$(labeler_list "$LABELER_FILE" ALLOWED_SUBTYPES | with_prefix 'type:')"
  compare "labeler ALLOWED_SUBTYPES matches the type:* set in $LABELS_FILE minus the coarse-Type fallback labels" "$subtypes" "$lab_sub" \
    "fix: edit the ALLOWED_SUBTYPES constant in $LABELER_FILE (never add bug or feature to it)"

  # --- g: older labelers hardcode the area allowlist
  if grep -qE 'const ALLOWED_AREAS = \[' "$LABELER_FILE"; then
    lab_areas="$(labeler_list "$LABELER_FILE" ALLOWED_AREAS | with_prefix '')"
    compare "labeler ALLOWED_AREAS matches the area:* set in $LABELS_FILE" "$areas" "$lab_areas" \
      "fix: edit the ALLOWED_AREAS constant in $LABELER_FILE — or take the labeler that reads labels.yml at run time (github-project-os #45)"
  elif grep -qF 'labels.yml' "$LABELER_FILE" && grep -qE 'loadAllowedAreas|readAllowedAreas' "$LABELER_FILE"; then
    ok "labeler reads area:* from $LABELS_FILE at run time (no ALLOWED_AREAS constant to drift)"
  else
    fail "labeler neither declares ALLOWED_AREAS nor loads it from .github/labels.yml — every Area selection would be ignored, or the script would throw"
    echo "      fix: take the labeler from github-project-os #45, or restore the ALLOWED_AREAS constant"
  fi

  # --- i: older labelers duplicate the allowlists as regexes
  if grep -qF '/^(p[0-3])\b/' "$LABELER_FILE"; then
    off="$(printf '%s\n' "$priorities" | grep -vE '^priority:p[0-3]$' || true)"
    if [ -n "$off" ]; then
      fail "labeler pre-filters priorities with /^(p[0-3])\\b/ and these are outside it (declared everywhere, ignored at run time): $(printf '%s\n' "$off" | tr '\n' ' ')"
      echo "      fix: take the labeler that matches the leading token against ALLOWED_PRIORITIES (github-project-os #45), or keep priorities within p0-p3"
    else
      ok "every priority:* fits the labeler's /^(p[0-3])\\b/ pre-filter"
    fi
  fi
  sub_re="$(grep -oE '/\^\(([a-z|]+)\)\\b/' "$LABELER_FILE" | grep -v 'p\[0-3\]' | head -n1 | sed -E 's#^/\^\((.*)\)\\b/$#\1#' || true)"
  if [ -n "$sub_re" ]; then
    re_set="$(printf '%s\n' "$sub_re" | tr '|' '\n' | with_prefix 'type:')"
    compare "labeler subtype pre-filter regex /^($sub_re)\\b/ matches ALLOWED_SUBTYPES" "$lab_sub" "$re_set" \
      "fix: take the labeler that matches the leading token against ALLOWED_SUBTYPES (github-project-os #45), or keep the regex and the constant equal"
  fi

  # --- h: older labelers only parse [a-z-] area names; one short-lived
  #        version took any non-whitespace token
  if grep -qF '(area:\S+)' "$LABELER_FILE"; then
    spaced="$(printf '%s\n' "$areas" | grep '[[:space:]]' || true)"
    if [ -n "$spaced" ]; then
      fail "labeler extracts area names as a single non-whitespace token and these contain whitespace (the box would tick and apply nothing): $(printf '%s\n' "$spaced" | sed "s/.*/'&'/" | tr '\n' ' ')"
      echo "      fix: take the labeler that matches against the allowlist (github-project-os #45), or remove the whitespace"
    else
      ok "no area:* name contains whitespace (the labeler reads a single token)"
    fi
  fi
  if grep -qF '/area:[a-z-]+/' "$LABELER_FILE"; then
    unparsable="$(printf '%s\n' "$areas" | grep -vE '^area:[a-z-]+$' || true)"
    if [ -n "$unparsable" ]; then
      fail "labeler extracts area names with /area:[a-z-]+/ and these names do not fit it (the box would tick and apply nothing): $(printf '%s\n' "$unparsable" | tr '\n' ' ')"
      echo "      fix: rename to lowercase letters and hyphens, or take the labeler from github-project-os #45"
    else
      ok "every area:* name fits the labeler's /area:[a-z-]+/ grammar"
    fi
  fi
fi

echo ""
echo "Summary: $ok_count OK, $fail_count FAIL"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

exit 0
