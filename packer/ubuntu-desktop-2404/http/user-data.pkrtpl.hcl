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
  # The Ubuntu Desktop ISO carries more than one install source, and the one marked
  # `default: true` is NOT the one you want. Read off the 24.04.4 media itself
  # (/casper/install-sources.yaml), verified 2026-07-22:
  #
  #     id: ubuntu-desktop-minimal   default: true    path: minimal.squashfs
  #     id: ubuntu-desktop           default: false   path: minimal.standard.squashfs
  #
  # So `id: ubuntu-desktop` is what selects the FULL desktop. Delete this block and the
  # build silently produces the minimized flavour: no LibreOffice, no Thunderbird, a
  # different seeded snap set. It installs cleanly and boots to a normal-looking GNOME, so
  # the difference only shows up much later, when someone goes looking for an application
  # that a real Ubuntu Desktop has and this template does not.
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
  # DHCP wherever the build runs. On this host that is vmbr0, the management LAN, which
  # already serves DHCP and has a real gateway; the design's original vmbr9 build plane
  # (10.99.0.0/24, masqueraded by the Proxmox host) works too. Either way DHCP is the only
  # thing this file needs to say, which is exactly why it says DHCP and not an address.
  #
  # This is build-time only: scripts/cleanup.sh deletes the generated netplan so that
  # cloud-init regenerates it on the clone's first boot.
  #
  # analyst-01 does not get a static address at all - it gets a DHCP RESERVATION at
  # 10.10.10.50, pinned by MAC on fw-01. That is why the MAC address is an input to the
  # design rather than something Proxmox invents: the reservation and the NIC are templated
  # from the same map, which is what keeps .50 stable across rebuilds.
  #
  # MATCHED BY NAME, NOT BY DRIVER. THIS IS THE DESKTOP-ONLY LANDMINE. READ THIS BEFORE
  # "TIDYING" IT BACK TO match: driver:.
  #
  # The server template (packer/ubuntu-server-2404) matches `driver: virtio_net`, and that
  # is correct THERE. It is fatal here, and the reason is the renderer:
  #
  #   * Ubuntu SERVER renders netplan through systemd-networkd, which can match on driver.
  #   * Ubuntu DESKTOP ships /etc/netplan/01-network-manager-all.yaml, which sets
  #     `renderer: NetworkManager` GLOBALLY. netplan merges every file in /etc/netplan, so
  #     that renderer also governs the file this section produces - and NetworkManager's
  #     netplan backend cannot match on driver.
  #
  # WHAT IT LOOKS LIKE WHEN YOU GET IT WRONG, observed on a real build 2026-07-22:
  #
  #   The install runs to completion. The machine reboots. GDM comes up and offers
  #   `labadmin`, so everything looks finished and correct. But there is no network icon in
  #   the top bar, `ip -br addr` shows `ens18  DOWN`, nmcli says `ens18:ethernet:unmanaged`,
  #   and Packer sits at "Waiting for SSH to become available..." until ssh_timeout and then
  #   fails with nothing useful in the log. The whole build is lost 25 minutes in.
  #
  #   The actual error is only visible from inside the guest:
  #
  #     # netplan generate
  #     ERROR: buildnic: NetworkManager definitions do not support matching by driver
  #
  #   And note HOW BAD that failure is: `netplan generate` fails for the ENTIRE merged
  #   configuration, not just for the offending stanza. One unsupported key means no backend
  #   configuration is written for ANY interface, so the machine has no network at all.
  #   cloud-init records it too - `cloud-init status --long` reports the failed netplan
  #   generate - but you have to already have a way in to read that.
  #
  # WHY `name: "en*"` IS THE RIGHT FIX RATHER THAN A HARD-CODED `ens18`.
  #   NetworkManager supports interface-name matching including globs, and netplan renders
  #   it to `[match] interface-name=en*` in the generated .nmconnection - verified on this
  #   image with `netplan generate --root-dir`, which exits 0 and writes a DHCP connection.
  #   The glob keeps the original intent: no dependence on a specific predictable name, so
  #   the file survives the NIC moving to a different bridge or PCI slot.
  #
  #   `macaddress` also works under NetworkManager, but a golden image must not contain the
  #   build VM's MAC.
  # ---------------------------------------------------------------------------------
  network:
    version: 2
    ethernets:
      buildnic:
        match:
          name: "en*"
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
