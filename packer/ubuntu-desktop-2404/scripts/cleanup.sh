#!/usr/bin/env bash
#
# cleanup.sh - the "de-subiquity" script for tpl-ubuntu-desktop-2404 (VMID 9001).
#
# WHAT THIS IS
#   The last thing that runs before Packer converts the build VM into a template. It strips
#   the BUILD's identity out of the image so the image has no identity at all and can be
#   given one at clone time.
#
# WHY IT IS THE MOST IMPORTANT FILE IN THIS DIRECTORY
#   A golden image is an installed system with every unique fact removed. Skip this and the
#   build succeeds, the template converts, the clone boots - and then it quietly keeps the
#   build's machine ID, SSH host keys, DHCP client identifier, and a cloud-init override
#   that says "cloud-init is finished here, ignore that drive". Nothing errors. It just does
#   not work, in ways that look like a networking problem.
#
#   `cloud-init clean` alone is the classic half-fix. It clears cloud-init's STATE. It does
#   not remove the installer's CONFIGURATION, and it is the configuration that disables
#   cloud-init on clones.
#
# THIS FILE IS A NEAR-TWIN OF packer/ubuntu-server-2404/scripts/cleanup.sh.
#   The duplication is deliberate. These are the last words spoken to two different images
#   and the desktop has genuinely different state to strip (a display manager, a login
#   session, NetworkManager). A shared script would have to branch on flavour and would be
#   read by nobody. Sections 10 and 11 are the desktop-only ones.

set -euo pipefail

echo "==> [1/11] removing the installer's cloud-init overrides"
#
#   99-installer.cfg
#       Written by the installer. Contains `datasource_list: [ None ]` - literally "there is
#       no datasource here". A clone therefore ignores the cloud-init drive OpenTofu
#       attached, keeps the build's hostname, and never applies its SSH key. This one file
#       is the difference between a template and a broken template.
#
#   subiquity-disable-cloudinit-networking.cfg
#       Contains `network: {config: disabled}`. On a clone it means cloud-init will never
#       write the network configuration it was handed.
#
#   curtin-preserve-sources.cfg
#       Tells cloud-init not to manage apt sources because the installer already did.
#
rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg
rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg
rm -f /etc/cloud/cloud.cfg.d/curtin-preserve-sources.cfg

echo "==> [2/11] pinning the datasource list"
#
# With the installer's override gone, cloud-init probes every datasource it knows - EC2,
# Azure, GCE, OpenStack, Oracle - by making HTTP requests to link-local metadata addresses
# that do not exist on this network. Each one has to time out. That is tens of seconds added
# to every boot, and on a desktop the learner is watching it happen.
cat > /etc/cloud/cloud.cfg.d/99-pve.cfg <<'EOF'
# Pinned by packer/ubuntu-desktop-2404/scripts/cleanup.sh.
# Proxmox presents cloud-init data as a NoCloud CD-ROM.
datasource_list: [ NoCloud, ConfigDrive ]
EOF

echo "==> [3/11] removing the installer's netplan configuration"
#
# Deleted so cloud-init REGENERATES 50-cloud-init.yaml on the clone's first boot, from
# whatever OpenTofu wrote to the cloud-init drive.
#
# CONSEQUENCE: a clone that boots without a cloud-init drive has no network at all. That is
# intentional - an image that silently keeps the wrong address is much harder to debug than
# one with no address - but it means the console is your only way in if the drive is missing.
rm -f /etc/netplan/00-installer-config.yaml
rm -f /etc/netplan/50-cloud-init.yaml
rm -f /etc/netplan/01-network-manager-all.yaml

echo "==> [4/11] clearing cloud-init state and its seed"
#
# --logs  removes the build's cloud-init logs, which contain the rendered user-data.
# --seed  removes the cached NoCloud seed, so a clone cannot find the BUILD's seed before
#         its own drive and reapply the build's identity.
#
# Runs AFTER the configuration removal above; the other order lets cloud-init re-read the
# installer overrides while cleaning.
cloud-init clean --logs --seed

echo "==> [5/11] emptying /var/lib/cloud"
#
# /var/lib/cloud/instance is a symlink to the build's instance directory, and
# /var/lib/cloud/sem holds "this module already ran" semaphores. A stale semaphore is how a
# clone decides it has already set its hostname. Note the trailing /* - the directory itself
# must survive.
rm -rf /var/lib/cloud/*

echo "==> [6/11] deleting SSH host keys"
#
# Host keys identify the MACHINE. Left in place, every clone presents the same host key,
# known_hosts stops meaning anything, and SSH's only man-in-the-middle protection is gone.
# In a SOC teaching lab that matters more than the convenience of skipping a prompt.
# The openssh-server unit regenerates a fresh set on first boot when none are present.
rm -f /etc/ssh/ssh_host_*

echo "==> [7/11] resetting the machine ID"
#
# TRUNCATE, DO NOT DELETE.
#   empty file   -> systemd generates a new ID on first boot.
#   missing file -> netplan loses the value it uses as the DHCP CLIENT IDENTIFIER.
#
# That last point is load-bearing here specifically: analyst-01 does not get a static
# address, it gets a DHCP RESERVATION at 10.10.10.50. Reservations depend on the client
# presenting a stable, UNIQUE identity. Every clone sharing one machine-id means every clone
# asking for the same lease.
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

echo "==> [8/11] making sure no Wazuh agent identity is baked in"
#
# This template does not install the agent, so the file usually does not exist. The guard
# stays because the failure is expensive and silent: a populated client.keys in a golden
# image means every clone enrols as the SAME agent, the manager rejects duplicates, and
# endpoints stop reporting to the SIEM. Truncate rather than delete - the agent expects the
# file to exist and re-registers into it.
if [ -f /var/ossec/etc/client.keys ]; then
  truncate -s 0 /var/ossec/etc/client.keys
fi

echo "==> [9/11] shrinking the image and clearing build traces"
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*

# Truncate rather than delete, so files keep their ownership and permissions.
find /var/log -type f -exec truncate -s 0 {} \;

rm -f /root/.bash_history
rm -f /home/*/.bash_history

# ---------------------------------------------------------------------------------------
# DESKTOP-ONLY STEPS START HERE
# ---------------------------------------------------------------------------------------

echo "==> [10/11] clearing desktop session and NetworkManager state"
#
# A desktop carries per-machine state that a server does not, and all of it describes the
# BUILD:
#
#   NetworkManager system-connections - saved profiles bound to the build NIC's MAC address.
#       On a clone with a different MAC they simply never activate, and the learner sees a
#       desktop with no network and no explanation.
#
#   GDM / AccountsService caches - the display manager remembers the last user, the session
#       type and the user's icon. Harmless but confusing on a fresh clone.
#
#   The build account's caches - thumbnails, recently-used lists, trash. These leak what was
#       done during the build into every learner's desktop.
rm -f /etc/NetworkManager/system-connections/*
rm -rf /var/lib/NetworkManager/*
rm -f /var/lib/AccountsService/users/*
rm -rf /home/*/.cache/*
rm -rf /home/*/.local/share/Trash/*
rm -f /home/*/.local/share/recently-used.xbel

echo "==> [11/11] keeping the desktop's network under NetworkManager"
#
# A desktop-specific trap, stated honestly because it has NOT been verified against a real
# build yet.
#
# cloud-init writes /etc/netplan/50-cloud-init.yaml without a `renderer:` key, and netplan's
# default renderer is systemd-networkd. On a server that is exactly right. On a DESKTOP it
# means GNOME's network applet shows no connections at all, because NetworkManager is not
# the thing managing the interface - the machine is online but the UI insists it is not,
# which is a genuinely bad first impression for an analyst workstation.
#
# netplan merges every file in /etc/netplan in lexical order, and `renderer` is a global
# key, so a 99- file wins over cloud-init's 50- file without having to modify it.
#
# If this turns out to fight with cloud-init on a real build, the fallback is to delete this
# file and let networkd own the interface - the machine still works, the applet just lies.
cat > /etc/netplan/99-renderer-networkmanager.yaml <<'EOF'
# Written by packer/ubuntu-desktop-2404/scripts/cleanup.sh.
# Netplan defaults to systemd-networkd. On a desktop that leaves GNOME's network applet
# blank even though the machine is online. `renderer` is a global key and files merge in
# lexical order, so this overrides cloud-init's 50-cloud-init.yaml without editing it.
network:
  version: 2
  renderer: NetworkManager
EOF
chmod 0600 /etc/netplan/99-renderer-networkmanager.yaml

# Zero out free space so the LVM-thin pool can reclaim it. This is the guest-side half of
# `discard = true` on the disk: the disk option lets discards through, fstrim issues them.
fstrim -av || true

sync
echo "==> cleanup complete - this image now has no identity of its own, which is the point"
