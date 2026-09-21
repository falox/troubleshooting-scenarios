SCRIPTS_DIR := $(realpath ../scripts)
SCENARIOS_DIR := scenarios

_ALL_OLS_AGENTIC := \
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
_ALL_OLS_CLASSIC := \
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
  _OLS_AGENTIC_CANDIDATES := $(strip $(subst $(COMMA), ,$(SCENARIO)))
else
  _OLS_AGENTIC_CANDIDATES := $(_ALL_OLS_AGENTIC)
endif

ifdef TAG
  OLS_AGENTIC_SCENARIOS := $(shell for d in $(_OLS_AGENTIC_CANDIDATES); do \
    for t in $(subst $(COMMA), ,$(TAG)); do \
      grep -q '^    - '"$$t"'$$' $(SCENARIOS_DIR)/$$d/evals-ols-agentic.yaml 2>/dev/null && echo $$d && break; \
    done; \
  done)
else
  OLS_AGENTIC_SCENARIOS := $(_OLS_AGENTIC_CANDIDATES)
endif

_OLS_CLASSIC_CANDIDATES := $(filter $(_OLS_AGENTIC_CANDIDATES),$(_ALL_OLS_CLASSIC))
ifdef TAG
  OLS_CLASSIC_SCENARIOS := $(shell for d in $(_OLS_CLASSIC_CANDIDATES); do \
    for t in $(subst $(COMMA), ,$(TAG)); do \
      grep -q '^    - '"$$t"'$$' $(SCENARIOS_DIR)/$$d/evals-ols-classic.yaml 2>/dev/null && echo $$d && break; \
    done; \
  done)
else
  OLS_CLASSIC_SCENARIOS := $(_OLS_CLASSIC_CANDIDATES)
endif

.PHONY: setup-ols-agentic setup-ols-classic eval-ols-agentic eval-ols-classic cleanup-ols-agentic cleanup-ols-classic help

setup-ols-agentic:
	@$(SCRIPTS_DIR)/setup-venv.sh
	@../venv/bin/python3 $(SCRIPTS_DIR)/sync-agent-crs.py system-ols-agentic.yaml
	@echo ""
	@echo "NOTE: Install lightspeed-agentic-operator manually by following:"
	@echo "  https://github.com/openshift/lightspeed-agentic-operator/tree/main/hack/quickstart"
	@echo "This will be automated in the future."

setup-ols-classic: setup-ols-agentic
	@bash $(SCRIPTS_DIR)/preflight.sh
	@bash $(SCRIPTS_DIR)/setup-ols.sh

eval-ols-agentic:
ifeq ($(OLS_AGENTIC_SCENARIOS),)
	@echo "No scenarios match the given filters."
else
	@bash $(SCRIPTS_DIR)/eval-ols-agentic.sh \
	  --system-config system-ols-agentic.yaml \
	  --setup-mode $(SETUP_MODE) \
	  $(if $(AGENT),--agents $(subst $(COMMA), ,$(AGENT))) \
	  $(if $(TAG),--tags $(subst $(COMMA), ,$(TAG))) \
	  --scenarios $(addprefix $(SCENARIOS_DIR)/,$(OLS_AGENTIC_SCENARIOS)) \
	  || { status=$$?; if [ "$$status" -ne 64 ]; then exit "$$status"; fi; }
endif

eval-ols-classic:
ifeq ($(OLS_CLASSIC_SCENARIOS),)
	@echo "No OLS classic scenarios match the given filters."
else
	@bash $(SCRIPTS_DIR)/eval-ols-classic.sh \
	  --system-config system-ols-classic.yaml \
	  $(if $(TAG),--tags $(subst $(COMMA), ,$(TAG))) \
	  --scenarios $(addprefix $(SCENARIOS_DIR)/,$(OLS_CLASSIC_SCENARIOS))
endif

cleanup-ols-agentic:
	@rm -rf ../venv
	@echo "venv removed."
	@echo ""
	@echo "NOTE: Remove lightspeed-agentic-operator manually for now."
	@echo "This will be automated in the future."

cleanup-ols-classic: cleanup-ols-agentic
	@bash $(SCRIPTS_DIR)/cleanup-ols.sh

help:
	@echo "Usage: make <target> [SETUP_MODE=run|scenario]"
	@echo ""
	@echo "Targets:"
	@echo "  setup-ols-agentic    Install venv (OLS agentic operator is manual for now)"
	@echo "  setup-ols-classic    Install venv and OLS classic"
	@echo "  eval-ols-agentic     Run OLS agentic scenarios"
	@echo "  eval-ols-classic     Run OLS classic scenarios"
	@echo "  cleanup-ols-agentic  Remove venv (OLS agentic operator is manual for now)"
	@echo "  cleanup-ols-classic  Remove venv and OLS classic"
	@echo "  help                 Show this help"
	@echo ""
	@echo "Options:"
	@echo "  SCENARIO=...              Comma-separated scenarios to run (default: all)"
	@echo "  TAG=...                   Filter scenarios by tag (default: none)"
	@echo "  SETUP_MODE=run|scenario   Setup/cleanup lifecycle (default: run)"
	@echo "    run:      per (scenario, agent, repeat) - for mutating agents"
	@echo "    scenario: per scenario - for read-only agents, parallel OK"
	@echo ""
	@echo "Examples:"
	@echo "  make eval-ols-agentic TAG=core SETUP_MODE=scenario"
	@echo "  make eval-ols-classic SCENARIO=blocked_deployment"
	@echo ""
	@echo "OLS agentic scenarios ($(words $(OLS_AGENTIC_SCENARIOS))):"
	@echo "$(OLS_AGENTIC_SCENARIOS)" | tr ' ' '\n' | column -x -c $$(tput cols) | expand | sed 's/^/  /'
	@echo ""
	@echo "OLS classic scenarios ($(words $(OLS_CLASSIC_SCENARIOS))):"
	@echo "$(OLS_CLASSIC_SCENARIOS)" | tr ' ' '\n' | column -x -c $$(tput cols) | expand | sed 's/^/  /'
