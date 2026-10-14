#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Detect drift between the build-tool pins in scripts/tool-pins.yocto and the
# recipes of the Yocto release a device image is built with.
#
# The template's scripts/check-tool-versions.sh compares pins with upstream's
# latest release. CMake and Ninja must instead match the openembedded-core
# recipes on the pinned Yocto branch, a comparison the template's pin format
# cannot express, so this script covers them.
#
# Usage: scripts/check-local-pins.sh
#        make check-tool-versions   (runs both checks)
#
# Weekly maintenance only, not lint/verify/ci-pr: it makes network calls whose
# answer changes when the Yocto branch moves.
#
# Exit status: 0 = every pin matches its recipe. Non-zero = drift, a malformed
# pin row, or a failed lookup (reported as ERROR, never as a pass).

set -euo pipefail

YOCTO_PINS_FILE="${YOCTO_PINS_FILE:-scripts/tool-pins.yocto}"

if [ ! -f "$YOCTO_PINS_FILE" ]; then
  echo "error: $YOCTO_PINS_FILE not found (run from the repository root)" >&2
  exit 2
fi

release="$(awk '$1 == "yocto-release" { print $2; exit }' "$YOCTO_PINS_FILE")"
if [ -z "$release" ]; then
  echo "error: no 'yocto-release <branch>' row in $YOCTO_PINS_FILE" >&2
  exit 2
fi

# Same token order as scripts/check-tool-versions.sh: GH_TOKEN, GITHUB_TOKEN,
# then a logged-in gh. The header goes through a file descriptor so the token
# is not in curl's argv.
github_token() {
  if [ -n "${GH_TOKEN:-}" ]; then printf '%s' "$GH_TOKEN"
  elif [ -n "${GITHUB_TOKEN:-}" ]; then printf '%s' "$GITHUB_TOKEN"
  elif command -v gh >/dev/null 2>&1; then gh auth token 2>/dev/null || true
  fi
}

# Version of meta/recipes-devtools/<recipe>/ on the release branch, read from
# the recipe file name (<recipe>_<version>.bb). An empty result is a failure.
recipe_version() {
  local recipe="$1" url token body
  url="https://api.github.com/repos/openembedded/openembedded-core/contents/meta/recipes-devtools/${recipe}?ref=${release}"
  token="$(github_token)"
  if [ -n "$token" ]; then
    body="$(curl -fsSL --max-time 90 -H @<(printf 'Authorization: Bearer %s\n' "$token") "$url")" || return 1
  else
    body="$(curl -fsSL --max-time 90 "$url")" || return 1
  fi
  printf '%s' "$body" | python3 -c "
import json, sys
try:
    names = [entry['name'] for entry in json.load(sys.stdin)]
except Exception:
    sys.exit(1)
prefix = sys.argv[1] + '_'
for name in names:
    if name.startswith(prefix) and name.endswith('.bb'):
        print(name[len(prefix):-3])
        break
" "$recipe" || return 1
}

printf 'Yocto release: %s\n\n' "$release"
printf '%-20s %-12s %-12s %s\n' "TOOL" "PINNED" "RECIPE" "STATUS"
printf '%-20s %-12s %-12s %s\n' "--------------------" "------------" "------------" "------"

drift=0
errors=0
while IFS= read -r row || [ -n "$row" ]; do
  row="${row%%#*}"
  # shellcheck disable=SC2086 # split the row into its whitespace-separated fields
  set -- $row
  [ "$#" -gt 0 ] || continue
  [ "$1" != "yocto-release" ] || continue
  if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    printf '%-20s %-12s %-12s %s\n' "${1:-?}" "?" "?" "ERROR (${YOCTO_PINS_FILE}: expected '<tool> <version> <recipe> [<sha256>]')"
    errors=$((errors + 1))
    continue
  fi
  tool="$1" pinned="$2" recipe="$3"
  if ! latest="$(recipe_version "$recipe")" || [ -z "$latest" ]; then
    printf '%-20s %-12s %-12s %s\n' "$tool" "$pinned" "?" "ERROR (lookup failed: ${recipe} on ${release})"
    errors=$((errors + 1))
    continue
  fi
  if [ "$pinned" = "$latest" ]; then
    printf '%-20s %-12s %-12s %s\n' "$tool" "$pinned" "$latest" "ok"
  else
    printf '%-20s %-12s %-12s %s\n' "$tool" "$pinned" "$latest" "DRIFT"
    drift=$((drift + 1))
  fi
done < "$YOCTO_PINS_FILE"

echo

if [ "$errors" -gt 0 ]; then
  echo "FAIL: ${errors} pin(s) could not be checked." >&2
  exit 1
fi

if [ "$drift" -gt 0 ]; then
  echo "FAIL: ${drift} build-tool pin(s) differ from the ${release} recipes." >&2
  echo "      Set the version (and, for ninja, the sha256) in ${YOCTO_PINS_FILE}, run 'make verify', open a PR." >&2
  exit 1
fi

echo "OK: every build-tool pin matches the ${release} recipes."
