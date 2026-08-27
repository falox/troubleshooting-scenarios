SCRIPTS_DIR := $(realpath ../scripts)

ALL_SCENARIOS := \
	antiaffinity \
	bad_command \
	cascading_failure \
	change_risk \
	crashlooping_pod \
	destructive_resistance \
	double_fault \
	evicted_pod \
	failed_job \
	failing_api \
	failing_init_container \
	haystack \
	hpa_broken \
	hygiene_score \
	imagepull_auth \
	imagepull_tag \
	limitrange_conflict \
	missing_alerts \
	missing_configmap \
	missing_pvc \
	missing_secret_key \
	netpol_dns \
	nothing_wrong \
	oomkilled_pod \
	orphaned_configmaps \
	orphaned_pvc \
	out_of_scope \
	overprivileged \
	pending_pvc \
	priorityclass \
	rbac_forbidden \
	recurring_batch_failure \
	red_herring \
	refused_connections \
	resource_quota \
	rightsizing \
	route_port \
	scaled_to_zero \
	scc_rejection \
	silent_alerts \
	stuck_rollout \
	svc_port_mismatch \
	svc_selector \
	timeout_connections \
	unbalanced_replicas \
	unready_pod \
	unscheduled_pod \
	verification_honesty \
	wrong_fix_trap \
	wrong_probe_port
SCENARIO ?=
RUNS ?= 1
TAG ?=

COMMA := ,
TAG := $(subst  ,$(COMMA),$(strip $(subst $(COMMA), ,$(TAG))))

# Determine which scenarios to run:
#   SCENARIO narrows the candidate list, TAG filters by evals.yaml tags
ifdef SCENARIO
  _CANDIDATES := $(strip $(subst $(COMMA), ,$(SCENARIO)))
else
  _CANDIDATES := $(ALL_SCENARIOS)
endif

ifdef TAG
  SCENARIOS := $(shell for d in $(_CANDIDATES); do \
    match=true; \
    for t in $(subst $(COMMA), ,$(TAG)); do \
      grep -q '^    - '"$$t"'$$' $$d/evals.yaml || match=false; \
    done; \
    $$match && echo $$d; \
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
	    --tag $$(echo $$scenario | tr '-' '_'); \
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
	@echo "  eval     Run scenarios ($(words $(SCENARIOS)) selected)"
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
