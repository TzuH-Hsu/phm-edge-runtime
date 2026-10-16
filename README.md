# phm-edge-runtime

<p align="center">
  <strong>Layered update runtime for Linux edge devices: A/B base image, signed artifact delivery, atomic switch with health-check rollback, watchdog.</strong>
</p>

<p align="center">
  <a href="https://github.com/TzuH-Hsu/phm-edge-runtime/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/TzuH-Hsu/phm-edge-runtime/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <img alt="Status" src="https://img.shields.io/badge/Status-Early-orange">
  <a href="LICENSE"><img alt="License Apache 2.0" src="https://img.shields.io/badge/License-Apache%202.0-D22128"></a>
  <img alt="Update: A/B + RAUC" src="https://img.shields.io/badge/Update-A%2FB%20%2B%20RAUC-006b75">
  <img alt="Platform: Linux" src="https://img.shields.io/badge/Platform-Linux-0e8a16">
</p>

Field-deployed edge devices fail at the worst possible moment: mid-update, with nobody on site. `phm-edge-runtime` separates what changes rarely from what changes often, and makes every switch reversible.

- **Base image** — A/B partitions, updated through RAUC. Rarely touched.
- **Application and model artifacts** — independent channels. Pull from a registry, verify the signature, switch atomically, roll back automatically when the health check fails.
- **Watchdog** — the hardware watchdog as the last line of defence.

The reason for the split is simple: a model ships far more often than an operating system, and a model update must never require rebuilding an image.

> **Status: early.** The API is not stable; expect breaking changes before `v1.0`. The code is C++20 and builds with CMake (see [#81](https://github.com/TzuH-Hsu/phm-edge-runtime/issues/81)).

## Why not just ship a whole image every time

Whole-image updates are simpler and they are the right answer for many fleets. They stop being the right answer when the thing that changes most often is a 20 MB model artifact and the image is 800 MB, when the link to the device is a metered or intermittent one, and when a failed boot means a site visit. At that point the deployment unit has to become the artifact, and the runtime has to own the switch.

## Scope

| In scope | Out of scope |
| --- | --- |
| Channel abstraction: source, verification, atomic switch, health check, rollback | Board support and image recipes (that is the Yocto layer's job) |
| Base image channel (A/B, RAUC) | Building the artifacts themselves |
| Application and model artifact channels | Anything specific to one deployment or site |
| Version matrix and compatibility rejection | Telemetry and application logic |
| Watchdog integration | |

## Getting started

There is no published package yet; these steps build from source, from a fresh clone to green tests and a first local run. What each `make` target does, where the build options live and how the source tree is laid out are in [`docs/development.md`](docs/development.md).

### 1. Required tools

| Tool | Version | Where the version is set |
| --- | --- | --- |
| C++ compiler | GCC or Clang with C++20; CI uses the runner image's GCC | `CMakeLists.txt` (`CMAKE_CXX_STANDARD`) |
| CMake | 3.28 or later; CI installs the pinned version | `CMakeLists.txt` (minimum), [`scripts/tool-pins.yocto`](scripts/tool-pins.yocto) (CI pin) |
| Ninja | CI installs the pinned version | [`scripts/tool-pins.yocto`](scripts/tool-pins.yocto) |
| clang-format, clang-tidy | The LLVM release of the CI runner image (Ubuntu 24.04 packages) | Runner image |
| GoogleTest | Exact pinned version, fetched by the first configure | [`cmake/Dependencies.cmake`](cmake/Dependencies.cmake) |
| markdownlint-cli2, yamllint, lychee, actionlint, gitleaks | CI installs the pinned versions | [`scripts/install-ci-tools.sh`](scripts/install-ci-tools.sh) |
| syft | CI installs the pinned version | [`scripts/tool-pins.extra`](scripts/tool-pins.extra) |
| Node.js | 22 or later (markdownlint-cli2 needs it); CI uses the current LTS | [`.github/workflows/ci.yml`](.github/workflows/ci.yml) |
| Python | 3; CI uses the runner image's | Runner image |

### 2. Get the source

```bash
git clone https://github.com/TzuH-Hsu/phm-edge-runtime.git && cd phm-edge-runtime
```

The repository has no submodules.

### 3. Set up the environment once

Install the tools, then run `make setup`.

macOS (the compiler and Python come with the Xcode Command Line Tools):

```bash
brew install cmake ninja llvm yamllint lychee actionlint gitleaks syft node
npm install -g markdownlint-cli2
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

Linux x86_64 (Ubuntu 24.04, as in CI). Install Node.js 22 or later first, for example with nvm, so that `npm install -g` needs no `sudo`:

```bash
sudo apt-get update && sudo apt-get install -y build-essential curl unzip pipx clang-format clang-tidy
ALLOW_LOCAL_INSTALL=1 make ci-tools
export PATH="$HOME/.local/bin:$PATH"
```

`make ci-tools` is the installer CI runs and installs the versions CI pins: the binaries into `/usr/local/bin` (with `sudo` when that directory is not writable), markdownlint-cli2 with `npm install -g` and yamllint with `pipx` into `~/.local/bin`.

On either system, an `export PATH=…` line lasts only for the current shell; add it to your shell's startup file (for example `~/.zshrc` or `~/.bashrc`) so that a new terminal still finds the tools.

```bash
make setup
```

`make setup` checks that every tool `make verify` runs is on `PATH`, prints `ok: every tool make verify needs is on PATH` or the missing ones, and installs nothing.

### 4. Build

```bash
make build
```

Configures the `dev` preset and builds the library and the tests in `build/dev`; the first configure downloads GoogleTest and checks its SHA-256.

### 5. Run the tests

```bash
make test
make test-one TEST=Skeleton
```

`make test` runs every unit test on the plain build and on the AddressSanitizer/UndefinedBehaviorSanitizer build; `make test-one` builds `build/dev` and runs only the tests whose `<Suite>.<Test>` name matches the `ctest -R` regular expression.

### 6. Run it locally

```bash
build/dev/tests/skeleton_test
```

This is the only program the repository builds today. It compiles every public header and runs one test; it prints `[ RUN      ] Skeleton.PublicHeadersCompile`, ends with `[  PASSED  ] 1 test.` and exits with status 0. The library has no runtime component yet; the first one, the disk-backed queue, arrives with [#73](https://github.com/TzuH-Hsu/phm-edge-runtime/issues/73).

### 7. Before opening a pull request

```bash
make verify
```

Runs every lint (`make lint`) and both test builds (`make test`), the same as CI; branch and pull request rules are in [Contributing](#contributing).

### 8. Common problems

- **`make ci-tools` stops with `installs from a linux x86_64 release asset`** — it downloads Linux x86_64 release binaries; on macOS or another architecture, install the tools with your package manager as in step 3.
- **The first `make build` or `make test` fails while downloading GoogleTest** — the first configure of each build tree downloads it from `github.com`, so that host must be reachable (set `https_proxy` if you are behind a proxy); later configures reuse the download until `make clean`.
- **`make lint-cpp` reports formatting that CI accepts, or the reverse** — clang-format releases format differently; use the LLVM release the CI runner image ships (step 1) and check it with `clang-format --version`.

Everything else, including the CMake presets and how to list the test names, is in [`docs/development.md`](docs/development.md).

## Contributing

Work from an issue, branch as `<type>/<issue#>-<slug>` or `<type>/<slug>`, use Conventional Commits, and open a PR whose body says `Closes #N`, `Refs #N` or `No issue: <reason>`; `No issue:` is for a small change that needs no tracking. `main` is protected: PR required, `ci` must pass. Conventions live in [`AGENTS.md`](AGENTS.md) (canonical) and [`CONTRIBUTING.md`](CONTRIBUTING.md).

Two rules are specific to this repository and non-negotiable:

- **No deployment-specific content** — no organisation names, site names, equipment models, data samples or project codenames, anywhere, including tests and fixtures.
- **No dependency on a downstream project** — applications depend on this library, never the reverse.

Contributions are provided under Apache-2.0 by default ([§5](LICENSE)). No CLA.

## Security

Signature verification and rollback are the security surface of this library. Report vulnerabilities privately — see [`SECURITY.md`](SECURITY.md). Please do not open a public issue for a suspected vulnerability.

## License

[Apache-2.0](LICENSE). Copyright 2026 Tzu-Hsuan Hsu. Attribution requirements are in [`NOTICE`](NOTICE).
