#!/usr/bin/env python3
"""Save the cluster configuration CRs at the start of an eval session."""

import argparse
import json
from pathlib import Path
import subprocess
import sys

import yaml

from report_progress import write_atomic


RESOURCES = {
    "OLSConfig": "olsconfigs.ols.openshift.io",
    "LLMProvider": "llmproviders.agentic.openshift.io",
    "Agent": "agents.agentic.openshift.io",
}


def capture(directory, agentic=False):
    """Save full CRs and continue if one resource type cannot be read."""
    directory.mkdir(parents=True, exist_ok=True)
    kinds = list(RESOURCES) if agentic else ["OLSConfig"]
    failed = False
    for kind in kinds:
        try:
            result = subprocess.run(
                ["oc", "get", RESOURCES[kind], "--all-namespaces", "-o", "json",
                 "--request-timeout=10s"],
                check=True, capture_output=True, text=True, timeout=30,
            )
            for resource in json.loads(result.stdout).get("items", []):
                metadata = resource["metadata"]
                name = metadata["name"]
                if metadata.get("namespace"):
                    name = f"{metadata['namespace']}__{name}"
                path = directory / f"{kind.lower()}-{name}.yaml"
                write_atomic(path, yaml.safe_dump(resource, sort_keys=False, allow_unicode=True))
                print(f"Saved {kind}: {path}", file=sys.stderr)
        except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
            failed = True
            detail = getattr(error, "stderr", None) or str(error)
            print(f"WARNING: Could not save {kind} CRs: {detail.strip()}", file=sys.stderr)
    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--agentic", action="store_true",
                        help="Also save LLMProvider and Agent CRs")
    args = parser.parse_args()
    return capture(args.directory, agentic=args.agentic)


if __name__ == "__main__":
    sys.exit(main())
