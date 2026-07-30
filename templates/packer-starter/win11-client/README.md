# tpl-win11-client (VMID 9003)

This directory builds the golden template that `win-client-01` is cloned from — and,
in a classroom, every per-learner endpoint clone in the 200–699 VMID range.

`win-client-01` (VMID 105) is the domain-joined Windows workstation on the SOC LAN. It
is the machine the incident scenarios happen *on*: phishing lands here, credentials get
typed here, and the Sysmon and Wazuh agent telemetry that
`docs/incident-scenarios/` teaches learners to read is generated here.

---

## The licensing timebomb

Read this before planning a semester around this template.

| | Windows Server 2022 Evaluation | **Windows 11 Enterprise Evaluation** |
|---|---|---|
| Initial term | 180 days | **90 days** |
| Rearms | 6 | **2** |
| Total runway | ~1080 days | **~270 days** |
| Convert in place? | Yes — `DISM /Set-Edition` to retail | **No. Rebuild is the only option.** |

`slmgr /rearm` is **not** the escape hatch and is deliberately absent from this build.
It decrements the rearm counter *immediately*, at the moment it runs, not at expiry.
With only two rearms available, putting it in a Packer build spends half the runway
per build — and getting an answer file right usually takes more than two builds. See
`scripts/90-cleanup.ps1`.

**If you have Volume Licensing media, use it.** Point `windows_iso_file` at the VL ISO
and set `product_key` to the Windows 11 Enterprise GVLK. A VL install has no
evaluation clock at all, which converts a recurring 90-day operational problem into a
one-off media problem. The evaluation path exists because not everyone has VL media,
not because it is the better choice.

---

## You must supply the install media

**A fresh clone of this repository cannot build this template.**

The Windows 11 Enterprise Evaluation ISO is registration-gated: Microsoft only exposes
it behind an Evaluation Center form, and the resulting link is a short-lived
`go.microsoft.com` redirect. There is no stable URL to pin and no published checksum,
so there is nothing a Packer template can reference.

| File | Where it goes | Notes |
|---|---|---|
| Windows 11 ISO | `local:iso/windows-11-enterprise-eval.iso` | Registration-gated. Rename yours to match, or override `windows_iso_file`. |
| `virtio-win-0.1.271.iso` | `local:iso/virtio-win-0.1.271.iso` | Fetch from the **versioned** `archive-virtio/` directory, not `stable-virtio/` or `latest-virtio/` — those are moving 301 redirects. 0.1.285 and 0.1.292 carry a vioscsi read-retry regression; 0.1.271 is the known-good pin. |

Record the SHA256 you compute locally in `docs/proxmox/iso-shelf.md`.

`xorriso` must be installed **on the machine running Packer**, not on Proxmox — the
`cd_content` seed ISO is built locally and then uploaded.

---

## How to build

```sh
export PKR_VAR_proxmox_url='https://<LAB_MANAGEMENT_IP>:8006/api2/json'
export PKR_VAR_proxmox_username='packer@pve!buildtoken'
export PKR_VAR_proxmox_token='<token uuid only>'
export PKR_VAR_windows_admin_password='<build-only Administrator password>'

cp packer/common.pkrvars.hcl.example      packer/common.pkrvars.hcl      # shared, gitignored
cp packer/win11-client/win11-client.pkrvars.hcl.example \
   packer/win11-client/win11-client.pkrvars.hcl                          # then edit both

packer init     packer/win11-client/
packer fmt      -check packer/win11-client/
packer validate -var-file=packer/common.pkrvars.hcl \
                -var-file=packer/win11-client/win11-client.pkrvars.hcl \
                packer/win11-client/
packer build    -var-file=packer/common.pkrvars.hcl \
                -var-file=packer/win11-client/win11-client.pkrvars.hcl \
                packer/win11-client/
```

This template uses the repo-wide variable names (`proxmox_url`, `proxmox_username`,
`proxmox_token`, `proxmox_node`, `proxmox_insecure_tls`, `storage_pool`,
`iso_storage_pool`, `build_bridge`, `task_timeout`), so `packer/common.pkrvars.hcl`
configures it exactly as it configures the Linux templates.

`packer validate` needs the connection variables to be set even though it never
contacts Proxmox — the plugin's `Prepare()` rejects an empty URL or token. For a purely
offline check with nothing exported, use `packer validate -syntax-only`.

---

## Why Windows 11 needs more hardware than Server 2022

The server template chose `q35` + OVMF for consistency. Here there is no choice —
Windows 11 will not install otherwise.

| Requirement | How it is satisfied | Notes |
|---|---|---|
| UEFI | `bios = "ovmf"` + `efi_config` | An MBR `DiskConfiguration` will not boot under OVMF. The answer file lays out EFI + MSR + Primary and installs to PartitionID 3. |
| TPM 2.0 | `tpm_config { tpm_version = "v2.0" }` | A **real** vTPM, not a bypass. A TPM device on Proxmox requires the `q35` machine type. |
| Machine type | `machine = "q35"` | Required by the TPM device. Also gives six AHCI ports, which is what makes three SATA CDs possible. |
| Secure Boot | `efi_pre_enrolled_keys = true` | Flip to false if the firmware refuses to boot the installer — the 2011 Microsoft certificate set began expiring in June 2026. |
| CPU | `cpu_type = "host"` | Necessary but **not** sufficient: Windows 11's CPU requirement is a model allow-list, not a feature test. |

### The bypass registry keys, and what each one is actually for

The answer file writes `HKLM\System\Setup\LabConfig` values in the `windowsPE` pass.
It is worth being precise about why, because the usual framing ("bypass the Windows 11
requirements") is misleading here:

| Key | Why it is present |
|---|---|
| `BypassTPMCheck` | **Belt and braces only.** Proxmox provides a real vTPM 2.0. This exists so that a mistyped `tpm_config` produces a working build with a missing device rather than an opaque Setup failure forty minutes into a ninety-minute build. |
| `BypassSecureBootCheck` | Same reasoning — OVMF with pre-enrolled keys satisfies this on its own. |
| `BypassRAMCheck` | **Load-bearing.** Not because 4 GB fails the 4 GB minimum, but because the build sits exactly on the boundary and the check is fussy about how memory is reported. |
| `BypassCPUCheck` | **Load-bearing.** A perfectly capable host CPU that is not on Microsoft's supported-model list fails this. |
| `BypassStorageCheck` | The 64 GB minimum against a 60 GB disk. Sizing the disk to a licence check rather than to the lab's needs would be the tail wagging the dog. |

This is a lab workstation for detection engineering, not a machine Microsoft supports.
Bypassing the checks is the honest configuration; pretending the hardware is something
it is not would be worse.

---

## The trap that only bites client SKUs

`winrm quickconfig` **refuses to run when the network profile is Public** — and Public
is the default for a new network on Windows 11, while Server 2022 defaults to
Domain or Private. The error it produces talks about the firewall and never mentions
the profile.

The symptom is that the WinRM bootstrap appears to succeed, Packer never connects, and
the build hangs until `winrm_timeout` expires two hours later. This is the classic
"works on Server 2022, hangs on Windows 11" failure.

`cd/setup.ps1` forces the profile to Private *before* touching WinRM. That one line is
the entire fix.

---

## The drive-letter trap

Three CDs are attached during the build (install media, virtio-win, and the generated
`PACKERCD` seed), all on SATA with pinned indices. Drive letters in an answer file are
**positional** — adding or reordering an `additional_iso_files` block shifts
`D:`/`E:`/`F:` and silently breaks driver injection. The symptom is "Setup found no
disks", which points nowhere near the cause.

Two defences:

- `Autounattend.xml` lists every plausible letter for every `w11` driver directory.
  Paths that do not exist are logged in `setupact.log` and skipped.
- Anything that *can* look itself up does so **by volume label** — `setup.ps1` finds
  its own CD by the `PACKERCD` label, and the provisioner scripts find the virtio CD
  by looking for a known file on it.

Note the driver directories are `w11`, not `2k22`. Loading a Server 2022 driver into a
Windows 11 install is one of those mistakes that appears to work and then produces
intermittent storage errors months later.

---

## Files

| File | What it does |
|---|---|
| `win11-client.pkr.hcl` | The build. Variables, source, provisioner order. |
| `cd/Autounattend.xml.pkrtpl` | Windows Setup answer file. VirtIO injection, LabConfig bypasses, GPT layout, OOBE, WinRM bootstrap hook. |
| `cd/setup.ps1` | Runs at first logon from `FirstLogonCommands`. Forces the network profile to Private, configures WinRM, installs the QEMU guest agent. |
| `scripts/00-virtio-guest-tools.ps1` | Full virtio driver + tools install from the mounted CD. |
| `scripts/10-cloudbase-init.ps1` | Cloudbase-Init install and configuration. |
| `scripts/90-cleanup.ps1` | Credential scrub, log clear, TRIM. Documents the licensing timebomb and why `slmgr /rearm` is absent. |
| `scripts/99-sysprep.ps1` | `sysprep /generalize /oobe /mode:vm /quit`. Must be last. |
| `win11-client.pkrvars.hcl.example` | Non-secret variables. Copy and edit; never commit the copy. |

The PowerShell scripts are near-copies of the ones in `packer/win-server-2022/`. That
duplication is deliberate: the two templates are independent build units, and a shared
file across sibling Packer directories is fragile because relative paths resolve
against the template folder. Keep them in sync by hand; the differences are commented
where they exist.

---

## What has not been verified

Authored offline, before the Proxmox host existed (`docs/iac/decisions.md` D-05). These
are reasoned, not tested:

- **The `boot_command`.** The "Press any key to boot from CD" window is roughly five
  seconds and moves with host speed.
- **The WIM index.** `1` is right for single-image Enterprise Evaluation media and
  wrong for retail multi-edition media. Check yours.
- **The `LabConfig` `RunSynchronous` placement.** Writing the bypass values from the
  `windowsPE` pass is the widely-used approach, but it was not run here.
- **The Cloudbase-Init download URL**, and its metadata service class for Proxmox's
  cloud-init drive. Two services are listed so one is a fallback for the other.
- **Whether `unmount = true` on a pre-existing `iso_file` also deletes it from
  storage.** Confirm `local:iso/virtio-win-0.1.271.iso` survives the first build.
- **Secure Boot key enrolment** against the expiring 2011 certificate set.

`packer fmt` and `packer validate` pass, and the rendered `Autounattend.xml` was
checked as well-formed XML. Those are syntax results, not build results. Nothing here
claims to have been tested against hardware.

---

## Learning Reflection

The instructive thing about this template is that it is the same build as the server
one, and the differences are almost entirely *licensing and policy*, not engineering.

The technical delta is small: three extra lines for a TPM, four different driver
directory names, and one `Set-NetConnectionProfile` call. Everything else that makes
this template harder is Microsoft policy expressed as an obstacle — a supported-CPU
allow-list that a perfectly good CPU fails, an OOBE that pushes toward a cloud account,
an evaluation licence that is half as long and cannot be converted, and a rearm command
that punishes you for using it early.

That is worth noticing, because it is a real and transferable lesson about building
infrastructure: the hard parts of a build are frequently not the parts that are
technically hard. They are the parts where somebody else's business model is encoded
in the software, and where the failure modes were designed to be inconvenient rather
than informative.

The corresponding professional skill is not cleverness. It is reading the constraints
accurately, writing them down where the next person will find them, and refusing to
pretend a 90-day licence is a reproducible artifact.
