# ADR 0004: The staff roster is the source of truth for accounts

**Status:** accepted

## Context

In small offices, accounts are created by hand and forgotten when people leave.
Ex-employees keeping access is one of the most common findings in audits.

## Decision

- `policy/people.yml` lists every person, their groups, and optionally
  `status: left`.
- Running `make users` makes the directory match the roster **exactly**:
  new people are created, group changes are applied, and anyone not on the roster
  (or marked `left`) is **deleted**. This uses lldap's bootstrap with cleanup.
- Access is by group only. Applications (here Grafana) map groups to roles. Nobody
  gets permissions directly.
- Initial passwords are generated per person and kept in `.secrets/users/`, never
  in the repo.
- Service accounts are listed separately, each with one job and the least access
  (Grafana uses a read-only bind account).

## Consequences

- Offboarding is a reviewed change in Git: who left, when, and who approved it.
- A run against the wrong roster file would delete real accounts. The playbook
  prints who was removed, and the test suite exercises exactly this path.
- People who need temporary access still need a roster entry, which is the point.
