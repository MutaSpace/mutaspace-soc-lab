# =============================================================================
# outputs.tf - what the lab looks like, for humans and for the test suite
# =============================================================================
#
# These outputs have two audiences and both matter.
#
#   A HUMAN, after an apply, wants to answer "what got built, and did it get the
#   addresses I expected?" without opening the Proxmox UI.
#
#   THE TEST SUITE in tofu/tests/ has no other way in. OpenTofu test files can read
#   variables, outputs and the results of previous runs - they cannot reach into a
#   module's locals. So every fact the tests assert about VMID ranges, network
#   placement and addressing has to be exposed here first. That is not a workaround;
#   it means the thing being tested is the same thing a human can read.
#
# NOTHING HERE ASKS A GUEST ANYTHING.
#   There is no output reading `ipv4_addresses` from the QEMU guest agent. Every
#   address in this lab is deterministic by design - static, or a DHCP reservation
#   pinned to a MAC that is itself an input - so it is knowable without a running
#   machine. Outputs that depend on a booted guest turn `tofu output` into a
#   liveness check and hang on anything deliberately powered off.
#

# -----------------------------------------------------------------------------
# Inventory
# -----------------------------------------------------------------------------

output "vm_ids" {
  description = "VM name -> pinned VMID, for every machine in the lab including learner endpoints."
  value       = { for name, vm in local.all_vms : name => vm.vm_id }
}

output "vm_addresses" {
  description = "VM name -> the IPv4 address the machine ends up with, whether it was configured statically or handed out as a DHCP reservation. Null for appliances that address themselves."
  value       = { for name, vm in local.all_vms : name => vm.effective_ipv4 }
}

output "vm_macs" {
  description = "VM name -> MAC address of each NIC in net0..netN order. Pinned inputs, not discovered values."
  value       = { for name, vm in local.all_vms : name => [for n in vm.nics : n.mac_address] }
}

output "vm_bridges" {
  description = "VM name -> the bridge each NIC is attached to, in net0..netN order. This is what the network placement test reads."
  value       = local.vm_bridges
}

output "vm_networks" {
  description = "VM name -> which logical plane its primary NIC is on: lan, isolated, build, or wan."
  value       = local.vm_network
}

output "vm_roles" {
  description = "VM name -> role. Only \"firewall\" is treated specially by the code."
  value       = { for name, vm in local.all_vms : name => vm.role }
}

output "vm_kinds" {
  description = "VM name -> \"core\" (shared infrastructure, VMID 100-199) or \"learner\" (per-learner endpoint, VMID 200-699). The VMID policy test uses this to know which range applies."
  value       = { for name, vm in local.all_vms : name => vm.kind }
}

output "template_ids" {
  description = "Template key -> VMID, straight from lab.yaml. The hard contract between packer/ and tofu/."
  value       = local.template_ids
}

output "network_prefixes" {
  description = "Logical plane -> the /24 prefix every host address on it must start with, e.g. lan -> \"10.10.10.\". Used by the addressing test to prove no machine has been given an address on the wrong wire."
  value       = { for key, net in local.network_meta : key => net.prefix }
}

# -----------------------------------------------------------------------------
# The seam to the firewall
# -----------------------------------------------------------------------------

output "dhcp_reservations" {
  description = <<-EOT
    Every machine that takes its address from DHCP, with the MAC that must claim it.

    This is the handover point between OpenTofu and the OPNsense configuration. The
    firewall's static mappings are generated from this same map, which is the whole
    reason analyst-01 is still 10.10.10.50 after being destroyed and rebuilt - the
    MAC is an input in lab.yaml, so the reservation never has to chase a value
    Proxmox invented at create time.
  EOT
  value       = local.dhcp_reservations
}

output "mac_address_derivation" {
  description = <<-EOT
    For every machine with a known address: the MAC written by hand in lab.yaml, and
    the MAC the BC:24:11-plus-last-three-octets convention says it should have.

    Exposed so the addressing test can prove the two agree. A mismatch means someone
    changed an address without changing the MAC, which does not break anything
    immediately - it just quietly destroys the property that makes a lease table
    readable, and it will eventually collide with another machine.
  EOT
  value = {
    for name, derived in local.derived_macs : name => {
      declared = local.all_vms[name].nics[0].mac_address
      derived  = derived
    }
  }
}

output "firewall_wan" {
  description = "fw-01's WAN addressing. SENSITIVE: this is the operator's real upstream network, which repository policy forbids committing. OpenTofu does not configure it - OPNsense has no cloud-init - but the config.xml seed generator and the runbook both need it."
  sensitive   = true
  value = {
    mode    = var.wan_ipv4_mode
    address = var.wan_ipv4_address
    gateway = var.wan_ipv4_gateway
    bridge  = local.site.wan_bridge
  }
}

# -----------------------------------------------------------------------------
# Classroom
# -----------------------------------------------------------------------------

output "learners" {
  description = "Learner id -> their Proxmox pool, PVE user, and the machines they own. Only learners actually built (capped by var.learner_count) appear."
  value = {
    for l in local.enabled_learners : l.id => {
      pool_id = "learner${l.id}"
      user_id = "learner${l.id}@pve"
      vms = {
        for name, vm in local.learner_vms : name => {
          vm_id   = vm.vm_id
          address = vm.effective_ipv4
        } if vm.learner == l.id
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Ansible
# -----------------------------------------------------------------------------

output "ansible_inventory" {
  description = <<-EOT
    The lab arranged into the groups Ansible needs, for a human to eyeball against
    the committed static inventory.

    This is NOT written to a file and NOT consumed by Ansible directly. Generating
    an inventory file from inside the same OpenTofu run creates a chicken-and-egg at
    destroy time and leaves a stale file behind after a partial apply. Since every
    address here is deterministic, the inventory can simply be committed - and
    committed is reviewable, which a generated file is not.

    The Windows split is not cosmetic. `bootstrap_windows` reaches a machine over
    NTLM as its LOCAL Administrator, before it is a domain member.
    `domain_windows` reaches the same machine over Kerberos afterwards. The account
    changes identity across the promotion reboot, and NTLM cannot delegate - which
    is also why every play that creates an Active Directory object has to run
    against dc-01 itself rather than reaching through another host.
  EOT
  value = {
    for group, members in {
      firewall = { for name, vm in local.all_vms : name => vm if vm.role == "firewall" }
      linux    = { for name, vm in local.all_vms : name => vm if vm.guest == "linux" }
      windows  = { for name, vm in local.all_vms : name => vm if vm.guest == "windows" }
      } : group => {
      hosts = {
        for name, vm in members : name => {
          ansible_host = (
            vm.effective_ipv4 != null ? vm.effective_ipv4 :
            vm.role == "firewall" ? local.network_meta["lan"].gateway :
            null
          )
          vm_id   = vm.vm_id
          plane   = local.vm_network[name]
          fqdn    = "${name}.${local.site.domain}"
          learner = vm.learner
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Bring-up visibility
# -----------------------------------------------------------------------------
# What lab.yaml declares but is currently switched off.
#
# Worth surfacing rather than leaving to a diff against git: a machine that is
# absent because somebody set enabled:false looks exactly like a machine that was
# never written, and the difference matters when a lab is half built.
output "disabled_vms" {
  value       = local.disabled_vm_names
  description = "Machines declared in lab.yaml but switched off with enabled:false."
}

# Which templates the current plan actually requires. Shrinks as machines are
# disabled, which is the mechanism that lets a partly-built lab plan at all.
output "templates_required" {
  value       = local.templates_in_use
  description = "Template key -> VMID for every template an enabled machine needs on the host."
}

# Which template each planned machine clones from. Paired with the above, this is
# what makes "why is this template still required?" answerable.
output "vm_templates" {
  value       = { for name, vm in local.all_vms : name => vm.template_key }
  description = "Machine -> template key it clones from."
}
