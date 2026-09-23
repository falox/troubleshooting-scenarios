#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --system-config FILE --scenarios SCENARIO... [--tags TAG...]"
  exit 1
}

SYSTEM_CONFIG=""
SCENARIOS=()
TAGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --system-config) SYSTEM_CONFIG="$2"; shift 2 ;;
    --scenarios)     shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do SCENARIOS+=("$1"); shift; done ;;
    --tags)          shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do TAGS+=("$1"); shift; done ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[ -n "$SYSTEM_CONFIG" ] && [ ${#SCENARIOS[@]} -gt 0 ] || usage

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/../venv"
PYTHON="${VENV_DIR}/bin/python3"

for scenario in "${SCENARIOS[@]}"; do
  if [ ! -f "$scenario/evals-ols-classic.yaml" ]; then
    echo "ERROR: $scenario/evals-ols-classic.yaml not found" >&2
    exit 1
  fi
done

bash "$SCRIPT_DIR/preflight.sh" --require-ols

DATETIME="$(date +%Y%m%d_%H%M%S)"
EVAL_DIR="results/${DATETIME}"

TAG_FLAGS=()
if [ ${#TAGS[@]} -gt 0 ]; then
  TAG_FLAGS=(--tags "${TAGS[@]}")
fi

pf_pid=""
eval_sa="ols-classic-eval"
eval_sa_created=0
eval_role_bound=0

cleanup_ols_classic() {
  if [ -n "$pf_pid" ]; then kill "$pf_pid" 2>/dev/null || true; fi
  if [ "$eval_role_bound" -eq 1 ]; then
    oc adm policy remove-cluster-role-from-user cluster-reader -z "$eval_sa" -n openshift-lightspeed >/dev/null 2>&1 || true
  fi
  if [ "$eval_sa_created" -eq 1 ]; then
    oc delete serviceaccount "$eval_sa" -n openshift-lightspeed --ignore-not-found >/dev/null 2>&1 || true
  fi
}
trap cleanup_ols_classic EXIT

if ! curl -ksf --connect-timeout 2 "https://localhost:8443/docs" >/dev/null 2>&1; then
  echo "==> Starting port-forward to OLS..."
  oc port-forward -n openshift-lightspeed deployment/lightspeed-app-server 8443:8443 >/dev/null 2>&1 &
  pf_pid=$!
  ols_ok=false
  for _ in $(seq 1 30); do
    if curl -ksf --connect-timeout 2 "https://localhost:8443/docs" >/dev/null 2>&1; then ols_ok=true; break; fi
    sleep 2
  done
  if [ "$ols_ok" != "true" ]; then
    echo "ERROR: OLS not reachable at https://localhost:8443 after port-forward attempt" >&2
    exit 1
  fi
fi

auth_token=$(oc whoami -t 2>/dev/null || true)
if [ -z "$auth_token" ]; then
  echo "==> No OAuth token, creating service account token..."
  if ! oc get serviceaccount "$eval_sa" -n openshift-lightspeed >/dev/null 2>&1; then
    oc create serviceaccount "$eval_sa" -n openshift-lightspeed >/dev/null
    eval_sa_created=1
  fi
  if ! oc get clusterrolebinding -o jsonpath='{range .items[*]}{.roleRef.name}{"|"}{range .subjects[*]}{.kind}:{.namespace}:{.name}{" "}{end}{"\n"}{end}' 2>/dev/null \
      | grep -q "^cluster-reader|.*ServiceAccount:openshift-lightspeed:${eval_sa}"; then
    oc adm policy add-cluster-role-to-user cluster-reader -z "$eval_sa" -n openshift-lightspeed >/dev/null
    eval_role_bound=1
  fi
  auth_token=$(oc create token "$eval_sa" -n openshift-lightspeed --duration=1h)
fi

export API_KEY="$auth_token"

echo "scenarios:  ${#SCENARIOS[@]}"
for scenario in "${SCENARIOS[@]}"; do
  echo "  $scenario"
done

group_setup_script() {
  local scenario="$1"
  local group_dir
  group_dir="$(dirname "$scenario")"
  if [[ "$scenario" == */* ]] && [ -x "$group_dir/setup.sh" ]; then
    echo "$group_dir/setup.sh"
  fi
}

group_cleanup_script() {
  local scenario="$1"
  local group_dir
  group_dir="$(dirname "$scenario")"
  if [[ "$scenario" == */* ]] && [ -x "$group_dir/cleanup.sh" ]; then
    echo "$group_dir/cleanup.sh"
  fi
}

restart_port_forward() {
  if [ -n "$pf_pid" ]; then
    kill "$pf_pid" 2>/dev/null || true
    wait "$pf_pid" 2>/dev/null || true
    echo "==> Restarting port-forward after group setup..."
    oc port-forward -n openshift-lightspeed deployment/lightspeed-app-server 8443:8443 >/dev/null 2>&1 &
    pf_pid=$!
  fi
  echo "==> Waiting for OLS to be ready..."
  local ols_ok=false
  for _ in $(seq 1 30); do
    if curl -ksf --connect-timeout 2 "https://localhost:8443/docs" >/dev/null 2>&1; then ols_ok=true; break; fi
    sleep 2
  done
  if [ "$ols_ok" != "true" ]; then
    echo "ERROR: OLS not reachable after group setup" >&2
    return 1
  fi
}

overall_status=0
groups_setup=()

for scenario in "${SCENARIOS[@]}"; do
  grp_setup="$(group_setup_script "$scenario")"
  if [ -n "$grp_setup" ]; then
    already_done=false
    for g in "${groups_setup[@]+"${groups_setup[@]}"}"; do
      if [ "$g" = "$grp_setup" ]; then already_done=true; break; fi
    done
    if [ "$already_done" = "false" ]; then
      echo ""
      echo "==> Group setup: $grp_setup"
      if ! bash "$grp_setup"; then
        overall_status=$?
        break
      fi
      groups_setup+=("$grp_setup")
      if ! restart_port_forward; then
        overall_status=1
        break
      fi
    fi
  fi

  echo ""
  echo "==> Setup: $scenario"
  scenario_status=0
  if [ -x "$scenario/setup.sh" ]; then bash "$scenario/setup.sh" || scenario_status=$?; fi
  if [ "$scenario_status" -eq 0 ]; then
    bash "$SCRIPT_DIR/run-agentic-evals.sh" \
      --system-config "$SYSTEM_CONFIG" \
      --evals "$scenario/evals-ols-classic.yaml" \
      --eval-dir "$EVAL_DIR" \
      "${TAG_FLAGS[@]}" || scenario_status=$?
  fi
  echo "==> Cleanup: $scenario"
  if [ -x "$scenario/cleanup.sh" ]; then bash "$scenario/cleanup.sh" || echo "WARNING: cleanup failed (non-fatal)"; fi
  if [ "$scenario_status" -ne 0 ]; then overall_status=$scenario_status; break; fi
done

groups_cleanup=()
for scenario in "${SCENARIOS[@]}"; do
  grp_cleanup="$(group_cleanup_script "$scenario")"
  if [ -n "$grp_cleanup" ]; then
    already_done=false
    for g in "${groups_cleanup[@]+"${groups_cleanup[@]}"}"; do
      if [ "$g" = "$grp_cleanup" ]; then already_done=true; break; fi
    done
    if [ "$already_done" = "false" ]; then
      echo "==> Group cleanup: $grp_cleanup"
      bash "$grp_cleanup" || echo "WARNING: group cleanup failed (non-fatal)"
      groups_cleanup+=("$grp_cleanup")
    fi
  fi
done

if [ -n "$(find "$EVAL_DIR" -name '*_summary.json' -print -quit 2>/dev/null)" ]; then
  echo ""
  echo "==> Generating report..."
  report_status=0
  "$PYTHON" "$SCRIPT_DIR/generate-report-classic.py" \
    "$EVAL_DIR" \
    --output "results/report_${DATETIME}.md" || report_status=$?
  if [ "$report_status" -eq 0 ]; then
    echo "==> Report: results/report_${DATETIME}.md"
  elif [ "$overall_status" -eq 0 ]; then
    overall_status=$report_status
  fi
fi

if [ "$overall_status" -ne 0 ]; then exit "$overall_status"; fi
