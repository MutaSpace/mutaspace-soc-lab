# =============================================================================
# versions.tf - engine version, provider pin, and state encryption
# =============================================================================
#
# WHY THIS FILE EXISTS
#   Three things that must be nailed down before a single resource is declared:
#   which OpenTofu, which Proxmox provider, and how the state file is protected.
#   All three are the kind of decision that is invisible when it is right and
#   ruinous when it is wrong, so each one carries its reasoning here rather than
#   in a commit message nobody will read again.
#
terraform {
  # ---------------------------------------------------------------------------
  # OpenTofu >= 1.12
  # ---------------------------------------------------------------------------
  # 1.12 rather than "any recent version" for concrete reasons:
  #   * `terraform_data` with `triggers_replace` - the supported replacement for
  #     `null_resource`, which this repository never uses.
  #   * `tofu test` with `mock_provider`, which is what lets the entire lab be
  #     validated offline with no Proxmox host in existence. See tofu/tests/.
  #   * native state encryption, configured below.
  required_version = ">= 1.12.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"

      # ---------------------------------------------------------------------
      # PINNED EXACTLY. Not "~> 0.111", not ">= 0.111".
      # ---------------------------------------------------------------------
      # In v0.109.0 the provider renamed `agent.wait_for_ip.enabled` to
      # `agent.wait_for_ip.disabled` - and inverted the meaning. A configuration
      # that was correct before the bump was silently backwards after it.
      #
      # A pessimistic constraint (`~> 0.111`) would have allowed that upgrade to
      # arrive on its own, in the middle of a semester, on a machine a class is
      # sitting in front of. An exact pin means provider upgrades are a decision
      # somebody makes deliberately, reads the changelog for, and tests.
      #
      # `.terraform.lock.hcl` is committed alongside this for the same reason.
      version = "0.111.1"
    }
  }

  # ---------------------------------------------------------------------------
  # State encryption
  # ---------------------------------------------------------------------------
  # This is not belt-and-braces. OpenTofu state stores every attribute of every
  # resource in cleartext by default, and this lab's state will contain the
  # firewall's WAN addressing (which is the operator's real home network) and any
  # guest credential that passes through `initialization`. A plaintext
  # terraform.tfstate in a public teaching repository is a leak waiting for one
  # careless `git add -A`.
  #
  # State is local rather than remote on purpose: one node, one operator, no
  # cluster. A remote backend here would be ceremony. Encryption is not.
  #
  # The passphrase comes from the environment - `export TF_VAR_state_passphrase=...`,
  # usually via a gitignored .envrc and direnv. It has no default, so forgetting it
  # is a loud error rather than a quiet downgrade to no encryption.
  encryption {
    key_provider "pbkdf2" "lab" {
      passphrase = var.state_passphrase

      # 600,000 iterations. The brief asks for at least 200,000; OWASP's current
      # PBKDF2-SHA512 guidance is 210,000 and this is a long-lived key derived
      # once per command, so the extra cost is unmeasurable and the margin is free.
      iterations    = 600000
      hash_function = "sha512"
      key_length    = 32
      salt_length   = 32
    }

    method "aes_gcm" "lab" {
      keys = key_provider.pbkdf2.lab
    }

    state {
      method = method.aes_gcm.lab
    }

    # The plan file is encrypted too. `tofu plan -out=tfplan` writes every value it
    # resolved, including the sensitive ones, so an unencrypted plan file leaks
    # exactly what an unencrypted state file leaks.
    plan {
      method = method.aes_gcm.lab
    }
  }
}
