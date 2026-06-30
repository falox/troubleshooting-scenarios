#!/usr/bin/env bash
set -euo pipefail

KUBECTL=${KUBECTL:-oc}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURE_DIR="${SCRIPT_DIR}/fixtures"

echo "=== Enabling user workload monitoring ==="
${KUBECTL} apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOF

echo ""
echo "=== Cleaning up existing namespaces ==="
${KUBECTL} delete namespace shared-services --ignore-not-found --wait
${KUBECTL} delete namespace payments --ignore-not-found --wait

MANIFESTS=$(mktemp -d)
trap 'rm -rf $MANIFESTS' EXIT
cp -r "${FIXTURE_DIR}"/* "$MANIFESTS/"

# Both services use a single "dbuser" account (harder to diagnose)
sed -i 's/PGUSER: reporting/PGUSER: dbuser/' "$MANIFESTS/shared-services/01-secrets.yaml"
sed -i 's/PGPASSWORD: reporting123/PGPASSWORD: dbuser123/' "$MANIFESTS/shared-services/01-secrets.yaml"
sed -i 's/PGUSER: payments/PGUSER: dbuser/' "$MANIFESTS/payments/01-secrets.yaml"
sed -i 's/PGPASSWORD: payments123/PGPASSWORD: dbuser123/' "$MANIFESTS/payments/01-secrets.yaml"

# Replace two CREATE USER/GRANT blocks with a single dbuser
sed -i "/CREATE USER reporting/,/GRANT.*TO reporting;/c\\    CREATE USER dbuser WITH PASSWORD 'dbuser123';\n    GRANT SELECT ON ALL TABLES IN SCHEMA public TO dbuser;" \
  "$MANIFESTS/shared-services/02-postgres.yaml"
sed -i "/CREATE USER payments/,/GRANT.*TO payments;/d" \
  "$MANIFESTS/shared-services/02-postgres.yaml"

echo ""
echo "=== Deploying shared-services ==="
${KUBECTL} apply -f "$MANIFESTS/shared-services/"
${KUBECTL} -n shared-services wait --for=condition=available deployment/postgres --timeout=120s
${KUBECTL} -n shared-services wait --for=condition=available deployment/reporting-service --timeout=120s

echo ""
echo "=== Deploying payments ==="
${KUBECTL} apply -f "$MANIFESTS/payments/"
${KUBECTL} -n payments wait --for=condition=available deployment/payments-api --timeout=120s

echo ""
echo "=== Rolling out reporting-service v1.0.2 ==="
${KUBECTL} -n shared-services set image deployment/reporting-service reporting-service=quay.io/afalossi/ts01-reporting-service:v1.0.2
${KUBECTL} -n shared-services rollout status deployment/reporting-service --timeout=120s

ROUTE=$(${KUBECTL} -n payments get route payments-api -o jsonpath='{.spec.host}')
TOKEN=$(${KUBECTL} whoami -t)
THANOS_HOST=$(${KUBECTL} -n openshift-monitoring get route thanos-querier -o jsonpath='{.spec.host}')

echo ""
echo "Waiting for connection pool exhaustion (~3 minutes)..."
while true; do
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' "http://${ROUTE}/api/v1/process-payment" 2>/dev/null || echo "000")
  if [ "$STATUS" = "503" ]; then
    break
  fi
  sleep 5
done
echo "payments-api is returning 503."

echo "Waiting for PaymentErrorRateHigh critical alert to fire..."
while true; do
  ALERT_COUNT=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
    "https://${THANOS_HOST}/api/v1/alerts" 2>/dev/null |
    python3 -c "
import sys, json
data = json.load(sys.stdin)
print(sum(1 for a in data.get('data',{}).get('alerts',[])
          if a['labels'].get('alertname')=='PaymentErrorRateHigh'
          and a['labels'].get('severity')=='critical'
          and a['state']=='firing'))" 2>/dev/null || echo "0")
  if [ "$ALERT_COUNT" -gt 0 ] 2>/dev/null; then
    break
  fi
  sleep 10
done

echo "Setup complete. PaymentErrorRateHigh critical alert is firing."
