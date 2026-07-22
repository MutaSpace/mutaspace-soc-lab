# IaC Decisions

This document records the decisions made after the design research in [design.md](design.md) was
completed, and supersedes that document wherever the two disagree.

The design document was researched and written under the assumption that the lab was a **brownfield
estate** — six VMs already running on `mutaspace-soc-node01`, holding a live Active Directory forest
and indexed Wazuh alerts that the incident labs depend on. That assumption is no longer correct.

The design document is kept as written rather than rewritten, because the research behind it is
still valid and the brownfield analysis explains why several decisions were made the way they were.

---

## Decision Record

Decisions taken 2026-07-21.

| # | Question | Decision |
|---|---|---|
| **D-01** | Brownfield or greenfield? | **Greenfield.** A new Proxmox host is being built. Nothing is adopted. |
| **D-02** | Firewall platform | **Migrate to OPNsense 26.7.** |
| **D-03** | `dc-01` lifecycle | **Built from a Packer template.** Superseded by D-01. |
| **D-04** | `sensor-01` traffic visibility | **Suricata inline on the firewall.** |
| **D-05** | Proxmox host availability | Host is being built. IaC is authored offline first. |

---

## D-01: Greenfield Build

**Decision.** The lab is built from scratch on a new Proxmox host. No existing VM is imported.

**Why it matters.** This is the single most simplifying decision in the project.

The design document spends considerable effort on brownfield adoption: `import` blocks, `prevent_destroy`
guards, `protection = true`, an adopt-versus-reprovision decision for every VM, and a first
`tofu plan` that had to report `No changes.` before anything else could proceed. All of that work
existed to avoid destroying a running classroom.

None of it is needed now. Every VM is built from a template, which means every VM is reproducible,
which is the actual goal.

**What this removes from the design:**

- `tofu/adopted.tf` and `tofu/imports/brownfield.tf` are not written
- `prevent_destroy` is not needed on `fw-01`, `dc-01` or `wazuh-01`
- The `lifecycle: adopted` value in `lab.yaml` is dropped; every VM is `reprovisioned` or `linked`
- Risk R2 (adopt-or-rebuild `dc-01`) is closed
- Risk R5 (delete `test-client-01`) is closed — VM 101 will not exist on the new host
- Gaps G1 (`fw-01`'s VMID) and G2 (`win-client-01`'s VMID and specs) stop being archaeology and
  become design decisions: `fw-01` is 100, `win-client-01` is 105

**What this adds.** The Active Directory forest is no longer a thing that exists — it is a thing the
code must create. `mutaspace.local`, the `MUTASPACE` NetBIOS name, the reverse lookup zone
`10.10.10.in-addr.arpa`, and the lab accounts `test.user` and `lab.user02` that both completed
incident scenarios reference must all be built by Ansible.

This raises the stakes on `ansible/playbooks/90-lab-seed.yml`. It is not a convenience script. It is
the thing that makes
[failed-login-investigation.md](../incident-scenarios/failed-login-investigation.md) and
[account-creation-investigation.md](../incident-scenarios/account-creation-investigation.md)
reproducible on the new host. If it is wrong, two pieces of completed coursework stop working.

**Ordering consequence.** In a brownfield lab, `fw-01` already exists and everything else can be
built behind it. In a greenfield lab, nothing on `vmbr1` can reach anything until the firewall is
routing — so the hardest VM to automate is also the one that must come first.

This is why the build plane (`vmbr9`) matters more here than the design document implies. It is not
an optimization for Packer. It is the only way to build anything at all before the firewall exists.

---

## D-02: OPNsense 26.7

**Decision.** The firewall is rebuilt on OPNsense 26.7 rather than pfSense CE.

**Why.** pfSense CE 2.8.x has no downloadable ISO. Netgate publishes no standalone ISO or memstick
image for 2.8.0 or 2.8.1; the official mirror stops at 2.7.2-RELEASE. The only Netgate-provided
media for a fresh 2.8.x install is the Netgate Installer, a network installer obtained through a
store account, which fetches the operating system over the internet at install time.

There is no URL to pin, no stable checksum, and no answer file. A firewall built that way cannot be
described as reproducible, and reproducibility is the entire point of this exercise.

OPNsense publishes freely mirrored images with SHA256 checksums at stable URLs, and has a
first-party API, which means firewall rules and DHCP reservations can eventually be managed
declaratively rather than restored from an XML blob.

**A verified alternative existed and was rejected.** A fact-checker confirmed that installing pfSense
2.7.2 from its still-published offline ISO and upgrading in place to 2.8.1 is a real, Netgate
staff-endorsed path that needs no store account. That path was rejected because the upgrade step is
manual and unpinnable, which reintroduces exactly the problem being solved.

**What this costs.** Roughly ten documentation files change, and a semester of pfSense-specific
screenshots and muscle memory goes stale. That is a real cost to a teaching lab and it should be
stated plainly rather than minimized.

**What survives unchanged.** Every network fact in the existing documentation. Both platforms are
FreeBSD running `pf` on VirtIO NICs, so `vtnet0` and `vtnet1`, the LAN address `10.10.10.1/24`, the
DHCP pool `10.10.10.100–200`, the DNS and domain options handed to clients, and every recorded
validation output remain literally correct. The changes are a rewrite of
[fw-01-firewall-plan.md](../vms/fw-01-firewall-plan.md) plus a find-and-replace elsewhere.

**Honest caveat.** OPNsense has no official cloud-init. Its installer is interactive, and the config
importer needs a keypress and a device selection. Unattended install means a timing-sensitive Packer
`boot_command` driving a console, and that `boot_command` will break on version bumps. The firewall
remains the least automatable VM in the lab on either platform. OPNsense wins because the artifact
is pinnable, not because the install is clean.

---

## D-03: `dc-01` Built From a Template

**Decision.** Superseded by D-01. With a greenfield host there is no forest to adopt.

The original decision was to adopt the running domain controller and rebuild it at a semester
boundary, so that the rebuild was a planned exercise rather than an emergency triggered by the
Windows Server evaluation clock expiring.

That reasoning no longer applies, but the underlying licensing constraint does, and it does not go
away by being built from code:

- Windows Server 2022 Evaluation is a 180-day license, rearmable up to six times
- It must be activated over the internet within the first 10 days or it shuts down automatically
- `vmbr1` has no route out until `fw-01` is routing, so **the domain controller must be permitted
  outbound access during its first 10 days**

That last point is a firewall rule that has to exist in the IaC, and it sits in direct tension with
the "isolated lab" framing the network design is built around. It is worth teaching rather than
hiding.

The Windows evaluation ISOs are also registration-gated, so they cannot be fetched by URL. They are
manually acquired artifacts, recorded in `docs/proxmox/iso-shelf.md`. A fresh clone of this
repository cannot build the Windows templates without them, and that belongs in the README as a
first-class caveat rather than a footnote.

---

## D-04: Suricata Inline on the Firewall

**Decision.** Suricata runs on `fw-01` as an OPNsense plugin. `sensor-01` is not built as a separate
IDS VM in the first version.

**Why.** The network design left `sensor-01`'s placement explicitly undecided, and the reason it is
hard is worth stating: **a plain Linux bridge does not mirror traffic.** A promiscuous NIC attached
to `vmbr1` will not see unicast traffic flowing between two other VMs on that bridge. Attaching a
sensor to a bridge and expecting it to see everything is one of the most common mistakes in
virtualized lab design, and the lab would have hit it.

Running Suricata inline on the firewall sidesteps mirroring entirely. Every packet crossing between
network segments already passes through `fw-01` by design, so the sensor sees it without any host
networking changes.

**The limitation, stated honestly.** Inline placement sees only traffic that crosses the firewall.
It does not see east-west traffic between two VMs on the same LAN segment — so an attack from
`win-client-01` against `ubuntu-app-01`, both on `vmbr1`, is invisible to it.

That is a real detection gap and learners should be taught it rather than left to assume coverage.
It is also a genuinely good teaching moment about sensor placement, which is a real skill: the tool
matters less than where you put it.

**The upgrade path** is Open vSwitch with a mirror port feeding a dedicated capture NIC on a real
`sensor-01` VM. That sees east-west traffic and is the more realistic enterprise design. It is
deferred because it is a larger change to host networking, and host networking changes are the ones
most likely to break a class in progress.

---

## D-05: Offline-First Authoring

**Decision.** All infrastructure code is written and validated offline before the Proxmox host
exists.

**Why this is possible.** `tofu init` resolves and installs `bpg/proxmox v0.111.1` without a
Proxmox endpoint, and OpenTofu's `tofu test` with `mock_provider` runs a full plan against mocked
provider data with no host contact at all. `packer fmt` and `packer validate` check template syntax
the same way.

This means the parts of the design that can be verified without hardware genuinely are verified —
HCL syntax, module wiring, the VMID allocation policy, network placement assertions, and the
consistency between `lab.yaml` and the OpenTofu that consumes it.

**What cannot be verified until the host exists.** Everything that touches the API or the installer
media: the minimum privilege set for the API token, whether snippet updates change in place rather
than forcing VM recreation, whether the Packer plugin works against the installed Proxmox VE
version, and every `boot_command` in every template. Those are listed as risks in
[design.md](design.md) section 9 and are expected to need correction on first contact with real
hardware.

The goal of authoring offline is not to be right on the first apply. It is to make the first apply
fail for interesting reasons rather than for typos.

---

## Learning Reflection

Four of these five decisions were made by choosing the option that is *less capable but more
reproducible* — OPNsense over pfSense, inline Suricata over mirrored, greenfield over adoption.

That is a pattern worth naming, because it runs against the instinct that says the more capable
option is the better one. In a teaching lab, a component that can be rebuilt from source on demand
is worth more than a component that does more but exists only as a machine someone once configured
by hand.

The exception is the Windows evaluation licensing, which is not reproducible and cannot be made so.
The honest response there is to document the constraint clearly rather than to pretend the lab is
more reproducible than it is.
