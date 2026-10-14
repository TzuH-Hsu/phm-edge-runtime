# GitHub Project OS - make-target contract: CI workflows call these targets
# and never contain logic of their own. L0 = lint (lint-docs, lint-actions,
# lint-secrets, lint-cpp, lint-licenses, check). L1 = test (ctest on a plain and
# on a sanitized build). verify = L0+L1 (canonical pre-PR gate).
# maintenance = lint-docs-external + check-tool-versions, the weekly drift
# detectors. It runs both and aggregates their exit status, so the workflow step
# stays a bare `make maintenance` and the job's combined failure behaviour is
# reproducible locally. All three are intentionally excluded from
# lint/verify/ci-pr: they make external network calls. The network calls in
# `verify` are `lint-licenses`, which reads licences from the package registries
# because lock files carry none, and the first configure of a build tree, which
# downloads the pinned, hash-verified test framework.
# CHANGELOG.md is excluded from markdownlint: release-please generates it.
# Customize tool invocations HERE, not in .github/workflows/*.

SHELL := /usr/bin/env bash
.PHONY: help setup lint-licenses sbom lint-docs lint-docs-external lint-actions lint-secrets lint-cpp check lint configure build test-unit test-sanitize test test-one clean verify ci-pr ci-tools check-tool-versions maintenance

.DEFAULT_GOAL := help

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n\n"} \
	/^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' \
	$(MAKEFILE_LIST)
	@echo ""

lint-docs: ## Lint markdown and YAML, check internal links
	@command -v markdownlint-cli2 >/dev/null 2>&1 || { echo "install: npm install -g markdownlint-cli2"; exit 1; }
	@command -v yamllint >/dev/null 2>&1 || { echo "install: brew install yamllint (or pip install yamllint)"; exit 1; }
	@command -v lychee >/dev/null 2>&1 || { echo "install: brew install lychee"; exit 1; }
	markdownlint-cli2 '**/*.md' '#node_modules' '#build' '#CHANGELOG.md'
	yamllint .
	lychee --offline --no-progress -- './**/*.md'

lint-docs-external: ## Full external link check (weekly maintenance workflow; not run in CI-PR)
	@command -v lychee >/dev/null 2>&1 || { echo "install: brew install lychee"; exit 1; }
	lychee --config lychee.toml --no-progress -- './**/*.md'

lint-actions: ## Lint GitHub Actions workflows
	@command -v actionlint >/dev/null 2>&1 || { echo "install: brew install actionlint"; exit 1; }
	actionlint

lint-secrets: ## Scan for committed secrets
	@command -v gitleaks >/dev/null 2>&1 || { echo "install: brew install gitleaks"; exit 1; }
	gitleaks detect --no-banner

check: ## Run repo self-consistency scripts (skips scripts not yet added)
	@if [ -x scripts/check-skills.sh ]; then scripts/check-skills.sh; else echo "skip: scripts/check-skills.sh not present yet"; fi
	@if [ -x scripts/check-local-md.sh ]; then scripts/check-local-md.sh; else echo "skip: scripts/check-local-md.sh not present yet"; fi
	@if [ -x scripts/check-label-forms.sh ]; then scripts/check-label-forms.sh; else echo "skip: scripts/check-label-forms.sh not present yet"; fi
	@if [ -x scripts/check-node-tests.sh ]; then scripts/check-node-tests.sh; else echo "skip: scripts/check-node-tests.sh not present yet"; fi
	@if [ -f scripts/test_check_licenses.py ]; then PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -q scripts/test_check_licenses.py; else echo "skip: scripts/test_check_licenses.py not present yet"; fi

lint: lint-docs lint-actions lint-secrets lint-cpp lint-licenses check ## L0 - aggregate all lint/consistency checks

# --- C++ build, tests and static analysis --------------------------------------
# Presets are in CMakePresets.json; each preset builds into build/<preset>.
# The versioned LLVM tool names are preferred so a machine with several LLVM
# releases installed uses a known one.
CLANG_FORMAT ?= $(firstword $(shell command -v clang-format-22 clang-format 2>/dev/null))
CLANG_TIDY ?= $(firstword $(shell command -v clang-tidy-22 clang-tidy 2>/dev/null))
CXX_SOURCES = git ls-files -z -- '*.cpp' '*.hpp'
CXX_TRANSLATION_UNITS = git ls-files -z -- '*.cpp'

# Every tool `make verify` runs. `setup` reports the missing ones; it installs
# nothing (docs/development.md lists how to install each).
SETUP_TOOLS := markdownlint-cli2 yamllint lychee actionlint gitleaks syft node python3 cmake ninja c++

setup: ## Check that every tool `make verify` needs is on PATH (installs nothing)
	@missing=""; \
	for tool in $(SETUP_TOOLS); do command -v "$$tool" >/dev/null 2>&1 || missing="$$missing $$tool"; done; \
	[ -n "$(CLANG_FORMAT)" ] || missing="$$missing clang-format"; \
	[ -n "$(CLANG_TIDY)" ] || missing="$$missing clang-tidy"; \
	if [ -n "$$missing" ]; then \
		echo "missing:$$missing" >&2; \
		echo "see docs/development.md, Build requirements" >&2; \
		exit 1; \
	fi; \
	echo "ok: every tool make verify needs is on PATH"

configure: ## Configure the host build (build/dev)
	@command -v cmake >/dev/null 2>&1 || { echo "install: brew install cmake"; exit 1; }
	@command -v ninja >/dev/null 2>&1 || { echo "install: brew install ninja"; exit 1; }
	cmake --preset dev

build: configure ## Build the library and the tests (build/dev)
	cmake --build --preset dev

test-unit: build ## Run the unit tests on the host build
	ctest --preset dev

test-sanitize: ## Build and run the unit tests with ASan and UBSan (build/asan-ubsan)
	@command -v cmake >/dev/null 2>&1 || { echo "install: brew install cmake"; exit 1; }
	@command -v ninja >/dev/null 2>&1 || { echo "install: brew install ninja"; exit 1; }
	cmake --preset asan-ubsan
	cmake --build --preset asan-ubsan
	ctest --preset asan-ubsan

test: test-unit test-sanitize ## L1 - unit tests on the plain and the sanitized build

# TEST is a ctest -R regular expression over test names (<Suite>.<Test>).
test-one: ## Build build/dev and run only the tests whose name matches TEST=<regex>
	@if [ -z "$(TEST)" ]; then echo "usage: make test-one TEST=<ctest -R regex>, e.g. TEST=Skeleton" >&2; exit 2; fi
	@$(MAKE) --no-print-directory build
	ctest --preset dev -R '$(TEST)'

clean: ## Remove the build trees (build/ only)
	rm -rf build

# clang-tidy ignores a .clang-tidy it cannot parse (for example a key its
# release does not know) and still exits 0, so lint-cpp fails on any message
# from --dump-config first. The header filter is anchored to this checkout, so
# headers under build/ (downloaded test dependencies) are never checked.
lint-cpp: configure ## Check C++ formatting (clang-format) and static analysis (clang-tidy)
	@test -n "$(CLANG_FORMAT)" || { echo 'install: brew install llvm, then put "$$(brew --prefix llvm)/bin" on PATH'; exit 1; }
	@test -n "$(CLANG_TIDY)" || { echo 'install: brew install llvm, then put "$$(brew --prefix llvm)/bin" on PATH'; exit 1; }
	$(CXX_SOURCES) | xargs -0 -r $(CLANG_FORMAT) --dry-run --Werror
	@err="$$($(CLANG_TIDY) --dump-config 2>&1 >/dev/null)"; \
	if [ -n "$$err" ]; then echo "$$err" >&2; echo "clang-tidy cannot read .clang-tidy" >&2; exit 1; fi
	$(CXX_TRANSLATION_UNITS) | xargs -0 -r $(CLANG_TIDY) -p build/dev --quiet --header-filter='^$(CURDIR)/(include|src|tests)/'

verify: lint test ## L0+L1 - canonical local pre-PR gate

ci-pr: verify ## Alias of verify; what ci.yml runs

# The tools ci.yml installs before `make ci-pr`; maintenance.yml passes its own
# TOOLS. Kit tools go to the template's scripts/install-ci-tools.sh; the tools
# this repository adds (EXTRA_CI_TOOLS, pinned in scripts/tool-pins.extra and
# scripts/tool-pins.yocto) go to scripts/install-extra-tools.sh, so the kit
# script stays identical to upstream. The C++ compiler, clang-format and
# clang-tidy come with the runner image.
CI_TOOLS := markdownlint-cli2 yamllint actionlint gitleaks lychee syft cmake ninja
EXTRA_CI_TOOLS := syft cmake ninja
TOOLS ?= $(CI_TOOLS)

ci-tools: ## Install pinned CI tools (CI only) - default CI_TOOLS, or TOOLS="lychee"
	@set -e; kit="$(filter-out $(EXTRA_CI_TOOLS),$(TOOLS))"; extra="$(filter $(EXTRA_CI_TOOLS),$(TOOLS))"; \
	if [ -n "$$kit" ]; then scripts/install-ci-tools.sh $$kit; fi; \
	if [ -n "$$extra" ]; then scripts/install-extra-tools.sh $$extra; fi

# Two checks: the template's (kit pins and scripts/tool-pins.extra against
# upstream releases) and the local one (scripts/tool-pins.yocto against the
# Yocto recipes). Both run even when the first fails.
check-tool-versions: ## Compare CI tool pins against upstream and the Yocto recipes (weekly maintenance; makes network calls)
	@rc=0; \
	scripts/check-tool-versions.sh || rc=1; \
	scripts/check-local-pins.sh || rc=1; \
	exit $$rc

maintenance: ## Everything the weekly maintenance workflow runs (network; not in verify)
	@rc=0; \
	$(MAKE) --no-print-directory lint-docs-external || rc=1; \
	$(MAKE) --no-print-directory check-tool-versions || rc=1; \
	exit $$rc

# --- Licence hygiene and SBOM -------------------------------------------------
# `lint-licenses` is part of `lint`; syft is pinned in scripts/tool-pins.extra
# and installed by `make ci-tools`.
# Both targets skip ./build: it holds build trees, including the test-only
# dependencies CMake downloads at configure time, none of which is delivered.
# Both targets switch off syft's two GitHub Actions catalogers: the actions a
# workflow or action.yml references are CI tooling, not delivered with the
# product, and carry no licence data. Do not `--exclude './.github/**'` instead:
# that also drops the npm dependencies of a local action under .github/actions/.
# Lock files such as pnpm-lock.yaml and uv.lock carry no licence data, so both
# targets let syft look licences up from the package registries (network).
# SBOM_IMAGES lists the container images that ship with the product (for
# example SBOM_IMAGES="ghcr.io/owner/api:1.2.3 nginx:1.30.5-alpine"). `sbom`
# writes one full SPDX file per image. `lint-licenses` also checks each image
# (without binary classifiers): language packages and Go modules against the
# allowlist; OS packages are the system layer, covered by the source offer, so
# only licences the policy rejects outright (AGPL, SSPL, ...) fail there.
# Output names carry a short hash of the image reference, so two references
# never map to the same file.
SYFT_ENV := SYFT_JAVASCRIPT_SEARCH_REMOTE_LICENSES=true SYFT_PYTHON_SEARCH_REMOTE_LICENSES=true SYFT_GOLANG_SEARCH_REMOTE_LICENSES=true
SYFT_CATALOGERS := --select-catalogers '-github-actions-usage-cataloger,-github-action-workflow-usage-cataloger'
SYFT_IMAGE_CATALOGERS := --select-catalogers '-binary-classifier-cataloger,-elf-binary-package-cataloger,-pe-binary-package-cataloger,-linux-kernel-cataloger'
SYFT_EXCLUDES := --exclude './build/**'
SBOM_IMAGES ?=

lint-licenses: ## Reject copyleft dependencies (GPL/AGPL/LGPL/SSPL/...)
	@command -v syft >/dev/null 2>&1 || { echo "install: brew install syft"; exit 1; }
	set -o pipefail; $(SYFT_ENV) syft dir:. -o json -q $(SYFT_CATALOGERS) $(SYFT_EXCLUDES) | python3 scripts/check-licenses.py
	@set -o pipefail; for img in $(SBOM_IMAGES); do \
		echo "image $$img"; \
		$(SYFT_ENV) syft "$$img" -o json -q $(SYFT_IMAGE_CATALOGERS) | python3 scripts/check-licenses.py --image || exit 1; \
	done

sbom: ## Write SPDX SBOM + readable third-party licence list to dist/ (repo and SBOM_IMAGES)
	@command -v syft >/dev/null 2>&1 || { echo "install: brew install syft"; exit 1; }
	@mkdir -p dist
	$(SYFT_ENV) syft dir:. -q $(SYFT_CATALOGERS) $(SYFT_EXCLUDES) -o spdx-json=dist/sbom.spdx.json -o template=dist/third-party-licences.txt -t scripts/licence-table.tmpl
	@echo "wrote dist/sbom.spdx.json and dist/third-party-licences.txt"
	@for img in $(SBOM_IMAGES); do \
		safe=$$(printf '%s' "$$img" | tr -c 'A-Za-z0-9.-' '_')-$$(printf '%s' "$$img" | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:8])'); \
		$(SYFT_ENV) syft "$$img" -q -o spdx-json="dist/sbom-image-$$safe.spdx.json" -o template="dist/third-party-licences-image-$$safe.txt" -t scripts/licence-table.tmpl || exit 1; \
		echo "wrote dist/sbom-image-$$safe.spdx.json"; \
	done
