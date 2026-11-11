# ADR 0002: Docker networking for a routed, firewalled lab

**Status:** accepted

## Context

Each zone needs to be a separate network whose only exit is the firewall
container. The obvious choice, Docker networks with `internal: true`, was the
first design.

## What happened

With `internal` networks no traffic reached the firewall at all, not even traffic
the policy allowed. Packet counters on the firewall stayed at zero while the
client had already resolved the firewall's MAC address.

The cause: for an internal network Docker installs host rules that drop any
packet whose destination is outside the network's subnet. With bridge netfilter
(the Docker Desktop default), that includes a packet handed to a *router on the
same bridge*. A routed design is impossible on internal networks.

The test that settled it: two networks, a router container between them, and a
TCP listener, tried with each Docker network option:

| Network type | Routed through firewall | Host can bypass via Docker's gateway |
|---|---|---|
| internal bridge | no | no |
| ipvlan (internal) | no | no |
| normal bridge (any gateway mode) | **yes** | **yes** |

## Decision

Use normal bridges, and close the bypass on the machines themselves:

1. At boot, each machine points its default route at the firewall, then
   **drops `CAP_NET_ADMIN` from its capability bounding set** (`setpriv`), for
   itself and everything it will ever start.
2. Services that Ansible starts (sshd, rsyslog) are started the same way.
3. The firewall is the only container that keeps `CAP_NET_ADMIN`.

A test checks every running process on every machine for the capability.

## Consequences

- Routing works, and no process on a machine can change routes to reach the
  internet through Docker's own gateway.
- An administrator using `docker exec` on the host still can. That's the lab's
  equivalent of physical access to the server room, and it's out of scope.
- In a real office the switch would only connect machines to the firewall, so
  this problem doesn't exist there. The finding is about the lab, but debugging it
  (counters, isolating variables, a minimal reproduction) is the useful part.
