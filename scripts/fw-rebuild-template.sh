#!/usr/bin/env bash
# =============================================================================
# scripts/fw-rebuild-template.sh
#
# ██ RUNNING THIS STARTS THE LOAD-BEARING WINDOW ██
#
#   This script DESTROYS the live OPNsense template (VMID 9004,
#   tpl-opnsense-267) on the Proxmox host and rebuilds it with Packer. From
#   the moment `qm destroy 9004` runs until the new template verifies, the
#   `terraform_data.template_exists` gate (tofu/templates.tf) fails EVERY
#   `tofu apply` --- not just fw-01's. That window is why this script exists:
#   it owns destroy -> build -> verify ATOMICALLY, behind build-blocking
#   gates, with a lock marker that says "no tofu apply of any kind".
#
#   Do NOT run the partial steps by hand. Run this, via `task fw:rebuild-template`,
#   deliberately, with the lab-impact window announced. It is safe to preview
#   with --dry-run (runs the offline gates, prints the destructive steps).
#
# WHAT IT DOES, IN ORDER
#   1. ALL-LOCAL-GATES-GREEN checkpoint (offline, read-only):
#        a. scripts/fw-preflight.sh  --- root password<->hash cross-check, SSH
#           public key shape, API pair, rendered-config XML sanity.
#        b. packer init + validate for packer/opnsense-267.
#        (gitleaks/pre-commit are the third local gate; they run at COMMIT
#        time, so this script checks the working tree is clean --- everything
#        being rebuilt from has already passed them.)
#   2. Writes the lock marker LOCALLY (.planning/opnsense-as-code/.rebuild-in-progress)
#      and ON THE HOST (/tmp/fw-rebuild.lock). While either exists: NO tofu apply.
#   3. `qm destroy 9004` on the host --- only after the gates are green, and
#      only if 9004 is actually a template (never a running VM).
#   4. Launches the DETACHED Packer build with a captured PID file
#      (setsid nohup ... & echo $! > pidfile). House rule: if the build must
#      be killed, kill ONLY by `kill "$(cat <pidfile>)"` --- never pkill.
#   5. Polls to completion, then verifies the new template on the host:
#      `qm list` shows 9004 AND /etc/pve/qemu-server/9004.conf says
#      `template: 1`.
#   6. Removes both lock markers --- only on verified success. On any failure
#      the locks STAY, because the no-apply window is still open.
#
# IF THE BUILD STALLS
#   Screendump the guest console BEFORE theorising (see CLAUDE.md):
#     ssh <host> 'echo "screendump /tmp/x.ppm" | qm monitor 9004 >/dev/null 2>&1'
#   Kill only by the captured PID:  kill "$(cat <pidfile printed below>)"
#   The locks stay in place; re-run this script to retry the whole sequence.
#
# USAGE
#   ./fw-rebuild-template.sh --help
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT

readonly OPNSENSE_DIR="${REPO_ROOT}/packer/opnsense-267"
readonly PKR_COMMON="${REPO_ROOT}/packer/common.pkrvars.hcl"
# packer:run in the Taskfile auto-includes <template>/<template>.pkrvars.hcl
# when the operator has filled one in; mirror that here.
readonly PKR_TPLVARS="${OPNSENSE_DIR}/opnsense-267.pkrvars.hcl"

readonly TEMPLATE_VMID=9004
readonly TEMPLATE_NAME="tpl-opnsense-267"

# Lock markers. Presence of EITHER means: the template_exists gate WILL fail,
# do not run `tofu apply` of any kind until this script finishes and removes them.
readonly LOCK_LOCAL="${REPO_ROOT}/.planning/opnsense-as-code/.rebuild-in-progress"
readonly LOCK_HOST="/tmp/fw-rebuild.lock"

# Detached-build artifacts, beside the local lock. The .log is gitignored
# (*.log); the pidfile is removed on success and is the ONLY sanctioned kill
# handle for the build.
readonly PID_FILE="${REPO_ROOT}/.planning/opnsense-as-code/packer-build.pid"
readonly LOG_FILE="${REPO_ROOT}/.planning/opnsense-as-code/packer-build.log"

# ~30-60 min is normal; past this, stop polling and hand over to the operator.
readonly POLL_INTERVAL=30
readonly POLL_TIMEOUT_MIN=100

DRY_RUN=0
ASSUME_YES=0

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GRN=$'\033[32m'
  C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_DIM=$'\033[2m'; C_BLD=$'\033[1m'
else
  C_RESET=''; C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_DIM=''; C_BLD=''
fi

info() { printf '%s[ .. ]%s %s\n' "$C_BLU" "$C_RESET" "$*"; }
ok()   { printf '%s[ ok ]%s %s\n' "$C_GRN" "$C_RESET" "$*"; }
warn() { printf '%s[ !! ]%s %s\n' "$C_YEL" "$C_RESET" "$*" >&2; }
die()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
hint() { printf '         %s%s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }

usage() {
  cat <<EOF
${SCRIPT_NAME} - atomic OPNsense template rebuild (destroy 9004 -> build -> verify)

DESTRUCTIVE. Destroys ${TEMPLATE_NAME} (VMID ${TEMPLATE_VMID}) on the Proxmox
host and rebuilds it with Packer, owning the whole no-template window: while
the lock markers exist, NO \`tofu apply\` of any kind may run (the
template_exists gate would fail it anyway --- the lock makes that a stated
rule instead of a surprise). Locks are removed only on verified success.

USAGE
  ./${SCRIPT_NAME} [options]

OPTIONS
  --dry-run      Run the offline gates for real, then PRINT the destructive
                 steps without touching the host or starting a build.
  --yes          Skip the interactive confirmation (for the deliberate,
                 announced cutover only).
  -h, --help     Show this help and exit.

READS (from the environment / .envrc)
  LAB_HOST_SSH               ssh destination of the Proxmox node (root@<ip>)
  PKR_VAR_proxmox_*          Packer API credentials (see .envrc.example s.1)
  PKR_VAR_root_*             fw-01 root password/hash/key (gated by fw-preflight)
  PKR_VAR_fw_api_*           fw-01 API pair (gated by fw-preflight)

SEE ALSO
  scripts/fw-preflight.sh    the build-blocking gate this script runs first
  tofu/templates.tf          the template_exists gate the lock marker guards
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes)     ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *)         die "Unknown argument: $1  (see --help)" ;;
  esac
  shift
done

host_ssh="${LAB_HOST_SSH:-}"
[[ -n "$host_ssh" ]] || die "LAB_HOST_SSH is not set. \`qm\` only exists on the Proxmox node --- set it to root@<LAB_MANAGEMENT_IP> (.envrc.example section 1)."
command -v packer >/dev/null 2>&1 || die "packer is required but was not found on PATH."
command -v ssh    >/dev/null 2>&1 || die "ssh is required but was not found on PATH."
[[ -d "$OPNSENSE_DIR" ]] || die "Template directory not found: ${OPNSENSE_DIR}"
[[ -f "$PKR_COMMON" ]]   || die "packer/common.pkrvars.hcl is missing. Copy the .example and fill it in."

printf '%s%s== OPNsense template rebuild --- VMID %s (%s) ==%s\n' \
  "$C_BLD" "$C_BLU" "$TEMPLATE_VMID" "$TEMPLATE_NAME" "$C_RESET"
(( DRY_RUN )) && warn "DRY RUN: gates run for real; nothing on the host will be touched."

# Var-file arguments, mirrored from the Taskfile's packer:run.
pkr_var_args=(-var-file="$PKR_COMMON")
[[ -f "$PKR_TPLVARS" ]] && pkr_var_args+=(-var-file="$PKR_TPLVARS")

# ---------------------------------------------------------------------------
# Step 1 --- ALL-LOCAL-GATES-GREEN checkpoint. Offline, read-only, always run
# (even under --dry-run). Nothing destructive happens unless ALL are green.
# ---------------------------------------------------------------------------
info "Gate 1/3: scripts/fw-preflight.sh (password<->hash, SSH key, API pair, render sanity)"
"${SCRIPT_DIR}/fw-preflight.sh" || die "fw-preflight failed. Fix .envrc section 6; nothing was touched."
ok "fw-preflight green."

info "Gate 2/3: packer validate (packer/opnsense-267)"
( cd "$OPNSENSE_DIR" && packer init . >/dev/null && packer validate "${pkr_var_args[@]}" . ) \
  || die "packer validate failed. Nothing was touched."
ok "packer validate green."

# Gate 3 is gitleaks/pre-commit. Those run at COMMIT time, so what this gate
# can assert here is that the rebuild runs from committed, already-scanned
# code --- a dirty tree means something in this build has never been through them.
info "Gate 3/3: clean working tree (gitleaks/pre-commit ran at commit time)"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]]; then
  warn "Working tree is NOT clean. The pre-commit gitleaks gate has not seen these changes."
  hint "Commit (letting pre-commit run) before a load-bearing rebuild, or accept that this build bakes unscanned edits."
  (( ASSUME_YES || DRY_RUN )) || { read -r -p "Continue with a dirty tree? [y/N] " a; [[ "$a" == [yY] ]] || die "Aborted. Nothing was touched."; }
else
  ok "Working tree clean --- everything in this build has passed pre-commit/gitleaks."
fi

ok "ALL-LOCAL-GATES-GREEN checkpoint passed."

# ---------------------------------------------------------------------------
# Dry run stops here: print the destructive sequence and exit.
# ---------------------------------------------------------------------------
if (( DRY_RUN )); then
  printf '\n%sDRY RUN --- the real run would now, in order:%s\n' "$C_BLD" "$C_RESET"
  echo "  1. write lock:   ${LOCK_LOCAL}"
  echo "  2. write lock:   ${host_ssh}:${LOCK_HOST}"
  echo "     (while either lock exists: NO tofu apply of any kind)"
  echo "  3. ssh ${host_ssh} 'qm destroy ${TEMPLATE_VMID}'   (only if 9004 is a template)"
  echo "  4. setsid nohup packer build ${pkr_var_args[*]} .   # detached, in ${OPNSENSE_DIR}"
  echo "     pidfile: ${PID_FILE}    log: ${LOG_FILE}"
  echo "  5. poll to completion (~30-60 min), then verify on the host:"
  echo "     qm list shows ${TEMPLATE_VMID} ${TEMPLATE_NAME}  AND  grep '^template: 1' /etc/pve/qemu-server/${TEMPLATE_VMID}.conf"
  echo "  6. remove both locks (ONLY on verified success)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Point of no return. Confirm deliberately.
# ---------------------------------------------------------------------------
if (( ! ASSUME_YES )); then
  printf '\n%sThis DESTROYS template %s on %s and opens the no-apply window.%s\n' \
    "$C_YEL" "$TEMPLATE_VMID" "$host_ssh" "$C_RESET"
  read -r -p "Type REBUILD to continue: " answer
  [[ "$answer" == "REBUILD" ]] || die "Aborted. Nothing was touched."
fi

# ---------------------------------------------------------------------------
# Step 2 --- lock markers, local AND on the host, BEFORE anything destructive.
# ---------------------------------------------------------------------------
lock_msg="fw template rebuild in progress since $(date -Iseconds) (pid $$ on $(hostname)).
Meaning: VMID ${TEMPLATE_VMID} may not exist right now, so the template_exists
gate fails EVERY tofu apply. Do NOT run tofu apply until this file is gone.
Owned by scripts/fw-rebuild-template.sh; removed only on verified success."

mkdir -p "$(dirname "$LOCK_LOCAL")"
printf '%s\n' "$lock_msg" > "$LOCK_LOCAL"
ok "Local lock written: ${LOCK_LOCAL}"

printf '%s\n' "$lock_msg" | ssh "$host_ssh" "cat > ${LOCK_HOST}" \
  || die "Could not write the host lock (${host_ssh}:${LOCK_HOST}). Local lock left in place; nothing destroyed."
ok "Host lock written: ${host_ssh}:${LOCK_HOST}"

# ---------------------------------------------------------------------------
# Step 3 --- destroy the old template. Only a TEMPLATE: if 9004 exists but is
# not `template: 1`, something is very wrong and no automation should destroy it.
# ---------------------------------------------------------------------------
if ssh "$host_ssh" "test -f /etc/pve/qemu-server/${TEMPLATE_VMID}.conf"; then
  ssh "$host_ssh" "grep -q '^template: 1' /etc/pve/qemu-server/${TEMPLATE_VMID}.conf" \
    || die "VMID ${TEMPLATE_VMID} exists on the host but is NOT a template. Refusing to destroy it. Locks left in place --- investigate by hand."
  info "Destroying old template ${TEMPLATE_VMID} on the host..."
  ssh "$host_ssh" "qm destroy ${TEMPLATE_VMID}" \
    || die "qm destroy ${TEMPLATE_VMID} failed. Locks left in place --- investigate on the host."
  ok "Old template destroyed. The no-template window is OPEN."
else
  warn "VMID ${TEMPLATE_VMID} does not exist on the host --- the window was already open (resuming a failed rebuild?). Continuing."
fi

# ---------------------------------------------------------------------------
# Step 4 --- detached Packer build with a captured PID (house rule: kill only
# by this pidfile, NEVER pkill --- pkill -x packer kills every build on the
# machine and pgrep -f matches its own shell; both have caused real damage).
# ---------------------------------------------------------------------------
info "Launching detached packer build (log: ${LOG_FILE})"
# setsid reparents packer, so its `$!` is a short-lived intermediate, NOT the
# build --- capturing it would make `kill "$(cat pidfile)"` miss the real
# process (or the poll loop below think a live build already exited). Instead
# background a subshell that EXECs into nohup->packer: `exec` keeps the SAME pid
# through the chain, so the subshell's `$!` IS the packer process. nohup ignores
# SIGHUP so the build survives a dropped terminal; the wrapper polls it to the
# end regardless.
( cd "$OPNSENSE_DIR" || exit 1; exec nohup packer build "${pkr_var_args[@]}" . > "$LOG_FILE" 2>&1 < /dev/null ) &
build_pid=$!
echo "$build_pid" > "$PID_FILE"
# Confirm the captured pid is really the packer build (exec chain settles fast).
if ! ps -o comm= -p "$build_pid" 2>/dev/null | grep -q '^packer$'; then
  sleep 1
  ps -o comm= -p "$build_pid" 2>/dev/null | grep -q '^packer$' \
    || die "Captured pid ${build_pid} is not a running packer process --- the build failed to start. Check ${LOG_FILE}. Locks left in place (no tofu apply until resolved)."
fi
ok "Build running, pid ${build_pid} (captured in ${PID_FILE})."
hint "To kill it: kill \"\$(cat ${PID_FILE})\"   --- never pkill."
hint "If it stalls: screendump the guest console first (see the header of this script)."

# ---------------------------------------------------------------------------
# Step 5 --- poll to completion, then verify the new template on the host.
# ---------------------------------------------------------------------------
elapsed=0
while kill -0 "$build_pid" 2>/dev/null; do
  sleep "$POLL_INTERVAL"
  elapsed=$(( elapsed + POLL_INTERVAL ))
  if (( elapsed % 300 == 0 )); then
    info "Build still running (${elapsed}s elapsed). Last log line:"
    hint "$(tail -n 1 "$LOG_FILE" 2>/dev/null || echo '<no log yet>')"
  fi
  if (( elapsed >= POLL_TIMEOUT_MIN * 60 )); then
    warn "Build exceeded ${POLL_TIMEOUT_MIN} minutes and is STILL RUNNING. Not killing it."
    hint "Screendump the guest console before theorising. Kill only by: kill \"\$(cat ${PID_FILE})\""
    die "Timed out waiting. Locks left in place --- the no-apply window is still open."
  fi
done

info "Packer process exited after ~${elapsed}s. Verifying the result on the host..."
if ! grep -q "Builds finished" "$LOG_FILE" 2>/dev/null; then
  warn "Log does not say 'Builds finished'. Tail of ${LOG_FILE}:"
  tail -n 20 "$LOG_FILE" >&2 || true
fi

ssh "$host_ssh" "qm list | grep -q '^ *${TEMPLATE_VMID} .*${TEMPLATE_NAME}'" \
  || { tail -n 20 "$LOG_FILE" >&2 || true; \
       die "VMID ${TEMPLATE_VMID} (${TEMPLATE_NAME}) not in qm list. Build FAILED. Locks left in place --- no tofu apply until this is fixed."; }
ssh "$host_ssh" "grep -q '^template: 1' /etc/pve/qemu-server/${TEMPLATE_VMID}.conf" \
  || die "VMID ${TEMPLATE_VMID} exists but is not marked 'template: 1'. Build incomplete. Locks left in place."
ok "Verified on the host: ${TEMPLATE_VMID} ${TEMPLATE_NAME}, template: 1."

# ---------------------------------------------------------------------------
# Step 6 --- verified success: close the window.
# ---------------------------------------------------------------------------
ssh "$host_ssh" "rm -f ${LOCK_HOST}" || warn "Could not remove ${host_ssh}:${LOCK_HOST} --- remove it by hand."
rm -f "$LOCK_LOCAL" "$PID_FILE"
ok "Lock markers removed. tofu apply is allowed again."

printf '\n%s%sTemplate rebuild complete and verified.%s\n' "$C_BLD" "$C_GRN" "$C_RESET"
hint "Next (Wave 2.3): tofu apply -replace='module.vm[\"fw-01\"].proxmox_virtual_environment_vm.this' -parallelism=1"
exit 0
