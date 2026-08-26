#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="rbac-forbidden"
DEPLOY="rbac-forbidden-demo"

oc apply -f "$FIXTURE_DIR/manifest.yaml"

# Wait for the deployment to become available
echo "Waiting for deployment $DEPLOY to become available…"
oc wait --for=condition=Available deployment/"$DEPLOY" \
  -n "$NS" --timeout=120s

# Wait for the app to log 403 responses
echo "Waiting for the app to log HTTP 403 responses…"
ATTEMPT=0
until [ "$ATTEMPT" -ge 60 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  POD=$(oc get pods -n "$NS" -l "app=$DEPLOY" -o name 2>/dev/null | head -1)
  if [ -n "$POD" ]; then
    LOGS=$(oc logs "$POD" -n "$NS" --tail=20 2>/dev/null || true)
    if echo "$LOGS" | grep -q "HTTP 403"; then
      echo "Setup complete: app is logging HTTP 403 errors (attempt $ATTEMPT)"
      exit 0
    fi
  fi
  sleep 2
done

echo "HTTP 403 log line not detected within 120s"
oc logs -n "$NS" -l "app=$DEPLOY" --tail=10 2>/dev/null || true
exit 1
