# =============================================================================
# templates.tf - prove the golden templates exist before cloning anything
# =============================================================================
#
# THE PROBLEM THIS SOLVES
#   OpenTofu clones VMs from templates that Packer built. If somebody has not run
#   Packer yet, or a template got renumbered, or a build failed halfway, the clone
#   fails - but it fails LATE, against the API, with a message about a VMID rather
#   than a message about the thing that is actually wrong. Worse, if some other VM
#   happens to occupy that VMID, the clone succeeds and produces the wrong machine.
#
#   So the templates are checked at PLAN time, before anything is touched, and the
#   error says what to do about it.
#
# WHY NOT JUST READ THE VMID OUT OF PACKER'S MANIFEST
#   Because it is tempting and it is a trap. Packer's manifest post-processor
#   records the template's VMID, and feeding that straight into `clone { vm_id }`
#   looks like elegant plumbing. But the ENTIRE clone block is ForceNew - vm_id,
#   full, datastore_id, node_name and retries. A manifest-driven VMID means every
#   template rebuild destroys and recreates every VM that clones it, including the
#   domain controller holding the forest.
#
#   The two mechanisms therefore do different jobs. Packer PINS the VMID as a
#   contract. lab.yaml restates that contract as a constant. This file ASSERTS the
#   two agree. Nothing derives a clone target from a build artifact.
#

# -----------------------------------------------------------------------------
# What templates does the host actually have?
# -----------------------------------------------------------------------------
data "proxmox_virtual_environment_vms" "templates" {
  node_name = local.site.node

  # `template` is a boolean on the API side but the filter takes strings.
  filter {
    name   = "template"
    values = ["true"]
  }
}

locals {
  # VMIDs of every template on the node, as strings so `contains()` is unambiguous.
  discovered_template_vmids = [
    for vm in data.proxmox_virtual_environment_vms.templates.vms : tostring(vm.vm_id)
  ]

  # VMID -> name, so the error message can say what IS at that VMID rather than
  # only that something is wrong.
  discovered_template_names = {
    for vm in data.proxmox_virtual_environment_vms.templates.vms : tostring(vm.vm_id) => vm.name
  }
}

# -----------------------------------------------------------------------------
# The assertions
# -----------------------------------------------------------------------------
#
# `terraform_data` and not `null_resource`: null_resource is a provider resource
# from the hashicorp/null provider, needs a provider download, and is superseded.
# terraform_data is built into OpenTofu, creates nothing, and exists precisely to
# be a place to hang lifecycle rules on.
#
# One instance per template actually referenced by a VM, so an unused template
# entry in lab.yaml does not block a plan.
resource "terraform_data" "template_exists" {
  for_each = local.templates_in_use

  # Recorded in state so `tofu plan` shows the assertion changing if lab.yaml's
  # template numbering is edited - which is itself a useful warning.
  input = {
    template = each.key
    vm_id    = each.value
    name     = local.template_names[each.key]
  }

  lifecycle {
    precondition {
      condition = contains(local.discovered_template_vmids, tostring(each.value))
      error_message = join(" ", [
        "Template '${local.template_names[each.key]}' (VMID ${each.value}) does not exist on node '${local.site.node}',",
        "or exists but is not marked as a template.",
        "Build it with Packer before running OpenTofu.",
        "Do NOT 'fix' this by editing the templates: block in lab.yaml -",
        "the clone block is ForceNew, so changing a template VMID destroys and recreates every VM that uses it.",
      ])
    }

    # Second, quieter check: the right template is at the right number.
    #
    # This catches the genuinely nasty case where VMID 9002 exists and is a
    # template, so the check above passes, but it is the Kali image because two
    # Packer builds were run with their vm_id values transposed. The clone would
    # succeed and produce a domain controller that is actually Kali Linux.
    precondition {
      condition = (
        !contains(local.discovered_template_vmids, tostring(each.value)) ||
        local.discovered_template_names[tostring(each.value)] == local.template_names[each.key]
      )
      error_message = join(" ", [
        "VMID ${each.value} is a template, but it is named",
        "'${try(local.discovered_template_names[tostring(each.value)], "unknown")}' where lab.yaml expects",
        "'${local.template_names[each.key]}'. Two Packer builds have most likely been given each other's vm_id.",
        "Fix the Packer templates, not lab.yaml.",
      ])
    }
  }
}
