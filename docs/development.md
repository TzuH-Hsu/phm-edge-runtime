# Development

How to build and test the `phm-edge-runtime` library, and how the source tree is laid out. Branches, commits and pull requests are covered in [`CONTRIBUTING.md`](../CONTRIBUTING.md).

## Build requirements

| Tool | Version | Used for |
| --- | --- | --- |
| C++ compiler | Any GCC or Clang with C++20 support; CI uses the runner image's GCC | Compiling |
| CMake | 4.3.1 in CI; 3.28 or later locally | Configure and build |
| Ninja | 1.13.2 in CI | Build |
| clang-format, clang-tidy | The runner image's LLVM in CI; the Makefile prefers `clang-format-22` and `clang-tidy-22` when present | Formatting and static analysis (`make lint-cpp`) |
| markdownlint-cli2, yamllint, lychee, actionlint, gitleaks, syft, node, python3 | See [`CONTRIBUTING.md`](../CONTRIBUTING.md) | The rest of `make lint` |

The install commands for macOS and Linux are in the README, [Getting started](../README.md#getting-started). The CI versions of CMake and Ninja are pinned in `scripts/tool-pins.yocto`, which follows the Yocto release a device image is built with and is compared with that release's recipes every week.

GoogleTest 1.17.0 is a test-only dependency. CMake uses an installed copy of exactly that version when it finds one; otherwise the first configure downloads the release archive and checks it against the SHA-256 in `cmake/Dependencies.cmake`.

## Common commands

```bash
make setup                  # Check that every tool `make verify` needs is on PATH; installs nothing
make build                  # Configure and build the library and the tests in build/dev
make test                   # Run the unit tests on the plain build and on the ASan/UBSan build
make test-one TEST=Skeleton # Build build/dev and run only the tests whose name matches the ctest -R regex
make verify                 # Lint and test: the gate before every pull request
make clean                  # Remove build/ (the build trees) and nothing else
```

`make lint-cpp` runs clang-format and clang-tidy alone. Test names have the form `<Suite>.<Test>`; `ctest --preset dev -N` lists them.

CMake presets are in `CMakePresets.json`:

| Preset | What it builds | Build directory |
| --- | --- | --- |
| `dev` | Debug, warnings as errors | `build/dev` |
| `asan-ubsan` | The same, plus AddressSanitizer and UndefinedBehaviorSanitizer; undefined behaviour aborts | `build/asan-ubsan` |

A build that does not use a preset (for example a recipe build) has `PHM_RUNTIME_WARNINGS_AS_ERRORS` and `PHM_RUNTIME_SANITIZE` off.

## Layout

```text
include/phm/runtime/   public headers, included as <phm/runtime/...>
src/                   library sources and the library target
tests/unit/            GoogleTest unit tests
cmake/                 compiler warnings, sanitizers, test dependencies
```

- One library target, `phm_edge_runtime`, with the alias `phm_edge_runtime::phm_edge_runtime` for consumers.
- `cmake --install build/dev --prefix <dir>` installs the public headers and the exported target; a consumer calls `find_package(phm_edge_runtime CONFIG REQUIRED)` and links `phm_edge_runtime::phm_edge_runtime`. The project's warning flags are not part of the installed target.
- Namespace `phm::runtime`; a component may use a nested namespace.
- CMake options and cache variables of this project start with `PHM_RUNTIME_`.
- While the library has no source files it is an INTERFACE library; `src/CMakeLists.txt` shows how the first source file turns it into a static library.
- Every source file starts with `SPDX-License-Identifier: Apache-2.0`.
