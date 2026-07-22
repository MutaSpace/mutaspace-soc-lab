# =============================================================================
# modules/proxmox-vm/variables.tf - the module's interface
# =============================================================================
#
# Everything the module needs, and nothing it can work out for itself. The types
# are written out in full rather than as `any` on purpose: a typo in lab.yaml
# should fail at plan time with a message naming the field, not at apply time with
# a Proxmox API error naming a QEMU option.
#

# -----------------------------------------------------------------------------
# Identity
# -----------------------------------------------------------------------------

variable "name" {
  description = "VM name as it appears in Proxmox. Also the guest hostname, which is what Wazuh uses as agent.name - so it must be stable across rebuilds or saved detection queries stop matching."
  type        = string
}

variable "vm_id" {
  description = "Pinned VMID. ForceNew - changing it destroys and recreates the machine. Never let this float; random_vm_ids is the wrong default for a lab where the numbering is itself a teaching artifact."
  type        = number

  validation {
    condition     = var.vm_id >= 100 && var.vm_id <= 999999
    error_message = "vm_id must be at least 100. Proxmox reserves 0-99."
  }
}

variable "node_name" {
  description = "Proxmox node to build on."
  type        = string
}

variable "description" {
  description = "Free text shown in the Proxmox UI. Explains what the machine is for, so somebody looking at the host without this repository still has a chance."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Proxmox tags. Used for filtering in the UI and for grouping in scripts."
  type        = list(string)
  default     = []
}

variable "pool_id" {
  description = "Proxmox resource pool. Pools are how a learner is granted rights over their own machines and nobody else's."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Where the machine comes from
# -----------------------------------------------------------------------------

variable "template_vm_id" {
  description = "VMID of the golden template to clone. A constant from lab.yaml, never a value derived from a Packer build artifact - the whole clone block is ForceNew."
  type        = number
}

variable "full_clone" {
  description = <<-EOT
    true  = full clone, an independent copy of the disk.
    false = linked clone, a copy-on-write layer over the template's image.

    Linked clones are cheap to create and destroy, which suits machines that get
    reset constantly. They cannot be moved to another datastore, which is why the
    module refuses to set a target datastore when this is false.
  EOT
  type        = bool
  default     = true
}

variable "datastore_id" {
  description = "Datastore for the VM's disk. Must be the same datastore the template lives on when full_clone is false."
  type        = string
}

# -----------------------------------------------------------------------------
# Hardware
# -----------------------------------------------------------------------------

variable "cores" {
  description = "vCPU count."
  type        = number
}

variable "cpu_type" {
  description = "QEMU CPU model. \"host\" passes the physical CPU's feature flags straight through, which matters for nested virtualisation and for anything doing crypto. The Proxmox default is kvm64, a 2008-era feature set."
  type        = string
  default     = "host"
}

variable "memory_dedicated" {
  description = "RAM ceiling in MB."
  type        = number
}

variable "memory_floating" {
  description = <<-EOT
    Balloon floor in MB. 0 disables ballooning entirely.

    Setting this equal to memory_dedicated turns ballooning ON: the host may
    reclaim memory the guest is not using. Setting it to 0 pins the full amount.

    Never balloon a JVM that commits its heap up front - the Wazuh indexer is
    exactly that, and reclaiming its heap forces the guest to swap.
  EOT
  type        = number
  default     = 0
}

variable "disk_size" {
  description = "Disk size in GB. Growing a cloned disk is fine; shrinking it below the template's size is not possible."
  type        = number
}

variable "disk_interface" {
  description = "Disk bus, e.g. scsi0. Must be scsi or sata - the module sets ssd = true, which QEMU rejects on a virtio-blk disk."
  type        = string
  default     = "scsi0"

  validation {
    condition     = can(regex("^(scsi|sata)[0-9]+$", var.disk_interface))
    error_message = "disk_interface must be scsiN or sataN. virtio-blk is rejected because the module sets ssd = true and iothread = true, neither of which is valid on that bus."
  }
}

variable "nics" {
  description = <<-EOT
    Network interfaces, IN ORDER. The first entry becomes net0, the second net1,
    and so on, and the guest sees them in that order.

    This ordering is load-bearing for the firewall: net0 is WAN, net1 is LAN,
    net2 is OPT. Reorder them in a refactor and the firewall comes up with WAN and
    LAN swapped, which takes the lab off the internet and puts a DHCP server on the
    management bridge, with nothing in the plan output to explain why.
  EOT
  type = list(object({
    bridge      = string
    model       = optional(string, "virtio")
    mac_address = string
    role        = optional(string, "primary")
  }))

  validation {
    condition     = length(var.nics) > 0
    error_message = "A VM needs at least one network interface."
  }

  validation {
    condition     = alltrue([for n in var.nics : can(regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", n.mac_address))])
    error_message = "Every NIC needs a pinned MAC address in aa:bb:cc:dd:ee:ff form. MACs are inputs here, not outputs, because the firewall's DHCP reservations are templated from the same map."
  }
}

variable "bios" {
  description = "\"seabios\" or \"ovmf\". Windows 11 needs ovmf. Leave null to inherit whatever the template has, which is almost always the right answer for a clone."
  type        = string
  default     = null
}

variable "machine" {
  description = "QEMU machine type, e.g. \"q35\". Windows 11 needs q35. Leave null to inherit from the template."
  type        = string
  default     = null
}

variable "scsi_hardware" {
  description = "SCSI controller. virtio-scsi-single gives each disk its own controller, which is what makes iothread = true actually do anything."
  type        = string
  default     = "virtio-scsi-single"
}

variable "os_type" {
  description = <<-EOT
    Proxmox ostype: l26 for modern Linux, win11 for Windows 11 and Server
    2022/2025, "other" for appliances such as OPNsense.

    On Windows this is not cosmetic. Proxmox decides how to treat a cloud-init
    password based on ostype, and if ostype is not a Windows value at the moment
    the password is set, Proxmox crypt-hashes it and the guest then tries to use
    the hash as the plaintext password. That ordering trap is the origin of the
    widely repeated folklore that "Windows cloud-init passwords do not work".
  EOT
  type        = string
  default     = "l26"
}

# -----------------------------------------------------------------------------
# Guest configuration
# -----------------------------------------------------------------------------

variable "cloud_init" {
  description = <<-EOT
    Cloud-init settings, or null for a guest that configures itself (OPNsense).

    type: "nocloud" for Linux, "configdrive2" for Windows/Cloudbase-Init.

    ipv4_address may be a CIDR ("10.10.10.30/24") or the literal string "dhcp".

    user_data_file_id points at a snippet uploaded by snippets.tf. Note that this
    attribute is ForceNew: editing the CONTENT of a snippet while its filename
    stays the same does not recreate the VM (and therefore does not re-run
    cloud-init either - the change is invisible until the machine is rebuilt),
    but changing the filename destroys and recreates the VM. Filenames here are
    deliberately stable and snippet edits are treated as needing a deliberate
    rebuild.
  EOT
  type = object({
    type              = string
    dns_domain        = optional(string)
    dns_servers       = optional(list(string), [])
    ipv4_address      = optional(string)
    ipv4_gateway      = optional(string)
    user_data_file_id = optional(string)
    meta_data_file_id = optional(string)
  })
  default = null

  validation {
    condition     = var.cloud_init == null || contains(["nocloud", "configdrive2"], try(var.cloud_init.type, ""))
    error_message = "cloud_init.type must be \"nocloud\" (Linux) or \"configdrive2\" (Windows / Cloudbase-Init)."
  }
}

variable "user_account" {
  description = <<-EOT
    Cloud-init user/password/keys set through Proxmox's own fields rather than
    through a user-data snippet.

    This exists for completeness and is normally left null. Proxmox implements
    user_data_file_id as `cicustom user=`, which REPLACES the user-data it would
    otherwise generate from these fields - so setting both is not an error, it is
    just misleading, because the user_account half silently does nothing. The
    module refuses the combination rather than letting somebody debug it at 2am.

    It is also worth knowing that the username here is ignored entirely on Windows;
    Cloudbase-Init takes the account name from its own configuration file inside
    the guest.
  EOT
  type = object({
    username = optional(string)
    password = optional(string)
    keys     = optional(list(string), [])
  })
  default   = null
  sensitive = true
}

variable "agent_enabled" {
  description = <<-EOT
    Whether the QEMU guest agent is genuinely installed and running in the image.

    Set this true only when the agent is actually baked into the template. When it
    is not, the provider cannot tell "no agent" from "slow boot", so it waits out
    the agent timeout - fifteen minutes by default - on EVERY create and EVERY
    refresh. Meanwhile Proxmox's shutdown path holds a lock that blocks stop until
    it times out too. It is the single most expensive wrong boolean in this file.
  EOT
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

variable "started" {
  description = "Whether the VM should be running. The research plane is built but left off, because 64 GB does not stretch to everything at once."
  type        = bool
  default     = true
}

variable "on_boot" {
  description = "Start automatically when the Proxmox host boots."
  type        = bool
  default     = true
}

variable "startup_order" {
  description = "Proxmox boot order. Lower starts first. fw-01 is 1 and dc-01 is 2, because nothing on the LAN can route or resolve until those two are up. Null leaves the machine out of the ordered startup entirely."
  type        = number
  default     = null
}

# -----------------------------------------------------------------------------
# Placement safety
# -----------------------------------------------------------------------------

variable "role" {
  description = "What this machine is for. Only \"firewall\" is special-cased, by the preconditions below."
  type        = string
  default     = "generic"
}

variable "wan_bridge" {
  description = "The bridge carrying the real upstream network. Only the firewall is permitted to touch it, and it must be that machine's net0."
  type        = string
}
