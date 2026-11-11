# Runbook: a service is down (`ServiceDown` alert)

**Owner:** IT admins · **Trigger:** Prometheus `ServiceDown` alert, or users report it

The alert names the service. Start with what users notice most.

| Service | Users notice | First check | Usual fix |
|---|---|---|---|
| directory-ldap / directory-web | Nobody can log in to anything | `docker logs --tail 50 kestrel-lldap` | `docker restart kestrel-lldap` |
| files-ssh | Admins can't manage the file server | `docker exec kestrel-files pgrep sshd` | `make configure` (restarts sshd) |
| backup-server | Backups fail tonight | `docker logs --tail 50 kestrel-rest-server` | `docker restart kestrel-rest-server` |
| siem | Nothing visible, but you're blind | `docker exec kestrel-wazuh /var/ossec/bin/wazuh-control status` | `docker restart kestrel-wazuh` |

## If a whole segment is unreachable

It's probably the firewall.

1. `docker exec kestrel-fw nft list chain inet filter forward | head`: are the
   office rules loaded? If you only see a tiny baseline, the firewall restarted
   without its rules (it fails closed on purpose).
2. `make configure` reloads them.
3. Check `docker logs kestrel-fw` for why it restarted.

## Afterwards

- Confirm the alert clears in Prometheus (<http://127.0.0.1:9090/alerts>).
- If it was down for more than 30 minutes during working hours, write a short
  incident note.
