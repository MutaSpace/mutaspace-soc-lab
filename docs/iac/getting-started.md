# Getting Started

This is the walkthrough from a fresh checkout to a running lab. It is written to be followed
by a person, but the intended way to use it is to open the repo in **Claude Code** and say
"help me set up the lab" — Claude reads this file and walks you through each step, asks you
for your Proxmox details, and does the fiddly parts with you. You do not have to understand
every command; you have to answer questions about your own setup.

If you would rather drive it yourself, every step is here.

---

## Before you start: which path are you on?

**Ask one question first: do working templates already exist on the Proxmox host?**

```
ssh <your-proxmox-host> 'qm list'
```

- If you see `tpl-ubuntu-server-2404`, `tpl-win-server-2022`, and so on — **the templates
  are built.** Skip Parts 1–3 and go straight to **Part 4 (Deploy)**. This is the common
  case for someone joining a host an instructor already prepared, and it saves about an hour.
- If you see none, or an empty list — you are building from scratch. Start at Part 1.

Either way, you will fill in your own connection details (Part 2). Nobody skips that.

---

## What you need first

- A **Proxmox VE 8.x or 9.x host** you can reach over SSH as root. (7.x is not supported.)
- A **workstation** — your laptop — with the tools in
  [prerequisites.md](prerequisites.md). Install those first; it is mostly OpenTofu, Packer,
  Ansible and Task, and none are in the default apt repos.
- For the Windows templates only: the evaluation ISOs, downloaded yourself. They are
  registration-gated and cannot be shared — see [iso-shelf.md](../proxmox/iso-shelf.md).
  You can build everything else without them.

Nothing here runs on the Proxmox host except one bootstrap script. Packer, OpenTofu and
Ansible all run on your workstation and talk to Proxmox over the API and SSH.

---

## Part 1 — Prepare the host (once per host)

`scripts/bootstrap-host.sh` turns a fresh Proxmox install into one this repo can talk to. It
detects your PVE version, fixes the package repositories, creates the two API tokens Packer
and OpenTofu need, enables snippet storage, and creates the lab bridges. It is idempotent —
safe to re-run, and it tells you what it skipped.

```
scp scripts/bootstrap-host.sh root@<your-host>:/root/
ssh root@<your-host> '/root/bootstrap-host.sh --dry-run'   # see what it will do first
ssh root@<your-host> '/root/bootstrap-host.sh'             # then do it
```

**It prints two API token secrets exactly once.** Copy them somewhere safe immediately —
Proxmox cannot show them again. If you lose them, re-run with `--rotate-tokens`.

The script prints the secrets in the two different shapes Packer and OpenTofu each need.
That difference is real and is the single most common wasted afternoon in this stack, so the
script spells it out. You will paste these into `.envrc` in the next part.

---

## Part 2 — Fill in your details (everyone does this)

Three files hold everything specific to your host and workstation. Each has a committed
`.example`. Copy each, then fill it in. **Claude Code can do this with you — tell it your
Proxmox IP, node name and so on, and it will fill in the files and explain each value.**

```
cp .envrc.example .envrc
cp packer/common.pkrvars.hcl.example packer/common.pkrvars.hcl
cp tofu/terraform.tfvars.example tofu/terraform.tfvars
```

These three files are gitignored. They hold your secrets and your real network details, and
they never get committed.

### `.envrc` — secrets

The API tokens from Part 1, an SSH key for the build, and (if you build Windows) a build-time
Administrator password. The file's own comments walk through each one, including the
Packer-vs-OpenTofu token-shape trap. Load it with `direnv allow`, or `source .envrc`.

### `packer/common.pkrvars.hcl` — how Packer reaches Proxmox

Your endpoint URL and node name. Two values here need a real decision, and the file's
comments explain both:

- **`build_bridge`** — leave it `vmbr0` if your management network hands out DHCP and has
  internet (the usual case). Only change it to `vmbr9` if `vmbr0` is a bare WAN uplink.
- **`http_bind_address`** — if your workstation has more than one network interface (Docker,
  a VPN, virtual machines of its own all add interfaces), set this to the address the
  Proxmox host can actually reach you on. If you skip this with multiple interfaces, the
  installer will appear to hang for no reason. If your laptop has one interface, leave it
  empty.

### `tofu/terraform.tfvars` — how the lab is shaped

Your WAN addressing and how many learners. Small file; the comments cover it.

**One value here is not optional: `pve_node`.** `lab.yaml` is committed with the node name of
the machine this lab was developed on, so it is wrong for you, and a wrong node name makes
every API call 404 in a way that looks like a broken token. Set it here (or as
`TF_VAR_pve_node`) rather than editing `lab.yaml` — `lab.yaml` is tracked, so editing it means
a merge conflict every time you pull.

```
hostname            # run on the Proxmox host
pvesh get /nodes    # or ask the API
```

If you get it wrong, `tofu plan` tells you, and lists the node names your host actually has.

### Turn on the pre-commit hook

```
pre-commit install
```

Do this once, now. It runs secret scanning and formatting checks on every commit.

This is not optional hygiene advice — it is here because it was skipped once on the machine
this lab was built on, and a shared password reached a public repository as a direct result.
The scanner was configured correctly the whole time; nothing ran it. See
[decisions.md](decisions.md).

### Rotate the shared credential

The `.example` files ship `changeme` placeholders. Once the lab is up, replace them with
values only you know:

```
./scripts/rotate-lab-credentials.sh
```

It generates one new password, applies it to the firewall, the domain controller, your
`.envrc` and the jumpbox, verifies each, and writes the value to a mode-600 file it tells you
about. Never printed to your terminal.

### Check it before going further

```
task preflight
```

This checks every tool, both token shapes, that Proxmox is reachable, that the bridges and
storage exist, and that any ISOs you need are present. It fails loudly with a specific reason
rather than letting you discover the problem three steps later. Fix whatever it reports
before continuing.

---

## Part 3 — Build the templates (once per host)

Each template installs one OS and converts it to a reusable image. They are independent, so
build the ones you can and skip the rest for now. **Watch the first one; once you trust the
process the rest can run in the background.**

```
task build:ubuntu          # 9000 — the most-used template; build this first
task build:ubuntu-desktop  # 9001
task build:kali            # 9005 — public ISO, no extra steps
```

The two Ubuntu templates and Kali build from public ISOs with no manual media. Ubuntu Server
takes about 15 minutes; the others similar.

**Windows** (9002 Server, 9003 client) needs your own evaluation ISOs on the host first, plus
a small driver ISO the repo builds for you:

```
ssh root@<your-host> '/root/build-winpe-driver-iso.sh'          # for Server 2022
task build:win-server
```

**Windows 11 (9003) needs one extra step first, and it is not optional.** Windows install
media prints

```
Press any key to boot from CD or DVD......
```

and gives you about five seconds. Nothing is there to press the key, so the firmware falls
through to an empty disk and the build sits at "Waiting for WinRM" until it times out. Trying
to have Packer press the key does not work reliably — it was attempted with a 130-second
keystroke barrage and still missed, because a vTPM makes boot timing vary and QEMU drops
keystrokes under load.

The fix removes the prompt instead of racing it. Every Windows ISO contains a second UEFI boot
image that does not prompt, and this script rebuilds your ISO around it:

```
scp scripts/remaster-windows-iso.sh root@<your-host>:/root/
ssh root@<your-host> '/root/remaster-windows-iso.sh --src Win11_<your-iso>.iso'
```

Then point `packer/win11-client/win11-client.pkrvars.hcl` at the `-noprompt.iso` it produced
and run `task build:win11`. Takes about 15 minutes and needs ~18 GB of temporary space on the
host.

The remastered ISO is a derivative of Microsoft evaluation media. It is for **your** host
only — do not copy it to another instructor. Each of you remasters your own.

Windows takes longer — 30–40 minutes including sysprep — and installs onto virtio hardware
using a driver-injection trick the template handles for you. If a Windows build stalls at
"Waiting for WinRM", the usual cause is a missing or too-short build password in `.envrc`;
`task preflight` catches that.

**OPNsense** (9004, the firewall) is the most finicky — its unattended installer is timing
sensitive. Build it last, and expect it to be the one that needs a second try.

Confirm what you have at any point:

```
ssh root@<your-host> 'qm list'    # tpl-* entries with STATUS stopped are your templates
```

You do not need all six to start deploying. Whatever you have built, the next part deploys —
and skips the rest.

---

## Part 4 — Deploy the lab

OpenTofu clones your templates into the real VMs. It reads `lab.yaml`, which describes every
machine, and it refuses to build a VM whose template does not exist yet — so machines whose
templates you have not built are marked `enabled: false` and simply skipped.

```
task lab:plan     # shows exactly what will be created — read it
task lab:up       # creates the VMs
```

As you build more templates, flip the matching machines to `enabled: true` in `lab.yaml` and
run `task lab:up` again. It only adds what is new.

Then configure the guests — Active Directory, DNS, Wazuh, agents, detections — with the
numbered Ansible playbooks, in order:

```
task ansible:deps          # install the collections, once
task ansible:dc-promote    # 10 — build the AD forest first; everything depends on DNS
task ansible:dns-records   # 20
task ansible:domain-join   # 30
task ansible:wazuh-server  # 40
task ansible:wazuh-agents  # 50
task ansible:endpoints     # 60
task ansible:detections    # 70
task ansible:lab-seed      # 90 — the accounts the incident scenarios use
```

Run `task --list` to see everything available.

---

## Part 5 — Classroom lifecycle

Once the lab runs, snapshot each learner's machines so a class can be reset:

```
task learner:snapshot LEARNER=01     # mark "start of class"
task learner:reset    LEARNER=01     # roll back after a session
```

The reset scripts also nudge the clock and the Wazuh agent, because a rolled-back Windows VM
comes up with a stale clock that breaks Kerberos until it resyncs.

---

## When something goes wrong

- **Read [resume-here.md](resume-here.md)** if a build was left half-finished — it records
  where things stood and what to check first.
- **Look at the guest console.** A stalled build almost always shows the reason on screen:
  ```
  ssh root@<host> 'echo "screendump /tmp/x.ppm" | qm monitor <vmid> >/dev/null 2>&1'
  scp root@<host>:/tmp/x.ppm /tmp/ && python3 -c "from PIL import Image; Image.open('/tmp/x.ppm').save('/tmp/x.png')"
  ```
  then open `/tmp/x.png`.
- **A `403 Permission check failed (<path>, <Priv>)`** means the build token is missing a
  privilege. Add it to `build_privs()` in `scripts/bootstrap-host.sh`, copy the script up,
  and re-run it — so it is fixed for good, not just on your host.
- **Ask Claude Code.** This whole repo is written to be diagnosed conversationally. Describe
  the symptom and paste the error; the design docs and the honest failure notes in the
  templates give it plenty to work from.

---

## Learning Reflection

The point of making the repo self-guiding is not laziness. It is that infrastructure setup is
mostly a sequence of small environment-specific decisions — which bridge, which address,
which ISO — and the failures come from getting one of them subtly wrong in a way no error
message names clearly. A walkthrough that a person and an assistant follow together, checking
each step on the real host before moving to the next, is how you catch those while they are
cheap. That is the same habit the lab itself teaches: verify what is actually happening
before you trust that it worked.
