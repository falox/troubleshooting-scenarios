#!/usr/bin/env python3
"""Sync Agent CRs on OpenShift from system.yaml agent configuration."""

import argparse
import subprocess
import sys

import yaml


def extract_agents(system_yaml_path: str) -> list[dict]:
    """Extract active agents from system.yaml.

    Returns a list of dicts with keys: name, provider, model, namespace.
    """
    with open(system_yaml_path) as f:
        config = yaml.safe_load(f)

    agents_config = config.get("agents", {})
    if not agents_config.get("enabled", False):
        return []

    active_names = agents_config.get("default", {}).get("agent", [])
    result = []

    for agent_name in active_names:
        agent = agents_config.get(agent_name, {})
        description = agent.get("description", "")
        parts = description.split("|", 1)
        if len(parts) != 2:
            print(
                f"WARNING: {agent_name}: description '{description}' "
                f"not in provider|model format, skipping",
                file=sys.stderr,
            )
            continue

        provider, model = parts
        result.append({
            "name": agent.get("agent_ref", ""),
            "provider": provider,
            "model": model,
            "namespace": agent.get("namespace", "openshift-lightspeed"),
        })

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


def main():
    parser = argparse.ArgumentParser(description="Sync Agent CRs from system.yaml")
    parser.add_argument("system_yaml", help="Path to system.yaml")
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print CRs without applying",
    )
    args = parser.parse_args()

    agents = extract_agents(args.system_yaml)
    if not agents:
        print("No agents to sync.")
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
