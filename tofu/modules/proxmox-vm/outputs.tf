# =============================================================================
# modules/proxmox-vm/outputs.tf - what the module tells the root about a machine
# =============================================================================
#
# Note what is NOT here: `ipv4_addresses`, the list the QEMU guest agent reports.
# Reading it makes every plan depend on a guest being booted and the agent
# answering, which turns a plan into a liveness check and hangs when a machine is
# deliberately powered off. Every address in this lab is deterministic - either
# statically configured or a DHCP reservation pinned to a MAC - so it is known
# without asking the guest.
#

output "vm_id" {
  description = "The pinned VMID."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  description = "VM name, which is also the guest hostname and the Wazuh agent name."
  value       = proxmox_virtual_environment_vm.this.name
}

output "mac_addresses" {
  description = "MAC address of each NIC, in net0..netN order. Pinned inputs, echoed back so the root module can template the firewall's DHCP reservations from the same source."
  value       = [for n in var.nics : n.mac_address]
}

output "bridges" {
  description = "Bridge each NIC is attached to, in net0..netN order."
  value       = [for n in var.nics : n.bridge]
}
