#!/usr/bin/env bash
set -euo pipefail

# The evaluator always uses OpenAI for the judge, even when OLS uses another provider.
if [ -z "${EVAL_OPENAI_API_KEY:-}" ]; then
  printf '\033[0;31mERROR:\033[0m EVAL_OPENAI_API_KEY not set (needed for judge LLM)\n'
  exit 1
fi

has_gcp=false

if [ -n "${EVAL_VERTEX_CREDENTIALS:-}" ] || [ -n "${EVAL_VERTEX_PROJECT_ID:-}" ]; then
  if [ ! -f "${EVAL_VERTEX_CREDENTIALS:-}" ]; then
    echo "ERROR: EVAL_VERTEX_CREDENTIALS must point to an existing file" >&2
    exit 1
  fi
  if [ -z "${EVAL_VERTEX_PROJECT_ID:-}" ]; then
    echo "ERROR: EVAL_VERTEX_PROJECT_ID must be set with EVAL_VERTEX_CREDENTIALS" >&2
    exit 1
  fi
  has_gcp=true
fi

NAMESPACE="openshift-lightspeed"

function setup_openai_secret() {
    echo "==> Setting up OpenAI secret for the agent..."
    : "${EVAL_OPENAI_API_KEY:?EVAL_OPENAI_API_KEY must be set}"

    oc create secret generic creds-agentic-openai -n "$NAMESPACE" \
        --from-literal=OPENAI_API_KEY="$EVAL_OPENAI_API_KEY" \
        --dry-run=client -o yaml | oc apply -f -

    echo "    OpenAI secret configured."
}

function setup_openai_provider() {
    echo "==> Setting up OpenAI provider..."

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
      name: creds-agentic-openai
EOF
    echo "    OpenAI provider configured."
}

function setup_vertex() {
    local PROVIDER_NAME="$1"
    local MODEL_PROVIDER
    echo "==> Setting up Vertex AI provider: ${PROVIDER_NAME}..."
    oc create secret generic creds-agentic-vertex -n "$NAMESPACE" \
        --from-file=GOOGLE_APPLICATION_CREDENTIALS="$EVAL_VERTEX_CREDENTIALS" \
        --dry-run=client -o yaml | oc apply -f -

    case "$PROVIDER_NAME" in
        vertex-anthropic)
            MODEL_PROVIDER="Anthropic"
            ;;
        vertex-google)
            MODEL_PROVIDER="Google"
            ;;
        *)
            echo "ERROR: Unknown Vertex provider: ${PROVIDER_NAME}"
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
    projectID: $EVAL_VERTEX_PROJECT_ID
    region: global
    modelProvider: ${MODEL_PROVIDER}
    credentialsSecret:
      name: creds-agentic-vertex
EOF
    echo "    Vertex AI provider configured: ${MODEL_PROVIDER}"
}

setup_openai_secret
setup_openai_provider
if $has_gcp; then
    setup_vertex vertex-google
    setup_vertex vertex-anthropic
fi
