# ADR 0003: Append-only backups with retention on the server side

**Status:** accepted

## Context

Modern ransomware finds and deletes backups before it encrypts anything. If the
server being backed up can delete its own backups, so can ransomware on that
server.

## Decision

- **restic** on each server, encrypting on the client with a key the backup
  server never uses during normal operation.
- **rest-server with `--append-only --private-repos`**: clients can add
  snapshots but never delete or overwrite them, and each client sees only its
  own repository.
- **Retention (`forget --prune`) runs on the backup server**, directly against
  the repositories on its disk, weekly. Clients never prune.
- The backup segment accepts only port 8000, and only from servers and mgmt.
- Every run reports to Prometheus and syslog. Alerts fire if it failed, if it's
  older than 26 hours, or if it never ran.
- Restores are tested automatically (`test_backup.py` restores and compares).

## A lesson from testing

The first version of the "client cannot delete its backups" test checked restic's
exit code, and failed: `restic forget` **exits 0 even when the server refuses the
delete** with 403 Forbidden. The server was doing its job; the client just didn't
report it. The test now checks what matters: the server answered 403 and the
snapshot is still there. Monitoring that trusts exit codes alone can give false
confidence, in both directions.

## Consequences

- A compromised file server can add junk snapshots but can't destroy history.
- The backup server holds the repository keys (to prune), so it is the most
  sensitive machine and the most isolated one.
- Still one copy in one place. Off-site replication is on the [roadmap](../roadmap.md).
