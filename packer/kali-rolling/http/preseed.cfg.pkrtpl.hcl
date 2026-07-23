# preseed.cfg - unattended answer file for tpl-kali-rolling (VMID 9005)
#
# WHAT THIS IS
#   A debconf preseed. Kali is Debian, so its installer is debian-installer, and the way you
#   automate debian-installer is to pre-answer its questions. Packer serves this file over
#   HTTP and the kernel command line points the installer at it.
#
# HOW TO READ A PRESEED LINE
#   <owner> <question-name> <type> <value>
#   e.g.  d-i  partman-auto/method  string  regular
#   The owner is usually `d-i` (the installer itself); `tasksel` and package names appear
#   when the question belongs to a package rather than to the installer.
#
# WHY THIS LOOKS NOTHING LIKE THE UBUNTU FILES
#   Ubuntu Server and Desktop use subiquity's `autoinstall`, which is YAML nested inside a
#   cloud-config document. Debian and Kali use preseeding, which is a flat list of debconf
#   answers. Same goal, unrelated syntax. Do not try to translate between them line by line.
#
# ${"$"}{...} values are substituted by Packer's templatefile() before this is served.
#
# ---------------------------------------------------------------------------------------
# Locale, keyboard, console
# ---------------------------------------------------------------------------------------
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us
d-i console-setup/ask_detect boolean false

# ---------------------------------------------------------------------------------------
# Network
#
# DHCP on the build plane (vmbr9, 10.99.0.0/24, masqueraded by the Proxmox host). This is
# the only network with a route to the internet while the lab is being built, and the
# installer needs one to fetch packages from Kali's mirror.
#
# The CLONES do not live here. kali-01 lands on vmbr2 at 10.10.20.10 and untrusted-01 at
# 10.10.20.20, behind a default-deny policy toward the SOC LAN. Nothing about that is
# configured here - it is applied at clone time.
#
# netcfg/choose_interface = auto picks the first interface that has a link, which on a
# single-NIC build VM is the only one there is. Naming it explicitly would hard-code a
# device name that can change.
# ---------------------------------------------------------------------------------------
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string ${hostname}
d-i netcfg/get_domain string ${domain}
d-i netcfg/hostname string ${hostname}

# Do not stop and complain if DHCP is slow; retry instead. A hung installer waiting on a
# network prompt is the most common way an unattended Debian build fails.
d-i netcfg/dhcp_timeout string 60
d-i netcfg/dhcpv6_timeout string 60

# ---------------------------------------------------------------------------------------
# Mirror
#
# Pinned to Kali's rolling suite. `http.kali.org` is a redirector that picks a nearby
# mirror, which is the right default for a lab that may move.
# ---------------------------------------------------------------------------------------
d-i mirror/country string manual
d-i mirror/http/hostname string http.kali.org
d-i mirror/http/directory string /kali
d-i mirror/http/proxy string
d-i mirror/suite string kali-rolling

# USE the mirror, do not just point at it. FOUND THE HARD WAY, 2026-07-23.
#
# The mirror/* settings above only say WHERE the mirror is. Without the line below,
# d-i installing from a full Kali DVD writes ONLY the cdrom source into the target's
# /etc/apt/sources.list and never adds the network mirror. pkgsel then installs from
# the DVD alone, and cloud-init is not on the DVD (it IS in the network repo), so:
#
#   in-target: E: Package 'cloud-init' has no installation candidate
#   main-menu: Configuring 'pkgsel' failed with error code 100
#
# Because cloud-init shared one apt transaction with the rest of pkgsel/include, its
# failure aborted the WHOLE step - so openssh-server and qemu-guest-agent never
# installed either, and the build then died at "Timeout waiting for SSH" with a guest
# that had no agent and no sshd. The symptom pointed at a boot hang; the cause was one
# unavailable package on the install media.
#
# use_mirror=true adds the network mirror so pkgsel can reach cloud-init.
# disable-cdrom-entries removes the DVD source from the INSTALLED system, so the
# clone's apt does not error looking for a disc that is not there.
d-i apt-setup/use_mirror boolean true
d-i apt-setup/disable-cdrom-entries boolean true

# ---------------------------------------------------------------------------------------
# Clock
#
# UTC in the guest, always. Log correlation is the entire point of a SOC lab: an endpoint
# whose clock runs on local time produces events that appear to happen at a different moment
# than the same events seen by the SIEM, and every investigation built on that is wrong in a
# way that is very hard to notice.
#
# NTP is enabled here so the image has a sane clock during the build. The lab's real time
# source is fw-01, and Ansible points the clones at it.
# ---------------------------------------------------------------------------------------
d-i clock-setup/utc boolean true
d-i time/zone string Etc/UTC
d-i clock-setup/ntp boolean true

# ---------------------------------------------------------------------------------------
# Accounts
#
# Root login is DISABLED and a sudo-capable account is created instead. Two reasons:
#   - it matches how modern Kali ships, so nothing surprising happens to a learner;
#   - the Ubuntu templates in this repository use the same account name, which keeps the
#     Ansible inventory from needing per-host user overrides.
#
# The password arrives already SHA-512 hashed. The plaintext exists only in the operator's
# shell, never in this repository and never in the rendered file.
# ---------------------------------------------------------------------------------------
d-i passwd/root-login boolean false
d-i passwd/make-user boolean true
d-i passwd/user-fullname string MutaSpace Lab Admin
d-i passwd/username string ${username}
d-i passwd/user-password-crypted password ${password_hash}

# ---------------------------------------------------------------------------------------
# Partitioning
#
# `regular` + `atomic` means one big root partition plus swap, on /dev/sda.
#
# WHY NOT LVM HERE, WHEN THE UBUNTU TEMPLATES USE IT
#   Because these two VMs are LINKED clones with a hard 20 GB ceiling inherited from
#   untrusted-01, and they are disposable by design - an attack box that gets broken is
#   supposed to be thrown away and re-cloned, not repaired. LVM earns its keep when you need
#   to grow or reshape storage over a long life. Neither of these machines has one.
#
# /dev/sda is correct because the disk is attached to a virtio-scsi controller, which
# presents as a SCSI disk. A virtio-blk disk would be /dev/vda, and getting this wrong makes
# the installer stop to ask which disk to use.
# ---------------------------------------------------------------------------------------
d-i partman-auto/disk string /dev/sda
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic

# Confirm every destructive step. An unattended installer that stops to ask "are you sure"
# is an unattended installer that hangs.
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
d-i partman-md/confirm boolean true
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true

# ---------------------------------------------------------------------------------------
# Package selection
#
# DELIBERATELY MINIMAL, and this is a design decision worth defending.
#
# The obvious thing to do on a Kali image is to install `kali-linux-default`, the metapackage
# that pulls in the full standard tool set. Two reasons not to:
#
#   1. IT DOES NOT FIT. The template disk is capped at 20 GB by untrusted-01, the smaller of
#      the two linked clones. kali-linux-default plus a desktop does not leave usable room.
#
#   2. TOOLING IS ANSIBLE'S JOB, NOT PACKER'S. kali-01 does attack simulation and
#      untrusted-01 does trust-boundary research. Those are different tool sets. Baking the
#      union of them into a shared golden image means every change to either one is a
#      template rebuild - and a template rebuild, for a linked clone, means destroying and
#      re-cloning both VMs.
#
# The image carries what it needs to be MANAGED: a guest agent, SSH, cloud-init, sudo and
# Python for Ansible. Everything a pentester recognises as Kali is layered on afterwards.
#
# `standard` is the base Debian task; no desktop task is selected.
# ---------------------------------------------------------------------------------------
tasksel tasksel/first multiselect standard

d-i pkgsel/include string qemu-guest-agent openssh-server cloud-init sudo python3 ca-certificates

# Kali is rolling, so "upgrade" means "pull in whatever is current today". `none` keeps the
# build reproducible for the length of one build; the image is expected to be rebuilt, not
# maintained.
d-i pkgsel/upgrade select none

# Do not phone home with a package usage survey from a lab machine.
popularity-contest popularity-contest/participate boolean false

# ---------------------------------------------------------------------------------------
# Bootloader
# ---------------------------------------------------------------------------------------
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev string /dev/sda

# ---------------------------------------------------------------------------------------
# Finish
#
# Do not display "Installation complete, press Continue to reboot" - there is nobody to
# press it. The VM reboots straight into the installed system, and because the VM's boot
# order puts scsi0 ahead of the CD, it boots the new install rather than the installer.
# ---------------------------------------------------------------------------------------
d-i finish-install/reboot_in_progress note

# ---------------------------------------------------------------------------------------
# late_command
#
# Runs inside the installer, just before reboot, with the installed system mounted at
# /target. `in-target <cmd>` runs a command as though chrooted into the new system; a bare
# shell redirect writes to /target/... from the installer's own filesystem view. The two
# forms are mixed below because writing a file is easier the second way and changing its
# ownership is easier the first.
#
# Everything here exists so Packer and Ansible can get in:
#
#   authorized_keys  - Packer's SSH communicator authenticates with the key, so the password
#                      hashed above is a console credential and nothing more.
#
#   NOPASSWD sudo    - Packer's provisioners run `sudo -E bash /tmp/script.sh` over a
#                      key-authenticated session with no TTY. Without this, sudo demands a
#                      password on a terminal that does not exist and the cleanup script -
#                      the step that makes this a template rather than a copy of one machine
#                      - never runs. The alternative is giving Packer the plaintext password,
#                      which defeats the point of hashing it. Deliberate lab tradeoff.
#
#   ssh / qemu-guest-agent enabled - the agent is how both Packer and OpenTofu discover the
#                      VM's IP address. Without it the build hangs at "Waiting for SSH".
# ---------------------------------------------------------------------------------------
d-i preseed/late_command string \
    in-target mkdir -p /home/${username}/.ssh ; \
    echo '${ssh_public_key}' > /target/home/${username}/.ssh/authorized_keys ; \
    in-target chown -R ${username}:${username} /home/${username}/.ssh ; \
    in-target chmod 0700 /home/${username}/.ssh ; \
    in-target chmod 0600 /home/${username}/.ssh/authorized_keys ; \
    echo '${username} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/90-${username} ; \
    in-target chmod 0440 /etc/sudoers.d/90-${username} ; \
    in-target systemctl enable ssh ; \
    in-target systemctl enable qemu-guest-agent
