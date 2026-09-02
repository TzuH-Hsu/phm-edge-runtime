#!/usr/bin/env bash
# check-local-md.sh — local-file hygiene check.
#
# Verifies:
#   a. no *.local.md file is tracked by git (session memory, never committed)
#   b. no .env / .env.* file is tracked, except .env.example
#   c. (non-fatal) warns if an untracked HANDOVER.local.md at repo root
#      exceeds 150 lines
#
# Exit status: 0 if a/b pass (WARN in c does not affect exit status),
# 1 if a or b fail.

set -euo pipefail

cd "$(dirname "$0")/.."

HANDOVER_LINE_CAP=150

fail_count=0

fail() {
  echo "FAIL: $1"
  fail_count=$((fail_count + 1))
}

pass() {
  echo "PASS: $1"
}

warn() {
  echo "WARN: $1"
}

# --- a: no *.local.md tracked by git --------------------------------------

tracked_local_md="$(git ls-files '*.local.md' || true)"

if [ -n "$tracked_local_md" ]; then
  fail "tracked *.local.md file(s) found (session memory must never be committed):"
  echo "$tracked_local_md" | while IFS= read -r f; do
    echo "  - $f"
  done
else
  pass "no *.local.md files are tracked by git"
fi

# --- b: no .env / .env.* tracked, except .env.example ---------------------

tracked_env="$(git ls-files '.env' '.env.*' '**/.env' '**/.env.*' 2>/dev/null || true)"

bad_env=""
if [ -n "$tracked_env" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="$(basename "$f")"
    if [ "$base" != ".env.example" ]; then
      bad_env="$bad_env
$f"
    fi
  done <<EOF
$tracked_env
EOF
fi

if [ -n "$bad_env" ]; then
  fail "tracked .env file(s) found (only .env.example is allowed):"
  echo "$bad_env" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo "  - $f"
  done
else
  pass "no disallowed .env files are tracked by git (only .env.example, if any, is permitted)"
fi

# --- c: non-fatal WARN on oversized untracked HANDOVER.local.md ----------

HANDOVER_FILE="HANDOVER.local.md"

if [ -f "$HANDOVER_FILE" ]; then
  if git ls-files --error-unmatch "$HANDOVER_FILE" >/dev/null 2>&1; then
    : # tracked — already covered (and would fail) by check (a) above
  else
    line_count="$(awk 'END { print NR }' "$HANDOVER_FILE")"
    if [ "$line_count" -gt "$HANDOVER_LINE_CAP" ]; then
      warn "handoff file over the 150-line cap — rewrite it (see skills/context-handoff/)"
    else
      pass "$HANDOVER_FILE is within the $HANDOVER_LINE_CAP-line cap ($line_count lines)"
    fi
  fi
else
  pass "no untracked $HANDOVER_FILE present at repo root"
fi

echo ""
if [ "$fail_count" -gt 0 ]; then
  echo "Summary: $fail_count FAIL"
  exit 1
fi

echo "Summary: all checks passed"
exit 0
