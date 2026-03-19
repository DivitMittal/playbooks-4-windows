.PHONY: help deps lint check bootstrap dotfiles packages update verify \
        encrypt-vault decrypt-vault clean facts

ANSIBLE      := ansible-playbook
ANSIBLE_LINT := ansible-lint
GALAXY       := ansible-galaxy
INVENTORY    := inventory/hosts.yml
VAULT_FILE   := inventory/group_vars/all/vault.yml

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

deps: ## Install Python deps and Ansible collections
	pip install -r requirements.txt
	$(GALAXY) collection install -r requirements.yml -p .collections/

lint: ## Run ansible-lint across all playbooks
	$(ANSIBLE_LINT) playbooks/

check: ## Dry-run the full site playbook (no changes applied)
	$(ANSIBLE) playbooks/site.yml --check --diff

bootstrap: ## Bootstrap a fresh Windows machine (WinRM setup + Scoop)
	$(ANSIBLE) playbooks/bootstrap.yml -v

dotfiles: ## Deploy all dotfiles only
	$(ANSIBLE) playbooks/dotfiles.yml --tags dotfiles

packages: ## Install all packages (Scoop + Winget + MSYS2)
	$(ANSIBLE) playbooks/packages.yml --tags packages

update: ## Update all installed packages
	$(ANSIBLE) playbooks/update.yml --tags update

verify: ## Verify desired state without making changes
	$(ANSIBLE) playbooks/verify.yml

site: ## Run the full site playbook
	$(ANSIBLE) playbooks/site.yml -v

site-diff: ## Run full site playbook with diff output
	$(ANSIBLE) playbooks/site.yml --diff

encrypt-vault: ## Encrypt the vault file
	ansible-vault encrypt $(VAULT_FILE)

decrypt-vault: ## Decrypt the vault file (for editing)
	ansible-vault decrypt $(VAULT_FILE)

edit-vault: ## Edit the vault file in place
	ansible-vault edit $(VAULT_FILE)

facts: ## Gather and display facts for all hosts
	ansible -i $(INVENTORY) windows -m setup | less

clean: ## Remove runtime artifacts and cached facts
	rm -rf .facts_cache/ *.retry *.log

init-vault-pass: ## Create .vault_pass (you will be prompted for the password)
	@read -s -p "Enter vault password: " pw && echo "$$pw" > .vault_pass && chmod 600 .vault_pass
	@echo "\n.vault_pass created with mode 600"
