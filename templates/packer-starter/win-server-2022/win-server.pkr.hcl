# =============================================================================
# HOW THE VIRTIO DRIVERS GET INTO WinPE - read before changing anything here
# =============================================================================
#
# Windows Setup cannot see a virtio-scsi disk until the storage driver is loaded
# in WinPE. Two answer-file mechanisms were tried on this media (Windows Server
# 2022 Evaluation, March 2022, on PVE 9.2.2) and NEITHER works:
#
#   Microsoft-Windows-PnpCustomizationsWinPE
#     -> Setup aborts at "Setup is starting" with
#        "Windows could not apply the Windows PE bootstrap setting specified in
#         the unattend answer file"
#        This happens even with exactly four paths, every one verified to exist.
#        Bisection confirmed the component: removing only it lets Setup proceed.
#
#   Microsoft-Windows-Setup/RunSynchronous calling drvload
#     -> The bootstrap error goes away, Setup reaches disk selection, and still:
#        "Windows needs the driver for device
#         [Red Hat VirtIO SCSI pass-through controller]".
#
#        The first reading of this was "RunSynchronous runs too late". That is
#        WRONG, and the disk-selection page itself disproves it: Setup NAMES the
#        controller, which it can only do because vioscsi had already loaded and
#        the disk had been enumerated. The timing was fine.
#
#        The actual reason is that drvload and driver staging are different
#        operations. Microsoft KB2686316 puts it plainly: drvload "loads driver
#        into memory and starts the device. Doesn't propagate the driver to the
#        installed OS", whereas $WinPEDriver$ and unattend DriverPaths "will
#        attempt to load all drivers into memory, and ALSO will schedule them for
#        injection into the installing OS."
#
#        So Setup could see the disk and still refused it: a boot-critical
#        controller whose driver is not staged for injection would produce an
#        installed OS that cannot boot itself. No RunSynchronous command can fix
#        that, because nothing runnable from a command line registers a package
#        with Setup's injection list. Only the GUI "Load Driver" button,
#        DriverPaths, and $WinPEDriver$ feed it.
#
# None of that was a driver or path problem. From a Shift+F10 shell inside the
# failing WinPE: E: really was the virtio CD, the .inf really existed, drvload
# loaded it successfully, and `wmic diskdrive get size` then reported the 60 GB
# disk. The drivers were always fine; the delivery mechanism was not.
#
# WHAT ACTUALLY WORKS: $WinPEDriver$
#   Windows Setup scans the ROOT of every attached volume for a folder named
#   exactly $WinPEDriver$ - by drive letter, CD-ROMs included, not USB-only. It
#   loads what it finds AND schedules those packages for injection into the
#   installed OS, which is the half that drvload could not do. No answer file to
#   reject it and no drive letter to guess.
#
#   scripts/build-winpe-driver-iso.sh builds that volume from the pinned
#   virtio-win ISO; it is attached below as sata3.
#
#   Ref: https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/limitations-dollar-sign-winpedriver-dollar-sign
#
#   RESULT: Windows installs onto scsi0 / virtio-scsi-single with a virtio NIC,
#   which is what the rest of the lab uses. The tempting fallback - SATA disk and
#   E1000 NIC, which is what the original hand-built dc-01 did - was deliberately
#   not taken. It works and it carries emulated 1990s hardware forward forever.
# =============================================================================

# packer/win-server-2022/win-server.pkr.hcl
#
# WHAT THIS IS
#   The Packer build for golden template VMID 9002, `tpl-win-server-2022`.
#   Its only consumer is `dc-01` (VMID 102), the Active Directory domain controller
#   and DNS server for `example.local`.
#
# WHY IT EXISTS
#   The lab is greenfield (docs/iac/decisions.md D-01). Nothing is adopted, so the
#   domain controller has to be reproducible from code. Everything below the domain
#   itself -- the operating system, the storage bus, the network driver, the guest
#   agent, the cloud-init agent -- is baked here, once. Everything above it (the
#   forest, the OUs, the lab accounts `test.user` and `lab.user02`) is Ansible's job,
#   because HashiCorp archived terraform-provider-ad on 2025-08-11 and there is no
#   supported IaC provider for AD objects.
#
# ############################################################################
# # READ THIS BEFORE YOU TRY TO BUILD: YOU MUST SUPPLY THE INSTALL MEDIA.    #
# #                                                                          #
# # The Windows Server 2022 Evaluation ISO is REGISTRATION-GATED. Microsoft  #
# # only exposes it behind an Evaluation Center form, and the link it hands   #
# # you is a short-lived `go.microsoft.com` redirect. There is NO stable URL   #
# # and NO stable checksum, so there is nothing a Packer template can pin.    #
# #                                                                          #
# # This file therefore references the media as `local:iso/<name>.iso` -- a   #
# # file the operator uploaded to Proxmox by hand. A FRESH CLONE OF THIS      #
# # REPOSITORY CANNOT BUILD THIS TEMPLATE. That is a property of Microsoft's   #
# # distribution model, not an oversight. See README.md in this directory.    #
# #                                                                          #
# # Do NOT "fix" this by inventing a download URL. Any URL you find for an    #
# # evaluation ISO is either a redirect that expires or someone else's        #
# # unverifiable mirror.                                                     #
# ############################################################################
#
# BUILD PLANE
#   This template is built on `vmbr9` (10.99.0.0/24, gateway 10.99.0.1 = the Proxmox
#   host itself, masqueraded). vmbr9 exists because in a greenfield build nothing on
#   vmbr1 can reach the internet until `fw-01` routes -- and `fw-01` is itself a VM.
#   OpenTofu re-points `network_device.bridge` to vmbr1 at clone time; `bridge` is a
#   normal, non-ForceNew attribute on bpg/proxmox, so the switch is free.

packer {
  # Packer 1.11+ is required for the `boot_iso` block used below.
  required_version = ">= 1.11.0"

  required_plugins {
    proxmox = {
      # Floor is effectively 1.2.3: v1.2.2 silently dropped `cpu_type`, which would
      # leave this VM on the legacy `kvm64` model. v1.2.4 is very new; `~> 1.2`
      # keeps us inside the 1.x line without pinning to a release with no field
      # exposure. See docs/iac/design.md decision D5.
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
# shape we want -- the repo never contains a token, and `packer validate` still runs
# offline because an unset variable resolves to "".
#
# THE CREDENTIAL SHAPE TRAP: Packer and bpg/proxmox want the SAME API token in
# DIFFERENT shapes and sharing one variable between them silently 401s.
#
#   Packer (here):  username = "packer@pve!buildtoken"   token = "<uuid>"
#   OpenTofu (bpg): api_token = "terraform@pve!provider=<uuid>"   (ONE string)
#
# That is why these are two separate environment variables with Packer-specific
# names. Do not point them at the OpenTofu variables.
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
  default     = "example-soc-node01"
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
    Datastore for the template disk, the EFI vars disk and (on win11) the TPM state.

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

    NOTE: the ISO itself is built by `xorriso` on the *Packer host*, not on Proxmox.
    If xorriso is missing the failure message is confusing. `apt install xorriso`.
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
    The Windows Server 2022 Evaluation ISO, ALREADY UPLOADED to Proxmox by hand.

    Registration-gated: there is no URL to pin and no published checksum to verify
    against. Upload it under this exact name, or override this variable. Record the
    SHA256 you computed locally in docs/proxmox/iso-shelf.md so the build is at least
    reproducible *for you*.
  EOT
  default     = "local:iso/windows-server-2022-eval.iso"
}

variable "virtio_win_iso_file" {
  type        = string
  description = <<-EOT
    The virtio-win driver ISO, ALSO uploaded by hand.

    Pin 0.1.271. Do not use the `stable-virtio/` or `latest-virtio/` paths -- they are
    moving 301 redirects, so "stable" means something different every month. 0.1.285
    and 0.1.292 carry a vioscsi read-retry/performance regression; 0.1.271 is the
    known-good pin for this lab. Fetch it from the versioned `archive-virtio/`
    directory on fedorapeople.org and verify the checksum published alongside it.
  EOT
  default     = "local:iso/virtio-win-0.1.271.iso"
}

variable "windows_image_index" {
  type        = number
  description = <<-EOT
    WIM index inside the ISO to install.

    On the standard Server 2022 evaluation media this is usually:
      1 = Standard   (Server Core)
      2 = Standard   (Desktop Experience)   <-- we want this
      3 = Datacenter (Server Core)
      4 = Datacenter (Desktop Experience)

    "Usually" is doing real work in that sentence -- the ordering is a property of the
    ISO you downloaded, not of Windows. VERIFY IT before your first build:
      dism /Get-WimInfo /WimFile:D:\sources\install.wim
    Desktop Experience is chosen over Server Core deliberately: this is teaching
    material, and learners need Server Manager and the ADUC console to see what
    Ansible did to the directory.
  EOT
  default     = 2
}

variable "winpe_driver_iso_file" {
  type    = string
  default = "local:iso/virtio-winpe-drivers.iso"

  # A small ISO whose root contains a $WinPEDriver$ folder. Windows Setup scans
  # attached volumes for that folder by name and loads the drivers inside it before
  # the disk list is drawn - no answer file, no drive letter to guess.
  #
  # Build it on the Proxmox host with scripts/build-winpe-driver-iso.sh. It is
  # derived from the pinned virtio-win ISO, so it is a build artifact rather than
  # something to acquire.
  description = "ISO containing a root $WinPEDriver$ folder. Built from virtio-win by scripts/build-winpe-driver-iso.sh."
}

variable "virtio_cd_letter" {
  type    = string
  default = "E"

  # Drive letter WinPE assigns to the virtio-win CD.
  #
  # X: is WinPE's own ramdisk and optical drives start at D:. This template
  # attaches three CDs in a fixed order - sata0 install media, sata1 virtio-win,
  # sata2 the answer-file seed - so virtio is E:.
  #
  # Do NOT "make this safer" by listing several letters. Every path listed in
  # PnpCustomizationsWinPE must resolve; a single bad one fails the entire
  # windowsPE pass with a message that names none of them.
  description = "Drive letter of the virtio-win CD inside WinPE. Determined by CD attach order, not guessed."
}

variable "product_key" {
  type        = string
  description = <<-EOT
    Leave empty for evaluation media (evaluation ISOs carry their own edition and
    reject a key). Set a GVLK here only if you are installing from Volume Licensing
    media instead. Empty means the <ProductKey> element is omitted entirely.
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
    for three things: the Autounattend AdministratorPassword, the OOBE AutoLogon, and
    Packer's WinRM communicator.

    Set PKR_VAR_windows_admin_password in your shell. Never commit it.

    This password ends up in plaintext inside the answer file and in the LSA secret
    during the build. sysprep /generalize plus the scrubbing in scripts/90-cleanup.ps1
    removes most of it, but the honest control is to treat this as a build-only
    credential and rotate the real Administrator password from Ansible afterwards.
  EOT
  # No default value and no env() call: Packer already reads any variable `foo`
  # from `PKR_VAR_foo`, so `export PKR_VAR_windows_admin_password=...` is all that is
  # needed. The empty default is what keeps `packer validate` green offline.
  default   = ""
  sensitive = true

  validation {
    # Deliberately permits "" so `packer validate` stays green with no environment
    # set -- offline validation is a first-class requirement (decisions.md D-05).
    # It still catches a weak password when one IS supplied.
    condition     = var.windows_admin_password == "" || length(var.windows_admin_password) >= 12
    error_message = "The windows_admin_password variable must be at least 12 characters. Set PKR_VAR_windows_admin_password in your environment."
  }
}

# ---------------------------------------------------------------------------
# Guest agents
# ---------------------------------------------------------------------------

variable "cloudbase_init_msi_url" {
  type        = string
  description = <<-EOT
    Download URL for the Cloudbase-Init installer.

    ⚠️ UNVERIFIED: this template was authored offline, so the URL below was never
    fetched. If it 404s, download CloudbaseInitSetup_1_1_8_x64.msi by hand from
    cloudbase.it, host it somewhere the build plane can reach, and override this
    variable. scripts/10-cloudbase-init.ps1 fails loudly rather than silently
    skipping, so you will find out on the first build, not on the first clone.

    Cloudbase-Init 1.1.8 (2026-04-20) is the current stable. The widely repeated
    "stable is from 2020, use the continuous build" advice is out of date.
  EOT
  default     = "https://www.cloudbase.it/downloads/CloudbaseInitSetup_1_1_8_x64.msi"
}

variable "efi_pre_enrolled_keys" {
  type        = bool
  description = <<-EOT
    Pre-enrol Microsoft's Secure Boot keys into the OVMF variable store.

    Left true because that is what a real Windows machine looks like and Secure Boot
    is worth demonstrating. If your first build dies at the firmware with a security
    violation, flip this to false: Proxmox ships the 2011 Microsoft certificate set,
    those certificates began expiring in June 2026, and full enrolment of the 2023
    set (including the KEK) needs qemu-server >= 9.1.5. The Packer plugin exposes only
    this boolean -- it has no control over WHICH certificates get enrolled.
  EOT
  default     = true
}

# ---------------------------------------------------------------------------
# VirtIO driver injection (the whole reason this template exists)
#
# The old, hand-built dc-01 used a SATA disk and an E1000 NIC. That was not a design
# choice -- it was a workaround for a manual install: Windows Setup cannot see a
# virtio-scsi disk because WinPE has no virtio driver, so the installer shows an empty
# disk list and people fall back to emulated hardware.
#
# Because this is greenfield we can do it properly. `Microsoft-Windows-PnpCustomizationsWinPE`
# loads drivers into WinPE *before* the disk list is drawn, so Setup sees the
# virtio-scsi disk and installs onto it. The result is a template whose disk bus and
# NIC match every other VM in the lab: scsi0 on virtio-scsi-single, virtio NIC.
#
# THE DRIVE-LETTER PROBLEM. Drive letters in an answer file are positional. WinPE
# assigns them in device order, and adding or reordering an `additional_iso_files`
# block shifts D:/E:/F: and silently breaks injection -- the install "just" falls back
# to no disks found. We cannot run a script in windowsPE to look the volume up by
# label, so we do the next best thing: list every plausible letter for every driver
# directory. A DriverPath that does not exist is logged in setupact.log and skipped,
# so the redundant entries cost nothing.
# ---------------------------------------------------------------------------

locals {
  # Contract values. These are pinned, not computed. tofu asserts against them at
  # plan time; see docs/iac/design.md section 6 step 12 for why a manifest-driven
  # VMID would be catastrophic (the entire bpg `clone` block is ForceNew, so a
  # template rebuild would destroy and recreate dc-01).
  vm_id         = 9002
  template_name = "tpl-win-server-2022"

  # Volume label of the generated seed ISO. setup.ps1 finds itself by this label
  # rather than by drive letter, which is the part we CAN make position-independent.
  seed_cd_label = "PACKERCD"

  # 2k22 = the Server 2022 driver directories on the virtio-win ISO.
  virtio_driver_dirs = [
    "vioscsi\\2k22\\amd64",  # storage controller -- without this, no disks are found
    "NetKVM\\2k22\\amd64",   # network -- without this, no WinRM and the build hangs
    "Balloon\\2k22\\amd64",  # memory ballooning driver (blnsvr.exe comes later, from the MSI)
    "vioserial\\2k22\\amd64" # virtio-serial, the transport the QEMU guest agent uses
  ]

  # WinPE hands X: to its own ramdisk and starts optical drives at D:. The three
  # CDs are attached in a DETERMINISTIC order by this template - sata0 the install
  # media, sata1 virtio-win, sata2 the answer-file seed - so virtio lands on E:.
  #
  # NARROWED FROM ["D","E","F","G"] on 2026-07-22, after Windows Setup failed with
  #
  #   Windows could not apply the Windows PE bootstrap setting specified in the
  #   unattend answer file.
  #
  # The previous comment here asserted that driver paths which do not exist are
  # "noted in setupact.log and skipped, so the redundancy is free". That is not
  # true: 4 letters x 4 driver directories produced 16 PathAndCredentials entries
  # of which at most 4 could resolve, and windowsPE refused the whole component.
  # Guessing wide is not free - it is the failure.
  #
  # If the CD order ever changes, change this letter rather than adding more.
  candidate_cd_letters = [var.virtio_cd_letter]

  # The .inf inside each directory above, in the same order. drvload takes a file,
  # not a directory, so these are paired positionally with virtio_driver_dirs.
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

  # The password is dropped into XML text nodes, so the five XML metacharacters have
  # to be escaped or a password containing `&` produces an answer file that is not
  # well-formed. Windows Setup's response to malformed XML is to ignore the file
  # entirely and show the interactive installer -- i.e. the build hangs and the reason
  # is invisible. Escaping here is cheaper than debugging that.
  admin_password_xml = replace(replace(replace(var.windows_admin_password, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")

  autounattend = templatefile("cd/Autounattend.xml.pkrtpl", {
    admin_password = local.admin_password_xml
    image_index    = var.windows_image_index
    product_key    = var.product_key
    # PnpCustomizationsWinPE is not used - see the long comment in the template.
    # These drive the RunSynchronous drvload commands instead.
    driver_dirs   = local.virtio_driver_dirs
    inf_names     = local.virtio_inf_names
    virtio_cd     = var.virtio_cd_letter
    seed_cd_label = local.seed_cd_label
    computer_name = "PKR-WS22-TPL"
  })
}

source "proxmox-iso" "win-server-2022" {
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
  template_description = "Windows Server 2022 (Desktop Experience) golden template. virtio-scsi-single + virtio NIC, QEMU guest agent, Cloudbase-Init. Built by Packer; do not edit by hand. Consumer: dc-01 (102)."
  tags                 = "template;windows;example"

  # --- firmware -------------------------------------------------------------
  #
  # q35 + OVMF, matching win11-client. This is a deliberate choice and the reason is
  # consistency, not necessity: Server 2022 installs perfectly happily on SeaBIOS +
  # i440fx, but Windows 11 does NOT -- it requires q35, UEFI and a TPM. One OpenTofu
  # module (`tofu/modules/proxmox-vm`) clones every VM in the lab, so having one
  # Windows template on SeaBIOS and the other on OVMF would force the module to
  # special-case firmware per VM. A single firmware story is worth more than the
  # ~50 MB of EFI vars disk it costs.
  #
  # It is also the more realistic configuration: every Windows machine shipped in the
  # last decade boots UEFI, and Secure Boot / Credential Guard demonstrations are only
  # possible on this side of the fence.
  bios    = "ovmf"
  machine = "q35"

  # Proxmox `ostype` values: win10 covers "Windows 10/2016/2019", win11 covers
  # "Windows 11/2022/2025". Server 2022 is therefore win11, which looks wrong and
  # is not. Getting this right matters for more than cosmetics: the OpenTofu side
  # MUST have ostype set before it sets cipassword, or PVE crypt-hashes the password
  # and Cloudbase-Init dutifully injects the hash as if it were plaintext.
  os = "win11"

  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = var.efi_pre_enrolled_keys
  }

  # No tpm_config here. Server 2022 does not require a TPM, and every stateful device
  # added to a template is a device every clone inherits. win11-client does need one.

  # --- CPU / memory ---------------------------------------------------------
  #
  # The plugin defaults to cpu_type = "kvm64", a 2003-era feature set. `host` passes
  # the physical CPU through, which Windows needs for sane performance and which
  # Credential Guard / VBS demos need for the virtualisation extensions.
  cpu_type = "host"
  sockets  = 1
  cores    = 2
  memory   = 4096
  numa     = false

  # Ballooning off. dc-01 runs floating = 0 (see the VM inventory), and a Windows
  # guest needs both the Balloon driver AND blnsvr.exe before ballooning does
  # anything anyway -- both are installed by scripts/00-virtio-guest-tools.ps1.
  ballooning_minimum = 0

  # --- storage --------------------------------------------------------------
  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    disk_size    = "60G"
    storage_pool = var.storage_pool

    # raw, not qcow2: local-lvm is LVM-thin and does not support qcow2.
    format = "raw"

    # io_thread requires virtio-scsi-single, which is why the two go together.
    io_thread  = true
    cache_mode = "none"

    # discard + ssd are not a micro-optimisation. Without discard, blocks deleted
    # inside the guest are never returned to the LVM-thin pool, and a full thin pool
    # stalls or corrupts writes across EVERY VM on the host -- not just this one.
    discard = true
    ssd     = true
  }

  # --- network --------------------------------------------------------------
  network_adapters {
    model  = "virtio"
    bridge = var.build_bridge

    # The per-NIC Proxmox firewall inserts an fwbr/fwln/fwpr veth chain. It is noise
    # on a build-plane NIC that exists for ten minutes. Real per-VM firewalling is
    # done by fw-01, not by the host bridge.
    firewall = false

    # No mac_address here on purpose. MACs are a per-VM contract (BC:24:11 + the last
    # three octets of the IP) pinned by OpenTofu, because OPNsense DHCP reservations
    # are templated from the same map. A MAC baked into a template would be shared by
    # every clone.
  }

  # --- cloud-init drive -----------------------------------------------------
  #
  # Deliberately NOT set (`cloud_init` defaults to false). bpg/proxmox creates and
  # owns the cloud-init drive through its `initialization` block at clone time; a
  # second drive created here would fight it. Cloudbase-Init is installed INSIDE the
  # guest by scripts/10-cloudbase-init.ps1 -- that is the agent, not the drive.

  # --- boot media -----------------------------------------------------------
  #
  # THREE CDs, all on SATA, indices pinned.
  #
  # Why SATA and not IDE: the q35 machine type exposes only a stub IDE controller
  # (ide0/ide2), which is not enough ports for three CDs. q35's AHCI controller gives
  # six (sata0-sata5) and WinPE has a native AHCI driver.
  #
  # Why the CDs are NOT on the virtio-scsi controller: chicken and egg. WinPE would
  # need the vioscsi driver to read the CD that contains the vioscsi driver.
  #
  # Why the indices are written out explicitly: see the drive-letter comment above.
  # Reordering these blocks silently breaks driver injection.

  boot_iso {
    type     = "sata"
    index    = 0
    iso_file = var.windows_iso_file

    # Detach before the template is created -- otherwise every clone of this template
    # boots with a 5 GB Windows ISO attached.
    #
    # NOTE the key is `unmount`, not `unmount_iso`. Inside the boot_iso block it is
    # `unmount`; `unmount_iso` was the deprecated top-level field. Getting this wrong
    # is an "Unsupported argument" error, which at least fails loudly.
    unmount = true
  }

  # The $WinPEDriver$ volume. Windows Setup scans the root of every attached volume
  # for a folder with this exact name and drvloads whatever it finds, BEFORE it
  # enumerates storage for the disk list. That timing is the whole point: it is
  # earlier than RunSynchronous and it does not go through the answer file, which is
  # what rejected PnpCustomizationsWinPE.
  #
  # Built on the Proxmox host by scripts/build-winpe-driver-iso.sh - about 29 MB of
  # the four drivers WinPE actually needs, rather than the full 693 MB virtio ISO.
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
    # plugin also deletes an ISO it did not upload is not something we could test
    # without a host. On the first real build, confirm `local:iso/virtio-win-*.iso`
    # still exists afterwards before you delete your local copy.
  }

  additional_iso_files {
    type  = "sata"
    index = 2

    # Windows Setup scans the root of every removable, read-only volume for a file
    # named exactly `Autounattend.xml`. That is how the answer file gets picked up.
    #
    # It is NOT delivered on a floppy. `proxmox-iso` has no floppy_files/floppy_dirs
    # at all -- any tutorial telling you to use A:\autounattend.xml is written for the
    # qemu, virtualbox or hyperv builders.
    #
    # The label is PACKERCD rather than the Linux-flavoured "cidata": cidata is the
    # NoCloud label cloud-init looks for, and this ISO is not a NoCloud seed. What
    # matters is that setup.ps1 can find its own volume by label instead of guessing
    # a drive letter.
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
  # We send several spacebars over several seconds rather than one perfectly-timed
  # keystroke. The extra presses land in an unattended Setup UI where nothing is
  # waiting for input, so they are harmless. Expect to re-tune `boot_wait` on first
  # contact with real hardware -- a slower host moves the window.
  boot_wait    = "4s"
  boot_command = ["<spacebar><wait1s><spacebar><wait1s><spacebar><wait1s><spacebar><wait1s><spacebar>"]

  # --- communicator ---------------------------------------------------------
  #
  # Plain HTTP WinRM on 5985. This is a build plane on an isolated, host-masqueraded
  # bridge that exists for the duration of one build, so the cost of an unencrypted
  # channel is bounded and the cost of provisioning a certificate is not. Ansible
  # talks to the finished VMs over Kerberos, not over this.
  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.windows_admin_password
  winrm_use_ssl  = false
  winrm_insecure = true

  # A full Windows Server install plus reboots is comfortably over an hour on
  # spinning-rust-era hardware. This timeout is how long Packer waits for the FIRST
  # WinRM connection, i.e. it must cover the entire OS installation.
  winrm_timeout = "2h"

  # How Packer learns the guest's IP address. The plugin asks the QEMU guest agent --
  # there is no DHCP-lease scraping fallback. This is why setup.ps1 installs
  # qemu-ga from the virtio CD during FirstLogonCommands, BEFORE Packer ever tries to
  # connect: with `qemu_agent = true` and no agent running, every create and every
  # refresh sits there for fifteen minutes and then fails.
  qemu_agent = true
}

build {
  name    = "tpl-win-server-2022"
  sources = ["source.proxmox-iso.win-server-2022"]

  # Order matters and each step explains itself in its own header comment.
  #
  # ⚠️ NOTE THE `${path.root}` PREFIX, AND THE FACT THAT THE `cd_content` BLOCK ABOVE
  # DOES NOT HAVE ONE. Packer resolves these two things against different directories:
  #
  #   file() / templatefile()   -> relative to the TEMPLATE FOLDER
  #   provisioner `script`      -> relative to the CURRENT WORKING DIRECTORY
  #
  # So `file("cd/setup.ps1")` is correct as written, and `script = "scripts/x.ps1"`
  # would only work if you happened to run Packer from inside this directory. Using
  # `${path.root}` makes the provisioners work from anywhere, which is what CI and
  # the repo-root build commands in README.md need. This asymmetry is not documented
  # anywhere obvious and produces a "no such file or directory" at validate time.

  provisioner "powershell" {
    only   = ["proxmox-iso.win-server-2022"]
    script = "${path.root}/scripts/00-virtio-guest-tools.ps1"
  }

  provisioner "powershell" {
    only   = ["proxmox-iso.win-server-2022"]
    script = "${path.root}/scripts/10-cloudbase-init.ps1"
    environment_vars = [
      "CLOUDBASE_INIT_MSI_URL=${var.cloudbase_init_msi_url}"
    ]
  }

  # A reboot here shakes out anything that only takes effect on restart (driver
  # binding, service start modes) while we can still see the failure.
  provisioner "windows-restart" {
    only                  = ["proxmox-iso.win-server-2022"]
    restart_timeout       = "30m"
    check_registry        = true
    restart_check_command = "powershell -command \"Write-Output 'restarted'\""
  }

  provisioner "powershell" {
    only   = ["proxmox-iso.win-server-2022"]
    script = "${path.root}/scripts/90-cleanup.ps1"
  }

  # LAST. Everything after sysprep /generalize runs on a machine whose identity has
  # already been erased, so nothing may follow it.
  provisioner "powershell" {
    only   = ["proxmox-iso.win-server-2022"]
    script = "${path.root}/scripts/99-sysprep.ps1"
  }

  post-processor "manifest" {
    # ${path.root} keeps this beside the template rather than in whatever directory
    # Packer happened to be run from. It is build output, not source: the repo's
    # .gitignore needs to cover `packer/*/manifest.json`.
    output     = "${path.root}/manifest.json"
    strip_path = true

    # The manifest records artifact_id, which for the Proxmox builder is literally
    # the template's VMID as a string. It is tempting to feed that into OpenTofu's
    # clone { vm_id = ... }. DO NOT. The entire bpg clone block is ForceNew, so a
    # manifest-driven VMID means every template rebuild destroys and recreates every
    # downstream VM -- including dc-01 and the whole directory with it. The VMID is
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
