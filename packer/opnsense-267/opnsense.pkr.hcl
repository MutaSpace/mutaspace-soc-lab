# packer/opnsense-267/opnsense.pkr.hcl
#
# WHAT THIS FILE IS
#   The Packer build that produces `tpl-opnsense-267` (VMID 9004), the golden
#   template OpenTofu clones into `fw-01` (VMID 100) — the lab's firewall,
#   router, DHCP server, NTP server and, per decision D-04, its IDS.
#
# WHY IT EXISTS
#   Decision D-01 makes this lab greenfield, and that creates an ordering
#   problem: nothing on vmbr1 can reach the internet until fw-01 routes, and
#   fw-01 is itself a VM. So the firewall has to be the FIRST thing built, on
#   the vmbr9 build plane, from an image that can be pinned and checksummed.
#   Decision D-02 chose OPNsense over pfSense for exactly that reason — not
#   because the install is cleaner, but because the artifact is downloadable.
#
# ★ READ THIS BEFORE YOU TRUST ANYTHING BELOW ★
#
#   This is the most fragile file in the repository, and pretending otherwise
#   would be dishonest. OPNsense has no cloud-init, no answer file and no
#   unattended installer. Everything below the install line is achieved by
#   typing at a console and hoping the screen says what we think it says.
#
#   Concretely, this build:
#     * cannot be verified without a Proxmox host and the real ISO;
#     * has never been executed as committed (authored offline, D-05);
#     * drives the installer with a keystroke sequence whose correctness
#       depends on menu ORDER and screen TIMING in OPNsense 26.7 specifically.
#
#   Every other template in this repo has a supported unattended path —
#   subiquity autoinstall, Autounattend.xml, cloud-init. This one does not.
#   That is the price of a firewall whose image can be pinned, and the honest
#   framing of D-02 is that OPNsense won on the artifact, not on the install.

packer {
  required_version = ">= 1.11.0"

  required_plugins {
    proxmox = {
      # The design pins `~> 1.2`, matching every other template in this repo.
      # `packer init` resolves the newest matching release, which keeps us
      # above the 1.2.3 floor — 1.2.2 silently dropped `cpu_type`, and this
      # build sets it. If you ever hand-place a plugin binary, do not use
      # 1.2.2.
      version = "~> 1.2"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ---------------------------------------------------------------------------
# Derived values
# ---------------------------------------------------------------------------
#
# Everything here is computed from variables.pkr.hcl so that an address is
# written down exactly once. The network addresses are derived rather than
# typed because "10.10.10.1 with a /24" and "10.10.10.0/24" drifting apart is
# a classic way to produce a DHCP scope that serves the wrong subnet.

locals {
  lan_cidr      = "${var.lan_address}/${var.lan_prefix}"
  isolated_cidr = "${var.isolated_address}/${var.isolated_prefix}"

  # -------------------------------------------------------------------------
  # DHCP reservations, derived from lab.yaml
  # -------------------------------------------------------------------------
  #
  # WHY THIS IS DERIVED AND NOT TYPED OUT
  #   config.xml.pkrtpl.hcl's own header claims "one source, rendered twice,
  #   cannot drift". That claim was false while this list was a literal in
  #   variables.pkr.hcl: OpenTofu computes reservations for the per-learner
  #   Windows clients too (lab.yaml -> learner_endpoints.win-client, mode dhcp,
  #   host .60 step 2), and the literal list only ever carried analyst-01 and
  #   win-client-01. A learner client with a pinned MAC and no matching
  #   <reservation> boots, takes a pool address from .100-.200 and looks fine.
  #
  #   So both sides now read the SAME lab.yaml and apply the SAME rules. This
  #   block is the Packer-side twin of `local.dhcp_reservations` in
  #   tofu/locals.tf; if you change one, the tests in tofu/tests/addressing
  #   will tell you about the other.
  #
  # WHY `parseint` AND NOT `tonumber`
  #   Packer's HCL2 has no tonumber(). This is one of the small places where
  #   Packer's function set is a subset of OpenTofu's.
  #
  # PATHS: bare and relative, resolved against THIS directory - see the note on
  # `config_xml` below for why "${path.root}/" would be wrong here.
  lab = yamldecode(file("../../lab.yaml"))

  # [10, 10, 10, 0] and "10.10.10" for the SOC LAN.
  lan_octets      = [for o in split(".", split("/", local.lab.networks.lan.cidr)[0]) : parseint(o, 10)]
  lan_host_prefix = join(".", slice(split(".", split("/", local.lab.networks.lan.cidr)[0]), 0, 3))

  # Only the first `learner_count` of the roster, exactly as tofu/locals.tf slices it.
  enabled_learners = slice(
    local.lab.learners,
    0,
    min(var.learner_count, length(local.lab.learners)),
  )

  # Core machines that ask for an address and are on the SOC LAN. `sort(keys())`
  # makes the order deterministic, which is what keeps the generated uuids stable
  # across renders. fw-01 is skipped automatically: it declares `nics` rather than
  # `nic`, and its ipv4 mode is "none".
  core_dhcp_reservations = [
    for name in sort(keys(local.lab.vms)) : {
      hostname = name
      mac      = local.lab.vms[name].nic.mac
      address  = local.lab.vms[name].ipv4.reservation
    }
    if try(local.lab.vms[name].ipv4.mode, "") == "dhcp"
    && try(local.lab.vms[name].nic.bridge, "") == local.lab.networks.lan.bridge
  ]

  # Per-learner endpoints that ask for an address on the SOC LAN. The MAC is
  # derived from the address by the BC:24:11 convention, which is exactly what
  # tofu/locals.tf does for the same machines - that is what makes the two sides
  # agree without either one reading the other.
  learner_dhcp_reservations = flatten([
    for idx, learner in local.enabled_learners : [
      for role in learner.endpoints : {
        hostname = "${role}-l${learner.id}"
        mac = format(
          "BC:24:11:%02d:%02d:%02d",
          local.lan_octets[1],
          local.lan_octets[2],
          local.lab.learner_endpoints[role].ipv4.host_base + (idx * local.lab.learner_endpoints[role].ipv4.host_step),
        )
        address = format(
          "%s.%d",
          local.lan_host_prefix,
          local.lab.learner_endpoints[role].ipv4.host_base + (idx * local.lab.learner_endpoints[role].ipv4.host_step),
        )
      }
      if try(local.lab.learner_endpoints[role].ipv4.mode, "") == "dhcp"
      && try(local.lab.networks[local.lab.learner_endpoints[role].network].bridge, "") == local.lab.networks.lan.bridge
    ]
  ])

  # OPNsense's Kea model links a reservation to its subnet by uuid, so the uuids
  # have to be STABLE across renders - a regenerated uuid is a new reservation and
  # an orphaned old one. They are therefore derived, not random: a sequence number
  # plus the MAC with its colons removed. The first two come out byte-identical to
  # the constants this file used to carry.
  #
  # The rendered MAC is lower-cased because that is what OPNsense itself writes
  # when it rewrites config.xml. lab.yaml writes the same MACs in upper case; Kea
  # matches hw-address case-insensitively, and since both spellings now come from
  # one source they cannot disagree about anything that matters.
  dhcp_reservations = [
    for i, r in concat(local.core_dhcp_reservations, local.learner_dhcp_reservations) : {
      uuid     = format("4f0d%04d-0000-4000-8000-%s", i + 1, lower(replace(r.mac, ":", "")))
      hostname = r.hostname
      mac      = lower(r.mac)
      address  = r.address
    }
  ]

  # cidrsubnet(x, 0, 0) normalises a host address to its network address:
  # 10.10.10.1/24 -> 10.10.10.0/24
  lan_network      = cidrsubnet(local.lan_cidr, 0, 0)
  isolated_network = cidrsubnet(local.isolated_cidr, 0, 0)

  # Pinned so that rendering this template twice produces identical XML.
  # OPNsense's Kea model links each reservation to its subnet by uuid.
  dhcp_subnet_uuid = "4f0d0000-0000-4000-8000-0a0a0a0000ff"

  # The rendered /conf/config.xml that gets copied onto the installed system.
  #
  # The path is bare and relative on purpose. templatefile() already resolves
  # relative to the template directory, so writing "${path.root}/config/..."
  # here would prepend that directory a second time and only work when Packer
  # happens to be invoked from inside this folder. (The manifest
  # post-processor below is the opposite case — its output path IS relative to
  # the working directory, so it does need path.root.)
  config_xml = templatefile("config/config.xml.pkrtpl.hcl", {
    fw_hostname      = var.fw_hostname
    lab_domain       = var.lab_domain
    timezone         = var.timezone
    opnsense_version = var.opnsense_version

    root_password_hash = var.root_password_hash

    upstream_dns = var.upstream_dns

    wan_if      = var.wan_if
    wan_mode    = var.wan_mode
    wan_address = var.wan_address
    wan_prefix  = var.wan_prefix
    wan_gateway = var.wan_gateway

    lan_if        = var.lan_if
    lan_address   = var.lan_address
    lan_prefix    = var.lan_prefix
    lan_network   = local.lan_network
    lan_dhcp_from = var.lan_dhcp_from
    lan_dhcp_to   = var.lan_dhcp_to

    isolated_if      = var.isolated_if
    isolated_address = var.isolated_address
    isolated_prefix  = var.isolated_prefix
    isolated_network = local.isolated_network

    dc_address        = var.dc_address
    dhcp_subnet_uuid  = local.dhcp_subnet_uuid
    dhcp_reservations = local.dhcp_reservations

    # OPNsense stores booleans as "0"/"1", not "true"/"false".
    suricata_enabled    = var.suricata_enabled ? "1" : "0"
    suricata_ips_mode   = var.suricata_ips_mode ? "1" : "0"
    suricata_interfaces = var.suricata_interfaces
  })
}

# ---------------------------------------------------------------------------
# Source
# ---------------------------------------------------------------------------

source "proxmox-iso" "opnsense" {

  # --- API -----------------------------------------------------------------
  # Packer wants the endpoint WITH /api2/json. The bpg OpenTofu provider wants
  # it WITHOUT. Same host, two shapes; see variables.pkr.hcl.
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = var.proxmox_insecure_tls
  node                     = var.proxmox_node

  # The OPNsense install writes well over a gigabyte before it returns. The
  # stock 1-minute API task timeout is not survivable.
  task_timeout = var.task_timeout

  # --- Identity ------------------------------------------------------------
  vm_id                = var.template_vm_id
  vm_name              = var.template_name
  template_name        = var.template_name
  template_description = "OPNsense ${var.opnsense_version} golden template. Built by packer/opnsense-267. Clone target: fw-01 (VMID 100). Seeded /conf/config.xml; os-suricata + os-qemu-guest-agent installed."

  # --- Hardware ------------------------------------------------------------
  # `other` is the Proxmox ostype for FreeBSD. Setting it wrong mostly affects
  # the default hardware Proxmox suggests, but it also shows up in `qm config`
  # and this is teaching material.
  os       = "other"
  cpu_type = "host"
  sockets  = 1
  cores    = 2
  memory   = 4096

  # No `machine` is set, so Proxmox uses i440fx. q35 would also work, but a
  # firewall gains nothing from PCIe and FreeBSD-on-i440fx is the better-worn
  # path. Windows 11 (packer/win11-client) is the template that genuinely
  # needs q35 + OVMF + TPM; this one does not.

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    disk_size    = "20G"
    storage_pool = var.storage_pool
    format       = "raw"

    # discard + ssd are not micro-optimisations. Without TRIM passing through,
    # deleted blocks are never returned to the LVM-thin pool, and a full thin
    # pool stalls writes for EVERY VM on the host, not just this one.
    discard = true
    ssd     = true

    # virtio-scsi-single exists precisely so each disk gets its own iothread.
    io_thread = true
  }

  # Three NICs, all on the build plane.
  #
  # Why three when the build only needs one: the seeded config.xml names
  # vtnet0/vtnet1/vtnet2. If the template were built with a single NIC, the
  # first boot after the config import would find two of its three interfaces
  # missing and drop to OPNsense's interactive interface-assignment prompt —
  # on a machine nobody is watching. Building with the same NIC COUNT as fw-01
  # means the names already resolve.
  #
  # They are all on vmbr9 because vmbr1 and vmbr2 have no route to anything
  # during the build. OpenTofu re-points them at vmbr0/vmbr1/vmbr2 at clone
  # time, which is free: `bridge` is not a ForceNew attribute.
  #
  # firewall = false: the Proxmox per-NIC firewall inserts an fwbr/fwln/fwpr
  # veth chain with macfilter on. On a router that forwards other machines'
  # frames, that is exactly the wrong thing to have in the path.
  network_adapters {
    bridge   = var.build_bridge
    model    = "virtio"
    firewall = false
  }
  network_adapters {
    bridge   = var.build_bridge
    model    = "virtio"
    firewall = false
  }
  network_adapters {
    bridge   = var.build_bridge
    model    = "virtio"
    firewall = false
  }

  # --- Installer media -----------------------------------------------------
  #
  # The boot_iso BLOCK, not the old top-level iso_file/iso_url/unmount_iso
  # attributes. Inside the block the key is `unmount`, not `unmount_iso`.
  #
  # No iso_url and no iso_checksum on purpose: OPNsense ships the DVD image
  # bzip2-compressed and Proxmox cannot boot a compressed image, so this is a
  # manually prepared artifact. The download + verify + bunzip2 recipe is in
  # variables.pkr.hcl and in this directory's README. No sha256 is invented
  # here; the operator records the one they computed.
  boot_iso {
    type     = "ide"
    index    = "2"
    iso_file = var.opnsense_iso_file
    unmount  = true
  }

  # --- Config seed ---------------------------------------------------------
  #
  # A second CD carrying nothing but /conf/config.xml.
  #
  # iso_storage_pool is MANDATORY whenever cd_files/cd_content is used — the
  # builder's Prepare() hard-fails without it, before any build starts.
  #
  # cd_label matters more than it looks: FreeBSD exposes an ISO9660 volume at
  # /dev/iso9660/<LABEL>, so the boot_command can mount the seed BY NAME
  # instead of guessing whether it landed on cd0 or cd1. Device-order guessing
  # is a classic source of "worked on my machine" in exactly this kind of
  # build.
  #
  # ── Deviation worth naming ───────────────────────────────────────────────
  # The original plan was a FAT image handed to OPNsense's own "Import
  # Configuration" installer step. This build uses an ISO9660 volume and
  # copies the file itself instead, for two reasons: Packer's cd_content
  # produces ISO9660 (via xorriso on the Packer host — install it, the failure
  # without it is confusing), and the importer is one more interactive dialog
  # whose device-selection screen would have to be driven blind. `cp` is the
  # same operation with none of the dialog.
  #
  # If a future OPNsense refuses to mount this, the FAT fallback is:
  #   dd if=/dev/zero of=seed.img bs=1M count=8 && mkfs.vfat -n OPNCFG seed.img
  #   mmd -i seed.img ::/conf && mcopy -i seed.img config.xml ::/conf/config.xml
  # upload it to the ISO store, point boot_iso-style at it, and change the
  # mount line in the boot_command to
  #   mount -t msdosfs /dev/msdosfs/OPNCFG /tmp/seed
  #
  # ⚠️ UNVERIFIED OFFLINE: that Packer's cd_content creates the intermediate
  # `conf/` directory for a nested key. The SDK is believed to MkdirAll the
  # parent, but this was not executed. If the build fails building the CD,
  # flatten the key to "config.xml" and adjust the cp line.
  additional_iso_files {
    type             = "ide"
    index            = "3"
    cd_label         = "OPNCFG"
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
    cd_content = {
      "/conf/config.xml" = local.config_xml
    }
  }

  # --- Communicator --------------------------------------------------------
  #
  # There is none, and that is a design decision rather than a shortcut.
  #
  # The obvious alternative is: install, import a temporary build-plane config
  # that enables SSH, let Packer connect, run real provisioners, then write the
  # final config. That is a better-engineered build and it costs a second
  # config.xml template plus an SSH keypair plus a second password hash — and
  # it still cannot be tested offline, so it would be more untested code, not
  # less.
  #
  # With no communicator, every step happens at the console in one
  # boot_command. The whole build is therefore visible in one place, which for
  # a build this fragile is worth more than provisioner ergonomics. If this
  # template ever needs real provisioners (a Wazuh agent, custom Suricata
  # rules), that is the moment to pay for the SSH path.
  #
  # qemu_agent is false because os-qemu-guest-agent is installed DURING the
  # build. Leaving it true makes the plugin wait on an agent that does not
  # exist yet.
  communicator = "none"
  qemu_agent   = false

  # ---------------------------------------------------------------------------
  # ██  THIS WILL BREAK ON VERSION BUMPS  ██████████████████████████████████████
  # ---------------------------------------------------------------------------
  #
  # Everything from here to the end of boot_command is a sequence of keystrokes
  # typed blind into a console. It encodes three assumptions, ALL of which are
  # specific to OPNsense 26.7:
  #
  #   1. WHICH SCREENS APPEAR, and in what order.
  #   2. WHERE the cursor starts in each menu, so that N × <down> lands on the
  #      entry we want.
  #   3. HOW LONG each screen takes to appear, because <wait> is the only
  #      synchronisation primitive available. Packer cannot read the screen.
  #
  # An OPNsense minor release can move a menu entry, add a "do you want to
  # enable X" question, or change the installer's default filesystem. When that
  # happens this build does not error — it types the right keys at the wrong
  # screen and produces a template that is subtly wrong, or hangs until
  # task_timeout.
  #
  # ★ WHEN IT BREAKS, THE FIX IS NOT MORE SLEEPS. ★
  #
  # Adding <wait> until it passes produces a build that takes forty minutes and
  # breaks again next release, because you will have papered over a changed
  # screen rather than found it. Do this instead:
  #
  #   1. Boot the new ISO by hand on the Proxmox host, in the same VM shape
  #      (`qm create` with virtio-scsi-single, 3 virtio NICs on vmbr9).
  #   2. Walk the installer manually and WRITE DOWN every screen, its default
  #      cursor position, and roughly how long it took to appear.
  #   3. Re-derive the sequence below from those notes.
  #   4. Only then adjust timings, and add margin to the ones that are genuinely
  #      I/O-bound (the install itself, pkg downloads) rather than uniformly.
  #
  # Budget this on every OPNsense upgrade. Pin the OPNsense version for a whole
  # semester so it happens on your schedule, not mid-class. That the firewall
  # needs a scheduled re-tune is a property of the platform, not a bug in this
  # file.
  #
  # Also: var.root_password is typed here in the clear. `packer build -debug`
  # and PACKER_LOG=1 will show it. Do not paste build logs into a ticket.
  #
  # Note on notation: every wait carries an explicit unit (<wait5s>, <wait8m>)
  # rather than the bare <wait5> form seen in older templates. Packer accepts
  # both, but boot_command is parsed at BUILD time, not by `packer validate` —
  # so nothing here is syntax-checked before a real build starts, and being
  # unambiguous is the only defence available.
  # ---------------------------------------------------------------------------

  # The FreeBSD loader menu counts down ~10s on its own; we never touch it.
  # This wait covers loader + live-system boot to the "login:" prompt.
  boot_wait = "3m"

  # Console typing speed. The default is fast enough to outrun a serial-ish
  # VGA console redraw on a busy host; slowing it down costs seconds and buys
  # a great deal of reliability.
  boot_key_interval      = "50ms"
  boot_keygroup_interval = "1s"

  boot_command = [
    # ======================================================================
    # PHASE 1 — the live installer  (fragile: dialogs, menu order, defaults)
    # ======================================================================

    # Live system login. OPNsense ships a dedicated installer account; logging
    # in as `installer` launches the installer instead of a shell.
    # Credentials installer/opnsense are published by the project, not secrets.
    "installer<enter><wait5s>",
    "opnsense<enter><wait30s>",

    # "Keymap Selection". The default highlighted entry is "Continue with
    # default keymap layout", so a bare Enter accepts US layout — which is
    # also the layout Packer's own keystroke mapping assumes. Changing the
    # keymap here would desynchronise every character typed afterwards.
    "<enter><wait10s>",

    # Main installer task menu.
    #
    # ⚠️ ASSUMPTION: the first entry is "Install (UFS)" and the cursor starts
    # on it, so a bare Enter selects it. VERIFY THIS FIRST when the build
    # breaks — it is the single most likely thing to have moved, and picking
    # the wrong entry here lands in "Import Configuration" or "Password Reset"
    # rather than an install.
    #
    # UFS rather than ZFS on purpose: the UFS path is two dialogs (pick disk,
    # confirm) where ZFS is four (vdev type, disk checklist, options, confirm).
    # Fewer dialogs is less to break. This firewall is rebuilt from this
    # template rather than upgraded in place, so ZFS boot environments — the
    # main reason to prefer ZFS on OPNsense — buy nothing here. If you want
    # ZFS, that is a one-line change plus re-tuning this section.
    "<enter><wait10s>",

    # Disk selection. One disk exists (scsi0 on virtio-scsi-single, which
    # FreeBSD enumerates as da0), so it is the only entry and is preselected.
    "<enter><wait5s>",

    # Destructive-write confirmation. The dialog defaults to "No"; one <right>
    # moves to "Yes".
    "<right><enter>",

    # ── The install itself ────────────────────────────────────────────────
    # Copies the DVD onto da0. On an NVMe-backed local-lvm this is a few
    # minutes; the margin here is deliberate because this is the one step that
    # is genuinely I/O-bound and varies with the host.
    "<wait8m>",

    # "Root Password" — new password, then confirmation.
    # Empty by default (see variables.pkr.hcl): an empty entry is rejected and
    # the build fails loudly rather than shipping a firewall with a password
    # that is public in this repository.
    "${var.root_password}<enter><wait2s>",
    "${var.root_password}<enter><wait10s>",

    # "Complete Install" → reboot into the installed system.
    "<enter><wait30s>",

    # ======================================================================
    # PHASE 2 — the installed system  (robust: a shell, not dialogs)
    # ======================================================================
    #
    # Everything below is typed into a real shell. Shell commands are the
    # STABLE part of this file: `ifconfig` and `pkg` have not moved in years,
    # whereas the dialogs above move between releases. When re-tuning, expect
    # to rewrite Phase 1 and keep Phase 2.

    # First boot: rc scripts, interface auto-assignment, ruleset load. Ends at
    # a console login prompt.
    "<wait4m>",
    "<enter><wait5s>",
    "root<enter><wait5s>",
    "${var.root_password}<enter><wait30s>",

    # OPNsense console menu. Option 8 is "Shell".
    # ⚠️ ASSUMPTION: option number 8. It has been stable for many releases but
    # it is a menu, so it is a version-bump risk like everything in Phase 1.
    "8<enter><wait10s>",

    # ── Build-plane networking ────────────────────────────────────────────
    # Nothing serves DHCP on vmbr9, so the half-built firewall gives itself an
    # address by hand purely so it can reach the OPNsense package mirror. All
    # of this is thrown away when the real config is imported a few lines down.
    #
    # This is done with ifconfig rather than the console's "Set interface IP
    # address" menu because ifconfig is not a dialog and cannot move.
    "ifconfig ${var.wan_if} inet ${var.build_address}/${var.build_prefix} up<enter><wait3s>",
    "route add default ${var.build_gateway}<enter><wait3s>",
    "echo 'nameserver ${var.upstream_dns}' > /etc/resolv.conf<enter><wait3s>",

    # Prove connectivity before the long step. If this fails the pkg commands
    # below fail too, but the ping output on the console is what tells a human
    # watching the build WHICH half broke.
    "ping -c 3 ${var.build_gateway}<enter><wait10s>",

    # ── Plugins ───────────────────────────────────────────────────────────
    # os-qemu-guest-agent: mandatory. Every VM in this lab is created with
    #   agent.enabled = true, and a VM with that set and no agent running
    #   blocks for fifteen minutes on every create AND every refresh.
    # os-suricata: decision D-04. Suricata runs here, inline on the firewall,
    #   because a Linux bridge does not mirror and a sensor VM on vmbr1 would
    #   see almost nothing. It is installed now, on the build plane, because
    #   after the real config is imported this machine has no working uplink
    #   until it is cloned into fw-01 and plugged into vmbr0.
    "pkg update -f<enter><wait2m>",
    "pkg install -y os-qemu-guest-agent os-suricata<enter><wait5m>",

    # ── Seed the real configuration ───────────────────────────────────────
    # Mount by ISO9660 volume label, not by device node: /dev/iso9660/OPNCFG
    # is stable regardless of whether the seed landed on cd0 or cd1.
    "mkdir -p /tmp/seed<enter><wait2s>",
    "mount_cd9660 /dev/iso9660/OPNCFG /tmp/seed<enter><wait5s>",
    "cp /tmp/seed/conf/config.xml /conf/config.xml<enter><wait3s>",
    "umount /tmp/seed<enter><wait3s>",

    # ── Hygiene before this becomes a template ────────────────────────────
    # /conf/backup holds previous configs. Right now that means the factory
    # default one; leaving it in a golden template means every clone ships a
    # copy of somebody else's config history.
    "rm -f /conf/backup/*.xml<enter><wait2s>",

    # SSH host keys must NOT be baked into a template: every clone would share
    # one identity, which is both a real security problem and the reason
    # "REMOTE HOST IDENTIFICATION HAS CHANGED" warnings get trained out of
    # people. OPNsense regenerates these on first boot when they are absent.
    "rm -f /conf/sshd/ssh_host_*<enter><wait2s>",
    "rm -f /etc/ssh/ssh_host_*<enter><wait2s>",

    # Flush to disk before anything stops the machine.
    "sync<enter><wait5s>",

    # Power off cleanly. The plugin will also issue its own stop before
    # converting to a template; stopping an already-stopped VM is a no-op, and
    # halting here is far more deterministic than relying on ACPI reaching a
    # shell session.
    "halt -p<enter><wait60s>",
  ]
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
#
# No provisioners: there is no communicator to run them over (see above).
# The manifest records which VMID this build produced.
#
# ⚠️ The manifest is a RECORD, not an input. It is tempting to feed
# artifact_id straight into OpenTofu's clone{ vm_id = ... }, and it would be
# actively dangerous: the entire clone block is ForceNew, so a manifest-driven
# VMID means every template rebuild destroys and recreates every VM cloned
# from it. The VMID is pinned in both places and asserted at plan time instead.

build {
  name    = "opnsense-267"
  sources = ["source.proxmox-iso.opnsense"]

  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
    custom_data = {
      template_name    = var.template_name
      template_vm_id   = "${var.template_vm_id}"
      opnsense_version = var.opnsense_version
      build_bridge     = var.build_bridge
    }
  }
}
