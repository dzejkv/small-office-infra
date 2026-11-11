# Runbook: SIEM alert triage

**Owner:** IT admins · **Trigger:** a Wazuh alert at level 8 or above

Read alerts: `docker exec kestrel-wazuh tail -f /var/ossec/logs/alerts/alerts.json`
All raw events: `/var/ossec/logs/archives/archives.json` on the same container.

## First five minutes, for any alert

1. **What** fired (rule ID), **from where** (`data.srcip`, which zone), **when**.
2. Is it expected? A planned scan, an admin testing? If yes, note it and close it.
3. If not, follow the rule-specific steps below.
4. Write it down: time, alert, what you did, outcome.

## By rule

### 100101: Guest network tried to reach an internal host (level 8)

Guests only ever need the internet, so this is never normal.

1. Which guest IP? Check the Wi-Fi controller for the device name, and who is
   visiting today.
2. One attempt can be a misconfigured laptop. Several, or different ports, means
   someone is looking around.
3. Block the device on the guest Wi-Fi. If it continues, talk to the visitor's host.
4. The firewall already blocked it. No internal impact unless other alerts show otherwise.

### 100102: Possible network scan (level 10)

1. Find the source host. If it's a **workstation**, treat it as possibly
   compromised and follow [compromised workstation](compromised-workstation.md).
2. If it's in **mgmt**, ask the IT admins whether they ran a scan.
3. Search archives for the same source IP in the last 24 hours: what else did it try?

### 5712: SSH brute force (level 10), and 5710/5718

SSH is key-only and reachable only from mgmt, so guessing can't succeed. But it
shows someone with access to the management network is trying.

1. Which mgmt host is the source? Only `admin` should ever SSH.
2. Check who is logged in on that host and what they're doing.
3. If nobody in IT explains it, treat the admin host as compromised: rotate the
   admin SSH key (`rm /root/.ssh/id_ed25519*` on admin, then `make configure`).

### 100111: Backup failed (level 9)

Not an attack in itself, but backups failing is how ransomware incidents become
disasters. Follow [restore runbook → backup alerts](restore.md#backup-alerts).

## Escalate when

- More than one rule fires from the same host within an hour.
- Anything comes from the servers or backup zone.
- You can't explain an alert within 30 minutes.

Escalate to the studio director (Maren Holt, fictional) and the external IT security contact.
