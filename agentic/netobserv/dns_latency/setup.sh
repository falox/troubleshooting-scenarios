#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_NS="name-resolution"
export TARGET_NS
export REQUIRED_NETOBSERV_FEATURES="DNSTracking"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/check_prereqs.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/wait_for.sh"

check_netobserv_prereqs
deploy_netobserv_fixture "${SCRIPT_DIR}/fixtures" "${TARGET_NS}"

wait_for_rollout "${TARGET_NS}" "resolver-checker" "180s"
echo "Waiting for DNS prober traffic (NetObserv export may take a few minutes)…"
wait_for_log_pattern "${TARGET_NS}" "app=resolver-checker" "kubernetes\\.default|Name:|Address" 30 3
wait_for_netobserv_warmup
echo "Scenario dns_latency ready (TARGET_NS=${TARGET_NS})"
