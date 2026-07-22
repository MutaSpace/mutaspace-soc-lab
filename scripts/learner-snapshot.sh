#!/usr/bin/env bash
# =============================================================================
# scripts/learner-snapshot.sh
#
# WHAT THIS IS
#   Takes the 'baseline' snapshot of one learner's VMs. The instructor runs this
#   ONCE per learner, at the start of a module. scripts/learner-reset.sh then
#   rolls back to it as many times as the learner needs.
#
# WHY IT EXISTS, AND WHY IT IS A SNAPSHOT AND NOT A BACKUP
#   The obvious reset mechanism is vzdump + qmrestore. It is the wrong one here.
#   A vzdump backup is always LOGICALLY full: it reads the guest-visible disk,
#   so a linked clone's backup contains the whole base template, and qmrestore
#   allocates a fresh standalone volume. The linked-clone relationship - the
#   thing that lets a 64 GB host hold three learners' endpoints - is destroyed
#   by the restore. qm snapshot / qm rollback preserves it.
#
# WHY THE VM IS STOPPED FIRST, AND WHY THERE IS NO --vmstate
#   A snapshot of a RUNNING VM with RAM state writes a multi-gigabyte vmstate
#   file, and the storage-selection chain for vmstate ends at 'local' - the 96 GB
#   root LV. Worse, rolling back to a RAM snapshot RESUMES the guest mid-flight
#   instead of cold-booting it. For a classroom that is exactly the wrong
#   semantics: "reset" should mean "boot from a known-good disk", not "resume a
#   process from a fortnight ago".
#
# WHY EXACTLY ONE SNAPSHOT PER VM
#   Whether rolling back to a non-most-recent snapshot on LVM-thin silently
#   deletes newer snapshots is not something this lab has verified (on ZFS it
#   demonstrably requires destroying newer ones). One snapshot named 'baseline'
#   sidesteps the question entirely. That is why --replace exists and why this
#   script refuses to add a second snapshot by default.
#
# WHAT IT ASSUMES
#   * It runs ON the Proxmox VE host, as root. 'qm' is a host-local tool.
#   * Learner VMIDs follow the documented policy:
#         vmid = 200 + (learner_index * 10) + role_offset
#         role offsets:  win-client = 5, kali = 6
#   * Those VMs already exist. This script never creates or clones anything.
#
# ⚠️ WHERE learner_index COMES FROM, AND WHERE THIS SCRIPT CAN BE WRONG
#   In lab.yaml and tofu/locals.tf, learner_index is the POSITION IN THE ROSTER
#   (`for idx, learner in local.enabled_learners`). The id is just a label.
#
#   This script runs on the Proxmox host, where lab.yaml does not exist, so it
#   cannot read the roster. It assumes index = id - 1, which is correct for the
#   contiguous roster 01, 02, 03 the lab ships with - and WRONG the moment a
#   learner is removed or an id is skipped. Remove learner 02 from the roster
#   and learner 03 moves from index 2 to index 1, i.e. from VMIDs 225/226 to
#   215/216, while this script still computes 225/226.
#
#   Two guards exist for that:
#     * --index <n> passes the roster position explicitly.
#     * Every VM is checked by NAME before it is touched. The VM at the computed
#       VMID must be called '<role>-l<id>' - the same name OpenTofu gives it. A
#       mismatch is a hard error, so the worst case is a refusal to act, never a
#       snapshot taken of somebody else's machine.
#
# USAGE
#   ./learner-snapshot.sh --help
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SNAPSHOT_DEFAULT="baseline"

# role name -> VMID offset within the learner's block of ten.
readonly ROLE_NAMES=("win-client" "kali")
readonly ROLE_OFFSETS=(5 6)

readonly LEARNER_ID_MIN=1
# 20 is the ceiling tofu/variables.tf enforces on learner_count: above it the
# per-learner address block (host .60 upward, step 2) runs into the DHCP pool at
# .100. A learner beyond 20 can never have been built, so accepting one here
# could only ever produce a confusing "VM does not exist".
readonly LEARNER_ID_MAX=20

SNAPSHOT_NAME="$SNAPSHOT_DEFAULT"
LEARNER_INDEX=""             # explicit roster position; empty means "id - 1"
DESCRIPTION=""
REPLACE=0
DRY_RUN=0
START_AFTER=0
SHUTDOWN_TIMEOUT=180

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GRN=$'\033[32m'
  C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_BLD=$'\033[1m'
else
  C_RESET=''; C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_BLD=''
fi

info() { printf '%s[ .. ]%s %s\n' "$C_BLU" "$C_RESET" "$*"; }
ok()   { printf '%s[ ok ]%s %s\n' "$C_GRN" "$C_RESET" "$*"; }
warn() { printf '%s[ !! ]%s %s\n' "$C_YEL" "$C_RESET" "$*" >&2; }
die()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

run() {
  local desc="$1"; shift
  if (( DRY_RUN )); then
    printf '%s[ dry ]%s %s\n         $ %s\n' "$C_YEL" "$C_RESET" "$desc" "$*"
    return 0
  fi
  info "$desc"
  "$@"
}

usage() {
  cat <<EOF
${SCRIPT_NAME} - take the 'baseline' snapshot of a learner's VMs

Runs ON the Proxmox VE host, as root. Shuts each of the learner's VMs down,
takes one disk-only snapshot per VM, and leaves them stopped.

USAGE
  sudo ./${SCRIPT_NAME} <learner-id> [options]

ARGUMENTS
  <learner-id>   ${LEARNER_ID_MIN}..${LEARNER_ID_MAX}, with or without a leading zero (01, 1, 12).

OPTIONS
  --index <n>            The learner's 0-based POSITION IN THE ROSTER in
                         lab.yaml, which is what the VMID is actually derived
                         from. Defaults to (learner-id - 1), which is correct
                         only while the roster is a contiguous 01, 02, 03...
                         Pass this explicitly if an id has been skipped or a
                         learner removed.
  --name <snap>          Snapshot name. Default: ${SNAPSHOT_DEFAULT}
                         Change this only if you know why. learner-reset.sh
                         defaults to the same name.
  --description <text>   Snapshot description. Default: an auto-generated one
                         naming the learner and the date.
  --replace              Delete an existing snapshot of the same name first.
                         Without this, an existing snapshot is a hard error -
                         accumulating snapshots is what this design avoids.
  --start                Start the VMs again after snapshotting. Off by default:
                         the instructor usually takes the baseline and hands the
                         VMs over cold.
  --shutdown-timeout <s> Seconds to wait for a clean guest shutdown before
                         giving up. Default: ${SHUTDOWN_TIMEOUT}
  --dry-run              Print every action without performing it.
  -h, --help             Show this help and exit.

EXAMPLES
  sudo ./${SCRIPT_NAME} 01
  sudo ./${SCRIPT_NAME} 03 --replace --description "start of module 3"

VMID POLICY
  vmid = 200 + (roster_index * 10) + role_offset
  role offsets: win-client=5, kali=6
  learner 01 -> 205, 206      learner 02 -> 215, 216

  roster_index is the learner's position in lab.yaml, NOT their id. The two
  coincide for the roster this lab ships with. Every VM is verified by name
  before it is touched, so a mismatch stops the script rather than snapshotting
  somebody else's machine.

SEE ALSO
  scripts/learner-reset.sh    the other half of this pair
  docs/iac/design.md          section 7, "Classroom Lifecycle"
EOF
}

# -----------------------------------------------------------------------------
# Learner id -> VMIDs
# -----------------------------------------------------------------------------
LEARNER_ID=""
LEARNER_PADDED=""
declare -a LEARNER_VMIDS=()
declare -a LEARNER_ROLES=()

resolve_learner() {
  local raw="$1"
  [[ "$raw" =~ ^[0-9]{1,2}$ ]] || die "learner id must be 1-2 digits, got: '${raw}'"

  # 10#  forces base 10 so that '08' is eight, not an invalid octal literal.
  LEARNER_ID="$((10#$raw))"
  (( LEARNER_ID >= LEARNER_ID_MIN && LEARNER_ID <= LEARNER_ID_MAX )) \
    || die "learner id ${LEARNER_ID} is outside ${LEARNER_ID_MIN}..${LEARNER_ID_MAX}"

  LEARNER_PADDED="$(printf '%02d' "$LEARNER_ID")"

  # Roster position, which is what the VMID is really derived from. See the
  # header: id - 1 is an assumption, --index is the escape hatch.
  local index
  if [[ -n "$LEARNER_INDEX" ]]; then
    index="$LEARNER_INDEX"
  else
    index=$(( LEARNER_ID - 1 ))
  fi
  local base=$(( 200 + index * 10 ))

  local i
  for i in "${!ROLE_NAMES[@]}"; do
    LEARNER_VMIDS+=( $(( base + ROLE_OFFSETS[i] )) )
    LEARNER_ROLES+=( "${ROLE_NAMES[i]}" )
  done
}

# Refuse to touch a VM that is not the one we think it is.
#
# OpenTofu names these '<role>-l<id>' (tofu/locals.tf). If the VM sitting at the
# computed VMID has a different name, the roster-index assumption above has
# broken and continuing would mean snapshotting another learner's machine.
assert_vm_belongs_to_learner() {
  local vmid="$1" role="$2"
  local expected="${role}-l${LEARNER_PADDED}"
  local actual
  actual="$(vm_name "$vmid" || true)"

  [[ -z "$actual" || "$actual" == "$expected" ]] || die "VM ${vmid} is named '${actual}', but learner ${LEARNER_PADDED}'s ${role} should be '${expected}'.
       The VMID was computed from the roster position, and that assumption has
       broken - most likely a learner was removed from lab.yaml or an id was
       skipped, so positions shifted. Nothing has been changed.
       Re-run with the correct 0-based roster position:
         sudo ${SCRIPT_NAME} ${LEARNER_PADDED} --index <n>"
}

vm_exists()   { qm config "$1" >/dev/null 2>&1; }
vm_status()   { qm status "$1" 2>/dev/null | awk '{print $2}'; }
vm_name()     { qm config "$1" 2>/dev/null | awk -F': *' '$1=="name"{print $2}'; }
snap_exists() { qm listsnapshot "$1" 2>/dev/null | grep -Eq "(^|[[:space:]])$2([[:space:]]|$)"; }

wait_for_stopped() {
  local vmid="$1" deadline=$(( SECONDS + SHUTDOWN_TIMEOUT ))
  while (( SECONDS < deadline )); do
    [[ "$(vm_status "$vmid")" == "stopped" ]] && return 0
    sleep 3
  done
  return 1
}

stop_vm() {
  local vmid="$1"
  local status
  status="$(vm_status "$vmid")"
  if [[ "$status" == "stopped" ]]; then
    ok "VM ${vmid} is already stopped"
    return 0
  fi

  run "requesting clean shutdown of VM ${vmid}" qm shutdown "$vmid" --forceStop 0 || true
  (( DRY_RUN )) && return 0

  if wait_for_stopped "$vmid"; then
    ok "VM ${vmid} stopped cleanly"
    return 0
  fi

  warn "VM ${vmid} did not shut down within ${SHUTDOWN_TIMEOUT}s - forcing stop"
  warn "A forced stop means the guest filesystem was not flushed. The baseline"
  warn "will be crash-consistent rather than clean. That is usually survivable,"
  warn "but if the guest later complains about a dirty filesystem, this is why."
  qm stop "$vmid"
  wait_for_stopped "$vmid" || die "VM ${vmid} will not stop; refusing to snapshot it"
  ok "VM ${vmid} force-stopped"
}

snapshot_vm() {
  local vmid="$1" role="$2"
  local label
  label="$(vm_name "$vmid" || true)"
  printf '\n%s%s-- VM %s (%s%s)%s\n' "$C_BLD" "$C_BLU" "$vmid" "$role" \
    "${label:+, ${label}}" "$C_RESET"

  if ! vm_exists "$vmid"; then
    die "VM ${vmid} does not exist on this host.
       Expected it from the learner VMID policy (200 + (id-1)*10 + offset).
       Either the learner's VMs were never provisioned, or the policy in
       docs/iac/design.md section 7.3 has drifted from reality."
  fi

  assert_vm_belongs_to_learner "$vmid" "$role"

  if snap_exists "$vmid" "$SNAPSHOT_NAME"; then
    if (( REPLACE )); then
      run "deleting existing snapshot '${SNAPSHOT_NAME}' on ${vmid}" \
        qm delsnapshot "$vmid" "$SNAPSHOT_NAME"
    else
      die "VM ${vmid} already has a snapshot named '${SNAPSHOT_NAME}'.
       This design keeps exactly ONE snapshot per learner VM on purpose: whether
       rolling back to a non-most-recent snapshot on LVM-thin destroys newer
       ones is unverified, and one snapshot makes the question moot.
       Re-run with --replace if you really mean to move the baseline."
    fi
  fi

  stop_vm "$vmid"

  local desc="$DESCRIPTION"
  [[ -n "$desc" ]] || desc="MutaSpace SOC Lab baseline for learner ${LEARNER_PADDED} (${role}), taken $(date -Is)"

  # NOTE: no --vmstate. Disk-only, VM stopped. See the header for why.
  run "snapshotting VM ${vmid} as '${SNAPSHOT_NAME}'" \
    qm snapshot "$vmid" "$SNAPSHOT_NAME" --description "$desc"
  ok "VM ${vmid} snapshot '${SNAPSHOT_NAME}' created"

  if (( START_AFTER )); then
    run "starting VM ${vmid}" qm start "$vmid"
    ok "VM ${vmid} started"
  fi
}

main() {
  local positional=""
  while (( $# )); do
    case "$1" in
      --index)             shift; [[ $# -gt 0 ]] || die "--index needs a value"; LEARNER_INDEX="$1" ;;
      --index=*)           LEARNER_INDEX="${1#*=}" ;;
      --name)              shift; [[ $# -gt 0 ]] || die "--name needs a value"; SNAPSHOT_NAME="$1" ;;
      --name=*)            SNAPSHOT_NAME="${1#*=}" ;;
      --description)       shift; [[ $# -gt 0 ]] || die "--description needs a value"; DESCRIPTION="$1" ;;
      --description=*)     DESCRIPTION="${1#*=}" ;;
      --replace)           REPLACE=1 ;;
      --start)             START_AFTER=1 ;;
      --shutdown-timeout)  shift; [[ $# -gt 0 ]] || die "--shutdown-timeout needs a value"; SHUTDOWN_TIMEOUT="$1" ;;
      --shutdown-timeout=*) SHUTDOWN_TIMEOUT="${1#*=}" ;;
      --dry-run)           DRY_RUN=1 ;;
      -h|--help)           usage; exit 0 ;;
      -*)                  usage >&2; die "unknown option: $1" ;;
      *)                   [[ -z "$positional" ]] || die "unexpected extra argument: $1"; positional="$1" ;;
    esac
    shift
  done

  [[ -n "$positional" ]] || { usage >&2; die "a learner id is required"; }
  [[ "$SHUTDOWN_TIMEOUT" =~ ^[0-9]+$ ]] || die "--shutdown-timeout must be an integer"
  [[ -z "$LEARNER_INDEX" || "$LEARNER_INDEX" =~ ^[0-9]{1,2}$ ]] \
    || die "--index must be a 0-based roster position, got: '${LEARNER_INDEX}'"

  command -v qm >/dev/null 2>&1 \
    || die "qm not found. This script must run ON the Proxmox VE host."
  [[ "${EUID}" -eq 0 ]] || die "must run as root (try: sudo ${SCRIPT_NAME} $*)"

  resolve_learner "$positional"

  printf '%s%sMutaSpace SOC Lab - baseline snapshot%s\n' "$C_BLD" "$C_BLU" "$C_RESET"
  printf '  learner  : %s\n' "$LEARNER_PADDED"
  printf '  snapshot : %s\n' "$SNAPSHOT_NAME"
  printf '  VMs      : %s\n' "${LEARNER_VMIDS[*]}"
  (( DRY_RUN )) && printf '  mode     : DRY RUN - nothing will be changed\n'

  local i
  for i in "${!LEARNER_VMIDS[@]}"; do
    snapshot_vm "${LEARNER_VMIDS[i]}" "${LEARNER_ROLES[i]}"
  done

  printf '\n%sBaseline taken for learner %s.%s\n' "$C_GRN" "$LEARNER_PADDED" "$C_RESET"
  printf 'Reset with:  ./scripts/learner-reset.sh %s\n' "$LEARNER_PADDED"
  if (( ! START_AFTER )); then
    printf 'The VMs were left STOPPED. Start them, or let learner-reset.sh do it.\n'
  fi
}

main "$@"
