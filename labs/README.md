# Labs

Manual troubleshooting scenarios for a live OpenShift cluster. Each lab has
its own Makefile to control faults. Use them for demos, troubleshooting
practice, or testing an assistant against a deployed application.

## Available labs

| Lab | Description |
|-----|-------------|
| [payments-api-failure/](payments-api-failure/) | A connection leak fills the shared PostgreSQL pool and causes payment failures. Includes easy and hard modes. |
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
# Investigate the fault.
make fix
make cleanup
```

See each lab's own `README.md` for its specific commands, difficulty modes, and expected alerts.
