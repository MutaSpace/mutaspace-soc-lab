# Per-template variables for tpl-kali-rolling (VMID 9005).
#
# WHY THIS FILE EXISTS, SEPARATE FROM common.pkrvars.hcl:
#   common.pkrvars.hcl is shared by every build and binds the generic `iso_file` to the
#   Ubuntu server ISO. Kali's installer ISO therefore cannot ride on `iso_file` - it would
#   collide - so it uses its own `kali_iso_file`, set here, exactly the way the Windows
#   templates keep `windows_iso_file` out of common. Pass this file IN ADDITION to common:
#
#     packer build -var-file=packer/common.pkrvars.hcl \
#                  -var-file=packer/kali-rolling/kali.pkrvars.hcl packer/kali-rolling/
#
# The ISO was downloaded onto the host directly (the host has a fast uplink) rather than
# pushed ~4 GB over the workstation's VPN. Filename and sha256 verified 2026-07-23 against
# https://kali.download/base-images/kali-2026.2/SHA256SUMS. When Kali rolls, update this
# filename, iso_url and iso_checksum together, and record it in docs/proxmox/iso-shelf.md.
kali_iso_file = "local:iso/kali-linux-2026.2-installer-amd64.iso"
