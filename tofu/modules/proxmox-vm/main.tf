# =============================================================================
# modules/proxmox-vm/main.tf - one module, every VM in the lab
# =============================================================================
#
# WHY ONE MODULE AND NOT ONE FILE PER VM
#   Because a lab with nine hand-written VM resources has nine places for a
#   landmine to hide, and only some of them will have been defused. Every clone
#   trap the design research turned up is handled once, here, and applies to every
#   machine automatically.
#
#   The traps this module exists to defuse, in one list:
#
#     * The clone block is entirely ForceNew. Nothing in it may be derived from a
#       build artifact.
#     * Linked clones cannot change datastore, so datastore_id must be OMITTED -
#       not merely equal to the template's - when full = false.
#     * A partial disk block silently resets everything it does not mention to
#       schema defaults, so discard flips back to "ignore" and the LVM-thin pool
#       stops reclaiming freed blocks. Every disk attribute is restated.
#     * stop_on_destroy defaults to false, which means destroy sends an ACPI
#       shutdown and then waits for a guest that may not be listening.
#     * agent.enabled = true without an agent costs 15 minutes per operation.
#     * network_device blocks map POSITIONALLY to net0..netN.
#

resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  vm_id       = var.vm_id
  node_name   = var.node_name
  description = var.description
  tags        = var.tags
  pool_id     = var.pool_id

  started = var.started
  on_boot = var.on_boot

  # Default is FALSE, which makes `tofu destroy` send an ACPI shutdown request and
  # then sit there. On a guest with no ACPI daemon listening - an appliance, a
  # machine mid-install, anything wedged - that is a wait for the shutdown timeout
  # on every single destroy. In a lab where machines are torn down deliberately and
  # often, this being true is the difference between a workflow and a chore.
  stop_on_destroy = true

  # Windows 11 needs q35 + OVMF. Both are inherited from the template on a clone,
  # so these are usually null and restating them is a no-op that documents intent.
  #
  # The EFI disk and the TPM state are deliberately NOT declared. They exist in the
  # template; declaring efi_disk or tpm_state on a clone asks Proxmox to create a
  # second one.
  bios          = var.bios
  machine       = var.machine
  scsi_hardware = var.scsi_hardware

  # ---------------------------------------------------------------------------
  # Where the machine comes from
  # ---------------------------------------------------------------------------
  clone {
    vm_id = var.template_vm_id
    full  = var.full_clone

    # Cloning is one of the operations that fails under I/O contention when several
    # VMs are created at once - Proxmox returns a lock error rather than queuing.
    # Two retries plus `tofu apply -parallelism=1` is the combination that works.
    retries = 2

    # THE OMISSION IS THE POINT.
    #
    # Proxmox cannot move a linked clone to a different storage; the copy-on-write
    # relationship is internal to the storage layer. Passing datastore_id at all
    # when full = false makes the clone fail. Null here means the attribute is not
    # sent, and the clone lands next to its template - which is why Packer must
    # write templates to the same local-lvm the clones live on.
    datastore_id = var.full_clone ? var.datastore_id : null
  }

  # ---------------------------------------------------------------------------
  # CPU and memory
  # ---------------------------------------------------------------------------
  cpu {
    cores   = var.cores
    sockets = 1
    type    = var.cpu_type
  }

  memory {
    dedicated = var.memory_dedicated

    # floating == dedicated turns ballooning on; 0 turns it off. Proxmox's own
    # default is 0, so ballooning is opt-in rather than something that happens by
    # accident to a machine that cannot survive it.
    floating = var.memory_floating
  }

  # ---------------------------------------------------------------------------
  # Disk - every attribute restated, deliberately
  # ---------------------------------------------------------------------------
  # The provider documents this as a caveat and it is easy to skim past: if you
  # modify ANY attribute of a cloned disk, you must also supply every other
  # attribute that differs from the schema default. Write only `interface` and
  # `size` and you will silently get discard = "ignore", cache = "none",
  # ssd = false and iothread = false - and then spend an afternoon wondering why
  # `tofu plan` never converges.
  disk {
    interface    = var.disk_interface
    datastore_id = var.datastore_id
    size         = var.disk_size

    # discard = "on" passes guest TRIM through to the LVM-thin pool.
    #
    # Without it, blocks a guest deletes are never returned to the pool. The pool
    # fills with data nothing references, and a full LVM-thin pool does not fail
    # politely on one VM - it stalls writes across every VM on the host. On a
    # single-node teaching lab with one NVMe drive that is the whole classroom.
    discard = "on"

    # Advertises the disk as non-rotational, which lets the guest issue TRIM in the
    # first place. Invalid on virtio-blk, which is why disk_interface is validated.
    ssd = true

    cache = "none"
    aio   = "io_uring"

    # Needs virtio-scsi-single, which is set above.
    iothread = true

    backup = true
  }

  # ---------------------------------------------------------------------------
  # Network - ORDER IS THE WIRE
  # ---------------------------------------------------------------------------
  # These blocks map positionally: the first becomes net0, the second net1, the
  # third net2. For every machine except the firewall there is exactly one and the
  # ordering is uninteresting. For fw-01 it decides which physical segment the
  # firewall believes is the internet.
  dynamic "network_device" {
    for_each = var.nics
    content {
      bridge = network_device.value.bridge
      model  = network_device.value.model

      # Pinned, not generated.
      #
      # If Proxmox assigns the MAC, the address only exists after the VM is
      # created - which is after the firewall's DHCP reservations had to be
      # written. Pinning inverts that dependency: the MAC is an input, the same
      # map feeds both the VM and the firewall's static mappings, and a machine
      # keeps its reserved address across a full destroy-and-rebuild.
      #
      # Contrary to widespread belief this attribute is not ForceNew - it is
      # Optional + Computed - so pinning it does not taint anything.
      mac_address = network_device.value.mac_address
    }
  }

  # ---------------------------------------------------------------------------
  # Cloud-init
  # ---------------------------------------------------------------------------
  # Absent entirely for appliances. OPNsense has no cloud-init and never will;
  # pretending otherwise just produces a drive nothing reads.
  #
  # Note what is NOT set here: `upgrade`. Proxmox defaults it to true, which makes
  # every clone run a package upgrade on first boot, but the API restricts that
  # option to root@pam - so an API token cannot set it to false either. The
  # workaround is that supplying custom user-data replaces Proxmox's generated
  # user-data wholesale, and the templates in ../../templates/ set
  # package_upgrade: false themselves.
  dynamic "initialization" {
    for_each = var.cloud_init == null ? [] : [var.cloud_init]

    content {
      # local-lvm is the silent default for this block as well as for disks. On a
      # host whose storage is named anything else, the apply fails with "storage
      # local-lvm does not exist" reported against a block that never mentions
      # storage. Setting it explicitly makes that impossible.
      datastore_id = var.datastore_id
      interface    = "ide2"

      # nocloud for Linux, configdrive2 for Windows. This is ForceNew.
      type = initialization.value.type

      dns {
        domain  = initialization.value.dns_domain
        servers = initialization.value.dns_servers
      }

      # Static addressing goes through here rather than through the guest's own
      # network configuration, so the resolver is set to dc-01 before the guest has
      # any way to ask DHCP what the resolver should be. That is what breaks the
      # "guests need the DC for DNS, and the DC is a guest" circularity.
      dynamic "ip_config" {
        for_each = try(initialization.value.ipv4_address, null) == null ? [] : [1]
        content {
          ipv4 {
            address = initialization.value.ipv4_address
            gateway = initialization.value.ipv4_gateway
          }
        }
      }

      # ForceNew. Filenames are stable by design; see the note on var.cloud_init.
      user_data_file_id = try(initialization.value.user_data_file_id, null)
      meta_data_file_id = try(initialization.value.meta_data_file_id, null)

      # Provided for the case where a guest is configured through Proxmox's own
      # cloud-init fields instead of a snippet. Mutually exclusive with
      # user_data_file_id in practice - see the precondition below.
      dynamic "user_account" {
        for_each = var.user_account == null ? [] : [var.user_account]
        content {
          username = user_account.value.username
          password = user_account.value.password
          keys     = user_account.value.keys
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Guest agent
  # ---------------------------------------------------------------------------
  agent {
    enabled = var.agent_enabled
  }

  operating_system {
    type = var.os_type
  }

  # A serial device costs nothing and prevents a specific, baffling failure:
  # Debian and Ubuntu cloud images kernel-panic when their boot disk is resized if
  # no serial device is present. Every Linux VM here is a resized clone.
  serial_device {
    device = "socket"
  }

  # Boot ordering, so that a host reboot brings the lab back in an order that
  # works: firewall, then domain controller, then the SIEM, then everything that
  # depends on all three.
  dynamic "startup" {
    for_each = var.startup_order == null ? [] : [var.startup_order]
    content {
      order = startup.value
    }
  }

  lifecycle {
    # -------------------------------------------------------------------------
    # The placement guard
    # -------------------------------------------------------------------------
    # vmbr0 carries the operator's real home network and the Proxmox management
    # address. A lab VM landing there is not a cosmetic mistake: it exposes a
    # deliberately vulnerable machine to a real network, and in the case of a
    # second DHCP server it breaks the household.
    #
    # This is checked here AND in tofu/tests/network_placement.tftest.hcl. The test
    # catches it in CI with no host; this catches it in a plan somebody ran by hand.
    precondition {
      condition = var.role == "firewall" || alltrue([
        for n in var.nics : n.bridge != var.wan_bridge
      ])
      error_message = "VM '${var.name}' is attached to '${var.wan_bridge}', the management/WAN bridge. Only the firewall may touch it."
    }

    # The firewall's net0 must be the WAN leg. If the list is reordered, OPNsense
    # comes up with WAN and LAN swapped and the failure looks like a hardware fault.
    precondition {
      condition     = var.role != "firewall" || var.nics[0].bridge == var.wan_bridge
      error_message = "The firewall's FIRST network interface must be on '${var.wan_bridge}'. net0 becomes vtnet0 becomes WAN; reordering the nics list silently swaps WAN and LAN."
    }

    # A cloud-init snippet replaces the user-data Proxmox would have generated from
    # user_account, so setting both means half the configuration silently does
    # nothing. Failing here is cheaper than discovering it in a guest.
    precondition {
      condition     = var.user_account == null || var.cloud_init == null || try(var.cloud_init.user_data_file_id, null) == null
      error_message = "VM '${var.name}' sets both user_account and cloud_init.user_data_file_id. Proxmox implements the snippet as `cicustom user=`, which replaces the generated user-data entirely, so user_account would be silently ignored. Pick one."
    }

    # A balloon floor above the ceiling is accepted by the API and then behaves in
    # ways nobody expects. It is almost always a transposed pair of numbers in
    # lab.yaml.
    precondition {
      condition     = var.memory_floating == 0 || var.memory_floating <= var.memory_dedicated
      error_message = "VM '${var.name}' has memory.floating (${var.memory_floating}) above memory.dedicated (${var.memory_dedicated}). floating is the balloon FLOOR, dedicated is the ceiling; they have most likely been swapped."
    }
  }
}
