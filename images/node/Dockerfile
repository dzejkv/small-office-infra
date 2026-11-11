# One small Linux image for every "machine" in the lab: workstations, servers,
# the firewall, and the network namespaces that third-party services join.
FROM alpine:3.22

RUN apk add --no-cache \
      python3 iproute2 nftables ulogd rsyslog \
      openssh-server openssh-client openldap-clients \
      restic curl netcat-openbsd bash tzdata ca-certificates setpriv tini \
 && mkdir -p /etc/nftables.d /etc/rsyslog.d /var/log

COPY baseline.nft /etc/nftables.d/baseline.nft
COPY rsyslog.conf /etc/rsyslog.conf
COPY entrypoint.sh /usr/local/bin/node-entrypoint
RUN chmod 0755 /usr/local/bin/node-entrypoint

ENTRYPOINT ["/usr/local/bin/node-entrypoint"]
# tini as PID 1 reaps finished processes (sleep alone would leave zombies behind).
CMD ["/sbin/tini", "--", "sleep", "infinity"]
