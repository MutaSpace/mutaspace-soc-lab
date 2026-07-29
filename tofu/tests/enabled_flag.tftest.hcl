# enabled_flag.tftest.hcl
#
# WHAT THIS CHECKS
#   That `enabled: false` in lab.yaml actually removes a machine from the plan,
#   and - the part that matters more - that it also releases the template the
#   machine was holding.
#
# WHY IT MATTERS
#   The flag exists because template preconditions are all-or-nothing: until
#   every template referenced by an enabled machine exists on the host, NOTHING
#   can be applied, including machines whose own template is ready. Disabling the
#   machines you cannot build yet is what lets the lab come up in the order it is
#   actually built in.
#
#   That only works if disabling a machine genuinely drops its template from
#   templates_in_use. If it did not, the flag would look like it worked - the
#   machine would vanish from the plan - while the plan stayed blocked on a
#   template nothing was asking for any more. That failure would be confusing
#   enough to send someone editing VMIDs, which is the one thing lab.yaml warns
#   against, because the clone block is ForceNew.
#
#   These runs use the real lab.yaml rather than a fixture, so they also serve as
#   a live check on the current bring-up state.

variables {
  # Required by the root module. Named so it cannot be mistaken for a real one,
  # and allowlisted in .gitleaks.toml on that basis - these runs never touch a
  # host and never write state.
  state_passphrase = "offline-test-passphrase-not-a-secret"
  learner_count    = 3
}

mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/mock-user-data.yaml"
    }
  }
}

# The node-existence check in templates.tf asks the host what its nodes are
# called. Under mock_provider that list comes back EMPTY, which fails the check
# before any assertion below runs - so it has to be supplied here too.
#
# The name must match `site.node` in lab.yaml (or var.pve_node if the test sets
# it). That coupling is deliberate: if someone changes the committed node name
# without updating these mocks, the tests fail and say so, which is better than
# the tests silently passing against a name the real host does not have.
override_data {
  target = data.proxmox_virtual_environment_nodes.available
  values = {
    names = ["swc2026"]
  }
}

override_data {
  target = data.proxmox_virtual_environment_vms.templates
  values = {
    vms = [
      { vm_id = 9000, name = "tpl-ubuntu-server-2404", node_name = "swc2026", status = "stopped", template = true, tags = [] },
      { vm_id = 9001, name = "tpl-ubuntu-desktop-2404", node_name = "swc2026", status = "stopped", template = true, tags = [] },
      { vm_id = 9002, name = "tpl-win-server-2022", node_name = "swc2026", status = "stopped", template = true, tags = [] },
      { vm_id = 9003, name = "tpl-win11-client", node_name = "swc2026", status = "stopped", template = true, tags = [] },
      { vm_id = 9004, name = "tpl-opnsense-267", node_name = "swc2026", status = "stopped", template = true, tags = [] },
      { vm_id = 9005, name = "tpl-kali-rolling", node_name = "swc2026", status = "stopped", template = true, tags = [] },
    ]
  }
}

# ---------------------------------------------------------------------------
# With the flag honoured: only enabled machines are built.
# ---------------------------------------------------------------------------
run "a_disabled_machine_is_not_built" {
  command = plan

  variables {
    assume_all_enabled = false
  }

  # Nothing that lab.yaml disables may appear in the plan.
  assert {
    condition = length([
      for name in keys(output.vm_ids) : name
      if contains(output.disabled_vms, name)
    ]) == 0
    error_message = "A machine marked enabled:false in lab.yaml was still planned."
  }

  # The "and the disabled list is not silently empty" assertion that used to sit
  # here has been DELETED, on the instruction it carried: "If the lab is now fully
  # built, delete this assertion rather than weakening the one above."
  #
  # That day came on 2026-07-29. Template 9003 (Windows 11) was finally built, so
  # win-client-01 - the last core machine held back by a missing template - is
  # enabled, and output.disabled_vms is now empty. The assertion above is
  # consequently vacuous rather than wrong: it still fails correctly the moment
  # anything is disabled again, which is the case it exists for.
  #
  # Note that `learner_endpoints.win-client` remains enabled:false, deliberately -
  # those are LINKED clones and pin template 9003 so it cannot be rebuilt while
  # they exist. They do not appear in disabled_vms, which is why this assertion
  # went empty even though something in lab.yaml is still switched off.
}

# ---------------------------------------------------------------------------
# The real point: a disabled machine releases its template.
# ---------------------------------------------------------------------------
run "disabling_a_machine_releases_its_template" {
  command = plan

  variables {
    assume_all_enabled = false
  }

  # Every template still required must be required BY something that is enabled.
  # If this fails, the flag is removing machines but not their template holds,
  # and the plan will stay blocked for reasons that no longer exist.
  assert {
    condition = alltrue([
      for tpl in keys(output.templates_required) :
      contains(values(output.vm_templates), tpl)
    ])
    error_message = "A template is still required by the plan but no enabled machine uses it - enabled:false is not releasing template holds."
  }
}

# ---------------------------------------------------------------------------
# The escape hatch still works.
# ---------------------------------------------------------------------------
run "assume_all_enabled_restores_the_whole_lab" {
  command = plan

  variables {
    assume_all_enabled = true
  }

  # This is what lets the rest of the suite keep testing invariants across the
  # complete design while the lab is only partly built.
  assert {
    condition     = length(keys(output.vm_ids)) > length(output.disabled_vms)
    error_message = "assume_all_enabled did not restore the disabled machines."
  }

  assert {
    condition = alltrue([
      for name in output.disabled_vms : contains(keys(output.vm_ids), name)
    ])
    error_message = "assume_all_enabled=true must plan every machine lab.yaml declares, including the disabled ones."
  }
}
