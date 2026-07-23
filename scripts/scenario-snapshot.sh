#!/usr/bin/env bash
# =============================================================================
# scripts/scenario-snapshot.sh
#
# WHAT THIS IS
#   Takes the 'scenario-baseline' snapshot of the two incident-scenario TARGET
#   VMs - ubuntu-app-01 (106) and kali-01 (108). The instructor runs this ONCE,
#   DELIBERATELY, AFTER the scenario instrumentation is proven (nginx access-log
#   localfile present, kali attack tooling installed, disk grow complete).
#   scripts/scenario-reset.sh then rolls those two VMs back to it between runs.
#
# WHY ONLY 106 AND 108, AND WHY wazuh-01 IS NEVER IN THE SET
#   The whole point of the scenario reset is EVIDENCE RETENTION. A student runs
#   an attack, it fires a Wazuh rule, and the alert lands in the indexer on
#   wazuh-01 (104). Resetting the lab for the next student must roll back the
#   attack surface - the target and the attacker - WITHOUT touching the SIEM, so
#   the fired alerts survive for grading. Therefore this script's target set is a
#   FIXED, TWO-ENTRY list: 106 and 108. wazuh-01 (104), dc-01, fw-01 and the
#   jumpbox are deliberately absent and must never be snapshotted or rolled back
#   by this pair of scripts.
#
# WHY THE SNAPSHOT NAME IS 'scenario-baseline' AND NOT 'baseline'
#   The learner lifecycle (scripts/learner-snapshot.sh) already uses 'baseline'
#   on the per-learner VMs. These are different VMs and a different lifecycle;
#   the distinct name keeps the two from ever being confused and lets a target
#   that happens to carry both kinds of snapshot keep them separate.
#
# WHY THE VM IS STOPPED FIRST, AND WHY THERE IS NO --vmstate
#   A snapshot of a RUNNING VM with RAM state writes a multi-gigabyte vmstate
#   file to 'local', the root LV, and rolling back to a RAM snapshot RESUMES the
#   guest mid-flight instead of cold-booting it. "Reset" here must mean "boot
#   from a known-good disk", not "resume a process from last week". So the VM is
#   shut down first and the snapshot is disk-only.
#
# WHY EXACTLY ONE SNAPSHOT PER VM
#   Whether rolling back to a non-most-recent snapshot on LVM-thin silently
#   deletes newer snapshots is not something this lab has verified. One snapshot
#   named 'scenario-baseline' sidesteps the question. That is why --replace
#   exists and why this script refuses to add a second snapshot by default.
#
# OPTIONAL: FULL BASELINE / CLEAR SIEM HISTORY (manual, NOT automated)
#   The automated path never clears the SIEM - that is the point. Two deliberate,
#   MANUAL operations exist for when an instructor really does want a clean slate
#   between cohorts. Neither is wired into `task`; do them by hand, knowingly.
#
#   A) Re-take the scenario baseline (targets only). After changing the
#      instrumented baseline (new tooling, a fixed localfile), move the snapshot:
#          sudo ./scenario-snapshot.sh --replace
#      This rolls the 'scenario-baseline' forward on 106 and 108. It does NOT
#      touch wazuh-01 or clear any alert - only the disk the next reset restores.
#
#   B) Clear the SIEM's alert history (wazuh-01, evidence-destroying). This is
#      the ONLY way old alerts leave the indexer, and it is intentionally not a
#      script - it throws away exactly the grading evidence the reset preserves.
#      Do it only between cohorts, ON wazuh-01, understanding it is irreversible,
#      e.g. deleting the wazuh-alerts indices via the indexer API:
#          curl -k -u <admin> -XDELETE 'https://127.0.0.1:9200/wazuh-alerts-*'
#      (Wazuh recreates the write index on the next event.) Confirm the retention
#      window with the instructor first; there is no undo.
#
# WHAT IT ASSUMES
#   * It runs ON the Proxmox VE host, as root. 'qm' is a host-local tool.
#   * The two target VMs already exist. This script never creates or clones.
#
# THE NAME GUARD - WHY A STATIC role->name MAP
#   Unlike the learner scripts, whose VMIDs are computed from a roster position
#   and can drift, these two VMIDs are fixed by lab.yaml (106, 108). The risk is
#   not arithmetic drift but a mis-numbered EDIT to this script pointing it at
#   the wrong VM - above all at 104. So before either VM is touched it is checked
#   BY NAME against a static map: 106 MUST be 'ubuntu-app-01' and 108 MUST be
#   'kali-01'. A mismatch is a hard error, so the worst case is a refusal to act,
#   never a snapshot taken of the SIEM or another machine.
#
# USAGE
#   ./scenario-snapshot.sh --help
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SNAPSHOT_DEFAULT="scenario-baseline"

# The fixed target set. These are the ONLY VMs this script may ever touch.
# Each VMID is paired with the name it MUST have (the name guard below). This is
# a static map on purpose - see the header. wazuh-01 (104) is deliberately absent.
readonly TARGET_VMIDS=(106 108)
readonly TARGET_NAMES=("ubuntu-app-01" "kali-01")
readonly TARGET_ROLES=("target" "attacker")

SNAPSHOT_NAME="$SNAPSHOT_DEFAULT"
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
${SCRIPT_NAME} - take the 'scenario-baseline' snapshot of the scenario targets

Runs ON the Proxmox VE host, as root. Shuts down ubuntu-app-01 (106) and
kali-01 (108), takes one disk-only snapshot per VM, and leaves them stopped.
wazuh-01 (104) is NEVER touched - that is how the fired alerts survive a reset.

Take this ONCE, deliberately, AFTER the scenario instrumentation is proven.

USAGE
  sudo ./${SCRIPT_NAME} [options]

OPTIONS
  --name <snap>          Snapshot name. Default: ${SNAPSHOT_DEFAULT}
                         Change this only if you know why. scenario-reset.sh
                         defaults to the same name.
  --description <text>   Snapshot description. Default: an auto-generated one
                         naming the target and the date.
  --replace              Delete an existing snapshot of the same name first.
                         Without this, an existing snapshot is a hard error -
                         accumulating snapshots is what this design avoids.
  --start                Start the VMs again after snapshotting. Off by default:
                         the baseline is taken cold and reset starts them.
  --shutdown-timeout <s> Seconds to wait for a clean guest shutdown before
                         giving up. Default: ${SHUTDOWN_TIMEOUT}
  --dry-run              Print every action without performing it.
  -h, --help             Show this help and exit.

EXAMPLES
  sudo ./${SCRIPT_NAME}
  sudo ./${SCRIPT_NAME} --replace --description "instrumented baseline, module 2"

TARGET SET (fixed)
  106 -> ubuntu-app-01 (the scenario target)
  108 -> kali-01       (the attacker)

  Every VM is verified by name before it is touched: 106 must be
  'ubuntu-app-01' and 108 must be 'kali-01', or the script refuses to act.
  wazuh-01 (104) is not in the set and is never snapshotted here.

SEE ALSO
  scripts/scenario-reset.sh   the other half of this pair
  docs/scenarios/README.md    the evidence-retention model
EOF
}

vm_exists()   { qm config "$1" >/dev/null 2>&1; }
vm_status()   { qm status "$1" 2>/dev/null | awk '{print $2}'; }
vm_name()     { qm config "$1" 2>/dev/null | awk -F': *' '$1=="name"{print $2}'; }
snap_exists() { qm listsnapshot "$1" 2>/dev/null | grep -Eq "(^|[[:space:]])$2([[:space:]]|$)"; }

# Refuse to touch a VM that is not the one we think it is.
#
# The two VMIDs are fixed by lab.yaml, so the failure mode guarded against is a
# mis-numbered edit to this script - above all one pointing at wazuh-01 (104).
# If the VM at the target VMID has a different name, that has happened and
# continuing could snapshot the SIEM or another machine.
assert_vm_is_target() {
  local vmid="$1" expected="$2"
  local actual
  actual="$(vm_name "$vmid" || true)"

  [[ "$actual" == "$expected" ]] || die "VM ${vmid} is named '${actual:-<none>}', but the scenario target at ${vmid} must be '${expected}'.
       The scenario target set is a FIXED map (106->ubuntu-app-01, 108->kali-01)
       and this VM does not match it - most likely this script was edited to the
       wrong VMID. Nothing has been changed. Refusing to snapshot the wrong VM
       (this guard is what keeps the SIEM, wazuh-01/104, out of the target set)."
}

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
  local vmid="$1" role="$2" expected="$3"
  local label
  label="$(vm_name "$vmid" || true)"
  printf '\n%s%s-- VM %s (%s%s)%s\n' "$C_BLD" "$C_BLU" "$vmid" "$role" \
    "${label:+, ${label}}" "$C_RESET"

  if ! vm_exists "$vmid"; then
    die "VM ${vmid} does not exist on this host.
       Expected the scenario target '${expected}' at ${vmid} (from lab.yaml).
       Either the lab was never deployed or the VMID has drifted from lab.yaml."
  fi

  assert_vm_is_target "$vmid" "$expected"

  if snap_exists "$vmid" "$SNAPSHOT_NAME"; then
    if (( REPLACE )); then
      run "deleting existing snapshot '${SNAPSHOT_NAME}' on ${vmid}" \
        qm delsnapshot "$vmid" "$SNAPSHOT_NAME"
    else
      die "VM ${vmid} already has a snapshot named '${SNAPSHOT_NAME}'.
       This design keeps exactly ONE scenario snapshot per target on purpose:
       whether rolling back to a non-most-recent snapshot on LVM-thin destroys
       newer ones is unverified, and one snapshot makes the question moot.
       Re-run with --replace if you really mean to move the baseline."
    fi
  fi

  stop_vm "$vmid"

  local desc="$DESCRIPTION"
  [[ -n "$desc" ]] || desc="MutaSpace SOC Lab scenario-baseline for ${expected} (${role}), taken $(date -Is)"

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
  while (( $# )); do
    case "$1" in
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
      *)                   usage >&2; die "unexpected argument: $1 (this script has a fixed target set and takes no positional args)" ;;
    esac
    shift
  done

  [[ "$SHUTDOWN_TIMEOUT" =~ ^[0-9]+$ ]] || die "--shutdown-timeout must be an integer"

  command -v qm >/dev/null 2>&1 \
    || die "qm not found. This script must run ON the Proxmox VE host."
  [[ "${EUID}" -eq 0 ]] || die "must run as root (try: sudo ${SCRIPT_NAME} $*)"

  printf '%s%sMutaSpace SOC Lab - scenario-baseline snapshot%s\n' "$C_BLD" "$C_BLU" "$C_RESET"
  printf '  snapshot : %s\n' "$SNAPSHOT_NAME"
  printf '  targets  : %s (106=ubuntu-app-01, 108=kali-01)\n' "${TARGET_VMIDS[*]}"
  printf '  excluded : wazuh-01 (104) is never touched - evidence must survive\n'
  (( DRY_RUN )) && printf '  mode     : DRY RUN - nothing will be changed\n'

  local i
  for i in "${!TARGET_VMIDS[@]}"; do
    snapshot_vm "${TARGET_VMIDS[i]}" "${TARGET_ROLES[i]}" "${TARGET_NAMES[i]}"
  done

  printf '\n%sscenario-baseline taken for the scenario targets.%s\n' "$C_GRN" "$C_RESET"
  printf 'Reset with:  ./scripts/scenario-reset.sh\n'
  if (( ! START_AFTER )); then
    printf 'The VMs were left STOPPED. Start them, or let scenario-reset.sh do it.\n'
  fi
}

main "$@"
