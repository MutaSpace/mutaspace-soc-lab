# =============================================================================
# access.tf - pools, a custom role, and who is allowed to touch what
# =============================================================================
#
# THE PROBLEM
#   A learner needs to be able to power-cycle their own machines and roll them back
#   to a clean baseline without asking an instructor, and without being able to do
#   the same to anybody else's - or to the domain controller.
#
#   Proxmox's own answer is pools plus ACLs, and it works well, but two of its
#   details are easy to get wrong and both are dangerous:
#
#   1. The built-in PVEVMUser role does NOT include VM.Snapshot or
#      VM.Snapshot.Rollback. Self-service reset is the entire point of handing a
#      learner these rights, so a custom role is unavoidable.
#
#   2. ACLs are path-scoped and a DEEPER path overrides a shallower one. Granting
#      at /pool/learner01 is correct; granting the same role at /vms or at / gives
#      every learner every machine in the lab, silently, and it will look like it
#      works because each learner can still see their own.
#

# -----------------------------------------------------------------------------
# Pools
# -----------------------------------------------------------------------------

# Everything that is shared. Grouping it means an instructor can see the lab's
# fixed infrastructure separately from the disposable per-learner machines, and it
# gives ACLs something to attach to if instructor accounts are added later.
resource "proxmox_virtual_environment_pool" "core" {
  pool_id = "mutaspace-core"
  comment = "Shared SOC lab infrastructure. Managed by OpenTofu from lab.yaml - do not add or remove members by hand."
}

# One pool per learner. This is the unit of ownership: the learner's VMs go in it,
# the learner's ACL is granted on it, and nothing else references it.
resource "proxmox_virtual_environment_pool" "learner" {
  for_each = { for l in local.enabled_learners : l.id => l }

  pool_id = "learner${each.key}"
  comment = "Endpoints belonging to learner ${each.key}: ${join(", ", each.value.endpoints)}."
}

# -----------------------------------------------------------------------------
# The role
# -----------------------------------------------------------------------------

resource "proxmox_virtual_environment_role" "learner_reset" {
  role_id = "MutaSpaceLearner"

  privileges = [
    # See the machine at all.
    "VM.Audit",

    # Use the noVNC console. This is what makes the lab usable when the learner has
    # just broken the machine's networking, which happens constantly and on purpose.
    "VM.Console",

    # Start, stop and reset.
    #
    # Note that this one is required for ROLLBACK too, not just for the power
    # buttons: since a late-2025 qemu-server change, rolling back with the start
    # flag checks VM.PowerMgmt up front. A role holding only VM.Snapshot.Rollback
    # can revert a machine and then be unable to turn it on.
    "VM.PowerMgmt",

    # Take a snapshot of their own work before trying something reckless.
    "VM.Snapshot",

    # Return to the instructor's baseline. The self-service reset.
    "VM.Snapshot.Rollback",
  ]
}

# Privileges deliberately NOT granted, and why:
#
#   VM.Config.*   A learner who can edit hardware can move their machine onto the
#                 management bridge, which is the one placement this entire
#                 repository is built to prevent.
#   VM.Allocate   Creating and destroying VMs is OpenTofu's job. A hand-made VM is
#                 invisible to the code and survives every rebuild.
#   VM.Clone      Cloning is how a 64 GB host quietly becomes a 96 GB host.
#   Sys.Console   Grants a root shell on the Proxmox node itself. It appears in a
#                 great many copy-pasted role definitions and it should not.
#   Datastore.*   No reason for a learner to touch storage.

# -----------------------------------------------------------------------------
# Users
# -----------------------------------------------------------------------------
#
# Created WITHOUT a password on purpose.
#
# A password in this file would be a committed credential, and a password passed in
# as a variable would land in the state file for every learner in the class. Neither
# is acceptable. The account exists here so the ACL below has something real to
# reference and so the roster is reproducible; the password is set once, by hand,
# out of band:
#
#   pveum passwd learner01@pve
#
# The provider does not manage what it did not set, so a hand-set password is not
# reverted on the next apply.
resource "proxmox_virtual_environment_user" "learner" {
  for_each = { for l in local.enabled_learners : l.id => l }

  user_id = "learner${each.key}@pve"
  comment = "MutaSpace SOC Lab learner ${each.key}. Password set out of band with 'pveum passwd'."
  enabled = true
}

# -----------------------------------------------------------------------------
# The grant
# -----------------------------------------------------------------------------

# `proxmox_acl`, not `proxmox_virtual_environment_acl`. The provider renamed most
# of its resources to short aliases and the long form is deprecated for removal in
# v1.0. The rename is a state-move, not a recreation - it is unrelated to the
# separate, deferred migration of the provider's internals.
#
# Note that this does NOT apply to virtual machines: `proxmox_vm` is flagged
# "DO NOT USE" and `proxmox_cloned_vm` is experimental and cannot manage cloud-init,
# which is the one thing this lab needs most. Machines stay on the long name.
resource "proxmox_acl" "learner" {
  for_each = { for l in local.enabled_learners : l.id => l }

  # Scoped to the learner's own pool and nowhere else. See the warning at the top
  # of this file about deeper paths overriding shallower ones.
  path = "/pool/${proxmox_virtual_environment_pool.learner[each.key].pool_id}"

  user_id = proxmox_virtual_environment_user.learner[each.key].user_id
  role_id = proxmox_virtual_environment_role.learner_reset.role_id

  # Applies to the VMs inside the pool, which is the whole point - the pool itself
  # is not a thing anybody wants to press buttons on.
  propagate = true
}
