SCRIPTS_DIR := $(realpath ../scripts)

ALL_SCENARIOS := \
	blocked_deployment \
	blocked_deployment_alert \
	blocked_deployment_alert_remediation \
	batch_submission_timeouts \
	blocked_dns \
	cascading_failure \
	crashlooping_pod_alert \
	crashlooping_pod_alert_remediation \
	degraded_namespace \
	destructive_resistance \
	diagnostic_trap \
	double_fault \
	empty_endpoints \
	evicted_pod \
	excessive_permissions \
	exhausted_quota \
	exhausted_quota_alert \
	exhausted_quota_alert_remediation \
	failed_job \
	failed_replicaset \
	failed_start \
	failing_api_alert \
	failing_api_alert_cross_namespace \
	failing_api_alert_cross_namespace_remediation \
	failing_api_alert_remediation \
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
	nothing_wrong \
	orphaned_configmaps \
	orphaned_pvc \
	oversized_requests \
	partial_fix \
	pending_pvc_alert \
	pending_pvc_alert_remediation \
	pending_replicas \
	red_herring \
	refused_connections \
	refused_service \
	restarting_pod_alert \
	stuck_rollout \
	stuck_rollout_alert \
	stuck_rollout_alert_remediation \
	timeout_connections \
	unbalanced_replicas \
	unknown_autoscaler \
	unknown_autoscaler_alert \
	unknown_autoscaler_alert_remediation \
	unprivileged_pod \
	unready_pod_alert \
	unready_pod_alert_remediation \
	unscheduled_pod
OLS_CLASSIC_SCENARIOS := \
	batch_submission_timeouts \
	crashlooping_pod_alert \
	failed_job \
	failing_api_alert \
	failing_api_alert_cross_namespace \
	pending_pvc_alert \
	refused_connections \
	restarting_pod_alert \
	timeout_connections \
	unbalanced_replicas \
	unready_pod_alert
SCENARIO ?=
TAG ?=
AGENT ?=
SETUP_MODE ?= run

COMMA := ,
EMPTY :=
SPACE := $(EMPTY) $(EMPTY)

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

_OLS_CLASSIC_CANDIDATES := $(filter $(_CANDIDATES),$(OLS_CLASSIC_SCENARIOS))
ifdef TAG
  _OLS_CLASSIC := $(shell for d in $(_OLS_CLASSIC_CANDIDATES); do \
    for t in $(subst $(COMMA), ,$(TAG)); do \
      grep -q '^    - '"$$t"'$$' $$d/evals-ols-classic.yaml 2>/dev/null && echo $$d && break; \
    done; \
  done)
else
  _OLS_CLASSIC := $(_OLS_CLASSIC_CANDIDATES)
endif

.PHONY: setup setup-ols-classic eval eval-ols-classic cleanup cleanup-ols-classic help

setup:
	@$(SCRIPTS_DIR)/setup-venv.sh
	@../venv/bin/python3 $(SCRIPTS_DIR)/sync-agent-crs.py system.yaml
	@echo ""
	@echo "NOTE: Install lightspeed-agentic-operator manually by following:"
	@echo "  https://github.com/openshift/lightspeed-agentic-operator/tree/main/hack/quickstart"
	@echo "This will be automated in the future."

setup-ols-classic: setup
	@bash $(SCRIPTS_DIR)/preflight.sh
	@bash $(SCRIPTS_DIR)/setup-ols.sh

eval:
ifeq ($(SCENARIOS),)
	@echo "No scenarios match the given filters."
else
	@bash $(SCRIPTS_DIR)/eval-ols-agentic.sh \
	  --system-config system.yaml \
	  --setup-mode $(SETUP_MODE) \
	  $(if $(AGENT),--agents $(subst $(COMMA), ,$(AGENT))) \
	  $(if $(TAG),--tags $(subst $(COMMA), ,$(TAG))) \
	  --scenarios $(SCENARIOS)
endif

eval-ols-classic:
ifeq ($(_OLS_CLASSIC),)
	@echo "No OLS classic scenarios match the given filters."
else
	@bash $(SCRIPTS_DIR)/eval-ols-classic.sh \
	  --system-config system-ols-classic.yaml \
	  $(if $(TAG),--tags $(subst $(COMMA), ,$(TAG))) \
	  --scenarios $(_OLS_CLASSIC)
endif

cleanup:
	@rm -rf ../venv
	@echo "venv removed."
	@echo ""
	@echo "NOTE: Remove lightspeed-agentic-operator manually for now."
	@echo "This will be automated in the future."

cleanup-ols-classic: cleanup
	@bash $(SCRIPTS_DIR)/cleanup-ols.sh

help:
	@echo "Usage: make <target> [SETUP_MODE=run|scenario]"
	@echo ""
	@echo "Targets:"
	@echo "  setup              Install venv (OLS agentic is manual for now)"
	@echo "  setup-ols-classic  Install venv and OLS classic"
	@echo "  eval               Run agentic scenarios ($(words $(SCENARIOS)) matched)"
	@echo "  eval-ols-classic   Run OLS classic scenarios ($(words $(_OLS_CLASSIC)) matched)"
	@echo "  cleanup            Remove venv (OLS agentic is manual for now)"
	@echo "  cleanup-ols-classic Remove venv and OLS classic"
	@echo "  help               Show this help"
	@echo ""
	@echo "Options (shared):"
	@echo "  SCENARIO=...              Comma-separated scenario(s) to run (default: all)"
	@echo "  TAG=...                   Filter by tag (default: none)"
	@echo ""
	@echo "Options (eval):"
	@echo "  AGENT=...                 Comma-separated agent model(s) to run (default: all from system.yaml)"
	@echo "  SETUP_MODE=run|scenario   Setup/cleanup lifecycle (default: run)"
	@echo "    run:      per (scenario, agent, repeat) - for mutating agents"
	@echo "    scenario: per scenario - for read-only agents, parallel OK"
	@echo "  Agents and repeat count are read from system.yaml.(agents can be overridden with AGENT=)."
	@echo "  Example: make eval AGENT=gpt-5.4,gemini-2.5-pro SCENARIO=blocked_deployment"
	@echo ""
	@echo "Options (eval-ols-classic):"
	@echo "  Agents and repeat count are read from system-ols-classic.yaml."
	@echo ""
	@echo "Agentic scenarios:"
	@echo "$(SCENARIOS)" | tr ' ' '\n' | column -x -c $$(tput cols) | expand | sed 's/^/  /'
	@echo ""
	@echo "OLS classic scenarios:"
	@echo "$(_OLS_CLASSIC)" | tr ' ' '\n' | column -x -c $$(tput cols) | expand | sed 's/^/  /'
