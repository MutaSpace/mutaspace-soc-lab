# packer/win11-client/win11-client.pkr.hcl
#
# WHAT THIS IS
#   The Packer build for golden template VMID 9003, `tpl-win11-client`.
#   Its consumer is `win-client-01` (VMID 105), the domain-joined Windows workstation
#   on the SOC LAN -- and, in a classroom, every per-learner endpoint clone in the
#   200-699 VMID range.
#
# WHY IT EXISTS
#   This is the machine the incident scenarios happen ON. A workstation is where
#   phishing lands, where credentials get typed, where an attacker gets their first
#   foothold, and where Sysmon and the Wazuh agent produce the telemetry that
#   docs/incident-scenarios/ teaches learners to read. Server templates are
#   infrastructure; this one is the subject matter.
#
#   It is also the most-cloned template in the lab, which raises the cost of anything
#   left inside it. See scripts/90-cleanup.ps1.
#
# ############################################################################
# # READ THIS BEFORE YOU TRY TO BUILD: YOU MUST SUPPLY THE INSTALL MEDIA.    #
# #                                                                          #
# # The Windows 11 Enterprise Evaluation ISO is REGISTRATION-GATED. Microsoft #
# # only exposes it behind an Evaluation Center form, and the link it hands   #
# # you is a short-lived `go.microsoft.com` redirect. There is NO stable URL  #
# # and NO stable checksum, so there is nothing a Packer template can pin.    #
# #                                                                          #
# # This file therefore references the media as `local:iso/<name>.iso` -- a   #
# # file the operator uploaded to Proxmox by hand. A FRESH CLONE OF THIS      #
# # REPOSITORY CANNOT BUILD THIS TEMPLATE. That is a property of Microsoft's  #
# # distribution model, not an oversight. See README.md in this directory.    #
# #                                                                          #
# # Do NOT "fix" this by inventing a download URL. Any URL you find for an    #
# # evaluation ISO is either a redirect that expires or someone else's        #
# # unverifiable mirror.                                                     #
# ############################################################################
#
# ############################################################################
# # THE LICENSING TIMEBOMB -- READ THIS BEFORE YOU PLAN A SEMESTER AROUND IT #
# #                                                                          #
# # Windows 11 Enterprise Evaluation is the harshest licence in this lab:    #
# #                                                                          #
# #   * 90 days, not the 180 that Server 2022 Evaluation gets.               #
# #   * TWO rearms maximum. Roughly 270 days of total runway.                #
# #   * It CANNOT be converted in place. Server 2022 Evaluation can become a #
# #     retail install with `DISM /Set-Edition`. This cannot. When the clock  #
# #     runs out the only route forward is a full rebuild from media that     #
# #     cannot be re-fetched by a script.                                    #
# #                                                                          #
# # And `slmgr /rearm` is NOT the escape hatch -- it decrements the counter   #
# # immediately, at the moment it runs. With two rearms available, putting it #
# # in a Packer build burns the runway during template development. It is    #
# # deliberately absent; see scripts/90-cleanup.ps1.                          #
# #                                                                          #
# # IF YOU HAVE VOLUME LICENSING MEDIA, USE IT. Point windows_iso_file at the #
# # VL ISO and set product_key to the Windows 11 Enterprise GVLK. A VL        #
# # install has no evaluation clock at all, which turns a recurring 90-day    #
# # operational problem into a one-off media problem.                        #
# ############################################################################
#
# BUILD PLANE
#   Built on `vmbr9` (10.99.0.0/24, gateway 10.99.0.1 = the Proxmox host, masqueraded).
#   OpenTofu re-points `network_device.bridge` to vmbr1 at clone time; `bridge` is a
#   normal, non-ForceNew attribute on bpg/proxmox, so the switch is free.

packer {
  # Packer 1.11+ is required for the `boot_iso` block used below.
  required_version = ">= 1.11.0"

  required_plugins {
    proxmox = {
      # Floor is effectively 1.2.3: v1.2.2 silently dropped `cpu_type`, which would
      # leave this VM on the legacy `kvm64` model -- and on a Windows 11 guest that is
      # not a performance footnote, it is a failed CPU compatibility check.
      version = "~> 1.2"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ---------------------------------------------------------------------------
# Proxmox connection
#
# SECRETS POLICY (README.md:347): credentials come from environment variables only.
# `env()` is legal in Packer *only* inside a variable default, which is exactly the
# shape we want -- the repo never contains a token.
#
# THE CREDENTIAL SHAPE TRAP: Packer and bpg/proxmox want the SAME API token in
# DIFFERENT shapes and sharing one variable between them silently 401s.
#
#   Packer (here):  username = "packer@pve!buildtoken"   token = "<uuid>"
#   OpenTofu (bpg): api_token = "terraform@pve!provider=<uuid>"   (ONE string)
# ---------------------------------------------------------------------------

# WHY THESE DEFAULTS ARE PLACEHOLDERS AND NOT ""
#   An empty string is not enough. The proxmox builder's Prepare() rejects an empty
#   proxmox_url, username or token with "must be specified", so `packer validate` cannot
#   run offline against defaults of "". Decision D-05 requires it to. These placeholders
#   are deliberately non-functional -- 127.0.0.1 is not the lab and the token is not a
#   credential -- so a build that forgets to export the real values fails at the first
#   API call rather than quietly building somewhere unexpected.

variable "proxmox_url" {
  type        = string
  description = "Proxmox API endpoint, e.g. https://<LAB_MANAGEMENT_IP>:8006/api2/json. Set PKR_VAR_proxmox_url."
  default     = "https://127.0.0.1:8006/api2/json"
}

variable "proxmox_username" {
  type        = string
  description = "Packer-shaped API token ID, e.g. packer@pve!buildtoken. Set PKR_VAR_proxmox_username."
  default     = "packer@pve!buildtoken"
}

variable "proxmox_token" {
  type        = string
  description = "The token UUID on its own -- NOT concatenated onto the ID. Set PKR_VAR_proxmox_token."
  default     = "unset-export-PKR_VAR_proxmox_token"
  sensitive   = true
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name that runs the build."
  default     = "mutaspace-soc-node01"
}

variable "proxmox_insecure_tls" {
  type        = bool
  description = "True while the host still presents its self-signed PVE certificate."
  default     = true
}

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

variable "storage_pool" {
  type        = string
  description = <<-EOT
    Datastore for the template disk, the EFI vars disk and the TPM state volume.

    This MUST be `local-lvm`. Linked clones cannot cross datastores -- pve-docs:
    "It is not possible to change the Target storage for linked clones, because this
    is a storage internal feature." Templates therefore live on the same datastore as
    the VMs cloned from them.
  EOT
  default     = "local-lvm"
}

variable "iso_storage_pool" {
  type        = string
  description = <<-EOT
    Where Packer writes the generated `cd_content` ISO (the Autounattend seed).

    This is NOT optional. An `additional_iso_files` block that uses `cd_files` or
    `cd_content` and omits `iso_storage_pool` makes the plugin's Prepare() hard-fail
    before it ever contacts Proxmox.

    The ISO is built by `xorriso` on the *Packer host*, not on Proxmox. If xorriso is
    missing the failure message does not mention xorriso.
  EOT
  default     = "local"
}

variable "build_bridge" {
  type        = string
  description = "Build-plane bridge. vmbr9 is host-masqueraded and is the only bridge with a route out before fw-01 exists."
  default     = "vmbr9"
}

variable "task_timeout" {
  type        = string
  description = <<-EOT
    How long to wait for a single Proxmox API task.

    The plugin default is ONE MINUTE, which does not cover a multi-gigabyte ISO upload,
    a disk allocation or a template conversion. When it is too low the failure reads as
    an API timeout and gives no hint that the operation itself was fine and merely slow.

    The repo-wide `common.pkrvars.hcl` sets 10m, which is adequate; the local default is
    a little more generous because the Windows media is the largest in the ISO shelf.
  EOT
  default     = "20m"
}

# ---------------------------------------------------------------------------
# Install media -- both operator-supplied
# ---------------------------------------------------------------------------

variable "windows_iso_file" {
  type        = string
  description = <<-EOT
    The Windows 11 ISO, ALREADY UPLOADED to Proxmox by hand.

    Registration-gated if you are using the Enterprise Evaluation. Prefer Volume
    Licensing media if you have it -- see the licensing banner at the top of this file.
    Record the SHA256 you computed locally in docs/proxmox/iso-shelf.md.
  EOT
  default     = "local:iso/windows-11-enterprise-eval.iso"
}

variable "virtio_win_iso_file" {
  type        = string
  description = <<-EOT
    The virtio-win driver ISO, ALSO uploaded by hand.

    Pin 0.1.271. Do not use the `stable-virtio/` or `latest-virtio/` paths -- they are
    moving 301 redirects, so "stable" means something different every month. 0.1.285
    and 0.1.292 carry a vioscsi read-retry/performance regression; 0.1.271 is the
    known-good pin for this lab.
  EOT
  default     = "local:iso/virtio-win-0.1.271.iso"
}

variable "windows_image_index" {
  type        = number
  description = <<-EOT
    WIM index inside the ISO to install.

    Windows 11 Enterprise Evaluation media normally carries a single image at index 1.
    Multi-edition consumer media does not -- a retail Win11 ISO has Home, Home N, Pro,
    Education and several others, and index 1 on that media is Home, which cannot join
    a domain. VERIFY IT before your first build:
      dism /Get-WimInfo /WimFile:D:\sources\install.wim
  EOT
  default     = 1
}

variable "winpe_driver_iso_file" {
  type    = string
  default = "local:iso/virtio-winpe-drivers-w11.iso"

  # A small ISO whose root contains a $WinPEDriver$ folder. Windows Setup scans
  # attached volumes for that folder by name and loads the drivers inside it before
  # the disk list is drawn - no answer file, no drive letter to guess.
  #
  # NOTE THE `-w11` SUFFIX. This is NOT the server template's iso: the driver
  # directories baked inside differ (w11 vs 2k22), and loading a 2k22 storage driver
  # into a Windows 11 install is the mistake that appears to work and then produces
  # intermittent storage errors months later. Build it on the Proxmox host with:
  #   build-winpe-driver-iso.sh --variant w11 --out .../virtio-winpe-drivers-w11.iso
  # It is derived from the pinned virtio-win ISO, so it is a build artifact.
  description = "ISO containing a root $WinPEDriver$ folder built from the w11 virtio drivers. Built by build-winpe-driver-iso.sh --variant w11."
}

variable "virtio_cd_letter" {
  type    = string
  default = "E"

  # Drive letter WinPE assigns to the virtio-win CD.
  #
  # X: is WinPE's own ramdisk and optical drives start at D:. This template attaches
  # four CDs in a fixed order - sata0 install media, sata1 virtio-win, sata2 the
  # answer-file seed, sata3 the $WinPEDriver$ volume - so virtio-win is E:.
  #
  # This is vestigial now that drivers arrive via $WinPEDriver$ rather than by a
  # drive-letter-positional answer-file path. It is kept only so this template stays
  # diffable against the server one; nothing in the answer file consumes it.
  description = "Drive letter of the virtio-win CD inside WinPE. Determined by CD attach order, not guessed."
}

variable "product_key" {
  type        = string
  description = <<-EOT
    Leave empty for evaluation media (evaluation ISOs carry their own edition and
    reject a key).

    Set the Windows 11 Enterprise GVLK here if you are building from Volume Licensing
    media. That is the recommended path -- it removes the 90-day clock entirely. Empty
    means the <ProductKey> element is omitted from the answer file.
  EOT
  default     = ""
}

# ---------------------------------------------------------------------------
# Build credentials
# ---------------------------------------------------------------------------

variable "windows_admin_password" {
  type        = string
  description = <<-EOT
    Password for the built-in local Administrator DURING THE BUILD ONLY. It is used
    for the Autounattend AdministratorPassword, the OOBE AutoLogon, and Packer's WinRM
    communicator.

    Set PKR_VAR_windows_admin_password in your shell. Never commit it.

    This one matters more than its server-side twin: this template is cloned for every
    learner endpoint, so a build password that survives into the image is a build
    password every learner has local Administrator with. sysprep /generalize plus
    scripts/90-cleanup.ps1 remove it; rotate it from Ansible anyway.
  EOT
  # No default value and no env() call: Packer already reads any variable `foo`
  # from `PKR_VAR_foo`, so `export PKR_VAR_windows_admin_password=...` is all that is
  # needed. The empty default is what keeps `packer validate` green offline.
  default   = ""
  sensitive = true

  validation {
    # Deliberately permits "" so `packer validate` stays green with no environment
    # set -- offline validation is a first-class requirement (decisions.md D-05).
    condition     = var.windows_admin_password == "" || length(var.windows_admin_password) >= 12
    error_message = "The windows_admin_password variable must be at least 12 characters. Set PKR_VAR_windows_admin_password in your environment."
  }
}

# ---------------------------------------------------------------------------
# Guest agents and firmware
# ---------------------------------------------------------------------------

variable "cloudbase_init_msi_url" {
  type        = string
  description = <<-EOT
    Download URL for the Cloudbase-Init installer.

    ⚠️ UNVERIFIED: this template was authored offline, so the URL below was never
    fetched. If it 404s, download CloudbaseInitSetup_1_1_8_x64.msi by hand, host it
    somewhere the build plane can reach, and override this variable.
    scripts/10-cloudbase-init.ps1 fails loudly rather than silently skipping.
  EOT
  default     = "https://www.cloudbase.it/downloads/CloudbaseInitSetup_1_1_8_x64.msi"
}

variable "efi_pre_enrolled_keys" {
  type        = bool
  description = <<-EOT
    Pre-enrol Microsoft's Secure Boot keys into the OVMF variable store.

    True by default because Secure Boot is one of the three things Windows 11 actually
    checks for, and because a workstation with Secure Boot on is what a real endpoint
    looks like. If the firmware refuses to boot the installer, set this to false: PVE
    ships the 2011 Microsoft certificate set, which began expiring in June 2026, and
    full enrolment of the 2023 set including the KEK needs qemu-server >= 9.1.5. The
    Packer plugin exposes only this boolean and cannot choose WHICH certificates.

    The Autounattend also sets BypassSecureBootCheck, so turning this off does not
    block the install -- it only makes the resulting machine less realistic.
  EOT
  default     = true
}

# ---------------------------------------------------------------------------
# VirtIO driver injection -- via $WinPEDriver$, exactly as the server template
#
# WHY NOT AN ANSWER-FILE MECHANISM. Both were tried first on the server media and
# neither works (the full history is in packer/win-server-2022/win-server.pkr.hcl):
#
#   Microsoft-Windows-PnpCustomizationsWinPE  -> Setup aborts at "Setup is starting"
#     with "Windows could not apply the Windows PE bootstrap setting specified in the
#     unattend answer file", even with every path verified to exist.
#   RunSynchronous drvload  -> Setup reaches the disk list and still refuses the disk:
#     drvload loads a driver into memory but does not STAGE it for injection into the
#     installed OS, and a boot-critical controller that is not staged is rejected.
#
# WHAT WORKS. Windows Setup scans the ROOT of every attached volume for a folder named
# exactly `$WinPEDriver$`, loads what it finds AND schedules it for injection into the
# installed OS -- the half drvload could not do. No answer file to reject it, no drive
# letter to guess. build-winpe-driver-iso.sh --variant w11 builds that volume from the
# w11 virtio driver directories; this template attaches it as sata3.
#
# The w11 (not 2k22) directories matter: a Server 2022 storage driver in a Windows 11
# install appears to work and then produces intermittent storage errors months later.
# ---------------------------------------------------------------------------

locals {
  # Contract values. Pinned, not computed. tofu asserts against them at plan time;
  # it never consumes the Packer manifest, because the whole bpg `clone` block is
  # ForceNew and a drifting VMID would destroy every downstream VM.
  vm_id         = 9003
  template_name = "tpl-win11-client"

  seed_cd_label = "PACKERCD"

  # w11 = the Windows 11 driver directories on the virtio-win ISO. These describe what
  # the $WinPEDriver$ volume must contain; they are no longer referenced by the answer
  # file (see the header above), but are kept -- like the server template's 2k22 list --
  # so the two templates stay diffable and the intent stays documented.
  virtio_driver_dirs = [
    "vioscsi\\w11\\amd64",  # storage controller -- without this, no disks are found
    "NetKVM\\w11\\amd64",   # network -- without this, no WinRM and the build hangs
    "Balloon\\w11\\amd64",  # ballooning driver (blnsvr.exe comes later, from the MSI)
    "vioserial\\w11\\amd64" # virtio-serial, the transport the QEMU guest agent uses
  ]

  # NARROWED FROM ["D","E","F","G"] on 2026-07-22 to match the server template. When the
  # server still injected drivers through the answer file, guessing four letters x four
  # directories produced 16 PathAndCredentials entries and windowsPE refused the whole
  # PnpCustomizationsWinPE component -- guessing wide was the failure, not a free safety
  # net. Vestigial now that drivers come from $WinPEDriver$; kept for diffability.
  candidate_cd_letters = [var.virtio_cd_letter]

  # The .inf inside each directory above, paired positionally. Vestigial, as above.
  virtio_inf_names = [
    "vioscsi.inf",
    "netkvm.inf",
    "balloon.inf",
    "vioser.inf",
  ]

  virtio_driver_paths = flatten([
    for letter in local.candidate_cd_letters : [
      for dir in local.virtio_driver_dirs : "${letter}:\\${dir}"
    ]
  ])

  # The password is dropped into XML text nodes, so the XML metacharacters have to be
  # escaped or a password containing `&` produces an answer file that is not
  # well-formed. Windows Setup's response to malformed XML is to ignore the file
  # entirely and show the interactive installer -- i.e. the build hangs and the reason
  # is invisible.
  admin_password_xml = replace(replace(replace(var.windows_admin_password, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")

  autounattend = templatefile("cd/Autounattend.xml.pkrtpl", {
    admin_password = local.admin_password_xml
    image_index    = var.windows_image_index
    product_key    = var.product_key
    # PnpCustomizationsWinPE is not used - drivers arrive via $WinPEDriver$. These are
    # passed for parity with the server template's templatefile call; the answer file
    # no longer references them.
    driver_dirs   = local.virtio_driver_dirs
    inf_names     = local.virtio_inf_names
    virtio_cd     = var.virtio_cd_letter
    seed_cd_label = local.seed_cd_label
    computer_name = "PKR-WIN11-TPL"
  })
}

source "proxmox-iso" "win11-client" {
  # --- connection -----------------------------------------------------------
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = var.proxmox_insecure_tls
  node                     = var.proxmox_node

  task_timeout = var.task_timeout

  # --- identity -------------------------------------------------------------
  vm_id                = local.vm_id
  vm_name              = local.template_name
  template_name        = local.template_name
  template_description = "Windows 11 golden template. q35 + OVMF + vTPM 2.0, virtio-scsi-single + virtio NIC, QEMU guest agent, Cloudbase-Init. Built by Packer; do not edit by hand. Consumer: win-client-01 (105) and learner endpoint clones. NOTE: evaluation media expires after 90 days and cannot be converted in place."
  tags                 = "template;windows;mutaspace"

  # --- firmware -------------------------------------------------------------
  #
  # NOT NEGOTIABLE ON WINDOWS 11, unlike on the server template where q35 + OVMF was a
  # consistency choice. Windows 11 requires UEFI and a TPM 2.0, and a TPM device on
  # Proxmox requires the q35 machine type. i440fx + SeaBIOS cannot install this OS.
  bios    = "ovmf"
  machine = "q35"

  # Boot the DISK first, then the install CD — and DELIBERATELY LEAVE net0 OUT.
  # THIS IS THE FIX for the boot-catch problem that blocked this template. FOUND
  # 2026-07-23.
  #
  # With the default boot order (which includes net0), a missed "Press any key to
  # boot from CD" sends OVMF into a PXE-v4 -> PXE-v6 -> HTTP-v4 -> HTTP-v6 fall-
  # through, each with a multi-second timeout, so the CD prompt only comes back
  # around once every ~50 s. Combined with this VM's slow, variable vTPM POST
  # (~40-70 s, measured), no bounded keystroke burst could reliably land in the
  # ~6 s window — the server template has no vTPM, POSTs fast, and catches the
  # prompt with five spacebars, which is why it never needed this.
  #
  # Omitting net0 from the boot order removes the PXE detour entirely. Now the
  # loop is scsi0 (empty on first boot, fails instantly) -> sata0 CD (the ~5 s
  # "press any key") -> repeat every few seconds. The prompt is up almost
  # continuously after POST, so the spacebar burst below catches it. net0 is still
  # present and fully functional for the OS and for WinRM — it is just not a
  # firmware boot device. After install, scsi0 is bootable and wins on its own.
  boot = "order=scsi0;sata0"

  # Proxmox ostype: win11 covers "Windows 11/2022/2025".
  #
  # This also matters on the OpenTofu side, where ostype MUST be set before cipassword
  # or PVE crypt-hashes the password and Cloudbase-Init injects the hash as plaintext.
  os = "win11"

  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = var.efi_pre_enrolled_keys
  }

  # A REAL vTPM 2.0, not a bypass.
  #
  # The Autounattend does set BypassTPMCheck, but that is belt and braces for a
  # mistyped config -- the device below is genuine. It matters beyond passing Setup:
  # BitLocker, Credential Guard and Windows Hello all bind to a TPM, and a workstation
  # without one cannot demonstrate any of the credential-protection behaviour a SOC
  # analyst is expected to reason about.
  #
  # This adds a small state volume that every clone inherits. That is the cost, and it
  # is worth it.
  tpm_config {
    tpm_storage_pool = var.storage_pool
    tpm_version      = "v2.0"
  }

  # --- CPU / memory ---------------------------------------------------------
  #
  # cpu_type = "host" passes the physical CPU through. The plugin default kvm64 is a
  # 2003-era feature set that Windows 11 rejects outright.
  #
  # Note that "host" is necessary but not sufficient: Windows 11's CPU requirement is a
  # model ALLOW-LIST, not a feature test, so a perfectly capable host CPU can still
  # fail it. That is what BypassCPUCheck in the answer file is for.
  cpu_type = "host"
  sockets  = 1
  cores    = 2
  memory   = 4096
  numa     = false

  # Ballooning off in the template. win-client-01 runs floating = 0; per-learner clones
  # may enable it in OpenTofu, which is why blnsvr.exe is installed regardless.
  ballooning_minimum = 0

  # --- storage --------------------------------------------------------------
  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    disk_size    = "64G"
    storage_pool = var.storage_pool

    # raw, not qcow2: local-lvm is LVM-thin and does not support qcow2.
    format = "raw"

    # io_thread requires virtio-scsi-single, which is why the two go together.
    io_thread  = true
    cache_mode = "none"

    # discard + ssd are not a micro-optimisation. Without discard, blocks deleted
    # inside the guest are never returned to the LVM-thin pool, and a full thin pool
    # stalls or corrupts writes across EVERY VM on the host. This template is the most
    # cloned one in the lab, so it is also the biggest contributor to that risk.
    discard = true
    ssd     = true
  }

  # --- network --------------------------------------------------------------
  network_adapters {
    model  = "virtio"
    bridge = var.build_bridge

    # The per-NIC Proxmox firewall inserts an fwbr/fwln/fwpr veth chain. It is noise on
    # a build-plane NIC. Real filtering is fw-01's job.
    firewall = false

    # No mac_address here on purpose. win-client-01's MAC is pinned by OpenTofu to
    # BC:24:11:10:10:51, derived from its address, and the OPNsense DHCP reservation
    # that keeps it on 10.10.10.51 across rebuilds is templated from the same map. A
    # MAC baked into a template would be shared by every clone and every reservation
    # would collide.
  }

  # --- cloud-init drive -----------------------------------------------------
  #
  # Deliberately NOT set. bpg/proxmox creates and owns the cloud-init drive through its
  # `initialization` block at clone time. Cloudbase-Init is installed INSIDE the guest
  # by scripts/10-cloudbase-init.ps1 -- that is the agent, not the drive.

  # --- boot media -----------------------------------------------------------
  #
  # FOUR CDs, all on SATA, indices pinned.
  #
  # Why SATA and not IDE: q35 exposes only a stub IDE controller (ide0/ide2), which is
  # not enough ports for four CDs. q35's AHCI controller gives six (sata0-sata5), and
  # WinPE has a native AHCI driver.
  #
  # Why the CDs are NOT on the virtio-scsi controller: chicken and egg. WinPE would
  # need the vioscsi driver to read the CD that contains the vioscsi driver.
  #
  # Why the indices are explicit: the $WinPEDriver$ mechanism does not care about drive
  # letters, but the seed ISO's setup.ps1 finds itself by volume label and the whole
  # set stays easier to reason about pinned.

  boot_iso {
    type     = "sata"
    index    = 0
    iso_file = var.windows_iso_file

    # Detach before the template is created. NOTE the key is `unmount`, not
    # `unmount_iso` -- the latter was the deprecated top-level field.
    unmount = true
  }

  # The $WinPEDriver$ volume. Windows Setup scans the root of every attached volume for
  # a folder with this exact name and drvloads whatever it finds AND stages it for
  # injection, BEFORE it enumerates storage for the disk list. That timing -- earlier
  # than RunSynchronous -- and the staging step are the whole point. It does not go
  # through the answer file, which is what rejected PnpCustomizationsWinPE.
  #
  # Built on the Proxmox host by build-winpe-driver-iso.sh --variant w11: ~30 MB of the
  # four w11 drivers WinPE actually needs, rather than the full 693 MB virtio ISO.
  additional_iso_files {
    type     = "sata"
    index    = 3
    iso_file = var.winpe_driver_iso_file
    unmount  = true
  }

  additional_iso_files {
    type     = "sata"
    index    = 1
    iso_file = var.virtio_win_iso_file
    unmount  = true

    # ⚠️ UNVERIFIED OFFLINE: `unmount` definitely detaches the drive. Whether the
    # plugin also deletes an ISO it did not upload could not be tested without a host.
    # On the first real build, confirm local:iso/virtio-win-*.iso still exists.
  }

  additional_iso_files {
    type  = "sata"
    index = 2

    # Windows Setup scans the root of every removable, read-only volume for a file
    # named exactly `Autounattend.xml`.
    #
    # It is NOT delivered on a floppy -- proxmox-iso has no floppy_files/floppy_dirs at
    # all. Any tutorial using A:\autounattend.xml is written for the qemu, virtualbox
    # or hyperv builders.
    #
    # The label is PACKERCD rather than "cidata": cidata is the NoCloud label
    # cloud-init looks for, and this is not a NoCloud seed. What matters is that
    # setup.ps1 can find its own volume by LABEL instead of guessing a letter.
    cd_label = local.seed_cd_label
    cd_content = {
      "Autounattend.xml" = local.autounattend
      "setup.ps1"        = file("cd/setup.ps1")
    }

    # Mandatory for cd_content/cd_files. Omitting it hard-fails in Prepare().
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  # --- boot ---------------------------------------------------------------
  #
  # ⚠️ TIMING-SENSITIVE AND UNVERIFIABLE OFFLINE (decisions.md D-05).
  #
  # Windows install media prints "Press any key to boot from CD or DVD..." and gives
  # you about five seconds. Miss it and the firmware falls through to an empty disk,
  # which under OVMF usually means the UEFI shell and a build that hangs until
  # winrm_timeout.
  #
  # Several spacebars over several seconds beats one perfectly-timed keystroke. The
  # extra presses land in an unattended Setup UI where nothing waits for input.
  #
  # RE-TUNED 2026-07-22 ON FIRST CONTACT WITH THE REAL HOST -- AND STILL AN OPEN ISSUE.
  # Read this before you touch the timing OR conclude the template works.
  #
  # THE CD-PROMPT IS A MOVING TARGET ON THIS OS. VM 9002 (server) and 9003 (this one)
  # THE BOOT RACE IS GONE. THERE IS NO boot_command ANY MORE.
  #
  # This used to be the most fragile thing in the repository: a 55-spacebar burst
  # followed by 30 repeated <enter>s, spanning ~130 seconds, trying to catch two
  # separate prompts whose timing varies with host load. It is worth recording
  # what it was fighting, because the reasoning is instructive and the conclusion
  # is that the whole fight was avoidable.
  #
  # WHAT MADE IT HARD
  #   * 9003 has a vTPM (mandatory for Win11). Measured boot makes POST duration
  #     wildly variable - observed ~45 s on an idle host to >120 s under load.
  #   * On this OVMF, SPACEBAR at the "Press any key to boot from CD or DVD"
  #     prompt is intercepted as the boot-menu HOTKEY rather than consumed as
  #     "any key", so a spacebar burst parked the VM in the boot-device menu
  #     forever and Packer waited out its full 2 h winrm_timeout.
  #   * Steering the menu (down, enter) then left a SECOND ~5 s window - the
  #     Windows "press any key" prompt - at a variable delay.
  #   * QEMU's sendkey drops keystrokes under load, so more keys is not more
  #     reliable, just louder guessing.
  #
  # WHAT ACTUALLY FIXED IT
  #   scripts/remaster-windows-iso.sh rebuilds the install ISO with
  #   efi/microsoft/boot/efisys_noprompt.bin as the UEFI El Torito boot image
  #   instead of efisys.bin. Microsoft ships both inside every Windows ISO; the
  #   second one boots without prompting at all.
  #
  #   With no prompt, and with `boot = "order=scsi0;sata0"` above, the sequence is
  #   fully deterministic and needs no input whatsoever:
  #
  #     fresh build  -> scsi0 is an empty disk with no boot sector
  #                  -> firmware falls through to sata0, the install DVD
  #                  -> efisys_noprompt boots WinPE immediately
  #     after install -> scsi0 is bootable and wins, so the installer does not loop
  #
  #   Deleting a race beats winning it. If you ever see
  #   "Press any key to boot from CD or DVD" on this template again, the pkrvars
  #   file is pointing at the ORIGINAL ISO rather than the remastered one.
  #
  # boot_wait still matters: it is how long Packer waits before it starts looking
  # for the communicator, and the install has to get going first.
  boot_wait    = "20s"
  boot_command = []

  # --- communicator ---------------------------------------------------------
  #
  # Plain HTTP WinRM on 5985, on an isolated build plane that exists for the length of
  # one build. sysprep /generalize resets the listener and credential state at the end;
  # the finished VMs are managed by Ansible over Kerberos, not over this.
  #
  # ⚠️ CLIENT-SKU GOTCHA: `winrm quickconfig` refuses to run when the network profile
  # is Public, which is the DEFAULT on Windows 11 and is NOT the default on Server
  # 2022. cd/setup.ps1 forces the profile to Private before touching WinRM. Without
  # that one line this build hangs here and the error message never mentions the
  # network profile. This is the classic "works on Server 2022, hangs on Win11".
  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.windows_admin_password
  winrm_use_ssl  = false
  winrm_insecure = true

  # This timeout must cover the ENTIRE OS installation, because it is how long Packer
  # waits for the first WinRM connection.
  winrm_timeout = "2h"

  # How Packer learns the guest's IP. The plugin asks the QEMU guest agent; there is no
  # DHCP-lease fallback. cd/setup.ps1 installs qemu-ga from the virtio CD during
  # FirstLogonCommands, before Packer ever tries to connect. With `qemu_agent = true`
  # and no agent running, every create and every refresh stalls for fifteen minutes --
  # in Packer now, and in OpenTofu later.
  qemu_agent = true
}

build {
  name    = "tpl-win11-client"
  sources = ["source.proxmox-iso.win11-client"]

  # ⚠️ NOTE THE `${path.root}` PREFIX, AND THE FACT THAT THE `cd_content` BLOCK ABOVE
  # DOES NOT HAVE ONE. Packer resolves these two things against different directories:
  #
  #   file() / templatefile()   -> relative to the TEMPLATE FOLDER
  #   provisioner `script`      -> relative to the CURRENT WORKING DIRECTORY
  #
  # So `file("cd/setup.ps1")` is correct as written, and `script = "scripts/x.ps1"`
  # would only work if you ran Packer from inside this directory.

  provisioner "powershell" {
    only   = ["proxmox-iso.win11-client"]
    script = "${path.root}/scripts/00-virtio-guest-tools.ps1"
  }

  provisioner "powershell" {
    only   = ["proxmox-iso.win11-client"]
    script = "${path.root}/scripts/10-cloudbase-init.ps1"
    environment_vars = [
      "CLOUDBASE_INIT_MSI_URL=${var.cloudbase_init_msi_url}"
    ]
  }

  # A reboot here shakes out anything that only takes effect on restart while we can
  # still see the failure.
  provisioner "windows-restart" {
    only                  = ["proxmox-iso.win11-client"]
    restart_timeout       = "30m"
    check_registry        = true
    restart_check_command = "powershell -command \"Write-Output 'restarted'\""
  }

  provisioner "powershell" {
    only   = ["proxmox-iso.win11-client"]
    script = "${path.root}/scripts/90-cleanup.ps1"
  }

  # LAST. Everything after sysprep /generalize runs on a machine whose identity has
  # already been erased, so nothing may follow it.
  provisioner "powershell" {
    only   = ["proxmox-iso.win11-client"]
    script = "${path.root}/scripts/99-sysprep.ps1"
  }

  post-processor "manifest" {
    # ${path.root} keeps this beside the template rather than in whatever directory
    # Packer happened to be run from. It is build output, not source: the repo's
    # .gitignore needs to cover `packer/*/manifest.json`.
    output     = "${path.root}/manifest.json"
    strip_path = true

    # The manifest records artifact_id, which for the Proxmox builder is the template's
    # VMID as a string. It is tempting to feed that into OpenTofu's clone { vm_id }.
    # DO NOT. The entire bpg clone block is ForceNew, so a manifest-driven VMID means
    # every template rebuild destroys and recreates every downstream VM. The VMID is
    # pinned here as a contract; OpenTofu asserts against it, it does not consume it.
  }
}

# Declared but deliberately UNUSED.
#
# packer/common.pkrvars.hcl is shared by every template in this repository, and it
# sets http_bind_address for the templates that serve an autoinstall seed over
# Packer's built-in HTTP server (the two Ubuntu ones and Kali). This template does
# not use that server - it seeds its answer file from an attached CD instead - but
# a var file that sets a variable the template does not declare makes
# `packer validate` emit:
#
#     Warning: Undefined variable
#     The variable "http_bind_address" was set but was not declared...
#
# followed by a block of raw HCL. Validate still passes, but for anyone running
# `task validate` on a fresh clone that reads as breakage. Declaring it here costs
# nothing and keeps the shared var file genuinely shared.
variable "http_bind_address" {
  type        = string
  default     = null
  description = "Unused by this template. Declared so the shared common.pkrvars.hcl does not warn."
}
