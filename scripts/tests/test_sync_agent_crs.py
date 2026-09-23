"""Tests for sync-agent-crs.sh YAML parsing logic."""

import json
import subprocess
import textwrap
from pathlib import Path
from unittest.mock import patch

import pytest
import yaml

import importlib.util

spec = importlib.util.spec_from_file_location(
    "sync_agent_crs",
    Path(__file__).resolve().parent.parent / "sync-agent-crs.py",
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


SYSTEM_YAML = textwrap.dedent("""\
    agents:
      enabled: true
      default:
        agent:
          - agent-openai-1
          - agent-google-1
          # - agent-anthropic-2
      agent-openai-1:
        description: "openai|gpt-5.6-luna"
        type: openshift_agentic_run
        namespace: openshift-lightspeed
        agent_ref: openai-gpt-5-6-luna
      agent-google-1:
        description: "vertex-google|gemini-3-7-flash"
        type: openshift_agentic_run
        namespace: openshift-lightspeed
        agent_ref: google-gemini-3-7-flash
      agent-anthropic-2:
        description: "vertex-anthropic|claude-sonnet-5"
        type: openshift_agentic_run
        namespace: openshift-lightspeed
        agent_ref: anthropic-sonnet-5
""")


def test_extract_agents(tmp_path):
    system_yaml = tmp_path / "system.yaml"
    system_yaml.write_text(SYSTEM_YAML)

    agents = mod.extract_agents(str(system_yaml))

    assert len(agents) == 2
    assert agents[0] == {
        "name": "openai-gpt-5-6-luna",
        "provider": "openai",
        "model": "gpt-5.6-luna",
        "namespace": "openshift-lightspeed",
    }
    assert agents[1] == {
        "name": "google-gemini-3-7-flash",
        "provider": "vertex-google",
        "model": "gemini-3-7-flash",
        "namespace": "openshift-lightspeed",
    }


def test_extract_agents_rejects_missing_provider(tmp_path):
    config = textwrap.dedent("""\
        agents:
          enabled: true
          default:
            agent:
              - agent-bad
          agent-bad:
            description: "just-a-model"
            type: openshift_agentic_run
            namespace: openshift-lightspeed
            agent_ref: bad-agent
    """)
    system_yaml = tmp_path / "system.yaml"
    system_yaml.write_text(config)

    with pytest.raises(mod.AgentConfigError) as error:
        mod.extract_agents(str(system_yaml))

    assert "agent-bad" in str(error.value)
    assert "provider|model" in str(error.value)


def test_extract_agents_disabled(tmp_path):
    config = textwrap.dedent("""\
        agents:
          enabled: false
          default:
            agent:
              - agent-openai-1
          agent-openai-1:
            description: "openai|gpt-5.6-luna"
            type: openshift_agentic_run
            namespace: openshift-lightspeed
            agent_ref: openai-gpt-5-6-luna
    """)
    system_yaml = tmp_path / "system.yaml"
    system_yaml.write_text(config)

    agents = mod.extract_agents(str(system_yaml))

    assert len(agents) == 0


def test_extract_agents_no_agents_section(tmp_path):
    config = textwrap.dedent("""\
        core:
          max_threads: 1
    """)
    system_yaml = tmp_path / "system.yaml"
    system_yaml.write_text(config)

    agents = mod.extract_agents(str(system_yaml))

    assert len(agents) == 0


def test_generate_cr():
    agent = {
        "name": "openai-gpt-5-6-luna",
        "provider": "openai",
        "model": "gpt-5.6-luna",
        "namespace": "openshift-lightspeed",
    }

    cr = mod.generate_cr(agent)

    assert cr == {
        "apiVersion": "agentic.openshift.io/v1alpha1",
        "kind": "Agent",
        "metadata": {
            "name": "openai-gpt-5-6-luna",
            "namespace": "openshift-lightspeed",
        },
        "spec": {
            "llmProvider": {"name": "openai"},
            "model": "gpt-5.6-luna",
        },
    }


def test_check_agent_crs_succeeds(capsys):
    agents = [{
        "name": "openai-gpt-5-6-luna",
        "provider": "openai",
        "model": "gpt-5.6-luna",
        "namespace": "openshift-lightspeed",
    }]
    response = {
        "items": [
            {
                "metadata": {
                    "name": "openai-gpt-5-6-luna",
                    "namespace": "openshift-lightspeed",
                },
                "spec": {
                    "llmProvider": {"name": "openai"},
                    "model": "gpt-5.6-luna",
                },
            }
        ]
    }

    with patch.object(
        mod.subprocess,
        "run",
        return_value=subprocess.CompletedProcess(
            args=[], returncode=0, stdout=json.dumps(response), stderr=""
        ),
    ) as run:
        assert mod.check_agent_crs(agents) is True

    run.assert_called_once_with(
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
    assert capsys.readouterr().out == ""


def test_check_agent_crs_accepts_cluster_scoped_resource(capsys):
    agents = [{
        "name": "openai-gpt-5-6-luna",
        "provider": "openai",
        "model": "gpt-5.6-luna",
        "namespace": "openshift-lightspeed",
    }]
    response = {
        "items": [
            {
                "metadata": {"name": "openai-gpt-5-6-luna"},
                "spec": {
                    "llmProvider": {"name": "openai"},
                    "model": "gpt-5.6-luna",
                },
            }
        ]
    }

    with patch.object(
        mod.subprocess,
        "run",
        return_value=subprocess.CompletedProcess(
            args=[], returncode=0, stdout=json.dumps(response), stderr=""
        ),
    ):
        assert mod.check_agent_crs(agents) is True

    assert capsys.readouterr().out == ""


def test_check_agent_crs_reports_missing_and_stale(capsys):
    agents = [
        {
            "name": "openai-gpt-5-6-luna",
            "provider": "openai",
            "model": "gpt-5.6-luna",
            "namespace": "openshift-lightspeed",
        },
        {
            "name": "google-gemini-3-7-flash",
            "provider": "vertex-google",
            "model": "gemini-3.7-flash",
            "namespace": "openshift-lightspeed",
        },
    ]
    response = {
        "items": [
            {
                "metadata": {
                    "name": "openai-gpt-5-6-luna",
                    "namespace": "openshift-lightspeed",
                },
                "spec": {
                    "llmProvider": {"name": "old-provider"},
                    "model": "old-model",
                },
            }
        ]
    }

    with patch.object(
        mod.subprocess,
        "run",
        return_value=subprocess.CompletedProcess(
            args=[], returncode=0, stdout=json.dumps(response), stderr=""
        ),
    ):
        assert mod.check_agent_crs(agents) is False

    output = capsys.readouterr().err
    assert "not synchronized" in output
    assert "old-provider" in output
    assert "old-model" in output
    assert "missing openshift-lightspeed/google-gemini-3-7-flash" in output
    assert "make setup-ols-agentic" in output
