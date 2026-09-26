#!/usr/bin/env python3
"""Print the same evaluation summary for previews and real runs."""

import argparse
import sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required to show the evaluation summary.", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Show an evaluation summary")
    parser.add_argument("--system-config", required=True)
    parser.add_argument("--setup-mode", choices=("run", "scenario"), required=True)
    parser.add_argument("--agents", nargs="+")
    parser.add_argument("--scenarios", nargs="*", required=True)
    args = parser.parse_args()

    with open(args.system_config, encoding="utf-8") as config_file:
        config = yaml.safe_load(config_file) or {}

    agents_config = config.get("agents") or {}
    defaults = agents_config.get("default") or {}
    agent_names = args.agents if args.agents is not None else defaults.get("agent", [])
    repeat = defaults.get("repeat", 1)

    print(f"setup_mode: {args.setup_mode}")
    print(f"repeats:    {repeat}")
    print(f"agents:     {len(agent_names)}")
    for name in agent_names:
        agent = agents_config.get(name) or {}
        print(f"  {agent.get('description') or name}")

    print(f"scenarios:  {len(args.scenarios)}")
    for scenario in args.scenarios:
        print(f"  {scenario.removeprefix('scenarios/')}")
    if not args.scenarios:
        print("No scenarios match the given filters.")


if __name__ == "__main__":
    main()
