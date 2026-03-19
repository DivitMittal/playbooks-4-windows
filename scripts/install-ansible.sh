#!/usr/bin/env bash
# install-ansible.sh — Set up the Ansible control node on macOS
# Run once on your Mac before using this project.
#
# Usage:
#   chmod +x scripts/install-ansible.sh
#   ./scripts/install-ansible.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[>>]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*" >&2; exit 1; }

# ── 1. Python 3 ───────────────────────────────────────────────────────────────
log "Checking Python 3..."
if ! command -v python3 &>/dev/null; then
    err "Python 3 not found. Install via: brew install python"
fi
PYTHON=$(command -v python3)
ok "Python: $($PYTHON --version)"

# ── 2. Virtual environment ────────────────────────────────────────────────────
log "Creating Python virtual environment at .venv/"
if [[ ! -d .venv ]]; then
    $PYTHON -m venv .venv
fi
source .venv/bin/activate
ok "venv activated: $VIRTUAL_ENV"

# ── 3. Python dependencies ────────────────────────────────────────────────────
log "Installing Python packages from requirements.txt..."
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt
ok "Python packages installed"

# ── 4. Ansible collections ────────────────────────────────────────────────────
log "Installing Ansible collections from requirements.yml..."
ansible-galaxy collection install -r requirements.yml -p .collections/ --force
ok "Ansible collections installed"

# ── 5. Vault password ─────────────────────────────────────────────────────────
if [[ ! -f .vault_pass ]]; then
    log "Creating .vault_pass..."
    read -rs -p "Enter a vault password: " VAULT_PW
    echo
    echo "$VAULT_PW" > .vault_pass
    chmod 600 .vault_pass
    ok ".vault_pass created (mode 600)"
else
    ok ".vault_pass already exists"
fi

# ── 6. Encrypt vault.yml ──────────────────────────────────────────────────────
VAULT_FILE="inventory/group_vars/all/vault.yml"
if ansible-vault view "$VAULT_FILE" &>/dev/null 2>&1; then
    ok "vault.yml is already encrypted"
else
    log "Encrypting $VAULT_FILE with your vault password..."
    log "Edit it first: fill in your real git email and Windows credentials."
    read -rp "Edit vault.yml now? [y/N] " EDIT_VAULT
    if [[ "${EDIT_VAULT,,}" == "y" ]]; then
        "${EDITOR:-vim}" "$VAULT_FILE"
    fi
    ansible-vault encrypt "$VAULT_FILE"
    ok "$VAULT_FILE encrypted"
fi

# ── 7. Summary ────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Setup complete!"
echo ""
echo " Next steps:"
echo "   1. Edit inventory/hosts.yml — set ansible_host to your Windows IP"
echo "   2. Edit inventory/group_vars/all/vault.yml — set credentials"
echo "      (run: make edit-vault)"
echo "   3. On Windows (as Admin): .\\scripts\\bootstrap-winrm.ps1"
echo "   4. Test connection: ansible windows -m win_ping"
echo "   5. Run: make bootstrap"
echo "   6. Run: make site"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
