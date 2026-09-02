#!/usr/bin/env bash
# Install checksum-verified release binaries used by the make lint targets.
#
# This exists because ci.yml and maintenance.yml both need these tools, and the
# install logic was previously duplicated byte-for-byte in both workflow files
# with nothing marking the copies as needing to stay in sync. Per AGENTS.md
# ("the Makefile is the only executable contract in this repository") and
# skills/github-actions-hygiene rule 1, this logic belongs here, not in YAML.
#
# Usage: scripts/install-ci-tools.sh <tool> [<tool>...]
#        make ci-tools TOOLS="actionlint gitleaks lychee"
#
# Known tools: actionlint, gitleaks, lychee (GitHub release tarballs, sha256
# verified), markdownlint-cli2 (npm), yamllint (PyPI).
#
# All five version pins live here so `make check-tool-versions` has one place to
# read and compare against upstream — Dependabot cannot see any of them.
#
# CI-oriented installer. Local development is unchanged: the `make lint-*`
# targets still only *check* for these tools and print a brew/npm hint. Nothing
# invokes this script implicitly.
#
# INSTALL_DIR (default /usr/local/bin) can point at a throwaway prefix for
# testing the tarball tools. sudo is used only when the target is not writable
# by the caller. It does NOT apply to markdownlint-cli2 (npm) or yamllint
# (pipx/pip): those install into their own package-manager prefixes, which is
# what CI needs so `make ci-pr` finds them on PATH. Each tool prints its real
# destination, so the output never claims a directory it did not write to.
#
# bash 3.2 portable (macOS default /bin/bash), matching scripts/bootstrap.sh:
# no associative arrays, no mapfile, no arrays-of-arrays.

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
KNOWN_TOOLS="actionlint, gitleaks, lychee, markdownlint-cli2, yamllint"

# --- version pins -----------------------------------------------------------
# SINGLE SOURCE OF TRUTH for every CI tool version. Dependabot cannot see these
# (there is no manifest for it to read), so `make check-tool-versions` compares
# them against upstream weekly from maintenance.yml and fails on drift.
#
# scripts/check-tool-versions.sh parses these lines by name. Keep the
# `<TOOL>_VERSION="x.y.z"` shape — one pin per line, double-quoted, no shell
# expressions — or the drift check silently stops covering the changed pin.
ACTIONLINT_VERSION="1.7.12"
GITLEAKS_VERSION="8.30.1"
LYCHEE_VERSION="0.24.2"
MARKDOWNLINT_CLI2_VERSION="0.23.2"
YAMLLINT_VERSION="1.38.0"

# --- preflight --------------------------------------------------------------
# The three tarball tools ship linux x86_64 assets only, which is correct for
# the ubuntu-latest hosted runners this repo uses. On any other architecture the
# download would succeed and then fail at exec time with a confusing "exec
# format error", so fail loudly and early instead. Supporting arm64 means adding
# per-tool asset names here, not relaxing this check.
#
# markdownlint-cli2 (npm) and yamllint (PyPI) are cross-platform, so the guard
# is applied per-tool rather than once up front — that keeps those two usable on
# a maintainer's macOS box.
require_supported_platform() {
  local tool="$1" os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  if [ "$os" != "Linux" ] || { [ "$arch" != "x86_64" ] && [ "$arch" != "amd64" ]; }; then
    echo "error: '${tool}' installs from a linux x86_64 release asset (got ${os}/${arch})." >&2
    echo "       On other platforms, install it with your package manager;" >&2
    echo "       the make lint-* targets print the expected install hints." >&2
    exit 1
  fi
}

# --- helpers (moved verbatim from ci.yml / maintenance.yml) ------------------
verify_checksum() {
  local asset="$1" checksums="$2" line hash
  line="$(grep -F "$asset" "$checksums" || true)"
  if [ -z "$line" ]; then
    line="$(head -n 1 "$checksums")"
  fi
  hash="$(printf '%s\n' "$line" | grep -Eo '[A-Fa-f0-9]{64}' | head -n 1)"
  test -n "$hash"
  printf '%s  %s\n' "$hash" "$asset" | sha256sum -c -
}

place_binary() {
  # place_binary <source-path> <binary-name>
  local found="$1" binary="$2"
  if [ -w "$INSTALL_DIR" ]; then
    install -m 0755 "$found" "${INSTALL_DIR}/${binary}"
  else
    sudo install -m 0755 "$found" "${INSTALL_DIR}/${binary}"
  fi
}

install_tar_binary() {
  local repo="$1" tag="$2" asset="$3" checksums="$4" binary="$5"
  local url="https://github.com/${repo}/releases/download/${tag}"
  curl -fsSLO "$url/$asset"
  curl -fsSLO "$url/$checksums"
  verify_checksum "$asset" "$checksums"
  local extract_dir="${tmp}/extract-${binary}"
  mkdir -p "$extract_dir"
  tar -xzf "$asset" -C "$extract_dir"
  local found
  found="$(find "$extract_dir" -type f -name "$binary" -print -quit)"
  if [ -z "$found" ]; then
    echo "::error::binary '$binary' not found in $asset" >&2
    exit 1
  fi
  place_binary "$found" "$binary"
}

# npm and PyPI installs are integrity-checked by the registries' own hash
# mechanisms plus an exact `@`/`==` pin, which is the equivalent of the sha256
# verification the tarball path does by hand.
#
# NOTE: these two do NOT honour INSTALL_DIR — npm and pip/pipx install into
# their own configured prefixes, and on CI that is what we want (the tools must
# land on PATH for `make ci-pr`). INSTALL_DIR governs the tarball tools only;
# the per-tool progress line below states the real destination so the output
# never claims a directory it did not write to.
#
# Because they escape INSTALL_DIR, they cannot be sandboxed for a test run — so
# outside CI they refuse to run unless ALLOW_LOCAL_INSTALL=1 is set explicitly.
# This is not hypothetical: a "harmless" isolated-prefix test of this script did
# a real `npm install -g` and `pip install --user` on a maintainer's laptop.
require_install_consent() {
  local tool="$1"
  if [ -n "${CI:-}" ] || [ "${ALLOW_LOCAL_INSTALL:-}" = "1" ]; then
    return 0
  fi
  echo "error: '${tool}' installs via a system package manager (npm -g / pip --user)." >&2
  echo "       It ignores INSTALL_DIR, so this would modify your machine, not a sandbox." >&2
  echo "       Re-run with ALLOW_LOCAL_INSTALL=1 if that is what you want." >&2
  exit 1
}
install_npm_global() {
  local pkg="$1" version="$2"
  command -v npm >/dev/null 2>&1 || {
    echo "error: npm not found — '$pkg' needs Node.js (ci.yml runs actions/setup-node first)" >&2
    exit 1
  }
  npm install -g "${pkg}@${version}"
}

install_python_tool() {
  local pkg="$1" version="$2"
  if command -v pipx >/dev/null 2>&1; then
    pipx install "${pkg}==${version}"
  else
    python3 -m pip install --user "${pkg}==${version}"
  fi
  # pip --user and pipx both land here; on GitHub runners that directory is not
  # on PATH for subsequent steps unless it is exported this way. Guarded so the
  # script stays runnable outside Actions.
  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$HOME/.local/bin" >> "$GITHUB_PATH"
  fi
}

install_tool() {
  case "$1" in
    actionlint)
      require_supported_platform actionlint
      install_tar_binary "rhysd/actionlint" "v${ACTIONLINT_VERSION}" \
        "actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
        "actionlint_${ACTIONLINT_VERSION}_checksums.txt" \
        "actionlint"
      ;;
    gitleaks)
      require_supported_platform gitleaks
      install_tar_binary "gitleaks/gitleaks" "v${GITLEAKS_VERSION}" \
        "gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
        "gitleaks_${GITLEAKS_VERSION}_checksums.txt" \
        "gitleaks"
      ;;
    lychee)
      require_supported_platform lychee
      install_tar_binary "lycheeverse/lychee" "lychee-v${LYCHEE_VERSION}" \
        "lychee-x86_64-unknown-linux-gnu.tar.gz" \
        "lychee-x86_64-unknown-linux-gnu.tar.gz.sha256" \
        "lychee"
      ;;
    markdownlint-cli2)
      require_install_consent markdownlint-cli2
      install_npm_global "markdownlint-cli2" "${MARKDOWNLINT_CLI2_VERSION}"
      ;;
    yamllint)
      require_install_consent yamllint
      install_python_tool "yamllint" "${YAMLLINT_VERSION}"
      ;;
    *)
      echo "error: unknown tool '$1' (known: ${KNOWN_TOOLS})" >&2
      exit 1
      ;;
  esac
}

# --- main -------------------------------------------------------------------
if [ "$#" -eq 0 ]; then
  echo "usage: $0 <tool> [<tool>...]   (known: ${KNOWN_TOOLS})" >&2
  exit 1
fi

# Validate every requested tool up front so a typo fails instantly rather than
# halfway through a multi-tool install. The platform guard is per-tool and lives
# in install_tool, since only the tarball tools are linux-x86_64-only.
for tool in "$@"; do
  case "$tool" in
    actionlint | gitleaks | lychee | markdownlint-cli2 | yamllint) ;;
    *)
      echo "error: unknown tool '$tool' (known: ${KNOWN_TOOLS})" >&2
      exit 1
      ;;
  esac
done

# Only the tarball path writes to INSTALL_DIR, so only create it when a tarball
# tool was actually requested — otherwise an npm/PyPI-only run would leave an
# empty directory behind and imply it had installed something there.
for tool in "$@"; do
  case "$tool" in
    actionlint | gitleaks | lychee)
      mkdir -p "$INSTALL_DIR"
      break
      ;;
  esac
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

# Report the real destination per tool. npm/pip manage their own prefixes and
# ignore INSTALL_DIR, so claiming INSTALL_DIR for them would be a lie.
destination_of() {
  case "$1" in
    markdownlint-cli2) printf 'npm global prefix' ;;
    yamllint) printf 'pipx/pip user prefix' ;;
    *) printf '%s' "$INSTALL_DIR" ;;
  esac
}

for tool in "$@"; do
  echo "installing ${tool} -> $(destination_of "$tool")"
  install_tool "$tool"
done
