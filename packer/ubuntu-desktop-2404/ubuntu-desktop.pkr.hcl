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
#      `source: id: ubuntu-desktop`. The default source on this ISO is the desktop one, but
#      stating it is what makes the file readable and stops it silently changing meaning if
#      Canonical reorders the sources.
#
#   2. The live layer is packaged differently. The Server ISO names its squashfs layers
#      `ubuntu-server-minimal.*.squashfs`; the Desktop ISO uses `minimal.standard.live.squashfs`
#      and friends. That name is passed to the kernel as `layerfs-path=`, and if it is wrong
#      the live session does not start at all - you get a black screen or an initramfs
#      prompt, long before autoinstall is ever consulted.
#
#      IF THIS BUILD FAILS BEFORE THE INSTALLER APPEARS, `layerfs_path` IS THE FIRST THING
#      TO CHECK. Boot the ISO by hand, look at the GRUB entries with `e`, and copy the
#      layerfs-path value the ISO itself uses. It changes across point releases.
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
  type        = string
  default     = "vmbr9"
  description = "Build-plane bridge."
}

# ---------------------------------------------------------------------------------------
# Media variables
# ---------------------------------------------------------------------------------------

variable "iso_url" {
  type        = string
  default     = "https://releases.ubuntu.com/24.04/ubuntu-24.04.4-desktop-amd64.iso"
  description = "Ubuntu Desktop 24.04 LTS ISO. releases.ubuntu.com carries only the current point release, so this URL 404s when 24.04.5 ships."
}

variable "iso_checksum" {
  type    = string
  default = "none"

  # "none" on purpose. A checksum written from memory is worse than no checksum, because it
  # looks like verification and is not. The authoritative value is in
  #   https://releases.ubuntu.com/24.04/SHA256SUMS
  # (signed; verify with SHA256SUMS.gpg). Set iso_checksum = "sha256:<value>" before the
  # first real build.
  description = "Set to sha256:<hash> from https://releases.ubuntu.com/24.04/SHA256SUMS before building."
}

variable "layerfs_path" {
  type    = string
  default = "minimal.standard.live.squashfs"

  # The Desktop ISO's live filesystem is assembled from stacked squashfs layers and the
  # kernel has to be told which layer to boot. The Server ISO's layers are named
  # `ubuntu-server-minimal.*.squashfs`; the Desktop ISO's are `minimal.*.squashfs`, so a
  # boot command copied from a Server template hangs before the installer ever starts.
  #
  # This is exposed as a variable rather than hard-coded precisely because it drifts between
  # point releases. Verify it against the ISO you are actually building from.
  description = "Value for the kernel's layerfs-path= argument. Verify against the ISO's own GRUB entries if the live session fails to start."
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
    type             = "ide"
    index            = "2"
    iso_url          = var.iso_url
    iso_checksum     = var.iso_checksum
    iso_storage_pool = var.iso_storage_pool
    unmount          = true

    # Block form, not the deprecated top-level keys. Inside the block the key is `unmount`,
    # not `unmount_iso`.
  }

  boot      = "order=scsi0;ide2"
  boot_wait = "5s"

  # Disk first, CD second. On the first boot the disk is empty and SeaBIOS falls through to
  # the ISO; after the install the disk is bootable and wins, which is what stops the
  # post-install reboot from starting the installer all over again.

  # --- Autoinstall seed over HTTP ---------------------------------------------------
  http_content = local.http_content

  boot_command = [
    # Drop to the GRUB command line. The 22.04-era <esc><esc>e / <f6> recipes do not apply
    # to the 24.04 menu.
    "<wait5>c<wait>",

    # Same three load-bearing details as the server template:
    #   - the literal `autoinstall` token, or subiquity stops to ask "Continue? (yes|no)"
    #   - single quotes around the ds= value, because GRUB treats `;` as a statement separator
    #   - the trailing slash on the seed URL, for portability
    #
    # Plus the one that is unique to Desktop: layerfs-path. If this value does not match a
    # layer that exists on the ISO, the live session never starts and you never reach the
    # installer at all. See the variable definition above.
    "linux /casper/vmlinuz layerfs-path=${var.layerfs_path} autoinstall 'ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ---<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
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
