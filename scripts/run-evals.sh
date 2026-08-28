#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --system-config FILE --evals FILE --results-dir DIR --ols-url URL [--provider NAME] [--model NAME] --tags TAG [TAG ...]"
  exit 1
}

SYSTEM_CONFIG=""
EVALS=""
RESULTS_DIR=""
OLS_URL=""
OLS_NS="${OLS_NS:-openshift-lightspeed}"
OLS_PROVIDER=""
OLS_MODEL=""
TAGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --system-config) SYSTEM_CONFIG="$2"; shift 2 ;;
    --evals)         EVALS="$2"; shift 2 ;;
    --results-dir)   RESULTS_DIR="$2"; shift 2 ;;
    --ols-url)       OLS_URL="$2"; shift 2 ;;
    --provider)      OLS_PROVIDER="$2"; shift 2 ;;
    --model)         OLS_MODEL="$2"; shift 2 ;;
    --tags)          shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do TAGS+=("$1"); shift; done ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[ -n "$SYSTEM_CONFIG" ] && [ -n "$EVALS" ] && [ -n "$RESULTS_DIR" ] && [ -n "$OLS_URL" ] && [ ${#TAGS[@]} -gt 0 ] || usage

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/../venv"

if [ ! -f "${VENV_DIR}/bin/lightspeed-eval" ]; then
  echo "ERROR: lightspeed-eval not found at ${VENV_DIR}/bin/lightspeed-eval"
  echo "Run setup first (make setup)"
  exit 1
fi

if [ -z "${OPENAI_API_KEY:-}" ]; then
  printf '\033[0;31mERROR:\033[0m OPENAI_API_KEY not set (needed for judge LLM)\n'
  exit 1
fi

# 1. Generate system-runtime.yaml with actual OLS_URL (and optional provider/model)
mkdir -p "$RESULTS_DIR"
RUNTIME_CONFIG="${RESULTS_DIR}/system-runtime.yaml"
SED_ARGS=(-e "s|^  api_base: .*|  api_base: ${OLS_URL}|")
if [ -n "$OLS_PROVIDER" ]; then
  SED_ARGS+=(-e "/^api:/,/^[a-z]/{s|^  provider: .*|  provider: \"${OLS_PROVIDER}\"|;}")
fi
if [ -n "$OLS_MODEL" ]; then
  SED_ARGS+=(-e "/^api:/,/^[a-z]/{s|^  model: .*|  model: \"${OLS_MODEL}\"|;}")
fi
sed "${SED_ARGS[@]}" "$SYSTEM_CONFIG" > "$RUNTIME_CONFIG"

# 2. Auto port-forward if OLS_URL is localhost and not reachable
PF_PID=""
cleanup_pf() {
  if [ -n "$PF_PID" ]; then
    kill "$PF_PID" 2>/dev/null || true
    wait "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup_pf EXIT

if [[ "$OLS_URL" == https://localhost:* ]]; then
  port="${OLS_URL##*:}"
  # Remove any trailing path
  port="${port%%/*}"
  if ! curl -ksf --connect-timeout 2 "${OLS_URL}/docs" >/dev/null 2>&1; then
    echo "==> Starting port-forward to OLS (${OLS_NS}, localhost:${port} -> 8443)..."
    oc port-forward -n "$OLS_NS" deployment/lightspeed-app-server "${port}:8443" >/dev/null 2>&1 &
    PF_PID=$!
    sleep 3
  fi
fi

# 3. Wait for OLS endpoint
echo "==> Waiting for OLS at ${OLS_URL}..."
ok=false
for i in $(seq 1 30); do
  case "$OLS_URL" in
    https://*) check_cmd="curl -ksf" ;;
    *)         check_cmd="curl -sf" ;;
  esac
  if $check_cmd --connect-timeout 3 "${OLS_URL}/docs" >/dev/null 2>&1; then
    ok=true
    break
  fi
  sleep 2
done

if [ "$ok" != "true" ]; then
  printf '\033[0;31mERROR:\033[0m OLS not reachable at %s after 60s\n' "$OLS_URL"
  exit 1
fi
echo "==> OLS OK at ${OLS_URL}"

# 4. Run lightspeed-eval
AUTH_TOKEN="$(oc whoami -t 2>/dev/null || true)"
if [ -z "$AUTH_TOKEN" ]; then
  echo "==> No OAuth token found, creating service account token..."
  oc adm policy add-cluster-role-to-user cluster-admin -z default -n "$OLS_NS" >/dev/null 2>&1 || true
  AUTH_TOKEN="$(oc create token default -n "$OLS_NS" --duration=1h)"
fi

echo ""
echo "==> Running eval: tags=${TAGS[*]}"
API_KEY="$AUTH_TOKEN" "${VENV_DIR}/bin/lightspeed-eval" \
  --system-config "$RUNTIME_CONFIG" \
  --output-dir "$RESULTS_DIR" \
  --eval-data "$EVALS" \
  --tags "${TAGS[@]}"

echo ""
echo "==> All evals complete. Results in ${RESULTS_DIR}/"
