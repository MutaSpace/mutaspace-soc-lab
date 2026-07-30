#!/usr/bin/env bash
#
# cleanup.sh - identity-stripping script for tpl-kali-rolling (VMID 9005).
#
# WHAT THIS IS
#   The last thing that runs before Packer converts the build VM into a template. It removes
#   every fact that describes THIS machine, so the image can be given a new identity at
#   clone time instead of inheriting an old one.
#
# WHY IT MATTERS MORE HERE THAN ANYWHERE ELSE IN THE LAB
#   kali-01 and untrusted-01 are LINKED clones of this template. They share its disk. If the
#   template carries a machine ID, an SSH host key or a cloud-init "already done" marker,
#   both attack boxes carry the SAME one - and the two machines whose entire purpose is to
#   be distinguishable from each other in the SIEM become indistinguishable.
#
# WHAT IS DIFFERENT FROM THE UBUNTU CLEANUP SCRIPTS
#   There is no subiquity here, so there are no installer overrides to delete: the whole
#   "de-subiquity" section of the Ubuntu scripts has no equivalent. What Kali has instead is
#   uncertainty about cloud-init, because cloud-init is not part of the distribution - the
#   preseed installed it. Step 3 says so plainly rather than pretending otherwise.

set -euo pipefail

echo "==> [1/8] pinning the cloud-init datasource list"
#
# Without a pin, cloud-init probes every datasource it knows: EC2, Azure, GCE, OpenStack,
# Oracle. Each probe is an HTTP request to a link-local metadata address that does not exist
# on vmbr2, and each one has to time out before the next is tried. That is tens of seconds
# added to every boot of a machine learners are going to reboot a lot.
#
# Proxmox presents cloud-init data as a NoCloud CD-ROM.
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-pve.cfg <<'EOF'
# Pinned by packer/kali-rolling/scripts/cleanup.sh.
# Proxmox presents cloud-init data as a NoCloud CD-ROM. Probing cloud providers that do not
# exist on the isolated segment costs tens of seconds per boot.
datasource_list: [ NoCloud, ConfigDrive ]
EOF

echo "==> [2/8] clearing cloud-init state and its seed"
#
# --logs  removes the build's cloud-init logs, which contain the rendered configuration.
# --seed  removes the cached seed, so a clone cannot find the BUILD's seed before its own
#         drive and reapply the build's identity.
#
# Guarded, because cloud-init came from the preseed rather than from the distribution: if it
# is not there, that is worth knowing about but is not a reason to fail the build with a
# "command not found" that says nothing useful.
if command -v cloud-init >/dev/null 2>&1; then
  cloud-init clean --logs --seed
  rm -rf /var/lib/cloud/*
else
  echo "    WARNING: cloud-init is not installed. The clones will NOT pick up their static"
  echo "    addresses (10.10.20.10 / 10.10.20.20) from OpenTofu's cloud-init drive."
  echo "    Check the preseed's pkgsel/include line before using this template."
fi

echo "==> [3/8] removing generated network configuration"
#
# HONEST STATUS: this is the least verified step in the Linux templates and it is called out
# rather than buried.
#
# On Ubuntu, cloud-init renders netplan and the story is simple. On Debian and Kali,
# cloud-init picks a renderer at runtime: netplan if netplan is installed, otherwise
# `eni` (/etc/network/interfaces.d/), and Kali's desktop images add NetworkManager as a
# third thing that wants to own the interface. Which of the three actually wins on a given
# Kali build has NOT been tested here, because it cannot be tested without the Proxmox host.
#
# Both possible outputs are removed so that whichever renderer cloud-init chooses on the
# clone starts from nothing rather than from the build's DHCP-on-vmbr9 configuration.
#
# IF THE CLONES COME UP WITH NO NETWORK, THIS IS THE FIRST PLACE TO LOOK. The documented
# fallback is to stop relying on cloud-init for Kali's addressing entirely: let the clones
# take DHCP and have Ansible write the static addresses. That costs one play and removes an
# unknown.
rm -f /etc/network/interfaces.d/50-cloud-init
rm -f /etc/netplan/50-cloud-init.yaml
rm -f /etc/NetworkManager/system-connections/*
rm -rf /var/lib/NetworkManager/*

echo "==> [4/8] deleting SSH host keys"
#
# Host keys identify the MACHINE, not the user. Two linked clones of one template presenting
# one host key means known_hosts cannot tell kali-01 from untrusted-01, and SSH's only
# protection against a man-in-the-middle quietly stops working. On the lab's designated
# hostile segment that is not an acceptable shortcut.
#
# The openssh-server unit regenerates a fresh set on first boot when none are present.
rm -f /etc/ssh/ssh_host_*

echo "==> [5/8] resetting the machine ID"
#
# TRUNCATE, DO NOT DELETE.
#   empty file   -> systemd generates a new ID on first boot.
#   missing file -> the DHCP client identifier that derives from it disappears, and systemd
#                   may take a different initialisation path entirely.
#
# Every clone sharing a machine ID means every clone presenting the same DHCP client
# identifier and fighting over one lease.
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

echo "==> [6/8] making sure no Wazuh agent identity is baked in"
#
# The Wazuh agent is not installed by this template, so this file normally does not exist.
# The guard stays because the failure it prevents is silent and expensive: a populated
# client.keys in a golden image means every clone enrols as the SAME agent, the manager
# rejects the duplicates with "Duplicate agent name", and the endpoint stops appearing in
# the SIEM. Losing telemetry from the attack box is losing the half of the story that the
# detections are supposed to catch.
#
# Truncate rather than remove - the agent expects the file and re-registers into it.
if [ -f /var/ossec/etc/client.keys ]; then
  truncate -s 0 /var/ossec/etc/client.keys
fi

echo "==> [7/8] clearing build traces"
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*

# Truncate rather than delete so files keep their ownership and permissions.
find /var/log -type f -exec truncate -s 0 {} \;

rm -f /root/.bash_history
rm -f /home/*/.bash_history

echo "==> [8/8] returning freed blocks to the thin pool"
#
# The guest-side half of `discard = true` on the disk: the disk option lets discards through
# to the storage layer, fstrim is what issues them. This matters more for this template than
# any other, because its two consumers are linked clones sharing one thin pool with every
# other VM on the host, and a full LVM-thin pool stalls writes everywhere at once.
fstrim -av || true

sync
echo "==> cleanup complete - this image now has no identity of its own, which is the point"
