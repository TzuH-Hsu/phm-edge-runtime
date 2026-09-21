#!/usr/bin/env bash
# check-node-tests.sh — runs every scripts/*.test.js under plain node.
#
# The logic behind the event-driven workflows lives in scripts/*.js
# (ADR-0008: issue-labeler.js, pr-lint.js); the workflows only call it. Each
# module has a sibling *.test.js that exercises its pure functions and its
# run() entry point with stubbed GitHub objects — node built-ins only, no
# dependencies to install.
#
# node is a dependency of `make check` for this one script, like
# markdownlint-cli2 is for lint-docs; a missing node fails with an install
# hint the way the Makefile's other tool checks do — never a green skip.
#
# Exit status: 0 if the tests pass, 1 otherwise.

set -euo pipefail

cd "$(dirname "$0")/.."

command -v node >/dev/null 2>&1 || { echo "install: node (e.g. brew install node) — needed for scripts/*.test.js"; exit 1; }

# Every `require(... /scripts/<name>.js)` in a workflow must name a file that
# is here, with its sibling test — an adopter who takes a thin-caller workflow
# without its script gets a job that fails on every event while `make check`
# stays green, and a handler without a test is outside ADR-0008.
missing=0
for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$wf" ] || continue
  while IFS= read -r js; do
    [ -n "$js" ] || continue
    if [ ! -f "$js" ]; then
      echo "FAIL: $wf requires $js, which is missing — take the workflow and the script together (docs/template/upgrading.md)"
      missing=$((missing + 1))
    elif [ ! -f "${js%.js}.test.js" ]; then
      # ADR-0008: a handler a workflow calls is tested, no exceptions
      echo "FAIL: $wf requires $js, which has no ${js%.js}.test.js — every workflow handler ships with its test (ADR-0008)"
      missing=$((missing + 1))
    else
      echo "OK: $wf requires $js (present, tested by ${js%.js}.test.js)"
    fi
  done <<EOF_JS
$(grep -oE 'scripts/[A-Za-z0-9._-]+\.js' "$wf" | sort -u)
EOF_JS
done
if [ "$missing" -gt 0 ]; then
  echo "Summary: node tests NOT run — $missing workflow-required script(s) missing"
  exit 1
fi

if node --test --test-reporter=dot scripts/*.test.js; then
  echo ""
  echo "OK: $(printf '%s ' scripts/*.test.js)passed"
  echo "Summary: node tests passed"
  exit 0
fi
echo "FAIL: a scripts/*.test.js failed — rerun with: node --test scripts/*.test.js"
echo "Summary: node tests FAILED"
exit 1
