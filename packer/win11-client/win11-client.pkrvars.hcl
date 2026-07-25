# Windows 11 25H2. NOT the "enterprise-eval" the variable default implies - same
# installer and the same w11 VirtIO driver paths, only the filename differs.
# Registration-gated, so there is no URL to pin. See docs/proxmox/iso-shelf.md.
# Remastered by scripts/remaster-windows-iso.sh so the CD boots without the
# "Press any key to boot from CD or DVD" prompt. See the boot_command note in
# win11-client.pkr.hcl. Do NOT point this back at the original ISO.
windows_iso_file = "local:iso/Win11_25H2_English_x64_v2-noprompt.iso"

# This is MULTI-EDITION CONSUMER media, not the single-image enterprise-eval the
# variable default (index 1) assumes. `dism`-equivalent read of sources/install.wim
# on 2026-07-22 gave 11 editions; index 1 is Windows 11 HOME, which CANNOT join a
# domain - and win-client-01 domain-joins mutaspace.local. Index 6 is Windows 11 Pro,
# the domain-capable edition a real endpoint runs. Verify if you re-fetch the media:
#   1=Home 4=Education 6=Pro 8=Pro Education 10=Pro for Workstations
windows_image_index = 6

# Generic Windows 11 Pro key, for EDITION SELECTION ONLY.
#
# This ISO is CONSUMER MULTI-EDITION media - sources/install.wim carries 11
# editions - so Setup cannot decide which one to install and stops at its
# "Product key" page. /IMAGE/INDEX alone does not suppress that page.
#
# This is Microsoft's published generic key for Windows 11 Pro. It selects the
# edition and does NOT activate: the installed system is unactivated, exactly as
# it would be from evaluation media. It is not a licence and carries none.
#
# Must match windows_image_index above (6 = Windows 11 Pro).
# If you switch to Enterprise EVALUATION media, REMOVE this line - eval media
# carries its own edition and rejects a key.
product_key = "VK7JG-NPHTM-C97JM-9MPGT-3V66T"
