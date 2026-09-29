#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Install checksum-verified release binaries for the CI tools this repository
# adds on top of the template kit.
#
# The template's scripts/install-ci-tools.sh knows only its own kit tools and
# stays identical to upstream. Tools this repository adds are pinned in
# scripts/tool-pins.extra (`<tool> <version> <source>`), which
# `make check-tool-versions` also reads, so each pin has one home and is watched
# for drift. This script installs the tools named on its command line at the
# versions pinned there.
#
# Usage: scripts/install-extra-tools.sh <tool> [<tool>...]
#        make ci-tools   (installs the kit tools and these)
#
# Known tools: syft (GitHub release tarball, sha256 verified against the
# release's checksum file).
#
# INSTALL_DIR (default /usr/local/bin) can point at a throwaway prefix for
# testing. sudo is used only when the target is not writable by the caller.
# Linux x86_64 only, like the kit tarball tools.

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
PINS_FILE="${PINS_FILE:-scripts/tool-pins.extra}"
KNOWN_TOOLS="syft"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <tool> [<tool>...]  (known: ${KNOWN_TOOLS})" >&2
  exit 2
fi

if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
  echo "::error::$0 installs linux x86_64 assets only (this is $(uname -s) $(uname -m))" >&2
  exit 1
fi

pinned_version() {
  local tool="$1" version
  version="$(awk -v t="$tool" '$1 == t { print $2; exit }' "$PINS_FILE")"
  if [ -z "$version" ]; then
    echo "::error::no pin for '$tool' in $PINS_FILE" >&2
    exit 1
  fi
  printf '%s' "$version"
}

place_binary() {
  local found="$1" binary="$2"
  if [ -w "$INSTALL_DIR" ]; then
    install -m 0755 "$found" "${INSTALL_DIR}/${binary}"
  else
    sudo install -m 0755 "$found" "${INSTALL_DIR}/${binary}"
  fi
}

# Download a release tarball and its checksum file, verify the tarball against
# its own line in that file, and install the named binary from it.
install_tar_binary() {
  local repo="$1" tag="$2" asset="$3" checksums="$4" binary="$5" hash
  local url="https://github.com/${repo}/releases/download/${tag}"
  curl -fsSLO "$url/$asset"
  curl -fsSLO "$url/$checksums"
  hash="$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; exit }' "$checksums")"
  if [ -z "$hash" ]; then
    echo "::error::$asset is not listed in $checksums" >&2
    exit 1
  fi
  printf '%s  %s\n' "$hash" "$asset" | sha256sum -c -
  mkdir -p "extract-${binary}"
  tar -xzf "$asset" -C "extract-${binary}"
  local found
  found="$(find "extract-${binary}" -type f -name "$binary" -print -quit)"
  if [ -z "$found" ]; then
    echo "::error::binary '$binary' not found in $asset" >&2
    exit 1
  fi
  place_binary "$found" "$binary"
}

PINS_FILE="$(cd "$(dirname "$PINS_FILE")" && pwd)/$(basename "$PINS_FILE")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

for tool in "$@"; do
  case "$tool" in
    syft)
      version="$(pinned_version syft)"
      install_tar_binary "anchore/syft" "v${version}" \
        "syft_${version}_linux_amd64.tar.gz" \
        "syft_${version}_checksums.txt" \
        "syft"
      ;;
    *)
      echo "::error::unknown tool '$tool' (known: ${KNOWN_TOOLS})" >&2
      exit 1
      ;;
  esac
  echo "installed ${tool} $(pinned_version "$tool") to ${INSTALL_DIR}"
done
