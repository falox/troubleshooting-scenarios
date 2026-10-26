"""Check MCP setup and rollout failures without a cluster."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def mcp_workspace(tmp_path):
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    for name in ("setup-mcp.sh", "mcp-config.sh"):
        shutil.copy(ROOT / "scripts" / name, scripts / name)
    binary = tmp_path / "bin/oc"
    binary.parent.mkdir()
    binary.write_text(f"#!{sys.executable}\n" + r'''
import json
import os
from pathlib import Path
import sys
import yaml

root = Path(os.environ["MCP_TEST_ROOT"])
args = sys.argv[1:]
with (root / "calls.jsonl").open("a") as output:
    output.write(json.dumps(args) + "\n")
state_file = root / "state.json"
state = json.loads(state_file.read_text()) if state_file.exists() else {}
if args[:2] == ["create", "namespace"]:
    print(yaml.safe_dump({"kind": "Namespace", "metadata": {"name": args[2]}}))
elif args[:2] == ["create", "clusterrolebinding"]:
    print(yaml.safe_dump({"kind": "ClusterRoleBinding", "metadata": {"name": args[2]}}))
elif args[:2] == ["create", "configmap"]:
    print(yaml.safe_dump({"kind": "ConfigMap", "metadata": {"name": args[2]},
                          "data": {"config.toml": sys.stdin.read()}}))
elif args[0] == "apply":
    resource = yaml.safe_load(sys.stdin)
    state[resource["kind"]] = resource
    state_file.write_text(json.dumps(state))
elif args[:2] == ["get", "configmap"]:
    print(state["ConfigMap"]["data"]["config.toml"], end="")
elif args[:2] == ["get", "deployment"]:
    sys.exit(0 if "Deployment" in state else 1)
elif args[:2] == ["get", "pods"]:
    print("mcp-pod 0/1 CrashLoopBackOff")
elif args[0] == "logs":
    print("Error: invalid toolset name: netobserv")
elif args[:2] == ["rollout", "status"]:
    deployment = state["Deployment"]
    image = deployment["spec"]["template"]["spec"]["containers"][0]["image"]
    assert image != "old-broken-image", "Wait started before the image update"
    assert any(arg.startswith("--timeout=") for arg in args), "Unbounded rollout wait"
    sys.exit(int(os.environ.get("MCP_TEST_ROLLOUT_STATUS", "0")))
elif args[:2] != ["rollout", "restart"]:
    sys.exit(9)
''')
    binary.chmod(0o755)
    return tmp_path


def run_mcp(root, script="setup-mcp.sh", args=(), **extra_env):
    result = subprocess.run(
        ["bash", str(root / "scripts" / script), *args],
        env={**os.environ, "PATH": f"{root / 'bin'}:{os.environ['PATH']}",
             "MCP_TEST_ROOT": str(root), "MCP_TOOLSETS": "core,config,netobserv",
             **extra_env},
        capture_output=True, text=True, timeout=10,
    )
    calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
    state = json.loads((root / "state.json").read_text())
    return result, calls, state


@pytest.mark.parametrize("existing", [False, True])
def test_setup_applies_config_and_image_before_wait(mcp_workspace, existing):
    root = mcp_workspace
    if existing:
        (root / "state.json").write_text(json.dumps({"Deployment": {
            "spec": {"template": {"spec": {"containers": [{"image": "old-broken-image"}]}}},
        }}))
    result, calls, state = run_mcp(root)
    assert result.returncode == 0, result.stdout + result.stderr
    assert not any(call[:2] == ["rollout", "restart"] for call in calls)
    assert sum(call[:2] == ["rollout", "status"] for call in calls) == 1
    template = state["Deployment"]["spec"]["template"]
    assert template["spec"]["containers"][0]["image"].startswith(
        "registry.redhat.io/openshift-mcp/openshift-mcp-server-rhel9@sha256:"
    )
    config = state["ConfigMap"]["data"]["config.toml"]
    assert 'toolsets = ["core","config","netobserv"]' in config
    assert template["metadata"]["annotations"]["mcp-config-hash"] == hashlib.sha256(
        config.encode()
    ).hexdigest()


def test_config_change_rolls_pods_but_unchanged_setup_is_stable(mcp_workspace):
    root = mcp_workspace
    result, _, first = run_mcp(root)
    assert result.returncode == 0, result.stdout + result.stderr
    result, _, same = run_mcp(root)
    assert result.returncode == 0, result.stdout + result.stderr
    assert first["Deployment"]["spec"]["template"] == same["Deployment"]["spec"]["template"]
    result, _, changed = run_mcp(root, MCP_TOOLSETS="core,config,ossm")
    assert result.returncode == 0, result.stdout + result.stderr
    assert first["Deployment"]["spec"]["template"] != changed["Deployment"]["spec"]["template"]


@pytest.mark.parametrize("script", ["setup-mcp.sh", "mcp-config.sh"])
@pytest.mark.parametrize("rollout_status", ["0", "1"])
def test_rollout_is_bounded_and_reports_failure(mcp_workspace, script, rollout_status):
    root = mcp_workspace
    result, _, _ = run_mcp(root)
    assert result.returncode == 0, result.stdout + result.stderr
    (root / "calls.jsonl").unlink()
    result, calls, _ = run_mcp(
        root, script, MCP_TEST_ROLLOUT_STATUS=rollout_status, MCP_ROLLOUT_TIMEOUT="7s",
    )
    assert result.returncode == int(rollout_status), result.stdout + result.stderr
    waits = [call for call in calls if call[:2] == ["rollout", "status"]]
    assert len(waits) == 1
    assert "--timeout=7s" in waits[0]
    assert any(call[:2] == ["rollout", "restart"] for call in calls) == (script == "mcp-config.sh")
    if rollout_status == "1":
        assert "CrashLoopBackOff" in result.stderr
        assert "invalid toolset name: netobserv" in result.stderr
        assert "MCP server ready" not in result.stdout
