# NetObserv Evaluation Scenarios

Evaluation scenarios for AI-assisted diagnosis of OpenShift network observability problems. The scenarios use the `netobserv` MCP toolset and run with OLS-classic.

## Scenarios

| Scenario | Signal | Required feature |
|----------|--------|------------------|
| `dns_latency` | DNS latency in flow metrics and logs | `DNSTracking` |
| `dns_nxdomain` | NXDOMAIN and DNS failures | `DNSTracking` |
| `packet_drops_kernel` | Kernel packet drops | `PacketDrop` |
| `packet_drops_policy` | NetworkPolicy-related drops | `NetworkEvents`, `PacketDrop` |
| `tls_issues` | TLS and HTTPS connection errors | `NetworkEvents` |
| `tcp_rtt` | High TCP round-trip time | `FlowRTT` |

## Setup and running

The NetObserv operator, FlowCollector, MCP server, and OLS connection are set up automatically when an OLS-classic NetObserv evaluation runs. From the parent `evals/` directory:

```bash
make setup-ols-classic

# All NetObserv scenarios
make eval-ols-classic TAG=netobserv

# One scenario
make eval-ols-classic SCENARIO=netobserv/dns_latency
```

The scenario setup scripts deploy synthetic traffic and wait for NetObserv data to reach Loki before the query runs. `NETOBSERV_WARMUP_SECS` controls the default 120-second warm-up.

To manage NetObserv independently from this directory:

```bash
make setup-netobserv-openshift
make netobserv-status
make clean-netobserv-openshift
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NETOBSERV_NS` | `netobserv` | NetObserv pipeline namespace |
| `NETOBSERV_OPERATOR_NS` | `openshift-netobserv-operator` | Operator namespace |
| `NETOBSERV_CATALOG_SOURCE` | `redhat` | OLM catalog source |
| `NETOBSERV_CHANNEL` | _(automatic)_ | OLM channel |
| `NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT` | `10m` | FlowCollector readiness timeout |
| `NETOBSERV_DELETE_OPERATOR_NAMESPACE` | `yes` | Delete the operator namespace during cleanup |
| `MCP_TOOLSETS` | `core,config,netobserv` | MCP toolsets enabled for the group |

The legacy [`netobserv/`](../../netobserv/) suite remains available and is not modified by this migration.
