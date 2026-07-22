# =============================================================================
# tests/addressing.tftest.hcl - addresses and MACs stay 1:1, unique and in-subnet
# =============================================================================
#
# WHAT THIS PROTECTS
#   The lab's addressing has a property that is easy to lose and expensive to
#   rediscover: every machine's MAC address encodes its IPv4 address, and every
#   address that comes from DHCP is pinned to that MAC by a reservation in the
#   firewall.
#
#   That property is what makes the lab reproducible. analyst-01 is 10.10.10.50
#   after being destroyed and rebuilt because its MAC was an input, not something
#   Proxmox invented at create time - and the firewall's static mapping is generated
#   from the same map that configures the VM.
#
#   Break it and nothing fails immediately. The machine still boots, still gets an
#   address, still works. What stops working is everything built on top: the DHCP
#   lease table stops being readable, the saved Wazuh queries pinned to a host
#   address stop matching, and two machines eventually collide.
#
#   Silent, delayed breakage is exactly the kind a test earns its keep on.
#

mock_provider "proxmox" {
  # The mock invents a value for every computed attribute, including the `id` of an
  # uploaded snippet - and it invents a random five-character string, which the
  # provider then rejects because a Proxmox file identifier has to look like
  # "datastore:content-type/filename". Giving it a well-formed one keeps the mock
  # honest without weakening anything the tests actually check.
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/mock-user-data.yaml"
    }
  }
}



variables {
  # Assert against the COMPLETE declared lab, not just whatever is switched on
  # today. During bring-up most machines carry enabled: false because their
  # templates do not exist yet - and if these checks only covered enabled
  # machines, switching one off would switch off the checks that protect it.
  assume_all_enabled = true

  state_passphrase = "offline-test-passphrase-not-a-secret"
  learner_count    = 3
}

override_data {
  target = data.proxmox_virtual_environment_vms.templates
  values = {
    vms = [
      { vm_id = 9000, name = "tpl-ubuntu-server-2404", node_name = "swc2026", status = "stopped", template = true, tags = [] },
      { vm_id = 9001, name = "tpl-ubuntu-desktop-2404", node_name = "swc2026", status = "stopped", template = true, tags = [] },
      { vm_id = 9002, name = "tpl-win-server-2022", node_name = "swc2026", status = "stopped", template = true, tags = [] },
      { vm_id = 9003, name = "tpl-win11-client", node_name = "swc2026", status = "stopped", template = true, tags = [] },
      { vm_id = 9004, name = "tpl-opnsense-267", node_name = "swc2026", status = "stopped", template = true, tags = [] },
      { vm_id = 9005, name = "tpl-kali-rolling", node_name = "swc2026", status = "stopped", template = true, tags = [] },
    ]
  }
}

run "every_mac_and_every_address_is_unique" {
  command = plan

  assert {
    condition     = length(distinct(flatten(values(output.vm_macs)))) == length(flatten(values(output.vm_macs)))
    error_message = "Two network interfaces share a MAC address. Duplicate MACs on one bridge produce intermittent, direction-dependent connectivity that looks like a hardware fault."
  }

  assert {
    condition     = length(distinct([for a in values(output.vm_addresses) : a if a != null])) == length([for a in values(output.vm_addresses) : a if a != null])
    error_message = "Two machines have been given the same IPv4 address."
  }

  # Every MAC comes out of Proxmox's own BC:24:11 allocation, so the lab's addresses
  # look native on the host and cannot collide with a real device on the upstream
  # network.
  assert {
    condition     = alltrue([for mac in flatten(values(output.vm_macs)) : startswith(upper(mac), "BC:24:11:")])
    error_message = "A MAC address does not use the BC:24:11 prefix. That is the OUI Proxmox allocates from; staying inside it keeps lab addresses distinguishable from real hardware on the uplink."
  }

  assert {
    condition     = alltrue([for mac in flatten(values(output.vm_macs)) : can(regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", mac))])
    error_message = "A MAC address is malformed."
  }
}

run "the_mac_still_encodes_the_address" {
  command = plan

  # The convention: BC:24:11 followed by the last three octets of the machine's
  # IPv4 address written as decimal digits. 10.10.10.51 becomes BC:24:11:10:10:51.
  #
  # lab.yaml writes these out by hand for the core machines, because they are pinned
  # inputs rather than computed outputs. Learner endpoints are generated. This
  # assertion is what stops the two drifting apart - and specifically what catches
  # somebody changing a machine's address without changing its MAC, which breaks
  # nothing today and produces an unreadable lease table forever after.
  #
  # fw-01's WAN leg is absent from this map on purpose: its address is the operator's
  # real upstream network, which is not in this repository and therefore cannot be
  # derived from.
  assert {
    condition = alltrue([
      for name, pair in output.mac_address_derivation :
      upper(pair.declared) == upper(pair.derived)
    ])
    error_message = "A hand-written MAC in lab.yaml no longer matches the address it is supposed to encode. Either the address changed and the MAC did not, or the convention was broken by hand. Both are fixed in lab.yaml."
  }

  # There should be one derived MAC for every machine with a known address, which
  # proves the check above is not passing vacuously over an empty map.
  assert {
    condition     = length(output.mac_address_derivation) == length([for a in values(output.vm_addresses) : a if a != null])
    error_message = "The MAC derivation map does not cover every addressed machine, so the check above may be passing without testing anything."
  }
}

run "every_address_is_on_the_wire_it_claims_to_be_on" {
  command = plan

  # A machine on vmbr2 with a 10.10.10.x address is not a typo that gets noticed.
  # It boots, it has no gateway that answers, and it presents as "the network is
  # broken" - which sends whoever is debugging it to the firewall, which is fine.
  assert {
    condition = alltrue([
      for name, address in output.vm_addresses :
      startswith(address, output.network_prefixes[output.vm_networks[name]])
      if address != null
    ])
    error_message = "A machine has an address that does not belong to the network its NIC is attached to. Check the nic.bridge and ipv4.address pair for that machine in lab.yaml."
  }

  # Reservations must sit OUTSIDE the firewall's dynamic pool.
  #
  # The pool is 10.10.10.100-.200. A static mapping inside that range is a
  # configuration error in every DHCP server worth using: ISC dhcpd (which OPNsense
  # uses) will either warn and ignore it or hand the address to somebody else first
  # and then have a conflict. This is precisely why learner endpoints start at .60
  # rather than at the .150 the original design sketch suggested.
  assert {
    condition = alltrue([
      for name, r in output.dhcp_reservations :
      tonumber(split(".", r.address)[3]) < 100 || tonumber(split(".", r.address)[3]) > 200
    ])
    error_message = "A DHCP reservation falls inside the dynamic pool (10.10.10.100-.200). Static mappings must live outside the range the server hands out, or the same address can be leased twice."
  }

  # Nothing may claim .1: that is the firewall on every plane.
  assert {
    condition = alltrue([
      for name, address in output.vm_addresses :
      tonumber(split(".", address)[3]) != 1
      if address != null && output.vm_roles[name] != "firewall"
    ])
    error_message = "A machine has been given host address .1, which is the firewall on every plane in this lab."
  }
}

run "the_dhcp_reservation_map_is_complete_and_consistent" {
  command = plan

  # The reservation map is the seam between OpenTofu and the OPNsense
  # configuration. If it disagrees with the VM definitions in either direction, the
  # firewall hands out an address the machine does not expect, or fails to hand out
  # one it is waiting for.
  assert {
    condition = alltrue([
      for name, r in output.dhcp_reservations :
      r.mac_address == output.vm_macs[name][0] && r.address == output.vm_addresses[name]
    ])
    error_message = "A DHCP reservation does not match the MAC and address of the machine it names."
  }

  # analyst-01 and win-client-01 are the two core machines that use DHCP, and their
  # reservations are named in the existing build documentation and in both completed
  # incident-scenario walkthroughs. If these move, written coursework stops being
  # correct.
  assert {
    condition = alltrue([
      output.dhcp_reservations["analyst-01"].address == "10.10.10.50",
      output.dhcp_reservations["win-client-01"].address == "10.10.10.51",
    ])
    error_message = "analyst-01 must reserve 10.10.10.50 and win-client-01 must reserve 10.10.10.51. Both addresses are written into existing documentation and into two completed incident-scenario labs."
  }

  # THE COMPLETE SET, NOT JUST THE FAMOUS TWO.
  #
  # This is the assertion that would have caught a real bug. The firewall's
  # config.xml used to carry a hand-written list of two reservations while this
  # map produced five: the per-learner Windows clients are DHCP machines too
  # (lab.yaml -> learner_endpoints.win-client, host_base 60, host_step 2), and
  # three of them had a pinned MAC on the hypervisor and no reservation on the
  # firewall.
  #
  # Nothing failed. Those three booted, took a pool address from .100-.200, and
  # looked healthy - while sitting on addresses the design does not document.
  # The Packer side now derives this same list from lab.yaml
  # (packer/opnsense-267/opnsense.pkr.hcl), so the two cannot disagree; this
  # assertion is the tripwire on the LAN half of that agreement.
  #
  # learner_count is 3 in this file's `variables` block, matching the default in
  # tofu/variables.tf. Change one and this list changes with it, deliberately.
  #
  # Compared as one joined string rather than as two lists, because `sort()`
  # returns a list(string) while the literal below is a tuple, and `==` between
  # those two is false even when every element matches - a genuinely confusing
  # failure that reports "5 unchanged elements hidden".
  assert {
    condition = join(", ", sort([
      for name, r in output.dhcp_reservations :
      "${r.hostname}=${r.address}" if r.network == "lan"
      ])) == join(", ", [
      "analyst-01=10.10.10.50",
      "win-client-01=10.10.10.51",
      "win-client-l01=10.10.10.60",
      "win-client-l02=10.10.10.62",
      "win-client-l03=10.10.10.64",
    ])
    error_message = "The set of SOC LAN DHCP reservations has changed. Every entry here must also be seeded into fw-01's config.xml, which packer/opnsense-267/ derives from lab.yaml with a matching learner_count. A machine with a reservation on one side and not the other still boots - it just silently takes a pool address instead."
  }
}
