#!/usr/bin/env python3
"""Expand a single-entry evals.yaml into one entry per agent."""

import copy
import sys

import yaml


def expand(evals: list[dict], agents: list[dict]) -> list[dict]:
    result = []
    for entry in evals:
        for agent in agents:
            expanded = copy.deepcopy(entry)
            expanded["conversation_group_id"] += f"_{agent['label']}"
            for turn in expanded.get("turns", []):
                spec = turn.get("proposal_spec", {})
                analysis = spec.get("analysis", {})
                if "agent" in analysis:
                    analysis["agent"] = agent["id"]
            result.append(expanded)
    return result


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} EVALS_YAML AGENTS_YAML", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        evals = yaml.safe_load(f)
    with open(sys.argv[2]) as f:
        agents_config = yaml.safe_load(f)

    expanded = expand(evals, agents_config["agents"])
    yaml.dump(expanded, sys.stdout, default_flow_style=False, sort_keys=False)


if __name__ == "__main__":
    main()
