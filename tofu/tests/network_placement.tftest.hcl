# =============================================================================
# tests/network_placement.tftest.hcl - nothing escapes onto the real network
# =============================================================================
#
# WHY THIS TEST EXISTS
#   There is exactly one Proxmox host. There is no staging environment, no second
#   machine to try things on, and the host runs coursework. The usual safety net -
#   "apply it somewhere harmless and look" - does not exist here, and this test
#   suite is what replaces it.
#
#   The specific failure it is built to catch is a lab VM landing on vmbr0. That
#   bridge carries the operator's real home network and the Proxmox management
#   address. A machine there is not a cosmetic mistake:
#
#     * the lab's deliberately vulnerable machines become reachable from a real
#       network, and from the internet if the upstream router forwards anything;
#     * a second DHCP server on the household LAN breaks the household;
#     * none of it is visible in `tofu plan` output, which shows a bridge name and
#       nothing about what that bridge means.
#
#   One wrong string in lab.yaml does all of that.
#
# HOW IT RUNS WITH NO HOST
#   `mock_provider` replaces every provider call with synthesised data, so `plan`
#   never opens a socket. The one thing that has to be supplied by hand is the
#   template data source: the real one asks the host what templates it has, and an
#   empty mock would trip the "you forgot to run Packer" precondition in
#   templates.tf before any of these assertions were reached.
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
  # The encryption block in versions.tf needs a passphrase. This one is not a
  # secret: a test's state is held in memory and thrown away.
  state_passphrase = "offline-test-passphrase-not-a-secret"

  learner_count = 3
}

# What the host would report if every Packer build had been run. Declared once at
# file level so every run block below inherits it.
override_data {
  target = data.proxmox_virtual_environment_vms.templates
  values = {
    vms = [
      { vm_id = 9000, name = "tpl-ubuntu-server-2404", node_name = "mutaspace-soc-node01", status = "stopped", template = true, tags = [] },
      { vm_id = 9001, name = "tpl-ubuntu-desktop-2404", node_name = "mutaspace-soc-node01", status = "stopped", template = true, tags = [] },
      { vm_id = 9002, name = "tpl-win-server-2022", node_name = "mutaspace-soc-node01", status = "stopped", template = true, tags = [] },
      { vm_id = 9003, name = "tpl-win11-client", node_name = "mutaspace-soc-node01", status = "stopped", template = true, tags = [] },
      { vm_id = 9004, name = "tpl-opnsense-267", node_name = "mutaspace-soc-node01", status = "stopped", template = true, tags = [] },
      { vm_id = 9005, name = "tpl-kali-rolling", node_name = "mutaspace-soc-node01", status = "stopped", template = true, tags = [] },
    ]
  }
}

run "no_machine_except_the_firewall_touches_the_wan_bridge" {
  command = plan

  assert {
    condition = alltrue([
      for name, bridges in output.vm_bridges :
      !contains(bridges, "vmbr0")
      if output.vm_roles[name] != "firewall"
    ])
    error_message = "A lab VM is attached to vmbr0, the management/WAN bridge. Only fw-01 may touch it - everything else exposes a deliberately vulnerable machine to the operator's real network."
  }

  # The mirror image of the rule above. The firewall is not merely ALLOWED on
  # vmbr0, it is required to be there, and specifically on net0.
  #
  # Proxmox maps network_device blocks positionally: the first becomes net0, which
  # OPNsense sees as vtnet0, which it assigns to WAN. Reorder the nics list in
  # lab.yaml during a tidy-up and the firewall boots believing the SOC LAN is the
  # internet. The lab loses its route out, a DHCP server appears on the management
  # bridge, and nothing in the plan output hints at the cause.
  assert {
    condition = alltrue([
      for name, bridges in output.vm_bridges :
      bridges[0] == "vmbr0"
      if output.vm_roles[name] == "firewall"
    ])
    error_message = "The firewall's FIRST interface is not on vmbr0. net0 becomes vtnet0 becomes WAN; the order of the nics list in lab.yaml decides which segment OPNsense treats as the internet."
  }

  # A completeness check rather than a safety one: a two-legged firewall would
  # apply perfectly cleanly and leave the isolated plane with no gateway at all.
  assert {
    condition = alltrue([
      for name, bridges in output.vm_bridges :
      length(setintersection(toset(bridges), toset(["vmbr0", "vmbr1", "vmbr2"]))) == 3
      if output.vm_roles[name] == "firewall"
    ])
    error_message = "The firewall does not have a leg on all three of vmbr0, vmbr1 and vmbr2. Without the OPT leg the isolated plane has no gateway, and kali-01 can neither be reached nor contained."
  }
}

run "no_machine_is_left_stranded_on_the_build_plane" {
  command = plan

  # vmbr9 exists so Packer can build templates before fw-01 is routing. It is
  # masqueraded straight out of the Proxmox host, which means anything sitting on
  # it has unfiltered internet access that bypasses the firewall entirely - and
  # therefore bypasses Suricata, the logging, and the point of the lab.
  #
  # A VM left on vmbr9 is usually a clone whose bridge was never re-pointed. It
  # works, which is exactly what makes it dangerous.
  assert {
    condition = alltrue([
      for name, bridges in output.vm_bridges :
      !contains(bridges, "vmbr9")
    ])
    error_message = "A lab VM is attached to vmbr9, the build plane. That bridge is masqueraded directly out of the Proxmox host, so the machine has internet access that never passes through fw-01 or Suricata. Packer builds there; nothing else lives there."
  }

  # Machines on the isolated plane must be single-homed. A second NIC on vmbr1
  # would bridge around the firewall and quietly undo the segmentation the whole
  # plane exists to provide.
  assert {
    condition = alltrue([
      for name, plane in output.vm_networks :
      length(output.vm_bridges[name]) == 1 && output.vm_bridges[name][0] == "vmbr2"
      if plane == "isolated" && output.vm_roles[name] != "firewall"
    ])
    error_message = "A machine on the isolated plane has more than one interface, or an interface somewhere other than vmbr2. Dual-homing an untrusted host bridges around the firewall."
  }

  # Every machine on the SOC LAN is single-homed too, for the same reason read the
  # other way round: a lab VM with a second NIC is either an accident or an attempt
  # to route around the design.
  assert {
    condition = alltrue([
      for name, plane in output.vm_networks :
      length(output.vm_bridges[name]) == 1
      if output.vm_roles[name] != "firewall"
    ])
    error_message = "A machine other than the firewall has more than one network interface. The firewall is the only multi-homed host in this lab; anything else with two legs is routing around it."
  }
}
