# ADR 0005: Wazuh over syslog, no agents (for now)

**Status:** accepted

## Context

A SIEM needs logs from every machine and the firewall. Wazuh can collect them
with its own agent on each machine, or receive standard syslog. The full Wazuh
stack (manager, indexer, dashboard) needs around 4 GB of RAM.

## Decision

- **Wazuh manager only**, receiving syslog on UDP 514 from `10.20.0.0/16` only.
  Its analysis engine (decoders, rules, correlation) is the part that detects things.
- Every machine forwards with **rsyslog** (with an in-memory queue for short outages).
- The firewall logs drops through **nftables → NFLOG → ulogd → syslog**, tagged
  with the source zone, so rules can say "from guest" instead of matching IPs.
- **Custom decoders and rules** in `config/siem/`, IDs 100100-100199, each with a
  MITRE ATT&CK reference where one applies.
- Self-scans of the SIEM container (CIS benchmark, rootcheck, FIM) are off. They
  describe Wazuh's own image, not the office, and produced over 100 irrelevant alerts.
- Every event is also kept in `archives.json` for investigations.

## Consequences

- Light enough to run on a laptop and in CI.
- No dashboard: alerts are read from `alerts.json` (see `make demo`). The indexer
  and dashboard are on the roadmap.
- No endpoint visibility (file integrity, processes) without agents. Listed as a
  known gap in the threat model.
- UDP syslog can be lost or spoofed. Acceptable inside a segmented lab; TLS
  syslog or agents would fix it.
