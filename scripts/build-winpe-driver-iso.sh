#!/usr/bin/env bash
# =============================================================================
# scripts/build-winpe-driver-iso.sh
#
# Builds a small ISO whose ROOT contains a $WinPEDriver$ folder, from the pinned
# virtio-win ISO. Runs ON the Proxmox host.
#
# WHY THIS EXISTS
#   Windows Setup scans the root of every attached volume for a folder named
#   exactly $WinPEDriver$ and drvloads whatever it finds, BEFORE it enumerates
#   storage for the disk-selection step. That timing is the entire point.
#
#   Both answer-file mechanisms were tried first and neither works on this media
#   (Windows Server 2022 Evaluation, March 2022, on PVE 9.2.2):
#
#     Microsoft-Windows-PnpCustomizationsWinPE
#       -> Setup aborts at "Setup is starting" with
#          "Windows could not apply the Windows PE bootstrap setting specified in
#           the unattend answer file"
#          even when every path it references is verified to exist and the
#          drivers load by hand with drvload in that same WinPE.
#
#     Microsoft-Windows-Setup/RunSynchronous calling drvload
#       -> runs too late. Setup has already enumerated storage, so it still stops
#          at "Windows needs the driver for device
#          [Red Hat VirtIO SCSI pass-through controller]".
#
#   $WinPEDriver$ sidesteps both: no answer file to reject it, and no drive
#   letter to guess.
#
# WHY NOT JUST ATTACH THE VIRTIO ISO
#   Its drivers are not at the root in a $WinPEDriver$ folder, so Setup does not
#   scan them. This builds a 29 MB volume with the four drivers WinPE needs
#   rather than shipping all 693 MB.
#
# USAGE
#   ./build-winpe-driver-iso.sh [--virtio <path>] [--out <path>]
# =============================================================================
set -euo pipefail

VIRTIO_ISO="/var/lib/vz/template/iso/virtio-win-0.1.271.iso"
OUT_ISO="/var/lib/vz/template/iso/virtio-winpe-drivers.iso"
# The drivers WinPE itself needs: storage to see the disk, network for WinRM,
# plus the two the guest wants early. Everything else installs later from the
# full virtio ISO via the guest tools MSI.
DRIVERS=(vioscsi NetKVM vioserial Balloon)
WIN_VARIANT="2k22"

while (( $# )); do
  case "$1" in
    --virtio) shift; VIRTIO_ISO="$1" ;;
    --out)    shift; OUT_ISO="$1" ;;
    --variant) shift; WIN_VARIANT="$1" ;;   # 2k22 for Server 2022, w11 for Windows 11
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

[[ $EUID -eq 0 ]] || { echo "must run as root on the Proxmox host" >&2; exit 1; }
[[ -f "$VIRTIO_ISO" ]] || { echo "virtio ISO not found: $VIRTIO_ISO" >&2; exit 1; }
command -v xorriso >/dev/null || { echo "xorriso missing: apt install xorriso" >&2; exit 1; }

STAGE="$(mktemp -d)"
MNT="$(mktemp -d)"
cleanup() { umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true; rm -rf "$STAGE"; }
trap cleanup EXIT

mount -o loop,ro "$VIRTIO_ISO" "$MNT"

# The folder name is literal and case-sensitive to Setup's scan. The dollar signs
# are quoted so the shell does not eat them.
DEST="${STAGE}/\$WinPEDriver\$"
mkdir -p "$DEST"

for d in "${DRIVERS[@]}"; do
  src="${MNT}/${d}/${WIN_VARIANT}/amd64"
  if [[ -d "$src" ]]; then
    cp -r "$src" "${DEST}/${d}"
    echo "  added ${d} (${WIN_VARIANT}/amd64)"
  else
    echo "  WARNING: ${src} not found - skipping ${d}" >&2
  fi
done

xorriso -as mkisofs -J -joliet-long -r -V WINPEDRV -o "$OUT_ISO" "$STAGE" >/dev/null 2>&1

echo
echo "built: $OUT_ISO ($(du -h "$OUT_ISO" | cut -f1))"
echo "attach it to the build VM; Setup will find \$WinPEDriver\$ on its own."
