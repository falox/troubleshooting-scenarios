#!/usr/bin/env python3
"""Convert lightspeed-eval summary JSON files to JUnit XML for Sippy ingestion.

Aggregates results per scenario/agent pair across runs so that each test case
in Sippy represents a stable, trackable identity (e.g. cascading_failure.openai-gpt-6-luna)
rather than ephemeral per-run entries.

A test case passes only when every run passes all metrics for that scenario/agent.
Aggregate stats (pass rate, average score, duration, tokens) are embedded as
JUnit properties for downstream analysis.
"""

import json
import sys
from collections import defaultdict
from pathlib import Path
from xml.etree.ElementTree import Element, SubElement, tostring
from xml.dom.minidom import parseString


SUITE_NAME = "troubleshooting-scenarios"


def _aggregate_key(agent: str, scenario: str) -> tuple[str, str]:
    return (agent, scenario)


def build_junit(summary_files: list[Path]) -> Element:
    """Build a JUnit XML tree from eval summary JSON files.

    Groups individual metric results by (agent, scenario) and aggregates across
    runs. Each group becomes one JUnit test case with a stable name.
    """
    # Collect raw results keyed by (agent, scenario) -> list of per-run dicts
    # Each "run" is one summary file for a specific agent/run_N directory.
    # A run may contain multiple metric results for the same scenario.
    groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
    run_tracker: dict[tuple[str, str], set[str]] = defaultdict(set)

    for path in sorted(summary_files):
        with open(path) as f:
            data = json.load(f)

        results = data.get("results") or []
        if not results:
            continue

        agent_name = path.parent.parent.name if path.parent.parent.name != "results" else "unknown"
        run_id = path.parent.name if path.parent.name.startswith("run_") else str(path)

        for r in results:
            scenario = r.get("conversation_group_id", "unknown")
            key = _aggregate_key(agent_name, scenario)
            groups[key].append({**r, "_run_id": run_id})
            run_tracker[key].add(run_id)

    testsuites = Element("testsuites")
    suite = SubElement(testsuites, "testsuite", name=SUITE_NAME)

    total_tests = 0
    total_failures = 0
    total_errors = 0

    for (agent, scenario), results in sorted(groups.items()):
        num_runs = len(run_tracker[(agent, scenario)])
        name = f"{scenario}.{agent}"

        # A run passes only when every metric result in it has result == "PASS".
        runs_by_id: dict[str, list[dict]] = defaultdict(list)
        for r in results:
            runs_by_id[r["_run_id"]].append(r)

        runs_passed = sum(
            1 for run_results in runs_by_id.values()
            if all(r.get("result") == "PASS" for r in run_results)
        )
        all_passed = runs_passed == num_runs

        # Aggregate scores
        scores = [r.get("score") for r in results if r.get("score") is not None]
        avg_score = sum(scores) / len(scores) if scores else 0.0

        # Aggregate duration (agent_latency)
        latencies = [r.get("agent_latency") for r in results if r.get("agent_latency") is not None and r.get("agent_latency") > 0]
        avg_latency = sum(latencies) / len(latencies) if latencies else 0.0

        # Aggregate tokens
        total_input = sum(r.get("api_input_tokens", 0) or 0 for r in results)
        total_output = sum(r.get("api_output_tokens", 0) or 0 for r in results)
        avg_input = total_input / num_runs if num_runs else 0
        avg_output = total_output / num_runs if num_runs else 0

        tc = SubElement(suite, "testcase", name=name, classname=scenario)
        if avg_latency > 0:
            tc.set("time", f"{avg_latency:.3f}")

        # Properties for Sippy to display
        props = SubElement(tc, "properties")
        SubElement(props, "property", name="agent", value=agent)
        SubElement(props, "property", name="scenario", value=scenario)
        SubElement(props, "property", name="runs_passed", value=str(runs_passed))
        SubElement(props, "property", name="runs_total", value=str(num_runs))
        SubElement(props, "property", name="pass_rate",
                   value=f"{runs_passed / num_runs * 100:.0f}" if num_runs else "0")
        SubElement(props, "property", name="avg_score", value=f"{avg_score:.2f}")
        SubElement(props, "property", name="avg_latency_seconds",
                   value=f"{avg_latency:.1f}")
        SubElement(props, "property", name="avg_api_input_tokens",
                   value=f"{avg_input:.0f}")
        SubElement(props, "property", name="avg_api_output_tokens",
                   value=f"{avg_output:.0f}")

        # Build output text with run-by-run detail
        output_lines = [
            f"Pass rate: {runs_passed}/{num_runs}",
            f"Avg score: {avg_score:.2f}",
            f"Avg latency: {avg_latency:.1f}s",
            f"Avg tokens: {avg_input:.0f}/{avg_output:.0f} (in/out)",
        ]

        # Collect judge reasons from failures
        fail_reasons = []
        for r in results:
            if r.get("result") in ("FAIL", "ERROR"):
                judges = r.get("judge_scores") or []
                for js in judges:
                    reason = js.get("reason", "")
                    if reason:
                        metric = r.get("metric_identifier", "").split(":")[-1]
                        fail_reasons.append(f"[{metric}] {reason}")

        has_errors = any(r.get("result") == "ERROR" for r in results)

        if not all_passed:
            output_lines.append("")
            if fail_reasons:
                output_lines.append("Failure details:")
                for reason in fail_reasons[:5]:
                    output_lines.append(f"  - {reason}")

            output_text = "\n".join(output_lines)

            if has_errors:
                total_errors += 1
                SubElement(tc, "error",
                           message=f"{runs_passed}/{num_runs} passed, avg_score={avg_score:.2f}"
                           ).text = output_text
            else:
                total_failures += 1
                SubElement(tc, "failure",
                           message=f"{runs_passed}/{num_runs} passed, avg_score={avg_score:.2f}"
                           ).text = output_text

        total_tests += 1

    suite.set("tests", str(total_tests))
    suite.set("failures", str(total_failures))
    suite.set("errors", str(total_errors))

    return testsuites


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <output.xml> <summary.json> [summary2.json ...]", file=sys.stderr)
        sys.exit(1)

    output_path = Path(sys.argv[1])
    summary_files = [Path(p) for p in sys.argv[2:]]

    for p in summary_files:
        if not p.exists():
            print(f"Warning: {p} not found, skipping", file=sys.stderr)

    existing = [p for p in summary_files if p.exists()]
    if not existing:
        print("No summary files found, skipping JUnit generation", file=sys.stderr)
        sys.exit(0)

    tree = build_junit(existing)
    raw = tostring(tree, encoding="unicode", xml_declaration=True)
    pretty = parseString(raw).toprettyxml(indent="  ", encoding="UTF-8")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(pretty)
    print(f"JUnit XML written to {output_path}")


if __name__ == "__main__":
    main()
