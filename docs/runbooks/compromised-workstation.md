# Runbook: suspected compromised workstation

**Owner:** IT admins · **Triggers:** scan alert (100102) from a staff IP, user reports odd behaviour, antivirus alert

## 1. Contain (minutes)

- Disconnect it from the network. In the lab: `docker network disconnect kestrel-staff kestrel-ws-02`.
  In the office: unplug the cable or disable its Wi-Fi.
- Don't switch it off: memory may hold evidence.
- Tell the user not to use it, and give them a spare.

## 2. Scope (first hour)

- Which account was in use? **Disable it now**: set `status: left` temporarily
  in the roster and run `make users`, then restore it after the password reset.
- In the SIEM archives, search for the workstation's IP: what did it connect to,
  what was blocked?
- Staff workstations can only reach LDAP on servers. Check the directory for
  failed or unusual logins from that IP.

## 3. Recover

- Reimage the workstation. In the lab: `terraform -chdir=terraform apply -replace='docker_container.host["ws-02"]'`, then `make configure`.
- Reset the user's password and re-enable their account: delete
  `.secrets/users/<uid>` (so a new password is generated), remove `status: left`,
  run `make users`, and hand over the new password from `make password U=<uid>`.
- If any file share was touched, check snapshots and restore ([restore runbook](restore.md)).

## 4. Learn

- How did it get in? Phishing, a USB stick, a download?
- Write a short incident note: timeline, impact, what stopped it spreading
  (usually: segmentation), what to change.
