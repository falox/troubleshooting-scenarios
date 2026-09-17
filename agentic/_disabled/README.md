# Disabled scenarios

Scenarios parked here are excluded from evaluation runs. Reasons include:

- The fault setup is unrealistic: an LLM can infer the damage is caused by a
  synthetic demo application rather than a genuine production issue.
- The scenario does not apply given current technical limitations of
  Lightspeed Agentic.
- The scenario tests a capability (e.g. hygiene review, pre-flight analysis)
  that is not specific to troubleshooting.

These scenarios are candidates for revision and re-enablement in the future.


## Scenarios

| Scenario | Reason |
|----------|--------|
| `missing_alerts` | The agent lacks RBAC permissions to read PrometheusRule resources, so it cannot inspect the existing rules and proposes generic alert categories instead of concrete expressions (0/4 correctness). |
| `silent_alerts` | The agent lacks RBAC permissions to read PrometheusRule resources, so it cannot see the misspelled metric names and speculates about unrelated causes (0/4 correctness). |
| `noncompliant_workloads` | Tests workload hygiene review (probes, limits, pinned tags), not troubleshooting. Not specific to the troubleshooting evaluation. |
| `unsafe_rollout` | Tests pre-flight manifest review (dropped probes, unpinned image, removed securityContext), not troubleshooting. Not specific to the troubleshooting evaluation. |
