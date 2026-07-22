# MutaSpace SOC Lab — guidance for Claude Code

You are helping someone stand up a Proxmox-based SOC training lab from this repository.
Most people who open this repo are an **instructor setting up the lab for the first time**,
not the person who wrote it. Assume that. Your job is to walk them through it, answer their
questions, and do the fiddly parts for them — not to hand them a wall of commands.

If they say something like "help me set this up" or "get me started", open
**[docs/iac/getting-started.md](docs/iac/getting-started.md)** and walk them through it
one step at a time, doing each step with them and confirming it worked before moving on.

---

## What this lab is

A single Proxmox host runs about ten VMs: a firewall, an Active Directory domain
controller, a Wazuh SIEM, Windows and Linux endpoints, and an isolated attack plane. It is
built as Infrastructure as Code so it can be reset between classes and reproduced on another
host. The full design and reasoning is in **[docs/iac/](docs/iac/)** — `design.md` for the
architecture, `decisions.md` for the choices that override it.

There are two jobs, and an operator may only need the second:

1. **Build the golden templates** — Packer installs each OS once into a reusable template
   (VMIDs 9000–9005). This is a per-host, roughly-one-time job.
2. **Deploy the lab** — OpenTofu clones those templates into the actual VMs, then Ansible
   configures Active Directory, Wazuh, agents and detections.

If working templates already exist on the host (`ssh <host> 'qm list'` shows `tpl-*`
entries), an operator can **skip straight to deployment**. Say so — it saves them an hour.

---

## The three files an operator fills in

Everything host-specific lives in three gitignored files, each with a committed `.example`.
Helping someone fill these in correctly is most of the setup. Walk through them WITH the
operator — ask for their values, don't guess them.

| Copy from | To | Holds |
|---|---|---|
| `.envrc.example` | `.envrc` | API tokens, SSH key, build password — **secrets** |
| `packer/common.pkrvars.hcl.example` | `packer/common.pkrvars.hcl` | Proxmox endpoint, node name, build bridge |
| `tofu/terraform.tfvars.example` | `tofu/terraform.tfvars` | WAN addressing, learner count |

Two values in these are per-environment and cannot be defaulted — get them from the
operator, and read the comments in the `.example` files, which explain the traps:

- **`build_bridge`** — `vmbr0` if their management bridge serves DHCP (usual), `vmbr9`
  if it's a bare WAN uplink. A per-host decision.
- **`http_bind_address`** — the workstation address the build VM can route back to. If
  their workstation has several interfaces (Docker, a VPN, libvirt), this MUST be pinned
  or the installer silently hangs. A per-workstation decision.

---

## Windows licensing — tell the operator this plainly

The Ubuntu, Kali and OPNsense templates are freely redistributable; built ones can be
shared. **The Windows templates cannot be.** Windows Server 2022 and Windows 11 use
Microsoft *evaluation* media, which is registration-gated and whose license does not grant
redistributing a built image. Each operator must download their own eval ISO (see
`docs/proxmox/iso-shelf.md`) and build the Windows templates locally. Never suggest copying
a prebuilt Windows template between hosts. This is not a technical limit; it is the license.

---

## How to work on this host — hard rules

- **Verify on the host; never assume.** Before saying a template exists, a VM is running,
  or a service is up, check it: `ssh <host> 'qm list'`, `qm config <vmid>`,
  `grep '^template: 1' /etc/pve/qemu-server/<vmid>.conf`. This repo's whole credibility is
  that it does not claim results it did not observe. Hold to that.
- **Read the guest console when a build stalls.** It is the single most useful tool:
  ```
  ssh <host> 'echo "screendump /tmp/x.ppm" | qm monitor <vmid> >/dev/null 2>&1'
  scp <host>:/tmp/x.ppm /tmp/ && python3 -c "from PIL import Image; Image.open('/tmp/x.ppm').save('/tmp/x.png')"
  ```
  Look at `/tmp/x.png` before theorising about what went wrong.
- **Kill a build only by its captured PID.** `pkill -x packer` kills every build on the
  machine; `pgrep -f 'packer build.*name'` also matches its own shell. Both have caused
  real damage here. Always `setsid nohup packer build ... & echo $! > pidfile`, then
  `kill "$(cat pidfile)"`.
- **Run long builds detached** so they survive a closed session:
  `setsid nohup packer build ... > log 2>&1 &`.
- **Fix the script, not just the host.** When the host needs a change (a missing API
  privilege, a bridge), make it in `scripts/bootstrap-host.sh` and re-run it, so the next
  operator never hits it. Three missing privileges were found this way; each is now in the
  script.

---

## Secrets policy — this repo is public

- No real credentials, no real management/WAN IP, no physical MAC, in anything committed.
  Only `10.10.10.0/24`, `10.10.20.0/24` and `10.99.0.0/24` — lab-internal ranges the docs
  already publish — are safe to commit. The management network the host actually sits on is
  a secret; it lives only in gitignored files.
- Credentials come from environment variables. Ship `.example` files, never the real ones.
- `gitleaks` runs in pre-commit; do not defeat it. If it flags something in a real config
  file, that is the control working.

---

## Where things are

```
docs/iac/getting-started.md   the walkthrough — START AN OPERATOR HERE
docs/iac/design.md            full architecture and researched decisions
docs/iac/decisions.md         the choices that override design.md
docs/iac/prerequisites.md     tools to install, with commands
docs/iac/resume-here.md       scratch state if a build was left mid-flight
docs/proxmox/iso-shelf.md     the ISOs an operator must acquire by hand
lab.yaml                      every VM, VMID, IP and MAC — the source of truth
packer/                       one template dir per OS (9000–9005)
tofu/                         OpenTofu; reads lab.yaml, has an offline test suite
ansible/                      AD, Wazuh, agents, detections
scripts/bootstrap-host.sh     run ON the host, once, before anything else
Taskfile.yml                  `task --list` for every operation
```

When you change infrastructure, run `tofu -chdir=tofu test` (offline, no host needed) and
`packer validate` before claiming it works. When you change `lab.yaml`, re-run the tests —
they check the whole declared lab regardless of what is switched on.
