# KubeVirt Troubleshooting Scenarios

Evaluation scenarios that test AI-assisted diagnosis of OpenShift Virtualization (KubeVirt) problems using the `kubevirt` MCP toolset and OpenShift Lightspeed.

## Prerequisites

- OpenShift 4.16+ cluster
- `oc` CLI authenticated with cluster-admin
- `OPENAI_API_KEY` exported (required for the judge LLM; also used as an OLS provider)
- Python 3.11, 3.12, or 3.13
- **Optional** (for Google/Anthropic providers): `GCP_SERVICE_ACCOUNT_JSON` + `GCP_PROJECT_ID` exported (see [Variables](#variables))

## KVM Requirements

OpenShift Virtualization requires KVM (Kernel-based Virtual Machine) to run VMs. On bare-metal clusters, KVM is natively available. On cloud environments like AWS, only metal instance types (e.g. `m5.metal`, `c5.metal`, `m6i.metal`) expose the `/dev/kvm` device needed for hardware virtualization.

When no KVM devices are detected on worker nodes, `make setup` automatically enables QEMU software emulation by setting `KVM_EMULATION=true` on the CNV operator Subscription. This allows all scenarios to run without hardware KVM, but VMs will be significantly slower. **Software emulation is not supported by Red Hat and should only be used in test/dev environments.**

Scenarios that require a running VM (`vm_crashloop`, `vm_migration_failure`) are skipped if neither KVM devices nor emulation are available. The `vm_storage_failure` scenario always runs since the VM never reaches the scheduling phase.

## Scenarios

| Scenario | VM | Fault | Signal |
|----------|-----|-------|--------|
| [vm_storage_failure](vm_storage_failure/) | `production-db-vm` | Non-existent StorageClass `premium-nvme-storage` | VM stuck in `Provisioning`, DV has no phase |
| [vm_crashloop](vm_crashloop/) | `web-server-vm` | cloud-init `runcmd: shutdown -h now` | VM repeatedly starts and stops (~35s cycle) |
| [vm_migration_failure](vm_migration_failure/) | `critical-app-vm` | `nodeSelector` pins VM to one node | Live migration fails (no valid target) |

All VMs use the modern instancetype-based format (matching the console "Custom configuration" default):
- `spec.instancetype.name: u1.small`
- `spec.preference.name: fedora`
- `containerDisk` for boot (crashloop and migration scenarios) to avoid storage quota issues

## Quick Start

```bash
export OPENAI_API_KEY=<your-key>

cd kubevirt
make setup    # install venv + OLS + MCP (with kubevirt toolset) + deploy broken VMs
make evals    # run all scenarios (default provider from system.yaml)
make cleanup  # remove broken VMs + CNV operator + MCP server
```

### Running with a specific LLM provider

Override the provider and model used for OLS queries (the judge LLM is unchanged):

```bash
make evals OLS_PROVIDER=google OLS_MODEL=gemini-2.5-pro
make evals OLS_PROVIDER=anthropic OLS_MODEL=claude-opus-4-6
```

Run a single scenario with a specific provider:

```bash
make vm_storage_failure-eval OLS_PROVIDER=google OLS_MODEL=gemini-2.5-pro
```

### Running across all providers

Automatically discovers all providers configured in the cluster's OLSConfig and runs evals for each, saving results to separate directories (`results/<provider>/`):

```bash
make evals-all-providers
```

### Running a single scenario

```bash
make vm_storage_failure-eval
make vm_crashloop-eval
make vm_migration_failure-eval
```

### What `make setup` does

1. Creates a Python venv with `lightspeed-eval` (skips if exists)
2. Checks cluster access and OLS readiness
3. Installs the OLS operator if not present (idempotent)
4. Deploys the MCP server with `core,config,kubevirt` toolsets
5. Connects OLS to the MCP server
6. Installs OpenShift Virtualization if not present (idempotent), enables software emulation if no KVM devices are available
7. Deploys all broken VM scenarios

### Manual scenario management

```bash
# Deploy only scenario VMs (without shared infra)
make setup-scenarios

# Clean only scenario VMs
make cleanup-scenarios
```

> **Note**: The migration failure scenario automatically triggers a `VirtualMachineInstanceMigration` during setup. No manual `virtctl migrate` step is needed.

## Troubleshooting Prompts

Sample questions to ask OpenShift Lightspeed (or any MCP-connected AI):

1. **Storage failure**: "Why is VM production-db-vm not starting in namespace kubevirt-scenarios?"
2. **Crashloop**: "VM web-server-vm keeps restarting. It starts but dies within seconds. Why?"
3. **Migration failure**: "I tried to migrate VM critical-app-vm but it failed. Why?"

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE` | `kubevirt-scenarios` | Namespace for scenario VMs |
| `NODE_NAME` | First worker node | Node to pin migration VM to |
| `KUBECTL` | `oc` | CLI tool (`oc` or `kubectl`) |
| `CNV_NS` | `openshift-cnv` | Namespace for CNV operator |
| `CNV_CHANNEL` | `stable` | OLM channel for CNV subscription |
| `CNV_SOURCE` | `redhat-operators` | CatalogSource name |
| `CNV_SOURCE_NS` | `openshift-marketplace` | CatalogSource namespace |
| `OLS_PROVIDER` | *(from system.yaml)* | Override OLS provider (e.g. `openai`, `google`, `anthropic`) |
| `OLS_MODEL` | *(from system.yaml)* | Override OLS model (e.g. `gemini-2.5-pro`, `claude-opus-4-6`) |
| `GCP_SERVICE_ACCOUNT_JSON` | | Path to GCP credentials JSON (ADC or service account key) |
| `GCP_PROJECT_ID` | | GCP project ID for Vertex AI |
| `GCP_LOCATION` | | Default Vertex AI location (overridden by per-provider vars) |
| `GCP_GOOGLE_LOCATION` | `global` | Vertex AI location for Google models |
| `GCP_ANTHROPIC_LOCATION` | `us-east5` | Vertex AI location for Anthropic models |
