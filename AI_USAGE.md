# AI usage

I'm the author of this project and responsible for everything in it. For
transparency, this file records where I used an AI assistant.

**Assistant:** Claude (Anthropic), model Claude Opus 5.5, used through Claude Code.

## How I used it

I set the goal (a fictional 20-person office's complete IT setup as code), and
chose a local Docker lab over AWS, Terraform and Ansible as the tools, and Wazuh
as the SIEM. Claude then drafted the design, the implementation, the tests and
the documentation, and ran and debugged them on my machine. I review, run and
test everything before committing, and I will keep this file updated as the
project changes.

## Files by contribution

Initial version:

| File(s) | AI contribution |
|---|---|
| `policy/network.yml`, `policy/people.yml` | Written by Claude (fictional people and network plan) |
| `terraform/` | First draft written by Claude |
| `ansible/` (playbooks, roles, inventory variables) | First draft written by Claude |
| `images/node/` (Dockerfile, entrypoint, baseline firewall) | First draft written by Claude |
| `config/monitoring/` (Prometheus, alerts, Grafana dashboard and LDAP) | First draft written by Claude |
| `config/siem/local_rules.xml`, `local_decoder.xml` | First draft written by Claude |
| `config/siem/ossec.conf` | Wazuh's default configuration, modified by Claude (changes listed at the top of the file) |
| `tests/`, `pytest.ini` | First draft written by Claude |
| `scripts/attack-demo.sh`, `Makefile`, `.github/workflows/ci.yml` | Written by Claude |
| `docs/` (architecture, threat model, ADRs, runbooks, cloud mapping, roadmap) | First draft written by Claude |
| `README.md` | First draft written by Claude |
| `LICENSE` | Standard MIT text |

Files I change by hand later will be listed here as author-written, with notes on
any part that still comes from the AI draft.

## What was not used

No real company's data, configuration, documents or procedures went into this
repository, and none were given to the AI assistant. All people and the
organisation are fictional.
