#!/bin/bash
# CI job: run OLS evaluation scenarios for a specific LLM provider.
#
# Input environment variables:
#   EVAL_SUITES             - Space-separated suites to run (default: kiali-ossm kubevirt netobserv)
#   OPENAI_API_KEY          - Required for judge LLM (always OpenAI)
#   OLS_DEFAULT_PROVIDER    - LLM provider: openai, google, or anthropic (default: openai)
#   OLS_DEFAULT_MODEL       - Model override (optional, has defaults per provider)
#   GCP_SERVICE_ACCOUNT_JSON - Path to GCP service account JSON (for google/anthropic)
#   GCP_PROJECT_ID          - GCP project ID (auto-extracted from SA JSON if not set)
#
# Usage:
#   scripts/ci-ols-user-evals.sh --artifact-dir "${ARTIFACT_DIR}"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --artifact-dir) ARTIFACT_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ── Validate inputs ──────────────────────────────────────────────────

: "${OPENAI_API_KEY:?OPENAI_API_KEY must be set (needed for judge LLM)}"

# Default to all three suites if not specified
SUITES="${EVAL_SUITES:-kiali-ossm kubevirt netobserv}"

# Save the key for the judge LLM — we may need to hide it from setup-ols.sh
JUDGE_OPENAI_API_KEY="$OPENAI_API_KEY"

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

echo "==> Provider: ${PROVIDER}"
echo "==> Model: ${MODEL}"
echo "==> Suites: ${SUITES}"

# ── Run evaluations for each suite ───────────────────────────────────

run_suite() {
  local SUITE="$1"
  local SUITE_DIR="${REPO_ROOT}/${SUITE}"

  if [ ! -d "$SUITE_DIR" ]; then
    echo "ERROR: Suite directory not found: ${SUITE_DIR}"
    return 1
  fi

  if [ ! -f "${SUITE_DIR}/Makefile" ]; then
    echo "ERROR: No Makefile in suite directory: ${SUITE_DIR}"
    return 1
  fi

  echo ""
  echo "=========================================="
  echo "Running eval: SUITE=${SUITE}, PROVIDER=${PROVIDER}"
  echo "=========================================="

  cd "$SUITE_DIR"

  # For non-openai providers, hide OPENAI_API_KEY during setup so setup-ols.sh
  # only creates the GCP provider(s) in OLSConfig, avoiding multi-provider issues.
  local SAVED_OPENAI_KEY="$OPENAI_API_KEY"
  if [ "$PROVIDER" != "openai" ]; then
    echo "==> Unsetting OPENAI_API_KEY during setup (provider: ${PROVIDER})"
    unset OPENAI_API_KEY
  fi

  echo "==> Running make setup..."
  if ! make setup; then
    echo "ERROR: make setup failed for ${SUITE}"
    echo "==> Running cleanup..."
    make cleanup || true
    return 1
  fi

  # Restore OPENAI_API_KEY for the judge LLM
  export OPENAI_API_KEY="$SAVED_OPENAI_KEY"

  echo "==> Running evaluations..."
  local EVAL_ARGS="OLS_PROVIDER=${PROVIDER}"
  [ -n "$MODEL" ] && EVAL_ARGS+=" OLS_MODEL=${MODEL}"
  if ! make evals $EVAL_ARGS; then
    echo "ERROR: make evals failed for ${SUITE}"
    echo "==> Running cleanup..."
    make cleanup || true
    return 1
  fi

  # Collect artifacts
  if [ -n "$ARTIFACT_DIR" ] && [ -d "${SUITE_DIR}/results" ]; then
    echo "==> Copying results to ${ARTIFACT_DIR}/${SUITE}/..."
    mkdir -p "${ARTIFACT_DIR}/${SUITE}"
    cp -r "${SUITE_DIR}/results/"* "${ARTIFACT_DIR}/${SUITE}/" 2>/dev/null || true

    # Generate markdown summary if JSON results exist
    local SUMMARY_JSONS=()
    while IFS= read -r -d '' file; do
      SUMMARY_JSONS+=("$file")
    done < <(find "${SUITE_DIR}/results" -name '*_summary.json' -print0 2>/dev/null | sort -z)

    if [ ${#SUMMARY_JSONS[@]} -gt 0 ] && [ -f "${SUITE_DIR}/evals.yaml" ]; then
      echo "==> Generating markdown summary..."
      local VENV_PYTHON="${REPO_ROOT}/venv/bin/python"
      if [ -f "$VENV_PYTHON" ]; then
        "$VENV_PYTHON" "${REPO_ROOT}/scripts/summarize-agentic-evals.py" \
          "${SUITE_DIR}/results" \
          --output "${ARTIFACT_DIR}/${SUITE}/summary.md" \
          --run-type ols \
          "${SUITE_DIR}/evals.yaml" \
          "${SUMMARY_JSONS[@]}" || echo "Warning: Summary generation failed"
      else
        echo "Warning: venv not found, skipping markdown summary generation"
      fi
    fi
  fi

  # Cleanup
  echo "==> Running cleanup..."
  make cleanup || true

  echo "==> OLS evaluation complete for ${SUITE} / ${PROVIDER}"
}

# Run each suite
for SUITE in $SUITES; do
  run_suite "$SUITE" || {
    echo "ERROR: Evaluation failed for SUITE=${SUITE}, PROVIDER=${PROVIDER}"
    exit 1
  }
done

echo ""
echo "==> All OLS evaluations complete for provider: ${PROVIDER}"
