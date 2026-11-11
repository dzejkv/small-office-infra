"""The SIEM receives logs from the office and the detections fire on realistic attacks.

Each test records where the alert log ends, does something an attacker would do,
and waits for the matching alert to appear after that point.
"""

from __future__ import annotations

import json
import random
import uuid

import pytest

from conftest import dexec, ip_of, wait_for

ALERTS = "/var/ossec/logs/alerts/alerts.json"
ARCHIVE = "/var/ossec/logs/archives/archives.json"


@pytest.fixture(autouse=True)
def _needs_siem(siem_enabled):
    if not siem_enabled:
        pytest.skip("SIEM is disabled (enable_siem = false)")


def line_count(path: str) -> int:
    return int(dexec("wazuh", f"wc -l < {path} 2>/dev/null || echo 0", check=True).stdout.strip() or 0)


def new_events(path: str, since: int) -> list[dict]:
    out = dexec("wazuh", f"tail -n +{since + 1} {path}", check=True).stdout
    events = []
    for line in out.splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return events


def wait_for_alert(since: int, rule_id: str, **data) -> dict:
    def match():
        for a in new_events(ALERTS, since):
            if a["rule"]["id"] == rule_id and all(a.get("data", {}).get(k) == v for k, v in data.items()):
                return a
        return None
    return wait_for(match, timeout=60, message=f"alert {rule_id} {data}")


def test_logs_from_servers_reach_the_siem():
    marker = f"siem-test-{uuid.uuid4()}"
    since = line_count(ARCHIVE)
    dexec("files", f"logger -t office-test {marker}", check=True)
    wait_for(lambda: any(marker in e.get("full_log", "") for e in new_events(ARCHIVE, since)),
             timeout=60, message="the test log line to arrive")


def test_guest_reaching_inside_raises_an_alert():
    port = str(random.randint(20000, 29999))  # unique, so we find *this* attempt
    since = line_count(ALERTS)
    dexec("guest-01", f"nc -z -w 1 {ip_of('files')} {port}")
    alert = wait_for_alert(since, "100101", dstport=port)
    assert alert["data"]["srcip"] == ip_of("guest-01")
    assert alert["rule"]["level"] >= 8


def test_port_scan_from_a_workstation_is_detected():
    since = line_count(ALERTS)
    ports = " ".join(str(p) for p in random.sample(range(30000, 39999), 15))
    dexec("ws-03", f"for p in {ports}; do nc -z -w 1 {ip_of('directory')} $p; done", timeout=120)
    alert = wait_for_alert(since, "100102")
    assert alert["data"]["srcip"] == ip_of("ws-03")


def test_ssh_password_guessing_is_detected():
    """Wazuh's built-in rule 5712: repeated logins with non-existent users."""
    since = line_count(ALERTS)
    users = " ".join(f"guess{uuid.uuid4().hex[:6]}" for _ in range(12))
    dexec("admin", f"for u in {users}; do ssh -o BatchMode=yes -o ConnectTimeout=3 "
                   f"-o StrictHostKeyChecking=no $u@{ip_of('files')} true 2>/dev/null; done", timeout=180)
    alert = wait_for_alert(since, "5712")
    assert alert["data"]["srcip"] == ip_of("admin")
