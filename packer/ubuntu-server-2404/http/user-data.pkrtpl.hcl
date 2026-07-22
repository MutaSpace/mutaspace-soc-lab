#cloud-config
#
# WHAT THIS IS
#   The subiquity autoinstall answer file for tpl-ubuntu-server-2404 (VMID 9000).
#   Packer renders it with templatefile() and serves it at /user-data from its built-in
#   HTTP server; the kernel command line points cloud-init's NoCloud datasource at that URL.
#
# WHY THE FIRST LINE MATTERS
#   `#cloud-config` is not a comment. cloud-init reads the first line to decide what kind of
#   payload this is. Without it the file is treated as an unrecognised blob and ignored, and
#   the installer falls back to asking a human questions that nobody is there to answer.
#
# WHY EVERYTHING IS NESTED UNDER `autoinstall:`
#   This file is a cloud-config document that CONTAINS an autoinstall document. Keys written
#   at the top level are cloud-config keys and subiquity never sees them. This is the single
#   most common shape error in Ubuntu autoinstall, and it fails quietly: the install runs,
#   just interactively.
#
# ${"$"}{...} SUBSTITUTIONS
#   Values in ${"$"}{...} are filled in by Packer's templatefile() before this is served.
#   They are not read by cloud-init.

autoinstall:
  version: 1

  # ---------------------------------------------------------------------------------
  # Locale and keyboard
  #
  # Set explicitly. Any question subiquity cannot answer from this file is a question it
  # asks on the console, and an unattended build has nobody to answer it.
  # ---------------------------------------------------------------------------------
  locale: en_US.UTF-8
  keyboard:
    layout: us

  # ---------------------------------------------------------------------------------
  # Network
  #
  # DHCP on the build plane. The Proxmox host is the gateway on 10.99.0.1 and masquerades
  # this subnet out through its physical NIC, which is the only reason a template build can
  # reach archive.ubuntu.com in a greenfield lab where fw-01 does not exist yet.
  #
  # This configuration does NOT survive into the clones - scripts/cleanup.sh deletes the
  # generated netplan file so that cloud-init regenerates it from OpenTofu's cloud-init
  # drive on first boot. That is how one image becomes wazuh-01 at 10.10.10.20 and
  # nlp-01 at 10.10.20.30.
  # ---------------------------------------------------------------------------------
  network:
    version: 2
    ethernets:
      # Match by driver rather than by name. Predictable interface names depend on PCI
      # topology, and the NIC is called ens18 during the build (on vmbr9) but may not be
      # after OpenTofu re-points the adapter. Matching the virtio driver is stable.
      buildnic:
        match:
          driver: virtio_net
        dhcp4: true

  # ---------------------------------------------------------------------------------
  # Identity
  #
  # The build account. It is baked into the golden image and therefore inherited by every
  # clone, so treat it as a real lab credential: Ansible manages the accounts that matter,
  # this one exists so automation has a way in and so a human can log in at the console when
  # a build fails at 2am.
  #
  # The password arrives here already hashed (SHA-512 crypt). The plaintext never exists in
  # this repository, in Packer's state, or in the rendered file.
  # ---------------------------------------------------------------------------------
  identity:
    hostname: ${hostname}
    username: ${username}
    password: "${password_hash}"

  # ---------------------------------------------------------------------------------
  # SSH
  #
  # install-server: true puts openssh-server in the installed system. allow-pw: false makes
  # the key the only way in over the network - the password above is a console credential,
  # not a remote one.
  # ---------------------------------------------------------------------------------
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - "${ssh_public_key}"

  # ---------------------------------------------------------------------------------
  # Storage
  #
  # sizing-policy: all is not a detail. The default is `scaled`, which deliberately leaves
  # most of a large disk unallocated - on a 20 GB disk you get roughly a 10 GB root and a
  # lot of confusion about where the rest went. `all` gives the root LV the whole disk.
  #
  # LVM rather than a plain partition, because it is what makes an online grow possible:
  # OpenTofu resizes scsi0 at clone time (up to 100 GB for wazuh-01) and cloud-init's
  # growpart extends the partition, the PV, the LV and the filesystem on first boot.
  # ---------------------------------------------------------------------------------
  storage:
    layout:
      name: lvm
      sizing-policy: all

  # ---------------------------------------------------------------------------------
  # Packages
  #
  # qemu-guest-agent is NOT optional here and its absence produces a baffling failure.
  # The Packer Proxmox plugin defaults qemu_agent to true, which means it asks the guest
  # agent for the VM's IP address rather than watching DHCP. No agent, no answer, and the
  # build sits at "Waiting for SSH" until ssh_timeout. Neither the ISO installer nor the
  # Ubuntu cloud image ships it. It is also how OpenTofu reads a clone's IP address later.
  #
  # cloud-init is already present on the live-server image; it is listed to make the
  # dependency explicit rather than incidental.
  # ---------------------------------------------------------------------------------
  packages:
    - qemu-guest-agent
    - cloud-init
    - python3
    - openssh-server

  # Apply security updates during the build so the golden image does not start life a month
  # behind. Anything more than `security` makes builds slow and non-reproducible.
  updates: security

  # Skip the "installation complete, press enter to reboot" prompt. Without this the build
  # stops one keystroke short of finishing.
  shutdown: reboot

  # ---------------------------------------------------------------------------------
  # late-commands
  #
  # These run inside the installer, with the freshly installed system mounted at /target.
  # `curtin in-target --` runs a command as though chrooted into it.
  # ---------------------------------------------------------------------------------
  late-commands:
    # Passwordless sudo for the build account.
    #
    # WHY: Packer's provisioners run `sudo -E bash /tmp/script.sh` over an SSH session
    # authenticated by key. There is no TTY and no password to feed to sudo, so without this
    # the cleanup script fails with "sudo: a terminal is required". The alternative - handing
    # Packer the plaintext password so it can pipe it to `sudo -S` - would mean the plaintext
    # has to exist somewhere, which is exactly what hashing it above was meant to avoid.
    #
    # This is a lab image and this line is a deliberate, documented tradeoff, not an
    # oversight. Ansible relies on it too.
    - echo '${username} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/90-${username}
    - chmod 0440 /target/etc/sudoers.d/90-${username}

    # Enable the guest agent explicitly. The package's unit is socket-activated on a virtio
    # serial port that only exists when the hypervisor provides it, and the enablement state
    # is worth pinning rather than inferring.
    - curtin in-target --target=/target -- systemctl enable qemu-guest-agent
