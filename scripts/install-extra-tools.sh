#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Install checksum-verified release binaries for the CI tools this repository
# adds on top of the template kit.
#
# The template's scripts/install-ci-tools.sh knows only its own kit tools and
# keeps upstream's pins and install logic. Tools this repository adds are pinned in
#   scripts/tool-pins.extra   syft (watched by scripts/check-tool-versions.sh)
#   scripts/tool-pins.yocto   cmake, ninja (watched by scripts/check-local-pins.sh)
# so each pin has one home and is watched for drift. This script installs the
# tools named on its command line at the versions pinned there.
#
# Usage: scripts/install-extra-tools.sh <tool> [<tool>...]
#        make ci-tools   (installs the kit tools and these)
#
# Known tools: syft (GitHub release tarball, sha256 verified against the
# release's checksum file), cmake (release tarball, sha256 verified, installed
# as a tree with its binaries linked into INSTALL_DIR), ninja (release zip,
# sha256 pinned in scripts/tool-pins.yocto because upstream publishes no
# checksum file).
#
# INSTALL_DIR (default /usr/local/bin) can point at a throwaway prefix for
# testing. sudo is used only when the target is not writable by the caller.
# Linux x86_64 only, like the kit tarball tools.

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
PINS_FILE="${PINS_FILE:-scripts/tool-pins.extra}"
YOCTO_PINS_FILE="${YOCTO_PINS_FILE:-scripts/tool-pins.yocto}"
KNOWN_TOOLS="cmake, ninja, syft"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <tool> [<tool>...]  (known: ${KNOWN_TOOLS})" >&2
  exit 2
fi

for tool in "$@"; do
  case "$tool" in
    cmake | ninja | syft) ;;
    *)
      echo "::error::unknown tool '$tool' (known: ${KNOWN_TOOLS})" >&2
      exit 1
      ;;
  esac
done

if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
  echo "::error::$0 installs linux x86_64 assets only (this is $(uname -s) $(uname -m))" >&2
  exit 1
fi

# Field <n> of the row for <tool> in <file>; a missing row or field is an error.
pin_field() {
  local file="$1" tool="$2" field="$3" value
  value="$(awk -v t="$tool" -v f="$field" '$1 == t { print $f; exit }' "$file")"
  if [ -z "$value" ]; then
    echo "::error::no field ${field} for '$tool' in $file" >&2
    exit 1
  fi
  printf '%s' "$value"
}

pinned_version() {
  case "$1" in
    cmake | ninja) pin_field "$YOCTO_PINS_FILE" "$1" 2 ;;
    *) pin_field "$PINS_FILE" "$1" 2 ;;
  esac
}

place_binary() {
  local found="$1" binary="$2"
  mkdir -p "$INSTALL_DIR" 2>/dev/null || sudo mkdir -p "$INSTALL_DIR"
  if [ -w "$INSTALL_DIR" ]; then
    install -m 0755 "$found" "${INSTALL_DIR}/${binary}"
  else
    sudo install -m 0755 "$found" "${INSTALL_DIR}/${binary}"
  fi
}

# Verify <asset> against its own line in the release checksum file <checksums>.
verify_listed() {
  local asset="$1" checksums="$2" hash
  hash="$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; exit }' "$checksums")"
  if [ -z "$hash" ]; then
    echo "::error::$asset is not listed in $checksums" >&2
    exit 1
  fi
  printf '%s  %s\n' "$hash" "$asset" | sha256sum -c -
}

# Download a release tarball and its checksum file, verify the tarball, and
# install the named binary from it.
install_tar_binary() {
  local repo="$1" tag="$2" asset="$3" checksums="$4" binary="$5"
  local url="https://github.com/${repo}/releases/download/${tag}"
  curl -fsSLO "$url/$asset"
  curl -fsSLO "$url/$checksums"
  verify_listed "$asset" "$checksums"
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

# CMake needs its share/ tree next to the binaries, so the whole release is
# unpacked beside INSTALL_DIR and its three binaries are linked into it. CMake
# resolves the link to find its modules.
install_cmake() {
  local version="$1"
  local asset="cmake-${version}-linux-x86_64.tar.gz"
  local checksums="cmake-${version}-SHA-256.txt"
  local url="https://github.com/Kitware/CMake/releases/download/v${version}"
  local root
  root="$(dirname "$INSTALL_DIR")/lib/cmake-${version}"
  curl -fsSLO "$url/$asset"
  curl -fsSLO "$url/$checksums"
  verify_listed "$asset" "$checksums"
  local sudo_cmd=""
  if ! mkdir -p "$root" 2>/dev/null || [ ! -w "$root" ]; then
    sudo_cmd="sudo"
    sudo mkdir -p "$root"
  fi
  $sudo_cmd tar -xzf "$asset" -C "$root" --strip-components=1
  mkdir -p "$INSTALL_DIR" 2>/dev/null || sudo mkdir -p "$INSTALL_DIR"
  local link_sudo=""
  [ -w "$INSTALL_DIR" ] || link_sudo="sudo"
  local binary
  for binary in cmake ctest cpack; do
    $link_sudo ln -sf "${root}/bin/${binary}" "${INSTALL_DIR}/${binary}"
  done
}

install_ninja() {
  local version="$1" sha256="$2"
  local asset="ninja-linux.zip"
  curl -fsSLO "https://github.com/ninja-build/ninja/releases/download/v${version}/${asset}"
  printf '%s  %s\n' "$sha256" "$asset" | sha256sum -c -
  mkdir -p extract-ninja
  unzip -q "$asset" -d extract-ninja
  place_binary extract-ninja/ninja ninja
}

absolute() { printf '%s/%s' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")"; }
PINS_FILE="$(absolute "$PINS_FILE")"
YOCTO_PINS_FILE="$(absolute "$YOCTO_PINS_FILE")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

for tool in "$@"; do
  version="$(pinned_version "$tool")"
  case "$tool" in
    syft)
      install_tar_binary "anchore/syft" "v${version}" \
        "syft_${version}_linux_amd64.tar.gz" \
        "syft_${version}_checksums.txt" \
        "syft"
      ;;
    cmake)
      install_cmake "$version"
      ;;
    ninja)
      sha256="$(pin_field "$YOCTO_PINS_FILE" ninja 4)"
      install_ninja "$version" "$sha256"
      ;;
  esac
  echo "installed ${tool} ${version} to ${INSTALL_DIR}"
done
