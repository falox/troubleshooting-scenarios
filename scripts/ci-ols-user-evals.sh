#!/bin/bash
# CI job: run OLS evaluation scenarios.
#
# Input environment variables:
#   EVAL_SUITES             - Space-separated suites to run (default: kiali-ossm kubevirt netobserv)
#   EVAL_OPENAI_API_KEY     - Required for judge LLM (always OpenAI)
#   EVAL_VERTEX_CREDENTIALS - Path to GCP service account JSON (for google/anthropic)
#   EVAL_VERTEX_PROJECT_ID  - GCP project ID (for google/anthropic)
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

: "${EVAL_OPENAI_API_KEY:?EVAL_OPENAI_API_KEY must be set (needed for judge LLM)}"

# Default to all three suites if not specified
SUITES="${EVAL_SUITES:-kiali-ossm kubevirt netobserv}"

if [ -n "${EVAL_VERTEX_CREDENTIALS:-}" ] || [ -n "${EVAL_VERTEX_PROJECT_ID:-}" ]; then
  if [ ! -f "${EVAL_VERTEX_CREDENTIALS:-}" ] || [ -z "${EVAL_VERTEX_PROJECT_ID:-}" ]; then
    echo "ERROR: Vertex requires EVAL_VERTEX_CREDENTIALS (existing file) and EVAL_VERTEX_PROJECT_ID" >&2
    exit 1
  fi
fi

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
  echo "Running eval: SUITE=${SUITE}"
  echo "=========================================="

  cd "$SUITE_DIR"

  echo "==> Running make setup..."
  if ! make setup; then
    echo "ERROR: make setup failed for ${SUITE}"
    echo "==> Running cleanup..."
    make cleanup || true
    return 1
  fi

  echo "==> Running evaluations..."
  # Run evals and capture exit status
  local EVAL_STATUS=0
  if ! make evals; then
    echo "ERROR: make evals failed for ${SUITE}"
    EVAL_STATUS=1
  fi

  # Collect artifacts (even if evals failed, there may be partial results)
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

  # Return the evaluation status
  if [ $EVAL_STATUS -ne 0 ]; then
    echo "==> OLS evaluation failed for ${SUITE}"
    return 1
  fi

  echo "==> OLS evaluation complete for ${SUITE}"
}

# Run each suite and track results
FAILED_SUITES=()
PASSED_SUITES=()

for SUITE in $SUITES; do
  if run_suite "$SUITE"; then
    PASSED_SUITES+=("$SUITE")
  else
    echo "ERROR: Evaluation failed for SUITE=${SUITE}"
    FAILED_SUITES+=("$SUITE")
  fi
done

echo ""
echo "=========================================="
echo "OLS Evaluation Summary"
echo "=========================================="
echo "Passed (${#PASSED_SUITES[@]}): ${PASSED_SUITES[*]:-none}"
echo "Failed (${#FAILED_SUITES[@]}): ${FAILED_SUITES[*]:-none}"
echo ""

if [ ${#FAILED_SUITES[@]} -gt 0 ]; then
  echo "ERROR: ${#FAILED_SUITES[@]} suite(s) failed"
  exit 1
fi

echo "==> All OLS evaluations complete."
