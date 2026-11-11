"""Shared helpers for testing the running lab.

Tests talk to the lab the way an admin would: `docker exec` into a machine and
run a command there, or call the published Grafana/Prometheus ports.
Everything is driven by policy/*.yml, so the tests follow the policy.
"""

from __future__ import annotations

import base64
import json
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
PREFIX = "kestrel"
NETWORK = yaml.safe_load((ROOT / "policy" / "network.yml").read_text())
ROSTER = yaml.safe_load((ROOT / "policy" / "people.yml").read_text())
SECRETS = ROOT / ".secrets"
GRAFANA = "http://127.0.0.1:3000"
PROMETHEUS = "http://127.0.0.1:9090"


def container(host: str) -> str:
    return f"{PREFIX}-{host}"


def dexec(host: str, script: str, *, check: bool = False, stdin: str | None = None,
          timeout: int = 120) -> subprocess.CompletedProcess:
    """Run a shell script inside a lab machine (or a service container)."""
    cmd = ["docker", "exec"] + (["-i"] if stdin is not None else []) + [container(host), "sh", "-c", script]
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, check=check, timeout=timeout)


def secret(name: str) -> str:
    return (SECRETS / name).read_text().strip()


def hosts_in(zone: str) -> list[str]:
    return [h for h, d in NETWORK["hosts"].items() if d.get("zone") == zone]


def ip_of(host: str) -> str:
    return NETWORK["hosts"][host]["ip"]


def http_json(url: str, user: str | None = None, password: str | None = None) -> tuple[int, object]:
    req = urllib.request.Request(url)
    if user is not None:
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        req.add_header("Authorization", f"Basic {token}")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, json.loads(resp.read() or b"null")
    except urllib.error.HTTPError as err:
        body = err.read()
        try:
            return err.code, json.loads(body or b"null")
        except json.JSONDecodeError:
            return err.code, body.decode(errors="replace")


def prom_query(expr: str) -> list[dict]:
    q = urllib.parse.quote(expr)
    status, body = http_json(f"{PROMETHEUS}/api/v1/query?query={q}")
    assert status == 200, body
    return body["data"]["result"]


def wait_for(predicate, timeout: float = 60, interval: float = 2, message: str = "condition"):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = predicate()
        if last:
            return last
        time.sleep(interval)
    raise AssertionError(f"timed out after {timeout}s waiting for {message} (last value: {last!r})")


# A small TCP probe that runs *inside* a lab machine. It tells apart:
#   open     - something answered
#   refused  - the packet got through, nothing listening (so the firewall allowed it)
#   filtered - no answer at all (the firewall dropped it)
PROBE = r'''
import json, socket, sys, concurrent.futures as cf
targets = json.loads(sys.stdin.read())
def probe(t):
    ip, port = t
    s = socket.socket(); s.settimeout(2.5)
    try:
        s.connect((ip, port)); r = "open"
    except ConnectionRefusedError:
        r = "refused"
    except OSError:
        r = "filtered"
    finally:
        s.close()
    return f"{ip}:{port}", r
with cf.ThreadPoolExecutor(64) as ex:
    print(json.dumps(dict(ex.map(probe, [tuple(t) for t in targets]))))
'''


def probe_many(src_host: str, targets: list[tuple[str, int]]) -> dict[str, str]:
    # The heredoc carries the probe script; stdin carries the target list.
    res = subprocess.run(
        ["docker", "exec", "-i", container(src_host), "sh", "-c",
         "cat > /tmp/probe.py <<'EOF'\n" + PROBE + "\nEOF\npython3 /tmp/probe.py"],
        input=json.dumps(targets), capture_output=True, text=True, timeout=120,
    )
    assert res.returncode == 0, res.stderr
    return json.loads(res.stdout)


@pytest.fixture(scope="session", autouse=True)
def lab_is_running():
    res = subprocess.run(["docker", "inspect", "-f", "{{.State.Running}}", container("fw")],
                         capture_output=True, text=True)
    if res.stdout.strip() != "true":
        pytest.skip("lab is not running: run `make up` first", allow_module_level=True)


@pytest.fixture(scope="session")
def siem_enabled() -> bool:
    res = subprocess.run(["docker", "inspect", "-f", "{{.State.Running}}", container("wazuh")],
                         capture_output=True, text=True)
    return res.stdout.strip() == "true"


@pytest.fixture(scope="session")
def internet_available() -> bool:
    res = dexec("fw", "nc -z -w 3 1.1.1.1 443")
    return res.returncode == 0
