# =============================================================================
# modules/proxmox-vm/versions.tf - the module's own provider requirement
# =============================================================================
#
# WHY A MODULE NEEDS THIS AT ALL
#   A child module does not inherit the root module's provider REQUIREMENTS, only
#   its configured provider instances. Without this block OpenTofu sees a resource
#   whose name starts with "proxmox_" and guesses the provider is
#   `hashicorp/proxmox` - which does not exist. The error it produces
#   ("Missing required provider ... hashicorp/proxmox") says nothing about the real
#   cause, which is this file being absent.
#
#   No version constraint is repeated here beyond the source. The root module pins
#   0.111.1 exactly; restating a constraint in the module would create a second
#   place to forget to update.
#
terraform {
  required_version = ">= 1.12.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}
