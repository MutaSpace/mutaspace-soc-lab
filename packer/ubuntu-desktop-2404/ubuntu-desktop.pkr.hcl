# ubuntu-desktop.pkr.hcl
#
# WHAT THIS IS
#   The Packer template that builds golden image VMID 9001, `tpl-ubuntu-desktop-2404`,
#   from the Ubuntu Desktop 24.04 LTS ISO.
#
# WHY IT EXISTS
#   analyst-01 (103) is the workstation a learner actually sits at. It needs a graphical
#   session, a browser and a desktop to open the Wazuh dashboard in. Everything else in the
#   lab is headless, which is why this is the only desktop template.
#
# WHY IT IS A SEPARATE TEMPLATE AND NOT "SERVER PLUS A DESKTOP"
#   Installing a full GNOME session on top of the server image would work, but it would take
#   ten minutes on every clone and produce a machine that is subtly different from a real
#   Ubuntu Desktop install (different default package set, different seeded snaps, different
#   display manager configuration). Golden images exist so that the slow, divergent work
#   happens once.
#
# WHAT IS DIFFERENT FROM THE SERVER TEMPLATE - READ THIS BEFORE DEBUGGING
#   Ubuntu Desktop 24.04 supports autoinstall, but it is NOT the same media as Server:
#
#   1. The autoinstall file must select the desktop install source explicitly, with
#      `source: id: ubuntu-desktop`. This is NOT decoration and it is NOT the ISO's default.
#      Verified on the 24.04.4 media, 2026-07-22, by mounting it and reading
#      /casper/install-sources.yaml:
#
#         id: ubuntu-desktop-minimal   default: true    path: minimal.squashfs
#         id: ubuntu-desktop           default: false   path: minimal.standard.squashfs
#
#      Omit the `source:` block and you get the MINIMIZED desktop - no LibreOffice, no
#      Thunderbird, a different seeded snap set. It installs cleanly and looks fine, so the
#      difference only surfaces when a learner goes looking for an application that a real
#      Ubuntu Desktop has and this template does not.
#
#   2. The live layer is packaged differently. The Server ISO names its squashfs layers
#      `ubuntu-server-minimal.*.squashfs`; the Desktop ISO uses `minimal.standard.live.squashfs`
#      and friends. That name is passed to the kernel as `layerfs-path=`, and if it is wrong
#      the live session does not start at all - you get a black screen or an initramfs
#      prompt, long before autoinstall is ever consulted.
#
#      IF THIS BUILD FAILS BEFORE THE INSTALLER APPEARS, `layerfs_path` IS THE FIRST THING
#      TO CHECK - but do NOT try to read the value off the ISO's own GRUB menu. That advice
#      is wrong and it wasted time here: the 24.04.4 desktop ISO's /boot/grub/grub.cfg does
#      not set layerfs-path AT ALL. Its menu entries are just
#
#         linux /casper/vmlinuz  --- quiet splash
#
#      because an interactive boot lets casper pick the layer itself. An autoinstall boot
#      has to name it. Get the value by listing the layers on the media instead:
#
#         mount -o loop,ro <iso> /mnt && ls /mnt/casper/*.squashfs
#
#      and pick the `.live.` one - the live layer is the only one that contains the
#      installer. On 24.04.4 that is minimal.standard.live.squashfs. Verified 2026-07-22.
#
#   3. The install is larger and slower. Disk and timeouts are sized accordingly.

packer {
  required_version = ">= 1.11.0"

  required_plugins {
    proxmox = {
      version = "~> 1.2"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ---------------------------------------------------------------------------------------
# Connection variables - see packer/README.md for the credential-shape trap.
#
# No real credential is committed; every value below is supplied through a PKR_VAR_*
# environment variable. The placeholder defaults exist for decision D-05 only: `packer
# validate` runs the builder's Prepare(), which hard fails on an empty URL, username or
# token, so a template with no defaults cannot be validated without a host. They are
# deliberately non-functional - a build that forgets to override them fails loudly at the
# first API call instead of quietly building against the wrong endpoint.
# ---------------------------------------------------------------------------------------

variable "proxmox_url" {
  type        = string
  description = "Proxmox API endpoint INCLUDING /api2/json."
  default     = "https://127.0.0.1:8006/api2/json"
}

variable "proxmox_username" {
  type        = string
  description = "API token owner in user@realm!tokenid form, e.g. packer@pve!buildtoken."
  default     = "packer@pve!buildtoken"
}

variable "proxmox_token" {
  type        = string
  sensitive   = true
  description = "The token secret (a bare UUID). Supply via PKR_VAR_proxmox_token."
  default     = "unset-export-PKR_VAR_proxmox_token"
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name that runs the build."
  default     = "mutaspace-soc-node01"
}

variable "proxmox_insecure_tls" {
  type        = bool
  default     = true
  description = "Proxmox ships a self-signed certificate."
}

variable "task_timeout" {
  type        = string
  default     = "10m"
  description = "Per-API-task timeout. The plugin default of 1 minute cannot cover an ISO upload or a template conversion."
}

# ---------------------------------------------------------------------------------------
# Placement variables
# ---------------------------------------------------------------------------------------

variable "storage_pool" {
  type        = string
  default     = "local-lvm"
  description = "Datastore for the template disk. Must match the datastore the clones use."
}

variable "iso_storage_pool" {
  type        = string
  default     = "local"
  description = "Datastore that holds ISO files."
}

variable "build_bridge" {
  type = string

  # DEFAULT CHANGED after first contact with real hardware, 2026-07-22, for the
  # same reasons as the server template - read the long note in
  # packer/ubuntu-server-2404/ubuntu-server.pkr.hcl for the full version.
  #
  # Short form: vmbr9 was an isolated, host-masqueraded build plane, designed on
  # the assumption that vmbr0 was a bare WAN uplink. On this host vmbr0 is a
  # working LAN with DHCP and a gateway, so building there removes dnsmasq, the
  # MASQUERADE rule, and - the one that actually matters - the problem that a VM
  # on an isolated subnet is NOT REACHABLE by the workstation running Packer.
  # Packer has to SSH into the machine it just installed. That failure arrives an
  # hour into a desktop build and looks like an SSH problem rather than a routing
  # one.
  #
  # NEVER vmbr1: no route out until fw-01 exists, which is the bootstrap problem
  # this lab has to solve.
  default     = "vmbr0"
  description = "Bridge used during the build. vmbr0 when it has DHCP and a gateway; vmbr9 for an isolated build plane."
}

# ---------------------------------------------------------------------------------------
# Media variables
# ---------------------------------------------------------------------------------------

variable "iso_url" {
  type        = string
  default     = "https://releases.ubuntu.com/24.04/ubuntu-24.04.4-desktop-amd64.iso"
  description = "Ubuntu Desktop 24.04 LTS ISO. releases.ubuntu.com carries only the current point release, so this URL 404s when 24.04.5 ships."
}

variable "desktop_iso_file" {
  type = string

  # WHY THIS IS NOT CALLED `iso_file`, WHICH IS THE OBVIOUS NAME.
  #
  #   packer/common.pkrvars.hcl is shared by EVERY template in this repository, and it
  #   already sets
  #       iso_file = "local:iso/ubuntu-24.04.4-live-server-amd64.iso"
  #   for the server build. One shared file cannot name two different ISOs under one key.
  #   If this variable were called `iso_file`, the desktop build would silently install
  #   Ubuntu SERVER onto VMID 9001 - a template that builds, converts and clones perfectly
  #   and simply has no desktop on it. Nothing would error.
  #
  #   This is the same trap common.pkrvars.hcl already documents for `windows_iso_file`,
  #   which both Windows templates share and which is therefore set per-template rather
  #   than in the common file. Per-template media get per-template variable names.
  #
  # WHY IT DEFAULTS TO AN ISO ON THE HOST RATHER THAN TO "".
  #
  #   The desktop ISO is 6.6 GB (the server ISO is 3.4 GB). Leaving this empty means Packer
  #   downloads it to the workstation and then uploads it to Proxmox on EVERY build. This
  #   workstation reaches the lab over WireGuard, so that upload dominates - and the upload
  #   is pure waste, because the host can fetch the same file from Ubuntu directly at line
  #   rate. Put it there once:
  #
  #     ssh <host> 'curl -L -o /var/lib/vz/template/iso/ubuntu-24.04.4-desktop-amd64.iso \
  #                   https://releases.ubuntu.com/24.04/ubuntu-24.04.4-desktop-amd64.iso'
  #
  #   packer/win11-client sets its media the same way, for the same reason.
  #
  # SET THIS TO "" to fall back to iso_url + iso_checksum (download, verify, upload). That
  # is the right setting for a clean host, and it is the only path in which the checksum
  # below is actually checked.
  default     = "local:iso/ubuntu-24.04.4-desktop-amd64.iso"
  description = "Desktop ISO already on the Proxmox host, e.g. local:iso/name.iso. Deliberately NOT named iso_file - common.pkrvars.hcl uses that key for the SERVER media. Empty falls back to iso_url + iso_checksum."
}

variable "iso_checksum" {
  type = string

  # Pinned 2026-07-22, read from https://releases.ubuntu.com/24.04/SHA256SUMS, the line for
  # ubuntu-24.04.4-desktop-amd64.iso.
  #
  # This was "none" while the templates were written offline, on the principle that a
  # checksum written from memory is worse than no checksum: it looks like verification and
  # is not. It is now a real published value.
  #
  # ONLY CONSULTED WHEN desktop_iso_file IS EMPTY. An ISO already sitting on the host is
  # not re-verified by Packer, so if you place the file by hand, check it by hand:
  #   sha256sum /var/lib/vz/template/iso/ubuntu-24.04.4-desktop-amd64.iso
  #
  # If you bump iso_url to a new point release you MUST bump this together with it. A stale
  # checksum fails the download loudly, which is far better than the silent failure where a
  # truncated ISO produces a template that boots strangely three weeks later.
  #
  # The sums file is signed. To verify it rather than trusting HTTPS alone:
  #   curl -O https://releases.ubuntu.com/24.04/SHA256SUMS
  #   curl -O https://releases.ubuntu.com/24.04/SHA256SUMS.gpg
  #   gpg --keyserver keyserver.ubuntu.com --recv-keys d94aa3f0efe21092
  #   gpg --verify SHA256SUMS.gpg SHA256SUMS
  default = "sha256:3a4c9877b483ab46d7c3fbe165a0db275e1ae3cfe56a5657e5a47c2f99a99d1e"

  description = "SHA256 of the Ubuntu Desktop ISO, from https://releases.ubuntu.com/24.04/SHA256SUMS. Bump alongside iso_url. Only used when desktop_iso_file is empty."
}

variable "http_bind_address" {
  type    = string
  default = ""

  # The address Packer's seed server binds to, and the value {{ .HTTPIP }} expands to in
  # the boot command.
  #
  # PIN THIS whenever the workstation has more than one interface. Packer binds the
  # listener to *:port but auto-detects a SINGLE address to ADVERTISE, and that heuristic
  # has no idea which of your interfaces the lab can reach. A workstation running Docker,
  # libvirt and a VPN can easily have ten candidates - docker0, half a dozen br-*, virbr0,
  # tun0, a public IP - and if Packer picks any of them the guest asks for the seed at an
  # address that does not exist on its network.
  #
  # THE SYMPTOM: nothing. cloud-init retries, gives up, and the installer falls back to
  # asking questions on a console nobody is watching until ssh_timeout expires. Identical
  # appearance to having no network at all, and to a mangled boot command.
  #
  # Set in packer/common.pkrvars.hcl to the workstation's WireGuard address, because that
  # is the only interface the lab can route back to.
  description = "Address Packer serves the autoinstall seed on. Empty = auto-detect (only safe with one interface)."
}

variable "layerfs_path" {
  type    = string
  default = "minimal.standard.live.squashfs"

  # The Desktop ISO's live filesystem is assembled from stacked squashfs layers and an
  # autoinstall boot has to name the layer it wants. The Server ISO's layers are called
  # `ubuntu-server-minimal.*.squashfs`; the Desktop ISO's are `minimal.*.squashfs`, so a
  # boot command copied from a Server template never reaches the installer.
  #
  # VERIFIED 2026-07-22 against ubuntu-24.04.4-desktop-amd64.iso, by mounting it:
  #
  #   minimal.squashfs                     the minimized desktop root
  #   minimal.standard.squashfs            the full desktop root
  #   minimal.standard.live.squashfs   <-- THIS ONE. The live layer, and the only one that
  #                                        contains the installer itself.
  #
  # The ISO's own GRUB menu does not set layerfs-path (it lets casper choose), so there is
  # nothing to copy from it - list /casper/*.squashfs on the media instead.
  #
  # Exposed as a variable rather than hard-coded because the layer names drift between point
  # releases. Re-check it against the ISO you are actually building from.
  description = "Value for the kernel's layerfs-path= argument. If the live session never starts, mount the ISO and list /casper/*.squashfs - you want the `.live.` layer."
}

# ---------------------------------------------------------------------------------------
# Guest identity variables
# ---------------------------------------------------------------------------------------

variable "ssh_username" {
  type        = string
  default     = "labadmin"
  description = "Build/administration account created by the autoinstall."
}

variable "build_password_hash" {
  type        = string
  sensitive   = true
  description = "SHA-512 crypt hash for the build account. Generate with: mkpasswd -m sha-512. On a DESKTOP image this is also the graphical login password, so choose it accordingly."
  # Empty so `packer validate` runs offline (D-05). subiquity rejects an empty crypt
  # field, so a forgotten export fails at install time, not silently.
  default = ""
}

variable "ssh_public_key" {
  type        = string
  description = "Public key installed into the build account's authorized_keys."
  default     = ""
}

variable "ssh_private_key_file" {
  type        = string
  description = "Path to the matching private key, used by Packer's SSH communicator."
  # Empty means "no key file". Packer OPENS and PARSES this path when it is non-empty,
  # so a wrong path is caught at validate time rather than at build time.
  default = ""
}

# ---------------------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------------------

locals {
  template_name = "tpl-ubuntu-desktop-2404"
  template_vmid = 9001

  # NoCloud needs BOTH files. meta-data is intentionally empty, but a 404 on it tells
  # cloud-init "this is not a NoCloud datasource" and the installer falls back to asking
  # questions on a console nobody is watching.
  #
  # THE PATHS BELOW ARE BARE AND RELATIVE ON PURPOSE. file() and templatefile() already
  # resolve relative to the TEMPLATE DIRECTORY, so writing "${path.root}/http/..." prepends
  # that directory a second time and the call only works when Packer happens to be invoked
  # from inside this folder. The `script =` and `output =` uses of ${path.root} further down
  # are the OPPOSITE case: those resolve against the CURRENT WORKING DIRECTORY and do need it.
  http_content = {
    "/meta-data" = file("http/meta-data")
    "/user-data" = templatefile("http/user-data.pkrtpl.hcl", {
      hostname       = "ubuntu-desktop-tpl"
      username       = var.ssh_username
      password_hash  = var.build_password_hash
      ssh_public_key = var.ssh_public_key
    })
  }
}

source "proxmox-iso" "ubuntu-desktop-2404" {

  # --- API connection ---------------------------------------------------------------
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = var.proxmox_insecure_tls
  task_timeout             = var.task_timeout

  # --- Template identity ------------------------------------------------------------
  vm_id                = local.template_vmid
  vm_name              = local.template_name
  template_name        = local.template_name
  template_description = "Ubuntu Desktop 24.04 LTS golden image. Built by packer/ubuntu-desktop-2404. Consumer: analyst-01 (103). Do not edit in place - rebuild from Packer."

  # --- Hardware ---------------------------------------------------------------------
  os       = "l26"
  bios     = "seabios"
  cores    = 2
  sockets  = 1
  cpu_type = "host"
  memory   = 4096

  # A graphical installer needs the RAM. 4096 matches analyst-01's allocation, so the build
  # environment resembles the runtime environment rather than being a special case.

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    disk_size    = "30G"
    storage_pool = var.storage_pool
    io_thread    = true
    discard      = true
    ssd          = true
    cache_mode   = "none"

    # 30G rather than the server template's 20G: a full GNOME desktop plus the seeded snaps
    # is roughly 12-15 GB installed, and a template with no headroom cannot survive its own
    # first `apt upgrade`.
    #
    # Still smaller than analyst-01's 40G. OpenTofu grows scsi0 at clone time and cloud-init
    # extends the filesystem on first boot. Disks grow; they never shrink.
    #
    # discard + ssd keep the LVM-thin pool from filling with blocks the guest already freed.
    # A full thin pool stalls writes for every VM on the host, not just this one.
  }

  network_adapters {
    model    = "virtio"
    bridge   = var.build_bridge
    firewall = false
  }

  # --- Cloud-init drive -------------------------------------------------------------
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  # --- Boot media -------------------------------------------------------------------
  boot_iso {
    type  = "ide"
    index = "2"

    # Two ways to supply the installer, and which one is used depends on whether
    # desktop_iso_file is set. Precedence is written out rather than implied so a half-set
    # pair fails loudly instead of quietly preferring the wrong one.
    #
    #   desktop_iso_file = "local:iso/ubuntu-24.04.4-desktop-amd64.iso"
    #       Use an ISO ALREADY on the Proxmox host. Nothing downloaded, nothing uploaded.
    #       This is the default and it is what you want: the file is 6.6 GB.
    #
    #   iso_url + iso_checksum  (desktop_iso_file = "")
    #       Download to the workstation, verify, upload to the host. Correct for a clean
    #       host, and the only path where iso_checksum is actually checked.
    iso_file         = var.desktop_iso_file != "" ? var.desktop_iso_file : null
    iso_url          = var.desktop_iso_file == "" ? var.iso_url : null
    iso_checksum     = var.desktop_iso_file == "" ? var.iso_checksum : null
    iso_storage_pool = var.iso_storage_pool
    unmount          = true

    # Block form, not the deprecated top-level keys. Inside the block the key is `unmount`,
    # not `unmount_iso`.
    #
    # index = "2" is pinned so the ISO is predictably ide2, which is what `boot` refers to.
  }

  boot = "order=scsi0;ide2"

  # Disk first, CD second. On the first boot the disk is empty and SeaBIOS falls through to
  # the ISO; after the install the disk is bootable and wins, which is what stops the
  # post-install reboot from starting the installer all over again.

  # 10s, not 5s. VERIFIED THE HARD WAY on PVE 9.2.2 building the server template, 2026-07-22.
  #
  # The GRUB menu has to be fully drawn and accepting input before the `c` that drops to the
  # command line is sent. If `c` lands too early it is swallowed, the rest of the boot
  # command is typed into a menu that ignores it, and the ISO boots its default entry -
  # which on the DESKTOP media means it boots the live session and sits on the "Install
  # Ubuntu / Try Ubuntu" welcome screen forever. That looks like autoinstall being ignored;
  # it is a timing problem.
  boot_wait = "10s"

  # Type slowly. Packer drives the console through QEMU's `sendkey`, one keystroke at a time
  # over the API, and at full speed keystrokes are DROPPED - a known flakiness in the
  # Proxmox plugin (issues #237 and #220: `sendkey: EOF` and lost characters).
  #
  # THE SYMPTOM, recorded so nobody diagnoses it twice:
  #
  #   Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
  #
  # That means the kernel booted with NO initrd, because the `initrd /casper/initrd` line
  # lost a character on the way in. Both files exist on the ISO and the paths below are
  # correct. The panic looks like broken media or a missing storage driver, and is neither.
  #
  # The desktop boot line is LONGER than the server one - it carries layerfs-path= as well -
  # so it has more characters to lose. If anything, this matters more here.
  boot_keygroup_interval = "100ms"

  # --- Autoinstall seed over HTTP ---------------------------------------------------
  http_content      = local.http_content
  http_bind_address = var.http_bind_address

  boot_command = [
    # Drop to the GRUB command line. The 22.04-era <esc><esc>e / <f6> recipes do not apply
    # to the 24.04 menu.
    "<wait5>c<wait2>",

    # Same three load-bearing details as the server template:
    #   - the literal `autoinstall` token, or subiquity stops to ask "Continue? (yes|no)"
    #   - single quotes around the ds= value, because GRUB treats `;` as a statement separator
    #   - the trailing slash on the seed URL, for portability
    #
    # Plus the one that is unique to Desktop: layerfs-path. If this value does not match a
    # layer that exists on the ISO, the live session never starts and you never reach the
    # installer at all. See the variable definition above.
    "linux /casper/vmlinuz layerfs-path=${var.layerfs_path} autoinstall 'ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ---<enter><wait2>",
    "initrd /casper/initrd<enter><wait2>",
    "boot<enter>",
  ]

  # --- Communicator -----------------------------------------------------------------
  communicator           = "ssh"
  ssh_username           = var.ssh_username
  ssh_private_key_file   = var.ssh_private_key_file
  ssh_timeout            = "90m"
  ssh_handshake_attempts = 100

  # 90 minutes, longer than the server template's 60. A desktop install unpacks far more,
  # and this build competes with nothing else on a single-node lab host but still has to
  # pull security updates over the masqueraded build plane.

  qemu_agent = true

  # The plugin asks the guest agent for the VM's IP. No agent, no answer, and the build
  # waits at "Waiting for SSH" until ssh_timeout. qemu-guest-agent is installed by the
  # autoinstall file for exactly this reason.
}

build {
  name    = "ubuntu-desktop-2404"
  sources = ["source.proxmox-iso.ubuntu-desktop-2404"]

  provisioner "shell" {
    inline = [
      "echo '==> waiting for cloud-init to finish its first boot'",
      "cloud-init status --wait || true",
      "echo '==> cloud-init finished'",
    ]
  }

  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    script          = "${path.root}/scripts/cleanup.sh"
  }

  # A build log, not a build input - the template's VMID is a pinned contract, and feeding
  # it back into OpenTofu's ForceNew clone block would recreate every VM on every rebuild.
  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
  }
}
