# Troubleshooting Scenarios

Reproducible fault scenarios for OpenShift clusters. Each scenario deploys a specific fault (misconfiguration, resource exhaustion, network issue, etc.) on a live cluster with setup and cleanup scripts. Use them for automated evaluations, manual troubleshooting, or live demos.

## Contents

- **[evals/](evals/)**: Fault scenarios with setup/cleanup scripts and Kubernetes fixtures. Designed for automated evals of OpenShift troubleshooting tools (Lightspeed, Incident Detection, and others), but can also be run manually on any cluster.
- **[labs/](labs/)**: Multi-service scenarios with richer fault models (cascading failures, graduated alerts, red herrings). Designed for live demos and manual troubleshooting practice.

## Scenario Structure

Each scenario under `evals/scenarios/` is a self-contained directory:

```
blocked_deployment/
  fixtures/           Kubernetes manifests that reproduce the fault
  setup.sh            Deploys fixtures to the cluster
  cleanup.sh          Removes everything the scenario created
  evals-*.yaml        One per tool under test (e.g. OLS Agentic, OLS Classic)
```

Scenarios are generic: they deploy real Kubernetes resources (Deployments, Services, ConfigMaps, NetworkPolicies, PrometheusRules, etc.) and create real faults on a live cluster. They are not tied to any specific AI tool.

## Running Evals for OpenShift Lightspeed

Scenarios include eval definitions for OpenShift Lightspeed (OLS). The [lightspeed-evaluation](https://github.com/lightspeed-core/lightspeed-evaluation) framework orchestrates each run: deploy the fault, query OLS, score the response with a judge LLM. All commands run from the `evals/` directory.

### OLS Agentic

Each scenario folder contains an `evals-ols-agentic.yaml` with the eval definitions. Configure which models to test and how many repeats per scenario in `evals/system-ols-agentic.yaml`. Running `make setup-ols-agentic` automatically syncs the Agent CRs on the cluster with the agents defined in the system config.

```bash
cd evals
make setup-ols-agentic
make eval-ols-agentic                                          # run all scenarios
make eval-ols-agentic SCENARIO=stuck_rollout                   # one scenario
make eval-ols-agentic SCENARIO=stuck_rollout,exhausted_quota   # multiple
make eval-ols-agentic TAG=alert                                # filter by tag
```

### OLS Classic

Each scenario folder that supports OLS Classic contains an `evals-ols-classic.yaml` with the eval definitions. Configure the OLS model and provider in `evals/system-ols-classic.yaml`.

```bash
cd evals
make setup-ols-classic
make eval-ols-classic                                          # run all scenarios
make eval-ols-classic SCENARIO=crashlooping_pod_alert          # one scenario
```

Run `make help` for all targets and options.

### Requirements

- OpenShift cluster accessible via `oc login` (5.x for OLS Agentic, 4.x+ for OLS Classic)
- `OPENAI_API_KEY` exported (judge LLM)
- Python 3.13+

### Results and reports

Eval runs produce logs and reports under `evals/results/` (gitignored). Reports worth keeping can be promoted to `evals/reports/` (tracked in git).
