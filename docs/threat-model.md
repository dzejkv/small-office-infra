# Threat model

What could realistically go wrong for a 20-person office, what this design does
about it, and where it stops.

## Assets

| Asset | Why it matters |
|---|---|
| Client project files | The studio's work. Losing them stops the business. |
| Finance and payroll share | Confidential. Must stay within finance. |
| Staff accounts | One stolen password opens everything that account can reach. |
| Backups | The last line of defence against ransomware. |
| Logs | Needed to find out what happened. |

## Likely attackers and events

For an office this size, the realistic threats are not nation states. They are:

1. **Phishing → malware on a workstation**, which then spreads.
2. **Ransomware**, which encrypts files and deletes backups first.
3. **A visitor** on guest Wi-Fi poking around.
4. **A leaver** whose account still works.
5. **Password guessing** against anything exposed.
6. **Things just breaking**: a failed disk, a backup job that silently stopped.

## Controls by threat

| Threat | Control | Verified by |
|---|---|---|
| Malware on a workstation spreads | Staff can reach only LDAP on servers. No SSH, no file-sharing ports, nothing in backup or mgmt. | `test_network.py` (every zone/port pair) |
| Malware maps the network | Every drop is logged. 10+ blocked connections in 60 s from one host raises an alert (rule 100102). | `test_siem.py::test_port_scan…` |
| Ransomware deletes backups | Backup server is append-only. Clients can't delete or overwrite. Retention runs only on the backup server. | `test_backup.py::test_client_cannot_delete…` |
| Ransomware reads other backups | Private repos: each client's login sees only its own. Data encrypted with a client-held key. | `test_backup.py::test_client_cannot_read…` |
| Compromised server phones home | Servers have no internet route at all. | `test_network.py` (`servers->internet`) |
| Compromised host re-routes around the firewall | All processes drop `CAP_NET_ADMIN` after boot. | `test_network.py::test_no_process…` |
| Guest reaches inside | Guest zone is internet-only, and any attempt inside alerts (rule 100101, level 8). | `test_network.py`, `test_siem.py` |
| Leaver keeps access | Accounts come from the roster. Marking someone `left` deletes them, and every login that uses the directory stops working. | `test_identity.py::test_leaver…` |
| Password guessing on SSH | SSH is key-only, reachable only from mgmt. Guessing still alerts (Wazuh rule 5712). | `test_siem.py::test_ssh…` |
| Firewall restarts open | It fails closed: if the real rules are missing it loads a baseline that forwards nothing. | `test_network.py::test_firewall_keeps…` |
| Backup stops silently | Metrics after every run. Alerts if failed, older than 26 h, or never ran. | `test_monitoring.py`, `test_backup.py` |
| Over-privileged accounts | Group-based access only. Grafana's directory login is a read-only service account. | `test_identity.py` |
| Secrets leak through Git | All secrets are generated at build time into `.secrets/` (gitignored, 0600). None are in the repo. | `.gitignore`, review |

## Known gaps

Being honest about these is part of the design:

1. **LDAP is plain text inside the office.** Passwords cross the staff → servers
   link unencrypted. Fix: LDAPS with an internal CA (roadmap).
2. **No MFA.** A phished password works. Fix: an identity provider with TOTP or
   WebAuthn in front of web apps (roadmap).
3. **Syslog over UDP** can be lost or spoofed. Fix: TLS syslog or Wazuh agents.
4. **The backup server is a single copy in the same building.** Fix: a second,
   off-site copy (3-2-1 rule) with object lock.
5. **The SIEM sees logs, not endpoints.** No file-integrity or process monitoring
   on workstations. Fix: Wazuh agents on servers and workstations.
6. **Lab limitation: `docker exec` is root on the host.** Anyone with Docker
   access controls everything. That's the equivalent of physical access to the
   server room, and it is out of scope.
7. **Initial passwords are generated, not forced to change.** lldap doesn't
   support "change at next login". The runbook covers delivery.
