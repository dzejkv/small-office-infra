# Runbook: restoring files from backup

**Owner:** IT admins · **Triggers:** "I deleted a file", ransomware, `BackupFailed` / `BackupTooOld` alert

## Restore a deleted or overwritten file

Run from the admin jump host (or `docker exec` in the lab).

1. Find the snapshot from before the change:
   ```bash
   docker exec -it kestrel-files sh -c '. /etc/office-backup/env; restic snapshots'
   ```
2. Look for the file:
   ```bash
   docker exec -it kestrel-files sh -c '. /etc/office-backup/env; restic ls <snapshot-id> /srv/files/design'
   ```
3. Restore it **to a separate folder** first, never over live data:
   ```bash
   docker exec -it kestrel-files sh -c '. /etc/office-backup/env; \
     restic restore <snapshot-id> --target /tmp/restore --include /srv/files/design/harbour-library-brief.txt'
   ```
4. Check it with the person who asked, then copy it into place.
5. Note the request in the IT log (who, what, which snapshot).

## Ransomware on the file server

1. **Isolate first.** Stop the file server: `docker stop kestrel-files`. In a real
   office: pull its network cable. Don't power off workstations yet (memory evidence).
2. Tell leadership. Check the SIEM for the first suspicious event (see the
   [triage runbook](siem-alert-triage.md)).
3. **Backups are safe**: the backup server is append-only, so the infected server
   couldn't delete them. Confirm with `restic snapshots` from the backup server.
4. Rebuild the file server clean: `terraform -chdir=terraform apply -replace='docker_container.host["files"]'`
   then `make configure`.
5. Restore the last snapshot taken **before** the infection into the new server.
6. Change all passwords, starting with IT admins.

## Backup alerts

| Alert | First check |
|---|---|
| `BackupFailed` | `docker exec kestrel-files tail -50 /var/log/office-backup.log`. Usually: backup server down, disk full, or a changed password. |
| `BackupTooOld` | Is cron running on the server? `docker exec kestrel-files pgrep crond` |
| `BackupNeverRan` | New server not yet configured: `make configure` |

After fixing anything, run `make backup-now` and confirm the dashboard shows OK.

## Restore test

`make test` restores the latest snapshot and compares it with the live data byte
for byte. If that test ever fails, treat it as a P1: you don't have working backups.
