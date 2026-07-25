# =============================================================================
# variables.tf - the few things that cannot live in lab.yaml
# =============================================================================
#
# WHY THIS FILE IS SHORT
#   lab.yaml is the file a human edits. Anything that describes the lab belongs
#   there, where a learner can read it. A variable here has to earn its place by
#   being one of exactly two things:
#
#     1. A SECRET. The management/WAN subnet is the operator's real home network,
#        and the repository's secrets policy forbids committing it. Passwords and
#        keys are the same category.
#
#     2. AN OPERATOR KNOB. Something that legitimately differs between one run and
#        the next - how many learners fit in tonight's RAM budget, whether this
#        particular host has a real certificate.
#
#   If a value is neither of those, it goes in lab.yaml.
#
# WHERE THE VALUES COME FROM
#   `tofu/terraform.tfvars` (gitignored) for the secrets, or TF_VAR_* environment
#   variables. `tofu/terraform.tfvars.example` shows the shape without the values.
#

# -----------------------------------------------------------------------------
# State encryption
# -----------------------------------------------------------------------------

variable "state_passphrase" {
  description = <<-EOT
    Passphrase used to derive the AES-GCM key that encrypts terraform.tfstate and
    any saved plan file. Minimum 16 characters - the pbkdf2 key provider rejects
    anything shorter. Deliberately has no default: a missing passphrase must be a
    hard error, not a silent fallback to unencrypted state.

    Supply it as TF_VAR_state_passphrase, never in a .tfvars file that could be
    committed.
  EOT
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Proxmox endpoint behaviour
# -----------------------------------------------------------------------------
# The endpoint URL and the API token itself are NOT variables. They are read
# directly from PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN by the provider, so
# there is no attribute in this repository for someone to paste a real token into.

variable "pve_insecure" {
  description = <<-EOT
    Skip TLS certificate verification when talking to the Proxmox API.

    Defaults to false, which is the secure choice and the opposite of most Proxmox
    tutorials. A fresh Proxmox install serves a self-signed certificate, so a lab
    will usually need this set to true in a gitignored terraform.tfvars - but that
    should be a deliberate decision, not an inherited default.
  EOT
  type        = bool
  default     = false
}

variable "pve_min_tls" {
  description = <<-EOT
    Minimum TLS version the provider will negotiate. The provider's own default is
    "1.3". Proxmox VE 8.x hosts commonly only offer TLS 1.2, and the failure mode
    is confusing - it presents as an unreachable host rather than as a TLS
    mismatch. Set "1.2" if that happens.
  EOT
  type        = string
  default     = "1.3"

  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.pve_min_tls)
    error_message = "pve_min_tls must be one of 1.0, 1.1, 1.2 or 1.3."
  }
}

variable "pve_ssh_username" {
  description = <<-EOT
    PAM (Linux) account on the Proxmox node used for the SFTP path that uploads
    cloud-init snippets. An API token is not a login, so this is a genuinely
    separate credential from PROXMOX_VE_API_TOKEN.

    Leave null to fall back to the PROXMOX_VE_SSH_USERNAME environment variable.
  EOT
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# The WAN / management plane - secret by policy
# -----------------------------------------------------------------------------
# fw-01's WAN leg sits on vmbr0, which carries the operator's real upstream
# network. Every other address in this lab is RFC1918 space the documentation
# already publishes, so it lives in lab.yaml. These three do not.
#
# OpenTofu does not configure these addresses - OPNsense has no cloud-init, and
# its interface assignment comes from the config.xml that Packer seeds into the
# template. They are declared here because the seed generator and the operator's
# runbook both need them, and because a sensitive output is a safer place to keep
# them than a wiki page.

variable "wan_ipv4_mode" {
  description = <<-EOT
    How fw-01's WAN interface gets its address: "dhcp" (take a lease from the
    upstream router - the usual choice for a lab hanging off a home network) or
    "static".
  EOT
  type        = string
  default     = "dhcp"

  validation {
    condition     = contains(["dhcp", "static"], var.wan_ipv4_mode)
    error_message = "wan_ipv4_mode must be either \"dhcp\" or \"static\"."
  }
}

variable "wan_ipv4_address" {
  description = <<-EOT
    fw-01's WAN address in CIDR form, e.g. "10.0.0.50/24". SECRET - this is the
    real upstream subnet. Only meaningful when wan_ipv4_mode is "static"; leave
    null otherwise.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "wan_ipv4_gateway" {
  description = <<-EOT
    Upstream default gateway for fw-01's WAN leg, e.g. "10.0.0.1". SECRET, same
    reasoning as wan_ipv4_address. Only meaningful when wan_ipv4_mode is "static".
  EOT
  type        = string
  default     = null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Guest credentials
# -----------------------------------------------------------------------------

variable "lab_ssh_authorized_keys" {
  description = <<-EOT
    Public SSH keys installed into the cloud-init admin account on every Linux
    guest. Public keys are not secrets, but they identify a person, so they are an
    input rather than a committed constant.

    An empty list is allowed and is a legitimate configuration for a lab that is
    driven entirely from the Proxmox console - but no key and no password means no
    remote access at all, and Ansible will not be able to reach the guests.
  EOT
  type        = list(string)
  default     = []
}

variable "lab_admin_password" {
  description = <<-EOT
    Optional password for the cloud-init admin account on Linux guests. Prefer SSH
    keys and leave this null; a password is here only because a teaching lab
    sometimes needs console logins.

    Never put this in a committed file. TF_VAR_lab_admin_password, or a gitignored
    terraform.tfvars.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Classroom capacity
# -----------------------------------------------------------------------------

variable "learner_count" {
  description = <<-EOT
    How many of the learners listed in lab.yaml actually get VMs built.

    This is a capacity lever, not a roster. The roster lives in lab.yaml so that it
    is reviewable in git; this number lets an instructor build only the first N of
    them to fit the RAM available tonight.

    The arithmetic: the shared core (fw-01, dc-01, wazuh-01, analyst-01,
    ubuntu-app-01, win-client-01) is about 28 GB, the Proxmox host wants ~4 GB, and
    each learner's endpoint pair is another 8 GB. On a 64 GB host that is three
    learners with the research plane powered off. Set this higher only if you have
    also raised the memory.
  EOT
  type        = number
  default     = 3

  validation {
    condition     = var.learner_count >= 0 && var.learner_count <= 20 && floor(var.learner_count) == var.learner_count
    error_message = "learner_count must be a whole number between 0 and 20. Above 20 the per-learner address block (host .60 upward, step 2) runs into the DHCP pool at .100."
  }
}

# -----------------------------------------------------------------------------
# assume_all_enabled
# -----------------------------------------------------------------------------
# Ignore every `enabled: false` in lab.yaml and treat the lab as fully declared.
#
# This exists for the TEST SUITE, and the reason is worth stating because the
# alternative is a subtle rot.
#
# tofu/tests/ asserts invariants about the whole lab: that no two machines claim
# the same VMID, that every MAC encodes its address, that the learner VMID
# formula holds, that the firewall's DHCP reservations match the machines they
# are written for. Those are properties of the lab as DESIGNED.
#
# During bring-up most machines are switched off, because their templates do not
# exist yet. If the tests only checked what happens to be enabled, then turning a
# machine off would also turn off the checks that protect it - and the suite
# would get quieter exactly as the lab got less complete. A test that passes
# because there is nothing left to test is worse than a failing one.
#
# So the tests set this to true and assert against the full declared lab. A plan
# or apply leaves it false and builds only what is enabled.
variable "assume_all_enabled" {
  type        = bool
  default     = false
  description = "Test-only. Ignore enabled:false in lab.yaml so invariants are checked against the complete declared lab."
}

# -----------------------------------------------------------------------------
# Proxmox node name override
# -----------------------------------------------------------------------------
variable "pve_node" {
  type    = string
  default = ""

  # The Proxmox node name, as PROXMOX knows it - not a name you choose.
  #
  # Leave empty to use `site.node` from lab.yaml. Set it when your host is named
  # something else, which it will be: lab.yaml is committed with the node name of
  # the machine this lab was developed on, and yours is different.
  #
  #   export TF_VAR_pve_node=my-proxmox-host
  #   # or in terraform.tfvars:  pve_node = "my-proxmox-host"
  #
  # Get the value with `hostname` on the host, or `pvesh get /nodes`.
  #
  # Getting this wrong produces a 404 against a node that does not exist, which
  # reads as "the API is broken" rather than "the name is wrong" - so
  # tofu/templates.tf asserts at plan time that the node actually exists and says
  # what the real node names are when it does not.
  description = "Proxmox node name. Empty means use site.node from lab.yaml."
}
