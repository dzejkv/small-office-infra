"""Monitoring sees every service through the firewall, and the alert rules are loaded."""

from __future__ import annotations

from conftest import GRAFANA, PROMETHEUS, http_json, prom_query, secret, wait_for


def test_every_service_check_is_up():
    def all_up():
        results = prom_query('probe_success{job="service-checks"}')
        return len(results) >= 5 and all(r["value"][1] == "1" for r in results) and results
    results = wait_for(all_up, timeout=90, message="all service checks to report up")
    assert {r["metric"]["service"] for r in results} >= {
        "directory-ldap", "directory-web", "files-ssh", "backup-server", "siem"}


def test_alert_rules_are_loaded():
    status, body = http_json(f"{PROMETHEUS}/api/v1/rules")
    assert status == 200
    names = {r["name"] for g in body["data"]["groups"] for r in g["rules"]}
    assert {"ServiceDown", "BackupFailed", "BackupTooOld", "BackupNeverRan"} <= names


def test_nothing_is_down():
    firing = [r["metric"]["alertname"] for r in prom_query('ALERTS{alertstate="firing"}')]
    assert "ServiceDown" not in firing
    assert "BackupFailed" not in firing


def test_dashboard_is_provisioned():
    status, body = http_json(f"{GRAFANA}/api/search?query=Office%20overview", "admin", secret("grafana-admin"))
    assert status == 200 and any(d["uid"] == "office-overview" for d in body)
