#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_NS="service-network"
export TARGET_NS
export REQUIRED_NETOBSERV_FEATURES="NetworkEvents PacketDrop"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/check_prereqs.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/wait_for.sh"

check_netobserv_prereqs
deploy_netobserv_fixture "${SCRIPT_DIR}/fixtures" "${TARGET_NS}"

wait_for_rollout "${TARGET_NS}" "api-service" "180s"
wait_for_rollout "${TARGET_NS}" "web-client" "180s"
wait_for_min_log_matches "${TARGET_NS}" "app=web-client" "request failed" 5 60 5
wait_for_netobserv_warmup
echo "Scenario packet_drops_policy ready (TARGET_NS=${TARGET_NS})"
