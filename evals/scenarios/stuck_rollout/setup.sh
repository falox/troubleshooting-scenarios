#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")/../../scripts" && pwd)"
NS="shipping-tracker"
APP="shipping-tracker"

"$SCRIPT_DIR/enable-uwm.sh"
oc apply -f "$FIXTURE_DIR/deployment.yaml"
oc apply -f "$FIXTURE_DIR/prometheusrule.yaml"

echo "Waiting for $APP to become available..."
oc wait --for=condition=Available "deployment/$APP" -n "$NS" --timeout=120s

echo "Rolling out a broken image to wedge the rollout..."
oc set image "deployment/$APP" \
  nginx=docker.io/nginxinc/nginx-unprivileged:9.99-broken -n "$NS"

echo "Waiting for the rollout to exceed its progress deadline..."
oc wait --for=condition=Progressing=false "deployment/$APP" \
  -n "$NS" --timeout=120s

echo "Setup complete: $APP rollout is stuck"

"$SCRIPT_DIR/wait-for-alert.sh" "ShippingTrackerRolloutStalled" "" 600
