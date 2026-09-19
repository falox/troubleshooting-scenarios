# Labs

Standalone, hand-driven troubleshooting scenarios for a live OpenShift cluster. Unlike the eval suites elsewhere in this repo, labs don't run through the `lightspeed-evaluation` framework — each one ships its own `Makefile` with `deploy`/`break`/`fix`/`cleanup` targets (and often more) so you can drive the fault lifecycle by hand. Use them for live demos, manual troubleshooting practice, or ad-hoc benchmarking of an AI assistant against a real cluster.

## Available labs

| Lab | Description |
|-----|-------------|
| [payments-api-failure/](payments-api-failure/) | A database connection leak in a service upgrade exhausts a shared PostgreSQL pool, taking down the payments API. The scenario is deliberately layered (two namespaces, a shared DB user, graduated alerts, a red herring in `deploy` mode) and is complex enough that current frontier models don't consistently troubleshoot it correctly. <br>**It's the most sophisticated lab here, useful for benchmarking and skill tuning.** |
| [alert-storm/](alert-storm/) | A broken ConfigMap on a central service cascades into failures across four downstream services, triggering a storm of alerts that obscures a simple root cause. |
| [image-pull-failure/](image-pull-failure/) | A typo in a container image reference puts all pods of a Deployment into `ImagePullBackOff`, violating a PodDisruptionBudget and firing the platform-level alert. |
| [control-plane-alerts/](control-plane-alerts/) | Two independent control-plane faults (a misconfigured Insights Operator upload endpoint and a disabled NTP daemon) each trigger their own alerts, with no application involved. |

## Usage

Each lab is self-contained; run its `Makefile` targets from within its own directory:

```bash
oc login ...                        # required

cd labs/payments-api-failure
make deploy-easy                    # or: make deploy
make break
```

See each lab's own `README.md` for its specific commands, difficulty modes, and expected alerts.
