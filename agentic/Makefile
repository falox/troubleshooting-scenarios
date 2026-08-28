SCRIPTS_DIR := $(realpath ../scripts)

ALL_SCENARIOS := \
	blocked_deployment \
	blocked_deployment_alert \
	blocked_dns \
	cascading_failure \
	crashlooping_pod_alert \
	degraded_namespace \
	destructive_resistance \
	diagnostic_trap \
	double_fault \
	empty_endpoints \
	evicted_pod \
	excessive_permissions \
	exhausted_quota \
	exhausted_quota_alert \
	failed_job \
	failed_replicaset \
	failed_start \
	failing_api_alert \
	failing_init_container \
	failing_probe \
	failing_route \
	forbidden_api \
	imagepull_missing \
	imagepull_private \
	inactive_deployment \
	missing_configmap \
	missing_pvc \
	missing_secret_key \
	orphaned_configmaps \
	orphaned_pvc \
	oversized_requests \
	partial_fix \
	pending_pvc_alert \
	pending_replicas \
	red_herring \
	refused_service \
	stuck_rollout \
	stuck_rollout_alert \
	timeout_connections \
	unbalanced_replicas \
	unknown_autoscaler \
	unknown_autoscaler_alert \
	unprivileged_pod \
	unready_pod_alert \
	unscheduled_pod
SCENARIO ?=
RUNS ?= 1
TAG ?=

COMMA := ,

ifdef SCENARIO
  _CANDIDATES := $(strip $(subst $(COMMA), ,$(SCENARIO)))
else
  _CANDIDATES := $(ALL_SCENARIOS)
endif

ifdef TAG
  SCENARIOS := $(shell for d in $(_CANDIDATES); do \
    for t in $(subst $(COMMA), ,$(TAG)); do \
      grep -q '^    - '"$$t"'$$' $$d/evals.yaml 2>/dev/null && echo $$d && break; \
    done; \
  done)
else
  SCENARIOS := $(_CANDIDATES)
endif

.PHONY: setup eval cleanup help

setup:
	$(SCRIPTS_DIR)/setup-venv.sh
	@echo ""
	@echo "NOTE: Install lightspeed-agentic-operator manually by following:"
	@echo "  https://github.com/openshift/lightspeed-agentic-operator/tree/main/hack/quickstart"
	@echo "This will be automated in the future."

eval:
ifeq ($(SCENARIOS),)
	@echo "No scenarios match the given filters."
else
	@for scenario in $(SCENARIOS); do \
	  if [ ! -d "$$scenario" ]; then \
	    echo "Error: scenario '$$scenario' not found. Available scenarios:"; \
	    for d in */; do \
	      if [ -f "$$d/evals.yaml" ]; then echo "  $${d%/}"; fi; \
	    done; \
	    exit 1; \
	  fi; \
	done
	$(eval DATETIME := $(shell date +%Y%m%d_%H%M%S))
	$(eval LOGS_DIR := results/logs/$(DATETIME))
	$(eval SUMMARY := results/results_$(DATETIME).md)
	@for scenario in $(SCENARIOS); do \
	  echo "==> Setup: $$scenario"; \
	  if [ -x $$scenario/setup.sh ]; then bash $$scenario/setup.sh; fi; \
	  echo "==> Scenario: $$scenario"; \
	  bash $(SCRIPTS_DIR)/run-agentic-evals.sh \
	    --system-config system.yaml \
	    --evals $$scenario/evals.yaml \
	    --results-dir $(LOGS_DIR) \
	    --runs $(RUNS) \
	    $(if $(TAG),--tags $(subst $(COMMA), ,$(TAG))); \
	  echo "==> Cleanup: $$scenario"; \
	  if [ -x $$scenario/cleanup.sh ]; then bash $$scenario/cleanup.sh; fi; \
	done
	@echo ""
	@echo "==> Generating summary..."
	@../venv/bin/python $(SCRIPTS_DIR)/summarize-agentic-evals.py \
	  $(LOGS_DIR) \
	  --output $(SUMMARY) \
	  $(foreach s,$(SCENARIOS),$s/evals.yaml) \
	  $$(find $(LOGS_DIR) -name '*_summary.json' | sort)
endif

cleanup:
	@for scenario in $(SCENARIOS); do \
	  if [ -x $$scenario/cleanup.sh ]; then \
	    echo "==> Cleanup: $$scenario"; \
	    bash $$scenario/cleanup.sh; \
	  fi; \
	done
	rm -rf ../venv
	@echo "venv removed."

help:
	@echo "Usage: make <target> [RUNS=N]"
	@echo ""
	@echo "Targets:"
	@echo "  setup    Install venv (lightspeed-agentic-operator is manual for now)"
	@echo "  eval     Run all the $(words $(SCENARIOS)) scenarios"
	@echo "  cleanup  Run scenario cleanup scripts and remove venv"
	@echo "  help     Show this help"
	@echo ""
	@echo "Options:"
	@echo "  SCENARIO=...  Comma-separated scenario(s) to run (default: all)"
	@echo "  RUNS=N        Number of runs per scenario (default: 1)"
	@echo "  TAG=...       Filter by tag, e.g. TAG=hard, TAG=alerts-adapter (default: none)"
	@echo ""
	@echo "Scenarios:"
	@echo "$(SCENARIOS)" | tr ' ' '\n' | column -x -c $$(tput cols) | expand | sed 's/^/  /'
