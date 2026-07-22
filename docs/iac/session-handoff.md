# Session Handoff

This document captures the state of the Infrastructure as Code work so it can be picked up in a
fresh session with no prior context.

**Date:** 2026-07-22
**Branch:** `feat/infrastructure-as-code`
**Status:** Authored and validated offline. Never run against hardware.

---

## What Happened

The repository was documentation-only. It described a Proxmox SOC lab that had been built by hand
through the web interface and documented step by step.

The goal was to rebuild it as Infrastructure as Code using Proxmox, Packer and OpenTofu.

The work went in three stages:

1. **Research.** Ten parallel research threads investigated the tooling, each load-bearing claim
   was handed to a separate adversarial verifier whose job was to refute it, and a second model
   reviewed the repository independently as a cross-check. Several widely-repeated claims were
   refuted; corrections are marked `[verifier]` in [design.md](design.md).
2. **Decisions.** Six blocking questions were answered by the lab owner. See
   [decisions.md](decisions.md), which supersedes the design document wherever they disagree.
3. **Implementation.** Seven subsystems authored in parallel under strict file ownership, then
   audited for toolchain correctness, cross-file consistency and leaked secrets, then fixed.

---

## The Decisions That Shape Everything

Read [decisions.md](decisions.md) for the full reasoning. In short:

| | Decision | Consequence |
|---|---|---|
| D-01 | **Greenfield build** | Nothing is adopted or imported. No `prevent_destroy`, no `import` blocks. The AD forest is something the code must *create*, which makes `90-lab-seed.yml` load-bearing |
| D-02 | **OPNsense 26.7**, not pfSense | pfSense CE 2.8.x has no downloadable ISO. Costs a rewrite of the firewall docs |
| D-03 | `dc-01` built from a Packer template | Windows evaluation licensing is now an architectural constraint, not a footnote |
| D-04 | **Suricata inline on the firewall** | No `sensor-01` VM. Real gap: it cannot see east-west traffic between two VMs on the same bridge |
| D-05 | Authored offline first | Everything verifiable without hardware is verified; nothing else is |

---

## What Exists

107 new files, roughly 19,500 lines.

| Path | Contents |
|---|---|
| `lab.yaml` | Single source of truth: every VM, VMID, IP, MAC. The one file a human edits |
| `packer/` | Six `proxmox-iso` templates producing VMIDs 9000–9005 |
| `tofu/` | One reusable `proxmox-vm` module, `for_each` over `lab.yaml`, and 11 offline tests |
| `ansible/` | Nine numbered playbooks, three roles, split bootstrap/domain Windows inventory |
| `scripts/` | `bootstrap-host.sh`, `preflight.sh`, learner snapshot/reset pair |
| `Taskfile.yml` | Single entrypoint; every operation named once |
| `docs/iac/` | This area: design, decisions, prerequisites, inventory, cross-check |

### The design detail worth knowing

`lab.yaml` is read by **both** `tofu/locals.tf` and the OPNsense Packer template. The firewall's
DHCP reservations and the VMs' pinned MAC addresses are therefore derived from one file rather than
maintained in two places.

This matters because the alternative failure is silent: a reservation that no longer matches the VM
it was written for produces a lab that looks correctly configured and does not work.

---

## What Is Actually Verified

Run and confirmed on 2026-07-22:

```
PASS  tofu fmt -check -recursive
PASS  tofu validate
PASS  tofu test                    11 assertions, mock_provider, no host contact
PASS  packer fmt -check -recursive
PASS  packer validate              6/6 templates, full validate with var files
PASS  bash -n                      every script
PASS  YAML parse                   every playbook, lab.yaml, Taskfile.yml
PASS  gitleaks                     clean tree, and still catches planted secrets
```

**This is a claim about internal consistency, not about whether the lab builds.** No line of this
code has touched a hypervisor.

---

## What Is NOT Verified

Everything that requires the Proxmox API or real installer media:

- The minimum API token privilege set. It is a synthesis, not a published specification. Proxmox
  returns clear `403 Permission check failed (<path>, <Priv>)` messages, so start narrow and add
  what it asks for
- Whether the Packer plugin works against the installed Proxmox VE version
- Every `boot_command` in every template. The OPNsense one is timing-sensitive by nature and is
  expected to need tuning
- Whether editing a cloud-init snippet updates in place or forces VM recreation
- The Windows Autounattend flows and VirtIO driver injection paths

Individual files carry `⚠️ UNVERIFIED OFFLINE` markers where a specific behaviour could not be
checked. Those markers are honest and should be resolved, not deleted.

---

## Next Steps

A base Proxmox host is available for testing.

```bash
# 1. On the Proxmox host, as root — detects the PVE version and branches on it
./scripts/bootstrap-host.sh

# 2. On the workstation
cp .envrc.example .envrc     # fill in, then: direnv allow
task preflight               # expect failures; that is the point

# 3. First real build — the compatibility test for the whole stack
task build:ubuntu            # produces template 9000

# 4. Smoke test the clone path before trusting it
qm clone 9000 899 --name smoke-test --full 1 && qm start 899
```

**Expect the first run to fail on the API token privileges.** That is the known-weakest assumption
in the design and the error messages are specific enough to fix it directly.

Build order after that: Ubuntu template → OPNsense/`fw-01` (nothing routes until it exists) →
Windows templates → `dc-01` and Active Directory → the Linux estate → `win-client-01` → the
research plane.

---

## Known Gaps and Loose Ends

| Gap | Detail |
|---|---|
| `dc-01` disk/NIC changed | The code uses `virtio-scsi-single` + `virtio`. The existing build doc records SATA + E1000, which was a workaround for missing drivers during a manual install. Packer injects those drivers, so the workaround is gone — but `docs/vms/dc-01-domain-controller-build.md` now describes something the code no longer produces and needs a note |
| Firewall docs still say pfSense | Per D-02 the platform is OPNsense. `docs/vms/fw-01-firewall-plan.md` needs a rewrite; roughly nine other files need a find-and-replace. Every network fact survives unchanged — both platforms are FreeBSD/pf on VirtIO |
| `sensor-01` is not built | Per D-04, Suricata runs inline on the firewall instead. The README's "Planned Architecture" table still lists it |
| README naming | The README calls the analyst workstation `ubuntu-analyst-01`; every build doc and both incident scenarios call it `analyst-01`. The code uses `analyst-01` |
| gitleaks tradeoff | The documented `10.0.0.x` example subnet is allowlisted inside `.example` files. It is RFC1918 and already published in the README, but that specific rule will not fire there. Credentials still will — verified with planted secrets |
| Windows/OPNsense ISOs | Manually acquired. A fresh clone cannot build those three templates |

---

## For the Live Demo

The demo is intended to show instructors how Claude Code helps automate this kind of work,
including the failures.

Worth showing:

- **`lab.yaml`** — the whole lab in one readable file, and the fact that two different tools read it
- **`tofu test`** — 11 assertions that run with no hypervisor, including "no VM except the firewall
  may touch the WAN bridge". This is the safety net that replaces having a second Proxmox host
- **`task preflight` failing** — it is designed to fail clearly and say what to fix
- **The `⚠️ UNVERIFIED OFFLINE` markers** — an honest artifact of building without hardware
- **The credential shape trap** in [prerequisites.md](prerequisites.md) — a correct credential in
  the wrong format returns a bare `401`

The most useful thing to demonstrate is probably the first failure, whatever it turns out to be.
Automation that works on the first try teaches nothing about how to debug automation.

---

## Learning Reflection

This handoff exists because context runs out, and a project that only lives in one conversation is
not reproducible — which is the same argument the repository makes about a lab that only lives on
one machine.

The honest summary is that the research and the code are both in reasonable shape, and neither has
met reality yet. The gap between "validates cleanly" and "works" is where the actual learning in
this project is going to happen, and it is worth documenting as carefully as everything that came
before it.
