"""Tests for scripts/expand-evals.py."""

import subprocess
import sys
import textwrap
from pathlib import Path

import yaml

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
EXPAND_SCRIPT = SCRIPTS_DIR / "expand-evals.py"


def run_expand(evals_yaml: str, agents_yaml: str, tmp_path: Path) -> list[dict]:
    """Write inputs to temp files, run expand-evals.py, return parsed output."""
    evals_file = tmp_path / "evals.yaml"
    agents_file = tmp_path / "agents.yaml"
    evals_file.write_text(evals_yaml)
    agents_file.write_text(agents_yaml)

    result = subprocess.run(
        [sys.executable, str(EXPAND_SCRIPT), str(evals_file), str(agents_file)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Script failed:\n{result.stderr}"
    return yaml.safe_load(result.stdout)


AGENTS_YAML = textwrap.dedent("""\
    agents:
      - id: default
        label: openai
      - id: opus
        label: anthropic
      - id: gemini
        label: gemini
""")

SINGLE_EVAL = textwrap.dedent("""\
    - conversation_group_id: my_scenario
      tag: agentic_my_scenario

      turns:
        - turn_id: turn_1
          proposal_spec:
            request: |
              Investigate the issue.
            targetNamespaces:
              - test-ns
            tools:
              skills:
                - image: quay.io/test/skills:latest
                  paths:
                    - /skills/test
            analysis:
              agent: default

          expected_proposal_status:
            phase: Completed
            conditions:
              - type: Analyzed
                status: "True"

          expected_outcome: >-
            The root cause is X.

          turn_metrics:
            - "custom:proposal_status"
            - "custom:proposal_evaluation_correctness"
          turn_metrics_metadata:
            "custom:proposal_evaluation_correctness":
              threshold: 0.75
""")


def test_expands_to_one_entry_per_agent(tmp_path):
    result = run_expand(SINGLE_EVAL, AGENTS_YAML, tmp_path)
    assert len(result) == 3


def test_conversation_group_id_gets_label_suffix(tmp_path):
    result = run_expand(SINGLE_EVAL, AGENTS_YAML, tmp_path)
    ids = [e["conversation_group_id"] for e in result]
    assert ids == ["my_scenario_openai", "my_scenario_anthropic", "my_scenario_gemini"]


def test_agent_value_is_set_from_id(tmp_path):
    result = run_expand(SINGLE_EVAL, AGENTS_YAML, tmp_path)
    agents = [e["turns"][0]["proposal_spec"]["analysis"]["agent"] for e in result]
    assert agents == ["default", "opus", "gemini"]


def test_tag_is_preserved(tmp_path):
    result = run_expand(SINGLE_EVAL, AGENTS_YAML, tmp_path)
    tags = [e["tag"] for e in result]
    assert all(t == "agentic_my_scenario" for t in tags)


def test_other_fields_are_preserved(tmp_path):
    result = run_expand(SINGLE_EVAL, AGENTS_YAML, tmp_path)
    for entry in result:
        turn = entry["turns"][0]
        assert turn["turn_id"] == "turn_1"
        assert turn["proposal_spec"]["request"].strip() == "Investigate the issue."
        assert turn["proposal_spec"]["targetNamespaces"] == ["test-ns"]
        assert turn["expected_outcome"].strip() == "The root cause is X."
        assert turn["turn_metrics_metadata"]["custom:proposal_evaluation_correctness"]["threshold"] == 0.75


def test_extra_entry_fields_are_preserved(tmp_path):
    """Fields like setup_script/cleanup_script (as in failed_job) are kept."""
    evals = textwrap.dedent("""\
        - conversation_group_id: with_scripts
          tag: agentic_with_scripts
          setup_script: ./setup.sh
          cleanup_script: ./cleanup.sh

          turns:
            - turn_id: turn_1
              proposal_spec:
                request: Investigate.
                targetNamespaces:
                  - ns
                analysis:
                  agent: default
              expected_proposal_status:
                phase: Completed
              expected_outcome: Fix it.
              turn_metrics:
                - "custom:proposal_status"
    """)
    result = run_expand(evals, AGENTS_YAML, tmp_path)
    for entry in result:
        assert entry["setup_script"] == "./setup.sh"
        assert entry["cleanup_script"] == "./cleanup.sh"


def test_single_agent(tmp_path):
    agents = textwrap.dedent("""\
        agents:
          - id: opus
            label: anthropic
    """)
    result = run_expand(SINGLE_EVAL, agents, tmp_path)
    assert len(result) == 1
    assert result[0]["conversation_group_id"] == "my_scenario_anthropic"
    assert result[0]["turns"][0]["proposal_spec"]["analysis"]["agent"] == "opus"


def test_copies_are_independent(tmp_path):
    """Mutating one copy must not affect another (deep copy)."""
    result = run_expand(SINGLE_EVAL, AGENTS_YAML, tmp_path)
    result[0]["turns"][0]["proposal_spec"]["request"] = "MUTATED"
    assert result[1]["turns"][0]["proposal_spec"]["request"] != "MUTATED"
