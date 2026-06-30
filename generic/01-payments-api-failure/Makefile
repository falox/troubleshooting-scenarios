# Payments API failure evaluation scenario
#
# Usage:
#   make setup     Install venv + OLS + MCP + deploy scenario
#   make evals     Run all scenarios
#   make cleanup   Remove scenario resources + MCP

# Scenarios (must match tag: values in evals.yaml)
SCENARIOS = payments_api_failure

# MCP config
MCP_TOOLSETS = core,config

# Shared infrastructure
include ../../scripts/eval.mk

# Setup: shared infra (scenario setup.sh handles deployment)
.PHONY: setup
setup: _setup-shared

# Cleanup: shared infra (scenario cleanup.sh handles resource deletion)
.PHONY: cleanup
cleanup:
	$(MAKE) _cleanup-shared

# Build and push container images
.PHONY: update-images
update-images:
	@./scripts/update-images.sh $(REGISTRY)
