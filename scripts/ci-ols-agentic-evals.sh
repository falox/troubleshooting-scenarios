#!/bin/bash
# CI job: install lightspeed-agentic-operator, configure LLM providers,
# and run agentic troubleshooting evaluations.
#
# Input environment variables:
#   EVAL_OPENAI_API_KEY             - OpenAI API key (judge LLM + OpenAI agent)
#   EVAL_VERTEX_CREDENTIALS         - Path to GCP service account JSON (Vertex AI)
#   EVAL_VERTEX_PROJECT_ID          - GCP project ID (Vertex region is always global)
#   AGENT                           - Agent key from system-ols-agentic.yaml
#                                     (default: openai-gpt-6-luna)
#   SCENARIOS                       - Space-separated scenario list (default: all)
#   ARTIFACT_DIR                    - CI artifact directory (default: /tmp/artifacts)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTIC_DIR="${REPO_DIR}/evals"
ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/artifacts}"

function install_operator() {
    echo "==> Installing lightspeed-agentic-operator..."
    local tmpdir
    tmpdir="$(mktemp -d)"
    git clone --depth 1 https://github.com/openshift/lightspeed-agentic-operator.git "$tmpdir"
    bash "$tmpdir/hack/quickstart/install.sh"
    rm -rf "$tmpdir"
    echo "==> Operator installed."
}

function run_evals() {
    echo "==> Running agentic evaluations for agent: ${AGENT}"
    cd "$REPO_DIR"

    # Configure providers and create Agent CRs from system-ols-agentic.yaml.
    make setup-ols-agentic

    # Run evals with AGENT variable
    local -a MAKE_ARGS=("AGENT=${AGENT}")
    if [[ -n "${SCENARIOS:-}" ]]; then
        # Convert space-separated SCENARIOS to comma-separated SCENARIO for Makefile
        local SCENARIO_LIST="${SCENARIOS// /,}"
        MAKE_ARGS+=("SCENARIO=${SCENARIO_LIST}")
    fi

    make eval-ols-agentic "${MAKE_ARGS[@]}"
}

function collect_results() {
    echo "==> Collecting results to ${ARTIFACT_DIR}..."
    mkdir -p "$ARTIFACT_DIR/agentic-${AGENT}"
    cp -r "$AGENTIC_DIR/results/"* "$ARTIFACT_DIR/agentic-${AGENT}/" 2>/dev/null || true
}

function cleanup() {
    echo "==> Cleaning up..."
    cd "$REPO_DIR"
    make cleanup-ols-agentic || true
}

# Use the same agent keys as system-ols-agentic.yaml.
AGENT="${AGENT:-openai-gpt-6-luna}"
case "$AGENT" in
    openai-gpt-6-luna|openai-gpt-5-6-terra|openai-gpt-6-sol) ;;
    google-gemini-3.5-flash-lite|google-gemini-3-8-flash|google-gemini-3-7-flash) ;;
    anthropic-opus-4-6|anthropic-sonnet-5) ;;
    *)
        echo "ERROR: Unknown AGENT=${AGENT}. Valid values: openai-gpt-6-luna, openai-gpt-5-6-terra, openai-gpt-6-sol, google-gemini-3.5-flash-lite, google-gemini-3-8-flash, google-gemini-3-7-flash, anthropic-opus-4-6, anthropic-sonnet-5" >&2
        exit 1
        ;;
esac

trap cleanup EXIT

echo "==> Running agentic evaluations for agent: ${AGENT}"

install_operator

run_evals
collect_results

echo "==> Agentic evaluation complete for agent: ${AGENT}"
