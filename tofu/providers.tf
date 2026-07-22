# =============================================================================
# providers.tf - how OpenTofu talks to Proxmox
# =============================================================================
#
# WHY THIS FILE IS ALMOST EMPTY
#   Every credential is missing from it on purpose.
#
#   The bpg/proxmox provider reads its endpoint and its API token straight from
#   the environment, so the safest configuration is the one that does not mention
#   them at all. There is no attribute here for a token, which means there is no
#   line for somebody to accidentally fill in with a real one and commit.
#
#   Set these before running any tofu command (a gitignored .envrc plus direnv is
#   the usual way):
#
#     export PROXMOX_VE_ENDPOINT="https://<LAB_MANAGEMENT_IP>:8006/"
#     export PROXMOX_VE_API_TOKEN="terraform@pve!provider=<uuid>"
#     export PROXMOX_VE_SSH_USERNAME="terraform"
#     export TF_VAR_state_passphrase="<at least 16 characters>"
#
#   ONE TRAP WORTH SPELLING OUT. Packer and OpenTofu want the same Proxmox
#   credential in two different shapes, and mixing them up produces a bare 401
#   with no hint as to why:
#
#     Packer:    username = "packer@pve!buildtoken"     token = "<uuid>"
#     OpenTofu:  api_token = "terraform@pve!provider=<uuid>"   (ONE joined string)
#
#   They are also two different tokens for two different users. Do not try to
#   share one environment variable between the two tools.
#
#   Note also that the endpoint here has NO /api2/json suffix. Packer's endpoint
#   does. The two tools disagree and both are right for themselves.
#
provider "proxmox" {
  # endpoint  <- PROXMOX_VE_ENDPOINT
  # api_token <- PROXMOX_VE_API_TOKEN
  # Deliberately absent. See above.

  # Certificate verification is ON by default here, which is the opposite of most
  # Proxmox examples on the internet. A fresh Proxmox install presents a
  # self-signed certificate, so a lab will usually need this flipped to true in a
  # gitignored terraform.tfvars - but that should be a conscious act with a
  # comment next to it, not a default somebody inherits without noticing.
  insecure = var.pve_insecure

  # The provider defaults to requiring TLS 1.3. Proxmox VE 8.x hosts frequently
  # only offer TLS 1.2, and the resulting failure looks nothing like a TLS problem
  # - it looks like the host is down. Set this to "1.2" if that happens.
  min_tls = var.pve_min_tls

  ssh {
    # File uploads are the reason this block exists.
    #
    # Cloud-init snippets CANNOT be uploaded through the Proxmox API: the storage
    # upload endpoint only accepts iso, vztmpl and import content. The provider
    # silently falls back to SFTP over SSH for the `snippets` content type, which
    # means snippets.tf does not work at all without a working SSH path.
    #
    # `agent = true` uses the operator's running ssh-agent, so no private key is
    # ever read by OpenTofu, stored in state, or written into this repository.
    agent = true

    # SSH needs a real PAM (Linux) account on the node. An API token is not a
    # login. Left null so it falls back to PROXMOX_VE_SSH_USERNAME.
    #
    # Grant that account narrow sudo. The sudoers line that circulated in the
    # provider's own documentation for years was CVE-2026-25499: allowing
    # `tee /var/lib/vz/*` also allows `tee /var/lib/vz/../../../etc/sudoers.d/x`,
    # which is a straight path to root. The fixed form forbids "/" in the
    # filename character class:
    #
    #   terraform ALL=(root) NOPASSWD: /usr/sbin/pvesm, /usr/sbin/qm, \
    #     /usr/bin/tee /var/lib/vz/snippets/[a-zA-Z0-9_][a-zA-Z0-9_.-]*
    username = var.pve_ssh_username
  }
}
