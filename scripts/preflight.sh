#!/usr/bin/env bash
# =============================================================================
# scripts/preflight.sh
#
# WHAT THIS IS
#   A checklist that runs FROM THE WORKSTATION and answers one question:
#   "if I run 'packer build' or 'tofu apply' right now, will it fail for a
#   boring reason?"
#
#   It prints one PASS / FAIL / WARN / SKIP line per check and exits non-zero
#   if anything failed.
#
# WHAT IT CHECKS
#   1. Required binaries exist, and tofu is at least 1.12.
#   2. Every required environment variable is set AND IN THE RIGHT SHAPE.
#   3. Both API tokens actually authenticate against the host.
#   4. The 'snippets' content type is enabled on the snippet storage.
#   5. vmbr1, vmbr2 and vmbr9 exist on the host, and vmbr9 carries 10.99.0.1.
#   6. Every template VMID declared in lab.yaml exists on the host AND is
#      flagged as a template.
#   7. Every manually-acquired ISO is present on the ISO storage.
#
# WHY CHECK 2 IS THE WHOLE POINT
#   Packer and the bpg/proxmox OpenTofu provider need the SAME PVE API token in
#   TWO DIFFERENT SHAPES:
#
#     Packer : PKR_VAR_proxmox_username="packer@pve!buildtoken"  (owner + id)
#              PKR_VAR_proxmox_token="<uuid>"                    (secret alone)
#     bpg    : PROXMOX_VE_API_TOKEN="terraform@pve!provider=<uuid>"  (one string)
#
#   This repository's Packer templates declare `proxmox_url`, `proxmox_username`
#   and `proxmox_token` as HCL variables, so Packer reads them from PKR_VAR_*
#   and NOT from the plugin's own PROXMOX_URL/PROXMOX_USERNAME/PROXMOX_TOKEN.
#   This script accepts either spelling and prefers PKR_VAR_*, because that is
#   what packer/*.pkr.hcl actually consumes.
#
#   Feeding one shape to the other tool produces a 401 whose message says
#   nothing about shape. Catching it here, with a regex, before a 40-minute
#   Windows template build, is the entire reason this script exists.
#
# WHAT IT ASSUMES
#   * It runs on the workstation, not on the Proxmox host.
#   * curl and jq are installed. jq is required, not optional: every host-side
#     check parses the PVE API's JSON, and hand-rolled JSON parsing in bash is
#     how you get checks that pass when they should fail.
#   * lab.yaml sits at the repository root and uses this repository's plain
#     block-mapping style for the keys this script reads (site.*, templates:,
#     iso_shelf:). It does NOT parse the whole file - only those keys.
#   * The PVE certificate is self-signed, so TLS verification is skipped when
#     PROXMOX_VE_INSECURE is true (the default assumption for this lab).
#
# OFFLINE USE
#   The lab's infrastructure code is authored BEFORE the Proxmox host exists
#   (decision D-05). Pass --offline to run only the checks that need no host:
#   binaries, environment-variable shapes, and lab.yaml consistency. Host
#   checks are then reported as SKIP, and SKIP is not a failure.
#
# USAGE
#   ./preflight.sh --help
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT

LAB_FILE="${REPO_ROOT}/lab.yaml"
OFFLINE=0
API_TIMEOUT=15
VERBOSE=0

# Minimum OpenTofu version. 1.12 is required for terraform_data + the
# triggers_replace behaviour this lab relies on instead of null_resource.
readonly TOFU_MIN_MAJOR=1
readonly TOFU_MIN_MINOR=12

# Manually-acquired media. These cannot be fetched from a URL: the Windows
# images are registration-gated and OPNsense publishes only a .bz2, which Packer
# cannot boot. Ubuntu and Kali are absent from this list on purpose - their
# Packer templates pull them from a real URL, so they are not "on the shelf".
#
# These filenames are a CROSS-FILE CONTRACT. They must match:
#   * the `default` of `windows_iso_file` / `virtio_win_iso_file` /
#     `opnsense_iso_file` in packer/*/ , and
#   * docs/proxmox/iso-shelf.md
# Override the list by adding an `iso_shelf:` block to lab.yaml, which is the
# right place for it once one exists.
DEFAULT_ISO_SHELF=(
  "windows-server-2022-eval.iso"     # packer/win-server-2022
  "windows-11-enterprise-eval.iso"   # packer/win11-client
  "virtio-win-0.1.271.iso"           # pinned; 0.1.285/0.1.292 regress vioscsi
  "OPNsense-26.7-dvd-amd64.iso"      # decompressed from the published .bz2
)

readonly REQUIRED_BRIDGES=("vmbr1" "vmbr2" "vmbr9")

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GRN=$'\033[32m'
  C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_DIM=$'\033[2m'; C_BLD=$'\033[1m'
else
  C_RESET=''; C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_DIM=''; C_BLD=''
fi

PASS_N=0; FAIL_N=0; WARN_N=0; SKIP_N=0
FAILURES=()

pass() { printf '%s[ PASS ]%s %s\n' "$C_GRN" "$C_RESET" "$*"; PASS_N=$((PASS_N+1)); }
fail() { printf '%s[ FAIL ]%s %s\n' "$C_RED" "$C_RESET" "$*"; FAIL_N=$((FAIL_N+1)); FAILURES+=("$*"); }
warns(){ printf '%s[ WARN ]%s %s\n' "$C_YEL" "$C_RESET" "$*"; WARN_N=$((WARN_N+1)); }
skip() { printf '%s[ SKIP ]%s %s\n' "$C_DIM" "$C_RESET" "$*"; SKIP_N=$((SKIP_N+1)); }
hint() { printf '         %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
section() { printf '\n%s%s-- %s%s\n' "$C_BLD" "$C_BLU" "$*" "$C_RESET"; }

usage() {
  cat <<EOF
${SCRIPT_NAME} - preflight checklist for the MutaSpace SOC Lab

Run from the workstation before 'packer build' or 'tofu apply'. Prints a
pass/fail checklist and exits non-zero if anything failed.

USAGE
  ./${SCRIPT_NAME} [options]

OPTIONS
  --offline            Skip every check that needs the Proxmox host. Use while
                       authoring the code before the host exists (decision
                       D-05). Skipped checks do not cause a non-zero exit.
  --lab-file <path>    Path to lab.yaml. Default: ${LAB_FILE}
  --timeout <seconds>  Per-request API timeout. Default: ${API_TIMEOUT}
  -v, --verbose        Print the API paths being queried.
  -h, --help           Show this help and exit.

ENVIRONMENT (all required unless --offline)
  OpenTofu / bpg provider
    PROXMOX_VE_ENDPOINT      https://<host>:8006      NO /api2/json suffix
    PROXMOX_VE_API_TOKEN     user@pve!tokenid=<uuid>  ONE concatenated string
    PROXMOX_VE_INSECURE      true | false             optional, defaults to true
    PROXMOX_VE_SSH_USERNAME  PAM user for snippet SFTP uploads
  Packer  (PROXMOX_URL / PROXMOX_USERNAME / PROXMOX_TOKEN also accepted)
    PKR_VAR_proxmox_url      https://<host>:8006/api2/json  WITH /api2/json
    PKR_VAR_proxmox_username user@pve!tokenid         NO '=' and NO secret
    PKR_VAR_proxmox_token    <uuid>                   the secret ALONE
  Other
    PVE_NODE                 optional; overrides site.node from lab.yaml

EXIT STATUS
  0  every check passed (warnings and skips are allowed)
  1  at least one check failed
  2  the script could not run at all (bad arguments, missing jq, no lab.yaml)

SEE ALSO
  scripts/bootstrap-host.sh   run that on the host first; it prints these values
  docs/iac/design.md          section 6, "Bootstrap & Ordering"
EOF
}

parse_args() {
  while (( $# )); do
    case "$1" in
      --offline)     OFFLINE=1 ;;
      --lab-file)    shift; [[ $# -gt 0 ]] || { usage >&2; exit 2; }; LAB_FILE="$1" ;;
      --lab-file=*)  LAB_FILE="${1#*=}" ;;
      --timeout)     shift; [[ $# -gt 0 ]] || { usage >&2; exit 2; }; API_TIMEOUT="$1" ;;
      --timeout=*)   API_TIMEOUT="${1#*=}" ;;
      -v|--verbose)  VERBOSE=1 ;;
      -h|--help)     usage; exit 0 ;;
      *)             printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
  done
}

# =============================================================================
# lab.yaml reading
#
# Deliberately a narrow reader, not a YAML parser. It handles exactly three
# shapes, all of which this repository's lab.yaml uses:
#
#   site:                       -> yaml_nested site node
#     node: mutaspace-soc-node01
#
#   templates:                  -> yaml_block_map templates
#     ubuntu-server-2404: 9000
#
#   iso_shelf:                  -> yaml_block_list iso_shelf
#     - win11-eval.iso
#
# Flow mappings ({ a: 1, b: 2 }) are NOT read, because none of the keys this
# script needs use them. If that ever changes, install yq and rewrite these
# three functions - do not extend the awk.
# =============================================================================
yaml_nested() {   # yaml_nested <top-key> <child-key>
  awk -v top="$1:" -v child="$2:" '
    { sub(/[[:space:]]*#.*$/, "") }
    $0 ~ "^"top"[[:space:]]*$" { inblk = 1; next }
    /^[^[:space:]#]/           { inblk = 0 }
    inblk && $1 == child       { $1 = ""; sub(/^[[:space:]]+/, ""); gsub(/^["'"'"']|["'"'"']$/, ""); print; exit }
  ' "$LAB_FILE" 2>/dev/null || true
}

yaml_block_map() { # yaml_block_map <top-key>  -> "key value" lines
  awk -v top="$1:" '
    { sub(/[[:space:]]*#.*$/, "") }
    $0 ~ "^"top"[[:space:]]*$" { inblk = 1; next }
    /^[^[:space:]#]/           { inblk = 0 }
    inblk && NF >= 2 && $1 ~ /:$/ {
      k = $1; sub(/:$/, "", k); $1 = ""; sub(/^[[:space:]]+/, "")
      gsub(/^["'"'"']|["'"'"']$/, ""); print k, $0
    }
  ' "$LAB_FILE" 2>/dev/null || true
}

yaml_block_list() { # yaml_block_list <top-key> -> one item per line
  awk -v top="$1:" '
    { sub(/[[:space:]]*#.*$/, "") }
    $0 ~ "^"top"[[:space:]]*$" { inblk = 1; next }
    /^[^[:space:]#]/           { inblk = 0 }
    inblk && $1 == "-"         { $1 = ""; sub(/^[[:space:]]+/, ""); gsub(/^["'"'"']|["'"'"']$/, ""); if (length($0)) print }
  ' "$LAB_FILE" 2>/dev/null || true
}

PVE_NODE=""
ISO_STORE="local"
SNIPPET_STORE="local"

load_lab_yaml() {
  section "lab.yaml"

  if [[ ! -f "$LAB_FILE" ]]; then
    fail "lab.yaml not found at ${LAB_FILE}"
    hint "lab.yaml is the single source of truth for VMIDs, IPs and MACs."
    hint "Pass --lab-file if it lives somewhere else."
    return 1
  fi
  pass "lab.yaml found: ${LAB_FILE}"

  PVE_NODE="${PVE_NODE:-$(yaml_nested site node)}"
  [[ -n "${PVE_NODE}" ]] || PVE_NODE="$(yaml_nested site node)"
  local iso_s snip_s
  iso_s="$(yaml_nested site iso_store)"
  snip_s="$(yaml_nested site snippets_store)"
  [[ -n "$iso_s"  ]] && ISO_STORE="$iso_s"
  [[ -n "$snip_s" ]] && SNIPPET_STORE="$snip_s"

  if [[ -z "$PVE_NODE" ]]; then
    fail "could not read site.node from lab.yaml (and PVE_NODE is unset)"
    return 1
  fi
  pass "node=${PVE_NODE}  iso_store=${ISO_STORE}  snippets_store=${SNIPPET_STORE}"

  local tcount
  tcount="$(yaml_block_map templates | wc -l | tr -d ' ')"
  if [[ "$tcount" -eq 0 ]]; then
    fail "lab.yaml declares no 'templates:' block"
    hint "Every template VMID (9000-9005) is a hard contract between Packer and"
    hint "OpenTofu. Without it there is nothing to verify."
    return 1
  fi
  pass "lab.yaml declares ${tcount} template VMIDs"
  return 0
}

# =============================================================================
# 1. binaries
# =============================================================================
check_binaries() {
  section "required tooling"

  local b
  for b in curl jq awk; do
    if command -v "$b" >/dev/null 2>&1; then
      pass "${b} present"
    else
      fail "${b} not found on PATH"
      [[ "$b" == "jq" ]] && hint "jq is required: every host check parses the PVE API's JSON."
    fi
  done

  # --- OpenTofu, with a version floor -----------------------------------------
  if ! command -v tofu >/dev/null 2>&1; then
    fail "tofu not found on PATH"
    hint "This lab uses OpenTofu, not Terraform: it needs terraform_data +"
    hint "triggers_replace and native state encryption."
  else
    local ver major minor
    ver="$(tofu version 2>/dev/null | head -1 | sed -n 's/.*[vV]\([0-9][0-9.]*\).*/\1/p')"
    if [[ -z "$ver" ]]; then
      warns "tofu present but its version could not be parsed"
    else
      major="${ver%%.*}"
      minor="${ver#*.}"; minor="${minor%%.*}"
      if (( major > TOFU_MIN_MAJOR || (major == TOFU_MIN_MAJOR && minor >= TOFU_MIN_MINOR) )); then
        pass "tofu ${ver} (>= ${TOFU_MIN_MAJOR}.${TOFU_MIN_MINOR})"
      else
        fail "tofu ${ver} is older than the required ${TOFU_MIN_MAJOR}.${TOFU_MIN_MINOR}"
        hint "terraform_data + triggers_replace replaces null_resource in this lab."
      fi
    fi
  fi

  # --- Packer -----------------------------------------------------------------
  if command -v packer >/dev/null 2>&1; then
    pass "packer $(packer version 2>/dev/null | head -1 | sed -n 's/.*[vV]\([0-9][0-9.]*\).*/\1/p')"
  else
    fail "packer not found on PATH"
  fi

  # --- Ansible ----------------------------------------------------------------
  if command -v ansible-playbook >/dev/null 2>&1; then
    pass "ansible-playbook $(ansible-playbook --version 2>/dev/null | head -1 | sed -n 's/.*[[ ]core \([0-9.]*\).*/\1/p;s/^ansible-playbook \([0-9.]*\)$/\1/p')"
  else
    fail "ansible-playbook not found on PATH"
  fi

  # --- Collections: advisory only, they are installable in one command --------
  if command -v ansible-galaxy >/dev/null 2>&1; then
    local coll
    coll="$(ansible-galaxy collection list 2>/dev/null || true)"
    local c
    for c in microsoft.ad ansible.windows; do
      if printf '%s' "$coll" | grep -q "^${c} "; then
        pass "collection ${c} installed"
      else
        warns "collection ${c} not installed"
        hint "ansible-galaxy collection install -r ansible/requirements.yml"
      fi
    done
  else
    warns "ansible-galaxy not found; collection versions not checked"
  fi

  # --- xorriso: needed on THIS machine, not on Proxmox ------------------------
  if command -v xorriso >/dev/null 2>&1; then
    pass "xorriso present (Packer builds cd_files ISOs locally)"
  else
    warns "xorriso not found"
    hint "Packer's cd_files/cd_content images are built on the PACKER HOST, not"
    hint "on Proxmox. Without xorriso the Windows builds fail confusingly."
  fi
}

# =============================================================================
# 2. environment variables - shape, not just presence
# =============================================================================
readonly RE_UUID='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
readonly RE_USERID='[A-Za-z0-9._-]+@[A-Za-z0-9]+'
readonly RE_TOKENID='[A-Za-z0-9._-]+'

# PKR_VAR_* is what this repo's templates actually read, because they declare
# `proxmox_url`/`proxmox_username`/`proxmox_token` as HCL variables. The
# plugin-native PROXMOX_* spellings are accepted as a fallback so that a shell
# set up from the plugin's own documentation still passes.
PK_USER=""; PK_USER_VAR=""
PK_TOKEN=""; PK_TOKEN_VAR=""
PK_URL="";  PK_URL_VAR=""

resolve_packer_env() {
  if [[ -n "${PKR_VAR_proxmox_username:-}" ]]; then
    PK_USER="${PKR_VAR_proxmox_username}"; PK_USER_VAR="PKR_VAR_proxmox_username"
  else
    PK_USER="${PROXMOX_USERNAME:-}";       PK_USER_VAR="PKR_VAR_proxmox_username"
  fi
  if [[ -n "${PKR_VAR_proxmox_token:-}" ]]; then
    PK_TOKEN="${PKR_VAR_proxmox_token}";   PK_TOKEN_VAR="PKR_VAR_proxmox_token"
  else
    PK_TOKEN="${PROXMOX_TOKEN:-}";         PK_TOKEN_VAR="PKR_VAR_proxmox_token"
  fi
  if [[ -n "${PKR_VAR_proxmox_url:-}" ]]; then
    PK_URL="${PKR_VAR_proxmox_url}";       PK_URL_VAR="PKR_VAR_proxmox_url"
  else
    PK_URL="${PROXMOX_URL:-}";             PK_URL_VAR="PKR_VAR_proxmox_url"
  fi
}

check_env() {
  section "credential environment variables (shape, not just presence)"

  local bpg_ok=0 packer_secret_ok=0
  resolve_packer_env

  # ---- bpg / OpenTofu: ONE concatenated string ------------------------------
  if [[ -z "${PROXMOX_VE_API_TOKEN:-}" ]]; then
    fail "PROXMOX_VE_API_TOKEN is unset"
    hint 'expected shape: terraform@pve!provider=<uuid>   (one single string)'
  elif [[ "${PROXMOX_VE_API_TOKEN}" =~ ^${RE_USERID}\!${RE_TOKENID}=${RE_UUID}$ ]]; then
    pass "PROXMOX_VE_API_TOKEN has the bpg single-string shape"
    bpg_ok=1
  else
    fail "PROXMOX_VE_API_TOKEN is set but has the WRONG SHAPE"
    hint 'expected: user@pve!tokenid=<uuid>   (userid, "!", token id, "=", uuid)'
    if [[ "${PROXMOX_VE_API_TOKEN}" != *"="* ]]; then
      hint 'yours has no "=" - that is the Packer shape. bpg needs the secret'
      hint 'CONCATENATED onto the token id. This is the classic silent 401.'
    fi
  fi

  # ---- Packer: TWO separate values ------------------------------------------
  if [[ -z "${PK_USER}" ]]; then
    fail "${PK_USER_VAR} is unset"
    hint 'expected shape: packer@pve!buildtoken   (NO secret, NO "=")'
    hint 'PROXMOX_USERNAME is accepted as a fallback spelling.'
  elif [[ "${PK_USER}" =~ ^${RE_USERID}\!${RE_TOKENID}$ ]]; then
    pass "${PK_USER_VAR} has the Packer user!tokenid shape"
  else
    fail "${PK_USER_VAR} is set but has the WRONG SHAPE"
    hint 'expected: user@pve!tokenid   (no secret appended)'
    if [[ "${PK_USER}" == *"="* ]]; then
      hint 'yours contains "=" - that is the bpg shape. Packer takes the secret'
      hint "in ${PK_TOKEN_VAR} instead. Sharing one variable silently 401s."
    fi
  fi

  if [[ -z "${PK_TOKEN}" ]]; then
    fail "${PK_TOKEN_VAR} is unset"
    hint 'expected shape: a bare uuid, nothing else'
    hint 'PROXMOX_TOKEN is accepted as a fallback spelling.'
  elif [[ "${PK_TOKEN}" =~ ^${RE_UUID}$ ]]; then
    pass "${PK_TOKEN_VAR} is a bare uuid"
    packer_secret_ok=1
  else
    fail "${PK_TOKEN_VAR} is set but has the WRONG SHAPE"
    hint 'expected: <uuid> alone. Yours looks like it carries a user id or an "=".'
  fi

  # ---- Cross-check: only meaningful once both shapes are valid --------------
  if (( bpg_ok && packer_secret_ok )); then
    if [[ "${PROXMOX_VE_API_TOKEN##*=}" == "${PK_TOKEN}" ]]; then
      warns "${PK_TOKEN_VAR} and PROXMOX_VE_API_TOKEN carry the SAME secret"
      hint "That works, but the lab creates two separate tokens on purpose:"
      hint "packer@pve!buildtoken (build) and terraform@pve!provider (provision)."
      hint "Separate tokens mean a leaked build token cannot destroy the lab."
    else
      pass "the Packer and bpg credentials are two distinct secrets"
    fi
  fi

  # ---- Endpoints: the /api2/json asymmetry ----------------------------------
  if [[ -z "${PROXMOX_VE_ENDPOINT:-}" ]]; then
    fail "PROXMOX_VE_ENDPOINT is unset"
    hint 'expected: https://<host>:8006   (bpg appends /api2/json itself)'
  elif [[ "${PROXMOX_VE_ENDPOINT}" == *"/api2/json"* ]]; then
    fail "PROXMOX_VE_ENDPOINT must NOT contain /api2/json"
    hint "bpg builds the API path itself; including it produces 404s that look"
    hint "like the host is unreachable."
  elif [[ "${PROXMOX_VE_ENDPOINT}" =~ ^https?://[^/]+ ]]; then
    pass "PROXMOX_VE_ENDPOINT looks right (no /api2/json suffix)"
  else
    fail "PROXMOX_VE_ENDPOINT is not a URL: ${PROXMOX_VE_ENDPOINT}"
  fi

  if [[ -z "${PK_URL}" ]]; then
    # Not a hard failure: packer/common.pkrvars.hcl can supply proxmox_url
    # instead of the environment, and that is the documented default path.
    warns "${PK_URL_VAR} is unset"
    hint 'expected: https://<host>:8006/api2/json   (Packer wants the full path)'
    hint 'Fine to leave unset IF packer/common.pkrvars.hcl sets proxmox_url.'
  elif [[ "${PK_URL}" == *"/api2/json"* ]]; then
    pass "${PK_URL_VAR} includes /api2/json"
  else
    fail "${PK_URL_VAR} must END WITH /api2/json"
    hint "This is the mirror image of the PROXMOX_VE_ENDPOINT rule. The two"
    hint "tools disagree about the endpoint, and both are right for themselves."
  fi

  # ---- SSH user for snippet uploads -----------------------------------------
  if [[ -n "${PROXMOX_VE_SSH_USERNAME:-}" ]]; then
    pass "PROXMOX_VE_SSH_USERNAME=${PROXMOX_VE_SSH_USERNAME}"
  else
    warns "PROXMOX_VE_SSH_USERNAME is unset"
    hint "Snippets cannot be uploaded over the PVE API - bpg pivots to SFTP and"
    hint "needs a real PAM account. Every cloud-init resource will fail without it."
  fi

  # ---- State encryption passphrase ------------------------------------------
  if [[ -n "${TF_VAR_state_passphrase:-}" || -n "${TF_ENCRYPTION:-}" ]]; then
    pass "OpenTofu state encryption material is present"
  else
    warns "neither TF_VAR_state_passphrase nor TF_ENCRYPTION is set"
    hint "State holds cloud-init passwords and the firewall's WAN address in"
    hint "plaintext unless encryption is configured."
  fi
}

# =============================================================================
# 3-7. host checks
# =============================================================================
API_BASE=""
CURL_TLS=()
CURL_FAIL=(-f)

api_get() { # api_get <path> [auth-header-value]
  local path="$1"
  local auth="${2:-PVEAPIToken=${PROXMOX_VE_API_TOKEN:-}}"
  (( VERBOSE )) && printf '         %sGET %s%s%s\n' "$C_DIM" "$API_BASE" "$path" "$C_RESET" >&2
  curl -sS "${CURL_FAIL[@]}" --max-time "$API_TIMEOUT" "${CURL_TLS[@]}" \
    -H "Authorization: ${auth}" "${API_BASE}${path}" 2>/dev/null
}

setup_api() {
  resolve_packer_env   # idempotent; keeps PK_* defined even if check_env is reordered
  API_BASE="${PROXMOX_VE_ENDPOINT%/}"
  API_BASE="${API_BASE%/api2/json}/api2/json"

  # PVE puts the useful part of a 403 in the RESPONSE BODY
  # ("Permission check failed (/vms/9000, VM.Config.Disk)"). Plain -f throws
  # that away; --fail-with-body keeps it. It needs curl >= 7.76, so probe.
  if curl --help all 2>/dev/null | grep -q -- '--fail-with-body'; then
    CURL_FAIL=(--fail-with-body)
  else
    CURL_FAIL=(-f)
  fi

  CURL_TLS=()
  local insecure="${PROXMOX_VE_INSECURE:-true}"
  if [[ "${insecure,,}" == "true" || "${insecure}" == "1" ]]; then
    CURL_TLS=(-k)
  fi
}

check_api_reachability() {
  section "Proxmox API reachability and token validity"

  local out
  if out="$(api_get /version)"; then
    local rel
    rel="$(printf '%s' "$out" | jq -r '.data.version // .data.release // "unknown"')"
    pass "bpg token authenticates; PVE reports version ${rel}"
    case "${rel%%.*}" in
      5|6|7) fail "PVE ${rel} is not supported by bpg/proxmox - upgrade the host" ;;
      8)     warns "PVE 8.x: set min_tls = \"1.2\" in the OpenTofu provider block" ;;
      9)     : ;;   # the version this lab targets; TLS 1.3 default is correct
      *)     warns "PVE ${rel} is newer than this checklist knows about" ;;
    esac
  else
    fail "GET ${API_BASE}/version failed with PROXMOX_VE_API_TOKEN"
    hint "Either the host is unreachable, the certificate was rejected"
    hint "(set PROXMOX_VE_INSECURE=true for the lab's self-signed cert), or the"
    hint "token is wrong. A 401 here with a correctly shaped token usually means"
    hint "the token was created WITHOUT --privsep=0, in which case it inherits"
    hint "no privileges at all."
    return 1
  fi

  # Prove the Packer pair independently - assembled into the header shape.
  if [[ -n "${PK_USER}" && -n "${PK_TOKEN}" ]]; then
    if api_get /version "PVEAPIToken=${PK_USER}=${PK_TOKEN}" >/dev/null; then
      pass "Packer credential pair authenticates (username + token, assembled)"
    else
      fail "the Packer credential pair does not authenticate"
      hint "${PK_USER_VAR} and ${PK_TOKEN_VAR} are individually well-shaped but"
      hint "the host rejects them. Check that packer@pve!buildtoken exists and"
      hint "was created with --privsep=0."
    fi
  else
    skip "Packer credential pair not tested (variables unset)"
  fi
  return 0
}

check_snippets() {
  section "snippets content type on storage '${SNIPPET_STORE}'"

  local out
  if ! out="$(api_get "/storage/${SNIPPET_STORE}")"; then
    fail "could not read storage '${SNIPPET_STORE}' from the API"
    return
  fi
  local content
  content="$(printf '%s' "$out" | jq -r '.data.content // ""')"
  if [[ -z "$content" ]]; then
    fail "storage '${SNIPPET_STORE}' returned no content list"
  elif printf '%s' "$content" | tr ',' '\n' | grep -Fqx snippets; then
    pass "storage ${SNIPPET_STORE} allows snippets (content=${content})"
  else
    fail "storage ${SNIPPET_STORE} does NOT allow snippets (content=${content})"
    hint "Fix on the host:  pvesm set ${SNIPPET_STORE} --content ${content},snippets"
    hint "Without it every cloud-init user-data resource fails."
  fi
}

check_bridges() {
  section "host bridges"

  local out
  if ! out="$(api_get "/nodes/${PVE_NODE}/network")"; then
    fail "could not read the network configuration of node ${PVE_NODE}"
    return
  fi

  local br
  for br in "${REQUIRED_BRIDGES[@]}"; do
    if printf '%s' "$out" | jq -e --arg i "$br" '.data[] | select(.iface == $i)' >/dev/null 2>&1; then
      local addr active
      addr="$(printf '%s' "$out" | jq -r --arg i "$br" '.data[] | select(.iface==$i) | .cidr // .address // ""')"
      active="$(printf '%s' "$out" | jq -r --arg i "$br" '.data[] | select(.iface==$i) | .active // 0')"
      if [[ "$active" == "1" || "$active" == "true" ]]; then
        pass "${br} present and active${addr:+ (${addr})}"
      else
        warns "${br} is declared but not active${addr:+ (${addr})}"
        hint "Run 'ifreload -a' on the host, or reboot it."
      fi
      if [[ "$br" == "vmbr9" ]]; then
        if [[ "$addr" == 10.99.0.1* ]]; then
          pass "vmbr9 carries the build-plane address 10.99.0.1"
        else
          fail "vmbr9 address is '${addr:-none}', expected 10.99.0.1/24"
          hint "The build plane must be 10.99.0.0/24. Proxmox's own masquerade"
          hint "example uses 10.10.10.1/24 - that is fw-01's LAN address here."
        fi
      fi
    else
      fail "${br} does not exist on node ${PVE_NODE}"
      hint "Run scripts/bootstrap-host.sh on the host."
    fi
  done
}

check_templates() {
  section "golden template VMIDs declared in lab.yaml"

  local out
  if ! out="$(api_get "/nodes/${PVE_NODE}/qemu")"; then
    fail "could not list VMs on node ${PVE_NODE}"
    return
  fi

  local name vmid
  while read -r name vmid; do
    [[ -n "$name" ]] || continue
    if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
      fail "template '${name}' has a non-numeric VMID in lab.yaml: '${vmid}'"
      continue
    fi
    local row
    row="$(printf '%s' "$out" | jq -c --argjson v "$vmid" '.data[] | select(.vmid == $v)')"
    if [[ -z "$row" ]]; then
      fail "template ${name} (VMID ${vmid}) does not exist on ${PVE_NODE}"
      hint "Build it:  packer build packer/${name}/"
      continue
    fi
    local is_tpl tpl_name
    is_tpl="$(printf '%s' "$row" | jq -r '.template // 0')"
    tpl_name="$(printf '%s' "$row" | jq -r '.name // "?"')"
    if [[ "$is_tpl" == "1" || "$is_tpl" == "true" ]]; then
      pass "template ${name} -> VMID ${vmid} exists and is a template (${tpl_name})"
    else
      fail "VMID ${vmid} exists as '${tpl_name}' but is NOT flagged as a template"
      hint "OpenTofu's clone{} block will fail. Convert it, or rebuild with Packer."
    fi
  done < <(yaml_block_map templates)
}

check_isos() {
  section "manually-acquired ISO shelf on storage '${ISO_STORE}'"

  local -a want=()
  local from_lab=0
  while read -r line; do
    [[ -n "$line" ]] && { want+=("$line"); from_lab=1; }
  done < <(yaml_block_list iso_shelf)

  if (( ! from_lab )); then
    want=("${DEFAULT_ISO_SHELF[@]}")
    warns "lab.yaml has no 'iso_shelf:' block; using this script's built-in list"
    hint "The built-in list is what this repo expects the media to be NAMED."
    hint "If your files are named differently, add an iso_shelf: list to lab.yaml"
    hint "and keep it in step with docs/proxmox/iso-shelf.md."
  fi

  local out
  if ! out="$(api_get "/nodes/${PVE_NODE}/storage/${ISO_STORE}/content?content=iso")"; then
    fail "could not list ISO content on storage ${ISO_STORE}"
    return
  fi

  local present
  present="$(printf '%s' "$out" | jq -r '.data[]?.volid // empty' | sed 's#.*/##')"

  local iso missing=0
  for iso in "${want[@]}"; do
    if printf '%s\n' "$present" | grep -Fxq "$iso"; then
      pass "ISO present: ${iso}"
    else
      fail "ISO missing from ${ISO_STORE}: ${iso}"
      missing=$(( missing + 1 ))
    fi
  done

  if (( missing )); then
    hint "Windows Server 2022 Eval, Windows 11 Eval and OPNsense are MANUALLY"
    hint "acquired: the Windows images are registration-gated and OPNsense ships"
    hint "a .bz2 that Packer cannot boot (decompress it first). There is no URL"
    hint "to automate. See docs/proxmox/iso-shelf.md."
  fi
}

# =============================================================================
# main
# =============================================================================
main() {
  parse_args "$@"

  printf '%s%sMutaSpace SOC Lab - preflight%s\n' "$C_BLD" "$C_BLU" "$C_RESET"
  printf '  repo    : %s\n' "$REPO_ROOT"
  printf '  mode    : %s\n' "$( (( OFFLINE )) && echo 'OFFLINE (host checks skipped)' || echo 'full' )"

  check_binaries

  local lab_ok=1
  load_lab_yaml || lab_ok=0

  check_env

  if (( OFFLINE )); then
    section "host checks"
    skip "API reachability          (--offline)"
    skip "snippets content type     (--offline)"
    skip "bridges vmbr1/vmbr2/vmbr9 (--offline)"
    skip "template VMIDs on host    (--offline)"
    skip "ISO shelf                 (--offline)"
  elif ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    section "host checks"
    fail "cannot run host checks without curl and jq"
  elif [[ -z "${PROXMOX_VE_ENDPOINT:-}" || -z "${PROXMOX_VE_API_TOKEN:-}" ]]; then
    section "host checks"
    fail "cannot run host checks: PROXMOX_VE_ENDPOINT / PROXMOX_VE_API_TOKEN missing"
  else
    setup_api
    if check_api_reachability; then
      check_snippets
      check_bridges
      if (( lab_ok )); then
        check_templates
        check_isos
      else
        skip "template and ISO checks (lab.yaml could not be read)"
      fi
    else
      skip "snippets / bridges / templates / ISOs (API unreachable)"
    fi
  fi

  # ---- summary --------------------------------------------------------------
  printf '\n%s%s-- summary%s\n' "$C_BLD" "$C_BLU" "$C_RESET"
  printf '  pass %d   fail %d   warn %d   skip %d\n' "$PASS_N" "$FAIL_N" "$WARN_N" "$SKIP_N"

  if (( FAIL_N )); then
    printf '\n%sFailed checks:%s\n' "$C_RED" "$C_RESET"
    printf '  - %s\n' "${FAILURES[@]}"
    printf '\nNot ready. Fix the above before running packer or tofu.\n'
    return 1
  fi

  if (( SKIP_N )); then
    printf '\n%sAll executed checks passed, but %d were skipped.%s\n' "$C_YEL" "$SKIP_N" "$C_RESET"
    printf 'A green offline run does NOT mean the host is ready.\n'
  else
    printf '\n%sReady.%s\n' "$C_GRN" "$C_RESET"
  fi
  return 0
}

main "$@"
