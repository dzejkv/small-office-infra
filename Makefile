SHELL := /bin/bash
.DEFAULT_GOAL := help
TF := terraform -chdir=terraform
ANSIBLE := cd ansible && ansible-playbook
VENV := .venv

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

up: infra configure ## Build and configure the whole office (about 3-5 minutes)
	@echo; echo "Office is up. Grafana: http://127.0.0.1:3000  Prometheus: http://127.0.0.1:9090"
	@echo "Log in to Grafana as any staff member, e.g. riyer (IT) with: make password U=riyer"

infra: ## Create networks, machines and services (Terraform)
	$(TF) init -input=false >/dev/null
	$(TF) apply -auto-approve -input=false

configure: ## Configure everything inside the machines (Ansible)
	$(ANSIBLE) site.yml

users: ## Apply changes in policy/people.yml (joiners, movers, leavers)
	$(ANSIBLE) users.yml

test: $(VENV) ## Run every test against the running lab
	$(VENV)/bin/pytest -v

test-fast: $(VENV) ## Tests that change nothing
	$(VENV)/bin/pytest -v -m "not slow"

demo: ## Simulate attacks and show what the SIEM caught
	./scripts/attack-demo.sh

backup-now: ## Run backups immediately
	docker exec kestrel-files /usr/local/bin/office-backup
	docker exec kestrel-directory /usr/local/bin/office-backup

password: ## Print a staff member's initial password: make password U=riyer
	@test -n "$(U)" || { echo "usage: make password U=<uid>"; exit 1; }
	@cat .secrets/users/$(U); echo

lint: ## Static checks (no lab needed)
	terraform fmt -check -recursive terraform
	$(TF) init -backend=false -input=false >/dev/null && $(TF) validate
	cd ansible && ANSIBLE_INVENTORY=/dev/null ansible-playbook --syntax-check site.yml users.yml

down: ## Destroy the lab (keeps .secrets/ so passwords stay the same)
	$(TF) destroy -auto-approve -input=false

clean: down ## Destroy the lab and delete all generated secrets
	rm -rf .secrets ansible/inventory/hosts.yml

$(VENV): tests/requirements.txt
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q -r tests/requirements.txt
	@touch $(VENV)

.PHONY: help up infra configure users test test-fast demo backup-now password lint down clean
