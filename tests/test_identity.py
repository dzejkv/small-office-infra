"""Accounts come from the roster, logins work only with the right password,
and group membership decides what someone can do (Grafana roles)."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest
import yaml

from conftest import GRAFANA, ROOT, ROSTER, dexec, http_json, secret

BASE = "dc=kestrel,dc=test"
LDAP = "ldap://10.20.20.10:3890"


def bind(uid: str, password: str, from_host: str = "ws-01") -> bool:
    res = dexec(from_host, f'ldapwhoami -x -H {LDAP} -D "uid={uid},ou=people,{BASE}" -y /dev/stdin',
                stdin=password)
    return res.returncode == 0


def active_people():
    return [p for p in ROSTER["people"] if p.get("status") != "left"]


def test_everyone_on_the_roster_can_log_in():
    for person in active_people():
        assert bind(person["uid"], secret(f"users/{person['uid']}")), person["uid"]


def test_wrong_password_is_rejected():
    assert not bind("atanaka", "definitely-not-the-password")


def test_directory_has_nobody_extra():
    admin = secret("lldap-admin")
    res = dexec("admin", f'ldapsearch -x -LLL -H {LDAP} -D "uid=admin,ou=people,{BASE}" -y /dev/stdin '
                         f'-b "ou=people,{BASE}" "(objectClass=person)" uid', stdin=admin, check=True)
    found = {line.split(": ", 1)[1] for line in res.stdout.splitlines() if line.startswith("uid: ")}
    expected = {p["uid"] for p in active_people()} | {s["uid"] for s in ROSTER["service_accounts"]} | {"admin"}
    assert found == expected


def test_group_membership_matches_roster():
    admin = secret("lldap-admin")
    res = dexec("admin", f'ldapsearch -x -LLL -H {LDAP} -D "uid=admin,ou=people,{BASE}" -y /dev/stdin '
                         f'-b "ou=people,{BASE}" "(uid=gmwangi)" memberOf', stdin=admin, check=True)
    assert f"cn=finance,ou=groups,{BASE}" in res.stdout
    assert f"cn=all-staff,ou=groups,{BASE}" in res.stdout
    assert f"cn=it-admins,ou=groups,{BASE}" not in res.stdout


def grafana_role(uid: str) -> str | None:
    status, body = http_json(f"{GRAFANA}/api/user/orgs", uid, secret(f"users/{uid}"))
    return body[0]["role"] if status == 200 and body else None


def test_grafana_role_comes_from_directory_group():
    assert grafana_role("riyer") == "Admin"      # it-admins
    assert grafana_role("atanaka") == "Viewer"   # everyone else


def test_service_account_cannot_log_into_grafana():
    status, _ = http_json(f"{GRAFANA}/api/user", "svc-grafana", secret("svc-grafana"))
    assert status == 401


def run_users_playbook(roster_file: Path) -> None:
    subprocess.run(
        ["ansible-playbook", "users.yml", "-e", f"roster_file={roster_file}"],
        cwd=ROOT / "ansible", check=True, capture_output=True, text=True, timeout=300,
    )


@pytest.mark.slow
def test_leaver_loses_access_and_joiner_gets_it_back(tmp_path):
    """Offboarding is a roster change: mark someone `status: left`, re-run, and
    every login that depends on the directory stops working for them."""
    roster = yaml.safe_load((ROOT / "policy" / "people.yml").read_text())
    for p in roster["people"]:
        if p["uid"] == "bcarter":
            p["status"] = "left"
    leaver_roster = tmp_path / "people.yml"
    leaver_roster.write_text(yaml.safe_dump(roster))
    password = secret("users/bcarter")

    try:
        run_users_playbook(leaver_roster)
        assert not bind("bcarter", password), "leaver can still log in to the directory"
        status, _ = http_json(f"{GRAFANA}/api/user", "bcarter", password)
        assert status == 401, "leaver can still log in to Grafana"
    finally:
        run_users_playbook(ROOT / "policy" / "people.yml")

    assert bind("bcarter", password), "re-adding the person did not restore access"
