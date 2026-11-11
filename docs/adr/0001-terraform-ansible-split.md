# ADR 0001: Terraform builds, Ansible configures, policy files drive both

**Status:** accepted

## Context

The lab has two kinds of state: *what exists* (networks, machines, addresses,
services) and *how each machine is configured* (firewall rules, users, cron
jobs). Doing both in one tool is possible but awkward: Terraform is poor at
in-machine configuration, and Ansible is poor at tracking what should be destroyed.

The same facts (IP plan, allowed flows, staff list) are needed in several places:
the containers, the firewall, the inventory, the tests.

## Decision

- **Terraform** creates networks, machines, service containers, secrets, and
  writes the Ansible inventory.
- **Ansible** configures inside the machines and is safe to re-run.
- **`policy/network.yml` and `policy/people.yml`** are the single source of truth.
  Terraform reads the IP plan, Ansible reads flows and people, and the tests read both.
- Static service config (Prometheus, Grafana, Wazuh) lives in `config/` and is
  mounted read-only. Changes to Wazuh content force its container to be recreated
  (a hash label), so a rule change can't be silently ignored.

## Consequences

- Changing an IP or adding a flow is a one-line policy change, and the tests
  follow automatically.
- Re-running Terraform with no changes changes nothing (checked: `plan` exits 0).
- Two tools to learn instead of one, but each does what it's good at. This is
  how most teams split it in practice.
