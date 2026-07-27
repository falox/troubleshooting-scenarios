#!/bin/bash
# CI job: run OLS evaluation scenarios for a specific LLM provider and suite.
#
# Input environment variables:
#   EVAL_SUITE              - Suite to run: kiali-ossm, kubevirt, or netobserv
#   OPENAI_API_KEY          - Required for judge LLM (always OpenAI)
#   OLS_DEFAULT_PROVIDER    - LLM provider: openai, google, or anthropic (default: openai)
#   OLS_DEFAULT_MODEL       - Model override (optional, has defaults per provider)
#   GCP_SERVICE_ACCOUNT_JSON - Path to GCP service account JSON (for google/anthropic)
#   GCP_PROJECT_ID          - GCP project ID (auto-extracted from SA JSON if not set)
#
# Usage:
#   tests/scripts/test-ols-evals.sh --artifact-dir "${ARTIFACT_DIR}"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --artifact-dir) ARTIFACT_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ── Validate inputs ──────────────────────────────────────────────────

: "${EVAL_SUITE:?EVAL_SUITE must be set (kiali-ossm, kubevirt, or netobserv)}"
: "${OPENAI_API_KEY:?OPENAI_API_KEY must be set (needed for judge LLM)}"

# Save the key for the judge LLM — we may need to hide it from setup-ols.sh
JUDGE_OPENAI_API_KEY="$OPENAI_API_KEY"

SUITE_DIR="${REPO_ROOT}/${EVAL_SUITE}"
if [ ! -d "$SUITE_DIR" ]; then
  echo "ERROR: Suite directory not found: ${SUITE_DIR}"
  exit 1
fi

if [ ! -f "${SUITE_DIR}/Makefile" ]; then
  echo "ERROR: No Makefile in suite directory: ${SUITE_DIR}"
  exit 1
fi

# ── Auto-extract GCP project ID from SA JSON if needed ───────────────

if [ -n "${GCP_SERVICE_ACCOUNT_JSON:-}" ] && [ -f "${GCP_SERVICE_ACCOUNT_JSON}" ] && [ -z "${GCP_PROJECT_ID:-}" ]; then
  if command -v jq &>/dev/null; then
    GCP_PROJECT_ID="$(jq -r '.project_id // empty' "$GCP_SERVICE_ACCOUNT_JSON")"
  elif command -v python3 &>/dev/null; then
    GCP_PROJECT_ID="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('project_id',''))" "$GCP_SERVICE_ACCOUNT_JSON")"
  fi
  if [ -n "$GCP_PROJECT_ID" ]; then
    export GCP_PROJECT_ID
    echo "==> Auto-detected GCP_PROJECT_ID: ${GCP_PROJECT_ID}"
  fi
fi

# ── Determine provider and model for result tracking ─────────────────

PROVIDER="${OLS_DEFAULT_PROVIDER:-openai}"
if [ -z "${OLS_DEFAULT_MODEL:-}" ]; then
  case "$PROVIDER" in
    openai)    MODEL="gpt-5.4" ;;
    google)    MODEL="gemini-2.5-pro" ;;
    anthropic) MODEL="claude-opus-4-6" ;;
    *)         MODEL="" ;;
  esac
else
  MODEL="${OLS_DEFAULT_MODEL}"
fi

echo "==> Suite: ${EVAL_SUITE}"
echo "==> Provider: ${PROVIDER}"
echo "==> Model: ${MODEL}"

# ── Cleanup on exit ──────────────────────────────────────────────────

cleanup() {
  echo "==> Running cleanup..."
  cd "$SUITE_DIR"
  make cleanup || true
}
trap cleanup EXIT

# ── Setup and run evals ──────────────────────────────────────────────

cd "$SUITE_DIR"

# For non-openai providers, hide OPENAI_API_KEY during setup so setup-ols.sh
# only creates the GCP provider(s) in OLSConfig, avoiding multi-provider issues.
if [ "$PROVIDER" != "openai" ]; then
  echo "==> Unsetting OPENAI_API_KEY during setup (provider: ${PROVIDER})"
  unset OPENAI_API_KEY
fi

echo "==> Running make setup..."
make setup

# Restore OPENAI_API_KEY for the judge LLM
export OPENAI_API_KEY="$JUDGE_OPENAI_API_KEY"

echo "==> Running evaluations..."
EVAL_ARGS="OLS_PROVIDER=${PROVIDER}"
[ -n "$MODEL" ] && EVAL_ARGS+=" OLS_MODEL=${MODEL}"
make evals $EVAL_ARGS

# ── Collect artifacts ────────────────────────────────────────────────

if [ -n "$ARTIFACT_DIR" ] && [ -d "${SUITE_DIR}/results" ]; then
  echo "==> Copying results to ${ARTIFACT_DIR}..."
  mkdir -p "$ARTIFACT_DIR"
  cp -r "${SUITE_DIR}/results/"* "$ARTIFACT_DIR/" 2>/dev/null || true
fi

echo "==> OLS evaluation complete for ${EVAL_SUITE} / ${PROVIDER}"
