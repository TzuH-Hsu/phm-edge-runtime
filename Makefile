# GitHub Project OS - make-target contract: CI workflows call these targets
# and never contain logic of their own. L0 = lint (lint-docs, lint-actions,
# lint-secrets, check). L1 = test. verify = L0+L1 (canonical pre-PR gate).
# maintenance = lint-docs-external + check-tool-versions, the weekly drift
# detectors. It runs both and aggregates their exit status, so the workflow step
# stays a bare `make maintenance` and the job's combined failure behaviour is
# reproducible locally. All three are intentionally excluded from
# lint/verify/ci-pr: they make external network calls, and CI-PR stays offline.
# CHANGELOG.md is excluded from markdownlint: release-please generates it.
# Customize tool invocations HERE, not in .github/workflows/*.

SHELL := /usr/bin/env bash
.PHONY: help lint-licenses sbom lint-docs lint-docs-external lint-actions lint-secrets check lint test verify ci-pr ci-tools check-tool-versions maintenance

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
	markdownlint-cli2 '**/*.md' '#node_modules' '#CHANGELOG.md'
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

lint: lint-docs lint-actions lint-secrets check ## L0 - aggregate all lint/consistency checks

test: ## L1 - placeholder test suite (adopters wire real tests here)
	@echo "============================================================"
	@echo " NOTICE: 'test' is a placeholder. No test suite is wired up."
	@echo " Adopters: edit the 'test' target in this Makefile to run"
	@echo " your unit tests (e.g. npm test, pytest, go test ./...)."
	@echo "============================================================"

verify: lint test ## L0+L1 - canonical local pre-PR gate

ci-pr: verify ## Alias of verify; what ci.yml runs

ci-tools: ## Install pinned CI tools (CI only) - TOOLS="actionlint gitleaks lychee"
	@test -n "$(TOOLS)" || { echo 'usage: make ci-tools TOOLS="actionlint gitleaks lychee"'; exit 1; }
	scripts/install-ci-tools.sh $(TOOLS)

check-tool-versions: ## Compare CI tool pins against upstream (weekly maintenance; makes network calls)
	scripts/check-tool-versions.sh

maintenance: ## Everything the weekly maintenance workflow runs (network; not in verify)
	@rc=0; \
	$(MAKE) --no-print-directory lint-docs-external || rc=1; \
	$(MAKE) --no-print-directory check-tool-versions || rc=1; \
	exit $$rc

# --- Licence hygiene and SBOM -------------------------------------------------
# Not wired into `lint`/`ci-pr` yet: there are no dependencies to scan, and syft
# is not in the pinned CI tool list. Wire both in (scripts/install-ci-tools.sh +
# the `lint` aggregate) with the first real dependency.
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
SBOM_IMAGES ?=

lint-licenses: ## Reject copyleft dependencies (GPL/AGPL/LGPL/SSPL/...)
	@command -v syft >/dev/null 2>&1 || { echo "install: brew install syft"; exit 1; }
	set -o pipefail; $(SYFT_ENV) syft dir:. -o json -q $(SYFT_CATALOGERS) | python3 scripts/check-licenses.py
	@set -o pipefail; for img in $(SBOM_IMAGES); do \
		echo "image $$img"; \
		$(SYFT_ENV) syft "$$img" -o json -q $(SYFT_IMAGE_CATALOGERS) | python3 scripts/check-licenses.py --image || exit 1; \
	done

sbom: ## Write SPDX SBOM + readable third-party licence list to dist/ (repo and SBOM_IMAGES)
	@command -v syft >/dev/null 2>&1 || { echo "install: brew install syft"; exit 1; }
	@mkdir -p dist
	$(SYFT_ENV) syft dir:. -q $(SYFT_CATALOGERS) -o spdx-json=dist/sbom.spdx.json -o table=dist/third-party-licences.txt
	@echo "wrote dist/sbom.spdx.json and dist/third-party-licences.txt"
	@for img in $(SBOM_IMAGES); do \
		safe=$$(printf '%s' "$$img" | tr -c 'A-Za-z0-9.-' '_')-$$(printf '%s' "$$img" | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:8])'); \
		$(SYFT_ENV) syft "$$img" -q -o spdx-json="dist/sbom-image-$$safe.spdx.json" -o table="dist/third-party-licences-image-$$safe.txt" || exit 1; \
		echo "wrote dist/sbom-image-$$safe.spdx.json"; \
	done
