# Adding a Scenario

Scenarios live under `evals/scenarios/`. Each scenario is a self-contained directory that deploys a fault on a live OpenShift cluster.

## Naming conventions

Directory names use underscores (`_`), not hyphens. Names should describe the observable symptom in `adjective_noun` form (e.g., `pending_pvc`, `crashlooping_pod`, `failing_api`). Name what an operator would see, not the underlying root cause.

Alert-triggered scenarios use an `_alert` suffix; remediation variants use `_alert_remediation`.

## Scenario directory structure

```
my_scenario/
  setup.sh                     Deploys fixtures to the cluster
  cleanup.sh                   Removes everything the scenario created
  fixtures/
    manifest.yaml              Kubernetes manifests (Deployments, Services, etc.)
    prometheusrule.yaml        PrometheusRules for alert-based scenarios
  evals-ols-agentic.yaml       Eval definitions for OLS Agentic
  evals-ols-classic.yaml       Eval definitions for OLS Classic (optional)
```

### setup.sh

Creates the namespace and deploys all resources. Must be idempotent and executable (`chmod +x`). Typically applies fixtures with `oc apply -f fixtures/` and waits for the fault to manifest (e.g., pod enters CrashLoopBackOff, alert fires).

### cleanup.sh

Deletes the namespace and any cluster-scoped resources the scenario created. Must be executable and tolerate resources that don't exist (use `--ignore-not-found`).

### fixtures/

Kubernetes manifests that reproduce the fault. Use business-domain names (e.g., `warehouse-ops`, `payments`, `report-generator`), not names that encode the diagnosis or test intent.

### evals-ols-agentic.yaml

Eval definitions for OLS Agentic. Each entry defines:

- `conversation_group_id`: must match the scenario directory name
- `description`: symptom, `RCA:` (root cause), `Expected:` (what the agent should do)
- `tag`: list of tags (e.g., `agentic`, `alert`, `difficulty_normal`)
- `turns`: the AgenticRun spec, expected status, and scoring metrics

### evals-ols-classic.yaml

Eval definitions for OLS Classic. Same structure but with `query`/`expected_response` instead of AgenticRun specs. Only add this file if the scenario is meaningful as a text Q&A.

## Registering the scenario

After creating the scenario directory:

1. Add the scenario name to the appropriate variable (`_ALL_OLS_AGENTIC` and/or `_ALL_OLS_CLASSIC`) in `evals/Makefile`
2. Add a row to the scenario table in `evals/README.md`
3. Run the `review-scenario` skill (`.agents/skills/review-scenario.md`, symlinked from `.claude/skills/`) to check for naming leaks, revealing comments, and unrealistic fault setups. In Claude Code: `/review-scenario my_scenario`

## Lint

Run all linters from the repository root:

```bash
make lint
```

This installs the pinned lint tools into `.tools/` when needed. To install them without running lint, use `make tools`.
