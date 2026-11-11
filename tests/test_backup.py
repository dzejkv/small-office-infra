"""Backups run, can be restored, and cannot be deleted from the server they protect."""

from __future__ import annotations

import json

from conftest import dexec, prom_query, wait_for

ENV = ". /etc/office-backup/env"


def snapshots(host: str) -> list[dict]:
    res = dexec(host, f"{ENV}; restic snapshots --json", check=True)
    return json.loads(res.stdout)


def test_backup_runs_and_reports_success():
    before = len(snapshots("files"))
    res = dexec("files", "/usr/local/bin/office-backup", timeout=300)
    assert res.returncode == 0, res.stderr
    assert len(snapshots("files")) == before + 1
    wait_for(
        lambda: any(r["metric"].get("instance") == "files" and r["value"][1] == "1"
                    for r in prom_query("office_backup_last_status")),
        timeout=60, message="Prometheus to see the backup result",
    )


def test_restore_matches_the_live_data():
    dexec("files", "/usr/local/bin/office-backup", check=True, timeout=300)
    res = dexec("files", f"""{ENV}
        rm -rf /tmp/restore-test
        restic restore latest --target /tmp/restore-test >/dev/null
        diff -r /srv/files /tmp/restore-test/srv/files && echo IDENTICAL
        rm -rf /tmp/restore-test""", timeout=300)
    assert "IDENTICAL" in res.stdout, res.stdout + res.stderr


def test_client_cannot_delete_its_own_backups():
    """Append-only server: ransomware on the file server can't wipe the backups.

    Note: restic exits 0 even when the server refuses the delete, so the exit
    code proves nothing. What matters is the server's answer and what's still there.
    """
    snaps = snapshots("files")
    assert snaps, "need at least one snapshot"
    victim = snaps[0]["short_id"]
    res = dexec("files", f"{ENV}; restic forget {victim}", timeout=120)
    assert "403" in res.stderr, f"server did not refuse the delete: {res.stderr}"
    assert victim in {s["short_id"] for s in snapshots("files")}, "snapshot disappeared"


def test_client_cannot_read_another_clients_backups():
    """Private repositories: the file server's login can't open the directory's backups."""
    res = dexec("files", f"""{ENV}
        repo=$(echo "$RESTIC_REPOSITORY" | sed 's#/files/$#/directory/#')
        code=$(curl -s -o /dev/null -w '%{{http_code}}' "${{repo#rest:}}config")
        echo "$code" """)
    assert res.stdout.strip() in ("401", "403"), res.stdout


def test_retention_job_runs_on_the_backup_server():
    res = dexec("backup", "/usr/local/bin/office-backup-prune", timeout=300)
    assert res.returncode == 0, res.stderr
