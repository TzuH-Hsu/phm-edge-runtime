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

lint-licenses: ## Reject copyleft dependencies (GPL/AGPL/LGPL/SSPL/...)
	@command -v syft >/dev/null 2>&1 || { echo "install: brew install syft"; exit 1; }
	syft dir:. -o json -q | python3 scripts/check-licenses.py

sbom: ## Write SPDX SBOM + readable third-party licence list to dist/
	@command -v syft >/dev/null 2>&1 || { echo "install: brew install syft"; exit 1; }
	@mkdir -p dist
	syft dir:. -q -o spdx-json=dist/sbom.spdx.json -o table=dist/third-party-licences.txt
	@echo "wrote dist/sbom.spdx.json and dist/third-party-licences.txt"
