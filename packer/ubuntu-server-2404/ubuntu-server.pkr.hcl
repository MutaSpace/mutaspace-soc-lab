# ubuntu-server.pkr.hcl
#
# WHAT THIS IS
#   The Packer template that builds golden image VMID 9000, `tpl-ubuntu-server-2404`,
#   from the Ubuntu Server 24.04 LTS live-server ISO.
#
# WHY IT EXISTS
#   Three of the lab's VMs are Ubuntu Server and are supposed to be identical below the
#   application layer: wazuh-01 (104), ubuntu-app-01 (106) and nlp-01 (110). Building each
#   of them from an ISO by hand would make "identical" an aspiration rather than a fact.
#   Building them from one golden template makes it structural: if the base image is wrong,
#   it is wrong in exactly one place and it is fixed in exactly one place.
#
# WHERE IT RUNS
#   On the build plane, vmbr9 (10.99.0.0/24), masqueraded by the Proxmox host itself.
#   This lab is greenfield: nothing on vmbr1 can reach the internet until fw-01 routes,
#   and fw-01 is itself a VM that has to be built first. vmbr9 is the only network that
#   exists before the firewall does, so every template build happens there. OpenTofu
#   re-points `network_device.bridge` to vmbr1 or vmbr2 when it clones - `bridge` is a
#   normal, non-ForceNew attribute on the bpg provider, so moving the NIC is free.
#
# THE HANDOFF CONTRACT
#   vm_id = 9000 is a contract, not a convenience. OpenTofu's `clone { vm_id = ... }` block
#   is ForceNew in its entirety, so if the template's VMID ever moved, every VM cloned from
#   it would be destroyed and recreated on the next apply. The VMID is pinned here and
#   asserted (never derived) on the OpenTofu side.

packer {
  required_version = ">= 1.11.0"

  required_plugins {
    # `~> 1.2` resolves to the newest 1.2.x. The floor that matters is 1.2.3:
    # v1.2.2 silently dropped support for `cpu_type`, which this template sets.
    proxmox = {
      version = "~> 1.2"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ---------------------------------------------------------------------------------------
# Connection variables
#
# NO REAL CREDENTIAL IS EVER COMMITTED. Packer reads any variable named `foo` from the
# environment variable `PKR_VAR_foo`, so the real values live in your shell (or direnv),
# not in a file that `git add -A` can sweep up.
#
# WHY THESE HAVE PLACEHOLDER DEFAULTS RATHER THAN NO DEFAULT
#   Decision D-05: this repository is authored offline and must pass `packer validate`
#   with no Proxmox host. `packer validate` runs the builder's Prepare() step, which hard
#   fails on an empty proxmox_url, username or token - and an undeclared default fails
#   even earlier, with "Unset variable". The placeholders below are deliberately
#   NON-FUNCTIONAL: 127.0.0.1 is not the lab, and a build that forgets to override them
#   fails at the first API call with a connection error or a 401, which is loud. This is
#   the same convention packer/opnsense-267/variables.pkr.hcl documents.
#
# TRAP: Packer and the bpg OpenTofu provider want the SAME API token in DIFFERENT shapes.
#   Packer:    proxmox_username = "packer@pve!buildtoken"   proxmox_token = "<uuid>"
#   OpenTofu:  api_token        = "terraform@pve!provider=<uuid>"   (ONE joined string)
# Feeding one variable to both silently 401s. See packer/README.md.
# ---------------------------------------------------------------------------------------

variable "proxmox_url" {
  type        = string
  description = "Proxmox API endpoint INCLUDING /api2/json (e.g. https://<LAB_MANAGEMENT_IP>:8006/api2/json). Note the bpg OpenTofu provider wants the same host WITHOUT /api2/json."
  # Placeholder. The real management subnet is secret and is never committed.
  default = "https://127.0.0.1:8006/api2/json"
}

variable "proxmox_username" {
  type        = string
  description = "API token owner in user@realm!tokenid form, e.g. packer@pve!buildtoken. NOT joined to the secret."
  default     = "packer@pve!buildtoken"
}

variable "proxmox_token" {
  type        = string
  sensitive   = true
  description = "The token secret (a bare UUID). Supply via PKR_VAR_proxmox_token."
  # Not a credential. A build that reaches the API with this value gets a 401,
  # which is the intended, loud failure.
  default = "unset-export-PKR_VAR_proxmox_token"
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name that runs the build."
  default     = "mutaspace-soc-node01"
}

variable "proxmox_insecure_tls" {
  type        = bool
  default     = true
  description = "Proxmox ships a self-signed certificate. True is honest for a lab; set false once a real certificate is installed."
}

variable "task_timeout" {
  type        = string
  default     = "10m"
  description = "How long to wait for a single Proxmox API task. The plugin default is 1 MINUTE, which is not enough for an ISO upload, a disk import or a template conversion."
}

# ---------------------------------------------------------------------------------------
# Placement variables
# ---------------------------------------------------------------------------------------

variable "storage_pool" {
  type        = string
  default     = "local-lvm"
  description = "Datastore for the template's disk. MUST be the same datastore the clones live on: Proxmox cannot change the target storage of a LINKED clone, so a template on the wrong pool quietly forbids linked cloning forever."
}

variable "iso_storage_pool" {
  type        = string
  default     = "local"
  description = "Datastore that holds ISO files. Required whenever Packer has to put an ISO somewhere itself."
}

variable "build_bridge" {
  type        = string
  default     = "vmbr9"
  description = "Build-plane bridge. NOT vmbr1 - vmbr1 has no route out until fw-01 exists."
}

# ---------------------------------------------------------------------------------------
# Media variables
#
# Ubuntu is one of the few images in this lab that CAN be pinned to a public URL, so it is.
# Point releases rotate: releases.ubuntu.com/24.04/ only carries the CURRENT point release,
# so when 24.04.5 lands this URL starts returning 404 and both values below must be updated
# together.
# ---------------------------------------------------------------------------------------

variable "iso_url" {
  type        = string
  default     = "https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso"
  description = "Ubuntu Server 24.04 LTS live-server ISO."
}

variable "iso_checksum" {
  type    = string
  default = "none"

  # DELIBERATELY "none", and that is not laziness.
  #
  # A checksum written from memory is worse than no checksum: it looks like verification and
  # is not. Pin it before the first real build. The authoritative value is published at
  #   https://releases.ubuntu.com/24.04/SHA256SUMS
  # and the file is signed - verify the signature with SHA256SUMS.gpg, then set:
  #   iso_checksum = "sha256:<value from SHA256SUMS>"
  #
  # Until then Packer will warn on every build, which is the correct amount of nagging.
  description = "Set to sha256:<hash> from https://releases.ubuntu.com/24.04/SHA256SUMS before building. 'none' skips verification."
}

# ---------------------------------------------------------------------------------------
# Guest identity variables
#
# The build account is baked into the golden image and therefore into every clone. Treat it
# as a lab credential with a real lifecycle: Ansible manages the accounts that matter, this
# one exists so Packer and Ansible have a way in.
# ---------------------------------------------------------------------------------------

variable "ssh_username" {
  type        = string
  default     = "labadmin"
  description = "Build/administration account created by the autoinstall."
}

variable "build_password_hash" {
  type        = string
  sensitive   = true
  description = "SHA-512 crypt hash for the build account. Generate with: mkpasswd -m sha-512 (package 'whois'). Export as PKR_VAR_build_password_hash. Needed because subiquity's identity section requires a password, and because you WILL want console access the first time a build fails."
  # Empty by default so `packer validate` runs offline (D-05). An empty crypt field in
  # the autoinstall identity section is rejected by subiquity, so a build that forgot to
  # export this fails at install time rather than shipping a passwordless template.
  default = ""
}

variable "ssh_public_key" {
  type        = string
  description = "Public key installed into the build account's authorized_keys. Export as PKR_VAR_ssh_public_key."
  default     = ""
}

variable "ssh_private_key_file" {
  type        = string
  description = "Path to the matching private key. Packer authenticates with the key, not the password, so the plaintext password never has to exist anywhere."
  # Empty means "no key file", which is what lets `packer validate` run offline. Packer
  # OPENS and PARSES this path when it is non-empty, so a wrong path fails at validate
  # time with 'ssh_private_key_file is invalid' - a genuinely useful early error.
  default = ""
}

# ---------------------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------------------

locals {
  template_name = "tpl-ubuntu-server-2404"
  template_vmid = 9000

  # Rendered once and served over Packer's built-in HTTP server as the NoCloud seed.
  #
  # NoCloud requires BOTH files. `meta-data` is intentionally empty but it must EXIST -
  # cloud-init treats a 404 on meta-data as "this is not a NoCloud datasource" and moves on,
  # and the installer then sits at an interactive prompt until ssh_timeout expires.
  #
  # THE PATHS BELOW ARE BARE AND RELATIVE ON PURPOSE. file() and templatefile() already
  # resolve relative to the TEMPLATE DIRECTORY, so writing "${path.root}/http/..." prepends
  # that directory a second time and the call only works when Packer happens to be invoked
  # from inside this folder. `packer validate packer/ubuntu-server-2404/` from the repo root
  # is the invocation that catches it. The `script =` and `output =` uses of ${path.root}
  # further down are the OPPOSITE case: those resolve against the CURRENT WORKING DIRECTORY
  # and genuinely do need the prefix.
  http_content = {
    "/meta-data" = file("http/meta-data")
    "/user-data" = templatefile("http/user-data.pkrtpl.hcl", {
      hostname       = "ubuntu-server-tpl"
      username       = var.ssh_username
      password_hash  = var.build_password_hash
      ssh_public_key = var.ssh_public_key
    })
  }
}

source "proxmox-iso" "ubuntu-server-2404" {

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
  template_description = "Ubuntu Server 24.04 LTS golden image. Built by packer/ubuntu-server-2404. Consumers: wazuh-01 (104), ubuntu-app-01 (106), nlp-01 (110). Do not edit in place - rebuild from Packer."

  # `template_name` is set explicitly rather than left to the plugin's auto-naming, because
  # before plugin v1.2.4 `packer build -force` could not find an auto-named template and the
  # rebuild failed with a name collision.

  # --- Hardware ---------------------------------------------------------------------
  os       = "l26"
  bios     = "seabios"
  cores    = 2
  sockets  = 1
  cpu_type = "host"
  memory   = 4096

  # cpu_type: the plugin default is `kvm64`, a lowest-common-denominator CPU that hides
  # host instruction sets from the guest. This is a single-node teaching lab with no live
  # migration, so there is nothing to be compatible with. `host` is both faster and honest.
  #
  # memory: the plugin default is 512 MB. Subiquity OOMs or kernel-panics well before it
  # finishes on that. 2048 is the floor for 24.04; 4096 is the value that does not make you
  # debug an installer crash that was never about your autoinstall file.

  scsi_controller = "virtio-scsi-single"

  # virtio-scsi-single (not the plugin default `lsi`) is what makes `io_thread` legal below:
  # "single" means one controller per disk, which is the arrangement an IO thread needs.

  disks {
    type         = "scsi"
    disk_size    = "20G"
    storage_pool = var.storage_pool
    io_thread    = true
    discard      = true
    ssd          = true
    cache_mode   = "none"

    # disk_size is deliberately the SMALLEST thing that fits, not the largest consumer.
    # OpenTofu grows scsi0 to the per-VM size at clone time (40G for ubuntu-app-01, 80G for
    # nlp-01, 100G for wazuh-01) and cloud-init's growpart module extends the partition and
    # filesystem on first boot. Disks can be grown. Disks cannot be shrunk. A 100G template
    # would make a 40G VM impossible.
    #
    # discard + ssd are not performance tuning, they are a safety interlock. `local-lvm` is
    # an LVM-thin pool: without discard, blocks deleted inside a guest are never returned to
    # the pool, the pool eventually fills, and a full thin pool stalls or corrupts writes
    # across EVERY VM on the host - not just the one that filled it.
    #
    # No `format` key: LVM-thin stores raw volumes. Setting a format here is only meaningful
    # on file-based storage such as a directory or NFS.
  }

  network_adapters {
    model    = "virtio"
    bridge   = var.build_bridge
    firewall = false

    # model: the plugin default is `e1000`, an emulated 2000s-era Intel NIC. virtio is a
    # paravirtualised interface - no device emulation, materially less CPU per packet.
    # Ubuntu has had the driver in-tree for well over a decade; there is no reason to
    # emulate hardware for a Linux guest.
  }

  # --- Cloud-init drive -------------------------------------------------------------
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  # This attaches an empty cloud-init drive to the TEMPLATE. It is what OpenTofu's
  # `initialization` block writes hostname, static IP, user and SSH key into at clone time.
  # Without it, every clone would come up as a byte-identical copy of the build VM.
  #
  # Known intermittent issue: the drive defaults to IDE, and there are field reports of an
  # IDE cloud-init volume being invisible on a COLD boot but appearing after a warm reset.
  # If clones ever ignore cloud-init on their very first boot, the first thing to try is
  # `cloud_init_disk_type = "scsi"` here, with a matching interface on the OpenTofu side.

  # --- Boot media -------------------------------------------------------------------
  boot_iso {
    type             = "ide"
    index            = "2"
    iso_url          = var.iso_url
    iso_checksum     = var.iso_checksum
    iso_storage_pool = var.iso_storage_pool
    unmount          = true

    # `boot_iso { }` is a block, not a set of top-level keys. The old top-level `iso_url`,
    # `iso_file` and `unmount_iso` fields still work in 1.2.x but emit removal warnings.
    # Inside the block the key is `unmount`, NOT `unmount_iso` - a small rename that
    # produces a confusing "unsupported argument" error if you copy an old example.
    #
    # index = "2" is pinned so the ISO is predictably ide2, which is what the boot order
    # below refers to.
  }

  boot      = "order=scsi0;ide2"
  boot_wait = "5s"

  # THE INSTALLER LOOP, AND WHY THIS LINE PREVENTS IT.
  # Subiquity reboots the VM when the install finishes, and Packer does not unmount the ISO
  # until the very end of the build. If the firmware preferred the CD, that reboot would
  # start the installer again, forever. Booting scsi0 FIRST works in both phases: on the
  # first boot the disk is empty and has no boot sector, so SeaBIOS falls through to ide2;
  # after the install the disk is bootable and wins.

  # --- Autoinstall seed over HTTP ---------------------------------------------------
  http_content = local.http_content

  boot_command = [
    # Ubuntu 24.04's ISO boots straight into a GRUB menu. Press `c` to drop to the GRUB
    # command line and build the kernel command line by hand.
    #
    # Do NOT copy the 22.04-era recipe (<esc><esc>e to edit the highlighted entry, or <f6>
    # for a boot-options prompt). The 24.04 menu layout changed and those keystrokes land
    # somewhere else entirely.
    "<wait5>c<wait>",

    # Three things in this line are load-bearing:
    #
    # 1. The literal token `autoinstall`. Without it, subiquity finds the seed, notices it
    #    was not explicitly told to run unattended, and stops at
    #    "Continue with autoinstall? (yes|no)". Packer sees no SSH and hangs until timeout.
    #
    # 2. The single quotes around the whole ds= value. GRUB treats `;` as a statement
    #    separator, so an unquoted ds=nocloud-net;s=http://... is parsed as TWO commands and
    #    the seed URL is silently lost.
    #
    # 3. The TRAILING SLASH on the seed URL. cloud-init has appended it automatically since
    #    23.1, so its absence is not the cause of a modern failure - but it costs nothing,
    #    it is what the documentation shows, and it keeps this line portable to older media.
    #
    # `---` separates arguments meant for the installed system's kernel command line from
    # arguments meant for the live environment.
    "linux /casper/vmlinuz autoinstall 'ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ---<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>",
  ]

  # If Packer runs somewhere the guest cannot route back to - {{ .HTTPIP }} resolving to a
  # VPN, a docker0 bridge or a WSL interface is the usual cause - the HTTP seed never
  # arrives and the installer waits forever. The fix is not to fight the interface: drop
  # http_content and deliver the same two files as `cd_files` with `cd_label = "cidata"`,
  # which turns the seed into a virtual CD and removes the network from the equation.

  # --- Communicator -----------------------------------------------------------------
  communicator           = "ssh"
  ssh_username           = var.ssh_username
  ssh_private_key_file   = var.ssh_private_key_file
  ssh_timeout            = "60m"
  ssh_handshake_attempts = 100

  # 60 minutes is not padding. Packer starts counting at boot, and the clock covers the
  # whole unattended install: partitioning, unpacking, and `apt` fetching updates plus
  # qemu-guest-agent over the build plane.

  qemu_agent = true

  # qemu_agent = true is the plugin DEFAULT, which is a trap worth naming: the plugin then
  # asks the guest agent for the VM's IP address. Neither the ISO installer nor an Ubuntu
  # cloud image ships qemu-guest-agent, so if it is not installed during the autoinstall
  # (it is - see http/user-data.pkrtpl.hcl) the build hangs waiting for an answer that
  # cannot come. The agent is also how OpenTofu learns a clone's IP later, so it belongs
  # in the image regardless.
}

build {
  name    = "ubuntu-server-2404"
  sources = ["source.proxmox-iso.ubuntu-server-2404"]

  # Step 1: do not race cloud-init.
  # Subiquity's final phase and the first cloud-init run overlap with sshd coming up, so
  # Packer can connect while apt/dpkg locks are still held. Anything that runs before this
  # completes fails intermittently, which is the worst way for it to fail.
  provisioner "shell" {
    inline = [
      "echo '==> waiting for cloud-init to finish its first boot'",
      "cloud-init status --wait || true",
      "echo '==> cloud-init finished'",
    ]
  }

  # Step 2: de-subiquity the image. See scripts/cleanup.sh - it is the single most
  # misunderstood step in golden imaging and every line of it is commented.
  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    script          = "${path.root}/scripts/cleanup.sh"
  }

  # The manifest is a build LOG, not a build INPUT. Read the difference carefully.
  #
  # For the Proxmox builder, `artifact_id` is literally the template's VMID as a string,
  # which makes it very tempting to feed straight into OpenTofu's `clone { vm_id = ... }`.
  # Do not. The entire clone block is ForceNew, so a manifest-driven VMID would mean that
  # every template rebuild destroys and recreates every VM downstream of it - including
  # dc-01. The VMID is a pinned contract here and a plan-time ASSERTION on the OpenTofu
  # side. Two mechanisms, two different jobs. This file exists so you can answer "when was
  # 9000 last rebuilt, and from what", and it is gitignored.
  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
  }
}
