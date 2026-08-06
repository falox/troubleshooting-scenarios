#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="netpol-dns-test"
APP="netpol-dns-demo"

echo "Applying netpol_dns scenario manifests in namespace ${NS}…"
oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for deployment to be available (up to 120s)…"
oc rollout status deployment/"$APP" -n "$NS" --timeout=120s

echo "Waiting for DNS resolution failure logs (up to 60s)…"
ATTEMPT=0
until oc logs -l "app=$APP" -n "$NS" --tail=20 2>/dev/null | grep -q "DNS resolution failed"; do
  ATTEMPT=$((ATTEMPT + 1))
  if [ "$ATTEMPT" -ge 20 ]; then
    echo "ERROR: DNS failure logs not found after 60s"
    oc get pods -n "$NS"
    oc logs -l "app=$APP" -n "$NS" --tail=10 || true
    exit 1
  fi
  [ $((ATTEMPT % 5)) -eq 0 ] && echo "  attempt ${ATTEMPT}/20 — waiting…"
  sleep 3
done
echo "Scenario netpol_dns ready — DNS resolution failure logs confirmed (attempt ${ATTEMPT})"
