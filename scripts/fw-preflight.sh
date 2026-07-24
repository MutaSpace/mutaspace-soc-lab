#!/usr/bin/env bash
# =============================================================================
# scripts/fw-preflight.sh
#
# WHAT THIS IS
#   The build-blocking gate for rebuilding the OPNsense template (VMID 9004,
#   tpl-opnsense-267 -> fw-01). It answers one question before anything
#   destructive runs: "if I bake fw-01's config.xml from the current .envrc,
#   will the firewall be reachable afterwards?"
#
#   It runs FROM THE WORKSTATION, needs NO Proxmox host, and exits non-zero the
#   instant any check fails, with a plain-English diagnosis.
#
# WHY IT EXISTS  (the failure it stops)
#   config.xml seeds the root account from TWO variables that must agree:
#     PKR_VAR_root_password        - typed at the installer console
#     PKR_VAR_root_password_hash   - baked into config.xml as the stored hash
#   If the hash is `openssl passwd -6` of a DIFFERENT string, the build
#   succeeds and the firewall boots, but the console password never matches the
#   baked hash --- a SILENT console lockout with no way back in short of a
#   template rebuild. HCL has no crypt(), so Packer cannot catch this itself and
#   `packer validate` cannot either (it only checks the vars are non-empty).
#   This script cryptographically cross-checks the pair, so the mismatch is
#   caught here instead of on a firewall nobody can log into.
#
#   It also checks PKR_VAR_root_authorized_keys looks like a real SSH PUBLIC
#   key (the value baked into <authorizedkeys>, which is what makes key-based
#   root SSH work from-scratch), and renders config.xml.pkrtpl.hcl locally to
#   confirm it is well-formed XML with a populated root <user> block.
#
# WHAT IT CHECKS
#   1. PKR_VAR_root_password is set and non-empty.
#   2. PKR_VAR_root_password_hash is set, non-empty, and looks like $6$ crypt.
#   3. crypt(root_password, root_password_hash) == root_password_hash
#      (python3's crypt.crypt --- the same algorithm openssl passwd -6 uses).
#   4. PKR_VAR_root_authorized_keys is set and looks like a public key
#      (an ssh-ed25519 / ssh-rsa / ecdsa-sha2-nistp{256,384,521} key type
#      followed by a space, so a bare "ecdsa-junk" is rejected).
#   5. RENDER: config.xml.pkrtpl.hcl renders to well-formed XML whose root
#      <user> block has a non-empty <authorizedkeys> and <password>. Catches a
#      template typo that packer validate would pass. Skips (does not fail) if
#      packer is not on PATH; skippable with --no-render.
#
# WHERE IT IS WIRED
#   `task fw:preflight` runs it directly, and `task build:opnsense` has it as a
#   hard precondition, so a rebuild refuses to start when this would fail. In
#   Wave 2 it also gates `qm destroy 9004` inside `task fw:rebuild-template`.
#
# USAGE
#   ./fw-preflight.sh --help
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT

readonly OPNSENSE_DIR="${REPO_ROOT}/packer/opnsense-267"
readonly SEED_TEMPLATE="${OPNSENSE_DIR}/config/config.xml.pkrtpl.hcl"

DO_RENDER=1

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GRN=$'\033[32m'
  C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_DIM=$'\033[2m'; C_BLD=$'\033[1m'
else
  C_RESET=''; C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_DIM=''; C_BLD=''
fi

FAIL_N=0
FAILURES=()

info() { printf '%s[ .. ]%s %s\n' "$C_BLU" "$C_RESET" "$*"; }
ok()   { printf '%s[ ok ]%s %s\n' "$C_GRN" "$C_RESET" "$*"; }
warn() { printf '%s[ !! ]%s %s\n' "$C_YEL" "$C_RESET" "$*" >&2; }
fail() { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; FAIL_N=$((FAIL_N+1)); FAILURES+=("$*"); }
die()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
hint() { printf '         %s%s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }

usage() {
  cat <<EOF
${SCRIPT_NAME} - build-blocking preflight for the OPNsense template rebuild

Runs on the WORKSTATION, needs no Proxmox host. Cross-checks the fw-01 root
password against its crypt hash, checks the root SSH public key is plausible,
and renders config.xml.pkrtpl.hcl to confirm it is well-formed XML. Exits
non-zero with a diagnosis on any failure. Wired as \`task fw:preflight\` and as
a hard precondition of \`task build:opnsense\`.

USAGE
  ./${SCRIPT_NAME} [options]

OPTIONS
  --no-render    Skip the rendered-config XML sanity check (checks 1-4 only).
  -h, --help     Show this help and exit.

READS (from the environment / .envrc)
  PKR_VAR_root_password         the firewall root password (console)
  PKR_VAR_root_password_hash    openssl passwd -6 of the SAME string
  PKR_VAR_root_authorized_keys  the root SSH PUBLIC key

SEE ALSO
  packer/opnsense-267/variables.pkr.hcl   the variables these feed
  .envrc.example section 6                 how to set them
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-render) DO_RENDER=0 ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "Unknown argument: $1  (see --help)" ;;
  esac
  shift
done

command -v python3 >/dev/null 2>&1 || die "python3 is required for the crypt cross-check but was not found on PATH."

printf '%s%s-- OPNsense template rebuild preflight%s\n' "$C_BLD" "$C_BLU" "$C_RESET"

# ---------------------------------------------------------------------------
# 1 + 2. The two root-password variables are present.
# ---------------------------------------------------------------------------
pw="${PKR_VAR_root_password:-}"
hash="${PKR_VAR_root_password_hash:-}"

if [[ -z "$pw" ]]; then
  fail "PKR_VAR_root_password is empty or unset."
  hint "Set it in .envrc (section 6) to the firewall's chosen root password."
else
  ok "PKR_VAR_root_password is set."
fi

if [[ -z "$hash" ]]; then
  fail "PKR_VAR_root_password_hash is empty or unset."
  hint 'Set it with: export PKR_VAR_root_password_hash="$(openssl passwd -6 <same password>)"'
elif [[ "$hash" != '$6$'* ]]; then
  fail "PKR_VAR_root_password_hash does not look like a SHA-512 crypt hash (it must start with \$6\$)."
  hint 'openssl passwd -6 produces $6$-prefixed hashes; a $1$/$5$/plain value here is wrong.'
else
  ok "PKR_VAR_root_password_hash is set and looks like a \$6\$ SHA-512 crypt hash."
fi

# ---------------------------------------------------------------------------
# 3. The hash actually verifies against the password.
#    This is the whole reason the script exists.
# ---------------------------------------------------------------------------
if [[ -n "$pw" && -n "$hash" ]]; then
  if PW="$pw" HASH="$hash" python3 -W ignore - <<'PY'
import os, sys
try:
    import crypt
except ModuleNotFoundError:
    # Python 3.13 removed the crypt module; fall back to passlib if present.
    try:
        from passlib.hash import sha512_crypt
        pw, h = os.environ["PW"], os.environ["HASH"]
        sys.exit(0 if sha512_crypt.verify(pw, h) else 1)
    except Exception as e:
        sys.stderr.write(f"no crypt module and passlib unavailable: {e}\n")
        sys.exit(2)
pw, h = os.environ["PW"], os.environ["HASH"]
sys.exit(0 if crypt.crypt(pw, h) == h else 1)
PY
  then
    ok "The hash verifies against the password: crypt(root_password) == root_password_hash."
  else
    rc=$?
    if [[ $rc -eq 2 ]]; then
      fail "Could not run the crypt cross-check (no python crypt module and no passlib)."
      hint "Install passlib, or run this on a Python <3.13 with the crypt module."
    else
      fail "PKR_VAR_root_password_hash does NOT verify against PKR_VAR_root_password."
      hint "The hash is openssl passwd -6 of a DIFFERENT string than the password."
      hint 'Regenerate it: export PKR_VAR_root_password_hash="$(openssl passwd -6 "$PKR_VAR_root_password")"'
      hint "Baking these as-is is a SILENT console lockout after the rebuild."
    fi
  fi
else
  fail "Skipping the hash<->password cross-check because one of the two is missing (see above)."
fi

# ---------------------------------------------------------------------------
# 4. The root SSH public key is plausible.
# ---------------------------------------------------------------------------
key="${PKR_VAR_root_authorized_keys:-}"
if [[ -z "$key" ]]; then
  fail "PKR_VAR_root_authorized_keys is empty or unset."
  hint 'Set it with: export PKR_VAR_root_authorized_keys="$(cat ~/.ssh/mutaspace_lab_ed25519.pub)"'
  hint "Without it, <authorizedkeys> is baked empty and key-based root SSH does not work."
elif [[ ! "$key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))[[:space:]]+[A-Za-z0-9+/]{32,}=*([[:space:]]|$) ]]; then
  # PUBLIC-key SHAPE gate, checked FIRST and unconditionally: a known key type
  # followed by a real base64 body (>=32 chars). This rejects a PRIVATE key
  # (which starts with '-----BEGIN ... PRIVATE KEY-----', never this shape), a
  # file path, a bare type with no body, or an empty `cat` --- BEFORE ssh-keygen
  # ever sees it. Critical: ssh-keygen -l -f will happily fingerprint a PRIVATE
  # key, so gating on the public shape first is what stops a private key being
  # accepted and baked into <authorizedkeys> (a secret leak into build artifacts).
  fail "PKR_VAR_root_authorized_keys is not a one-line SSH PUBLIC key."
  hint "Expected 'ssh-ed25519 <base64...>' (or ssh-rsa / ecdsa-sha2-nistp{256,384,521}) WITH real key material."
  hint "A PRIVATE key (would LEAK a secret into the build!), a bare type with no body, a file path, or an empty \`cat\` are the usual causes."
elif command -v ssh-keygen >/dev/null 2>&1 \
     && ! ssh-keygen -l -f <(printf '%s\n' "$key") >/dev/null 2>&1; then
  # Shape is right; when ssh-keygen is present, make it confirm the body decodes.
  fail "PKR_VAR_root_authorized_keys has a public-key shape but ssh-keygen rejects the key material."
  hint "The base64 body is likely corrupt or truncated --- re-copy the .pub file exactly."
else
  ok "PKR_VAR_root_authorized_keys is a valid SSH public key."
fi

# ---------------------------------------------------------------------------
# 5. RENDER: the seed renders to well-formed XML with a populated root <user>.
# ---------------------------------------------------------------------------
render_check() {
  [[ -f "$SEED_TEMPLATE" ]] || { fail "Seed template not found: ${SEED_TEMPLATE}"; return; }

  if ! command -v packer >/dev/null 2>&1; then
    warn "packer is not on PATH --- skipping the rendered-config XML sanity check."
    return
  fi

  local out
  out="$(mktemp)"

  # `packer console` evaluates local.config_xml, which is templatefile() of the
  # seed --- so this renders the exact XML a build would bake. A template typo
  # that breaks the XML surfaces here even though `packer validate` (which only
  # produces the string) passes it.
  if ! ( cd "$OPNSENSE_DIR" && packer init . >/dev/null 2>&1; echo 'local.config_xml' | packer console . ) >"$out" 2>/dev/null; then
    fail "Could not render config.xml.pkrtpl.hcl (packer console failed)."
    hint "Run:  cd ${OPNSENSE_DIR} && echo 'local.config_xml' | packer console ."
    rm -f "$out"
    return
  fi

  local result
  if result="$(python3 - "$out" <<'PY'
import sys, json, xml.dom.minidom as m

raw = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
s = raw.strip()

# `packer console` prints local.config_xml as RAW multi-line XML (verified: the
# capture starts with "<?xml" and carries real newlines, not \n escapes). Guard
# anyway against a future packer / terraform-style console that prints an
# HCL/JSON-quoted scalar (surrounding quotes + escapes) by unquoting it first,
# so this check can never pass or fail for the wrong reason.
if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
    try:
        s = json.loads(s)
    except Exception:
        pass

# Packer redacts sensitive values (the password hash) as the literal token
# <sensitive> in console output; that is a display artifact of the console, not
# of the baked file. Swap it for a placeholder so the redaction is not itself a
# malformed tag to the XML parser. (Done here, in Python, so the script needs no
# GNU-specific `sed -i`.)
s = s.replace("<sensitive>", "REDACTED")

try:
    doc = m.parseString(s)
except Exception as e:
    print(f"XML-NOT-WELLFORMED: {e}")
    sys.exit(2)

def child_text(node, tag):
    els = node.getElementsByTagName(tag)
    if not els or not els[0].firstChild:
        return ""
    return (els[0].firstChild.nodeValue or "").strip()

root_user = None
for u in doc.getElementsByTagName("user"):
    if child_text(u, "name") == "root":
        root_user = u
        break
if root_user is None:
    print("NO-ROOT-USER")
    sys.exit(3)
if not child_text(root_user, "authorizedkeys"):
    print("EMPTY-AUTHORIZEDKEYS")
    sys.exit(4)
if not child_text(root_user, "password"):
    print("EMPTY-PASSWORD")
    sys.exit(5)
print("OK")
PY
  )"; then
    ok "config.xml renders to well-formed XML with a populated root <user> block."
  else
    fail "Rendered config.xml failed its sanity check: ${result}"
    case "$result" in
      XML-NOT-WELLFORMED*) hint "A template edit broke the XML structure --- check config.xml.pkrtpl.hcl." ;;
      EMPTY-AUTHORIZEDKEYS) hint "PKR_VAR_root_authorized_keys rendered empty in <authorizedkeys>." ;;
      EMPTY-PASSWORD)       hint "PKR_VAR_root_password_hash rendered empty in <password>." ;;
      NO-ROOT-USER)         hint "The root <user> block is missing from the rendered config." ;;
    esac
  fi
  rm -f "$out"
}

if (( DO_RENDER )); then
  render_check
else
  info "Skipping the rendered-config XML sanity check (--no-render)."
fi

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------
printf '\n'
if (( FAIL_N > 0 )); then
  printf '%s%s%d check(s) failed. Fix .envrc (section 6) before rebuilding fw-01.%s\n' \
    "$C_BLD" "$C_RED" "$FAIL_N" "$C_RESET" >&2
  exit 1
fi
printf '%s%sPreflight passed --- the fw-01 root password/hash/key are consistent.%s\n' \
  "$C_BLD" "$C_GRN" "$C_RESET"
exit 0
