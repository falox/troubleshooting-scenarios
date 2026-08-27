#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc apply -f "$FIXTURE_DIR/deployment.yaml"
oc wait --for=condition=available deployment/newsletter-sender -n newsletter-sender --timeout=120s

oc scale deployment/newsletter-sender -n newsletter-sender --replicas=0
oc wait --for=jsonpath='{.spec.replicas}'=0 deployment/newsletter-sender -n newsletter-sender --timeout=30s

echo "Setup complete: newsletter-sender scaled to zero"
