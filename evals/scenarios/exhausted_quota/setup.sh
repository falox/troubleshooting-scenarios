#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")/../../scripts" && pwd)"
NS="team-onboarding"

"$SCRIPT_DIR/enable-uwm.sh"
oc apply -f "$FIXTURE_DIR/manifest.yaml"
oc apply -f "$FIXTURE_DIR/prometheusrule.yaml"

echo "Waiting for setup-worker to consume the pod quota..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 120 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  READY=$(oc get deployment setup-worker -n "$NS" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [ "$READY" = "2" ]; then
    echo "setup-worker is fully available (attempt $ATTEMPT)"
    break
  fi
  sleep 1
done

if [ "$READY" != "2" ]; then
  echo "ERROR: setup-worker did not become available within 120s"
  oc get deployment setup-worker -n "$NS"
  exit 1
fi

echo "Confirming onboarding-app pod creation is rejected by the quota..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 60 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  EVENTS=$(oc get events -n "$NS" \
    --field-selector "reason=FailedCreate" \
    -o jsonpath='{.items[*].message}' 2>/dev/null || true)
  if echo "$EVENTS" | grep -q "exceeded quota"; then
    echo "Setup complete: quota exceeded event detected (attempt $ATTEMPT)"
    break
  fi
  sleep 1
done

"$SCRIPT_DIR/wait-for-alert.sh" "TeamOnboardingDeploymentUnavailable" "" 600
