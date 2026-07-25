# packer/opnsense-267/variables.pkr.hcl
#
# WHAT THIS FILE IS
#   Every input to the OPNsense 26.7 golden-template build (VMID 9004,
#   `tpl-opnsense-267`), which OpenTofu clones into `fw-01` (VMID 100).
#
# WHY IT EXISTS AS A SEPARATE FILE
#   The builder in `opnsense.pkr.hcl` is already the most fragile artifact in
#   this repository. Keeping the knobs somewhere else means a learner can read
#   the *values* of the lab without having to read the boot-command timing, and
#   an operator can change an address without touching the fragile part.
#
# WHY EVERY VARIABLE HAS A DEFAULT
#   Decision D-05: this code is authored offline, before the Proxmox host
#   exists. `packer validate` runs the builder's Prepare() step, which hard
#   fails if `proxmox_url`, `username` or `token` are empty. Placeholder
#   defaults are what make `packer validate .` pass with no host, no var-file
#   and no environment. They are deliberately non-functional: a build that
#   forgets to override them fails at the API call, not silently against the
#   wrong host.
#
# SECRETS POLICY (README.md:347)
#   No real management IP, no password, no token, and no physical MAC appears
#   in this file or in any file in this directory. Credentials come from the
#   environment only:
#
#       export PKR_VAR_proxmox_url='https://<LAB_MANAGEMENT_IP>:8006/api2/json'
#       export PKR_VAR_proxmox_token='<uuid>'
#       export PKR_VAR_root_password='<the console/root password>'
#       export PKR_VAR_root_password_hash="$(openssl passwd -6 '<same password>')"
#
#   ⚠️ Packer and the bpg OpenTofu provider want the SAME Proxmox credential in
#   DIFFERENT shapes and sharing one variable silently returns 401:
#
#       Packer : username = "packer@pve!buildtoken"   token = "<uuid>"
#       bpg    : api_token = "terraform@pve!provider=<uuid>"   (one string)
#
#   They are separate variables on purpose. Do not "simplify" them into one.

# ---------------------------------------------------------------------------
# Proxmox API connection
# ---------------------------------------------------------------------------

variable "proxmox_url" {
  type        = string
  description = "Proxmox API endpoint. Packer wants the /api2/json suffix; the bpg OpenTofu provider explicitly does NOT. This is a real difference between the two tools, not a typo."
  # Placeholder. The real management subnet is secret and is never committed.
  default = "https://127.0.0.1:8006/api2/json"
}

variable "proxmox_username" {
  type        = string
  description = "API token ID in user@realm!tokenname form. Not a secret on its own — the token value is."
  default     = "packer@pve!buildtoken"
}

variable "proxmox_token" {
  type        = string
  sensitive   = true
  description = "API token secret (a bare UUID). Set via PKR_VAR_proxmox_token."
  # Not a credential. A build that reaches the API with this value gets a 401,
  # which is the intended, loud failure.
  default = "unset-export-PKR_VAR_proxmox_token"
}

variable "proxmox_insecure_tls" {
  type        = bool
  description = "Skip TLS verification against the Proxmox API. True by default because a fresh PVE install serves a self-signed certificate; set false once the host has a trusted cert."
  default     = true
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name that runs the build."
  default     = "mutaspace-soc-node01"
}

variable "task_timeout" {
  type        = string
  description = "How long Packer waits on a single Proxmox API task. The OPNsense install writes ~1.5 GB to disk, so the stock 1m default is not enough."
  default     = "20m"
}

# ---------------------------------------------------------------------------
# Storage and node placement
# ---------------------------------------------------------------------------

variable "storage_pool" {
  type        = string
  description = "Datastore for the template's disk. MUST be the same datastore the clones live on: pve-docs states the target storage of a linked clone cannot be changed, so a template on `local` can never be linked-cloned onto `local-lvm`."
  default     = "local-lvm"
}

variable "iso_storage_pool" {
  type        = string
  description = "Datastore holding the ISO shelf. Also where Packer uploads the generated config-seed ISO — additional_iso_files built from cd_content REQUIRE iso_storage_pool or the builder's Prepare() hard-fails before the build starts."
  default     = "local"
}

variable "opnsense_iso_file" {
  type        = string
  description = <<-EOT
    The OPNsense installer image, as a Proxmox volume ID.

    ⚠️ MANUALLY PREPARED ARTIFACT. There is no iso_url here on purpose.
    OPNsense publishes the DVD image bzip2-compressed, and Proxmox cannot boot
    a compressed image. The operator does this once, on the Proxmox host:

      cd /var/lib/vz/template/iso
      curl -fLO https://mirror.dns-root.de/opnsense/releases/26.7/OPNsense-26.7-dvd-amd64.iso.bz2
      curl -fLO https://mirror.dns-root.de/opnsense/releases/26.7/OPNsense-26.7-checksums-amd64.sha256
      sha256sum -c --ignore-missing OPNsense-26.7-checksums-amd64.sha256   # verify the .bz2
      bunzip2 OPNsense-26.7-dvd-amd64.iso.bz2
      sha256sum OPNsense-26.7-dvd-amd64.iso                                # record in iso-shelf.md

    Note the checksums file covers the COMPRESSED artifact. The sha256 of the
    decompressed .iso is not published by the project, so record the value you
    computed yourself in docs/proxmox/iso-shelf.md and compare on rebuild.
    No sha256 is hardcoded in this repository because none was verified while
    this file was written.
  EOT
  default     = "local:iso/OPNsense-26.7-dvd-amd64.iso"
}

# ---------------------------------------------------------------------------
# Template identity — a hard contract with lab.yaml and OpenTofu
# ---------------------------------------------------------------------------

variable "template_vm_id" {
  type        = number
  description = "VMID of the produced template. 9004 is a contract: OpenTofu's clone{} block is entirely ForceNew, so a VMID that drifts destroys and recreates fw-01."
  default     = 9004
}

variable "template_name" {
  type        = string
  description = "Name of the produced template."
  default     = "tpl-opnsense-267"
}

variable "opnsense_version" {
  type        = string
  description = "OPNsense release this template targets. The boot_command is tuned to this exact release — see the warning block in opnsense.pkr.hcl."
  default     = "26.7"
}

# ---------------------------------------------------------------------------
# Build plane (vmbr9)
# ---------------------------------------------------------------------------
#
# In a greenfield lab nothing on vmbr1 can reach the internet until fw-01 is
# routing, and fw-01 is itself a VM. vmbr9 breaks that circularity: it is a
# bridge with no physical port, and the Proxmox host masquerades it. Packer
# builds here; OpenTofu re-points network_device.bridge to vmbr0/1/2 at clone
# time, which is free because `bridge` is not a ForceNew attribute.
#
# ⚠️ Proxmox's own masquerade documentation example uses 10.10.10.1/24. That is
# fw-01's LAN address in this lab. Never copy it.

variable "build_bridge" {
  type        = string
  description = "Bridge the template is built on."
  default     = "vmbr9"
}

variable "build_address" {
  type        = string
  description = "Temporary address the half-built firewall gives itself on the build plane so it can reach the package mirrors. Nothing serves DHCP on vmbr9, so this is set by hand from the console during the build and is thrown away when the real config is imported."
  default     = "10.99.0.90"
}

variable "build_prefix" {
  type        = number
  description = "Prefix length of the build plane."
  default     = 24
}

variable "build_gateway" {
  type        = string
  description = "Build-plane gateway. This is the Proxmox host itself, which masquerades vmbr9 out through the physical NIC."
  default     = "10.99.0.1"
}

variable "upstream_dns" {
  type        = string
  description = "Resolver used during the build, and the firewall's own resolver afterwards. A public resolver, so not a secret."
  default     = "1.1.1.1"
}

# ---------------------------------------------------------------------------
# Firewall identity
# ---------------------------------------------------------------------------

variable "fw_hostname" {
  type        = string
  description = "Hostname baked into config.xml."
  default     = "fw-01"
}

variable "lab_domain" {
  type        = string
  description = "DNS domain of the lab. Also handed to DHCP clients as the domain-name option."
  default     = "mutaspace.local"
}

variable "timezone" {
  type        = string
  description = "Firewall timezone. fw-01 is the lab NTP server, so this is the clock every lab log timestamp is eventually compared against."
  default     = "Etc/UTC"
}

variable "root_password" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Root password typed at the installer console by the boot_command.

    Intentionally EMPTY by default. An empty password makes the OPNsense
    installer reject the entry and re-prompt, so a build that forgot to set
    this hangs and fails visibly. That is a much better outcome than shipping
    a firewall template with a well-known default password committed to a
    public repository.

    Set with:  export PKR_VAR_root_password='...'
  EOT
  default     = ""
}

variable "root_password_hash" {
  type        = string
  sensitive   = true
  description = <<-EOT
    The SAME password as root_password, but crypt-hashed, because config.xml
    stores a hash and replaces the user database when it is imported.

      export PKR_VAR_root_password_hash="$(openssl passwd -6 '<password>')"

    Two variables for one password is genuinely awkward. It exists because HCL
    has no crypt() function, so Packer cannot derive the hash from the
    plaintext. Deriving it would be the obvious improvement if a future version
    moves this step into a provisioner instead of a boot_command.
  EOT
  default     = ""
}

variable "root_authorized_keys" {
  type = string
  # NOT sensitive. This is the root account's SSH PUBLIC key, which is not a
  # secret --- but it is env-driven per the repo convention (README.md:347) so
  # that no operator's key is committed and each host bakes its own.
  description = <<-EOT
    Root SSH PUBLIC key baked into config.xml as <authorizedkeys>, so that
    key-based root SSH works on a from-scratch clone of this template with zero
    manual configuration. Give it in the normal one-line authorized_keys form
    (e.g. "ssh-ed25519 AAAA... comment"); opnsense.pkr.hcl base64-encodes it,
    because OPNsense stores authorizedkeys base64-encoded in config.xml.

    Intentionally EMPTY by default so `packer validate` runs offline. A build
    that forgets this bakes an empty <authorizedkeys> and password SSH is the
    only way in --- scripts/fw-preflight.sh catches that before a rebuild.

    Set with:  export PKR_VAR_root_authorized_keys="$(cat ~/.ssh/mutaspace_lab_ed25519.pub)"
  EOT
  default     = ""
}

variable "fw_api_key" {
  type = string
  # NOT sensitive. The OPNsense API "key" is the HTTP-Basic username-equivalent
  # of the credential pair --- a public identifier, like an access-key ID. The
  # SECRET half is fw_api_secret_hash below. Env-driven per repo convention.
  description = <<-EOT
    OPNsense API key baked into config.xml as <apikeys><item><key>, so the
    firewall API authenticates on a from-scratch clone with zero manual
    bootstrap. Stored VERBATIM (plaintext) in config.xml --- OPNsense treats it
    as the username half of HTTP Basic auth, not as a secret.

    Intentionally EMPTY by default so `packer validate` runs offline (D-05).
    A build that forgets it bakes an empty <apikeys> and the API automation
    has nothing to authenticate with --- scripts/fw-preflight.sh catches that
    before a rebuild.

    Generate once (with its secret):  openssl rand 60 | openssl base64 -A
    Set with:  export PKR_VAR_fw_api_key='<generated key>'
  EOT
  default     = ""
}

variable "fw_api_secret_hash" {
  type        = string
  sensitive   = true
  description = <<-EOT
    The sha512-crypt ($6$) hash of the OPNsense API SECRET, baked into
    config.xml as <apikeys><item><secret>. OPNsense verifies the pair with
    password_verify(), which accepts a random-salt `openssl passwd -6` hash
    --- no per-install salt is needed, which is what makes baking it possible.

    The PLAINTEXT secret never appears in this repository or in any Packer
    variable: it lives only in the operator's gitignored .envrc (FW_API_SECRET,
    for the API clients), and this variable carries only its hash:

      export PKR_VAR_fw_api_secret_hash="$(openssl passwd -6 "$FW_API_SECRET")"

    Intentionally EMPTY by default so `packer validate` runs offline (D-05).
    scripts/fw-preflight.sh blocks a rebuild when it is empty or not $6$-shaped.
  EOT
  default     = ""
}

# ---------------------------------------------------------------------------
# WAN (vmbr0) — the only address in the lab that is a real-world secret
# ---------------------------------------------------------------------------

variable "wan_if" {
  type        = string
  description = "FreeBSD device name of the WAN NIC. VirtIO NICs enumerate as vtnetN in PCI order, and OpenTofu attaches fw-01's NICs in the order vmbr0, vmbr1, vmbr2."
  default     = "vtnet0"
}

variable "wan_mode" {
  type        = string
  description = "Either \"dhcp\" or \"static\". DHCP is the default because it keeps the real management subnet out of this repository entirely."
  default     = "dhcp"

  validation {
    condition     = contains(["dhcp", "static"], var.wan_mode)
    error_message = "The variable wan_mode must be either \"dhcp\" or \"static\"."
  }
}

variable "wan_address" {
  type        = string
  sensitive   = true
  description = "WAN IPv4 address when wan_mode = static. SECRET — the real management subnet is never committed. Public docs use <LAB_MANAGEMENT_IP>."
  default     = ""
}

variable "wan_prefix" {
  type        = number
  description = "WAN prefix length when wan_mode = static."
  default     = 24
}

variable "wan_gateway" {
  type        = string
  sensitive   = true
  description = "WAN default gateway when wan_mode = static. SECRET, same reason as wan_address."
  default     = ""
}

# ---------------------------------------------------------------------------
# SOC LAN (vmbr1) — 10.10.10.0/24
# ---------------------------------------------------------------------------

variable "lan_if" {
  type        = string
  default     = "vtnet1"
  description = "FreeBSD device name of the SOC LAN NIC."
}

variable "lan_address" {
  type        = string
  default     = "10.10.10.1"
  description = "Gateway address for the SOC LAN. Every VM on vmbr1 points here."
}

variable "lan_prefix" {
  type        = number
  default     = 24
  description = "SOC LAN prefix length."
}

variable "lan_dhcp_from" {
  type        = string
  default     = "10.10.10.100"
  description = "First address of the SOC LAN DHCP pool. Matches the as-built lab recorded in docs/network/dhcp-validation.md."
}

variable "lan_dhcp_to" {
  type        = string
  default     = "10.10.10.200"
  description = "Last address of the SOC LAN DHCP pool."
}

variable "dc_address" {
  type        = string
  default     = "10.10.10.10"
  description = "dc-01. This is both the DNS server handed to DHCP clients and the source address of the deliberate outbound rule — see the rule's comment in config/config.xml.pkrtpl.hcl."
}

# THERE IS DELIBERATELY NO `dhcp_reservations` VARIABLE HERE.
#
# There used to be, and it was wrong in the way that is hardest to see: a
# hand-written list of two reservations that had to agree, by hand, with a list
# OpenTofu computes from lab.yaml. It did not agree. OpenTofu produces five
# reservations with `learner_count = 3` (analyst-01, win-client-01 and one
# per-learner Windows client); the literal list carried only the first two. The
# three learner clients would have booted, taken a pool address from
# 10.10.10.100-200, and looked perfectly healthy while sitting on the wrong
# address - the exact failure this seam exists to prevent.
#
# The reservations are now DERIVED from lab.yaml, in opnsense.pkr.hcl, by the
# same rules tofu/locals.tf uses. See the comment on `local.dhcp_reservations`
# there. `learner_count` below is the only input that list still needs.

variable "learner_count" {
  type        = number
  default     = 3
  description = <<-EOT
    How many of the learners listed in lab.yaml get a DHCP reservation seeded
    into the firewall's config.xml.

    MUST MATCH `learner_count` in tofu/variables.tf (same default, 3). OpenTofu
    pins a MAC for every learner endpoint it builds; a reservation that is not
    in this config.xml means that machine silently takes a pool address instead
    of the .60/.62/.64 the design promises.

    A reservation for a learner who is not built is harmless - Kea simply never
    sees that MAC - so if the two ever have to differ, this is the one to make
    larger.
  EOT

  validation {
    # Same ceiling as tofu/variables.tf. Above 20 the per-learner address block
    # (host .60 upward, step 2) collides with the DHCP pool at .100, and the
    # MAC-from-IP convention runs out of two-digit octets.
    condition     = var.learner_count >= 0 && var.learner_count <= 20
    error_message = "The variable learner_count must be between 0 and 20, matching tofu/variables.tf."
  }
}

# ---------------------------------------------------------------------------
# Isolated network (vmbr2) — 10.10.20.0/24
# ---------------------------------------------------------------------------

variable "isolated_if" {
  type        = string
  default     = "vtnet2"
  description = "FreeBSD device name of the isolated NIC. Becomes OPT1."
}

variable "isolated_address" {
  type        = string
  default     = "10.10.20.1"
  description = "Gateway address for the isolated network (kali-01, untrusted-01, nlp-01)."
}

variable "isolated_prefix" {
  type        = number
  default     = 24
  description = "Isolated network prefix length."
}

# ---------------------------------------------------------------------------
# Suricata (decision D-04)
# ---------------------------------------------------------------------------

variable "suricata_enabled" {
  type        = bool
  default     = true
  description = "Enable the os-suricata plugin in the seeded config. The plugin is always installed by the build; this only decides whether it starts."
}

variable "suricata_ips_mode" {
  type        = bool
  default     = false
  description = <<-EOT
    IPS (blocking) mode. FALSE on purpose.

    D-04 puts Suricata inline in the TOPOLOGICAL sense — it sits on the
    firewall, in the path, so it needs no port mirror. That is not the same as
    OPNsense's "IPS mode", which switches the interfaces to netmap and lets
    Suricata drop packets. In a teaching lab a false positive that black-holes
    the classroom mid-exercise costs more than the detection is worth, and
    netmap also disables hardware offloading on the interface.

    Flip this to true deliberately, as an exercise, not by default.
  EOT
}

variable "suricata_interfaces" {
  type        = string
  default     = "lan,opt1"
  description = "OPNsense interface keys Suricata watches. WAN is excluded because everything interesting is already visible on the inside of the NAT, where addresses are still lab addresses."
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
