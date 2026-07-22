# Packer Golden Templates

This directory builds the **golden images** every VM in the MutaSpace SOC Lab is cloned from.

A golden image is not "a machine someone finished setting up". It is an installed system with
every unique fact deliberately removed — no machine ID, no SSH host keys, no network address,
no cloud-init state — so that the identity can be handed to it at clone time instead of
inherited from the build. That removal step is the whole game, and it is why every template
here ends with a heavily commented `scripts/cleanup.sh` rather than a simple shutdown.

Templates are built on **`vmbr9`, the build plane**. This lab is greenfield: nothing on
`vmbr1` can reach the internet until `fw-01` is routing, and `fw-01` is itself a VM that has
to be built first. `vmbr9` (10.99.0.0/24, masqueraded by the Proxmox host at 10.99.0.1) is the
only network that exists before the firewall does. OpenTofu re-points each clone's NIC to
`vmbr1` or `vmbr2` afterwards.

---

## 1. Manual prerequisites — read this before anything else

**A fresh clone of this repository cannot build every template.** Three of the six base images
cannot be fetched from a URL, and pretending otherwise would make this directory look more
reproducible than it is. Do these by hand first.

### 1.1 ISOs that must be uploaded by hand

Upload to the Proxmox `local` storage (Datacenter → node → local → ISO Images → Upload), then
reference them from a template as `local:iso/<filename>.iso`. Record every SHA256 in
`docs/proxmox/iso-shelf.md`.

| Artifact | Why it cannot be automated | Notes |
|---|---|---|
| Windows Server 2022 Evaluation | Download is **registration-gated**. Behind the gate the link is a `go.microsoft.com` redirect that expires — there is no stable URL for Packer to pin. | 180-day evaluation. Must be activated over the internet **within 10 days** or it shuts itself down. |
| Windows 11 Evaluation | Same registration gate. | Windows 11 Enterprise Evaluation **cannot be rearmed**, unlike Server. |
| `virtio-win-0.1.271.iso` | The URL *is* public, but the commonly-cited `stable-virtio/` and `latest-virtio/` paths are **moving 301 redirects** — a pin that points at them is not a pin. | Use the versioned `archive-virtio/` path. 0.1.271 is the known-good version: 0.1.285 and 0.1.292 carry a `vioscsi` read-retry regression. |
| OPNsense 26.7 DVD | Published as a **`.bz2`**. Packer cannot boot a compressed image. | Decompress it *before* uploading: `bunzip2 OPNsense-26.7-dvd-amd64.iso.bz2`. |

### 1.2 ISOs that can be fetched by URL — but whose checksums are not pinned yet

Ubuntu Server, Ubuntu Desktop and Kali are fetched by `iso_url`, so nothing has to be uploaded
by hand. Their `iso_checksum` variables ship as **`"none"`**, and that is deliberate rather
than lazy: a checksum written from memory is worse than no checksum, because it looks like
verification and is not.

Packer prints a warning on every build until they are pinned. Pin them:

| Template | Where the authoritative checksum lives |
|---|---|
| `ubuntu-server-2404` | `https://releases.ubuntu.com/24.04/SHA256SUMS` (signed — verify with `SHA256SUMS.gpg`) |
| `ubuntu-desktop-2404` | same file |
| `kali-rolling` | `SHA256SUMS` in the release directory on `https://cdimage.kali.org/` |

⚠️ **The Kali `iso_url` default is a placeholder that has not been checked against the
mirror.** Kali is a rolling distribution: it releases roughly quarterly and `cdimage.kali.org`
removes older images. Open the mirror, take the current
`kali-linux-<version>-installer-amd64.iso` filename and its SHA256, and set both.

⚠️ **Ubuntu point releases rotate too.** `releases.ubuntu.com/24.04/` carries only the
*current* point release, so the pinned 24.04.4 URLs begin returning 404 when 24.04.5 ships.
When that happens, update the URL and the checksum **together**.

### 1.3 Host and workstation prerequisites

| Requirement | Why |
|---|---|
| `vmbr9` exists on the Proxmox host and masquerades out | Every build needs internet, and no lab network has a route until `fw-01` runs. Create it **before** any VM exists on it. ⚠️ Proxmox's own masquerade example uses `10.10.10.1/24` — that is `fw-01`'s LAN address in this lab. Do not copy it. |
| A Proxmox API token for `packer@pve` | See §3. |
| Packer ≥ 1.11 on your workstation | The templates declare `required_version = ">= 1.11.0"`. |
| `xorriso` on the **workstation**, not the host | Templates that build a virtual CD from `cd_files`/`cd_content` (the Windows ones) build that ISO locally. The failure without `xorriso` is confusing and does not name the missing tool. |
| `mkpasswd` (Debian/Ubuntu package `whois`) | Generates the SHA-512 password hash the Linux templates want. |
| An SSH key pair reserved for lab builds | Packer authenticates to the build VM with the key, which is what keeps a plaintext password out of every file in this repository. |

---

## 2. Build order

Build the templates in this order. It is not arbitrary — each step de-risks the next.

| # | Template | VMID | Consumers | Why here |
|---|---|---|---|---|
| 1 | `ubuntu-server-2404` | 9000 | `wazuh-01` (104), `ubuntu-app-01` (106), `nlp-01` (110) | Cheapest to build, most consumed, and the **compatibility test for the whole toolchain**: it is the first time this Packer plugin talks to this Proxmox version. If something is wrong with the API token, the build plane, the storage pool or the plugin, you want to find out here and not halfway through a Windows build. |
| 2 | `ubuntu-desktop-2404` | 9001 | `analyst-01` (103) | Same mechanism as 9000, one new variable (`layerfs_path`). Building it second means any failure is *about* the desktop, because the shared parts are already proven. |
| 3 | `kali-rolling` | 9005 | `kali-01` (108), `untrusted-01` (109) | Different installer entirely (preseed, not autoinstall). Also the first **linked-clone parent**, so it is where the "template must live on the clones' datastore" rule gets exercised. |
| 4 | `win-server-2022` | 9002 | `dc-01` (102) | Needs the manually uploaded media from §1.1. Longest build, most moving parts. |
| 5 | `win11-client` | 9003 | `win-client-01` (105) | Same media problem plus UEFI, Secure Boot and TPM. |
| 6 | `opnsense-267` | 9004 | `fw-01` (100) | The least automatable image in the lab: a timing-sensitive `boot_command` driving an interactive installer. Deliberately last, because everything else can be built and tested without it. |

Templates 4–6 are documented in their own directories. This README's manual-prerequisites
section applies to all six.

### Running a build

The example variable file has to be **copied before it can be used** — Packer requires a var
file to end in `.hcl` or `.json`, so `common.pkrvars.hcl.example` cannot be passed directly:

```bash
cp packer/common.pkrvars.hcl.example packer/common.pkrvars.hcl
$EDITOR packer/common.pkrvars.hcl        # node name, storage pools, bridge
```

`packer/common.pkrvars.hcl` is gitignored. Nothing secret belongs in it — credentials come
from the environment (§3) — but the node name and management network are lab-identifying
details, and keeping the real file untracked means the day someone does paste a token into it,
`git add -A` does not publish it.

Then, from inside a template directory:

```bash
cd packer/ubuntu-server-2404
packer init .
packer fmt -check .
packer validate -var-file=../common.pkrvars.hcl .
packer build   -var-file=../common.pkrvars.hcl .
```

…or from the repository root, which is what `task validate` and `task build:ubuntu` do:

```bash
packer init      packer/ubuntu-server-2404/
packer validate  packer/ubuntu-server-2404/
packer build -var-file=packer/common.pkrvars.hcl packer/ubuntu-server-2404/
```

**Both forms work, and it is worth knowing why that took effort.** Packer resolves paths by two
different rules in the same file:

| Where the path appears | Resolved relative to |
|---|---|
| `file()`, `templatefile()` | the **template directory** |
| provisioner `script =`, post-processor `output =` | the **current working directory** |

So a seed file is referenced bare — `file("http/meta-data")` — and a provisioner script is
referenced with the prefix — `script = "${path.root}/scripts/cleanup.sh"`. Getting that backwards
produces a doubled path (`packer/ubuntu-server-2404/packer/ubuntu-server-2404/http/meta-data`) that
only ever works when you happen to be standing inside the template folder. Three of these templates
had exactly that bug; `-syntax-only` does not evaluate `file()`, so the cheap check never caught it.

`packer init` must be run once per template directory. It resolves the
`github.com/hashicorp/proxmox` plugin at `~> 1.2`. The floor that matters is **1.2.3**:
v1.2.2 silently dropped support for `cpu_type`, which every template here sets.

### Why every credential variable has a placeholder default

Decision D-05 requires `packer validate` to pass with no Proxmox host. The builder's `Prepare()`
step hard-fails on an empty `proxmox_url`, `username` or `token` — and a variable with *no* default
fails even earlier with `Unset variable`. So every template gives those three a deliberately
non-functional default: `https://127.0.0.1:8006/api2/json`, `packer@pve!buildtoken`, and the string
`unset-export-PKR_VAR_proxmox_token`.

None of those is a credential, and none of them is the lab. A build that forgets to export the real
values fails at the first API call with a connection error or a 401 — loudly, immediately, and
against an address that is obviously not a hypervisor.

### Verifying a template by hand

A template that built successfully is not the same as a template that *works*. Smoke-test it
in the scratch VMID range (800–899), which never collides with anything real:

```bash
qm list | grep 9000
qm clone 9000 899 --name smoke-test --full 1
qm set 899 --net0 virtio,bridge=vmbr1
qm start 899
```

The template works if the clone comes up with **its own** hostname, machine ID and SSH host
keys. If it comes up believing it is the build VM, the cleanup script did not do its job — see
§5.

```bash
qm stop 899 && qm destroy 899
```

---

## 3. The credential-shape trap

**Packer and OpenTofu want the same Proxmox API token in two different shapes.** This catches
everyone, it produces a bare `401`, and the `401` says nothing about which half is wrong.

| Tool | Setting | Value |
|---|---|---|
| **Packer** | `username` | `packer@pve!buildtoken` |
| **Packer** | `token` | `<uuid>` |
| **OpenTofu (bpg)** | `api_token` | `terraform@pve!provider=<uuid>` |

Packer wants the token **owner and the secret as two separate values**. The bpg provider wants
**one concatenated string**, owner and secret joined by `=`.

There is a second, quieter version of the same trap in the endpoint URL:

| Tool | Endpoint |
|---|---|
| **Packer** | `https://<LAB_MANAGEMENT_IP>:8006/api2/json` — **with** `/api2/json` |
| **OpenTofu (bpg)** | `https://<LAB_MANAGEMENT_IP>:8006/` — **without** it |

So: **do not share one variable between the two tools.** Two tokens for two users
(`packer@pve` and `terraform@pve`) is also better practice — the audit log then tells you which
tool made a change, and revoking one does not break the other.

### Environment variables

Packer reads any variable named `foo` from the environment variable `PKR_VAR_foo`. Credentials
therefore live in your shell — or in a gitignored `.envrc` loaded by `direnv` — and never in a
file that a careless `git add` can sweep up.

| Environment variable | What it is |
|---|---|
| `PKR_VAR_proxmox_url` | API endpoint **including** `/api2/json`. (Also settable in `common.pkrvars.hcl`.) |
| `PKR_VAR_proxmox_username` | `packer@pve!buildtoken` — the token **owner**, not joined to the secret. |
| `PKR_VAR_proxmox_token` | The token secret, a bare UUID. |
| `PKR_VAR_build_password_hash` | SHA-512 crypt hash for the build account: `mkpasswd -m sha-512`. |
| `PKR_VAR_ssh_public_key` | Contents of the build key pair's `.pub` file. |
| `PKR_VAR_ssh_private_key_file` | **Path** to the matching private key. Packer reads the file itself. |

The password is only ever handled as a hash. It exists so a human can log in at the console
when a build fails — which is exactly when SSH is not available and exactly when you need to
see the installer's screen.

### The API token needs privileges, and nobody publishes the minimum set

Start narrow. Proxmox returns clear errors of the form
`403 Permission check failed (<path>, <Priv>)`, so add privileges empirically as they are
demanded, and record what you ended up with. The lists circulating online are synthesised from
bug reports rather than tested, and the one most often quoted comes from a build that *failed*.

---

## 4. What each directory contains

```
packer/
├── README.md                      this file
├── common.pkrvars.hcl.example     shared, non-secret settings; copy to common.pkrvars.hcl
├── ubuntu-server-2404/            VMID 9000
│   ├── ubuntu-server.pkr.hcl      the build definition
│   ├── http/user-data.pkrtpl.hcl  subiquity autoinstall, nested under `autoinstall:`
│   ├── http/meta-data             EMPTY ON PURPOSE — see below
│   └── scripts/cleanup.sh         the de-subiquity script
├── ubuntu-desktop-2404/           VMID 9001 — same shape, `source: id: ubuntu-desktop`
└── kali-rolling/                  VMID 9005 — debian-installer preseed, not autoinstall
    └── http/preseed.cfg.pkrtpl.hcl
```

**`http/meta-data` is empty and must stay that way — and must stay present.** The Ubuntu
templates seed cloud-init through its **NoCloud** datasource, and NoCloud requires *both*
`user-data` and `meta-data` to exist. A 404 on `meta-data` tells cloud-init "this is not a
NoCloud source", it silently moves on, and the installer stops at an interactive prompt that
nobody is watching. Kali has no such file because a preseed is not NoCloud — debian-installer
fetches exactly one file.

---

## 5. The failure modes worth knowing in advance

Most of these produce a *hang* rather than an error, which is why they are worth reading
before you meet them.

| Symptom | Cause |
|---|---|
| Build sits at **"Waiting for SSH"** for the full timeout, then fails with nothing useful | The plugin defaults `qemu_agent = true` and asks the **guest agent** for the VM's IP. Neither an ISO install nor a cloud image ships `qemu-guest-agent`. Every template here installs it during the OS install for exactly this reason. |
| Installer stops at **"Continue with autoinstall? (yes\|no)"** | The literal token `autoinstall` is missing from the kernel command line. Finding the seed is not enough — subiquity also wants to be told to run unattended. |
| Installer never finds the seed; asks questions instead | GRUB treats `;` as a statement separator, so an unquoted `ds=nocloud-net;s=http://...` is parsed as two commands. The whole `ds=` value must be single-quoted. |
| Seed never arrives, on an otherwise correct template | `{{ .HTTPIP }}` resolved to an interface the guest cannot route back to — a VPN, `docker0` or WSL. Do not fight the interface: deliver the seed as a `cd_files` virtual CD (`cd_label = "cidata"`) instead. |
| The install finishes, the VM reboots, **and the installer starts again** | Boot order preferred the CD. Every template sets `boot = "order=scsi0;ide2"`: on the first boot the disk is empty and SeaBIOS falls through to the ISO; afterwards the disk is bootable and wins. |
| Desktop build fails **before the installer appears** — black screen or an initramfs prompt | `layerfs_path`. The Desktop ISO's live layers are named `minimal.*.squashfs`; the Server ISO's are `ubuntu-server-minimal.*.squashfs`. The value drifts between point releases. |
| Template builds fine, **clones ignore their cloud-init settings** | The cleanup script did not run, or ran incompletely. Subiquity writes `/etc/cloud/cloud.cfg.d/99-installer.cfg` containing `datasource_list: [ None ]` — literally "there is no datasource here". `cloud-init clean` does **not** remove it. This is the single most common golden-image failure and every step of the fix is commented in `scripts/cleanup.sh`. |
| Every clone gets **the same DHCP lease** | `/etc/machine-id` was not reset. Truncate it — do not delete it: netplan derives the DHCP client identifier from it, and a missing file is a different bug from an empty one. |
| A `403 Permission check failed (<path>, <Priv>)` | The API token is missing a privilege. Add that one and retry; see §3. |
| A bare `401` | The credential-shape trap. See §3. |

---

## 6. What has and has not been verified

This repository's documentation standard is that a step is not complete because it was
written — it is complete when it was tested. These templates were authored **offline, before
the Proxmox host existed**, so it is worth being exact about which half is which.

**Verified on a workstation, with the real tools:**

- `packer fmt -check -recursive packer/` is clean.
- `packer init` resolves the `hashicorp/proxmox` plugin at `~> 1.2` for all six templates.
- `packer validate` reports *"The configuration is valid"* for **all six templates, run from the
  repository root, with no var-file, no environment and no Proxmox host** — the only output is the
  expected `iso_checksum = "none"` notice on the three templates that fetch their own ISO.
- Every autoinstall and preseed file renders through `templatefile()` without an unresolved
  substitution, and the two Ubuntu autoinstall files parse as valid YAML with the expected
  keys under `autoinstall:`.
- The OPNsense template's DHCP reservations are derived from `lab.yaml` at validate time and match
  the set OpenTofu computes from the same file, including the three per-learner Windows clients.

**Not verified, and not verifiable without the host:**

- Every `boot_command`. Whether the ISO's bootloader is at the state these keystrokes expect
  can only be found out by watching a real console. The Kali one is the least certain of the
  three: it is the only one driving isolinux rather than GRUB, and Kali is a rolling
  distribution whose media changes.
- Whether `iso_url` for Kali resolves at all — it is a placeholder (§1.2).
- Whether cloud-init on Kali configures networking the way the lab needs. Kali is Debian, and
  cloud-init picks its renderer at runtime — netplan, `eni`, or NetworkManager. Which one wins
  is untested. The documented fallback is to let the clones take DHCP and have Ansible write
  the static addresses; that costs one play and removes an unknown.
- Whether the Desktop template's `99-renderer-networkmanager.yaml` cooperates with cloud-init
  or fights it. Written because a GNOME desktop whose network applet shows nothing is a bad
  first impression for an analyst workstation; flagged because it has never run.
- Whether the Packer plugin works against the Proxmox VE version that ends up installed. The
  plugin's API client is pinned to a commit that predates PVE 9.0 and there is no published
  compatibility statement. Template 1 is the test.

The goal of authoring offline is not to be right on the first build. It is to make the first
build fail for *interesting* reasons rather than for typos.

---

## Learning Reflection

The thing that took longest to understand here was that **a golden image is defined by what you
remove, not by what you install.**

The install is the easy part — it is a package list and an answer file, and if it is wrong the
build fails loudly. The removal is where the difficulty lives, because if it is wrong nothing
fails at all. The template converts, the clones boot, and then two virtual machines quietly
share a DHCP lease, an SSH host key, and a configuration file saying cloud-init has already
run. Every symptom of that points at the network, and none of them points at the image.

The specific trap on Ubuntu is worth naming because it is genuinely counter-intuitive: the
*installer deliberately disables cloud-init* on the system it just installed. That is correct
behaviour for a machine a human installed and will maintain by hand — it stops cloud-init from
undoing their configuration on the next reboot. It is catastrophic for a template. And the
obvious remedy, `cloud-init clean`, does not fix it: `clean` clears cloud-init's *state*, while
the thing that breaks the template is the installer's *configuration*. Running the command that
looks right and getting a template that is still broken is the whole lesson in one step.

The second thing worth writing down is how much of this directory exists because of an
**ordering** problem rather than a technical one. `vmbr9` is not a performance optimisation or
a tidy separation of concerns; it exists because a greenfield lab has no route to the internet
until the firewall is up, and the firewall is a VM that has to be built like everything else.
Recognising that "what has to exist before this can exist?" is a design question — not a
scheduling detail to sort out on the day — changed the shape of this whole directory. It is the
same question a SOC asks about detection coverage, and it has the same failure mode: the gap is
invisible until something needs to cross it.
