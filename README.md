# Troubleshooting Scenarios

Reproducible faults for OpenShift clusters. Use them to evaluate troubleshooting
tools, practise manual diagnosis, or run demos.

- [Evals](evals/README.md): scenarios for automated evaluation and manual use.
- [Labs](labs/README.md): demos with manual fault controls.
- [Contributing](CONTRIBUTING.md): how to add a scenario and run checks.

## Requirements

Run the commands below from the repository root. You need:

- An OpenShift cluster and an active `oc login` session.
- Python 3.11–3.13 for the evaluation environment.
- `EVAL_OPENAI_API_KEY` for the judge and OpenAI models.
- `EVAL_VERTEX_CREDENTIALS` and `EVAL_VERTEX_PROJECT_ID` when active models use
  Google or Anthropic. The credentials value is a service account JSON path.

```bash
export EVAL_OPENAI_API_KEY="<openai-api-key>"
# Also set these when using Google or Anthropic:
export EVAL_VERTEX_CREDENTIALS="/path/to/service-account.json"
export EVAL_VERTEX_PROJECT_ID="<gcp-project-id>"
```

The setup targets create the local `venv/` and install the evaluation framework.

## OLS Agentic

Choose models and repeat counts in
[`evals/system-ols-agentic.yaml`](evals/system-ols-agentic.yaml).
The cluster needs the Lightspeed Agentic operator. The setup target syncs
Agent CRs; it does not install the operator.

```bash
make setup-ols-agentic
make eval-ols-agentic SCENARIO=blocked_deployment PREVIEW=1
make eval-ols-agentic SCENARIO=blocked_deployment
make eval-ols-agentic TAG=core
```

Before an evaluation, the runner checks that Agent CRs match the config.
Run `make setup-ols-agentic` again after changing agent settings.
For evaluations that change cluster resources, use `SETUP_MODE=run` to reset
resources before each agent and repeat.

## OLS Classic

Choose models in `agents.default.agent` in
[`evals/system-ols-classic.yaml`](evals/system-ols-classic.yaml).
Setup registers the active agents and judge models in OLS, using each entry's
`provider` and `model`. The first active agent sets the default model and must
use OpenAI. Remove Google and Anthropic entries for an OpenAI-only run.

```bash
make setup-ols-classic
make eval-ols-classic SCENARIO=crashlooping_pod_alert PREVIEW=1
make eval-ols-classic SCENARIO=crashlooping_pod_alert
make eval-ols-classic TAG=alert
```

Setup uses the `openshift-lightspeed` namespace. Without `SCENARIO` or `TAG`,
either evaluation target runs all scenarios supported by that mode.
See the [eval guide](evals/README.md#running-automated-evals) for filters,
setup modes, and failure handling.

## Manual setup and cleanup

Deploy faults without running an evaluation:

```bash
make setup-scenario SCENARIO=blocked_deployment PREVIEW=1
make setup-scenario SCENARIO=blocked_deployment
# Investigate the fault, then remove it:
make cleanup-scenario SCENARIO=blocked_deployment
```

Both targets require `SCENARIO`, `TAG`, or both. Use commas to select several
scenarios. Setup leaves faults running; cleanup removes scenario resources
and shared group resources where present.

## Results

Logs and generated reports are saved under `evals/results/` (ignored by Git).
Copy reports worth keeping to `evals/reports/` to track them in Git.
See [report generation](evals/README.md#reports) for commands and scoring rules.

Run `make help` for all targets and options.
