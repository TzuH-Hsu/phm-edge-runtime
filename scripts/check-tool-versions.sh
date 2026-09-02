#!/usr/bin/env bash
# Detect drift between the CI tool version pins and their upstream releases.
#
# Why this exists: none of these five tools live in a manifest Dependabot can
# read, so nothing was watching them. The pins would sit still while upstream
# shipped fixes, silently — exactly the rot this repo's governance is meant to
# design out. See issue #14.
#
# Usage: scripts/check-tool-versions.sh
#        make check-tool-versions
#
# Wired into the weekly maintenance workflow, NOT into lint/verify/ci-pr: it
# makes external network calls, and every PR should stay offline and hermetic.
# On a public repo the weekly run is free — hosted runners cost nothing and this
# is three GitHub API calls plus two registry fetches.
#
# Exit status: 0 = every pin current (or deliberately held). Non-zero = drift
# found, or a lookup failed. A failed lookup is deliberately an ERROR, never a
# silent pass: a check that quietly skips is worse than no check, because it
# reads as "all clear".
#
# bash 3.2 portable (macOS default /bin/bash), matching the other scripts here.

set -euo pipefail

PINS_FILE="${PINS_FILE:-scripts/install-ci-tools.sh}"

# --- deliberate holds --------------------------------------------------------
# If a newer upstream release is knowingly NOT adopted (it breaks something, or
# needs coordinated work), record it here so the weekly run reports HELD instead
# of failing. Keyed on tool:version, so a hold expires by itself once upstream
# publishes something newer — the alert returns rather than staying muted.
#
#   case "$1" in
#     lychee:0.25.0) echo "0.25.0 changed --offline semantics; tracked in #NN" ;;
#   esac
hold_reason() {
  case "$1" in
    *) return 1 ;;
  esac
}

# --- pin reading -------------------------------------------------------------
# Reads `<TOOL>_VERSION="x.y.z"` out of the installer, the single source of
# truth. Fails loudly if a pin is missing rather than reporting a tool as
# current on the strength of an empty string.
read_pin() {
  local var="$1" value
  value="$(sed -n "s/^${var}=\"\([^\"]*\)\".*/\1/p" "$PINS_FILE" | head -n 1)"
  if [ -z "$value" ]; then
    echo "error: could not read ${var} from ${PINS_FILE} — pin renamed or reformatted?" >&2
    echo "       The installer's comment documents the required shape." >&2
    return 1
  fi
  printf '%s' "$value"
}

# --- upstream lookups --------------------------------------------------------
fetch_json_field() {
  local url="$1" expr="$2" body
  body="$(curl -fsSL --max-time 30 "$url")" || return 1
  printf '%s' "$body" | python3 -c "
import json,sys
try:
    print(${expr})
except Exception:
    sys.exit(1)
" || return 1
}

# Prefer gh so Actions runs authenticate with GITHUB_TOKEN (1,000 req/hr per
# repo) instead of sharing the unauthenticated 60/hr-per-IP pool. Falls back to
# the public REST endpoint so this still works without gh installed.
latest_github_tag() {
  local repo="$1" tag=""
  if command -v gh >/dev/null 2>&1; then
    tag="$(gh api "repos/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null)" || tag=""
  fi
  if [ -z "$tag" ]; then
    tag="$(fetch_json_field "https://api.github.com/repos/${repo}/releases/latest" \
      "json.load(sys.stdin)['tag_name']")" || return 1
  fi
  [ -n "$tag" ] || return 1
  printf '%s' "$tag"
}

# Prints the upstream version with any tag prefix stripped so it compares
# directly against the pin. lychee tags as `lychee-vX.Y.Z`, the other two as
# `vX.Y.Z` — checked against the live API, not assumed.
latest_upstream() {
  case "$1" in
    actionlint) latest_github_tag "rhysd/actionlint" | sed 's/^v//' ;;
    gitleaks) latest_github_tag "gitleaks/gitleaks" | sed 's/^v//' ;;
    lychee) latest_github_tag "lycheeverse/lychee" | sed 's/^lychee-v//;s/^v//' ;;
    markdownlint-cli2)
      fetch_json_field "https://registry.npmjs.org/markdownlint-cli2/latest" \
        "json.load(sys.stdin)['version']"
      ;;
    yamllint)
      fetch_json_field "https://pypi.org/pypi/yamllint/json" \
        "json.load(sys.stdin)['info']['version']"
      ;;
    *)
      echo "error: no upstream source defined for '$1'" >&2
      return 1
      ;;
  esac
}

# --- main --------------------------------------------------------------------
if [ ! -f "$PINS_FILE" ]; then
  echo "error: pins file not found: ${PINS_FILE}" >&2
  exit 1
fi

# tool<TAB>pin-variable. Adding a tool to install-ci-tools.sh means adding a row
# here too, otherwise it goes unwatched — which is the very failure mode this
# script exists to close.
TOOLS="actionlint	ACTIONLINT_VERSION
gitleaks	GITLEAKS_VERSION
lychee	LYCHEE_VERSION
markdownlint-cli2	MARKDOWNLINT_CLI2_VERSION
yamllint	YAMLLINT_VERSION"

drift=0
errors=0

printf '%-20s %-12s %-12s %s\n' "TOOL" "PINNED" "LATEST" "STATUS"
printf '%-20s %-12s %-12s %s\n' "--------------------" "------------" "------------" "------"

while IFS="	" read -r tool var; do
  [ -n "$tool" ] || continue

  if ! pinned="$(read_pin "$var")"; then
    printf '%-20s %-12s %-12s %s\n' "$tool" "?" "?" "ERROR (pin unreadable)"
    errors=$((errors + 1))
    continue
  fi

  if ! latest="$(latest_upstream "$tool")" || [ -z "$latest" ]; then
    printf '%-20s %-12s %-12s %s\n' "$tool" "$pinned" "?" "ERROR (lookup failed)"
    errors=$((errors + 1))
    continue
  fi

  if [ "$pinned" = "$latest" ]; then
    printf '%-20s %-12s %-12s %s\n' "$tool" "$pinned" "$latest" "ok"
  elif reason="$(hold_reason "${tool}:${latest}")"; then
    printf '%-20s %-12s %-12s %s\n' "$tool" "$pinned" "$latest" "HELD - ${reason}"
  else
    printf '%-20s %-12s %-12s %s\n' "$tool" "$pinned" "$latest" "DRIFT"
    drift=$((drift + 1))
  fi
done <<EOF
$TOOLS
EOF

echo

if [ "$errors" -gt 0 ]; then
  echo "FAIL: ${errors} lookup/parse error(s). Not reporting 'all clear' on incomplete data." >&2
  echo "      If this is a transient network or rate-limit blip, re-run the workflow." >&2
  exit 1
fi

if [ "$drift" -gt 0 ]; then
  echo "FAIL: ${drift} tool pin(s) behind upstream." >&2
  echo "      Bump the pin in ${PINS_FILE}, run 'make verify', open a PR." >&2
  echo "      To knowingly stay behind, add a hold_reason entry in this script." >&2
  exit 1
fi

echo "All tool pins are current."
