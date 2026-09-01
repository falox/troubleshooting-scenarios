##@ Linting

LINT_DIRS ?= generic kiali-ossm kubevirt netobserv
TOOLS_VENV ?= .tools
TOOLS_PYTHON ?= python3
TOOLS_REQUIREMENTS := requirements-tools.txt
TOOLS_STAMP := $(TOOLS_VENV)/.installed

.PHONY: tools lint lint-shell lint-yaml

tools: $(TOOLS_STAMP) ## Install local development tools

$(TOOLS_STAMP): $(TOOLS_REQUIREMENTS)
	@command -v $(TOOLS_PYTHON) >/dev/null 2>&1 || \
	  { printf '\033[0;31mERROR:\033[0m %s not found.\n' "$(TOOLS_PYTHON)"; exit 1; }
	$(TOOLS_PYTHON) -m venv $(TOOLS_VENV)
	$(TOOLS_VENV)/bin/python -m pip install --quiet --requirement $(TOOLS_REQUIREMENTS)
	@touch $(TOOLS_STAMP)

lint: tools lint-shell lint-yaml ## Install tools and run all linters

lint-shell: ## Lint shell scripts with shellcheck
	@files=$$(git ls-files --cached --others --exclude-standard -- $(LINT_DIRS) | \
	  awk '/\.sh$$/'); \
	if [ -z "$$files" ]; then \
	  printf 'No .sh files found in: %s\n' "$(LINT_DIRS)"; \
	else \
	  printf '==> shellcheck %s file(s)\n' "$$(echo "$$files" | wc -w)"; \
	  echo "$$files" | xargs $(TOOLS_VENV)/bin/shellcheck; \
	fi

lint-yaml: ## Lint YAML files with yamllint
	@files=$$(git ls-files --cached --others --exclude-standard -- $(LINT_DIRS) | \
	  awk '/\.ya?ml$$/'); \
	if [ -z "$$files" ]; then \
	  printf 'No YAML files found in: %s\n' "$(LINT_DIRS)"; \
	else \
	  printf '==> yamllint %s file(s)\n' "$$(echo "$$files" | wc -w)"; \
	  echo "$$files" | xargs $(TOOLS_VENV)/bin/yamllint -c .yamllint.yml; \
	fi

##@ Maintenance

OLS_NS ?= openshift-lightspeed
SCRIPTS_DIR := scripts

.PHONY: help cleanup

help: ## Show available targets
	@echo ""
	@echo "  Root targets (maintenance):"
	@echo "    make tools            Install local development tools"
	@echo "    make cleanup          Remove OLS operator + venv"
	@echo "    make lint             Install tools and run all linters"
	@echo ""
	@echo "  Per-team workflow (run from team directory):"
	@echo "    cd kiali-ossm && make setup && make evals && make cleanup"
	@echo "    cd kubevirt   && make setup && make evals && make cleanup"
	@echo "    cd netobserv  && make setup && make evals && make cleanup"
	@echo ""

cleanup: ## Remove OLS operator + local venv
	@OLS_NS=$(OLS_NS) bash $(SCRIPTS_DIR)/cleanup-ols.sh
	rm -rf venv
	@echo "venv removed."
