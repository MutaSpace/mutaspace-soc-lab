# Prerequisites

This document lists everything that must be installed before the Infrastructure as Code in this
repository can be used.

There are two machines involved and they need different things. Confusing them is the most common
reason a first run fails.

| Machine | Role | What runs there |
|---|---|---|
| **Workstation** | Where you edit code and run commands | OpenTofu, Packer, Ansible, Task, git |
| **Proxmox host** | The hypervisor | `bootstrap-host.sh`, and nothing else from this repo |

Nothing in `packer/`, `tofu/` or `ansible/` runs on the Proxmox host. They all run on the
workstation and talk to Proxmox over the API and SSH.

---

## Workstation Tooling

### Required

These are checked by `scripts/preflight.sh`, which refuses to continue without them.

| Tool | Minimum | Why it is needed |
|---|---|---|
| OpenTofu | **1.12.0** | Provisions the VMs. 1.12 specifically, for `terraform_data` and native state encryption |
| Packer | **1.11.0** | Builds the golden templates |
| Ansible | **2.16** (core) | Everything OpenTofu cannot express: Active Directory, Wazuh, agents |
| `curl` | any | Every host check talks to the Proxmox API |
| `jq` | any | Parses the API's JSON responses |
| `awk` | any | Present on any Linux; listed because the scripts depend on it |
| `git` | any | You already have it if you are reading this |

### Strongly recommended

Not strictly required, but the repository is built around them and skipping them removes real
safety nets.

| Tool | Why |
|---|---|
| **Task** (`go-task`) | The single entrypoint. Every operation in this repo is a `task` command. Without it you are copying long command lines out of `Taskfile.yml` by hand |
| **gitleaks** | Secret scanning. This repository is public and describes a security lab; a leaked API token or WAN address is the realistic failure mode |
| **pre-commit** | Runs gitleaks and the formatters automatically. Without it, the scanning only happens when someone remembers |
| **shellcheck** | The scripts are shell, and shell is easy to get subtly wrong |
| **direnv** | Loads credentials from `.envrc` per directory, so they never live in your shell history or a committed file |

### Optional

| Tool | Why |
|---|---|
| `xorriso` | Only if you build the OPNsense template — it builds the config seed image |
| `gh` | Only for creating pull requests from the command line |
| `yamllint` | Runs via pre-commit anyway; useful standalone when editing playbooks |

---

## Installing on Ubuntu / Debian

Most of these are **not** in the default apt repositories, which is the part that surprises people.

```bash
# --- from apt, straightforward -------------------------------------------------
sudo apt update
sudo apt install -y curl jq gawk git python3 python3-pip pipx shellcheck xorriso direnv

# --- OpenTofu (NOT in apt) -----------------------------------------------------
# The installer script is the maintained path. Verify it before running it.
curl -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-opentofu.sh
less /tmp/install-opentofu.sh          # read it first; it runs as root
chmod +x /tmp/install-opentofu.sh
sudo /tmp/install-opentofu.sh --install-method deb
tofu version                            # expect >= 1.12.0

# --- Packer (HashiCorp apt repo) -----------------------------------------------
wget -O- https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y packer
packer version                          # expect >= 1.11.0

# --- Ansible (pipx keeps it off the system Python) -----------------------------
pipx install --include-deps ansible
pipx inject ansible pywinrm            # REQUIRED: Windows hosts are unreachable without it
ansible --version

# --- Task ----------------------------------------------------------------------
sudo sh -c "$(curl -fsSL https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin
task --version

# --- gitleaks ------------------------------------------------------------------
# Released as a tarball; check the latest version on the releases page first.
GITLEAKS_VERSION=8.30.1
curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
  | sudo tar -xz -C /usr/local/bin gitleaks
gitleaks version

# --- pre-commit ----------------------------------------------------------------
pipx install pre-commit
pre-commit install                      # run once, inside the repo
```

`pywinrm` is called out above because it is the single easiest thing to miss. Ansible installs
fine without it and then fails at the first Windows task with a connection error that does not
mention the missing library.

---

## Ansible Collections

Installed separately from Ansible itself, from `ansible/requirements.yml`:

```bash
task ansible:deps
# or directly:
ansible-galaxy collection install -r ansible/requirements.yml
```

| Collection | Version | Used for |
|---|---|---|
| `microsoft.ad` | 1.12.0 | Forest promotion, domain join, users, OUs |
| `ansible.windows` | 3.7.0 | DNS records, PowerShell, Windows packages |
| `community.general` | >= 10.0.0 | General modules |
| `community.proxmox` | >= 1.0.0 | Proxmox facts |
| `ansible.posix` | >= 1.5.0 | Linux system tasks |

The Wazuh roles are **git-cloned** into `ansible/roles/`, not installed from Galaxy. See
[ansible/README.md](../../ansible/README.md).

---

## Proxmox Host

| Requirement | Value |
|---|---|
| Proxmox VE | **8.x or 9.x**. 7.x is explicitly unsupported by the OpenTofu provider |
| Filesystem | `ext4` (gives `local` + `local-lvm`), matching the documented baseline |
| Network | One physical NIC, reachable from the workstation |
| Access | `root@pam` over SSH for the one-time bootstrap |

Everything else — the API users, the bridges, the snippets storage, the repository configuration —
is created by `scripts/bootstrap-host.sh`. Do not configure them by hand first; the script is
idempotent and will tell you what it skipped.

### The Proxmox version matters more than it looks

Run this before anything else:

```bash
pveversion -v | head -1
```

The version changes the privilege list for the API role, the format of the apt source files
(Proxmox VE 9 is Debian 13 and uses deb822 `.sources`), and the default TLS version. The bootstrap
script detects it and branches, but you should know which path you are on before you start
debugging anything.

---

## Manually Acquired Media

Three of the six templates cannot be built from a URL. This is a real limitation, not an oversight,
and it means **a fresh clone of this repository cannot build every template**.

| Template | Media | Why it is manual |
|---|---|---|
| `tpl-win-server-2022` | Windows Server 2022 Evaluation ISO | Microsoft requires registration; the download is a redirect behind that gate |
| `tpl-win11-client` | Windows 11 Evaluation ISO | Same |
| `tpl-opnsense-267` | OPNsense 26.7 DVD image | Published as `.bz2` and must be decompressed before Proxmox can boot it |
| all Windows builds | `virtio-win-0.1.271.iso` | Freely downloadable, but must be uploaded to the host |

Record each one in [../proxmox/iso-shelf.md](../proxmox/iso-shelf.md) as you acquire it: where it
came from, its SHA256, and where it lives on the host.

The Ubuntu and Kali templates build from a URL and need no manual step.

### The Windows evaluation clock

Windows Server 2022 Evaluation must be **activated over the internet within 10 days** or it shuts
itself down automatically. Because the SOC LAN has no route out until the firewall is running, the
firewall configuration deliberately includes an outbound allow rule for the domain controller.

That rule looks wrong next to an isolated lab. It is intentional, and it is worth showing learners
rather than hiding.

---

## Credentials

No credentials are stored in this repository. They come from environment variables, loaded from a
gitignored `.envrc`:

```bash
cp .envrc.example .envrc
# fill in the values, then:
direnv allow
```

The most common failure in the entire stack is worth stating here rather than leaving it to be
discovered. **Packer and OpenTofu want the same Proxmox credential in different shapes:**

```bash
# Packer wants them SEPARATE
PKR_VAR_proxmox_username="packer@pve!buildtoken"
PKR_VAR_proxmox_token="<uuid>"

# OpenTofu's bpg provider wants ONE concatenated string
PROXMOX_VE_API_TOKEN="terraform@pve!provider=<uuid>"
```

Passing one shape where the other is expected produces a bare `401`, with nothing to indicate that
the credential is correct but formatted wrong. `scripts/preflight.sh` checks both shapes with a
regex precisely to catch this before it wastes an afternoon.

---

## Verifying the Setup

```bash
task preflight
```

This checks every binary and version, both credential shapes, API reachability, the snippets
storage, the bridges, every template VMID, and the ISO shelf. It reports a pass/fail checklist and
exits non-zero on any failure.

To check only the parts that need no Proxmox host — useful while the hypervisor is still being
built:

```bash
task fmt:check     # formatting
task validate      # tofu + packer syntax
task test          # 11 offline assertions against mocked provider data
```

---

## Learning Reflection

The most interesting thing about this list is how much of it is not the tools themselves.

OpenTofu, Packer and Ansible install in a few minutes. What actually costs time is the surrounding
detail: a Python library called `pywinrm` that Ansible does not tell you it needs, a credential
that is correct but formatted for the wrong tool, an ISO that is compressed, an evaluation license
with a ten-day fuse.

This is normal infrastructure work. The headline tools are rarely the hard part, and a setup
document that only lists them is the kind of document that looks complete and leaves you stuck.
