# netobserv evaluation scenarios

# Scenarios (must match tag: values in evals.yaml)
SCENARIOS = dns_latency \
            dns_nxdomain \
            packet_drops_kernel \
            packet_drops_policy \
            tls_issues \
            tcp_rtt

# MCP config
MCP_TOOLSETS = core,config,netobserv

# Shared infrastructure
include ../scripts/eval.mk

# Suite infrastructure (NetObserv operator)
include build/netobserv.mk

# Setup: NetObserv operator first (MCP netobserv toolset requires operator to be installed)
# then shared infra (MCP with netobserv toolset) + FlowCollector
.PHONY: setup
setup: netobserv-install-operator
	$(MAKE) _setup-shared
	$(MAKE) netobserv-install-flowcollector

# Cleanup: NetObserv operator + shared infra
.PHONY: cleanup
cleanup:
	$(MAKE) clean-netobserv-openshift
	$(MAKE) _cleanup-shared
