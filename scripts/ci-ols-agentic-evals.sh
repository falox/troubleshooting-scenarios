#!/bin/bash
# CI job: install lightspeed-agentic-operator, configure LLM providers,
# and run agentic troubleshooting evaluations.
#
# Input environment variables:
#   OPENAI_API_KEY                  - OpenAI API key (judge LLM + OpenAI agent)
#   GOOGLE_APPLICATION_CREDENTIALS  - Path to GCP service account JSON (Vertex AI)
#   VERTEX_PROJECT_ID               - GCP project ID (falls back to credentials JSON)
#   VERTEX_REGION                   - GCP region (default: us-east1)
#   AGENT                           - Agent model to use: gpt-5.4, gemini-2.5-pro, claude-opus-4-6
#   SCENARIOS                       - Space-separated scenario list (default: all)
#   ARTIFACT_DIR                    - CI artifact directory (default: /tmp/artifacts)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTIC_DIR="${REPO_DIR}/agentic"
ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/artifacts}"
NAMESPACE="openshift-lightspeed"

function install_operator() {
    echo "==> Installing lightspeed-agentic-operator..."
    local tmpdir
    tmpdir="$(mktemp -d)"
    git clone --depth 1 https://github.com/openshift/lightspeed-agentic-operator.git "$tmpdir"
    bash "$tmpdir/hack/quickstart/install.sh"
    rm -rf "$tmpdir"
    echo "==> Operator installed."
}

function setup_openai_secret() {
    echo "==> Setting up OpenAI secret for judge LLM..."
    : "${OPENAI_API_KEY:?OPENAI_API_KEY must be set}"

    oc create secret generic llm-creds-openai -n "$NAMESPACE" \
        --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
        --dry-run=client -o yaml | oc apply -f -

    echo "    OpenAI secret configured."
}

function setup_openai_agent() {
    local AGENT_MODEL="$1"
    echo "==> Setting up OpenAI agent with model: ${AGENT_MODEL}..."

    oc apply -f - <<EOF
apiVersion: agentic.openshift.io/v1alpha1
kind: LLMProvider
metadata:
  name: openai
  namespace: openshift-lightspeed
spec:
  type: OpenAI
  openAI:
    credentialsSecret:
      name: llm-creds-openai
---
apiVersion: agentic.openshift.io/v1alpha1
kind: Agent
metadata:
  name: default
  namespace: openshift-lightspeed
spec:
  llmProvider:
    name: openai
  model: "${AGENT_MODEL}"
  timeouts:
    analysisSeconds: 600
    executionSeconds: 600
    verificationSeconds: 600
EOF
    echo "    OpenAI agent configured with model: ${AGENT_MODEL}"
}

function setup_vertex() {
    local AGENT_MODEL="$1"
    echo "==> Setting up Vertex AI provider for ${AGENT_MODEL}..."
    : "${GOOGLE_APPLICATION_CREDENTIALS:?GOOGLE_APPLICATION_CREDENTIALS must be set}"

    if [[ ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
        echo "ERROR: GCP credentials file not found at $GOOGLE_APPLICATION_CREDENTIALS" >&2
        exit 1
    fi

    if [[ -z "${VERTEX_PROJECT_ID:-}" ]]; then
        VERTEX_PROJECT_ID=$(python3 -c "import json; print(json.load(open('$GOOGLE_APPLICATION_CREDENTIALS'))['project_id'])")
        echo "    Extracted project ID from credentials: $VERTEX_PROJECT_ID"
    fi

    oc create secret generic llm-creds-vertex -n "$NAMESPACE" \
        --from-file=GOOGLE_APPLICATION_CREDENTIALS="$GOOGLE_APPLICATION_CREDENTIALS" \
        --dry-run=client -o yaml | oc apply -f -

    # Determine provider type and agent name based on model
    case "$AGENT_MODEL" in
        claude-opus-4-6)
            VERTEX_REGION="${VERTEX_REGION:-us-east1}"
            PROVIDER_NAME="vertex-anthropic"
            MODEL_PROVIDER="Anthropic"
            AGENT_NAME="opus"
            ;;
        gemini-2.5-pro)
            VERTEX_REGION="global"
            PROVIDER_NAME="vertex-google"
            MODEL_PROVIDER="Google"
            AGENT_NAME="gemini"
            ;;
        *)
            echo "ERROR: Unknown Vertex model: ${AGENT_MODEL}"
            exit 1
            ;;
    esac

    oc apply -f - <<EOF
apiVersion: agentic.openshift.io/v1alpha1
kind: LLMProvider
metadata:
  name: ${PROVIDER_NAME}
  namespace: $NAMESPACE
spec:
  type: GoogleCloudVertex
  googleCloudVertex:
    projectID: $VERTEX_PROJECT_ID
    region: $VERTEX_REGION
    modelProvider: ${MODEL_PROVIDER}
    credentialsSecret:
      name: llm-creds-vertex
---
apiVersion: agentic.openshift.io/v1alpha1
kind: Agent
metadata:
  name: ${AGENT_NAME}
  namespace: $NAMESPACE
spec:
  llmProvider:
    name: ${PROVIDER_NAME}
  model: "${AGENT_MODEL}"
  timeouts:
    analysisSeconds: 300
    executionSeconds: 300
    verificationSeconds: 300
EOF
    echo "    Vertex AI provider configured: ${MODEL_PROVIDER} with model ${AGENT_MODEL}"
}

function run_evals() {
    echo "==> Running agentic evaluations for agent: ${AGENT}"
    cd "$AGENTIC_DIR"

    # Run setup (system-ols-agentic.yaml used as-is)
    make setup-ols-agentic

    # Run evals with AGENT variable
    local MAKE_ARGS="AGENT=${AGENT}"
    if [[ -n "${SCENARIOS:-}" ]]; then
        # Convert space-separated SCENARIOS to comma-separated SCENARIO for Makefile
        local SCENARIO_LIST="${SCENARIOS// /,}"
        MAKE_ARGS+=" SCENARIO=${SCENARIO_LIST}"
    fi

    make eval-ols-agentic $MAKE_ARGS
}

function collect_results() {
    echo "==> Collecting results to ${ARTIFACT_DIR}..."
    mkdir -p "$ARTIFACT_DIR/agentic-${AGENT}"
    cp -r "$AGENTIC_DIR/results/"* "$ARTIFACT_DIR/agentic-${AGENT}/" 2>/dev/null || true
}

function cleanup() {
    echo "==> Cleaning up..."
    cd "$AGENTIC_DIR"
    make cleanup-ols-agentic || true
}

trap cleanup EXIT

# Default to gpt-5.4 if not specified
AGENT="${AGENT:-gpt-5.4}"

echo "==> Running agentic evaluations for agent: ${AGENT}"

install_operator

echo "==> Configuring LLM providers..."
case "$AGENT" in
    gpt-5.4)
        # OpenAI agent - needs secret for both agent and judge
        setup_openai_secret
        setup_openai_agent "$AGENT"
        ;;
    gemini-2.5-pro)
        # Google Gemini agent - needs Vertex for agent, OpenAI secret for judge
        setup_openai_secret  # For judge LLM only (no Agent CR needed)
        setup_vertex "$AGENT"
        ;;
    claude-opus-4-6)
        # Anthropic Opus agent - needs Vertex for agent, OpenAI secret for judge
        setup_openai_secret  # For judge LLM only (no Agent CR needed)
        setup_vertex "$AGENT"
        ;;
    *)
        echo "ERROR: Unknown AGENT=${AGENT}. Valid values: gpt-5.4, gemini-2.5-pro, claude-opus-4-6"
        exit 1
        ;;
esac

run_evals
collect_results

echo "==> Agentic evaluation complete for agent: ${AGENT}"
