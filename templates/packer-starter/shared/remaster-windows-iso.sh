#!/usr/bin/env bash
# =============================================================================
# scripts/remaster-windows-iso.sh
#
# WHAT THIS IS
#   Rewrites a Windows installation ISO so it boots WITHOUT the
#
#       Press any key to boot from CD or DVD......
#
#   prompt. Everything else about the ISO is preserved byte-for-byte; only the
#   UEFI El Torito boot image is swapped.
#
# WHY IT EXISTS
#   That prompt is a ~5 second window, and if nothing answers it the firmware
#   falls through to the next boot device. On a fresh Packer build the next
#   device is an empty disk, so the run ends at:
#
#       BdsDxe: No bootable option or device was found.
#
#   and Packer then waits the full winrm_timeout for a machine that never
#   started installing.
#
#   The obvious fix is to have the boot_command press a key. That was tried, at
#   length: the Windows 11 template blanketed the window with 55 spacebars and
#   30 repeated <enter>s spanning ~130 seconds of wall clock. It still missed,
#   because the prompt appears at a VARIABLE delay after the boot device is
#   selected and QEMU's sendkey is not a reliable stream - it drops keystrokes
#   under load. Spraying more keys is not a fix, it is a louder guess.
#
#   Microsoft ships the answer inside every Windows ISO. There are two UEFI boot
#   images in efi/microsoft/boot/:
#
#       efisys.bin           - prompts, waits, falls through on timeout
#       efisys_noprompt.bin  - boots immediately
#
#   Remastering with the second one deletes the race instead of trying to win
#   it. The boot_command then only has to steer the firmware's boot menu, which
#   is a deterministic sequence.
#
# LICENSING - READ THIS
#   The remastered ISO is a derivative of Microsoft evaluation media. It is for
#   YOUR host only. Do not redistribute it, do not copy it to another
#   instructor's machine, and do not put it anywhere shared. Each operator
#   downloads their own media and runs this script themselves. See the Windows
#   licensing section of CLAUDE.md and docs/proxmox/iso-shelf.md.
#
# WHERE IT RUNS
#   ON the Proxmox host, as root, because that is where the ISO shelf lives and
#   where there is disk space to unpack 8 GB.
#
# USAGE
#   ./remaster-windows-iso.sh --help
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly ISO_DIR_DEFAULT="/var/lib/vz/template/iso"

SRC=""
OUT=""
ISO_DIR="$ISO_DIR_DEFAULT"
KEEP_WORK=0
FORCE=0

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GRN=$'\033[32m'
  C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_BLD=$'\033[1m'
else
  C_RESET=''; C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_BLD=''
fi
info()    { printf '%s[ .. ]%s %s\n' "$C_BLU" "$C_RESET" "$*"; }
changed() { printf '%s[ ++ ]%s %s\n' "$C_GRN" "$C_RESET" "$*"; }
warn()    { printf '%s[ !! ]%s %s\n' "$C_YEL" "$C_RESET" "$*" >&2; }
die()     { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
section() { printf '\n%s%s== %s ==%s\n' "$C_BLD" "$C_BLU" "$*" "$C_RESET"; }

usage() {
  cat <<EOF
${SCRIPT_NAME} - remaster a Windows ISO to boot without the "press any key" prompt

Runs ON the Proxmox host, as root.

USAGE
  sudo ./${SCRIPT_NAME} --src <iso> [--out <iso>]

OPTIONS
  --src <file>    Source Windows ISO. A bare filename is resolved inside
                  ${ISO_DIR_DEFAULT}.
  --out <file>    Output ISO. Default: the source name with "-noprompt" inserted
                  before the extension.
  --iso-dir <dir> ISO shelf. Default: ${ISO_DIR_DEFAULT}
  --keep-work     Do not delete the unpacked tree (for inspection).
  --force         Overwrite the output ISO if it exists.
  -h, --help      Show this help.

AFTER RUNNING
  Point the Packer template at the new ISO, in the gitignored pkrvars file:

      windows_iso_file = "local:iso/<output name>"

  and simplify the boot_command: it no longer needs to answer a CD prompt, only
  to pick the DVD in the firmware boot menu.

EXAMPLE
  sudo ./${SCRIPT_NAME} --src Win11_25H2_English_x64_v2.iso
EOF
}

while (( $# )); do
  case "$1" in
    --src)      shift; [[ $# -gt 0 ]] || die "--src needs a value"; SRC="$1" ;;
    --src=*)    SRC="${1#*=}" ;;
    --out)      shift; [[ $# -gt 0 ]] || die "--out needs a value"; OUT="$1" ;;
    --out=*)    OUT="${1#*=}" ;;
    --iso-dir)  shift; [[ $# -gt 0 ]] || die "--iso-dir needs a value"; ISO_DIR="$1" ;;
    --iso-dir=*) ISO_DIR="${1#*=}" ;;
    --keep-work) KEEP_WORK=1 ;;
    --force)     FORCE=1 ;;
    -h|--help)  usage; exit 0 ;;
    *)          usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done

# -----------------------------------------------------------------------------
section "preflight"

[[ "${EUID}" -eq 0 ]] || die "must run as root (mount and the ISO shelf both need it)"
[[ -n "$SRC" ]] || { usage >&2; die "--src is required"; }
# genisoimage, NOT xorriso, and the reason is not a preference.
#
# Windows 11 media carries sources/install.wim at ~7 GB, which is past the 4 GB
# single-extent ceiling of ISO 9660. Windows Setup reads that file over UDF, so
# the rebuilt image has to carry a UDF filesystem.
#
# xorriso cannot create UDF. It builds ISO 9660 + Rock Ridge + Joliet (+HFS+) and
# its mkisofs emulation rejects -udf outright:
#     xorriso : FAILURE : -as mkisofs: Unsupported option '-udf'
# Dropping -udf and relying on ISO 9660 multi-extent instead would produce an
# image Windows Setup may or may not read, which is not a coin worth flipping
# after an 8 GB copy.
command -v genisoimage >/dev/null 2>&1 \
  || die "genisoimage not found. Install it: apt-get install -y genisoimage
  (xorriso will NOT do: it cannot create the UDF filesystem that Windows Setup
   needs to read the ~7 GB sources/install.wim.)"

# Resolve a bare filename against the shelf.
[[ "$SRC" == /* ]] || SRC="${ISO_DIR}/${SRC}"
[[ -f "$SRC" ]] || die "source ISO not found: ${SRC}"

if [[ -z "$OUT" ]]; then
  base="$(basename "$SRC")"
  OUT="${ISO_DIR}/${base%.*}-noprompt.iso"
fi
[[ "$OUT" == /* ]] || OUT="${ISO_DIR}/${OUT}"

if [[ -e "$OUT" ]] && (( ! FORCE )); then
  die "output already exists: ${OUT}  (use --force to overwrite)"
fi

src_bytes="$(stat -c %s "$SRC")"
src_gb=$(( src_bytes / 1024 / 1024 / 1024 ))
# Unpacked tree + new ISO, so budget roughly 2.2x the source.
need_gb=$(( src_gb * 22 / 10 + 2 ))
avail_gb="$(df -BG --output=avail "$ISO_DIR" | tail -1 | tr -dc '0-9')"
info "source ${src_gb} GB; need ~${need_gb} GB; ${avail_gb} GB available on $(df --output=target "$ISO_DIR" | tail -1)"
(( avail_gb >= need_gb )) || die "not enough space: need ~${need_gb} GB, have ${avail_gb} GB"

# -----------------------------------------------------------------------------
section "inspect the source"

MNT="$(mktemp -d)"
WORK="$(mktemp -d -p "$ISO_DIR" .remaster-XXXXXX)"

cleanup() {
  mountpoint -q "$MNT" 2>/dev/null && umount "$MNT" 2>/dev/null || true
  rmdir "$MNT" 2>/dev/null || true
  if (( KEEP_WORK )); then
    warn "left the unpacked tree at ${WORK} (--keep-work)"
  else
    rm -rf "$WORK" 2>/dev/null || true
  fi
}
trap cleanup EXIT

mount -o loop,ro "$SRC" "$MNT" 2>/dev/null || die "could not mount ${SRC}"

NOPROMPT_REL="efi/microsoft/boot/efisys_noprompt.bin"
[[ -f "${MNT}/${NOPROMPT_REL}" ]] \
  || die "${NOPROMPT_REL} is not in this ISO. Is it really Windows installation media?"
info "found ${NOPROMPT_REL}"

# The BIOS boot image. Optional: this lab's VMs are OVMF/q35 and boot the UEFI
# entry, but keeping the BIOS entry costs nothing and preserves the ISO's ability
# to boot a SeaBIOS machine.
ETFS_REL="boot/etfsboot.com"
HAVE_ETFS=0
[[ -f "${MNT}/${ETFS_REL}" ]] && { HAVE_ETFS=1; info "found ${ETFS_REL} (BIOS entry will be preserved)"; }

# Volume id, so the remastered ISO identifies itself the same way. Windows Setup
# does not depend on this, but a differently-labelled disc is confusing to a human
# looking at the Proxmox hardware tab.
VOLID="$(xorriso -indev "$SRC" -report_system_area cmd 2>/dev/null \
         | grep -oP -- "-volid '\K[^']+" | head -1 || true)"
[[ -n "$VOLID" ]] || VOLID="$(blkid -o value -s LABEL "$SRC" 2>/dev/null || echo CCCOMA_X64FRE_EN-US_DV9)"
info "volume id: ${VOLID}"

# -----------------------------------------------------------------------------
section "unpack"

info "copying $(du -sh "$MNT" | cut -f1) - this takes a few minutes"
# -a to preserve everything; the source is read-only so perms come out sane.
cp -a "${MNT}/." "${WORK}/"
umount "$MNT"
changed "unpacked to ${WORK}"

# Windows ISOs ship read-only; xorriso needs to read them, which is fine, but a
# later rm -rf needs write permission on the directories.
chmod -R u+w "$WORK"

# -----------------------------------------------------------------------------
section "rebuild"

# THE ONE MEANINGFUL FLAG IN THIS SCRIPT:
#
#   -e efi/microsoft/boot/efisys_noprompt.bin
#
# rather than efisys.bin. Everything else reproduces a standard Windows ISO
# layout so Setup finds what it expects.
#
#   -udf                  REQUIRED. sources/install.wim is ~7 GB, past the 4 GB
#                         ISO 9660 single-extent ceiling, and Setup reads it over
#                         UDF. This is the flag xorriso cannot provide.
#   -iso-level 3          Long/deep paths, and multi-extent as a belt-and-braces
#                         companion to UDF.
#   -no-emul-boot         El Torito "no emulation" for both entries.
#   -boot-load-size 8     4 KB (8 x 512 B sectors) for the BIOS entry.
#   -eltorito-alt-boot    Separates the BIOS entry from the UEFI entry.
#   -allow-limited-size   Lets genisoimage accept the >4 GB member instead of
#                         refusing outright.
GENISO_ARGS=(
  -iso-level 3
  -udf
  -allow-limited-size
  -volid "$VOLID"
  -disable-deep-relocation
  -untranslated-filenames
)
if (( HAVE_ETFS )); then
  GENISO_ARGS+=( -b "$ETFS_REL" -no-emul-boot -boot-load-size 8 -eltorito-alt-boot )
fi
# -e IS -efi-boot in genisoimage, which already implies the EFI platform id.
# There is no -eltorito-platform option here (that is a cdrtools/mkisofs flag);
# passing one makes genisoimage treat the value as a path and fail with
#   genisoimage: No such file or directory. Invalid node - 'efi'.
GENISO_ARGS+=( -e "$NOPROMPT_REL" -no-emul-boot -o "$OUT" "$WORK" )

info "genisoimage ${GENISO_ARGS[*]}"
# genisoimage is chatty on stderr (percent complete); keep only the tail.
genisoimage "${GENISO_ARGS[@]}" 2>&1 | tail -6

[[ -f "$OUT" ]] || die "genisoimage did not produce ${OUT}"
chmod 644 "$OUT"

# -----------------------------------------------------------------------------
section "verify"

out_bytes="$(stat -c %s "$OUT")"
info "output: $(( out_bytes / 1024 / 1024 )) MB"

# The output must be at least in the same ballpark. A tiny ISO means the copy
# silently failed and the result would boot to nothing.
(( out_bytes > src_bytes / 2 )) \
  || die "output is suspiciously small ($(( out_bytes / 1024 / 1024 )) MB vs source $(( src_bytes / 1024 / 1024 )) MB)"

# Prove the UEFI El Torito entry points at the noprompt image, rather than
# trusting that the flag did what it says.
if xorriso -indev "$OUT" -report_el_torito plain 2>&1 | grep -qi 'noprompt'; then
  changed "El Torito UEFI entry references efisys_noprompt.bin"
else
  # xorriso does not always echo the source path in the report; fall back to
  # confirming the boot catalog exists and the file is present in the tree.
  if xorriso -indev "$OUT" -find "$NOPROMPT_REL" 2>/dev/null | grep -q noprompt; then
    warn "could not read the boot image name out of the El Torito report,"
    warn "  but ${NOPROMPT_REL} is present in the image. Confirm by booting it:"
    warn "  a remastered ISO does NOT print 'Press any key to boot from CD or DVD'."
  else
    die "the remastered ISO does not contain ${NOPROMPT_REL} - do not use it"
  fi
fi

section "next steps"
cat <<EOF
  Output: ${OUT}

  1. Point the Packer template at it, in the GITIGNORED pkrvars file
     (packer/win11-client/win11-client.pkrvars.hcl):

       windows_iso_file = "local:iso/$(basename "$OUT")"

  2. Rebuild:  task build:win11

  3. Watch the console on the first attempt. The remastered ISO must NOT print
     "Press any key to boot from CD or DVD". If it still does, the El Torito
     entry did not take and the boot race is still there.

  LICENSING: this ISO is a derivative of Microsoft evaluation media. It is for
  THIS host only. Do not redistribute it - each instructor remasters their own.
EOF
