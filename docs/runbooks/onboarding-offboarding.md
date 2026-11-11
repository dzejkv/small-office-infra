# Runbook: joiners, movers, leavers

**Owner:** IT admins (`it-admins` group) · **Trigger:** HR notice

All account changes go through `policy/people.yml` and a reviewed commit. Never
create or delete accounts by hand in the directory's web UI: the next run would
undo it.

## Joiner

1. HR confirms start date, department and manager.
2. Add a line to `policy/people.yml`:
   ```yaml
   - { uid: jdoe, first: Jamie, last: Doe, groups: [design] }
   ```
   - `uid`: first initial + surname, lower case, unique.
   - Groups: only what the role needs. `all-staff` is added automatically.
3. Open a pull request. A second IT admin reviews it.
4. After merge: `make users`.
5. Get the initial password with `make password U=jdoe`. Give it to the person
   **in person or by phone**, never by email or chat.
6. On their first day, have them change it (directory web UI, from a workstation
   via IT) and confirm they can log in.

## Mover (changes role)

1. Change their `groups:` in the roster. **Remove** groups they no longer need;
   don't just add the new one.
2. Review, merge, `make users`.
3. Tell them to log out and back in to apps (Grafana updates roles at login).

## Leaver

Do this **on their last working day**, or immediately if the departure is not friendly.

1. Set `status: left` on their entry. Keep the line so there's a record:
   ```yaml
   - { uid: bcarter, first: Ben, last: Carter, groups: [office], status: left }
   ```
2. Review, merge, `make users`. The output lists who was offboarded.
3. Check: `make test` includes a test that the directory contains nobody
   unexpected.
4. Collect their laptop and badge. Reset any shared passwords they knew (Wi-Fi,
   suppliers).
5. Their files on the shares stay. Their manager decides what to keep.

## Checks

- Monthly: compare the roster with HR's list of current staff.
- Any account in the directory that isn't in the roster is deleted by the next
  run. If one appears, find out who created it and why.
