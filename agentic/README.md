# Agentic Evals

Behavioral evals for automated troubleshooting with [OpenShift Agentic Lightspeed](https://github.com/openshift/lightspeed-agentic-operator). Each scenario deploys a fault on a live cluster, submits a configurable number of `AgenticRun`s and scores the analysis.

## Scenarios

| Suite | Symptom | Root Cause | Difficulty | Alert (fires in) |
|-------|---------|------------|------------|------------------|
| `antiaffinity` | Several pods stuck in Pending | Required pod anti-affinity on hostname with 10 replicas exceeds node count; only 3 needed for HA | Normal | |
| `failing_api` | Payment API returning 503s (100% error rate) | Reporting service leaks DB connections, exhausting the shared PostgreSQL pool | Hard | |
| `imagepull_auth` | Pod in ImagePullBackOff | Private registry image without imagePullSecret (auth failure) | Normal | |
| `netpol_dns` | App logs DNS resolution failures after security hardening | Default-deny egress NetworkPolicy blocks DNS; needs egress rule for port 5353 to openshift-dns | Medium | |
| `pending_pvc` | PVC stuck in Pending, pods cannot start | PVC references a StorageClass (`standard-v2`) that does not exist | Medium | ~30s |
| `recurring_batch_failure` | Batch processor errors during 03:00-03:05 UTC | Upstream service has a scheduled maintenance window causing connection timeouts | Medium | |
| `sporadic_api_timeout` | Report generator timeouts during 03:00-03:05 window | Upstream API has a scheduled maintenance window, not a bug in the application | Medium | |
| `route_port` | Route returns 503 but pod and service are healthy | Route targets port 9090 but service only exposes 8080; router has no valid backend | Normal | |
| `svc_port_mismatch` | Service connections refused despite endpoints existing and pod Ready | Service targetPort (8081) doesn't match the container's listening port (8080) | Normal | |
| `refused_connections` | Gateway-proxy returning connection refused errors | Config hot-reload loaded staging database/cache hosts into production; staging hosts unreachable from production VPC | Medium | |
| `resource_quota` | Deployment has zero pods | ResourceQuota caps pods at 2, fully consumed by existing blocker deployment | Normal | |
| `crashlooping_pod` | Pod in CrashLoopBackOff | Required environment variable `DEPLOY_ENV` is missing from the deployment spec | Normal | ~3min |
| `failed_job` | inventory-sync-validator Job fails | Job cannot connect to database at prod-db:3333 (connection refused) | Normal | |
| `oomkilled_pod` | Pods repeatedly OOMKilled / CrashLoopBackOff | Python app has a memory leak (~1MB/s) that exceeds the 60Mi container limit | Normal | ~2min |
| `orphaned_pvc` | PVCs attached to no workload | Two of three PVCs are not mounted by any pod or deployment | Normal | |
| `timeout_connections` | Frontend gets connection timeouts to backend | NetworkPolicy only allows ingress from `tier=backend`, blocking `tier=frontend` pods | Normal | |
| `unbalanced_replicas` | Namespaces have different pod counts | fleet-alpha has 6 pods vs fleet-alpha1 with 9, due to different deployment sets | Normal | |
| `unready_pod` | Pod running but not becoming Ready | HTTP readiness probe targets port 9200 but container has no HTTP server | Normal | ~1.5min |
| `unscheduled_pod` | Pod stuck in Pending, not scheduled to any node | nodeSelector requires `disk-type=ssd-high-iops` but no nodes have this label | Normal | |

## Prerequisites

- `oc login` to an OpenShift 5.x cluster
- `OPENAI_API_KEY` exported
- [lightspeed-agentic-operator](https://github.com/openshift/lightspeed-agentic-operator) installed

## Usage

All commands run from this directory.

```bash
make setup                  # Install Python venv
make evals                  # Run all scenarios
make evals SUITES="failing_api pending_pvc"  # Run specific scenarios
make evals RUNS=3           # Run each scenario 3 times
make cleanup                # Remove scenario resources and venv
make help                   # Show all targets and options
```
