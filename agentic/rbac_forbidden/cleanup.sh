#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

NS="pod-inspector"

oc delete deployment inspector-app -n "$NS" --ignore-not-found
oc delete serviceaccount app-inspector-sa -n "$NS" --ignore-not-found

# Remove agent-created RBAC scoped to the scenario ServiceAccount.
# Namespaced Roles are all scenario-created, so delete them wholesale.
oc delete role --all -n "$NS" --ignore-not-found
for rb in $(oc get rolebindings -n "$NS" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .subjects[*]}{.name}{" "}{end}{"\n"}{end}' 2>/dev/null \
  | grep -w app-inspector-sa | cut -d'|' -f1); do
  oc delete rolebinding "$rb" -n "$NS" --ignore-not-found
done

# Clean up any cluster-scoped bindings the agent may have created
# (the anticipated wrong fix).
for crb in $(oc get clusterrolebindings \
  -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .subjects[*]}{.name}{":"}{.namespace}{" "}{end}{"\n"}{end}' 2>/dev/null \
  | grep -w "app-inspector-sa:$NS" | cut -d'|' -f1); do
  oc delete clusterrolebinding "$crb" --ignore-not-found
done

oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed pod-inspector namespace and resources"
