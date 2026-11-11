# Roadmap: what I would improve next

Ordered by risk reduced per hour of work.

1. **LDAPS with an internal CA.** Passwords currently cross the network in plain
   text inside the office.
2. **MFA** for web apps: an identity provider (e.g. Authelia or Keycloak) with
   TOTP/WebAuthn in front of Grafana and the directory UI.
3. **Off-site backup copy** (3-2-1): replicate the backup repositories to object
   storage with object lock. Add a monthly restore drill to the calendar.
4. **Wazuh agents** on servers and workstations: file integrity monitoring,
   process and login visibility. TLS for log transport.
5. **Wazuh indexer and dashboard**, and **Alertmanager** sending alerts to email or chat,
   so nobody has to read JSON.
6. **File server access by group**: serve the shares over SMB with LDAP
   authentication, so the department folders actually enforce `finance` vs `design`.
7. **Patch management**: a weekly job that updates packages and reports to
   monitoring; pinned image digests with automated update PRs.
8. **Policy linting in CI**: fail if a flow references a zone that doesn't exist,
   or if anything is allowed *into* backup from outside servers/mgmt.
