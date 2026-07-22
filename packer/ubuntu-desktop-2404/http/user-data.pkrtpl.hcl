#cloud-config
#
# WHAT THIS IS
#   The subiquity autoinstall answer file for tpl-ubuntu-desktop-2404 (VMID 9001).
#
# THE TWO SHAPE RULES THAT BREAK MOST AUTOINSTALL FILES
#   1. `#cloud-config` on line 1 is not a comment. cloud-init reads it to decide what kind
#      of document this is. Without it the file is ignored and the install goes interactive.
#   2. Everything belongs under `autoinstall:`. Keys at the top level are cloud-config keys
#      and subiquity never sees them. This fails quietly - the install still runs, it just
#      asks a human.
#
# ${"$"}{...} values are substituted by Packer's templatefile() before this is served.

autoinstall:
  version: 1

  # ---------------------------------------------------------------------------------
  # Install source
  #
  # THIS IS THE KEY DIFFERENCE FROM THE SERVER TEMPLATE.
  #
  # The Ubuntu Desktop ISO carries more than one install source, and `id: ubuntu-desktop`
  # selects the full desktop session rather than a minimal or server-flavoured install.
  # It is stated explicitly rather than left to the ISO's default so that this file says
  # what it means, and so it cannot change meaning underneath us if Canonical reorders the
  # sources in a later point release.
  #
  # search_drivers: false keeps the build deterministic. Driver search reaches out to
  # Canonical's servers and can install different third-party packages depending on when the
  # build runs, which is the opposite of what a golden image is for. There is no proprietary
  # hardware in a KVM guest to find drivers for anyway.
  # ---------------------------------------------------------------------------------
  source:
    id: ubuntu-desktop
    search_drivers: false

  locale: en_US.UTF-8
  keyboard:
    layout: us

  # ---------------------------------------------------------------------------------
  # Network
  #
  # DHCP on the build plane (vmbr9, 10.99.0.0/24, masqueraded by the Proxmox host). This is
  # build-time only: scripts/cleanup.sh deletes the generated netplan so that cloud-init
  # regenerates it on the clone's first boot.
  #
  # analyst-01 does not get a static address at all - it gets a DHCP RESERVATION at
  # 10.10.10.50, pinned by MAC on fw-01. That is why the MAC address is an input to the
  # design rather than something Proxmox invents: the reservation and the NIC are templated
  # from the same map, which is what keeps .50 stable across rebuilds.
  #
  # Matched by driver rather than by interface name: the NIC is ens18 during the build, and
  # predictable names depend on PCI topology that can differ after OpenTofu re-points the
  # adapter to vmbr1.
  # ---------------------------------------------------------------------------------
  network:
    version: 2
    ethernets:
      buildnic:
        match:
          driver: virtio_net
        dhcp4: true

  # ---------------------------------------------------------------------------------
  # Identity
  #
  # On a desktop image this account is also the GRAPHICAL login, so unlike the headless
  # templates the password here is a credential a human will actually type. It still never
  # exists in plaintext in this repository: it arrives already SHA-512 hashed.
  # ---------------------------------------------------------------------------------
  identity:
    hostname: ${hostname}
    username: ${username}
    password: "${password_hash}"

  # ---------------------------------------------------------------------------------
  # SSH
  #
  # A desktop machine still needs to be managed by Ansible, so openssh-server goes in and
  # the key is the only network credential. allow-pw: false means the password above works
  # at the graphical console and nowhere else.
  # ---------------------------------------------------------------------------------
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - "${ssh_public_key}"

  # ---------------------------------------------------------------------------------
  # Storage
  #
  # sizing-policy: all, for the same reason as the server template: the default `scaled`
  # policy deliberately leaves most of the disk unallocated. On a desktop image that is
  # worse, because the installed footprint is already large.
  # ---------------------------------------------------------------------------------
  storage:
    layout:
      name: lvm
      sizing-policy: all

  # ---------------------------------------------------------------------------------
  # Packages
  #
  # qemu-guest-agent is mandatory and its absence is the single most confusing failure in
  # this build: the Packer plugin defaults to asking the guest agent for the VM's IP, so
  # without it the build sits at "Waiting for SSH" until ssh_timeout and then dies with no
  # useful error.
  # ---------------------------------------------------------------------------------
  packages:
    - qemu-guest-agent
    - cloud-init
    - openssh-server
    - python3

  updates: security
  shutdown: reboot

  # ---------------------------------------------------------------------------------
  # late-commands - run inside the installer with the new system mounted at /target.
  # ---------------------------------------------------------------------------------
  late-commands:
    # Passwordless sudo for the build account, because Packer's provisioners run
    # `sudo -E bash` over a key-authenticated SSH session with no TTY and no password to
    # give. The alternative is handing Packer the plaintext password, which defeats the
    # point of hashing it. Deliberate lab tradeoff, and Ansible depends on it too.
    - echo '${username} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/90-${username}
    - chmod 0440 /target/etc/sudoers.d/90-${username}

    - curtin in-target --target=/target -- systemctl enable qemu-guest-agent

    # Desktop-only: stop GNOME's first-run wizard from appearing on the clone.
    #
    # gnome-initial-setup asks for language, keyboard, privacy and online accounts the first
    # time a NEW user logs in. On a template that means every learner meets a setup wizard
    # instead of a desktop, and the wizard's answers are not something the lab wants to vary.
    - curtin in-target --target=/target -- bash -c "mkdir -p /etc/skel/.config && touch /etc/skel/.config/gnome-initial-setup-done"
