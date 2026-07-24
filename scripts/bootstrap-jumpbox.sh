#!/usr/bin/env bash
# =============================================================================
# scripts/bootstrap-jumpbox.sh
#
# WHAT THIS IS
#   The second bootstrap of the MutaSpace SOC Lab. It turns a freshly-cloned
#   jumpbox-01 (VMID 101, 10.10.10.5) into the Ansible control node the lab is
#   configured FROM. Where bootstrap-host.sh prepares the Proxmox hypervisor,
#   this prepares the one lab VM that runs the config playbooks and the ai/
#   tooling against every other VM - Linux over SSH, Windows over WinRM.
#
#   It runs on the OPERATOR'S WORKSTATION, not on the jumpbox, and reaches the
#   jumpbox by SSH-jumping through the Proxmox host (the jumpbox has no route to
#   the operator's network; only the host does). In order it:
#
#     1. Checks its preconditions: the repo is here, the lab SSH key is here,
#        a filled-in ansible/lab-credentials.env is here, and the jumpbox is
#        reachable through the jump. Any of these missing stops with an
#        instruction, not a stack trace.
#     2. apt-installs ansible, python3-winrm (pywinrm for the NTLM WinRM
#        transport), python3-httpx (the oxlorg.opnsense collection's dep, used by
#        05-fw-config against the fw-01 API), git and rsync on the jumpbox.
#     3. rsyncs the ansible/ and ai/ trees to the jumpbox, with the same
#        exclusions the .gitignore files declare (no secrets, no build
#        artifacts).
#     4. Stages the lab SSH private key and the lab credentials onto the
#        jumpbox as ~/.ssh/mutaspace_lab_ed25519 and
#        <repo>/ansible/.secrets/env, both mode 600.
#     5. Installs the pinned Ansible collections from requirements.yml.
#     6. Verifies: ansible runs, pywinrm and httpx import, the Windows collections
#        are present, and (best-effort) the Linux hosts answer a ping.
#
# WHY IT EXISTS
#   The first lab bring-up ran Ansible from the Proxmox host: tooling installed
#   on the hypervisor, the repo rsynced into /root/ansible, lab passwords in
#   /root/ansible/.secrets/env, and the host given addresses on vmbr1/vmbr2 so
#   it could reach the VMs. None of that is reproduced by `git clone`. This
#   script captures that manual state as code and moves it onto a normal lab
#   citizen, so the host can go back to being just a hypervisor and the next
#   operator gets a control node with one command.
#
# WHAT IT ASSUMES
#   * It is run from a checkout of this repository, on the operator's
#     workstation, with `ssh <host>` already working (the WireGuard tunnel up
#     and the alias in ~/.ssh/config - see docs/iac/getting-started.md).
#   * jumpbox-01 already EXISTS and is booted. It is created by OpenTofu:
#       tofu -chdir=tofu apply
#     This script provisions the VM; it does not create it. If the jumpbox is
#     unreachable it says so and points here.
#   * The jumpbox runs Ubuntu Server 24.04 (template 9000), whose cloud-init
#     grants the `labadmin` user passwordless sudo and installs the lab public
#     key - so this script can sudo and log in without a password.
#
# IDEMPOTENCY
#   Safe to re-run. apt install of a present package is a no-op, rsync copies
#   only changes, and the key/secret files are rewritten to the same content
#   with the same mode. Re-running after editing a playbook is the intended way
#   to push that edit to the jumpbox.
#
# SECRETS
#   The lab credentials and the private key travel over the SSH transport (and
#   nothing else) and are written with umask 077. They are NEVER passed on a
#   command line - argv is visible in `ps` and in the jump host's audit log -
#   only ever piped over stdin into a file. This script prints variable NAMES
#   when it reports what it staged, never values.
#
# USAGE
#   ./bootstrap-jumpbox.sh --help
#
# SEE ALSO
#   scripts/bootstrap-host.sh    the hypervisor bootstrap that runs first
#   ansible/README.md            what the playbooks do once this has run
#   docs/iac/resume-here.md      why the jumpbox replaces the host-run Ansible
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Defaults. Every one is overridable by a flag; the defaults describe the lab as
# lab.yaml declares it, so a stock deployment needs no flags at all.
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"

# The Proxmox host is addressed by its ~/.ssh/config alias, not an IP, because
# the real management address is a secret under this repo's policy (README.md).
# `ssh <alias>` already carries the User and IdentityFile, so ProxyJump inherits
# them too.
JUMP_HOST="swc2026"

# The jumpbox itself: lab.yaml gives it 10.10.10.5 on the SOC LAN with the
# `labadmin` cloud-init user.
JUMPBOX_IP="10.10.10.5"
JUMPBOX_USER="labadmin"

# Where the repo lands on the jumpbox. A path under the login user's home, not
# /root - the playbooks run as labadmin, the same identity that reaches the VMs.
REMOTE_DIR="/home/${JUMPBOX_USER}/mutaspace-soc-lab"

# The lab SSH private key. Its public half is baked into templates 9000/9001/9005
# by cloud-init, so it opens both the jumpbox itself and every Linux lab VM. The
# credentials file names it as MUTASPACE_LINUX_SSH_KEY; honour that if exported.
LAB_KEY="${MUTASPACE_LINUX_SSH_KEY:-${HOME}/.ssh/id_ed25519_mutaspace_lab}"

# The filled-in lab credentials. Only the .example is committed; the operator
# copies and fills it (see the precondition below). Staged to the jumpbox as the
# .secrets/env the playbooks source.
CRED_FILE="ansible/lab-credentials.env"

# Where the private key lands on the jumpbox. This is the default the credentials
# example already points MUTASPACE_LINUX_SSH_KEY at, so the staged env needs no
# rewrite when the operator kept the default.
readonly REMOTE_KEY_PATH="/home/${JUMPBOX_USER}/.ssh/mutaspace_lab_ed25519"

DRY_RUN=0
DO_APT=1
DO_SYNC=1
DO_SECRETS=1
DO_COLLECTIONS=1
DO_VERIFY=1

# -----------------------------------------------------------------------------
# Output helpers - identical vocabulary to bootstrap-host.sh so the two scripts
# read the same in a terminal and in a log.
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GRN=$'\033[32m'
  C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_BLD=$'\033[1m'
else
  C_RESET=''; C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_BLD=''
fi

CHANGED_COUNT=0
SKIPPED_COUNT=0

log()     { printf '%s\n' "$*"; }
info()    { printf '%s[ .. ]%s %s\n' "$C_BLU" "$C_RESET" "$*"; }
changed() { printf '%s[ ++ ]%s %s\n' "$C_GRN" "$C_RESET" "$*"; CHANGED_COUNT=$((CHANGED_COUNT + 1)); }
skipped() { printf '%s[ == ]%s %s\n' "$C_YEL" "$C_RESET" "$*"; SKIPPED_COUNT=$((SKIPPED_COUNT + 1)); }
warn()    { printf '%s[ !! ]%s %s\n' "$C_YEL" "$C_RESET" "$*" >&2; }
die()     { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

section() {
  printf '\n%s%s== %s %s%s\n' "$C_BLD" "$C_BLU" "$*" \
    "$(printf '=%.0s' $(seq 1 $((60 - ${#1} > 0 ? 60 - ${#1} : 3))))" "$C_RESET"
}

usage() {
  cat <<EOF
${SCRIPT_NAME} - provision jumpbox-01 into the lab's Ansible control node

Runs ON THE WORKSTATION, reaching the jumpbox through the Proxmox host. Installs
Ansible + pywinrm, stages the repo, the lab SSH key and the lab credentials, and
installs the pinned collections. Idempotent: re-run it to push a playbook edit.

The jumpbox must already exist (OpenTofu creates it: 'tofu -chdir=tofu apply').

USAGE
  ./${SCRIPT_NAME} [options]

OPTIONS
  --jump-host <alias>     ~/.ssh/config alias of the Proxmox host to jump through.
                          Default: ${JUMP_HOST}
  --jumpbox-ip <ip>       The jumpbox's SOC-LAN address. Default: ${JUMPBOX_IP}
  --user <name>           Cloud-init login on the jumpbox. Default: ${JUMPBOX_USER}
  --key <path>            Lab SSH private key (opens jumpbox and Linux VMs).
                          Default: \$MUTASPACE_LINUX_SSH_KEY or
                          ${HOME}/.ssh/id_ed25519_mutaspace_lab
  --cred-file <path>      Filled-in lab credentials to stage as .secrets/env.
                          Default: ${CRED_FILE}
  --dry-run               Print every remote action without performing it.
  --skip-apt              Do not touch packages on the jumpbox.
  --skip-sync             Do not rsync the repo.
  --skip-secrets          Do not stage the key or credentials.
  --skip-collections      Do not install Ansible collections.
  --skip-verify           Do not run the post-install checks.
  -h, --help              Show this help and exit.

AFTER IT FINISHES
  ssh -J ${JUMP_HOST} ${JUMPBOX_USER}@${JUMPBOX_IP} -i <lab-key>
  cd ${REMOTE_DIR}/ansible
  set -a; . .secrets/env; set +a
  ansible-playbook -i inventory/hosts.yml playbooks/50-wazuh-agents.yml
EOF
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
parse_args() {
  while (( $# )); do
    case "$1" in
      --jump-host)   shift; [[ $# -gt 0 ]] || die "--jump-host needs a value"; JUMP_HOST="$1" ;;
      --jump-host=*) JUMP_HOST="${1#*=}" ;;
      --jumpbox-ip)  shift; [[ $# -gt 0 ]] || die "--jumpbox-ip needs a value"; JUMPBOX_IP="$1" ;;
      --jumpbox-ip=*) JUMPBOX_IP="${1#*=}" ;;
      --user)        shift; [[ $# -gt 0 ]] || die "--user needs a value"; JUMPBOX_USER="$1" ;;
      --user=*)      JUMPBOX_USER="${1#*=}" ;;
      --key)         shift; [[ $# -gt 0 ]] || die "--key needs a value"; LAB_KEY="$1" ;;
      --key=*)       LAB_KEY="${1#*=}" ;;
      --cred-file)   shift; [[ $# -gt 0 ]] || die "--cred-file needs a value"; CRED_FILE="$1" ;;
      --cred-file=*) CRED_FILE="${1#*=}" ;;
      --dry-run)     DRY_RUN=1 ;;
      --skip-apt)    DO_APT=0 ;;
      --skip-sync)   DO_SYNC=0 ;;
      --skip-secrets) DO_SECRETS=0 ;;
      --skip-collections) DO_COLLECTIONS=0 ;;
      --skip-verify) DO_VERIFY=0 ;;
      -h|--help)     usage; exit 0 ;;
      *)             usage >&2; die "unknown argument: $1" ;;
    esac
    shift
  done
  # --user changes both derived paths, unless the operator overrode them too.
  REMOTE_DIR="/home/${JUMPBOX_USER}/mutaspace-soc-lab"
}

# -----------------------------------------------------------------------------
# SSH plumbing. One place decides how we reach the jumpbox, so the ProxyJump and
# the key selection cannot drift between the command and the rsync.
#
#   IdentitiesOnly=yes  - offer only the lab key, so an operator with a crowded
#                         agent does not trip the server's MaxAuthTries first.
#   The known_hosts churn of a resettable lab VM is why StrictHostKeyChecking is
#   accept-new here: a rebuilt jumpbox presents a new key and this is a lab, not
#   a step in a chain of trust. This is the ONE place that relaxes it; the
#   playbooks keep host_key_checking on (ansible.cfg).
# -----------------------------------------------------------------------------
SSH_OPTS=()
ssh_setup() {
  SSH_OPTS=(
    -o "ProxyJump=${JUMP_HOST}"
    -i "${LAB_KEY}"
    -o IdentitiesOnly=yes
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=10
  )
}

# jb_ssh <command...> - run a command on the jumpbox. In --dry-run, print it.
jb_ssh() {
  if (( DRY_RUN )); then
    printf '%s[ dry ]%s ssh %s@%s $ %s\n' "$C_YEL" "$C_RESET" "$JUMPBOX_USER" "$JUMPBOX_IP" "$*"
    return 0
  fi
  ssh "${SSH_OPTS[@]}" "${JUMPBOX_USER}@${JUMPBOX_IP}" "$@"
}

# jb_put <mode> <remote_path> - read file content from stdin and write it on the
# jumpbox with the given mode, without ever putting it on a command line.
jb_put() {
  local mode="$1" dest="$2"
  if (( DRY_RUN )); then
    printf '%s[ dry ]%s stage (mode %s) -> %s:%s\n' "$C_YEL" "$C_RESET" "$mode" "$JUMPBOX_IP" "$dest"
    cat >/dev/null
    return 0
  fi
  # umask 077 so the file is never briefly world-readable between create and chmod.
  ssh "${SSH_OPTS[@]}" "${JUMPBOX_USER}@${JUMPBOX_IP}" \
    "umask 077; mkdir -p \"\$(dirname '${dest}')\" && cat > '${dest}' && chmod ${mode} '${dest}'"
}

# =============================================================================
# 0. Preconditions
# =============================================================================
REPO_ROOT=""
check_preconditions() {
  section "preconditions"

  # Run from the repo. Resolve the root from this script's location so the
  # working directory does not matter.
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  REPO_ROOT="$here"
  [[ -d "${REPO_ROOT}/ansible" && -d "${REPO_ROOT}/ai" ]] \
    || die "${REPO_ROOT} does not look like the repo (no ansible/ and ai/).
       Run this script from a checkout of mutaspace-soc-lab."
  info "repo root: ${REPO_ROOT}"

  # The lab SSH key.
  [[ -f "$LAB_KEY" ]] \
    || die "lab SSH key not found: ${LAB_KEY}
       This is the key whose public half cloud-init baked into the templates.
       Point at it with --key or export MUTASPACE_LINUX_SSH_KEY."
  info "lab SSH key: ${LAB_KEY}"

  # The filled-in credentials. Resolve relative paths against the repo root.
  [[ "$CRED_FILE" = /* ]] || CRED_FILE="${REPO_ROOT}/${CRED_FILE}"
  if [[ ! -f "$CRED_FILE" ]]; then
    die "lab credentials not found: ${CRED_FILE}
       Create it from the committed template and fill in the lab passwords:
         cp ansible/lab-credentials.env.example ansible/lab-credentials.env
         \$EDITOR ansible/lab-credentials.env
       It is gitignored; it never gets committed. Then re-run this script."
  fi
  info "lab credentials: ${CRED_FILE} ($(grep -cE '^\s*export ' "$CRED_FILE") exports)"

  # The jumpbox has to be up. This is the check that catches "you forgot to
  # tofu apply". `true` over SSH is the cheapest possible reachability probe.
  ssh_setup
  info "reaching jumpbox ${JUMPBOX_USER}@${JUMPBOX_IP} via ${JUMP_HOST} ..."
  if (( DRY_RUN )); then
    skipped "reachability check (dry run)"
  elif ssh "${SSH_OPTS[@]}" "${JUMPBOX_USER}@${JUMPBOX_IP}" true 2>/dev/null; then
    changed "jumpbox is reachable"
  else
    die "cannot reach ${JUMPBOX_USER}@${JUMPBOX_IP} through ${JUMP_HOST}.
       The jumpbox must exist and be booted before this runs. Create it with:
         tofu -chdir=tofu apply
       Then confirm by hand:
         ssh -J ${JUMP_HOST} ${JUMPBOX_USER}@${JUMPBOX_IP} -i ${LAB_KEY} hostname"
  fi
}

# =============================================================================
# 1. Packages
# =============================================================================
#
# ansible        - the whole point of the node. Ubuntu 24.04's ansible-core
#                  (2.16) satisfies the requires_ansible of both pinned Windows
#                  collections; the irreversible forest work (10/20) already ran
#                  on the host, so nothing that depends on a newer core runs here.
# python3-winrm  - pywinrm. The Windows groups use WinRM with the NTLM transport
#                  (inventory/group_vars/*_windows.yml); the apt package pulls
#                  python3-requests-ntlm, which NTLM needs.
# python3-httpx  - the oxlorg.opnsense collection's ONE pip dependency (its
#                  requirements.txt). 05-fw-config.yml's modules import httpx and
#                  fail hard without it; the apt package avoids the PEP 668
#                  externally-managed-environment wall that `pip install httpx` hits
#                  on Ubuntu 24.04. Found the hard way running 05-fw-config live.
# git, rsync     - rsync stages the repo (and must exist before the first sync);
#                  git is here for the optional wazuh-ansible clone (roles/README).
# =============================================================================
install_packages() {
  section "packages on the jumpbox"

  local pkgs="ansible python3-winrm python3-httpx git rsync"
  log "  installing: ${pkgs}"
  log "  (apt is idempotent - already-present packages are left as they are)"

  # DEBIAN_FRONTEND keeps a package's post-install from blocking on a prompt.
  # A single apt-get update then install; noninteractive and quiet.
  jb_ssh "sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq" \
    || die "apt-get update failed on the jumpbox (no route to the mirror?).
       The jumpbox reaches the internet through fw-01; check fw-01 is up."
  jb_ssh "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ${pkgs}" \
    || die "apt-get install failed on the jumpbox."
  changed "installed ${pkgs}"
}

# =============================================================================
# 2. Stage the repo
# =============================================================================
#
# rsync the two trees the control node actually runs: ansible/ and ai/. The
# exclusions mirror the two .gitignore files so no secret and no build artifact
# is ever pushed - the credentials and the key are staged separately, by the
# dedicated step below, with a tighter mode than a repo sync would give them.
# --delete keeps the jumpbox an exact mirror, so a file removed from the repo
# does not linger on the control node across a re-run.
# =============================================================================
stage_repo() {
  section "stage repo -> ${JUMPBOX_IP}:${REMOTE_DIR}"

  local excludes=(
    --exclude '.secrets/'
    --exclude 'collections/'
    --exclude '.ssh/'
    --exclude '*.env'
    --include '*.env.example'
    --exclude 'roles/wazuh-ansible/'
    --exclude '*.retry'
    --exclude 'facts_cache/'
    --exclude '.index/'
    --exclude 'out/'
    --exclude '__pycache__/'
    --exclude '*.pyc'
  )

  # rsync's own -e carries the same ProxyJump/key/known-hosts policy as jb_ssh.
  local rsh="ssh -o ProxyJump=${JUMP_HOST} -i ${LAB_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

  jb_ssh "mkdir -p '${REMOTE_DIR}'"

  local tree
  for tree in ansible ai; do
    if (( DRY_RUN )); then
      printf '%s[ dry ]%s rsync %s/ -> %s:%s/%s/\n' "$C_YEL" "$C_RESET" \
        "$tree" "$JUMPBOX_IP" "$REMOTE_DIR" "$tree"
      continue
    fi
    rsync -a --delete "${excludes[@]}" -e "$rsh" \
      "${REPO_ROOT}/${tree}/" "${JUMPBOX_USER}@${JUMPBOX_IP}:${REMOTE_DIR}/${tree}/" \
      || die "rsync of ${tree}/ failed."
    changed "synced ${tree}/"
  done
}

# =============================================================================
# 3. Stage the key and the credentials
# =============================================================================
#
# Both are secrets, so neither is touched by the repo sync. They travel over the
# SSH transport via jb_put (stdin only, umask 077) and land mode 600.
#
# The staged credentials get one edit: MUTASPACE_LINUX_SSH_KEY is forced to the
# jumpbox-local key path this script writes, whatever the workstation copy said,
# so the value is correct regardless of where the operator keeps their own key.
# =============================================================================
stage_secrets() {
  section "stage SSH key and credentials"

  # The private key, at the path the credentials example defaults to.
  jb_put 600 "${REMOTE_KEY_PATH}" < "$LAB_KEY"
  changed "staged lab SSH key -> ${REMOTE_KEY_PATH} (mode 600)"

  # The credentials, with the key path pinned to the jumpbox copy. Filter out any
  # existing MUTASPACE_LINUX_SSH_KEY line and append the correct one; everything
  # else is copied verbatim. Never echoed - piped straight through.
  {
    grep -v -E '^\s*export\s+MUTASPACE_LINUX_SSH_KEY=' "$CRED_FILE"
    printf 'export MUTASPACE_LINUX_SSH_KEY=%q\n' "$REMOTE_KEY_PATH"
  } | jb_put 600 "${REMOTE_DIR}/ansible/.secrets/env"
  changed "staged credentials -> ${REMOTE_DIR}/ansible/.secrets/env (mode 600)"

  if (( ! DRY_RUN )); then
    log "  staged variables (names only):"
    jb_ssh "grep -oE '^\s*export [A-Z_]+' '${REMOTE_DIR}/ansible/.secrets/env' | sed 's/export //'" \
      | sed 's/^/    /'
  fi
}

# =============================================================================
# 4. Ansible collections
# =============================================================================
#
# Installed into the project's collections/ directory (ansible.cfg sets
# collections_path = collections), so they sit beside the playbooks rather than
# in the login user's home. Pinned versions live in requirements.yml.
# =============================================================================
install_collections() {
  section "Ansible collections"
  log "  ansible-galaxy collection install -r requirements.yml (into collections/)"
  jb_ssh "cd '${REMOTE_DIR}/ansible' && ansible-galaxy collection install -r requirements.yml" \
    || die "collection install failed. Check the jumpbox has a route to Galaxy."
  changed "installed pinned collections"
}

# =============================================================================
# 5. Verify
# =============================================================================
#
# Prove the four things a broken control node fails on: ansible itself runs, the
# WinRM Python dependency imports, the Windows collections resolved, and the
# inventory parses. The Linux ping is best-effort - a stopped VM is not this
# script's failure, so a red ping is reported, not fatal.
# =============================================================================
verify() {
  section "verify"

  if (( DRY_RUN )); then
    skipped "verification (dry run)"
    return 0
  fi

  local v
  v="$(jb_ssh "ansible --version | head -1" 2>/dev/null || true)"
  [[ -n "$v" ]] && changed "ansible: ${v}" || warn "ansible did not report a version"

  if jb_ssh "python3 -c 'import winrm'" 2>/dev/null; then
    changed "pywinrm imports (WinRM/NTLM transport available)"
  else
    warn "python3 cannot import winrm - Windows plays will fail"
  fi

  if jb_ssh "python3 -c 'import httpx'" 2>/dev/null; then
    changed "httpx imports (oxlorg.opnsense modules can run - 05-fw-config)"
  else
    warn "python3 cannot import httpx - 05-fw-config.yml (fw-01 API) will fail"
  fi

  local cols
  cols="$(jb_ssh "cd '${REMOTE_DIR}/ansible' && ansible-galaxy collection list 2>/dev/null | grep -E 'microsoft.ad|ansible.windows'" || true)"
  if [[ -n "$cols" ]]; then
    changed "Windows collections present:"
    printf '%s\n' "$cols" | sed 's/^/    /'
  else
    warn "microsoft.ad / ansible.windows not found in the collection list"
  fi

  if jb_ssh "cd '${REMOTE_DIR}/ansible' && ansible-inventory -i inventory/hosts.yml --list >/dev/null" 2>/dev/null; then
    changed "inventory parses"
  else
    warn "inventory did not parse - check inventory/hosts.yml"
  fi

  # Best-effort liveness of the Linux estate. Sources the staged env so the key
  # path and lab user are set exactly as a real run would have them.
  log ""
  log "  best-effort: pinging the Linux hosts that are powered on ..."
  jb_ssh "cd '${REMOTE_DIR}/ansible' && set -a && . .secrets/env && set +a && ansible linux -i inventory/hosts.yml -m ping -o" \
    2>&1 | sed 's/^/    /' || warn "  some Linux hosts did not answer (expected if they are stopped)"
}

# =============================================================================
# main
# =============================================================================
main() {
  parse_args "$@"

  section "MutaSpace SOC Lab - jumpbox bootstrap"
  log "  from    : $(hostname 2>/dev/null || echo workstation) (this workstation)"
  log "  to      : ${JUMPBOX_USER}@${JUMPBOX_IP} via ${JUMP_HOST}"
  log "  repo on : ${REMOTE_DIR}"
  log "  date    : $(date -Is)"
  (( DRY_RUN )) && log "  mode    : DRY RUN - nothing on the jumpbox will change"

  check_preconditions

  if (( DO_APT ));         then install_packages;    else skipped "packages (--skip-apt)"; fi
  if (( DO_SYNC ));        then stage_repo;           else skipped "repo sync (--skip-sync)"; fi
  if (( DO_SECRETS ));     then stage_secrets;        else skipped "secrets (--skip-secrets)"; fi
  if (( DO_COLLECTIONS )); then install_collections;  else skipped "collections (--skip-collections)"; fi
  if (( DO_VERIFY ));      then verify;               else skipped "verify (--skip-verify)"; fi

  section "summary"
  log "  changed : ${CHANGED_COUNT}"
  log "  skipped : ${SKIPPED_COUNT}"
  log ""
  log "  The control node is ready. Reach it and run a playbook:"
  log "    ssh -J ${JUMP_HOST} ${JUMPBOX_USER}@${JUMPBOX_IP} -i ${LAB_KEY}"
  log "    cd ${REMOTE_DIR}/ansible"
  log "    set -a; . .secrets/env; set +a"
  log "    ansible-playbook -i inventory/hosts.yml playbooks/50-wazuh-agents.yml"
  log ""
  log "  Once the jumpbox is doing the config runs, the host's vmbr1/vmbr2"
  log "  management IPs can be removed - they were the stopgap this replaces."
  if (( DRY_RUN )); then
    log ""
    log "  DRY RUN - re-run without --dry-run to apply."
  fi
  return 0
}

main "$@"
