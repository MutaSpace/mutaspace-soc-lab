# tpl-win-server-2022 (VMID 9002)

This directory builds the golden template that `dc-01` is cloned from.

`dc-01` (VMID 102) is the Active Directory domain controller and DNS server for
`mutaspace.local`. This template contains the operating system and the guest agents.
It contains no Active Directory at all — the forest, the `10.10.10.in-addr.arpa`
reverse zone and the lab accounts `test.user` and `lab.user02` are created by Ansible
after the VM exists.

---

## You must supply the install media

**A fresh clone of this repository cannot build this template.** That is not a bug in
the code and it is not something a future commit will fix.

The Windows Server 2022 Evaluation ISO is registration-gated. Microsoft only exposes
it behind an Evaluation Center form, and the download link that form produces is a
short-lived `go.microsoft.com` redirect. There is no stable URL to pin and no
published checksum to verify against, so there is nothing a Packer template can
reference.

Two files have to be uploaded to Proxmox by hand before this build will run:

| File | Where it goes | Notes |
|---|---|---|
| Windows Server 2022 Evaluation ISO | `local:iso/windows-server-2022-eval.iso` | Registration-gated. Rename yours to match, or override `windows_iso_file`. |
| `virtio-win-0.1.271.iso` | `local:iso/virtio-win-0.1.271.iso` | Fetch from the **versioned** `archive-virtio/` directory, not `stable-virtio/` or `latest-virtio/` — those are moving 301 redirects, so "stable" means something different every month. 0.1.285 and 0.1.292 carry a vioscsi read-retry regression; 0.1.271 is the known-good pin. |

Record the SHA256 you compute locally in `docs/proxmox/iso-shelf.md`. The build cannot
be reproducible for anyone else, but it can at least be reproducible for you.

`xorriso` must also be installed **on the machine running Packer** — not on Proxmox.
The `cd_content` seed ISO is built locally and then uploaded, and the failure when
xorriso is missing does not mention xorriso.

---

## How to build

```sh
export PKR_VAR_proxmox_url='https://<LAB_MANAGEMENT_IP>:8006/api2/json'
export PKR_VAR_proxmox_username='packer@pve!buildtoken'
export PKR_VAR_proxmox_token='<token uuid only>'
export PKR_VAR_windows_admin_password='<build-only Administrator password>'

cp packer/common.pkrvars.hcl.example      packer/common.pkrvars.hcl       # shared, gitignored
cp packer/win-server-2022/win-server.pkrvars.hcl.example \
   packer/win-server-2022/win-server.pkrvars.hcl                         # then edit both

packer init     packer/win-server-2022/
packer fmt      -check packer/win-server-2022/
packer validate -var-file=packer/common.pkrvars.hcl \
                -var-file=packer/win-server-2022/win-server.pkrvars.hcl \
                packer/win-server-2022/
packer build    -var-file=packer/common.pkrvars.hcl \
                -var-file=packer/win-server-2022/win-server.pkrvars.hcl \
                packer/win-server-2022/
```

This template uses the repo-wide variable names (`proxmox_url`, `proxmox_username`,
`proxmox_token`, `proxmox_node`, `proxmox_insecure_tls`, `storage_pool`,
`iso_storage_pool`, `build_bridge`, `task_timeout`), so `packer/common.pkrvars.hcl`
configures it exactly as it configures the Linux templates. The per-template var-file
only carries the things that are genuinely specific to this build: the media, the WIM
index and the product key.

The token shape matters. Packer wants the token ID and the secret as **two** values;
OpenTofu's `bpg/proxmox` provider wants **one** concatenated string. Sharing a
variable between them produces a silent `401` that reads like a permissions problem.

`packer validate` needs the connection variables to be set even though it never
contacts Proxmox — the plugin's `Prepare()` rejects an empty URL or token. For a purely
offline check with nothing exported, use `packer validate -syntax-only`.

---

## What this template contains

| Property | Value | Why |
|---|---|---|
| VMID | `9002` | Pinned as a contract. OpenTofu asserts against it at plan time; it never consumes the Packer manifest, because the whole `clone` block is ForceNew and a drifting VMID would destroy `dc-01`. |
| Firmware | `q35` + OVMF + EFI vars disk | Matches `win11-client`, which has no choice. One OpenTofu module clones every VM in the lab; one firmware story is worth the ~50 MB. |
| Disk | `scsi0`, `virtio-scsi-single`, 60 GB, `discard` + `ssd` | `discard`/`ssd` are not tuning. Without them, blocks deleted in the guest are never returned to the LVM-thin pool, and a full thin pool stalls writes across **every** VM on the host. |
| NIC | `virtio` | Not E1000. |
| Guest agents | QEMU guest agent, virtio guest tools (incl. `blnsvr.exe`), Cloudbase-Init | Packer *and* OpenTofu both discover the guest IP through the QEMU guest agent. Without it baked in, every create and every refresh stalls for fifteen minutes. |
| Ballooning | Off (`ballooning_minimum = 0`) | `dc-01` runs `floating = 0`. |

### The VirtIO story, which is the point of this template

The domain controller that was built by hand ran on a **SATA disk and an E1000 NIC**.
That was not a design decision. Windows Setup cannot see a virtio-scsi disk, because
WinPE ships no VirtIO driver — so the installer shows an empty disk list and the only
way forward in a manual install is to fall back to emulated hardware.

Because the lab is now greenfield, the workaround is not needed. `Autounattend.xml`
injects the VirtIO drivers into **windowsPE**, before the disk list is drawn, so Setup
sees the real controller. The template that comes out matches every other VM in the
lab instead of carrying a manual-install compromise forward forever.

### The drive-letter trap

Three CDs are attached during the build (install media, virtio-win, and the generated
`PACKERCD` seed), all on SATA with pinned indices. Drive letters in an answer file are
**positional** — adding or reordering an `additional_iso_files` block shifts `D:`/`E:`/`F:`
and silently breaks driver injection, and the symptom is "Setup found no disks", which
does not point at the cause.

Two defences are in place:

- `Autounattend.xml` lists every plausible letter for every driver directory. Paths
  that do not exist are logged in `setupact.log` and skipped, so the redundancy is free.
- Anything that *can* look itself up does so **by volume label**, not by letter —
  `setup.ps1` finds its own CD by the `PACKERCD` label, and the provisioner scripts
  find the virtio CD by looking for a file on it.

---

## The licensing clock

Windows Server 2022 Evaluation is a **180-day** licence with **six** rearms, and it
must be activated over the internet **within the first 10 days** or it shuts itself
down.

`vmbr1` has no route out until `fw-01` is routing, so **the domain controller has to be
permitted outbound access during its first ten days.** That is a firewall rule that
must exist in the infrastructure code, and it sits in direct tension with the isolated
lab the network design is built around. It is documented rather than hidden because
the tension is real and worth teaching.

**`slmgr /rearm` is deliberately absent from this build.** It looks like the obvious
thing to add — reset the clock so every clone starts fresh — but it decrements the
rearm counter *immediately*, at the moment it runs, not at expiry. In a Packer build
that means one rearm burned per build, and a template rebuilt half a dozen times while
the answer file is being tuned has spent its entire licensing runway before it ever
became a domain controller. There is no recovery except reinstalling from media that
cannot be re-fetched by a script. See `scripts/90-cleanup.ps1`.

---

## Files

| File | What it does |
|---|---|
| `win-server.pkr.hcl` | The build. Variables, source, provisioner order. |
| `cd/Autounattend.xml.pkrtpl` | Windows Setup answer file. VirtIO injection, GPT layout, OOBE, WinRM bootstrap hook. |
| `cd/setup.ps1` | Runs at first logon from `FirstLogonCommands`. Configures WinRM and installs the QEMU guest agent so Packer can connect at all. |
| `scripts/00-virtio-guest-tools.ps1` | Full virtio driver + tools install from the mounted CD. |
| `scripts/10-cloudbase-init.ps1` | Cloudbase-Init install and configuration. |
| `scripts/90-cleanup.ps1` | Credential scrub, log clear, TRIM. Documents why `slmgr /rearm` is absent. |
| `scripts/99-sysprep.ps1` | `sysprep /generalize /oobe /mode:vm /quit`. Must be last. |
| `win-server.pkrvars.hcl.example` | Non-secret variables. Copy and edit; never commit the copy. |

---

## What has not been verified

This template was authored offline, before the Proxmox host existed
(`docs/iac/decisions.md` D-05). The following are reasoned, not tested, and are
expected to need correction on first contact with real hardware:

- **The `boot_command`.** Windows install media prints "Press any key to boot from CD
  or DVD" and gives you roughly five seconds. The spacebar timing here is a guess
  calibrated for an average host; a faster or slower machine moves the window.
- **The WIM index.** `windows_image_index = 2` is the usual position of Standard with
  the Desktop Experience, but the ordering is a property of your ISO. Check it.
- **The Cloudbase-Init download URL.** Never fetched. The script fails loudly with
  instructions rather than skipping the install.
- **Cloudbase-Init's metadata service class for Proxmox's cloud-init drive.** Two
  services are listed so that one is a fallback for the other.
- **Whether `unmount = true` on a pre-existing `iso_file` also deletes it from
  storage.** Confirm `local:iso/virtio-win-0.1.271.iso` survives the first build
  before you delete your local copy.
- **Secure Boot key enrolment.** `efi_pre_enrolled_keys` is true. Proxmox ships the
  2011 Microsoft certificate set, which began expiring in June 2026. If the firmware
  refuses to boot the installer, set it to false.

Nothing in this directory claims to have been tested against hardware. `packer fmt`
and `packer validate` pass; that is a syntax result, not a build result.

---

## Learning Reflection

The interesting thing about this template is how much of it is defence against
*silent* failure rather than against failure.

Almost none of the traps here announce themselves. A missing VirtIO driver does not
say "missing driver" — it says "Setup found no disks". A missing QEMU guest agent does
not say "install the agent" — it says nothing at all for fifteen minutes and then
times out. A reordered ISO device does not say "your drive letters moved" — it
produces the disk error again, from a completely different cause. `slmgr /rearm` does
not fail at all; it quietly spends a licence you will need in six months.

The pattern worth taking away is that in this layer of the stack, the useful skill is
not fixing errors. It is recognising the small number of failure *shapes* — build
hangs, empty disk list, wrong credentials on a clone — and knowing which handful of
causes produce each one. That is why almost every comment in these files explains a
symptom alongside its cause: the cause is easy to fix once you can name it, and nearly
impossible to find if you cannot.

The second thing worth naming is that the honest answer to "is this reproducible?" is
*no, not fully*. The media is gated, the licence expires, and the clock cannot be
reset. Writing that down plainly is better than a template that implies otherwise.
