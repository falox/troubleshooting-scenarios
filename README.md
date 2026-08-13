# Troubleshooting Scenarios

Evaluation suites for AI-assisted troubleshooting with [OpenShift Lightspeed](https://github.com/openshift/lightspeed-service) (OLS). 

See [CONTRIBUTING.md](CONTRIBUTING.md) to add a new eval suite.

## Eval suites

| Suite | Description |
|-------|-------------|
| [kiali-ossm/](kiali-ossm/) | Service-mesh troubleshooting using Kiali/OSSM MCP tools |
| [netobserv/](netobserv/) | Network observability using the NetObserv MCP toolset |
| [kubevirt/](kubevirt/) | OpenShift Virtualization troubleshooting using the KubeVirt MCP toolset |
| [agentic/](agentic/) |  Troubleshooting scenarios and benchmarks for [lightspeed-agentic-operator](https://github.com/openshift/lightspeed-agentic-operator) (see [agentic/README.md](agentic/README.md)) |
| [generic/](generic/) | Standalone fault-injection scenarios, e.g. for Incident Detection demos and Korrel8r testing |

## Requirements

- OpenShift 4.x cluster accessible via `oc login`
- `OPENAI_API_KEY` exported (required for the judge LLM; also configures an OpenAI OLS provider)
- Python 3.11, 3.12, or 3.13
- **Optional** (for Google/Anthropic providers via Vertex AI):
  - `GCP_SERVICE_ACCOUNT_JSON` — path to a GCP credentials JSON file (ADC or service account key)
  - `GCP_PROJECT_ID` — GCP project with Vertex AI access

## Quick start

```bash
export OPENAI_API_KEY=<your-key>

cd kiali-ossm          # or: cd netobserv, cd kubevirt
make setup             # install venv + OLS + MCP server + suite dependencies
make evals             # run all scenarios (default provider)
make cleanup          # remove suite dependencies + MCP server
```

Run a single scenario:

```bash
make check_mesh_status-eval
```

### Choosing an LLM provider

By default, evals use the provider and model from `system.yaml` (OpenAI). Override with Make variables:

```bash
# Run with a specific provider
make evals OLS_PROVIDER=google OLS_MODEL=gemini-2.5-pro
make evals OLS_PROVIDER=anthropic OLS_MODEL=claude-opus-4-6

# Run a single scenario with a specific provider
make vm_storage_failure-eval OLS_PROVIDER=google OLS_MODEL=gemini-2.5-pro

# Run all scenarios across every configured provider (results in results/<provider>/)
make evals-all-providers
```

To use Google or Anthropic providers, export the GCP credentials before `make setup`:

```bash
export GCP_SERVICE_ACCOUNT_JSON=~/.config/gcloud/application_default_credentials.json
export GCP_PROJECT_ID=<your-gcp-project>
make setup
```

### What `make setup` does

1. Creates a Python venv with `lightspeed-eval` (skips if exists)
2. Checks cluster access and OLS readiness
3. Installs the OLS operator if not present (idempotent)
4. Deploys the MCP server with the suite's toolsets
5. Connects OLS to the MCP server
6. Installs suite-specific dependencies (e.g., Bookinfo, FlowCollector)

### What `make cleanup` does

1. Removes suite-specific cluster resources
2. Disconnects OLS from the MCP server
3. Removes the MCP server namespace

## Uninstalling OLS

Suite cleanup does not remove OLS, since it's shared across suites. To remove the OLS operator and the local venv entirely, run from the repo root:

```bash
make cleanup
```

## Using a cluster Route instead of port-forward

By default, `make evals` auto-starts a port-forward to OLS on `localhost:8443`. To use the cluster Route instead:

```bash
OLS_URL=https://<ols-route-host> make evals
```

