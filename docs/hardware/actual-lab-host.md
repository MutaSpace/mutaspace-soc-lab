# Actual Lab Host

This document records the machine the Infrastructure as Code actually runs against, which is not
the machine described in [parts-list.md](parts-list.md).

Recorded 2026-07-22 from read-only inspection of the live host.

---

## Why This Document Exists

[parts-list.md](parts-list.md) describes a custom desktop PC built for this lab: a Ryzen 9 7900X
with 64 GB of RAM and a 2 TB NVMe drive. That machine is real and the reasoning behind it is sound.

It is not the machine the lab is being built on.

Rather than quietly editing the parts list to match, both are kept. The parts list records what was
planned and why; this document records what is actually there. Anyone reading the capacity
reasoning in [../iac/design.md](../iac/design.md) needs to know which set of numbers it was based
on, because several of its conclusions do not survive the change.

---

## Host Summary

| Item | Value |
|---|---|
| Hostname | `swc2026` |
| Management address | `<LAB_MANAGEMENT_IP>/24` on `vmbr0` (real value is gitignored, per the secrets policy) |
| Proxmox VE | **9.2.0** (pve-manager 9.2.2) |
| Base OS | Debian 13 (trixie) |
| Kernel | 7.0.2-6-pve |

---

## Hardware, Planned Versus Actual

| Component | Planned (parts-list.md) | Actual (`swc2026`) |
|---|---|---|
| CPU | AMD Ryzen 9 7900X — 12 cores / 24 threads | **Intel Core i9-12900H** — 14 cores / 20 threads |
| RAM | 64 GB DDR5 | **94 GB** |
| Storage | 2 TB NVMe Gen4 | **954 GB** Kingston NVMe |
| Network | Single onboard NIC | **Four NICs** (`nic0`–`nic3`) plus wifi |

### What each difference means

**The CPU is a mobile part.** The i9-12900H is a laptop/small-form-factor chip with 6 performance
cores and 8 efficiency cores. It has *fewer* threads than planned (20 versus 24), and it will
throttle under sustained load in a way a desktop 7900X does not. Packer building a Windows template
while Wazuh indexes is the workload most likely to expose this.

**There is more memory than planned**, which is genuinely useful. 94 GB against a design that
budgeted for 64 GB means the RAM pressure the design worried about is not a real constraint here.

**There is roughly half the storage**, and this is the constraint that actually bites. See below.

**There are three spare NICs.** The design assumed one, which is why it invents a masqueraded build
bridge (`vmbr9`) to give Packer internet access before the firewall exists. That design still works
and is still used. A spare physical NIC could later give `fw-01` a genuine physical WAN separate
from management, which would be closer to real enterprise topology. Deferred for now — see
[../iac/decisions.md](../iac/decisions.md).

---

## Storage Layout

```
nvme0n1  954 GB  Kingston OM8PGP41024Q-A0
  ├── pve/root     96 GB   ext4   -> Proxmox storage "local"      (ISOs, snippets, backups)
  ├── pve/swap      8 GB
  └── pve/data    816 GiB  LVM-thin -> Proxmox storage "local-lvm" (every VM and template disk)
```

There is **no second disk**. A 477 GB volume appeared during the first inspection and turned out to
be a USB Ventoy installer stick, which disconnected ten minutes later. It is removable media and
must not be used for Proxmox storage — a backup target that can be unplugged is not a backup
target.

### The capacity consequence

The design's capacity math assumed a **1.74 TiB** thin pool and concluded the lab would fit
comfortably. The real pool is **816 GiB**, which changes the answer.

VM disk sizes were reduced to fit:

| VM | Design | Actual | Reason |
|---|---|---|---|
| `wazuh-01` | 100 GB | **60 GB** | The one most likely to need raising again — the indexer grows with every alert |
| `dc-01` | 60 GB | **50 GB** | Windows Server plus AD needs far less than 50 GB |
| `win-client-01` | 60 GB | **50 GB** | Same |
| `nlp-01` | 80 GB | **40 GB** | Corpora can live on a share rather than the boot disk |
| learner `win-client` | full clone | **linked clone** | The largest single saving — see below |

Making the per-learner Windows endpoints linked clones rather than full clones saves roughly 150 GB
across three learners. The tradeoff is that linked clones pin their template: VMID 9003 cannot be
deleted or rebuilt while any learner clone exists, so rebuilding the Windows template means
destroying every learner endpoint first.

Resulting budget:

```
core VMs (9)                    360 GB
learner endpoints (all linked)  ~0 GB initially
golden templates (6, est.)      220 GB
                                ──────
realistic                       580 GB of 876 GB
worst case, fully allocated     850 GB of 876 GB
```

That leaves real headroom for snapshots, which matters because snapshots are the classroom reset
mechanism. **A full LVM-thin pool stalls or corrupts writes across every VM on the host at once**,
so `discard = "on"` is set on every disk and pool usage is worth watching.

---

## Host State at First Contact

| Check | Finding |
|---|---|
| Existing VMs | **None.** Zero VMs, zero containers — genuinely greenfield |
| Bridges | Only `vmbr0` (`<LAB_MANAGEMENT_IP>/24` on `nic0`). `vmbr1`, `vmbr2`, `vmbr9` absent |
| Snippets storage | **Not enabled** — `local` content is `iso,vztmpl,backup,import` |
| Repositories | **Enterprise repos active** — `pve-enterprise.sources` and `ceph.sources` both point at `enterprise.proxmox.com` and will fail without a subscription |
| NIC naming | The physical NIC really is called `nic0`, exactly as the earlier documentation said |

The last one is worth noting: `nic0` looked like a placeholder in the original documentation, and
it is not. It is the real interface name.

The snippets and repository findings are both things `scripts/bootstrap-host.sh` was written to fix,
which is a useful confirmation that the script is solving real problems rather than imagined ones.

---

## Management Network

The host sits on a management subnet that does not overlap any lab network:

| Plane | Subnet |
|---|---|
| Management / WAN | `<LAB_MANAGEMENT_SUBNET>` (gitignored) |
| SOC LAN | `10.10.10.0/24` |
| Isolated | `10.10.20.0/24` |
| Build plane | `10.99.0.0/24` |

No collisions, so no readdressing is needed.

---

## Learning Reflection

The gap between the planned host and the actual host is the most useful thing in this document.

The design was written carefully against a specific machine, and roughly a third of its capacity
reasoning stopped being true the moment it met different hardware. Not because the reasoning was
wrong, but because it rested on numbers nobody had checked against the machine that would actually
run it.

This is the ordinary condition of infrastructure work. The planning is still worth doing — the
storage problem was caught in ten minutes of read-only inspection precisely because the design had
already worked out what the numbers needed to be. A plan that gets contradicted by reality is doing
its job; a plan that never meets reality is the one to worry about.

The Ventoy drive is the sharper lesson. It presented as a 477 GB internal SATA disk, and the
decision to use it for backups was made and then withdrawn when inspection showed it was a
removable installer stick holding the ISO used to build this very host. Verifying before writing
cost one command. Formatting it would have cost the installer, the ISO library, and whatever else
was on it.
