# =============================================================================
# lab-vms.tf - the nine core machines
# =============================================================================
#
# ONE MODULE CALL, NOT NINE RESOURCES.
#
#   The temptation with a lab this size is to write out nine `resource` blocks,
#   one per machine, because each one is then visible in full at a glance. Do not.
#   Every clone landmine - the ForceNew clone block, the linked-clone datastore
#   rule, the disk block that resets what it does not mention, stop_on_destroy,
#   the guest-agent timeout - would then have to be right nine times, and the ninth
#   is where it goes wrong. It gets handled once, in modules/proxmox-vm, and
#   applies to everything.
#
#   What is lost is per-machine visibility in the HCL. That is bought back by
#   lab.yaml, which is where a human is supposed to look anyway.
#
# ORDERING, AND WHY THERE IS NO depends_on HERE
#   Nothing on vmbr1 can route until fw-01 is up, and nothing can resolve a name
#   until dc-01 is up. That is a real ordering constraint, but it is a constraint on
#   the GUEST software, not on the Proxmox API calls that create the VMs - creating
#   a VM never needs another VM to be running.
#
#   So the ordering is expressed where it actually applies:
#     * `startup { order }` (from lab.yaml) so a host reboot brings the lab back in
#       a working sequence;
#     * `tofu apply -parallelism=1`, because Proxmox returns lock errors under
#       concurrent clone I/O rather than queueing;
#     * a first apply targeted at the firewall, then the rest, documented in the
#       IaC runbook.
#
#   A depends_on chain between for_each instances is not expressible anyway, and
#   faking it by splitting the firewall back out into its own resource would
#   reintroduce exactly the duplication this module exists to remove.
#

locals {
  # Cloud-init configuration per machine, assembled here rather than in locals.tf
  # because it has to reference the snippet resources in snippets.tf.
  #
  # Null for appliances: OPNsense has no cloud-init, and attaching a drive it will
  # never read is worse than attaching nothing, because it looks configured.
  vm_cloud_init = {
    for name, vm in local.all_vms : name => (
      contains(["linux", "windows"], vm.guest) ? {
        # nocloud is what cloud-init on Linux expects. configdrive2 is what Proxmox
        # generates for a Windows ostype and what Cloudbase-Init looks for.
        type = vm.guest == "windows" ? "configdrive2" : "nocloud"

        dns_domain  = local.site.domain
        dns_servers = local.vm_dns_servers[name]

        # "dhcp" is a literal Proxmox accepts in place of an address. Machines with
        # a reservation still go through DHCP - the reservation lives in the
        # firewall and is keyed on the MAC pinned in lab.yaml - because exercising
        # the DHCP path is itself part of what the lab teaches.
        ipv4_address = (
          vm.ipv4_mode == "static" ? vm.ipv4_address :
          vm.ipv4_mode == "dhcp" ? "dhcp" :
          null
        )
        ipv4_gateway = vm.ipv4_mode == "static" ? vm.ipv4_gateway : null

        user_data_file_id = proxmox_virtual_environment_file.user_data[name].id
        meta_data_file_id = vm.guest == "linux" ? proxmox_virtual_environment_file.meta_data[name].id : null
      } : null
    )
  }
}

module "vm" {
  source = "./modules/proxmox-vm"

  for_each = local.core_vms

  name        = each.value.name
  vm_id       = each.value.vm_id
  node_name   = local.site.node
  description = each.value.description
  pool_id     = proxmox_virtual_environment_pool.core.pool_id

  # Tags are how the lab is filtered in the Proxmox UI and in scripts. `plane`
  # matters most: it is immediately visible which machines are on the isolated
  # segment and which are not.
  tags = [
    "mutaspace",
    "core",
    "plane-${local.vm_network[each.key]}",
    each.value.guest,
  ]

  template_vm_id = each.value.template_vm_id
  full_clone     = each.value.full_clone
  datastore_id   = local.site.datastore

  cores            = each.value.cores
  memory_dedicated = each.value.memory_dedicated
  memory_floating  = each.value.memory_floating

  disk_size      = each.value.disk_size
  disk_interface = each.value.disk_interface

  nics = each.value.nics

  bios    = each.value.bios
  machine = each.value.machine
  os_type = each.value.os_type

  cloud_init    = local.vm_cloud_init[each.key]
  agent_enabled = each.value.agent

  started       = each.value.started
  startup_order = each.value.startup_order

  role       = each.value.role
  wan_bridge = local.site.wan_bridge

  # Nothing is cloned until every template lab.yaml refers to has been proven to
  # exist. Without this the first failure of a forgotten Packer run is an API error
  # about a VMID, several minutes into an apply that has already created things.
  depends_on = [terraform_data.template_exists]
}
