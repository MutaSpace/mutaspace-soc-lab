# =============================================================================
# tests/vmid_policy.tftest.hcl - the numbering scheme is a contract, not a habit
# =============================================================================
#
# WHY VMIDs MATTER ENOUGH TO TEST
#   In most infrastructure a VM's internal identifier is an implementation detail
#   nobody should care about. Here it is a teaching artifact: documentation refers
#   to "VM 104", the reset scripts take a VMID as an argument, and a learner reading
#   `qm list` is supposed to be able to tell at a glance which machines are shared
#   infrastructure and which are their own.
#
#   The scheme:
#
#     100-199    core infrastructure
#     200-699    per-learner endpoints, 200 + (learner_index * 10) + role offset
#     800-899    scratch and smoke tests, never touched by this code
#     9000-9099  Packer golden templates
#
#   Two things make this worth enforcing rather than trusting.
#
#   First, `vm_id` is ForceNew. A number that drifts does not get corrected on the
#   next apply - it destroys the machine and builds a new one. On the domain
#   controller that is the forest.
#
#   Second, a VMID collision does not fail loudly. Proxmox will refuse the create,
#   but only after the plan looked fine and the apply had already done work; and if
#   the number collides with something outside this code entirely, the failure lands
#   somewhere else in the lab.
#

mock_provider "proxmox" {
  # The mock invents a value for every computed attribute, including the `id` of an
  # uploaded snippet - and it invents a random five-character string, which the
  # provider then rejects because a Proxmox file identifier has to look like
  # "datastore:content-type/filename". Giving it a well-formed one keeps the mock
  # honest without weakening anything the tests actually check.
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/mock-user-data.yaml"
    }
  }
}



variables {
  # Assert against the COMPLETE declared lab, not just whatever is switched on
  # today. During bring-up most machines carry enabled: false because their
  # templates do not exist yet - and if these checks only covered enabled
  # machines, switching one off would switch off the checks that protect it.
  assume_all_enabled = true

  state_passphrase = "offline-test-passphrase-not-a-secret"
  learner_count    = 3
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

run "every_vmid_sits_in_its_documented_range" {
  command = plan

  assert {
    condition = alltrue([
      for name, id in output.vm_ids :
      id >= 100 && id <= 199
      if output.vm_kinds[name] == "core"
    ])
    error_message = "A core infrastructure VM has a VMID outside 100-199. The ranges are what let somebody reading `qm list` tell shared infrastructure from learner machines without a reference sheet."
  }

  assert {
    condition = alltrue([
      for name, id in output.vm_ids :
      id >= 200 && id <= 699
      if output.vm_kinds[name] == "learner"
    ])
    error_message = "A learner endpoint has a VMID outside 200-699. Check learner_count and the vmid_offset values in lab.yaml's learner_endpoints block."
  }

  assert {
    condition     = alltrue([for key, id in output.template_ids : id >= 9000 && id <= 9099])
    error_message = "A golden template VMID is outside 9000-9099. Templates are numbered well clear of running machines so that rebuilding one can never collide with a VM somebody is using."
  }

  # Nothing this code manages may sit in the scratch range. 800-899 is where
  # smoke-test clones go - `qm clone 9000 899 --name smoke-test` - and the whole
  # value of a scratch range is being able to destroy anything in it without
  # checking first.
  assert {
    condition     = alltrue([for name, id in output.vm_ids : id < 800 || id > 899])
    error_message = "A managed VM is using a VMID in 800-899, the scratch range. That range must stay disposable: anything in it can be destroyed without checking what it was."
  }
}

run "no_two_machines_claim_the_same_number" {
  command = plan

  assert {
    condition     = length(distinct(values(output.vm_ids))) == length(values(output.vm_ids))
    error_message = "Two machines have been given the same VMID. Proxmox will refuse the second create, but only partway through an apply that has already built other things."
  }

  # A VM cannot share a number with a template. If it did, the clone would either
  # fail or - much worse - succeed against whatever happened to be there.
  assert {
    condition = length(setintersection(
      toset(values(output.vm_ids)),
      toset(values(output.template_ids)),
    )) == 0
    error_message = "A VM has been given the same VMID as a golden template. Templates and running machines share one number space in Proxmox."
  }

  # 107 is deliberately vacant. It was reserved for a standalone sensor-01 IDS VM,
  # which was dropped once it became clear a plain Linux bridge does not mirror
  # traffic - a promiscuous NIC on vmbr1 never sees unicast between two other VMs,
  # so the sensor would have watched almost nothing. Suricata runs inline on the
  # firewall instead.
  #
  # The gap is kept rather than closed up so the decision stays visible in `qm list`.
  # This assertion is not defending against a fault; it is defending a piece of
  # documentation that lives in the numbering.
  assert {
    condition     = !contains(values(output.vm_ids), 107)
    error_message = "VMID 107 is in use. It is deliberately reserved-and-empty: it was sensor-01's number, and the gap records that the standalone IDS was replaced by inline Suricata on fw-01. Pick another number."
  }
}

run "the_learner_vmid_formula_holds" {
  command = plan

  # 200 + (learner_index * 10) + role_offset, with win-client at offset 5 and kali
  # at 6. Learner 01 is index 0, so their machines are 205 and 206.
  #
  # Checked explicitly rather than by re-deriving the formula, because a test that
  # recomputes the thing it is testing proves nothing.
  assert {
    condition = alltrue([
      output.vm_ids["win-client-l01"] == 205,
      output.vm_ids["kali-l01"] == 206,
      output.vm_ids["win-client-l02"] == 215,
      output.vm_ids["kali-l02"] == 216,
      output.vm_ids["win-client-l03"] == 225,
      output.vm_ids["kali-l03"] == 226,
    ])
    error_message = "The learner VMID formula has drifted. Learner 01 must be 205/206, learner 02 215/216, learner 03 225/226 - ten VMIDs per learner keeps each learner's machines adjacent in `qm list` and leaves room for a third endpoint role later."
  }
}

run "learner_count_zero_builds_only_the_shared_core" {
  command = plan

  variables {
    learner_count = 0
  }

  # An instructor with a full host needs to be able to build the shared
  # infrastructure alone. If any part of the code assumed at least one learner, this
  # is where it would show up.
  assert {
    condition     = length([for name, kind in output.vm_kinds : name if kind == "learner"]) == 0
    error_message = "learner_count = 0 still produced learner machines."
  }

  assert {
    condition     = length([for name, kind in output.vm_kinds : name if kind == "core"]) == 9
    error_message = "The shared core is not nine machines. It should be fw-01, dc-01, analyst-01, wazuh-01, win-client-01, ubuntu-app-01, kali-01, untrusted-01 and nlp-01."
  }
}

run "an_oversized_class_is_refused_before_it_collides_with_the_dhcp_pool" {
  command = plan

  variables {
    learner_count = 25
  }

  # Learner addresses start at host .60 and step by 2, so learner 21 would be .100 -
  # the first address in the firewall's DHCP pool. A static mapping inside the pool
  # range is at best a warning and at worst refused outright.
  #
  # `expect_failures` inverts the test: this run PASSES because the validation
  # rejects the input. It is the only way to prove a guard actually guards.
  expect_failures = [var.learner_count]
}
