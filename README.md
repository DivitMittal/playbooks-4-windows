# playbooks-4-windows

Ansible-based Windows dotfile and workstation provisioning. Manages a Windows 10/11 personal
workstation from a macOS/Linux control node over WinRM, or locally via WSL2.

Ground-up rewrite of the bare-git [`sync-windows`](https://github.com/DivitMittal/sync-windows) pattern.

---

## Architecture

```
macOS (ansible-playbook) ──WinRM──▶ Windows machine
        OR
WSL2 on Windows (local) ──────────▶ Windows machine
```

### Role dependency chain

```
bootstrap  ←── scoop  ←── msys2
               (no dep)    winget
windows_settings
dotfiles  ←── windows_settings
```

`meta/main.yml` in each role declares dependencies — Ansible resolves them automatically.

---

## Prerequisites

**Control node** (macOS or WSL2):

- Python 3.10+
- `ansible-core` >= 2.15
- Collections: `ansible.windows`, `community.windows`, `community.general`, `community.crypto`

**Target machine** (Windows):

- Windows 10/11
- WinRM enabled (remote) — run `scripts/bootstrap-winrm.ps1` as Admin first
- Or Ansible running inside WSL2 (local connection, no WinRM needed)

---

## Quickstart

### 1. Set up the control node

```bash
bash scripts/install-ansible.sh   # creates venv, installs pip deps + galaxy collections
```

### 2. Configure vault credentials

```bash
make init-vault-pass              # prompts for vault password → writes .vault_pass (mode 600)
make edit-vault                   # set vault_git_email, vault_windows_user, vault_windows_password
```

### 3. Configure your target host

Edit `inventory/hosts.yml`. Default is WSL2 local execution — no changes needed for that.

For remote WinRM, uncomment and fill in the `winrm` connection block, then on the Windows
machine run as Administrator:

```powershell
.\scripts\bootstrap-winrm.ps1
```

### 4. Install dependencies and run

```bash
make deps        # install Ansible collections
make bootstrap   # bootstrap Scoop + prerequisites on fresh machine
make site        # full provisioning run
```

---

## Repository Layout

```
.
├── ansible.cfg                          # WinRM transport, vault path, fact cache
├── Makefile                             # primary interface — make help
├── requirements.yml                     # Ansible collection dependencies
├── requirements.txt                     # Python dependencies
├── scripts/
│   ├── bootstrap-winrm.ps1              # enable WinRM on Windows target (run as Admin)
│   └── install-ansible.sh               # set up macOS/Linux control node
├── inventory/
│   ├── hosts.yml                        # host definitions + connection vars
│   ├── host_vars/
│   │   └── windows_workstation.yml      # per-machine overrides (is_laptop, extras)
│   └── group_vars/
│       ├── all/
│       │   ├── main.yml                 # feature flags, user identity, XDG dirs
│       │   └── vault.yml                # encrypted secrets (ansible-vault)
│       └── windows/
│           ├── main.yml                 # Windows path variables
│           └── packages.yml             # Scoop / Winget / MSYS2 package lists
├── playbooks/
│   ├── site.yml                         # full provisioning
│   ├── bootstrap.yml                    # fresh machine setup only
│   ├── dotfiles.yml                     # configs only
│   ├── packages.yml                     # packages only
│   ├── update.yml                       # upgrade all packages
│   └── verify.yml                       # read-only state check
└── roles/
    ├── bootstrap/                       # execution policy, PSGallery, Scoop install
    ├── scoop/                           # buckets + package install loop
    ├── winget/                          # GUI apps and Microsoft ecosystem packages
    ├── msys2/                           # pacman packages inside MSYS2 environment
    ├── windows_settings/                # registry, environment vars, PATH, Explorer
    └── dotfiles/                        # static files + Jinja2 templates
```

---

## Roles

| Role | What it does |
|------|-------------|
| `bootstrap` | Sets PowerShell execution policy, NuGet/PSGallery trust, installs Scoop, creates XDG dirs |
| `scoop` | Adds buckets (main → extras → nerd-fonts → versions), installs CLI tools and apps |
| `winget` | Installs GUI apps and Microsoft products that integrate with the Windows Update ecosystem |
| `msys2` | Installs pacman packages inside MSYS2 via `bash.exe -l -c` to load the MSYS2 environment |
| `windows_settings` | Registry tweaks, environment variables, PATH management, Explorer preferences |
| `dotfiles` | Deploys static configs and rendered Jinja2 templates for git, PowerShell, WezTerm, Starship, Firefox |

### `windows_settings` task breakdown

| Task file | Manages |
|-----------|---------|
| `registry.yml` | Developer Mode, telemetry, context menu, taskbar, power plan |
| `environment.yml` | XDG vars, `EDITOR`, `VISUAL`, `SHELL`, `GIT_CONFIG_GLOBAL` |
| `path.yml` | Scoop shims, `.local/bin`, MSYS2 bin — asserts PATH after update |
| `explorer.yml` | Show extensions, hidden files, launch target |

### `dotfiles` managed configs

| Tool | File | Type |
|------|------|------|
| Git | `git/config.j2` | Template — injects `user_name`, `git_email` |
| PowerShell | `Profile.ps1.j2` | Template — editor, shell, paths, feature-gated sections |
| Starship | `starship.toml.j2` | Template — `is_laptop` controls battery module |
| Firefox | `firefox/user.js.j2` | Template — privacy hardening prefs |
| WezTerm | `wezterm/wezterm.lua` + opts/binds/splits/tabline | Static |
| Git | `git/attributes`, `git/ignore` | Static |
| whkd | `whkdrc` | Static |
| Tridactyl | `tridactylrc` | Static |
| Fastfetch | `config.jsonc` | Static |

---

## Feature Flags

All flags live in `inventory/group_vars/all/main.yml`. Set to `false` to skip entire subsystems.

```yaml
feature_scoop:            true
feature_winget:           true
feature_msys2:            true
feature_wezterm:          true
feature_starship:         true
feature_firefox:          true
feature_tridactyl:        true
feature_whkd:             true
feature_kanata:           false   # legacy, off by default
feature_windows_settings: true
feature_git_config:       true
```

Per-host overrides (e.g. `is_laptop: true`) go in `inventory/host_vars/<hostname>.yml`.

---

## Common Workflows

```bash
make help          # list all targets
make deps          # install Python deps + Ansible collections
make bootstrap     # bootstrap fresh machine
make dotfiles      # deploy configs only (fastest iteration loop)
make packages      # install/ensure all packages
make update        # upgrade all packages
make verify        # read-only state check
make site          # full provisioning run
make site-diff     # full run with --diff output
make check         # dry run (--check --diff)
make lint          # ansible-lint all playbooks
make edit-vault    # edit encrypted secrets
```

### Targeted runs with tags

```bash
ansible-playbook playbooks/site.yml --tags git
ansible-playbook playbooks/site.yml --tags wezterm,starship
ansible-playbook playbooks/site.yml --skip-tags firefox
ansible-playbook playbooks/dotfiles.yml --diff
```

---

## Extending the Project

### Add a package

Open `inventory/group_vars/windows/packages.yml` and append to the relevant list:

```yaml
# Scoop
scoop_packages:
  - name: bat
    bucket: main
    category: util

# Winget
winget_packages:
  - id: Microsoft.PowerToys
    source: winget
    category: app

# MSYS2
msys2_packages:
  - fzf
```

Then run `make packages`.

### Add a config file

**Static file:** drop in `roles/dotfiles/files/<tool>/`, add a `win_copy` task in
`roles/dotfiles/tasks/configs.yml`.

**Templated file:** create `roles/dotfiles/templates/<tool>/name.j2`, add a `win_template`
task, expose any new variables in `inventory/group_vars/windows/main.yml`.

### Add a registry setting

Open `roles/windows_settings/tasks/registry.yml` and add a `win_regedit` block.
All registry tasks are idempotent — `win_regedit` only writes when the value differs.

### Add a second machine

1. Add a host entry in `inventory/hosts.yml` under `windows:`
2. Create `inventory/host_vars/<hostname>.yml` with any overrides
3. All existing roles apply automatically (`forks = 10` in `ansible.cfg`)

---

## Secrets / Vault

Secrets are stored in `inventory/group_vars/all/vault.yml`, encrypted with `ansible-vault`.

| Variable | Used as |
|----------|---------|
| `vault_git_email` | aliased to `git_email` in `group_vars/windows/main.yml` |
| `vault_git_signing_key` | aliased to `git_signing_key` |
| `vault_windows_user` | WinRM authentication |
| `vault_windows_password` | WinRM authentication |

The vault password lives in `.vault_pass` (mode 600, gitignored). Never read `vault_*`
variables directly in tasks — always use the clean aliases.

```bash
make init-vault-pass   # create .vault_pass
make edit-vault        # edit secrets
ansible-vault rekey inventory/group_vars/all/vault.yml   # rotate password
```

---

## Variable Precedence

```
host_vars/windows_workstation.yml       (highest)
  group_vars/windows/packages.yml
  group_vars/windows/main.yml
    group_vars/all/vault.yml
    group_vars/all/main.yml
      role defaults/main.yml            (lowest)
```
