# =============================================================================
# learners.tf - per-learner endpoint machines
# =============================================================================
#
# THE SHAPE, AND WHY IT IS THIS SHAPE
#   The obvious classroom design gives every learner their own everything: their
#   own firewall, their own domain controller, their own SIEM. It is also the
#   design that does not fit. A full private stack is roughly 26 GB, which caps a
#   64 GB host at two learners - and two learners is not a classroom.
#
#   So infrastructure is shared and only the endpoints are private. Everybody uses
#   the same fw-01, dc-01 and wazuh-01; each learner gets a Windows client to
#   generate telemetry from and a Kali box to attack with. That is 8 GB a head, and
#   three of them fit alongside the shared core with the research plane powered off.
#
#   This also happens to be more realistic than the alternative. A SOC analyst does
#   not own the domain controller.
#
# THE TWO FORMULAS
#   VMID:    200 + (learner_index * 10) + role_offset
#   Address: host_base + (learner_index * host_step) on the role's network
#
#   Both are driven by the learner's POSITION in the lab.yaml roster, which has a
#   consequence worth stating plainly: inserting a learner in the middle of the list
#   renumbers everyone after them, and vm_id is ForceNew, so it destroys and
#   recreates their machines. Append; do not insert.
#
#   Leaving a ten-wide VMID block per learner is deliberate slack. Adding a third
#   endpoint role later costs a line in lab.yaml and renumbers nothing.
#
# WHY THE HOSTNAME COMES FROM CLOUD-INIT AND NOT FROM DHCP
#   Wazuh identifies an agent by name. If the hostname came from a DHCP option, a
#   snapshot rollback could bring the machine back under a different name, the agent
#   would re-register as a new agent, and every saved detection query pinned to
#   `agent.name` would quietly stop matching. The name is set in the image.
#

module "learner_vm" {
  source = "./modules/proxmox-vm"

  for_each = local.learner_vms

  name        = each.value.name
  vm_id       = each.value.vm_id
  node_name   = local.site.node
  description = each.value.description

  # The pool is the unit of ownership - see access.tf. A learner's ACL is granted
  # on their pool, so membership here is what actually decides what they can touch.
  pool_id = proxmox_virtual_environment_pool.learner[each.value.learner].pool_id

  tags = [
    "mutaspace",
    "learner",
    "learner-${each.value.learner}",
    "plane-${local.vm_network[each.key]}",
    each.value.guest,
  ]

  template_vm_id = each.value.template_vm_id

  # Kali endpoints are linked clones. A learner is expected to break their machine
  # and roll it back repeatedly, so a copy-on-write layer over the golden image is
  # both faster to create and far cheaper on the thin pool than N full 40 GB copies.
  full_clone   = each.value.full_clone
  datastore_id = local.site.datastore

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

  # Built but left powered off. The instructor starts a learner's pair at the
  # beginning of a session; leaving nine endpoint VMs idling would eat the RAM
  # headroom the shared core needs.
  started       = each.value.started
  startup_order = each.value.startup_order

  wan_bridge = local.site.wan_bridge

  depends_on = [terraform_data.template_exists]
}
