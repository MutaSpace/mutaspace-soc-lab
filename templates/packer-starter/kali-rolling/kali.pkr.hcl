# kali.pkr.hcl
#
# WHAT THIS IS
#   The Packer template that builds golden image VMID 9005, `tpl-kali-rolling`, from the
#   Kali Linux installer ISO.
#
# WHY IT EXISTS
#   Two VMs on the isolated segment come from this image: kali-01 (108, attack simulation)
#   and untrusted-01 (109, trust-boundary research). Both live on vmbr2 / 10.10.20.0/24
#   behind a default-deny policy toward the SOC LAN. They are the only VMs in the lab that
#   are supposed to be hostile.
#
# TWO CONSTRAINTS THAT SHAPE THIS FILE
#
#   1. BOTH CONSUMERS ARE LINKED CLONES.
#      A linked clone shares the template's disk and only stores its own changes, which is
#      what makes two attack boxes affordable on a single-node lab. It also imposes rules:
#      a linked clone cannot be moved to a different datastore, so this template MUST be
#      written to the same pool the clones live on (local-lvm), and OpenTofu's clone block
#      must omit datastore_id whenever full = false.
#
#   2. THE SMALLEST CONSUMER CAPS THE TEMPLATE DISK.
#      untrusted-01 has a 20 GB disk. Disks can be grown at clone time and can never be
#      shrunk, so the template disk is 20 GB - not kali-01's 40 GB. Getting this backwards
#      does not fail at build time; it fails later, when untrusted-01 turns out to be
#      impossible to create.
#
# WHY THIS IS A PRESEED AND NOT AN AUTOINSTALL
#   Kali is Debian, and its installer is debian-installer. It has no subiquity, no
#   autoinstall, and no cloud-config answer file. The unattended mechanism is preseeding:
#   a file of debconf answers fetched over HTTP, referenced from the kernel command line.
#   Same idea as the Ubuntu templates, completely different syntax.
#
# HONEST STATUS
#   Every boot_command in this repository is unverifiable without hardware, and this one is
#   the least verified of the three. Kali is a ROLLING distribution: the ISO filename, the
#   bootloader menu and the installer's question set all move. Expect to re-tune this on
#   the first real build and after every Kali release. That is the cost of a rolling base
#   image, and it is a fair trade for an attack box that ships current tooling.

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
# No real credential is committed; every value below comes from a PKR_VAR_* environment
# variable. The placeholder defaults exist for decision D-05: `packer validate` runs the
# builder's Prepare(), which hard fails on an empty URL, username or token, so without
# them this template cannot be validated offline. They are deliberately non-functional.
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
  default     = "example-soc-node01"
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
  description = "Datastore for the template disk. For this template it is not a preference but a requirement: linked clones cannot cross datastores, so the template must live where kali-01 and untrusted-01 live."
}

variable "iso_storage_pool" {
  type        = string
  default     = "local"
  description = "Datastore that holds ISO files."
}

variable "build_bridge" {
  type        = string
  default     = "vmbr9"
  description = "Build-plane bridge. Note that the CLONES land on vmbr2, not here - the build plane is the only network with a route out while the lab is being built."
}

# ---------------------------------------------------------------------------------------
# Media variables
#
# READ THIS BEFORE THE FIRST BUILD.
#
# Kali is rolling. cdimage.kali.org keeps only recent releases, so a pinned filename stops
# resolving once it ages out, and the version in the URL below is a PLACEHOLDER that has NOT
# been checked against the mirror.
#
#   1. Open https://cdimage.kali.org/ and find the current release directory.
#   2. Take the exact `kali-linux-<version>-installer-amd64.iso` filename from it.
#   3. Take its SHA256 from the SHA256SUMS file in the same directory (signed - verify it
#      against SHA256SUMS.gpg).
#   4. Set both values here, and record them in docs/proxmox/iso-shelf.md.
#
# There is also a `current/` directory that always points at the newest release, but the
# filename inside it still carries the version, so it does not save you from step 2 and it
# would make the build non-reproducible anyway. Pin the version.
# ---------------------------------------------------------------------------------------

variable "iso_url" {
  type = string
  # Verified resolving 2026-07-23: cdimage.kali.org 302-redirects this to
  # https://kali.download/base-images/kali-2026.2/... The 2025.4 placeholder this
  # replaced had already aged out and 404'd - Kali keeps only recent releases, so
  # re-verify this filename at https://cdimage.kali.org/ before every build and bump
  # iso_checksum in lockstep.
  default     = "https://cdimage.kali.org/kali-2026.2/kali-linux-2026.2-installer-amd64.iso"
  description = "Kali installer ISO. Verify the filename still exists at https://cdimage.kali.org/ before building; Kali rolls roughly quarterly and old images are removed. Ignored when kali_iso_file is set."
}

variable "iso_checksum" {
  type = string

  # Pinned 2026-07-23 for kali-linux-2026.2-installer-amd64.iso, read from
  # https://kali.download/base-images/kali-2026.2/SHA256SUMS (the mirror that
  # cdimage.kali.org's 302 redirects to; the cdimage SHA256SUMS served empty over
  # plain curl). Verify against SHA256SUMS.gpg for a proper signature check.
  #
  # WHY THIS IS NOW A REAL VALUE, NOT "none": the template shipped with "none" while
  # it was written offline, on the principle that a checksum typed from memory is
  # worse than none because it LOOKS like verification. This one was read from Kali's
  # published sums file at build time. If you bump iso_url to a newer Kali release you
  # MUST bump this too - a stale checksum fails the download loudly, which is the safe
  # failure, not the silent one where a truncated ISO boots strangely weeks later.
  default     = "sha256:6dbefacc95e3b556c19c48e8bae39b8b505e2d3a1aba0bfb7ab62b036c3d2ba3"
  description = "sha256:<hash> from the SHA256SUMS file next to the ISO. Bump alongside iso_url. Ignored when kali_iso_file is set (a host-side ISO is trusted as already-verified)."
}

variable "kali_iso_file" {
  type    = string
  default = ""

  # A Kali installer ISO ALREADY on the Proxmox host, e.g.
  #   kali_iso_file = "local:iso/kali-linux-2026.2-installer-amd64.iso"
  # When set, Packer neither downloads nor uploads anything and boots straight from it.
  #
  # WHY A KALI-SPECIFIC NAME AND NOT THE UBUNTU TEMPLATE'S `iso_file`:
  #   common.pkrvars.hcl binds the generic `iso_file` to the UBUNTU server ISO, shared
  #   across every build. If this template declared `iso_file` it would silently inherit
  #   that value and try to boot a Kali VM from the Ubuntu installer. This is exactly why
  #   the Windows templates use their own `windows_iso_file` instead of `iso_file`, set in
  #   a per-template pkrvars file rather than in common. This follows that precedent.
  #
  # Empty means "use iso_url + iso_checksum", which downloads to the workstation and then
  # uploads to the host - correct for a first run, but a ~4 GB push over the VPN every
  # build, so prefer the host-side ISO once it is in place.
  description = "Pre-uploaded Kali ISO on the host, e.g. local:iso/kali-linux-2026.2-installer-amd64.iso. Takes precedence over iso_url. Distinct from common's `iso_file` (which is the Ubuntu ISO)."
}

variable "http_bind_address" {
  type    = string
  default = ""

  # The address Packer's built-in HTTP server binds to, and what {{ .HTTPIP }} expands
  # to in the boot command's preseed/url=. Empty means auto-detect.
  #
  # PIN THIS whenever the workstation has more than one interface. Packer advertises a
  # SINGLE auto-detected address, and that heuristic has no idea which of the workstation's
  # interfaces the build VM can route back to. This workstation reaches the lab over a
  # WireGuard tunnel and has ~ten local interfaces (docker0, several br-*, virbr0, tun0);
  # if Packer advertises any of the wrong ones the installer requests the preseed from an
  # address that does not exist on its network, the fetch fails, and debian-installer falls
  # back to asking questions nobody answers - a silent hang identical to a mangled boot
  # command. common.pkrvars.hcl pins this to the WireGuard address for exactly this reason.
  #
  # WAS MISSING on the first real build: the variable existed nowhere and the source block
  # never set http_bind_address, so Packer auto-detected and the preseed fetch was at the
  # mercy of interface ordering. Wired in to match packer/ubuntu-server-2404.
  description = "Address Packer serves the preseed on. Empty = auto-detect (only safe with one interface); pin it on a multi-homed workstation."
}

# ---------------------------------------------------------------------------------------
# Guest identity variables
# ---------------------------------------------------------------------------------------

variable "ssh_username" {
  type        = string
  default     = "labadmin"
  description = "Build/administration account. Deliberately NOT Kali's default 'kali' user - a predictable username on the lab's designated attack box is a bad habit to teach, and the same account name across all templates keeps the Ansible inventory simple."
}

variable "build_password_hash" {
  type        = string
  sensitive   = true
  description = "SHA-512 crypt hash for the build account. Generate with: mkpasswd -m sha-512 (package 'whois'). Export as PKR_VAR_build_password_hash."
  # Empty so `packer validate` runs offline (D-05). An empty crypt field in a preseed
  # produces a locked account, so a forgotten export fails visibly at first login.
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
  template_name = "tpl-kali-rolling"
  template_vmid = 9005

  # debian-installer fetches ONE file, by the URL given on the kernel command line. There is
  # no meta-data/user-data pair here - that is a NoCloud convention and this is not NoCloud.
  #
  # THE PATH BELOW IS BARE AND RELATIVE ON PURPOSE. templatefile() already resolves relative
  # to the TEMPLATE DIRECTORY, so "${path.root}/http/..." prepends that directory a second
  # time and only works when Packer is invoked from inside this folder. The `script =` and
  # `output =` uses of ${path.root} further down are the opposite case - those resolve
  # against the CURRENT WORKING DIRECTORY and do need the prefix.
  http_content = {
    "/preseed.cfg" = templatefile("http/preseed.cfg.pkrtpl.hcl", {
      hostname       = "kali-tpl"
      domain         = "example.local"
      username       = var.ssh_username
      password_hash  = var.build_password_hash
      ssh_public_key = var.ssh_public_key
    })
  }
}

source "proxmox-iso" "kali-rolling" {

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
  template_description = "Kali Rolling golden image. Built by packer/kali-rolling. Consumers: kali-01 (108) and untrusted-01 (109), both LINKED clones on vmbr2. Deleting or rebuilding this template in place breaks both."

  # That last sentence is not decoration. A linked clone depends on the template's disk
  # existing and unchanged. Template rebuilds are a NEW VMID plus a re-clone cycle, never an
  # in-place edit - which is why the 9000-9099 block has room for successors.

  # --- Hardware ---------------------------------------------------------------------
  os       = "l26"
  bios     = "seabios"
  cores    = 2
  sockets  = 1
  cpu_type = "host"
  memory   = 2048

  # 2048 rather than the Ubuntu templates' 4096: debian-installer in text mode is far
  # lighter than subiquity, and this matches untrusted-01's allocation. kali-01 gets 4096 at
  # clone time - memory is not baked into the image the way disk geometry is.

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    disk_size    = "20G"
    storage_pool = var.storage_pool
    io_thread    = true
    discard      = true
    ssd          = true
    cache_mode   = "none"

    # 20G because untrusted-01 is 20G and it is a LINKED clone. See the header. This is the
    # one number in this file that cannot be changed casually.
    #
    # It is also why the preseed installs a minimal Kali rather than the full
    # kali-linux-default metapackage: the tool set would not fit, and toolsets are Ansible's
    # job anyway. See http/preseed.cfg.pkrtpl.hcl.
    #
    # discard + ssd keep the LVM-thin pool from filling with blocks the guest already freed.
    # Linked clones make this more important, not less: several thin volumes now share one
    # pool and one of them filling it stalls writes for every VM on the host.
  }

  network_adapters {
    model    = "virtio"
    bridge   = var.build_bridge
    firewall = false
  }

  # --- Cloud-init drive -------------------------------------------------------------
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  # Kali does not ship cloud-init; the preseed installs it. This is the least certain part
  # of this template and it is flagged rather than assumed - see the honest-status note in
  # scripts/cleanup.sh step 3. If cloud-init cannot be made to configure Kali's networking
  # reliably, the fallback is to let the clones come up on DHCP and have Ansible write the
  # static addresses (10.10.20.10 and 10.10.20.20). The lab still works; it just gains a
  # step.

  # --- Boot media -------------------------------------------------------------------
  boot_iso {
    type  = "ide"
    index = "2"

    # Two ways to supply the installer, mirroring packer/ubuntu-server-2404:
    #   kali_iso_file set -> boot an ISO ALREADY on the host, nothing downloaded or
    #                        uploaded. Strongly preferred once the ISO is on the host,
    #                        because the alternative re-pushes ~4 GB over the VPN every build.
    #   kali_iso_file ""  -> download from iso_url to the workstation and verify iso_checksum,
    #                        then upload to the host. Correct for a first run or a clean host.
    # Precedence is explicit so a half-set pair fails loudly rather than doing something in
    # between. Note this uses kali_iso_file, NOT the generic iso_file, which common.pkrvars
    # binds to the Ubuntu ISO - see the kali_iso_file variable comment.
    iso_file         = var.kali_iso_file != "" ? var.kali_iso_file : null
    iso_url          = var.kali_iso_file == "" ? var.iso_url : null
    iso_checksum     = var.kali_iso_file == "" ? var.iso_checksum : null
    iso_storage_pool = var.iso_storage_pool
    unmount          = true

    # Inside the block the key is `unmount`, NOT `unmount_iso` - the top-level spelling
    # emits a removal warning and the wrong in-block spelling is an "unsupported argument".
  }

  boot      = "order=scsi0;ide2"
  boot_wait = "10s"

  # Type slowly. Packer drives the console through QEMU's `sendkey`, one keystroke at a
  # time over the API, and at full speed keystrokes are DROPPED (Proxmox plugin issues
  # #237/#220, "sendkey: EOF"). The Ubuntu templates learned this the hard way - a dropped
  # character in `initrd /casper/initrd` produced a kernel panic, "VFS: Unable to mount
  # root fs on unknown-block(0,0)". This template's boot_command is LONGER and more fragile
  # (a full preseed/url= line typed at a `boot:` prompt), so the same 100ms interval applies
  # here. WAS MISSING on the first real build - copied from ubuntu-server-2404.
  boot_keygroup_interval = "100ms"

  # Disk first, CD second: on the first boot the disk is empty and SeaBIOS falls through to
  # the ISO; after the install the disk is bootable and wins. Without this, the installer's
  # closing reboot starts the installer again.
  #
  # boot_wait is 10s rather than the Ubuntu templates' 5s. The Kali ISO's boot menu has a
  # graphical splash that takes a moment to be ready for input, and keystrokes sent to a
  # bootloader that is not listening yet are simply lost.

  # --- Preseed over HTTP ------------------------------------------------------------
  http_content = local.http_content

  # Bind the seed server to a pinned address on a multi-homed workstation. Empty =
  # auto-detect. WAS MISSING on the first real build - without it Packer advertises an
  # auto-detected {{ .HTTPIP }}, and on this ten-interface workstation the installer can
  # request the preseed from an unreachable address and silently hang. See the variable.
  http_bind_address = var.http_bind_address

  boot_command = [
    # The Kali installer ISO boots isolinux on BIOS firmware. <esc> at the menu drops to a
    # `boot:` prompt where a kernel and its command line can be typed by hand.
    #
    # This is the equivalent of the Ubuntu templates' GRUB `c` step and it is just as
    # version-sensitive: if Kali switches this media to GRUB, this line stops working and
    # the fix is the GRUB console form instead.
    "<esc><wait>",

    # `install` selects the text-mode installer. `installgui` would start the graphical one,
    # which is slower and has no advantage when nobody is watching.
    "install<wait>",

    # auto=true is the important one and it is not obvious.
    #   Normally debian-installer asks about locale and networking BEFORE it is able to
    #   fetch anything over HTTP, which means a preseed URL arrives too late to answer those
    #   questions. auto=true raises the priority of the preseed fetch so that networking is
    #   brought up first and the file is loaded before the early questions are asked.
    #
    # priority=critical suppresses every question that has a default, so anything the
    # preseed forgets is answered rather than displayed. Combined with auto=true, an
    # incomplete preseed produces a WRONG install rather than a HUNG one - which is the
    # better failure, because it is visible.
    " auto=true priority=critical<wait>",

    # The preseed URL. Packer's built-in HTTP server binds to {{ .HTTPIP }} on a random
    # port; the guest reaches it over the build plane.
    #
    # If Packer runs somewhere the guest cannot route back to - {{ .HTTPIP }} resolving to a
    # VPN, docker0 or a WSL interface is the usual cause - this fetch fails and the
    # installer falls back to asking questions nobody will answer. The fix is not to fight
    # the interface: deliver the preseed as a `cd_files` virtual CD instead and reference it
    # as file:///cdrom/preseed.cfg.
    #
    # Written as `preseed/url=` in full rather than the `url=` shorthand. The shorthand is an
    # alias, and when it is used with the `auto` boot LABEL the installer appends a path of
    # its own (/d-i/<suite>/./preseed.cfg) to whatever you gave it. Spelling out the real
    # question name removes any question about which of those two behaviours applies here.
    " preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<wait>",

    # Locale and keyboard on the command line as well as in the preseed. They are asked
    # early enough that answering them twice is cheaper than debugging which one won.
    " locale=en_US.UTF-8 keymap=us<wait>",

    # Hostname and domain, likewise. This is the TEMPLATE's hostname; cloud-init overwrites
    # it on each clone.
    " hostname=kali-tpl domain=example.local<wait>",

    # `---` separates installer arguments from arguments for the installed system's kernel.
    " ---<wait>",
    "<enter>",
  ]

  # --- Communicator -----------------------------------------------------------------
  communicator         = "ssh"
  ssh_username         = var.ssh_username
  ssh_private_key_file = var.ssh_private_key_file
  # TEMPORARILY 15m while diagnosing the first-build SSH failure (see below). Restore to
  # 60m once the build is green: 60m is not padding, it covers the whole unattended install
  # plus apt fetching packages over the network before sshd is even reachable.
  #
  # FIRST REAL BUILD FAILED HERE, 2026-07-23: the install completed but Packer sat at
  # "Waiting for SSH to become available..." for the full timeout and then deleted the VM
  # with "Timeout waiting for SSH." Packer discovers the guest IP through the qemu guest
  # agent (qemu_agent = true), so the two candidate causes are (a) the agent never came up
  # so there was no IP to connect to, or (b) the IP was known but sshd/key auth rejected the
  # connection. Root cause and fix recorded where they belong once diagnosed live.
  ssh_timeout            = "60m"
  ssh_handshake_attempts = 100

  qemu_agent = true

  # The plugin defaults qemu_agent to true and then asks the guest agent for the VM's IP
  # address. No agent, no answer, and the build waits at "Waiting for SSH" until the timeout
  # with no useful error. qemu-guest-agent is in the preseed's package list for this reason,
  # and OpenTofu uses the same agent later to read a clone's address.
}

build {
  name    = "kali-rolling"
  sources = ["source.proxmox-iso.kali-rolling"]

  provisioner "shell" {
    inline = [
      "echo '==> waiting for cloud-init to finish its first boot (if it is present at all)'",
      # `|| true` because cloud-init is installed by the preseed rather than shipped with the
      # image, and a missing binary must not fail the build before the cleanup script has had
      # a chance to run and tell us what actually happened.
      "command -v cloud-init >/dev/null 2>&1 && cloud-init status --wait || true",
      "echo '==> proceeding'",
    ]
  }

  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    script          = "${path.root}/scripts/cleanup.sh"
  }

  # A build log, not a build input. The VMID is a pinned contract; feeding the manifest into
  # OpenTofu's ForceNew clone block would recreate every VM on every template rebuild - and
  # for a LINKED clone that is not even a recoverable mistake, it is a broken parent disk.
  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
  }
}
