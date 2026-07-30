#!/usr/bin/env bash
#
# cleanup.sh - the "de-subiquity" script for tpl-ubuntu-server-2404 (VMID 9000).
#
# WHAT THIS IS
#   The last thing that runs before Packer converts the build VM into a template. It strips
#   the BUILD's identity out of the image so that the image has no identity at all, and can
#   therefore be given one at clone time.
#
# WHY IT IS THE MOST IMPORTANT FILE IN THIS DIRECTORY
#   A golden image is not "an installed system you stopped using". It is an installed system
#   with every unique fact removed. Skip this script and the build succeeds, the template
#   converts, the clones boot - and then wazuh-01 and nlp-01 quietly share a machine ID, a
#   DHCP lease, an SSH host key and, worst of all, a cloud-init configuration that says
#   "cloud-init is already done here, ignore the drive". Nothing errors. It just does not
#   work, for reasons that look like networking.
#
#   The specific trap on Ubuntu Server is that the installer, subiquity, deliberately writes
#   files whose job is to DISABLE cloud-init on the installed system. That is correct
#   behaviour for a machine a human installed. It is catastrophic for a template.
#
# WHAT `cloud-init clean` DOES AND DOES NOT DO
#   `cloud-init clean` removes cloud-init's cached STATE. It does not remove the installer's
#   CONFIGURATION. Running it alone is the most common half-fix in golden imaging: it looks
#   like the right command, it exits 0, and the template is still broken.
#
# ORDER MATTERS
#   Configuration is removed BEFORE state, and the machine ID is reset LAST, because
#   cloud-init writes files while it runs and a reset performed too early can be undone.

set -euo pipefail

echo "==> [1/9] removing the installer's cloud-init overrides"
#
# This is the step that everything else depends on.
#
#   99-installer.cfg
#       Written by subiquity. It contains `datasource_list: [ None ]` plus the seed the
#       installer used. `[ None ]` means "there is no datasource" - so a clone dutifully
#       ignores the cloud-init drive that OpenTofu attached, keeps the build's hostname,
#       keeps the build's IP configuration, and never applies the SSH key. This single file
#       is the difference between a template and a broken template.
#
#   subiquity-disable-cloudinit-networking.cfg
#       Contains `network: {config: disabled}`. Correct for an installed machine whose
#       netplan a human owns. On a clone it means cloud-init will never write the static
#       address the lab design assigns, and the VM comes up with no usable network.
#
#   curtin-preserve-sources.cfg
#       Tells cloud-init not to manage apt sources, because the installer already did.
#       Harmless-looking, but it silently overrides any apt configuration handed to a clone.
#
rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg
rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg
rm -f /etc/cloud/cloud.cfg.d/curtin-preserve-sources.cfg

echo "==> [2/9] pinning the datasource list to the ones this lab actually uses"
#
# With the installer's override gone, cloud-init falls back to probing EVERY datasource it
# knows: EC2, Azure, GCE, OpenStack, Oracle, and more. Each probe is an HTTP request to a
# link-local metadata address that does not exist here, and each one has to time out.
# On a lab with no internet path until fw-01 routes, that is tens of seconds added to every
# single boot of every single VM.
#
# Proxmox presents cloud-init data as a NoCloud CD-ROM. ConfigDrive is kept as a second
# option because it costs nothing and covers the alternative shape.
cat > /etc/cloud/cloud.cfg.d/99-pve.cfg <<'EOF'
# Pinned by packer/ubuntu-server-2404/scripts/cleanup.sh.
# Proxmox attaches cloud-init data as a NoCloud CD-ROM. Probing cloud providers that do not
# exist on this network costs tens of seconds per boot.
datasource_list: [ NoCloud, ConfigDrive ]
EOF

echo "==> [3/9] removing the installer's netplan configuration"
#
# 00-installer-config.yaml is the netplan the installer wrote from the autoinstall file. It
# hard-codes the build-plane NIC on vmbr9. 50-cloud-init.yaml is the netplan cloud-init
# generated during the build.
#
# Both are deleted so that cloud-init REGENERATES 50-cloud-init.yaml on the clone's first
# boot, from the address OpenTofu put on the cloud-init drive.
#
# CONSEQUENCE WORTH KNOWING: a clone of this template that boots WITHOUT a cloud-init drive
# has no network configuration at all. That is intentional - an image that silently keeps
# working with the wrong address is much harder to debug than one that has no address - but
# it means the console is the only way in if the cloud-init drive is missing.
rm -f /etc/netplan/00-installer-config.yaml
rm -f /etc/netplan/50-cloud-init.yaml

echo "==> [4/9] clearing cloud-init state and its seed"
#
# --logs  removes /var/log/cloud-init*.log, which contain the build's hostname, IP and
#         the full rendered user-data. Not just tidiness: that user-data is a seed file.
# --seed  removes the cached NoCloud seed from the build. Without this, a clone can find
#         the BUILD's seed before it finds its own drive and reapply the build's identity.
#
# This must run AFTER the configuration removal above, or cloud-init re-reads the installer
# overrides while cleaning and leaves state behind.
cloud-init clean --logs --seed

echo "==> [5/9] emptying /var/lib/cloud"
#
# `cloud-init clean` leaves some of this behind depending on version. /var/lib/cloud/instance
# is a symlink to the build's instance directory and /var/lib/cloud/sem holds the
# "this module already ran" semaphores. A stale semaphore is how a clone decides it has
# already set its hostname.
#
# Note the trailing /* - the directory itself must survive, only its contents go.
rm -rf /var/lib/cloud/*

echo "==> [6/9] deleting SSH host keys"
#
# Host keys identify the MACHINE, not the user. Left in place, every VM in the lab presents
# the same host key, so an analyst's SSH client cannot tell wazuh-01 from nlp-01 and
# known_hosts becomes meaningless - which quietly destroys the only protection SSH offers
# against a man-in-the-middle. In a SOC teaching lab that is worth more than convenience.
#
# openssh-server's systemd unit regenerates a fresh set on first boot when none are present.
rm -f /etc/ssh/ssh_host_*

echo "==> [7/9] resetting the machine ID"
#
# TRUNCATE. DO NOT DELETE. The distinction is real and it bites:
#
#   empty file  -> systemd sees "uninitialised" and generates a new ID on first boot.
#   missing file -> systemd may take a different path entirely, and more importantly netplan
#                   uses /etc/machine-id as the DHCP client identifier. No machine-id means
#                   no stable client-id, and the DHCP reservations this lab depends on
#                   (analyst-01 at .50, win-client-01 at .51) stop being reliable.
#
# Without this reset every clone presents the SAME client identifier, so the DHCP server
# hands them all the SAME lease and they fight over one address.
truncate -s 0 /etc/machine-id

# D-Bus keeps its own copy. Point it at the real one so there is a single source of truth
# instead of two IDs that drift apart.
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

echo "==> [8/9] making sure no Wazuh agent identity is baked in"
#
# This template does not install the Wazuh agent, so the file below normally does not exist.
# The guard is here anyway because the failure it prevents is expensive and non-obvious:
# a populated /var/ossec/etc/client.keys in a golden image means every clone enrols as the
# SAME agent, the manager rejects the duplicates with "Duplicate agent name", and endpoints
# silently stop reporting to the SIEM. In a lab whose entire purpose is log collection, that
# is the worst possible thing to get wrong quietly.
#
# Truncate rather than remove: the agent expects the file to exist and re-registers into it.
if [ -f /var/ossec/etc/client.keys ]; then
  truncate -s 0 /var/ossec/etc/client.keys
fi

echo "==> [9/9] shrinking the image and clearing build traces"
#
# Package lists and cached .deb files are regenerated on the first `apt update`, and they
# are a surprising fraction of the image. Everything here is about the size and cleanliness
# of the template, not its correctness - which is why it runs last.
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*

# Logs from the build describe the build, not the clone. Truncate rather than delete so the
# files keep their ownership and permissions and rsyslog does not have to recreate them.
find /var/log -type f -exec truncate -s 0 {} \;

# Shell history from the build, for both the build account and root.
rm -f /root/.bash_history
rm -f /home/*/.bash_history

# Zero out free space so the LVM-thin pool can reclaim it. `fstrim` is the cheap version of
# the old "dd a huge file of zeros then delete it" trick and does not temporarily fill the
# disk. This is the guest-side half of the `discard = true` setting on the disk: the disk
# option lets discards through, fstrim is what issues them.
fstrim -av || true

sync
echo "==> cleanup complete - this image now has no identity of its own, which is the point"
