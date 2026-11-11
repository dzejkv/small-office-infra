#!/bin/sh
# Start-up for every lab machine.
set -eu

# 1. Every machine except the firewall sends traffic for other segments, and the
#    internet, through the firewall. Then it gives up CAP_NET_ADMIN for good, so
#    nothing running on it (a compromised service, a user) can change routes and
#    go around the firewall. See docs/adr/0002-docker-networking.md.
if [ -n "${FW_GATEWAY:-}" ] && [ -z "${NODE_CAPS_DROPPED:-}" ]; then
  ip route replace default via "$FW_GATEWAY"
  export NODE_CAPS_DROPPED=1
  exec setpriv --bounding-set -net_admin --inh-caps -net_admin -- "$0" "$@"
fi

# 2. The firewall fails closed: if Ansible's rules are missing (fresh container),
#    load a baseline that forwards nothing.
if [ "${NODE_ROLE:-}" = "firewall" ]; then
  if [ -f /etc/nftables.d/office.nft ]; then
    nft -f /etc/nftables.d/office.nft
  else
    nft -f /etc/nftables.d/baseline.nft
  fi
  if [ -f /etc/ulogd.conf ]; then ulogd -d -c /etc/ulogd.conf; fi
fi

# 3. Logging and scheduled jobs. Ansible replaces these configs and restarts them.
rsyslogd
crond -b -l 8
if [ -f /etc/ssh/sshd_config.d/office.conf ]; then
  /usr/sbin/sshd
fi

exec "$@"
