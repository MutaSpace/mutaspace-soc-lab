# =============================================================================
# locals.tf - read lab.yaml once, normalise it into maps the rest of the code uses
# =============================================================================
#
# WHAT THIS FILE DOES
#   It is the translation layer between "the file a human edits" and "the shape
#   OpenTofu wants". lab.yaml is written for readability: single-NIC machines say
#   `nic:` and the three-legged firewall says `nics:`; addresses are written the
#   way a network diagram writes them. This file turns all of that into one
#   uniform map of VM objects with every field always present, so that lab-vms.tf
#   and learners.tf can be a single `for_each` each instead of a pile of special
#   cases.
#
#   Nothing here talks to Proxmox. Every value below is computable offline, which
#   is exactly why the test suite in tofu/tests/ can run with no host in existence.
#
locals {
  # ---------------------------------------------------------------------------
  # The source of truth
  # ---------------------------------------------------------------------------
  # One read, at the repository root, one directory above this module. If this
  # path is wrong the failure is immediate and obvious, which is the good kind.
  lab = yamldecode(file("${path.module}/../lab.yaml"))

  site     = local.lab.site
  networks = local.lab.networks

  # Template name on the host is "tpl-" + the key in lab.yaml. Keeping the prefix
  # out of lab.yaml keeps that file readable; keeping the convention in exactly
  # one place keeps it honest.
  template_ids   = local.lab.templates
  template_names = { for key, id in local.lab.templates : key => "tpl-${key}" }

  # ---------------------------------------------------------------------------
  # Network helpers
  # ---------------------------------------------------------------------------
  # Every lab network is a /24, so "is this address on this network" is a string
  # prefix comparison rather than an exercise in bit arithmetic. If a /23 or
  # smaller ever appears here, this shortcut has to be replaced - the tests in
  # tofu/tests/addressing.tftest.hcl would keep passing while being wrong, so this
  # comment is the guard.
  network_meta = {
    for key, net in local.networks : key => {
      key     = key
      bridge  = net.bridge
      cidr    = net.cidr
      gateway = net.gateway
      dns     = net.dns

      # [10, 10, 10, 0] for 10.10.10.0/24
      octets = [for o in split(".", split("/", net.cidr)[0]) : tonumber(o)]

      # "10.10.10." - the string every host address on this network starts with.
      prefix = "${join(".", slice(split(".", split("/", net.cidr)[0]), 0, 3))}."
    }
  }

  # Reverse index: which logical network is a given bridge? vmbr0 is deliberately
  # absent - it is the WAN, its subnet is secret, and only fw-01 may touch it.
  network_by_bridge = { for key, net in local.network_meta : net.bridge => key }

  # ---------------------------------------------------------------------------
  # The MAC address convention, in code
  # ---------------------------------------------------------------------------
  # BC:24:11 is the OUI Proxmox itself assigns from, so these addresses look native
  # on the host. The remaining three octets are the last three octets of the IPv4
  # address written as decimal digits: 10.10.10.51 becomes BC:24:11:10:10:51.
  #
  # This is a readability convention, not hexadecimal arithmetic. It exists so that
  # a DHCP lease table, an ARP cache or a packet capture can be read without a
  # lookup sheet. lab.yaml writes these out by hand for the core VMs (they are
  # pinned INPUTS, not outputs); learner clones are generated, so they derive
  # theirs here from the same rule. tofu/tests/addressing.tftest.hcl asserts the
  # hand-written ones agree with the generated rule.
  #
  # Consequence worth knowing: an octet above 99 has three digits and cannot be
  # written this way. That is why learner addresses start at .60 with a step of 2
  # and why learner_count is capped at 20.
  mac_prefix = "BC:24:11"

  # ---------------------------------------------------------------------------
  # Core VMs (lab.yaml -> vms:)
  # ---------------------------------------------------------------------------
  core_vms = {
    for name, vm in local.lab.vms : name => {
      name    = name
      kind    = "core"
      learner = null

      # Defaults to the machine's own name. The only value that means anything to
      # the code is "firewall", which switches on the vmbr0 placement preconditions.
      role = try(vm.role, name)

      vm_id = vm.vm_id

      # "linked" means a linked clone: the disk is a copy-on-write layer over the
      # template's image. Cheap to create, cheap to destroy, and it cannot be moved
      # to another datastore - which is why Packer must write templates to the same
      # local-lvm the clones live on.
      full_clone = try(vm.lifecycle, "reprovisioned") != "linked"

      template_key   = vm.template
      template_vm_id = local.template_ids[vm.template]

      guest   = vm.guest
      os_type = vm.os_type

      cores            = vm.cores
      memory_dedicated = vm.memory.dedicated
      memory_floating  = vm.memory.floating

      disk_size      = vm.disk.size
      disk_interface = vm.disk.interface

      # A machine either declares one `nic` or an ordered list of `nics`. The list
      # form exists for fw-01 and the ORDER IS THE WIRE - see the long comment
      # against fw-01 in lab.yaml.
      nics = [
        for n in try(vm.nics, [vm.nic]) : {
          bridge      = n.bridge
          model       = try(n.model, "virtio")
          mac_address = n.mac
          role        = try(n.role, "primary")
        }
      ]

      ipv4_mode = vm.ipv4.mode

      # The address cloud-init will actually configure. Null for DHCP (the guest
      # asks) and for appliances (the guest already knows).
      ipv4_address = try(vm.ipv4.address, null)
      ipv4_gateway = try(vm.ipv4.gateway, null)

      # The address this machine is expected to END UP with, however it gets there.
      # Static machines: the declared address without its prefix length. DHCP
      # machines: the reservation the firewall hands them. This is the value the
      # Ansible inventory and the firewall's static-mapping template both consume.
      effective_ipv4 = (
        vm.ipv4.mode == "static" ? split("/", vm.ipv4.address)[0] :
        vm.ipv4.mode == "dhcp" ? vm.ipv4.reservation :
        null
      )

      agent         = vm.agent
      started       = try(vm.started, true)
      startup_order = try(vm.startup_order, null)

      bios    = try(vm.firmware.bios, null)
      machine = try(vm.firmware.machine, null)

      description = trimspace(vm.description)
    }
  }

  # ---------------------------------------------------------------------------
  # Learner endpoint VMs (lab.yaml -> learners: x learner_endpoints:)
  # ---------------------------------------------------------------------------
  # Only the first `learner_count` entries of the roster are built. The roster
  # itself stays in git so the class list is reviewable; the count is the knob that
  # fits it to tonight's RAM.
  enabled_learners = slice(
    local.lab.learners,
    0,
    min(var.learner_count, length(local.lab.learners))
  )

  # Flatten (learner x endpoint) into one list before turning it into a map. The
  # index into the ORIGINAL roster is what drives both the VMID and the address, so
  # it is captured here rather than recomputed later.
  learner_pairs = flatten([
    for idx, learner in local.enabled_learners : [
      for role in learner.endpoints : {
        learner_id    = learner.id
        learner_index = idx
        role          = role
        spec          = local.lab.learner_endpoints[role]
      }
    ]
  ])

  learner_vms = {
    for pair in local.learner_pairs : "${pair.role}-l${pair.learner_id}" => {
      name    = "${pair.role}-l${pair.learner_id}"
      kind    = "learner"
      learner = pair.learner_id
      role    = pair.role

      # 200 + (learner_index * 10) + role offset. Learner 01 (index 0) therefore
      # gets 205 for their Windows client and 206 for their Kali box, which keeps
      # a whole learner's machines adjacent and readable in `qm list`.
      vm_id = 200 + (pair.learner_index * 10) + pair.spec.vmid_offset

      full_clone = try(pair.spec.lifecycle, "reprovisioned") != "linked"

      template_key   = pair.spec.template
      template_vm_id = local.template_ids[pair.spec.template]

      guest   = pair.spec.guest
      os_type = pair.spec.os_type

      cores            = pair.spec.cores
      memory_dedicated = pair.spec.memory.dedicated
      memory_floating  = pair.spec.memory.floating

      disk_size      = pair.spec.disk.size
      disk_interface = pair.spec.disk.interface

      nics = [{
        bridge = local.network_meta[pair.spec.network].bridge
        model  = try(pair.spec.nic.model, "virtio")
        mac_address = format(
          "%s:%02d:%02d:%02d",
          local.mac_prefix,
          local.network_meta[pair.spec.network].octets[1],
          local.network_meta[pair.spec.network].octets[2],
          pair.spec.ipv4.host_base + (pair.learner_index * pair.spec.ipv4.host_step),
        )
        role = "primary"
      }]

      ipv4_mode = pair.spec.ipv4.mode

      ipv4_address = pair.spec.ipv4.mode == "static" ? format(
        "%s%d/24",
        local.network_meta[pair.spec.network].prefix,
        pair.spec.ipv4.host_base + (pair.learner_index * pair.spec.ipv4.host_step),
      ) : null

      ipv4_gateway = pair.spec.ipv4.mode == "static" ? local.network_meta[pair.spec.network].gateway : null

      effective_ipv4 = format(
        "%s%d",
        local.network_meta[pair.spec.network].prefix,
        pair.spec.ipv4.host_base + (pair.learner_index * pair.spec.ipv4.host_step),
      )

      agent         = pair.spec.agent
      started       = try(pair.spec.started, false)
      startup_order = try(pair.spec.startup_order, null)

      bios    = try(pair.spec.firmware.bios, null)
      machine = try(pair.spec.firmware.machine, null)

      description = "Learner ${pair.learner_id}. ${trimspace(pair.spec.description)}"
    }
  }

  # ---------------------------------------------------------------------------
  # Everything, in one map
  # ---------------------------------------------------------------------------
  all_vms = merge(local.core_vms, local.learner_vms)

  # Which templates are actually referenced by something. templates.tf asserts each
  # of these exists on the host before anything tries to clone it.
  templates_in_use = {
    for key, id in local.template_ids : key => id
    if contains([for vm in values(local.all_vms) : vm.template_key], key)
  }

  # ---------------------------------------------------------------------------
  # Cloud-init
  # ---------------------------------------------------------------------------
  # An appliance (fw-01) gets nothing: OPNsense has no cloud-init and its
  # addressing comes from the config.xml Packer seeds into the template.
  #
  # Linux guests get NoCloud. Windows guests get configdrive2, because that is the
  # format Proxmox generates for a Windows ostype and the format Cloudbase-Init
  # expects to find.
  cloud_init_vms = {
    for name, vm in local.all_vms : name => vm
    if contains(["linux", "windows"], vm.guest)
  }

  linux_cloud_init_vms   = { for name, vm in local.cloud_init_vms : name => vm if vm.guest == "linux" }
  windows_cloud_init_vms = { for name, vm in local.cloud_init_vms : name => vm if vm.guest == "windows" }

  # Which logical network is each VM's primary NIC on? "wan" for anything on the
  # management bridge (only fw-01 should ever be), which is how the placement test
  # spots a machine that has escaped onto the real home network.
  vm_network = {
    for name, vm in local.all_vms : name => try(local.network_by_bridge[vm.nics[0].bridge], "wan")
  }

  # DNS handed to each guest through the cloud-init drive.
  #
  # LAN machines resolve at dc-01 and nowhere else - that is what makes them
  # domain members rather than machines that happen to be on the same wire. The
  # isolated plane resolves at the firewall instead, because it is default-deny
  # toward vmbr1 and pointing it at the domain controller would either fail or
  # punch a hole in the isolation.
  vm_dns_servers = {
    for name, vm in local.all_vms : name => try(
      local.network_meta[local.vm_network[name]].dns,
      [],
    )
  }

  # ---------------------------------------------------------------------------
  # Derived views used by outputs and tests
  # ---------------------------------------------------------------------------

  # Every MAC in the lab, including fw-01's three. Used to prove uniqueness.
  all_macs = flatten([for name, vm in local.all_vms : [for n in vm.nics : n.mac_address]])

  # Every bridge each VM touches. The placement test reads this.
  vm_bridges = { for name, vm in local.all_vms : name => [for n in vm.nics : n.bridge] }

  # What the firewall's static DHCP mappings must contain. This is the seam between
  # OpenTofu and the OPNsense configuration: same map, two consumers, so a
  # reservation cannot drift from the MAC that is supposed to claim it.
  dhcp_reservations = {
    for name, vm in local.all_vms : name => {
      mac_address = vm.nics[0].mac_address
      address     = vm.effective_ipv4
      hostname    = name
      network     = local.vm_network[name]
    }
    if vm.ipv4_mode == "dhcp"
  }

  # The MAC convention, applied to whatever address each machine ends up with.
  # Compared against the hand-written MACs by the addressing test. fw-01's WAN leg
  # is excluded because its address is secret and therefore cannot be derived.
  derived_macs = {
    for name, vm in local.all_vms : name => format(
      "%s:%02d:%02d:%02d",
      local.mac_prefix,
      local.network_meta[local.vm_network[name]].octets[1],
      local.network_meta[local.vm_network[name]].octets[2],
      tonumber(split(".", vm.effective_ipv4)[3]),
    )
    if vm.effective_ipv4 != null && contains(keys(local.network_meta), local.vm_network[name])
  }
}
