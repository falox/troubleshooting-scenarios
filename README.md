# Troubleshooting Scenarios

Reproducible fault scenarios for OpenShift clusters. Each scenario deploys a specific fault (misconfiguration, resource exhaustion, network issue, etc.) on a live cluster with setup and cleanup scripts. Use them for automated evaluations, manual troubleshooting, or live demos.

## Contents

- **[evals/](evals/)**: Fault scenarios with setup/cleanup scripts and Kubernetes fixtures. Designed for automated evals of OpenShift troubleshooting tools (Lightspeed, Incident Detection, and others), but can also be run manually on any cluster.
- **[labs/](labs/)**: Multi-service scenarios with richer fault models (cascading failures, graduated alerts, red herrings). Designed for live demos and manual troubleshooting practice.

## Scenario Structure

Each scenario under `evals/scenarios/` is a self-contained directory:

```
scenario_name/
  fixtures/           Kubernetes manifests that reproduce the fault
  setup.sh            Deploys fixtures to the cluster
  cleanup.sh          Removes everything the scenario created
  evals-*.yaml        One per tool under test (e.g. OLS Agentic, OLS Classic)
```

Scenarios that require shared infrastructure (operators, MCP toolsets) are organized into **scenario groups**. A group is a directory containing its own `setup.sh` and `cleanup.sh` for one-time infrastructure provisioning, a `scripts/` directory with group-specific helpers, and individual scenario subdirectories:

```
group_name/
  setup.sh            Provisions shared infrastructure (runs once per group)
  cleanup.sh          Tears down shared infrastructure (runs once per group)
  scripts/            Group-specific helpers
  scenario1/          Individual scenario (same structure as above)
  scenario2/
  scenario3/
```

The eval runner detects grouped scenarios automatically and runs group setup before the first scenario in the group, then group cleanup after all scenarios in the group complete.

Scenarios are generic: they deploy real Kubernetes resources (Deployments, Services, ConfigMaps, NetworkPolicies, PrometheusRules, etc.) and create real faults on a live cluster. They are not tied to any specific AI tool.

## Running Evals for OpenShift Lightspeed

Scenarios include eval definitions for OpenShift Lightspeed (OLS). The [lightspeed-evaluation](https://github.com/lightspeed-core/lightspeed-evaluation) framework orchestrates each run: deploy the fault, query OLS, score the response with a judge LLM. All commands run from the `evals/` directory.

### OLS Agentic

Each scenario folder contains an `evals-ols-agentic.yaml` with the eval definitions. Configure which models to test and how many repeats per scenario in `evals/system-ols-agentic.yaml`. Running `make setup-ols-agentic` automatically syncs the Agent CRs on the cluster with the agents defined in the system config. Before a real evaluation, `make eval-ols-agentic` checks that these Agent CRs are present and match the system config; if they do not, it stops and asks you to run `make setup-ols-agentic`.

```bash
cd evals
make setup-ols-agentic
make eval-ols-agentic                                          # run all scenarios
make eval-ols-agentic SCENARIO=stuck_rollout                   # one scenario
make eval-ols-agentic SCENARIO=stuck_rollout,exhausted_quota   # multiple
make eval-ols-agentic TAG=alert                                # filter by tag
make eval-ols-agentic TAG=alert PREVIEW=1                      # preview matched scenarios
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
