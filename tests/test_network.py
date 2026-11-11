"""Segmentation: every zone-to-zone path behaves exactly as policy/network.yml says.

The expected result for each (source zone, destination zone, port) is derived
from the policy file. Nothing is hard-coded here, so a policy change that the
firewall does not implement makes these tests fail.
"""

from __future__ import annotations

import itertools

import pytest

from conftest import NETWORK, dexec, hosts_in, probe_many

INTERNET_TARGET = "1.1.1.1"
ZONES = [z for z in NETWORK["zones"] if z != "internet"]

# Every TCP port the policy mentions, plus some an attacker would try.
POLICY_PORTS = sorted({int(p.split("/")[0]) for f in NETWORK["flows"] for p in f["ports"] if p.endswith("/tcp")})
PORTS = sorted(set(POLICY_PORTS) | {445, 3389, 5432})


def allowed(src: str, dst: str, port: int) -> bool:
    return any(f["from"] == src and f["to"] == dst and f"{port}/tcp" in f["ports"] for f in NETWORK["flows"])


def target_ip(zone: str) -> str:
    return NETWORK["hosts"][hosts_in(zone)[0]]["ip"]


CASES = [
    (src, dst, port)
    for src, dst in itertools.permutations(ZONES + ["internet"], 2)
    if src != "internet"
    for port in (PORTS if dst != "internet" else [22, 80, 443, 3389])
]


@pytest.fixture(scope="module")
def results(internet_available):
    """Run all probes once, in parallel, from one machine per zone."""
    out = {}
    for src in ZONES:
        targets = [
            (INTERNET_TARGET if dst == "internet" else target_ip(dst), port)
            for s, dst, port in CASES if s == src
        ]
        out[src] = probe_many(hosts_in(src)[0], targets)
    out["_internet"] = internet_available
    return out


@pytest.mark.parametrize(
    "src,dst,port", CASES,
    ids=[f"{s}->{d}:{p}-{'allow' if allowed(s, d, p) else 'deny'}" for s, d, p in CASES],
)
def test_zone_policy(results, src, dst, port):
    if dst == "internet" and not results["_internet"]:
        pytest.skip("no internet access from this machine")
    ip = INTERNET_TARGET if dst == "internet" else target_ip(dst)
    outcome = results[src][f"{ip}:{port}"]
    if allowed(src, dst, port):
        # "refused" still proves the firewall let it through; only "filtered" means blocked.
        assert outcome in ("open", "refused"), f"{src}->{dst}:{port} should be allowed, got {outcome}"
    else:
        assert outcome == "filtered", f"{src}->{dst}:{port} should be blocked, got {outcome}"


CAP_NET_ADMIN = 1 << 12

# Capabilities of every process the machine itself runs. Processes started by
# `docker exec` (an admin on the host, or this test) are skipped: their process
# tree leads to PID 0 instead of the machine's PID 1. Zombies are skipped too.
CAPS_SCRIPT = r"""
for d in /proc/[0-9]*; do
  pid=${d#/proc/}
  [ -r "$d/status" ] || continue
  [ "$(awk '/^State:/{print $2}' "$d/status")" = Z ] && continue
  p=$pid
  while [ "$p" != 1 ] && [ "$p" != 0 ]; do
    p=$(awk '/^PPid:/{print $2}' /proc/$p/status 2>/dev/null || echo 0)
  done
  [ "$p" = 1 ] || continue
  name=$(awk '/^Name:/{print $2}' "$d/status")
  eff=$(awk '/^CapEff:/{print $2}' "$d/status"); bnd=$(awk '/^CapBnd:/{print $2}' "$d/status")
  echo "$name $eff $bnd"
done
"""


def test_no_process_on_a_host_can_change_routing():
    """Every machine except the firewall drops CAP_NET_ADMIN at boot, and Ansible
    starts services the same way, so nothing running there (a compromised sshd,
    a cron job) can re-route around the firewall."""
    for host, spec in NETWORK["hosts"].items():
        if spec.get("role") == "firewall":
            continue
        # Processes started by `docker exec` (like this check) are the host admin's own, so skip our shell.
        for line in dexec(host, CAPS_SCRIPT, check=True).stdout.splitlines():
            name, eff, bnd = line.split()
            assert int(eff, 16) & CAP_NET_ADMIN == 0, f"{host}: {name} can still change routing"
            assert int(bnd, 16) & CAP_NET_ADMIN == 0, f"{host}: {name} could regain CAP_NET_ADMIN"


def test_firewall_keeps_policy_after_restart():
    """The firewall reloads Ansible's rules on boot, and never starts open."""
    import subprocess
    subprocess.run(["docker", "restart", "kestrel-fw"], check=True, capture_output=True)
    rules = dexec("fw", "nft list chain inet filter forward", check=True).stdout
    assert "policy drop" in rules
    assert "staff -> servers" in rules, "office policy was not reloaded after restart"
