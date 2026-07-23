#!/usr/bin/env bash
# =============================================================================
# scripts/scenario-reset.sh
#
# WHAT THIS IS
#   Rolls the two incident-scenario TARGET VMs - ubuntu-app-01 (106) and
#   kali-01 (108) - back to the 'scenario-baseline' snapshot taken by
#   scripts/scenario-snapshot.sh, starts them, repairs the guest clock and the
#   Wazuh agent, and then MACHINE-PROVES the reset landed clean.
#
# WHY wazuh-01 (104) IS NEVER TOUCHED - THIS IS THE WHOLE POINT
#   A student runs an attack; it fires a Wazuh rule; the alert is durable in the
#   indexer on wazuh-01. Resetting for the next student rolls back only the
#   attack surface - the target (106) and the attacker (108) - so the fired
#   alerts SURVIVE on wazuh-01 for grading. wazuh-01 (104), dc-01, fw-01 and the
#   jumpbox are deliberately outside this script's target set and are never
#   stopped, rolled back or otherwise altered here. The target set is a FIXED,
#   two-entry list; there is no flag that can widen it.
#
# WHY THE REPAIR STEPS ARE PART OF THE SCRIPT AND NOT PART OF THE RUNBOOK
#   A rollback is a time machine, and two subsystems care about time and
#   identity:
#     1. TIME. 'qm rollback' returns the guest to the clock it had when the
#        snapshot was taken. A stale clock breaks Wazuh correlation across the
#        target and the manager, and any Kerberos-adjacent auth. So the script
#        forces 'timedatectl set-ntp true; chronyc makestep'.
#     2. WAZUH RE-ENROLMENT. A same-named agent can be blocked from
#        re-registering after a revert; restarting wazuh-agent after rollback is
#        the belt to the template's braces (disconnected_time=0).
#   Leaving these for the student means the student debugs the lab. So the
#   script does them, then CHECKS they took.
#
# WHY IT ROLLS BACK AND THEN STARTS, RATHER THAN USING --start
#   'qm rollback' does NOT restart the VM unless the snapshot carried RAM state.
#   The scenario-baseline is disk-only, so the script checks the power state
#   afterwards and starts the VM explicitly - which behaves the same on every
#   PVE version and matches what the web UI's rollback button silently fails to
#   do.
#
# RESET-CORRECTNESS - WHAT "PROVEN CLEAN" MEANS HERE
#   After the rollback+repair on each target the script asserts:
#     * the VM is running,
#     * its name still matches the target map (the guard, re-checked post-roll),
#     * the Wazuh agent is keyed (client.keys non-empty) and its service active,
#     * the guest clock reports NTP-synchronised.
#   And it states the EVIDENCE-RETENTION invariant: the attack-window artifacts
#   (auth.log / nginx access.log lines) went away WITH the rolled-back disk,
#   while the alerts those artifacts produced remain queryable on wazuh-01. That
#   split - clean target, preserved SIEM - is confirmed with `scenario:verify`
#   against the historical window, off this script.
#
# WHAT IT ASSUMES
#   * It runs ON the Proxmox VE host, as root.
#   * Both targets already have a 'scenario-baseline' snapshot.
#   * qemu-guest-agent is running in the guests (baked into every template). If
#     it does not answer, the repairs and checks are skipped with a warning
#     rather than failing the reset - the VM is already back and usable.
#
# THE NAME GUARD - WHY A STATIC role->name MAP
#   The two VMIDs are fixed by lab.yaml (106, 108), so the risk is not roster
#   drift but a mis-numbered EDIT to this script - above all one pointing a
#   destructive rollback at wazuh-01 (104). Before either VM is touched it is
#   checked BY NAME: 106 MUST be 'ubuntu-app-01', 108 MUST be 'kali-01'. A
#   mismatch stops the script; NOTHING is rolled back.
#
# DESTRUCTIVE
#   A rollback discards everything on the targets' disks since the baseline. The
#   script confirms interactively unless --force is given. (It never discards
#   anything on wazuh-01 - see above.)
#
# USAGE
#   ./scenario-reset.sh --help
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SNAPSHOT_DEFAULT="scenario-baseline"

# The fixed target set. These are the ONLY VMs this script may ever roll back.
# Each VMID is paired with the name it MUST have (the name guard below).
# wazuh-01 (104) is deliberately absent - the evidence on it must survive.
readonly TARGET_VMIDS=(106 108)
readonly TARGET_NAMES=("ubuntu-app-01" "kali-01")
readonly TARGET_ROLES=("target" "attacker")

SNAPSHOT_NAME="$SNAPSHOT_DEFAULT"
SCENARIO_ID=""               # optional, for messaging only; does NOT change the set
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
${SCRIPT_NAME} - roll the scenario targets back to 'scenario-baseline'

Runs ON the Proxmox VE host, as root. Rolls back ubuntu-app-01 (106) and
kali-01 (108), starts them, resynchronises the clock, restarts the Wazuh agent,
then checks the reset landed clean. wazuh-01 (104) is NEVER touched, so the
alerts a student fired stay queryable in the indexer for grading.

DESTRUCTIVE: everything on the targets' disks since the baseline is discarded.

USAGE
  sudo ./${SCRIPT_NAME} [scenario-id] [options]

ARGUMENTS
  [scenario-id]      Optional. Used only in messages (e.g. 'ssh-bruteforce').
                     It does NOT change the target set - reset is always 106+108.

OPTIONS
  --force            Do not ask for confirmation. Intended for automation.
  --name <snap>      Snapshot to roll back to. Default: ${SNAPSHOT_DEFAULT}
  --no-post-reset    Skip the clock resync, agent restart and correctness
                     checks. Only useful when deliberately demonstrating what
                     breaks.
  --agent-wait <s>   Seconds to wait for the guest agent after boot.
                     Default: ${AGENT_WAIT}
  --dry-run          Print every action without performing it.
  -h, --help         Show this help and exit.

EXAMPLES
  sudo ./${SCRIPT_NAME}
  sudo ./${SCRIPT_NAME} ssh-bruteforce --force

TARGET SET (fixed)
  106 -> ubuntu-app-01 (the scenario target)
  108 -> kali-01       (the attacker)
  104 -> wazuh-01      NEVER touched - evidence retention

SEE ALSO
  scripts/scenario-snapshot.sh   takes the baseline this rolls back to
  docs/scenarios/README.md       the evidence-retention model and full reset
EOF
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

# Refuse to roll back a VM that is not the one we think it is.
#
# The VMIDs are fixed by lab.yaml, so the failure mode guarded against is a
# mis-numbered edit pointing this destructive rollback at the wrong VM - above
# all wazuh-01 (104). A name mismatch is a hard stop with nothing rolled back.
assert_vm_is_target() {
  local vmid="$1" expected="$2"
  local actual
  actual="$(vm_name "$vmid" || true)"

  [[ "$actual" == "$expected" ]] || die "VM ${vmid} is named '${actual:-<none>}', but the scenario target at ${vmid} must be '${expected}'.
       The scenario target set is a FIXED map (106->ubuntu-app-01, 108->kali-01)
       and this VM does not match it - most likely this script was edited to the
       wrong VMID. NOTHING HAS BEEN ROLLED BACK. This guard is what keeps a
       rollback off the SIEM (wazuh-01/104) and off any other machine."
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

# guest_probe <vmid> <label> <sentinel> <command...>
# Runs a check inside the guest that prints <sentinel> on success, and reports
# ok/warn on whether the sentinel came back. Best-effort like guest_exec: a
# failed probe is a warning, never a rollback failure. Reads the sentinel out of
# the guest agent's captured stdout so it needs no JSON-exitcode parsing.
guest_probe() {
  local vmid="$1" label="$2" sentinel="$3"; shift 3
  if (( DRY_RUN )); then
    printf '%s[ dry ]%s check: %s on VM %s\n         $ qm guest exec %s -- %s\n' \
      "$C_YEL" "$C_RESET" "$label" "$vmid" "$vmid" "$*"
    return 0
  fi
  local out
  out="$(qm guest exec "$vmid" --timeout 60 -- "$@" 2>/dev/null || true)"
  if grep -q "$sentinel" <<<"$out"; then
    ok "${label} on VM ${vmid}"
  else
    warn "${label} could NOT be confirmed on VM ${vmid} - check by hand"
  fi
}

post_reset_repairs() {
  local vmid="$1" role="$2"

  if ! wait_for_agent "$vmid"; then
    warn "guest agent on VM ${vmid} did not answer within ${AGENT_WAIT}s."
    warn "Skipping the clock resync, the Wazuh agent restart and the reset-"
    warn "correctness checks for this VM. Run these by hand once it is up:"
    warn "  sudo timedatectl set-ntp true && sudo chronyc makestep"
    warn "  sudo systemctl restart wazuh-agent"
    return 0
  fi
  ok "guest agent on VM ${vmid} is responding"

  # Both scenario targets are Linux (ubuntu-app-01, kali-01). The Windows branch
  # is kept only so a mis-typed --name onto some other guest still does the sane
  # thing rather than running Linux commands on Windows.
  if is_windows_guest "$vmid"; then
    guest_exec "$vmid" "starting the Windows Time service" \
      sc.exe start w32time
    guest_exec "$vmid" "forcing a time resync" \
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

# reset_correctness_checks <vmid> <role> <expected-name>
# Machine-proves the reset landed clean on one target. Everything here is
# best-effort (warn, never die): the rollback itself already succeeded, and
# these confirm it is USABLE, not whether it happened.
reset_correctness_checks() {
  local vmid="$1" role="$2" expected="$3"

  printf '  %sreset-correctness (%s):%s\n' "$C_BLD" "$expected" "$C_RESET"

  # 1. Power state.
  if (( DRY_RUN )); then
    printf '%s[ dry ]%s check VM %s is running\n' "$C_YEL" "$C_RESET" "$vmid"
  elif [[ "$(vm_status "$vmid")" == "running" ]]; then
    ok "VM ${vmid} is running"
  else
    warn "VM ${vmid} is NOT running after reset"
  fi

  # 2. Name-guard, re-checked AFTER the rollback (the disk came from the
  #    snapshot; confirm it still is who we think it is).
  if (( DRY_RUN )); then
    printf '%s[ dry ]%s check VM %s is still named %s\n' "$C_YEL" "$C_RESET" "$vmid" "$expected"
  elif [[ "$(vm_name "$vmid" || true)" == "$expected" ]]; then
    ok "VM ${vmid} name still matches '${expected}'"
  else
    warn "VM ${vmid} name no longer matches '${expected}' after rollback"
  fi

  # The remaining checks need the guest agent. Windows targets are out of scope
  # for the scenario set, so the probes are Linux-only.
  if is_windows_guest "$vmid"; then
    return 0
  fi

  # 3. Wazuh agent re-connected: client.keys non-empty AND the service active.
  guest_probe "$vmid" "Wazuh agent is keyed (client.keys non-empty)" AGENT_KEYED \
    /bin/sh -c '[ -s /var/ossec/etc/client.keys ] && echo AGENT_KEYED'
  guest_probe "$vmid" "wazuh-agent service is active" AGENT_ACTIVE \
    /bin/sh -c 'systemctl is-active wazuh-agent 2>/dev/null | grep -qx active && echo AGENT_ACTIVE'

  # 4. Clock synchronised (Kerberos/correlation depend on it).
  guest_probe "$vmid" "guest clock reports NTP-synchronised" CLOCK_OK \
    /bin/sh -c 'timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qx yes && echo CLOCK_OK'
}

reset_vm() {
  local vmid="$1" role="$2" expected="$3"
  local label
  label="$(vm_name "$vmid" || true)"
  printf '\n%s%s-- VM %s (%s%s)%s\n' "$C_BLD" "$C_BLU" "$vmid" "$role" \
    "${label:+, ${label}}" "$C_RESET"

  vm_exists "$vmid" || die "VM ${vmid} does not exist on this host"
  assert_vm_is_target "$vmid" "$expected"
  snap_exists "$vmid" "$SNAPSHOT_NAME" \
    || die "VM ${vmid} has no snapshot named '${SNAPSHOT_NAME}'.
       Take one first:  ./scripts/scenario-snapshot.sh"

  run "rolling VM ${vmid} back to '${SNAPSHOT_NAME}'" \
    qm rollback "$vmid" "$SNAPSHOT_NAME"
  ok "VM ${vmid} rolled back"

  # qm rollback leaves the VM STOPPED unless the snapshot held RAM state (this
  # one is disk-only). Start it explicitly rather than relying on --start.
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

  if (( POST_RESET )); then
    post_reset_repairs "$vmid" "$role"
    reset_correctness_checks "$vmid" "$role" "$expected"
  fi
  return 0
}

confirm_destruction() {
  cat <<EOF

${C_YEL}${C_BLD}  THIS DISCARDS THE TARGETS' STATE${C_RESET}

  Rolling back to '${SNAPSHOT_NAME}' throws away every change on the disks of
  ubuntu-app-01 (106) and kali-01 (108) since the baseline: attack artifacts,
  files, and exercise progress on those two VMs.

  It does NOT touch wazuh-01 (104) - the alerts already fired stay in the
  indexer for grading. That preservation is the point.

  scenario : ${SCENARIO_ID:-<none>}
  targets  : ${TARGET_VMIDS[*]} (106=ubuntu-app-01, 108=kali-01)

EOF
  local reply=""
  read -r -p "  Type 'reset' to confirm: " reply || true
  [[ "$reply" == "reset" ]] || die "confirmation did not match. Nothing was changed."
}

print_post_reset_notes() {
  cat <<EOF

${C_BLD}Post-reset notes${C_RESET}

  EVIDENCE RETENTION - the reason only 106 and 108 were rolled back:

    * The attack-window artifacts on the TARGETS (ubuntu-app-01's auth.log and
      /var/log/nginx/access.log, kali-01's tool history) went away WITH the
      rolled-back disk. On-disk, the targets are back to the instrumented
      baseline as if no attack had run.
    * The ALERTS those artifacts produced are still on wazuh-01 (104), which was
      not touched. Prove it from the jumpbox against the historical window:
          task scenario:verify -- <scenario-id>
      A PASS there after a reset is the retention guarantee in action.

  THE GUEST CLOCK WAS STALE. A rollback restores the clock the guest had when
  the baseline was taken. This script forced a resync and checked NTPSynchronised
  above; if a check warned, give it a few seconds and re-run, or on the target:
      sudo timedatectl set-ntp true && sudo chronyc makestep

  THE WAZUH AGENT WAS RESTARTED. Without that a same-named agent can be blocked
  from re-registering; the manager's <auth><force> should carry
  disconnected_time=0. VERIFY on the manager:
      /var/ossec/bin/agent_control -l | grep -iE 'ubuntu-app-01|kali-01'

  A DELIBERATE FULL RESET (re-take the baseline, or clear SIEM history) is a
  SEPARATE, MANUAL procedure - see docs/scenarios/README.md. It is intentionally
  NOT on this automated path.
EOF
}

main() {
  local positional=""
  while (( $# )); do
    case "$1" in
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

  # The positional, if any, is only a scenario id for messaging. It cannot widen
  # or change the target set - that is a fixed {106, 108}.
  SCENARIO_ID="$positional"

  [[ "$AGENT_WAIT" =~ ^[0-9]+$ ]] || die "--agent-wait must be an integer"

  command -v qm >/dev/null 2>&1 \
    || die "qm not found. This script must run ON the Proxmox VE host."
  [[ "${EUID}" -eq 0 ]] || die "must run as root (try: sudo ${SCRIPT_NAME} $*)"

  printf '%s%sMutaSpace SOC Lab - scenario reset%s\n' "$C_BLD" "$C_BLU" "$C_RESET"
  printf '  scenario : %s\n' "${SCENARIO_ID:-<none> (messaging only; targets are fixed)}"
  printf '  snapshot : %s\n' "$SNAPSHOT_NAME"
  printf '  targets  : %s (106=ubuntu-app-01, 108=kali-01)\n' "${TARGET_VMIDS[*]}"
  printf '  preserved: wazuh-01 (104) is never touched - alerts survive\n'
  (( DRY_RUN )) && printf '  mode     : DRY RUN - nothing will be changed\n'

  if (( ! FORCE )) && (( ! DRY_RUN )); then
    confirm_destruction
  fi

  local i
  for i in "${!TARGET_VMIDS[@]}"; do
    reset_vm "${TARGET_VMIDS[i]}" "${TARGET_ROLES[i]}" "${TARGET_NAMES[i]}"
  done

  printf '\n%sScenario targets reset%s%s.%s\n' "$C_GRN" \
    "${SCENARIO_ID:+ for ${SCENARIO_ID}}" "" "$C_RESET"
  (( POST_RESET )) && print_post_reset_notes
}

main "$@"
