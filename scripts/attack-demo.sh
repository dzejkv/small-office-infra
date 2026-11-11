#!/usr/bin/env bash
# Simulated attacks against the lab, then a summary of what the SIEM detected.
# Everything happens inside the lab's own networks. Nothing leaves your machine.
set -euo pipefail

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ex() { docker exec "kestrel-$1" sh -c "$2" || true; }

if ! docker inspect -f '{{.State.Running}}' kestrel-wazuh >/dev/null 2>&1; then
  echo "SIEM is not running (enable_siem = false?)"; exit 1
fi
start=$(docker exec kestrel-wazuh sh -c 'wc -l < /var/ossec/logs/alerts/alerts.json')

step "1. A visitor on guest Wi-Fi tries to reach the file server and the directory"
ex guest-01 'for t in 10.20.20.20:22 10.20.20.20:445 10.20.20.10:3890; do nc -z -w1 ${t%:*} ${t#*:} && echo "$t open" || echo "$t blocked"; done'

step "2. Malware on a workstation scans the file server for open ports"
ex ws-02 'for p in 21 22 23 25 80 110 139 143 443 445 3306 3389 5432 5900 8080; do nc -z -w1 10.20.20.20 $p; done; echo "scanned 15 ports, all blocked"'

step "3. Someone on the admin network guesses SSH usernames on the file server"
ex admin 'for u in test oracle postgres guest user ubuntu pi support backup deploy git jenkins ftp mysql; do ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no $u@10.20.20.20 true 2>/dev/null; done; echo "14 attempts, all refused (key-only login)"'

step "4. Ransomware on the file server tries to delete its backups"
# restic exits 0 even when the server refuses, so check what is actually still there.
ex files '. /etc/office-backup/env
  id=$(restic snapshots --json | python3 -c "import json,sys; print(json.load(sys.stdin)[0][\"short_id\"])")
  restic forget "$id" 2>&1 | grep -q "403" && echo "server answered 403 Forbidden"
  restic snapshots --json | grep -q "\"short_id\":\"$id\"" && echo "snapshot $id is still there: backups survived" || echo "snapshot $id DELETED (bad!)"'

step "Waiting for the SIEM to correlate events"
sleep 10

step "Alerts raised during this demo (level 5 and up)"
docker exec kestrel-wazuh sh -c "tail -n +$((start + 1)) /var/ossec/logs/alerts/alerts.json" | python3 -c '
import json, sys, collections
seen = collections.OrderedDict()
for line in sys.stdin:
    try: a = json.loads(line)
    except json.JSONDecodeError: continue
    r = a["rule"]
    if r["level"] < 5: continue
    key = (r["id"], r["description"])
    seen.setdefault(key, [r["level"], 0])[1] += 1
if not seen: print("  (none yet, try again in a few seconds)")
for (rid, desc), (lvl, n) in seen.items():
    print(f"  level {lvl:>2}  rule {rid:>6}  x{n:<3} {desc}")
'
echo
echo "What to do with each alert: docs/runbooks/siem-alert-triage.md"
