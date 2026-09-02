#!/usr/bin/env bash
# check-skills.sh — skills consistency check.
#
# Verifies:
#   a. every skills/*/ directory has a SKILL.md
#   b. each SKILL.md frontmatter has a valid name/description/category
#   c. every skill is indexed in skills/README.md and AGENTS.md
#   d. every index reference in skills/README.md / AGENTS.md points at a
#      skill that actually exists (reverse check)
#
# Usage: scripts/check-skills.sh [skills-dir]
#   skills-dir defaults to "skills" (relative to repo root). This override
#   exists so the parser logic can be exercised against a scratch fixture
#   directory without touching real skill files.
#
# Exit status: 0 if every check passes, 1 otherwise.

set -euo pipefail

cd "$(dirname "$0")/.."

SKILLS_DIR="${1:-skills}"
README_FILE="skills/README.md"
AGENTS_FILE="AGENTS.md"

VALID_CATEGORIES="planning delivery quality release governance ai-collaboration"

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

is_valid_category() {
  candidate="$1"
  for cat in $VALID_CATEGORIES; do
    if [ "$cat" = "$candidate" ]; then
      return 0
    fi
  done
  return 1
}

# Extract the value of a "key: value" line from the first frontmatter block
# of a file. Prints empty string if not found.
extract_frontmatter_field() {
  file="$1"
  field="$2"
  awk -v field="$field" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm {
      prefix = field ":"
      if (index($0, prefix) == 1) {
        value = substr($0, length(prefix) + 1)
        sub(/^[ \t]+/, "", value)
        sub(/[ \t]+$/, "", value)
        print value
        found = 1
        exit
      }
    }
    END {
      if (!found) print ""
    }
  ' "$file"
}

if [ ! -d "$SKILLS_DIR" ]; then
  fail "skills directory '$SKILLS_DIR' does not exist"
  echo ""
  echo "Summary: $ok_count OK, $fail_count FAIL"
  exit 1
fi

# --- a, b: per-skill directory checks -------------------------------------

skill_names=""

for dir in "$SKILLS_DIR"/*/; do
  [ -d "$dir" ] || continue
  skill_name="$(basename "$dir")"
  skill_md="${dir}SKILL.md"

  if [ ! -f "$skill_md" ]; then
    fail "$skill_name: missing SKILL.md"
    continue
  fi

  name_field="$(extract_frontmatter_field "$skill_md" "name")"
  description_field="$(extract_frontmatter_field "$skill_md" "description")"
  category_field="$(extract_frontmatter_field "$skill_md" "category")"

  skill_failed=0

  if [ "$name_field" != "$skill_name" ]; then
    fail "$skill_name: frontmatter name '$name_field' does not match directory name"
    skill_failed=1
  fi

  if [ -z "$description_field" ]; then
    fail "$skill_name: frontmatter description is empty"
    skill_failed=1
  elif [ "${description_field#Use when}" = "$description_field" ]; then
    fail "$skill_name: frontmatter description does not start with 'Use when'"
    skill_failed=1
  fi

  if [ -z "$category_field" ]; then
    fail "$skill_name: frontmatter category is empty"
    skill_failed=1
  elif ! is_valid_category "$category_field"; then
    fail "$skill_name: frontmatter category '$category_field' not in {$VALID_CATEGORIES}"
    skill_failed=1
  fi

  if [ "$skill_failed" -eq 0 ]; then
    ok "$skill_name: SKILL.md present, frontmatter valid"
  fi

  skill_names="$skill_names $skill_name"
done

# --- c: every skill must be indexed in skills/README.md and AGENTS.md ----

for skill_name in $skill_names; do
  if [ ! -f "$README_FILE" ]; then
    fail "$skill_name: cannot verify skills/README.md entry — $README_FILE does not exist"
  elif ! grep -qF "($skill_name/SKILL.md)" "$README_FILE"; then
    fail "$skill_name: no entry '($skill_name/SKILL.md)' found in $README_FILE"
  else
    ok "$skill_name: indexed in $README_FILE"
  fi

  if [ ! -f "$AGENTS_FILE" ]; then
    fail "$skill_name: cannot verify AGENTS.md entry — $AGENTS_FILE does not exist"
  elif ! grep -qF "(skills/$skill_name/SKILL.md)" "$AGENTS_FILE"; then
    fail "$skill_name: no entry '(skills/$skill_name/SKILL.md)' found in $AGENTS_FILE"
  else
    ok "$skill_name: indexed in $AGENTS_FILE"
  fi
done

# --- d: reverse check — every index reference must point at a real skill -

if [ -f "$AGENTS_FILE" ]; then
  agents_refs="$(grep -oE '\(skills/[A-Za-z0-9_-]+/SKILL\.md\)' "$AGENTS_FILE" | sed -E 's#\(skills/([A-Za-z0-9_-]+)/SKILL\.md\)#\1#' | sort -u || true)"
  for ref in $agents_refs; do
    if [ ! -f "$SKILLS_DIR/$ref/SKILL.md" ]; then
      fail "AGENTS.md references skills/$ref/SKILL.md but $SKILLS_DIR/$ref/SKILL.md does not exist"
    else
      ok "AGENTS.md reference '$ref' resolves to an existing skill"
    fi
  done
fi

if [ -f "$README_FILE" ]; then
  readme_refs="$(grep -oE '\([A-Za-z0-9_-]+/SKILL\.md\)' "$README_FILE" | sed -E 's#\(([A-Za-z0-9_-]+)/SKILL\.md\)#\1#' | sort -u || true)"
  for ref in $readme_refs; do
    if [ ! -f "$SKILLS_DIR/$ref/SKILL.md" ]; then
      fail "skills/README.md references ($ref/SKILL.md) but $SKILLS_DIR/$ref/SKILL.md does not exist"
    else
      ok "skills/README.md reference '$ref' resolves to an existing skill"
    fi
  done
fi

echo ""
echo "Summary: $ok_count OK, $fail_count FAIL"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

exit 0
