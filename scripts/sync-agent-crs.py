#!/usr/bin/env python3
"""Sync Agent CRs on OpenShift from a system configuration YAML."""

import argparse
import subprocess
import sys

import yaml


class AgentConfigError(ValueError):
    """Raised when an active agent has an invalid system configuration."""

    def __init__(self, errors: list[str]):
        self.errors = errors
        super().__init__("; ".join(errors))


def extract_agents(system_yaml_path: str) -> list[dict]:
    """Extract active agents from a system configuration YAML.

    Returns a list of dicts with keys: name, provider, model, namespace.
    """
    with open(system_yaml_path) as f:
        config = yaml.safe_load(f)

    agents_config = config.get("agents", {})
    if not agents_config.get("enabled", False):
        return []

    active_names = agents_config.get("default", {}).get("agent", [])
    result = []
    errors = []

    for agent_name in active_names:
        agent = agents_config.get(agent_name) or {}
        description = agent.get("description", "")
        parts = description.split("|", 1)
        if len(parts) != 2 or not all(part.strip() for part in parts):
            errors.append(
                f"{agent_name}: description '{description}' "
                "not in provider|model format"
            )
            continue

        agent_ref = agent.get("agent_ref", "")
        if not agent_ref:
            errors.append(f"{agent_name}: agent_ref is required")
            continue

        provider, model = (part.strip() for part in parts)
        result.append({
            "name": agent_ref,
            "provider": provider,
            "model": model,
            "namespace": agent.get("namespace", "openshift-lightspeed"),
        })

    if errors:
        raise AgentConfigError(errors)

    return result


def generate_cr(agent: dict) -> dict:
    """Generate an Agent CR dict from agent info."""
    return {
        "apiVersion": "agentic.openshift.io/v1alpha1",
        "kind": "Agent",
        "metadata": {
            "name": agent["name"],
            "namespace": agent["namespace"],
        },
        "spec": {
            "llmProvider": {"name": agent["provider"]},
            "model": agent["model"],
        },
    }


def apply_cr(cr: dict) -> None:
    """Apply an Agent CR via oc apply."""
    cr_yaml = yaml.dump(cr, default_flow_style=False)
    subprocess.run(
        ["oc", "apply", "-f", "-"],
        input=cr_yaml,
        text=True,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def get_agent_crs() -> list[dict] | None:
    """Read all Agent CRs from the cluster."""
    try:
        result = subprocess.run(
            [
                "oc",
                "get",
                "agents.agentic.openshift.io",
                "--all-namespaces",
                "--output",
                "json",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        details = getattr(error, "stderr", "") or ""
        print("ERROR: Could not read Agent CRs from the cluster.", file=sys.stderr)
        if details.strip():
            print(details.strip(), file=sys.stderr)
        return None

    resources = yaml.safe_load(result.stdout) or {}
    return resources.get("items", [])


def check_agent_crs(agents: list[dict]) -> bool:
    """Check that configured Agent CRs exist and match the system config."""
    current_crs = get_agent_crs()
    if current_crs is None:
        print("Run 'make setup-ols-agentic' to synchronize the Agent CRs.", file=sys.stderr)
        return False

    current_by_name = {}
    for cr in current_crs:
        name = cr.get("metadata", {}).get("name")
        if name:
            current_by_name.setdefault(name, []).append(cr)
    mismatches = []

    for agent in agents:
        candidates = current_by_name.get(agent["name"], [])
        cr = next(
            (
                candidate
                for candidate in candidates
                if candidate.get("metadata", {}).get("namespace") == agent["namespace"]
            ),
            None,
        )
        if cr is None and len(candidates) == 1:
            candidate = candidates[0]
            candidate_namespace = candidate.get("metadata", {}).get("namespace")
            if not candidate_namespace:
                # Cluster-scoped Agent resources do not return a namespace.
                cr = candidate
            else:
                mismatches.append(
                    f"{agent['namespace']}/{agent['name']} exists in namespace "
                    f"'{candidate_namespace}'"
                )
        if cr is None:
            if not candidates:
                mismatches.append(f"missing {agent['namespace']}/{agent['name']}")
            continue

        spec = cr.get("spec", {})
        provider = spec.get("llmProvider", {}).get("name")
        if provider != agent["provider"]:
            mismatches.append(
                f"{agent['namespace']}/{agent['name']} has provider "
                f"'{provider}', expected '{agent['provider']}'"
            )
        if spec.get("model") != agent["model"]:
            mismatches.append(
                f"{agent['namespace']}/{agent['name']} has model "
                f"'{spec.get('model')}', expected '{agent['model']}'"
            )

    if mismatches:
        print(
            "ERROR: Agent CRs are not synchronized with "
            "system-ols-agentic.yaml.",
            file=sys.stderr,
        )
        for mismatch in mismatches:
            print(f"  - {mismatch}", file=sys.stderr)
        print("Run 'make setup-ols-agentic' to synchronize the Agent CRs.", file=sys.stderr)
        return False

    return True


def main():
    parser = argparse.ArgumentParser(description="Sync Agent CRs from system configuration")
    parser.add_argument("system_yaml", help="Path to system configuration YAML")
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print CRs without applying",
    )
    parser.add_argument(
        "--check", action="store_true",
        help="Check that Agent CRs match the system configuration",
    )
    args = parser.parse_args()

    try:
        agents = extract_agents(args.system_yaml)
    except AgentConfigError as error:
        print(
            f"ERROR: Invalid agent configuration in {args.system_yaml}.",
            file=sys.stderr,
        )
        for detail in error.errors:
            print(f"  - {detail}", file=sys.stderr)
        sys.exit(1)

    if not agents:
        if not args.check:
            print("No agents to sync.")
        return

    if args.check:
        if not check_agent_crs(agents):
            sys.exit(1)
        return

    if not args.dry_run:
        print(f"Syncing {len(agents)} Agent CR(s) to cluster...")

    for agent in agents:
        cr = generate_cr(agent)
        if args.dry_run:
            name = agent["name"]
            print(f"Agent CR: {name} (provider={agent['provider']}, model={agent['model']})")
            print(yaml.dump(cr, default_flow_style=False))
        else:
            apply_cr(cr)


if __name__ == "__main__":
    main()
