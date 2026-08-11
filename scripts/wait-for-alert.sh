#!/usr/bin/env bash
set -euo pipefail

ALERT_NAME="${1:?Usage: wait-for-alert.sh <ALERT_NAME> [SEVERITY] [TIMEOUT]}"
SEVERITY="${2:-}"
TIMEOUT="${3:-300}"

TOKEN=$(oc whoami -t 2>/dev/null || oc create token prometheus-k8s -n openshift-monitoring --duration=10m)
THANOS_HOST=$(oc -n openshift-monitoring get route thanos-querier -o jsonpath='{.spec.host}')

echo "Waiting for alert $ALERT_NAME to be firing (timeout ${TIMEOUT}s)..."
ELAPSED=0
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  ALERT_COUNT=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
    "https://${THANOS_HOST}/api/v1/alerts" 2>/dev/null |
    python3 -c "
import sys, json
data = json.load(sys.stdin)
sev = '${SEVERITY}'
print(sum(1 for a in data.get('data',{}).get('alerts',[])
          if a['labels'].get('alertname')=='${ALERT_NAME}'
          and a['state']=='firing'
          and (not sev or a['labels'].get('severity')==sev)))" 2>/dev/null || echo "0")
  if [ "$ALERT_COUNT" -gt 0 ] 2>/dev/null; then
    echo "Alert $ALERT_NAME is firing."
    exit 0
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

echo "ERROR: Alert $ALERT_NAME did not fire within ${TIMEOUT}s"
exit 1
