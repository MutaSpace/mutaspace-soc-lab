#!/usr/bin/env bash
# =============================================================================
# scripts/learner-reset.sh
#
# WHAT THIS IS
#   Rolls one learner's VMs back to the 'baseline' snapshot taken by
#   scripts/learner-snapshot.sh, starts them, and then repairs the two things a
#   rollback predictably breaks: the guest clock and the Wazuh agent.
#
# WHY THE REPAIR STEPS ARE PART OF THE SCRIPT AND NOT PART OF THE RUNBOOK
#   A rollback is a time machine, and two subsystems in this lab care very much
#   about time and identity:
#
#   1. KERBEROS. 'qm rollback' returns the guest to the clock it had when the
#      snapshot was taken. Roll a Windows client back to a two-week-old baseline
#      and its clock is two weeks behind the domain controller. Kerberos rejects
#      authentication outside the "Maximum tolerance for computer clock
#      synchronization" policy - five minutes by default - so domain logon fails
#      and the lab looks broken for a reason that has nothing to do with the
#      exercise. Wazuh correlation across dc-01, the client and ubuntu-app-01 is
#      also meaningless while their clocks disagree.
#
#   2. WAZUH RE-ENROLMENT. The manager's <auth><force> block ships with
#      disconnected_time = 1h and after_registration_time = 1h. In a classroom
#      where learners revert repeatedly, that silently blocks a same-named agent
#      from re-registering for up to an hour. The template should set both to 0;
#      restarting the agent after rollback is the belt to that braces.
#
#   Leaving either of these for the learner to discover means the learner spends
#   the lab debugging the lab. So this script does them.
#
# WHY IT ROLLS BACK AND THEN STARTS, RATHER THAN USING --start
#   'qm rollback' does NOT restart the VM. It stops it, reverts the disk, and
#   leaves it powered off unless the snapshot carried RAM state or --start was
#   passed. The web UI's rollback button posts no parameters, so a GUI rollback
#   also leaves the guest off - a genuinely surprising behaviour. This script
#   checks the power state afterwards and starts the VM explicitly, which works
#   the same way on every PVE version.
#
# WHAT IT ASSUMES
#   * It runs ON the Proxmox VE host, as root.
#   * The learner's VMs already have a 'baseline' snapshot.
#   * qemu-guest-agent is installed and running in the guests. It is baked into
#     every template in this lab. Without it the post-rollback repairs are
#     skipped with a warning rather than failing the reset.
#   * Learner VMIDs follow the documented policy:
#         vmid = 200 + (roster_index * 10) + role_offset
#         role offsets: win-client = 5, kali = 6
#
# ⚠️ WHERE roster_index COMES FROM, AND WHERE THIS SCRIPT CAN BE WRONG
#   In lab.yaml and tofu/locals.tf the index is the POSITION IN THE ROSTER, not
#   the learner's id. This script runs on the Proxmox host, where lab.yaml does
#   not exist, so it assumes index = id - 1. That is correct for the contiguous
#   roster 01, 02, 03 the lab ships with and wrong as soon as an id is skipped.
#   --index passes the position explicitly, and every VM is checked BY NAME
#   before it is rolled back, so a mismatch stops the script instead of
#   destroying another learner's work. Given what a rollback discards, that
#   check matters more here than it does in learner-snapshot.sh.
#
# DESTRUCTIVE
#   A rollback discards EVERYTHING the learner did since the baseline. The
#   script confirms interactively unless --force is given.
#
# USAGE
#   ./learner-reset.sh --help
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SNAPSHOT_DEFAULT="baseline"

readonly ROLE_NAMES=("win-client" "kali")
readonly ROLE_OFFSETS=(5 6)

readonly LEARNER_ID_MIN=1
# Matches the ceiling tofu/variables.tf enforces on learner_count. Above 20 the
# per-learner address block (host .60 upward, step 2) hits the DHCP pool at .100,
# so a learner beyond 20 can never have been built.
readonly LEARNER_ID_MAX=20

SNAPSHOT_NAME="$SNAPSHOT_DEFAULT"
LEARNER_INDEX=""             # explicit roster position; empty means "id - 1"
FORCE=0
DRY_RUN=0
POST_RESET=1
AGENT_WAIT=180
START_TIMEOUT=120

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
${SCRIPT_NAME} - roll a learner's VMs back to the 'baseline' snapshot

Runs ON the Proxmox VE host, as root. Rolls back, starts, then resynchronises
the guest clock and restarts the Wazuh agent so the learner does not inherit a
broken Kerberos logon and a silently missing agent.

DESTRUCTIVE: everything the learner did since the baseline is discarded.

USAGE
  sudo ./${SCRIPT_NAME} <learner-id> [options]

ARGUMENTS
  <learner-id>   ${LEARNER_ID_MIN}..${LEARNER_ID_MAX}, with or without a leading zero (01, 1, 12).

OPTIONS
  --index <n>        The learner's 0-based POSITION IN THE ROSTER in lab.yaml,
                     which is what the VMID is actually derived from. Defaults
                     to (learner-id - 1), correct only while the roster is a
                     contiguous 01, 02, 03...
  --force            Do not ask for confirmation. Intended for automation, not
                     for a human at a keyboard in a live classroom.
  --name <snap>      Snapshot to roll back to. Default: ${SNAPSHOT_DEFAULT}
  --no-post-reset    Skip the clock resync and Wazuh agent restart. Only useful
                     when you are deliberately demonstrating what breaks.
  --agent-wait <s>   Seconds to wait for the guest agent after boot.
                     Default: ${AGENT_WAIT}
  --dry-run          Print every action without performing it.
  -h, --help         Show this help and exit.

EXAMPLES
  sudo ./${SCRIPT_NAME} 01
  sudo ./${SCRIPT_NAME} 02 --force

SEE ALSO
  scripts/learner-snapshot.sh   takes the baseline this rolls back to
  docs/iac/design.md            sections 7.4 (Wazuh re-enrolment) and 7.5 (time)
EOF
}

# -----------------------------------------------------------------------------
# Learner id -> VMIDs. Kept identical to learner-snapshot.sh on purpose: the two
# scripts are a pair and must agree about which VMIDs a learner owns.
# -----------------------------------------------------------------------------
LEARNER_ID=""
LEARNER_PADDED=""
declare -a LEARNER_VMIDS=()
declare -a LEARNER_ROLES=()

resolve_learner() {
  local raw="$1"
  [[ "$raw" =~ ^[0-9]{1,2}$ ]] || die "learner id must be 1-2 digits, got: '${raw}'"
  LEARNER_ID="$((10#$raw))"     # 10# forces base 10 so '08' is not bad octal
  (( LEARNER_ID >= LEARNER_ID_MIN && LEARNER_ID <= LEARNER_ID_MAX )) \
    || die "learner id ${LEARNER_ID} is outside ${LEARNER_ID_MIN}..${LEARNER_ID_MAX}"

  LEARNER_PADDED="$(printf '%02d' "$LEARNER_ID")"

  # Roster position, not the id. See the header for why those differ and when.
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

# Refuse to roll back a VM that is not the one we think it is.
#
# OpenTofu names these '<role>-l<id>' (tofu/locals.tf). If the VM at the computed
# VMID has a different name, the roster-index assumption has broken and a
# rollback would destroy a different learner's work - the single most expensive
# mistake this pair of scripts can make.
assert_vm_belongs_to_learner() {
  local vmid="$1" role="$2"
  local expected="${role}-l${LEARNER_PADDED}"
  local actual
  actual="$(vm_name "$vmid" || true)"

  [[ -z "$actual" || "$actual" == "$expected" ]] || die "VM ${vmid} is named '${actual}', but learner ${LEARNER_PADDED}'s ${role} should be '${expected}'.
       The VMID was computed from the roster position, and that assumption has
       broken - most likely a learner was removed from lab.yaml or an id was
       skipped, so positions shifted. NOTHING HAS BEEN ROLLED BACK.
       Re-run with the correct 0-based roster position:
         sudo ${SCRIPT_NAME} ${LEARNER_PADDED} --index <n>"
}

vm_exists()   { qm config "$1" >/dev/null 2>&1; }
vm_status()   { qm status "$1" 2>/dev/null | awk '{print $2}'; }
vm_name()     { qm config "$1" 2>/dev/null | awk -F': *' '$1=="name"{print $2}'; }
vm_ostype()   { qm config "$1" 2>/dev/null | awk -F': *' '$1=="ostype"{print $2}'; }
snap_exists() { qm listsnapshot "$1" 2>/dev/null | grep -Eq "(^|[[:space:]])$2([[:space:]]|$)"; }

is_windows_guest() {
  case "$(vm_ostype "$1")" in
    win*|wvista|wxp|w2k*) return 0 ;;
    *)                    return 1 ;;
  esac
}

wait_for_running() {
  local vmid="$1" deadline=$(( SECONDS + START_TIMEOUT ))
  while (( SECONDS < deadline )); do
    [[ "$(vm_status "$vmid")" == "running" ]] && return 0
    sleep 2
  done
  return 1
}

wait_for_agent() {
  local vmid="$1" deadline=$(( SECONDS + AGENT_WAIT ))
  while (( SECONDS < deadline )); do
    if qm guest cmd "$vmid" ping >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  return 1
}

# guest_exec <vmid> <label> <command...>
# Best-effort: a failure here is reported but does not fail the reset. The VM is
# already back and usable; a failed resync is a warning, not a rollback failure.
guest_exec() {
  local vmid="$1" label="$2"; shift 2
  if (( DRY_RUN )); then
    printf '%s[ dry ]%s %s on VM %s\n         $ qm guest exec %s -- %s\n' \
      "$C_YEL" "$C_RESET" "$label" "$vmid" "$vmid" "$*"
    return 0
  fi
  if qm guest exec "$vmid" --timeout 120 -- "$@" >/dev/null 2>&1; then
    ok "${label} on VM ${vmid}"
  else
    warn "${label} FAILED on VM ${vmid} (guest agent refused or the command is absent)"
    warn "  do it by hand in the guest: $*"
  fi
}

post_reset_repairs() {
  local vmid="$1" role="$2"

  if ! wait_for_agent "$vmid"; then
    warn "guest agent on VM ${vmid} did not answer within ${AGENT_WAIT}s."
    warn "Skipping the clock resync and the Wazuh agent restart for this VM."
    warn "Tell the learner to run these by hand once the guest is up:"
    if is_windows_guest "$vmid"; then
      warn "  w32tm /resync /force"
      warn "  Restart-Service -Name WazuhSvc"
    else
      warn "  sudo timedatectl set-ntp true && sudo chronyc makestep"
      warn "  sudo systemctl restart wazuh-agent"
    fi
    return 0
  fi
  ok "guest agent on VM ${vmid} is responding"

  if is_windows_guest "$vmid"; then
    # The Windows Time service is set to manual/trigger start on many images and
    # will not be running after a cold boot, so start it before resyncing.
    guest_exec "$vmid" "starting the Windows Time service" \
      sc.exe start w32time
    guest_exec "$vmid" "forcing a time resync (Kerberos needs this)" \
      w32tm.exe /resync /force
    guest_exec "$vmid" "restarting the Wazuh agent" \
      powershell.exe -NoProfile -NonInteractive -Command \
      "Restart-Service -Name WazuhSvc -ErrorAction Stop"
  else
    guest_exec "$vmid" "forcing a time resync" \
      /bin/sh -c 'timedatectl set-ntp true 2>/dev/null; chronyc makestep 2>/dev/null || systemctl restart systemd-timesyncd'
    guest_exec "$vmid" "restarting the Wazuh agent" \
      /bin/sh -c 'systemctl restart wazuh-agent'
  fi
}

reset_vm() {
  local vmid="$1" role="$2"
  local label
  label="$(vm_name "$vmid" || true)"
  printf '\n%s%s-- VM %s (%s%s)%s\n' "$C_BLD" "$C_BLU" "$vmid" "$role" \
    "${label:+, ${label}}" "$C_RESET"

  vm_exists "$vmid" || die "VM ${vmid} does not exist on this host"
  assert_vm_belongs_to_learner "$vmid" "$role"
  snap_exists "$vmid" "$SNAPSHOT_NAME" \
    || die "VM ${vmid} has no snapshot named '${SNAPSHOT_NAME}'.
       Take one first:  ./scripts/learner-snapshot.sh ${LEARNER_PADDED}"

  run "rolling VM ${vmid} back to '${SNAPSHOT_NAME}'" \
    qm rollback "$vmid" "$SNAPSHOT_NAME"
  ok "VM ${vmid} rolled back"

  # qm rollback leaves the VM STOPPED unless the snapshot held RAM state. Start
  # it explicitly rather than relying on --start, which is not available on
  # every PVE version and is silently ignored by the web UI's rollback button.
  if (( DRY_RUN )); then
    printf '%s[ dry ]%s start VM %s if it is not already running\n' "$C_YEL" "$C_RESET" "$vmid"
  elif [[ "$(vm_status "$vmid")" == "running" ]]; then
    ok "VM ${vmid} is already running (the snapshot carried RAM state)"
  else
    run "starting VM ${vmid}" qm start "$vmid"
    if wait_for_running "$vmid"; then
      ok "VM ${vmid} is running"
    else
      warn "VM ${vmid} did not reach 'running' within ${START_TIMEOUT}s"
      return 0
    fi
  fi

  (( POST_RESET )) && post_reset_repairs "$vmid" "$role"
  return 0
}

confirm_destruction() {
  cat <<EOF

${C_YEL}${C_BLD}  THIS DISCARDS THE LEARNER'S WORK${C_RESET}

  Rolling back to '${SNAPSHOT_NAME}' throws away every change made inside these
  VMs since the baseline was taken: files, installed tools, exercise progress,
  and anything not saved off the VM.

  learner : ${LEARNER_PADDED}
  VMs     : ${LEARNER_VMIDS[*]}

EOF
  local reply=""
  read -r -p "  Type the learner id (${LEARNER_PADDED}) to confirm: " reply || true
  [[ "$reply" == "$LEARNER_PADDED" || "$reply" == "$LEARNER_ID" ]] \
    || die "confirmation did not match. Nothing was changed."
}

print_post_reset_notes() {
  cat <<EOF

${C_BLD}Post-reset notes${C_RESET}

  THE GUEST CLOCK WAS STALE. A rollback restores the clock the guest had when
  the baseline was taken. This script already forced a resync, but the effect
  is not always instant:

    * Kerberos rejects authentication outside a 5-minute skew by default, so a
      domain logon attempted in the first few seconds after boot can still fail.
      If it does, wait, then on the client:  klist purge && w32tm /resync /force
    * fw-01 is the lab's NTP server on 10.10.10.1 and dc-01 (the PDC emulator)
      syncs from it. Everything else inherits NT5DS from the domain hierarchy.

  THE WAZUH AGENT WAS RESTARTED. Without that, a same-named agent can be blocked
  from re-registering for up to an hour: the manager's <auth><force> block
  defaults to disconnected_time = 1h and after_registration_time = 1h. Both
  should be 0 in this lab's manager configuration - if agents still take an hour
  to come back, that is the setting to check, not the agent.

  VERIFY on the manager:
    /var/ossec/bin/agent_control -l | grep -i 'l${LEARNER_PADDED}'

  VERIFY on a Windows client:
    klist purge && whoami /groups
EOF
}

main() {
  local positional=""
  while (( $# )); do
    case "$1" in
      --index)          shift; [[ $# -gt 0 ]] || die "--index needs a value"; LEARNER_INDEX="$1" ;;
      --index=*)        LEARNER_INDEX="${1#*=}" ;;
      --force)          FORCE=1 ;;
      --name)           shift; [[ $# -gt 0 ]] || die "--name needs a value"; SNAPSHOT_NAME="$1" ;;
      --name=*)         SNAPSHOT_NAME="${1#*=}" ;;
      --no-post-reset)  POST_RESET=0 ;;
      --agent-wait)     shift; [[ $# -gt 0 ]] || die "--agent-wait needs a value"; AGENT_WAIT="$1" ;;
      --agent-wait=*)   AGENT_WAIT="${1#*=}" ;;
      --dry-run)        DRY_RUN=1 ;;
      -h|--help)        usage; exit 0 ;;
      -*)               usage >&2; die "unknown option: $1" ;;
      *)                [[ -z "$positional" ]] || die "unexpected extra argument: $1"; positional="$1" ;;
    esac
    shift
  done

  [[ -n "$positional" ]] || { usage >&2; die "a learner id is required"; }
  [[ "$AGENT_WAIT" =~ ^[0-9]+$ ]] || die "--agent-wait must be an integer"
  [[ -z "$LEARNER_INDEX" || "$LEARNER_INDEX" =~ ^[0-9]{1,2}$ ]] \
    || die "--index must be a 0-based roster position, got: '${LEARNER_INDEX}'"

  command -v qm >/dev/null 2>&1 \
    || die "qm not found. This script must run ON the Proxmox VE host."
  [[ "${EUID}" -eq 0 ]] || die "must run as root (try: sudo ${SCRIPT_NAME} $*)"

  resolve_learner "$positional"

  printf '%s%sMutaSpace SOC Lab - learner reset%s\n' "$C_BLD" "$C_BLU" "$C_RESET"
  printf '  learner  : %s\n' "$LEARNER_PADDED"
  printf '  snapshot : %s\n' "$SNAPSHOT_NAME"
  printf '  VMs      : %s\n' "${LEARNER_VMIDS[*]}"
  (( DRY_RUN )) && printf '  mode     : DRY RUN - nothing will be changed\n'

  if (( ! FORCE )) && (( ! DRY_RUN )); then
    confirm_destruction
  fi

  local i
  for i in "${!LEARNER_VMIDS[@]}"; do
    reset_vm "${LEARNER_VMIDS[i]}" "${LEARNER_ROLES[i]}"
  done

  printf '\n%sLearner %s reset.%s\n' "$C_GRN" "$LEARNER_PADDED" "$C_RESET"
  (( POST_RESET )) && print_post_reset_notes
}

main "$@"
