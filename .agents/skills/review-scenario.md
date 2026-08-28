---
description: Review an agentic scenario for eval quality. Use when a scenario is added, modified, or the user says "review scenario".
allowed-tools: Read, Bash(grep *), Bash(find *), Bash(ls *), Bash(wc *)
---

# Review agentic scenario

Audit a single agentic scenario for **leakage**: anything that lets an LLM solve the problem without genuine cluster investigation.

Three leakage vectors, checked in order:

1. **Naming** - resource names that encode the diagnosis
2. **Disclosure** - YAML comments or inline values that hand over the answer
3. **Realism** - faults an LLM can diagnose from the manifest alone

The argument is a scenario directory name under `agentic/` (e.g. `bad_command`).

## 1. Inventory

Read every file in `agentic/$SCENARIO/`:
- `fixtures/*.yaml` (all files)
- `fixtures/*.py` (all files)
- `setup.sh`
- `cleanup.sh`
- `evals.yaml`

Collect every Kubernetes resource name, label value, and shell variable assignment (`NS=`, `APP=`, `DEPLOY=`).

## 2. Consistency check

Verify that every `conversation_group_id` in `evals.yaml` matches the scenario directory name, optionally with a `_alert` suffix (e.g. `blocked_deployment` and `blocked_deployment_alert` are both valid for directory `blocked_deployment`). Flag any other mismatch as a **FAIL**-level issue.

## 3. Naming check

For each name collected, answer: **does this name tell an LLM what the problem is before it runs a single cluster command?**

Flag names that:
- Describe the fault mechanism (`antiaffinity-demo`, `missing-pvc-test`, `default-deny-egress`)
- Describe the expected answer (`healthy-app`, `nothing-wrong`, `quota-victim`)
- Reveal the test intent (`trap-demo`, `herring-app`, `fragile-app`)
- Carry test-context markers: `-demo`, `-test`, `eval-` prefixes/suffixes
- Use temporal hints that encode the answer: `old-`, year stamps, `legacy-` (when the scenario tests orphan detection)
- Reveal the scenario is synthetic: container names like `log-emitter`, `fault-injector`; script filenames like `generate_logs.py`, `simulate_*.py`; Secret/ConfigMap names containing `log-script`, `logs-script`, or `fault`
- Include `eval/scenario` or similar annotations that label the test case

Neutral names are business-domain names that a real team would use: `payments`, `warehouse-ops`, `report-generator`, `media-processing`.

## 4. Comment and disclosure check

Search fixture YAML for `#` comment lines. Flag comments that:
- Explain the root cause or the fault
- State the expected error message or behavior
- Reveal the fix
- Give away structural information an LLM should discover (e.g. "6 workloads here, 9 there")

Check Python scripts in `fixtures/` for docstrings or comments that describe the fault, the simulation intent, or the expected diagnosis (e.g. `"""Simulate a gateway that reloads config"""`, `# Root cause: config drift`). The LLM can read these via `oc get configmap -o yaml` or `oc get secret -o yaml`.

Also check for inline values that disclose the answer without needing a comment:
- Image tags containing `does-not-exist`, `fake`, `broken`, `invalid`, or impossible version numbers
- `replicas: 0` directly in the YAML (vs. scaling to zero at runtime in setup.sh)
- PrometheusRule annotations (`summary`, `description`) that contain troubleshooting instructions (e.g. "Check resource limits", "Inspect application logs", "Verify storage class"). Annotations should state what is happening, not how to fix it.

## 5. Realism check

For each fault in the scenario, answer: **can an LLM diagnose this by reading `oc get <resource> -o yaml` without needing runtime signals (events, logs, pod status, describe, metrics)?**

Classify:

- **CRITICAL**: the YAML alone is the complete diagnosis. Hardcoded `exit 1`, explicit memory bombs (`data.append("x" * 1000000)`), arithmetic that screams (64Mi write into 10Mi limit with both numbers in the command).
- **MODERATE**: the YAML is a strong hint but cluster signals add information. Port mismatches, missing referenced resources, suspicious nodeSelectors. Note whether reading the YAML IS the realistic diagnostic path for this type of issue (it often is for selector mismatches, probe ports, RBAC bindings).
- **OK**: the fault requires runtime investigation. Log analysis, connection behavior, metrics comparison, runtime state changes.

## 6. Request text check

Read the `request:` field in `evals.yaml`. Flag if it:
- States the root cause outright
- Names the exact broken resource when the scenario has multiple candidates
- Uses terminology that narrows the search space to one possibility

The request should describe **symptoms** (alerts, user reports, observed behavior), not causes.

## 7. Report

Output a structured report:

```
## Scenario: <name>

### Consistency
[conversation_group_id vs directory name: match or mismatch]

### Naming
[list each problematic name -> what it hints at -> suggested fix]

### Disclosure
[quote each problematic comment or value -> suggested fix]

### Realism
[each fault -> CRITICAL/MODERATE/OK -> rationale]
[for MODERATE: note if reading YAML is the realistic diagnostic path]

### Request text
[issues found, or "clean"]

### Verdict: PASS | NEEDS WORK | FAIL
[one-line summary of what to fix, or "no issues found"]
```

Severity guide:
- **FAIL**: naming encodes the diagnosis, OR a CRITICAL realism issue makes the scenario solvable from YAML alone
- **NEEDS WORK**: MODERATE issues that weaken the eval but don't invalidate it
- **PASS**: no significant leakage; the scenario requires genuine cluster investigation
