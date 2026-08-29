#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")/../../scripts" && pwd)"
NS="analytics-dashboard"

"$SCRIPT_DIR/enable-uwm.sh"
oc apply -f "$FIXTURE_DIR/manifest.yaml"
oc apply -f "$FIXTURE_DIR/prometheusrule.yaml"

echo "Waiting for ReplicaSet FailedCreate event..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 60 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  MESSAGES=$(oc get events -n "$NS" \
    --field-selector "reason=FailedCreate" \
    -o jsonpath='{.items[*].message}' 2>/dev/null || true)
  if echo "$MESSAGES" | grep -qi "minimum memory usage"; then
    echo "Setup complete: LimitRange violation detected (attempt $ATTEMPT)"
    break
  fi
  sleep 2
done

"$SCRIPT_DIR/wait-for-alert.sh" "AnalyticsDashboardDeploymentUnavailable" "" 600
