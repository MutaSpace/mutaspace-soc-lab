#!/usr/bin/env bash
# =============================================================================
# scripts/bootstrap-host.sh
#
# WHAT THIS IS
#   Step zero of the MutaSpace SOC Lab build. It runs ON the Proxmox VE host,
#   as root, once, BEFORE any Packer build or any OpenTofu apply. It turns a
#   freshly installed Proxmox host into a host that the infrastructure code can
#   actually talk to.
#
#   It does five things, in this order:
#     1. Detects the PVE major version and forks on it. Almost everything below
#        differs between PVE 8.x and 9.x, and PVE 7.x is refused outright.
#     2. Configures the no-subscription apt repository and disables enterprise.
#     3. Creates two API users, two minimum-privilege roles and two API tokens
#        (one for Packer, one for OpenTofu) and prints the secrets ONCE.
#     4. Enables the 'snippets' content type on the snippet storage.
#     5. Creates vmbr1, vmbr2 and vmbr9 in /etc/network/interfaces, with vmbr9
#        carrying the ip_forward + MASQUERADE rules that make the build plane
#        able to reach the internet before the firewall VM exists.
#
# WHY IT EXISTS
#   This lab is a GREENFIELD build. Nothing on the SOC LAN can reach the
#   internet until fw-01 routes, and fw-01 is itself a VM that has to be built
#   from a template first. The build plane (vmbr9) is what breaks that
#   circularity, and it has to exist before Packer runs. Likewise the API
#   tokens: Packer and OpenTofu both authenticate with a PVE API token, and the
#   two tools want the SAME secret in TWO DIFFERENT SHAPES. Getting that wrong
#   produces a silent 401 that looks like a network problem. This script prints
#   both shapes so nobody has to guess.
#
# WHAT IT ASSUMES
#   * It is running on the Proxmox VE host itself, as root (uid 0).
#   * pveversion, pveum, pvesm and ifreload are on PATH (they are, on PVE).
#   * The host is PVE 8.x or 9.x. 7.x is refused: the bpg/proxmox OpenTofu
#     provider explicitly does not support it.
#   * vmbr0 already exists and carries the physical uplink. The Proxmox
#     installer creates it; this script does not touch it.
#   * The real management subnet on vmbr0 is a SECRET. This script never reads,
#     prints or writes it. Only 10.10.10.0/24, 10.10.20.0/24 and 10.99.0.0/24
#     appear here, and all three are lab-internal and already public in the docs.
#
# IDEMPOTENCY
#   Safe to re-run. Anything already correct is left alone and reported as
#   "skip: <reason>" rather than silently passed over. The one thing that
#   CANNOT be made idempotent is an API token secret: PVE shows it exactly once
#   at creation. If a token already exists this script skips it and tells you to
#   re-run with --rotate-tokens if you need a new secret.
#
# USAGE
#   ./bootstrap-host.sh --help
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Constants. These are the lab's hard contract - see docs/iac/decisions.md.
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"

readonly ROLE_BUILD="MutaSpaceBuild"        # used by packer@pve!buildtoken
readonly ROLE_PROVISION="MutaSpaceProvision" # used by terraform@pve!provider

readonly USER_PACKER="packer@pve"
readonly TOKEN_PACKER="buildtoken"
readonly USER_TOFU="terraform@pve"
readonly TOKEN_TOFU="provider"

# Bridges this script may create. vmbr0 is deliberately absent: the Proxmox
# installer owns it, and its subnet is a secret under this repo's policy.
#
# Only vmbr9 gets an address here. 10.10.10.1 and 10.10.20.1 belong to fw-01,
# not to the host - see create_bridges() for why that matters.
readonly BR_LAN="vmbr1"
readonly BR_ISOLATED="vmbr2"
readonly BR_BUILD="vmbr9"
readonly BR_BUILD_ADDR="10.99.0.1/24"       # the host IS the build plane gateway
readonly BR_BUILD_CIDR="10.99.0.0/24"

readonly INTERFACES_FILE="/etc/network/interfaces"

# -----------------------------------------------------------------------------
# Options
# -----------------------------------------------------------------------------
DRY_RUN=0
ASSUME_YES=0
ROTATE_TOKENS=0
DO_REPOS=1
DO_USERS=1
DO_SNIPPETS=1
DO_NETWORK=1
UPLINK_IF=""
SNIPPET_STORAGE="local"
BUILD_PLANE_DHCP=0   # opt-in: only needed when builds run on vmbr9

# -----------------------------------------------------------------------------
# Output helpers. Colour only when stdout is a terminal, so logs stay readable.
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

# run <description> <command...>
# Executes the command, or prints it when --dry-run is set. Every mutating
# action in this script goes through here so that --dry-run is honest.
run() {
  local desc="$1"; shift
  if (( DRY_RUN )); then
    printf '%s[ dry ]%s %s\n         $ %s\n' "$C_YEL" "$C_RESET" "$desc" "$*"
    return 0
  fi
  "$@"
}

confirm() {
  local prompt="$1"
  (( ASSUME_YES )) && return 0
  (( DRY_RUN )) && return 0
  local reply=""
  read -r -p "${prompt} [y/N] " reply || true
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

usage() {
  cat <<EOF
${SCRIPT_NAME} - one-time Proxmox VE host bootstrap for the MutaSpace SOC Lab

Runs ON the Proxmox host, as root, before any Packer build or OpenTofu apply.
Detects the PVE version and forks on it, configures apt, creates the two API
users/roles/tokens, enables the snippets content type, and creates vmbr1,
vmbr2 and vmbr9 (the masqueraded build plane).

Idempotent: re-running changes nothing that is already correct, and says what
it skipped.

USAGE
  sudo ./${SCRIPT_NAME} [options]

OPTIONS
  --dry-run                 Print every action without performing it.
  --yes                     Do not prompt for confirmation (for automation).
  --rotate-tokens           Delete and recreate the API tokens. Use this when
                            you need a secret re-displayed - PVE only shows a
                            token secret once, at creation.
  --uplink <ifname>         Physical uplink used by the vmbr9 MASQUERADE rule.
                            Default: auto-detected from vmbr0's bridge-ports,
                            falling back to the default-route interface.
  --snippet-storage <id>    Storage to enable 'snippets' on. Default: local
  --skip-repos              Do not touch apt sources.
  --skip-users              Do not create users/roles/tokens.
  --skip-snippets           Do not touch storage content types.
  --build-plane-dhcp        Install dnsmasq and serve DHCP on ${BR_BUILD}.
                            ONLY needed when Packer builds run on the isolated
                            build plane. If vmbr0 already has DHCP and a gateway
                            (the usual case), build there instead and skip this.
  --skip-network            Do not touch ${INTERFACES_FILE}.
  -h, --help                Show this help and exit.

EXIT STATUS
  0 on success. Non-zero on any refusal (wrong PVE version, not root, a VM
  already attached to a bridge this script would modify, etc).

SEE ALSO
  docs/iac/design.md          section 6, "Bootstrap & Ordering"
  docs/iac/decisions.md       D-01 (greenfield), D-05 (offline authoring)
  scripts/preflight.sh        run this from the workstation afterwards
EOF
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
parse_args() {
  while (( $# )); do
    case "$1" in
      --dry-run)          DRY_RUN=1 ;;
      --yes|-y)           ASSUME_YES=1 ;;
      --rotate-tokens)    ROTATE_TOKENS=1 ;;
      --uplink)           shift; [[ $# -gt 0 ]] || die "--uplink needs an interface name"; UPLINK_IF="$1" ;;
      --uplink=*)         UPLINK_IF="${1#*=}" ;;
      --snippet-storage)  shift; [[ $# -gt 0 ]] || die "--snippet-storage needs a storage id"; SNIPPET_STORAGE="$1" ;;
      --snippet-storage=*) SNIPPET_STORAGE="${1#*=}" ;;
      --skip-repos)       DO_REPOS=0 ;;
      --skip-users)       DO_USERS=0 ;;
      --skip-snippets)    DO_SNIPPETS=0 ;;
      --build-plane-dhcp) BUILD_PLANE_DHCP=1 ;;
      --skip-network)     DO_NETWORK=0 ;;
      -h|--help)          usage; exit 0 ;;
      *)                  usage >&2; die "unknown argument: $1" ;;
    esac
    shift
  done
}

# =============================================================================
# 1. PVE version detection and fork
# =============================================================================
PVE_VERSION=""
PVE_MAJOR=""
DEBIAN_CODENAME=""

detect_pve_version() {
  section "Proxmox VE version"

  command -v pveversion >/dev/null 2>&1 \
    || die "pveversion not found. This script must run ON the Proxmox VE host."

  local banner
  banner="$(pveversion -v | head -1)"
  log "  ${banner}"

  # pveversion -v line 1 looks like:  proxmox-ve: 9.0.0 (running kernel: 6.14.0-2-pve)
  PVE_VERSION="$(printf '%s' "$banner" | sed -n 's/^proxmox-ve:[[:space:]]*\([0-9][0-9.]*\).*/\1/p')"
  [[ -n "$PVE_VERSION" ]] || die "could not parse a version out of: ${banner}"
  PVE_MAJOR="${PVE_VERSION%%.*}"

  # shellcheck disable=SC1091
  DEBIAN_CODENAME="$( . /etc/os-release 2>/dev/null && printf '%s' "${VERSION_CODENAME:-}" )"
  [[ -n "$DEBIAN_CODENAME" ]] || die "could not read VERSION_CODENAME from /etc/os-release"

  log "  parsed version : ${PVE_VERSION} (major ${PVE_MAJOR})"
  log "  debian base    : ${DEBIAN_CODENAME}"

  case "$PVE_MAJOR" in
    7|6|5)
      die "PVE ${PVE_VERSION} is not supported.
       The bpg/proxmox OpenTofu provider explicitly does not support PVE 7.x or
       older. Upgrade the host to PVE 8.x or 9.x before running any of this
       lab's infrastructure code. Nothing has been changed."
      ;;
    8)
      log "  fork           : PVE 8.x  (one-line apt sources, VM.Monitor exists,"
      log "                             set min_tls = \"1.2\" in the OpenTofu provider)"
      ;;
    9)
      log "  fork           : PVE 9.x  (deb822 .sources, VM.Monitor REMOVED,"
      log "                             TLS 1.3 default is fine)"
      ;;
    *)
      warn "PVE major version ${PVE_MAJOR} is newer than this script knows about."
      warn "Treating it like 9.x. Verify the privilege list and apt source format by hand."
      PVE_MAJOR=9
      ;;
  esac

  log ""
  log "  Record this version in docs/proxmox/host-baseline.md. Every privilege"
  log "  list, apt source format and TLS default in this lab forks on it."
}

# =============================================================================
# 2. apt repositories
# =============================================================================
configure_repos_pve8() {
  # PVE 8.x / Debian 12 - classic one-line sources.
  local nosub="/etc/apt/sources.list.d/pve-no-subscription.list"
  local want="deb http://download.proxmox.com/debian/pve ${DEBIAN_CODENAME} pve-no-subscription"

  if [[ -f "$nosub" ]] && grep -Fqx "$want" "$nosub"; then
    skipped "no-subscription repo already configured (${nosub})"
  else
    run "write ${nosub}" bash -c "printf '%s\n' '# MutaSpace SOC Lab - added by bootstrap-host.sh' '${want}' > '${nosub}'"
    changed "wrote ${nosub}"
  fi

  local f
  for f in /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/ceph.list; do
    [[ -f "$f" ]] || continue
    if grep -Eq '^[[:space:]]*deb[[:space:]]' "$f"; then
      run "comment out enterprise lines in ${f}" sed -i -E 's/^([[:space:]]*deb[[:space:]].*)$/# \1  # disabled by bootstrap-host.sh/' "$f"
      changed "disabled enterprise repo ${f}"
    else
      skipped "enterprise repo already disabled (${f})"
    fi
  done
}

configure_repos_pve9() {
  # PVE 9.x / Debian 13 - deb822 .sources files.
  local nosub="/etc/apt/sources.list.d/proxmox.sources"
  local keyring="/usr/share/keyrings/proxmox-archive-keyring.gpg"

  if [[ ! -f "$keyring" ]]; then
    warn "expected keyring ${keyring} is missing; apt will reject the repo."
    warn "install proxmox-archive-keyring before running apt update."
  fi

  if [[ -f "$nosub" ]] && grep -q 'pve-no-subscription' "$nosub"; then
    skipped "no-subscription repo already configured (${nosub})"
  else
    if (( DRY_RUN )); then
      printf '%s[ dry ]%s write %s (deb822, Suites: %s, Components: pve-no-subscription)\n' \
        "$C_YEL" "$C_RESET" "$nosub" "$DEBIAN_CODENAME"
    else
      cat >"$nosub" <<EOF
# MutaSpace SOC Lab - added by bootstrap-host.sh
# PVE 9.x / Debian ${DEBIAN_CODENAME} uses deb822-style .sources files. A
# one-line "deb ..." entry copied from a PVE 8 tutorial will be ignored here.
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: ${DEBIAN_CODENAME}
Components: pve-no-subscription
Signed-By: ${keyring}
EOF
    fi
    changed "wrote ${nosub}"
  fi

  local f
  for f in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
    [[ -f "$f" ]] || continue
    if grep -Eq '^[[:space:]]*Enabled:[[:space:]]*false' "$f"; then
      skipped "enterprise repo already disabled (${f})"
    elif grep -Eq '^[[:space:]]*Enabled:' "$f"; then
      run "disable ${f}" sed -i -E 's/^([[:space:]]*Enabled:).*/\1 false/' "$f"
      changed "disabled enterprise repo ${f}"
    else
      run "disable ${f}" bash -c "printf '%s\n' 'Enabled: false' >> '${f}'"
      changed "disabled enterprise repo ${f}"
    fi
  done
}

configure_repos() {
  section "apt repositories"
  if (( PVE_MAJOR >= 9 )); then
    configure_repos_pve9
  else
    configure_repos_pve8
  fi
  log ""
  log "  Run 'apt update && apt full-upgrade' yourself. This script does not"
  log "  upgrade the host - an unattended kernel upgrade mid-bootstrap is not"
  log "  something a build script should decide for you."
}

# =============================================================================
# 3. API users, roles and tokens
# =============================================================================
#
# MINIMUM PRIVILEGE SETS - READ THIS BEFORE "FIXING" THEM
#
# The lists below are a SYNTHESIS, not an authoritative published list. Nobody
# publishes a verified minimum privilege set for Packer + OpenTofu on PVE 8/9.
# The widely-circulated 23-privilege list comes from an OPEN bug report whose
# build actually failed.
#
# The good news is that PVE tells you exactly what is missing. A denied call
# returns:
#
#     403 Permission check failed (/vms/9000, VM.Config.Disk)
#
# So the correct method is: start narrow, run the build, read the 403, add the
# one privilege it names, record it. Do NOT paste a giant list from a tutorial.
#
# Two privileges are deliberately absent and should stay absent:
#   * Sys.Console - alone it grants vncshell/termproxy, i.e. a root shell on the
#     node. Granting it defeats the entire point of not using root@pam.
#   * Sys.Modify  - Sys.AccessNetwork is the modern, narrower replacement.
#
# One privilege is a version fork with a nasty failure mode:
#   * VM.Monitor was REMOVED in PVE 9.0. A role list copied from a pre-2025
#     tutorial fails outright on PVE 9.
#   * VM.GuestAgent.Audit only exists on PVE 9. Its ABSENCE does not produce a
#     clean 403 - the bpg provider HANGS when agent{enabled=true}. If a plan
#     hangs for 15 minutes, this is the first thing to check.
# -----------------------------------------------------------------------------

build_privs() {
  # Packer: create a VM from an ISO, drive it, convert it to a template.
  local privs=(
    Datastore.Audit
    Datastore.AllocateSpace
    Datastore.AllocateTemplate   # uploading ISOs and cd_files images
    Sys.Audit
    VM.Allocate
    VM.Audit
    VM.Clone
    VM.Config.CDROM
    VM.Config.CPU
    VM.Config.Cloudinit
    VM.Config.Disk
    VM.Config.HWType
    VM.Config.Memory
    VM.Config.Network
    VM.Config.Options            # also what flips template=1
    VM.Console                   # boot_command / sendkey
    VM.PowerMgmt
  )
  if (( PVE_MAJOR <= 8 )); then
    privs+=(VM.Monitor)          # removed in PVE 9.0
  else
    privs+=(Sys.AccessNetwork)   # needed if a builder uses the download-url path

    # SDN.Use and SDN.Audit - VERIFIED EMPIRICALLY on PVE 9.2.2, 2026-07-22.
    #
    # Attaching a NIC to a bridge is an SDN-permissioned operation on PVE 9, even
    # when the bridge is a plain Linux bridge in /etc/network/interfaces and no SDN
    # zone was ever configured. Proxmox synthesises a zone called "localnetwork"
    # for exactly this check.
    #
    # Without these, the FIRST Packer build fails at "Creating VM" with:
    #   403 Permission check failed (/sdn/zones/localnetwork/vmbr9, SDN.Use)
    #
    # That error is precise and points straight at the fix, which is why the
    # design deliberately started this list narrow rather than guessing wide:
    # an over-broad role that works is much harder to audit than a narrow one
    # that tells you what it is missing.
    privs+=(SDN.Use SDN.Audit)
  fi
  printf '%s\n' "${privs[@]}" | sort
}

provision_privs() {
  # OpenTofu / bpg provider: clone, configure, snapshot, pool, destroy.
  local privs=(
    Datastore.Allocate
    Datastore.AllocateSpace
    Datastore.AllocateTemplate
    Datastore.Audit
    Pool.Allocate
    Pool.Audit
    SDN.Audit
    Sys.Audit
    VM.Allocate
    VM.Audit
    VM.Backup
    VM.Clone
    VM.Config.CDROM
    VM.Config.CPU
    VM.Config.Cloudinit
    VM.Config.Disk
    VM.Config.HWType
    VM.Config.Memory
    VM.Config.Network
    VM.Config.Options
    VM.Console
    VM.Migrate
    VM.PowerMgmt                 # PVE 9.2 needs this to START a VM after rollback
    VM.Snapshot
    VM.Snapshot.Rollback
  )
  if (( PVE_MAJOR <= 8 )); then
    privs+=(VM.Monitor)          # removed in PVE 9.0
  else
    privs+=(SDN.Use Sys.AccessNetwork VM.GuestAgent.Audit)
  fi
  printf '%s\n' "${privs[@]}" | sort
}

# These helpers query the API through pvesh rather than parsing pveum's table
# output, because pveum's human-facing formatting has changed across PVE
# releases and a parser that silently stops matching turns "already correct"
# into "created again". pvesh mirrors the REST API, which is versioned.
#
# jq is NOT assumed - it is not installed on a stock Proxmox host. The JSON
# shapes read here are flat enough for grep, and every read is a presence test
# or a set of privilege names, never a value that could contain punctuation.

pve_role_exists() {
  pvesh get "/access/roles/$1" --output-format json >/dev/null 2>&1
}

pve_role_current_privs() {
  # GET /access/roles/{roleid} returns {"VM.Allocate":1,"VM.Audit":1,...}
  pvesh get "/access/roles/$1" --output-format json 2>/dev/null \
    | grep -oE '"[A-Za-z]+\.[A-Za-z.]+"' | tr -d '"' | sort -u
}

ensure_role() {
  local role="$1" want_list="$2"
  local want_csv count
  want_csv="$(printf '%s' "$want_list" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  count="$(printf '%s\n' "$want_list" | grep -c .)"

  if pve_role_exists "$role"; then
    local have_list
    have_list="$(pve_role_current_privs "$role" || true)"
    if [[ -n "$have_list" && "$have_list" == "$want_list" ]]; then
      skipped "role ${role} already holds exactly the expected ${count} privileges"
      return 0
    fi
    run "update role ${role}" pveum role modify "$role" -privs "$want_csv"
    changed "updated role ${role} to ${count} privileges"
  else
    run "create role ${role}" pveum role add "$role" -privs "$want_csv"
    changed "created role ${role} with ${count} privileges"
  fi
}

pve_user_exists() {
  pvesh get "/access/users/$1" --output-format json >/dev/null 2>&1
}

ensure_user() {
  local user="$1" comment="$2"
  if pve_user_exists "$user"; then
    skipped "user ${user} already exists"
  else
    run "create user ${user}" pveum user add "$user" --comment "$comment"
    changed "created user ${user}"
  fi
}

pve_acl_exists() {
  # GET /access/acl returns a flat array of {path,roleid,type,ugid,propagate}.
  # Whitespace is stripped so the grep works whether or not pvesh pretty-prints.
  local user="$1" role="$2"
  pvesh get /access/acl --output-format json 2>/dev/null \
    | tr -d ' \t\n' | tr '}' '\n' \
    | grep -F "\"ugid\":\"${user}\"" | grep -qF "\"roleid\":\"${role}\""
}

ensure_acl() {
  local user="$1" role="$2"
  if pve_acl_exists "$user" "$role"; then
    skipped "ACL / -> ${user} : ${role} already present"
  else
    run "grant ${role} to ${user} at /" pveum aclmod / -user "$user" -role "$role"
    changed "granted ${role} to ${user} at /"
  fi
}

pve_token_exists() {
  pvesh get "/access/users/$1/token/$2" --output-format json >/dev/null 2>&1
}

# ensure_token <user> <tokenid> <outvar>
# Sets <outvar> to the secret if a token was created, or to the empty string if
# it already existed (PVE cannot re-display a secret).
ensure_token() {
  local user="$1" token="$2" outvar="$3"
  local secret=""

  if pve_token_exists "$user" "$token"; then
    if (( ROTATE_TOKENS )); then
      run "delete token ${user}!${token}" pveum user token remove "$user" "$token"
      changed "deleted token ${user}!${token} (rotating)"
    else
      skipped "token ${user}!${token} already exists - secret cannot be re-displayed"
      warn "  If you do not have that secret saved, re-run with --rotate-tokens."
      printf -v "$outvar" '%s' ""
      return 0
    fi
  fi

  if (( DRY_RUN )); then
    printf '%s[ dry ]%s create token %s!%s (--privsep=0)\n' "$C_YEL" "$C_RESET" "$user" "$token"
    printf -v "$outvar" '%s' "<dry-run-no-secret>"
    return 0
  fi

  local json
  # --privsep=0 is mandatory. Without it the token inherits NOTHING from the
  # user and every single API call returns 403, no matter what the role says.
  json="$(pveum user token add "$user" "$token" --privsep=0 --output-format json)"
  secret="$(printf '%s' "$json" | sed -n 's/.*"value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  # NOTE: $json is NOT echoed here, however tempting that is for debugging.
  # It contains the token secret in its "value" field, and this message goes to
  # stderr - i.e. into the terminal and into any redirected build log. If the
  # response shape ever changes, inspect it interactively with
  #   pveum user token add ... --output-format json
  # rather than teaching this script to print it.
  [[ -n "$secret" ]] || die "token ${user}!${token} was created but its secret could not be parsed
       out of the API response. The token now exists WITHOUT a recorded secret.
       Delete it and try again:
         pveum user token remove ${user} ${token}
       The response is deliberately not printed here: it contains the secret."
  changed "created token ${user}!${token}"
  printf -v "$outvar" '%s' "$secret"
}

PACKER_SECRET=""
TOFU_SECRET=""

configure_users() {
  section "API users, roles and tokens"

  local build_list provision_list
  build_list="$(build_privs)"
  provision_list="$(provision_privs)"

  log "  ${ROLE_BUILD} privileges (PVE ${PVE_MAJOR}.x set):"
  printf '%s\n' "$build_list" | sed 's/^/    /'
  log "  ${ROLE_PROVISION} privileges (PVE ${PVE_MAJOR}.x set):"
  printf '%s\n' "$provision_list" | sed 's/^/    /'
  log ""

  ensure_role "$ROLE_BUILD"     "$build_list"
  ensure_role "$ROLE_PROVISION" "$provision_list"

  ensure_user "$USER_PACKER" "MutaSpace SOC Lab - Packer template builds"
  ensure_user "$USER_TOFU"   "MutaSpace SOC Lab - OpenTofu provisioning"

  ensure_acl "$USER_PACKER" "$ROLE_BUILD"
  ensure_acl "$USER_TOFU"   "$ROLE_PROVISION"

  ensure_token "$USER_PACKER" "$TOKEN_PACKER" PACKER_SECRET
  ensure_token "$USER_TOFU"   "$TOKEN_TOFU"   TOFU_SECRET
}

# =============================================================================
# 4. snippets content type
# =============================================================================
#
# cloud-init user-data is delivered as a "snippet". The snippets content type is
# NOT enabled by default, and it CANNOT be uploaded through the PVE API at all -
# /nodes/{node}/storage/{storage}/upload accepts only iso|vztmpl|import. The bpg
# provider silently pivots to SFTP over SSH for snippets, which is why a PAM
# account is also needed (see the NEXT STEPS block at the end of this script).
#
# Without this content type, every cloud-init resource fails.
# -----------------------------------------------------------------------------
configure_snippets() {
  section "snippets content type on storage '${SNIPPET_STORAGE}'"

  command -v pvesm >/dev/null 2>&1 || die "pvesm not found"

  local current
  # /etc/pve/storage.cfg is the source of truth and is trivially parseable.
  current="$(awk -v want="$SNIPPET_STORAGE" '
    /^[a-z]+:[[:space:]]/ { inblk = ($2 == want) }
    inblk && $1 == "content" { print $2; exit }
  ' /etc/pve/storage.cfg 2>/dev/null || true)"

  if [[ -z "$current" ]]; then
    die "storage '${SNIPPET_STORAGE}' has no content line in /etc/pve/storage.cfg
       (or the storage does not exist). Check 'pvesm status' and re-run with
       --snippet-storage <id>."
  fi

  if printf '%s' "$current" | tr ',' '\n' | grep -Fqx 'snippets'; then
    skipped "storage ${SNIPPET_STORAGE} already allows snippets (content=${current})"
    return 0
  fi

  local updated="${current},snippets"
  run "enable snippets on ${SNIPPET_STORAGE}" pvesm set "$SNIPPET_STORAGE" --content "$updated"
  changed "storage ${SNIPPET_STORAGE} content: ${current} -> ${updated}"
}

# =============================================================================
# 5. bridges
# =============================================================================
#
# vmbr1 (SOC LAN) and vmbr2 (isolated) are PORTLESS, ADDRESSLESS bridges on the
# host. The host does NOT hold 10.10.10.1 or 10.10.20.1 - fw-01 does. If the
# host also held those addresses you would have two default gateways answering
# on the same segment and the lab would route in ways nobody can debug.
#
# vmbr9 is different. It is the BUILD PLANE and the host itself is its gateway,
# because in a greenfield build nothing can reach the internet until fw-01
# routes, and fw-01 is a VM that has to be built first. So the host masquerades
# 10.99.0.0/24 out of the physical uplink.
#
#   *** Proxmox's own masquerade documentation example uses 10.10.10.1/24. ***
#   *** In THIS lab 10.10.10.1 is fw-01's LAN address. Copying that example ***
#   *** verbatim puts the host on the firewall's gateway address. Do not.   ***
# -----------------------------------------------------------------------------

detect_uplink() {
  [[ -n "$UPLINK_IF" ]] && { printf '%s' "$UPLINK_IF"; return 0; }

  local ifname=""
  # Preferred: whatever physical port vmbr0 already bridges.
  ifname="$(awk '
    /^[[:space:]]*iface[[:space:]]+vmbr0[[:space:]]/ { inblk = 1; next }
    /^[[:space:]]*(iface|auto|allow-)/ { inblk = 0 }
    inblk && $1 == "bridge-ports" { print $2; exit }
  ' "$INTERFACES_FILE" 2>/dev/null || true)"

  if [[ -z "$ifname" || "$ifname" == "none" ]]; then
    # Fallback: the interface the default route leaves by.
    ifname="$(ip -o route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"
  fi

  # ---------------------------------------------------------------------------
  # If that interface is enslaved to a bridge, MASQUERADE on the BRIDGE.
  #
  # VERIFIED THE HARD WAY on PVE 9.2.2, 2026-07-22. This is the single most
  # confusing bug in the whole bootstrap, because everything *looks* correct.
  #
  # vmbr0's bridge-ports says `nic0`, so "the uplink is nic0" is the physically
  # correct answer. It is the routing-WRONG answer. Once a NIC is enslaved to a
  # bridge it stops taking part in IP routing decisions - the bridge holds the
  # address and owns the route. Traffic from the build plane therefore leaves
  # via `dev vmbr0`, and a rule matching `-o nic0` never fires:
  #
  #   ip route get 10.200.2.2 from 10.99.0.5 iif vmbr9
  #     -> via 10.1.1.1 dev vmbr0
  #
  #   iptables -t nat -L POSTROUTING -v -n
  #     pkts bytes target      out    source
  #        0     0 MASQUERADE  nic0   10.99.0.0/24     <-- never matched
  #
  # The symptom is NOT "no network". The VM boots, ARPs fine, and its packets
  # leave the host - just with an un-NATted 10.99.0.x source address that
  # nothing upstream can reply to. So it presents as a silent timeout: the
  # Ubuntu autoinstall seed never downloads and subiquity drops to its
  # interactive menu, which looks like a broken boot command.
  #
  # A zero packet counter on the MASQUERADE rule is the diagnostic. Check it
  # first, before suspecting the installer.
  # ---------------------------------------------------------------------------
  if [[ -n "$ifname" ]]; then
    local master
    master="$(ip -o link show "$ifname" 2>/dev/null | grep -oP 'master \K[^ ]+' || true)"
    if [[ -n "$master" ]]; then
      warn "uplink ${ifname} is enslaved to ${master}; masquerading on ${master} instead"
      warn "  (a rule on an enslaved port never matches - the bridge owns the route)"
      ifname="$master"
    fi
  fi

  printf '%s' "$ifname"
}

bridge_declared() {
  grep -Eq "^[[:space:]]*iface[[:space:]]+$1[[:space:]]" "$INTERFACES_FILE"
}

# vms_on_bridge <bridge> -> prints "vmid:type" lines for every guest attached
vms_on_bridge() {
  local br="$1" f vmid
  for f in /etc/pve/qemu-server/*.conf; do
    [[ -e "$f" ]] || continue
    if grep -Eq "bridge=${br}([,[:space:]]|$)" "$f"; then
      vmid="${f##*/}"; vmid="${vmid%.conf}"
      printf 'qemu:%s\n' "$vmid"
    fi
  done
  for f in /etc/pve/lxc/*.conf; do
    [[ -e "$f" ]] || continue
    if grep -Eq "bridge=${br}([,[:space:]]|$)" "$f"; then
      vmid="${f##*/}"; vmid="${vmid%.conf}"
      printf 'lxc:%s\n' "$vmid"
    fi
  done
}

emit_plain_bridge() {
  local br="$1" purpose="$2"
  cat <<EOF

auto ${br}
iface ${br} inet manual
        bridge-ports none
        bridge-stp off
        bridge-fd 0
#       ${purpose}
#       Deliberately has NO address on the host: fw-01 is the gateway for this
#       segment, and two gateways on one segment is an undebuggable lab.
EOF
}

emit_build_bridge() {
  local uplink="$1"
  cat <<EOF

auto ${BR_BUILD}
iface ${BR_BUILD} inet static
        address ${BR_BUILD_ADDR}
        bridge-ports none
        bridge-stp off
        bridge-fd 0
        post-up   echo 1 > /proc/sys/net/ipv4/ip_forward
        post-up   iptables -t nat -A POSTROUTING -s '${BR_BUILD_CIDR}' -o ${uplink} -j MASQUERADE
        post-down iptables -t nat -D POSTROUTING -s '${BR_BUILD_CIDR}' -o ${uplink} -j MASQUERADE
#       BUILD PLANE. No physical port. Exists only so Packer can reach the
#       internet before fw-01 exists. OpenTofu re-points network_device.bridge
#       to ${BR_LAN}/${BR_ISOLATED} at clone time - 'bridge' is not ForceNew,
#       so that switch costs nothing.
#
#       WARNING: Proxmox's own masquerade example uses 10.10.10.1/24. That is
#       fw-01's LAN address in this lab. This bridge uses ${BR_BUILD_ADDR}
#       precisely so the two never collide.
#
#       If the PVE firewall is enabled, conntrack zones may also be needed:
#         iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone 1
EOF
}

create_bridges() {
  section "bridges ${BR_LAN}, ${BR_ISOLATED}, ${BR_BUILD}"

  [[ -f "$INTERFACES_FILE" ]] || die "${INTERFACES_FILE} not found"

  printf '%s%s' "$C_YEL" "$C_BLD"
  cat <<'BANNER'
  ----------------------------------------------------------------------------
  WARNING - THE PROXMOX MASQUERADE EXAMPLE IS WRONG FOR THIS LAB
  The Proxmox wiki's NAT/masquerade example configures the bridge as
  10.10.10.1/24. In the MutaSpace SOC Lab, 10.10.10.1 is fw-01's LAN address
  and the default gateway for every VM on the SOC LAN. Never copy that example
  verbatim here. The build plane is 10.99.0.0/24 for exactly this reason.
  ----------------------------------------------------------------------------
BANNER
  printf '%s' "$C_RESET"

  # --- Refuse if any guest already lives on a bridge we would touch ---------
  local br blocked=0 attached
  for br in "$BR_LAN" "$BR_ISOLATED" "$BR_BUILD"; do
    bridge_declared "$br" && continue   # we would not modify it
    attached="$(vms_on_bridge "$br" || true)"
    if [[ -n "$attached" ]]; then
      blocked=1
      warn "guests are already attached to ${br}, which is NOT declared in ${INTERFACES_FILE}:"
      printf '%s\n' "$attached" | sed 's/^/        /' >&2
    fi
  done
  if (( blocked )); then
    die "refusing to modify ${INTERFACES_FILE}.
       A guest is attached to a bridge this script would create. That means the
       host is not the greenfield host this script assumes, and rewriting the
       interfaces file could cut those guests off the network. Resolve by hand,
       or re-run with --skip-network."
  fi

  local uplink
  uplink="$(detect_uplink)"
  if [[ -z "$uplink" ]]; then
    die "could not determine the physical uplink interface for the ${BR_BUILD}
       MASQUERADE rule. Pass it explicitly: --uplink <ifname>
       ('ip -br link' lists the candidates)."
  fi
  log "  uplink for MASQUERADE: ${uplink}"
  if [[ "$uplink" == vmbr* ]]; then
    # This is the CORRECT outcome on a standard Proxmox host, not a warning sign.
    #
    # An earlier version of this script warned here that a bridge was "not a
    # physical port" and suggested passing --uplink with the physical interface.
    # That advice was exactly backwards and cost an afternoon: masquerading on a
    # bridge-enslaved port produces a rule that never matches, because the bridge
    # owns the route. See the long comment in detect_uplink().
    info "masquerading on '${uplink}' (the bridge holds the address and the route)"
  fi

  # --- Compose only the stanzas that are missing ----------------------------
  local additions="" any=0
  if bridge_declared "$BR_LAN"; then
    skipped "${BR_LAN} already declared in ${INTERFACES_FILE}"
  else
    additions+="$(emit_plain_bridge "$BR_LAN" "SOC LAN - 10.10.10.0/24, gateway 10.10.10.1 is fw-01")"$'\n'
    any=1
  fi
  if bridge_declared "$BR_ISOLATED"; then
    skipped "${BR_ISOLATED} already declared in ${INTERFACES_FILE}"
  else
    additions+="$(emit_plain_bridge "$BR_ISOLATED" "ISOLATED - 10.10.20.0/24, gateway 10.10.20.1 is fw-01")"$'\n'
    any=1
  fi
  if bridge_declared "$BR_BUILD"; then
    skipped "${BR_BUILD} already declared in ${INTERFACES_FILE}"
    log "         (its MASQUERADE rule is NOT re-checked - verify by hand:"
    log "          iptables -t nat -S POSTROUTING | grep ${BR_BUILD_CIDR})"
  else
    additions+="$(emit_build_bridge "$uplink")"$'\n'
    any=1
  fi

  if (( ! any )); then
    log ""
    log "  All three bridges are already declared. Nothing to do."
    return 0
  fi

  log ""
  log "  About to append to ${INTERFACES_FILE}:"
  printf '%s\n' "$additions" | sed 's/^/    | /'

  if ! confirm "  Append these stanzas and run 'ifreload -a'?"; then
    die "aborted by operator. ${INTERFACES_FILE} was not modified."
  fi

  local backup
  backup="${INTERFACES_FILE}.mutaspace-$(date +%Y%m%d%H%M%S).bak"
  run "back up ${INTERFACES_FILE}" cp -a "$INTERFACES_FILE" "$backup"
  changed "backed up ${INTERFACES_FILE} -> ${backup}"

  if (( DRY_RUN )); then
    printf '%s[ dry ]%s append stanzas to %s\n' "$C_YEL" "$C_RESET" "$INTERFACES_FILE"
  else
    printf '%s' "$additions" >>"$INTERFACES_FILE"
  fi
  changed "appended bridge stanzas to ${INTERFACES_FILE}"

  if command -v ifreload >/dev/null 2>&1; then
    run "apply network configuration" ifreload -a
    changed "ran 'ifreload -a'"
  else
    warn "ifreload not found (ifupdown2 missing?). Reboot or apply by hand."
  fi

  if (( ! DRY_RUN )); then
    log ""
    log "  Verification - 'ip -br link' for the lab bridges:"
    ip -br link show "$BR_LAN" 2>/dev/null | sed 's/^/    /' || warn "${BR_LAN} did not come up"
    ip -br link show "$BR_ISOLATED" 2>/dev/null | sed 's/^/    /' || warn "${BR_ISOLATED} did not come up"
    ip -br link show "$BR_BUILD" 2>/dev/null | sed 's/^/    /' || warn "${BR_BUILD} did not come up"
    log ""
    log "  Verification - the MASQUERADE rule:"
    (iptables -t nat -S POSTROUTING 2>/dev/null | grep -F "$BR_BUILD_CIDR" | sed 's/^/    /') \
      || warn "no POSTROUTING rule for ${BR_BUILD_CIDR} - check 'iptables -t nat -S'"
  fi
}

# =============================================================================
# Credential printout - the single most common silent 401 in this stack
# =============================================================================
print_credentials() {
  local endpoint_hint="https://<LAB_MANAGEMENT_IP>:8006"

  section "API CREDENTIALS - SHOWN ONCE, NEVER AGAIN"

  printf '%s%s' "$C_RED" "$C_BLD"
  cat <<'BANNER'
  ############################################################################
  #                                                                          #
  #   THESE SECRETS ARE DISPLAYED EXACTLY ONCE.                              #
  #   Proxmox does not store them in retrievable form. If you lose them the   #
  #   only remedy is to re-run this script with --rotate-tokens, which        #
  #   invalidates the old ones.                                              #
  #                                                                          #
  #   Put them in a password manager or a gitignored .envrc. NEVER commit     #
  #   them. This repository's policy (README.md) forbids committing tokens.   #
  #                                                                          #
  ############################################################################
BANNER
  printf '%s' "$C_RESET"

  cat <<EOF

  ---------------------------------------------------------------------------
  THE TRAP: ONE SECRET, TWO DIFFERENT SHAPES
  ---------------------------------------------------------------------------
  Packer and the bpg/proxmox OpenTofu provider both authenticate with a PVE API
  token, but they want it assembled DIFFERENTLY:

    Packer   wants the user and the secret as TWO separate values:
               proxmox_username = "${USER_PACKER}!${TOKEN_PACKER}"
               proxmox_token    = "<uuid>"

    bpg/tofu wants ONE concatenated string:
               api_token = "${USER_TOFU}!${TOKEN_TOFU}=<uuid>"

  Sharing one environment variable between the two tools silently 401s. The
  error message says nothing about shape. This is the single most common
  wasted afternoon in this stack.

  The endpoints differ too:
    Packer   proxmox_url         MUST end with /api2/json
    bpg      PROXMOX_VE_ENDPOINT MUST NOT include /api2/json

  This repository's Packer templates declare proxmox_url / proxmox_username /
  proxmox_token as HCL variables, so Packer reads them from PKR_VAR_<name> -
  NOT from the plugin's own PROXMOX_URL / PROXMOX_USERNAME / PROXMOX_TOKEN.
  Use the PKR_VAR_ spellings below.

EOF

  cat <<EOF
  ---------------------------------------------------------------------------
  EXPORT LINES - PACKER  (two values, split)
  ---------------------------------------------------------------------------
export PKR_VAR_proxmox_url="${endpoint_hint}/api2/json"
export PKR_VAR_proxmox_username="${USER_PACKER}!${TOKEN_PACKER}"
export PKR_VAR_proxmox_token="${PACKER_SECRET:-<not-created-this-run-see-above>}"

  ---------------------------------------------------------------------------
  EXPORT LINES - OPENTOFU / bpg  (one value, concatenated)
  ---------------------------------------------------------------------------
export PROXMOX_VE_ENDPOINT="${endpoint_hint}"
export PROXMOX_VE_API_TOKEN="${USER_TOFU}!${TOKEN_TOFU}=${TOFU_SECRET:-<not-created-this-run-see-above>}"
export PROXMOX_VE_SSH_USERNAME="terraform"

  Certificate verification is a VARIABLE in this repository, not a provider
  environment variable. tofu/providers.tf sets insecure = var.pve_insecure, and
  a provider argument always beats the environment - so PROXMOX_VE_INSECURE
  would be read, then overridden, and have no effect at all.

export TF_VAR_pve_insecure="true"         # self-signed PVE certificate

  Same story for TLS. The provider requires 1.3 by default; PVE 8.x hosts often
  offer only 1.2, and the failure looks like an unreachable host rather than a
  TLS mismatch. This host is PVE ${PVE_MAJOR}.x:

# export TF_VAR_pve_min_tls="1.2"          # uncomment on PVE 8.x

EOF

  log "  Replace <LAB_MANAGEMENT_IP> with the host's real management address."
  log "  That address is a SECRET by this repository's policy and is deliberately"
  log "  not printed here even though this script is running on the host."
  log ""
  log "  Verify the shapes before you build:  ./scripts/preflight.sh"
}

print_next_steps() {
  section "NEXT STEPS this script deliberately does NOT do"

  cat <<EOF
  1. CREATE THE PAM ACCOUNT FOR SNIPPET UPLOADS.
     Snippets cannot be uploaded through the PVE API. The bpg provider pivots to
     SFTP/SSH, which needs a REAL Linux account (not just a PVE user):

       adduser --disabled-password --gecos "" terraform
       mkdir -p /home/terraform/.ssh && chmod 700 /home/terraform/.ssh
       # install your workstation's public key into /home/terraform/.ssh/authorized_keys
       chown -R terraform:terraform /home/terraform/.ssh

     Then grant NARROW sudo. Use exactly this line:

       terraform ALL=(root) NOPASSWD: /usr/sbin/pvesm, /usr/sbin/qm, \\
         /usr/bin/tee /var/lib/vz/snippets/[a-zA-Z0-9_][a-zA-Z0-9_.-]*

     The absence of '/' from that character class IS the security fix. The older,
     widely copied 'tee /var/lib/vz/*' form is CVE-2026-25499 (High): the glob
     permits 'tee /var/lib/vz/../../../etc/sudoers.d/x', i.e. full root.

  2. STOCK THE ISO SHELF.
     Windows Server 2022 Eval, Windows 11 Eval and the OPNsense 26.7 DVD are
     manually acquired (registration-gated, or shipped as .bz2 that Packer
     cannot boot - decompress it first). Record every SHA256 in
     docs/proxmox/iso-shelf.md. There is no URL to automate.

  3. RUN PREFLIGHT FROM THE WORKSTATION.
       ./scripts/preflight.sh
     It re-checks everything above from the outside, including the two token
     shapes, and fails loudly rather than at 'packer build' time.

  4. RECORD THE PVE VERSION (${PVE_VERSION}) in docs/proxmox/host-baseline.md.
     If it is 8.x, set TF_VAR_pve_min_tls="1.2" (or pve_min_tls = "1.2" in
     tofu/terraform.tfvars): the provider defaults to TLS 1.3 and a TLS-1.2-only
     endpoint fails in a way that looks nothing like a TLS problem.
EOF
}

# =============================================================================
# main
# =============================================================================
# =============================================================================
# DHCP on the build plane
# =============================================================================
#
# WHY THIS EXISTS - it was missed entirely on the first pass, and the failure it
# causes is genuinely misleading.
#
# vmbr9 had an address (10.99.0.1/24), a working MASQUERADE rule and ip_forward
# enabled. Everything about the build plane looked finished. It had nothing to
# hand out leases.
#
# A Packer build VM boots the Ubuntu live installer, requests DHCP, gets no
# answer, and comes up with NO IP ADDRESS. It therefore cannot fetch the
# autoinstall seed, cloud-init eventually gives up, and subiquity falls back to
# its interactive language menu. That looks exactly like a broken boot command,
# and it is not - the boot command is fine and the machine simply has no network.
#
# The diagnostic that separates the two: check the MASQUERADE packet counter.
# A VM retrying an HTTP fetch generates a steady stream of packets. A VM with no
# lease generates almost none.
#
#   ss -ulnp | grep ':67 '                      <- nothing listening = this bug
#   iptables -t nat -L POSTROUTING -v -n        <- near-zero counter = no traffic
#
# A static IP on the kernel command line would also work, but DHCP is worth
# having anyway: every template build needs one, and the templates should not
# each carry a hard-coded build-time address.
#
# dnsmasq is bound to vmbr9 ONLY. `bind-interfaces` matters - without it dnsmasq
# binds the wildcard address and will answer DHCP and DNS on every interface on
# the host, including the management network. That would be a genuinely bad day.
# =============================================================================

configure_build_dhcp() {
  section "DHCP for the build plane (${BR_BUILD})"

  local conf="/etc/dnsmasq.d/mutaspace-build-plane.conf"

  if ! command -v dnsmasq >/dev/null 2>&1; then
    info "dnsmasq is not installed; installing (build VMs cannot get an address without it)"
    # apt-get update FIRST. On a freshly-installed host the only configured
    # repositories are the enterprise ones, which 401 without a subscription -
    # so the package lists are empty and the install fails with the misleading
    # "Package 'dnsmasq' has no installation candidate". configure_repos() has
    # already fixed the sources by this point; the lists just need refreshing.
    run "refresh package lists" env DEBIAN_FRONTEND=noninteractive apt-get update -qq
    run "install dnsmasq" env DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq
    # Proxmox has no DHCP server of its own, and a stock dnsmasq install enables a
    # system-wide resolver. Disable the default instance; only our scoped drop-in
    # should be active.
    run "disable stock dnsmasq resolver behaviour" systemctl disable --now dnsmasq 2>/dev/null || true
    changed "installed dnsmasq"
  else
    skipped "dnsmasq already installed"
  fi

  local desired
  desired="$(cat <<EOF
# MutaSpace SOC Lab - DHCP for the Packer build plane.
# Managed by ${SCRIPT_NAME}. Scoped to ${BR_BUILD} only.
interface=${BR_BUILD}
bind-interfaces
except-interface=lo
no-hosts
dhcp-authoritative
dhcp-range=10.99.0.100,10.99.0.200,12h
dhcp-option=option:router,10.99.0.1
dhcp-option=option:dns-server,10.99.0.1
# Upstream resolvers for build VMs. They need working DNS to reach
# archive.ubuntu.com; the lab's own DNS (dc-01) does not exist yet at build time.
server=1.1.1.1
server=9.9.9.9
EOF
)"

  if [[ -f "$conf" ]] && [[ "$(cat "$conf")" == "$desired" ]]; then
    skipped "${conf} already correct"
  else
    if (( DRY_RUN )); then
      info "[ dry ] write ${conf}"
    else
      printf '%s\n' "$desired" > "$conf"
    fi
    changed "wrote ${conf}"
  fi

  # A systemd unit scoped to this config, so the stock dnsmasq service stays off.
  local unit="/etc/systemd/system/dnsmasq-build-plane.service"
  local desired_unit
  desired_unit="$(cat <<EOF
[Unit]
Description=MutaSpace SOC Lab - DHCP/DNS for the Packer build plane (${BR_BUILD})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/sbin/dnsmasq --keep-in-foreground --conf-file=${conf}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
)"

  if [[ -f "$unit" ]] && [[ "$(cat "$unit")" == "$desired_unit" ]]; then
    skipped "${unit} already correct"
  else
    if (( DRY_RUN )); then
      info "[ dry ] write ${unit}"
    else
      printf '%s\n' "$desired_unit" > "$unit"
      systemctl daemon-reload
    fi
    changed "wrote ${unit}"
  fi

  if (( DRY_RUN )); then
    info "[ dry ] enable and start dnsmasq-build-plane"
  else
    systemctl enable --now dnsmasq-build-plane >/dev/null 2>&1 || true
    systemctl restart dnsmasq-build-plane >/dev/null 2>&1 || true
    if systemctl is-active --quiet dnsmasq-build-plane; then
      changed "dnsmasq-build-plane is active on ${BR_BUILD}"
      log "  Verification - listening sockets:"
      ss -ulnp 2>/dev/null | grep -E ':67 ' | sed 's/^/    /' || log "    (none - investigate)"
    else
      warn "dnsmasq-build-plane failed to start. Build VMs will get no address."
      warn "  journalctl -u dnsmasq-build-plane -n 30"
    fi
  fi
}

main() {
  parse_args "$@"

  if [[ "${EUID}" -ne 0 ]]; then
    die "must run as root on the Proxmox VE host (try: sudo ${SCRIPT_NAME})"
  fi

  section "MutaSpace SOC Lab - host bootstrap"
  log "  host    : $(hostname -f 2>/dev/null || hostname)"
  log "  date    : $(date -Is)"
  (( DRY_RUN )) && log "  mode    : DRY RUN - nothing will be changed"

  detect_pve_version

  # Deliberately if/else rather than `cond && do || skip`: with the latter, a
  # non-zero return from the action would ALSO print "skipped", which is exactly
  # the kind of quiet lie this script is trying not to tell.
  if (( DO_REPOS ));    then configure_repos;    else skipped "apt repositories (--skip-repos)"; fi
  if (( DO_USERS ));    then configure_users;    else skipped "users/roles/tokens (--skip-users)"; fi
  if (( DO_SNIPPETS )); then configure_snippets; else skipped "snippets content type (--skip-snippets)"; fi
  if (( DO_NETWORK ));  then create_bridges;     else skipped "bridges (--skip-network)"; fi
  # Must follow create_bridges: dnsmasq binds the build bridge, so it has to exist.
  #
  # OPT-IN. Most hosts do not need this. The build plane only needs its own DHCP
  # server when Packer builds run on it, and builds should run on vmbr0 whenever
  # vmbr0 has DHCP and a gateway - it needs no extra services and, unlike the
  # build plane, leaves the VM reachable from the workstation for Packer's SSH.
  if (( DO_NETWORK && BUILD_PLANE_DHCP )); then
    configure_build_dhcp
  else
    skipped "build-plane DHCP (not requested; pass --build-plane-dhcp if builds run on ${BR_BUILD})"
  fi

  if (( DO_USERS )); then print_credentials; fi
  print_next_steps

  section "summary"
  log "  changed : ${CHANGED_COUNT}"
  log "  skipped : ${SKIPPED_COUNT}  (already correct, or explicitly disabled)"
  (( DRY_RUN )) && log "  DRY RUN - re-run without --dry-run to apply."
  log ""
}

main "$@"
