# MutaSpace SOC Lab — Infrastructure as Code Design

**Document status:** design proposal, pre-implementation — **partly superseded, see below**
**Target repo:** `/home/profz/projects/mutaspace-soc-lab` (branch `main`, HEAD `f1150f8`)
**Written:** 2026-07-21
**Audience:** the person(s) who will write the HCL, YAML and playbooks from this document directly

---

## ⚠️ Read `decisions.md` first

This document is the *research output*. [`decisions.md`](decisions.md) is the *record of what was
actually decided afterwards*, and **where the two disagree, `decisions.md` wins.** It is kept here
unedited rather than rewritten, because the reasoning that led to a superseded conclusion is worth
more to a learner than a tidied-up document that hides it.

The five decisions that override text below:

| ID | Decision | What it supersedes here |
|---|---|---|
| D-01 | The build is **greenfield**, on a brand-new Proxmox host | §0 and §1 describe a brownfield estate with six running VMs to adopt. Nothing is adopted or imported; there is no `adopted.tf`, no `imports/`, no `prevent_destroy` |
| D-02 | The firewall is **OPNsense 26.7**, not pfSense | every mention of pfSense |
| D-03 | `dc-01` is built from a Packer template with **virtio-scsi-single + virtio NIC** | the SATA + E1000 hardware recorded in `docs/vms/`, which was a manual-install workaround, not a preference |
| D-04 | Suricata runs **inline on `fw-01`** as an OPNsense plugin | `sensor-01` and VMID 107 in Wave 6, and the `60-suricata.yml` playbook implied by Wave 6 — neither exists, because OPNsense is not in the Ansible inventory |
| D-05 | The code is **authored offline** and must pass `tofu validate` / `tofu test` / `packer validate` with no Proxmox host | the assumption throughout that a host is available to iterate against |

Two playbook names in the wave plan below were also renumbered during implementation:
`40-wazuh-agents.yml` became `50-wazuh-agents.yml`, and `50-detections.yml` became
`70-detections.yml`. `ansible/README.md` carries the authoritative run order.

---

## 0. Reading notes

Three inputs were synthesised: a citation-level repo inventory, a verified research digest (7 threads), and a completeness critique. **Where researchers and verifiers disagreed, the verifiers win** — every such correction is marked inline with `[verifier]`. Where nothing settled the question, it is stated as an open question in §9 rather than papered over.

Two facts dominate every decision below and should be read first:

1. **This is a brownfield estate, not a greenfield build.** Six VMs are running, `dc-01` holds a live AD forest, `wazuh-01` holds indexed alerts, and two completed incident labs depend on that state. The first `tofu apply` must not destroy coursework.
2. **The Proxmox VE version is never recorded anywhere in the repo** (`README.md:341`, `docs/proxmox/installation-and-access.md:27`). Every provider version, every privilege list, and every apt-source format in this document forks on PVE 8.x vs 9.x. **Establishing the host version is step zero and is blocking.**

---

## 1. Current State

### 1.1 Physical host

| Attribute | Value | Source |
|---|---|---|
| Hostname | `mutaspace-soc-node01` | `README.md:342`; `docs/proxmox/host-baseline.md:33` |
| Hypervisor | Proxmox VE — **version never stated** | `README.md:341` |
| CPU | AMD Ryzen 9 7900X — 12C / 24T | `docs/hardware/parts-list.md:48,54-55` |
| RAM | 64 GB DDR5 (2×32 GB, 2-DIMM for future 128 GB) | `docs/hardware/parts-list.md:76,80` |
| Storage | 1× Silicon Power 2 TB UD90 NVMe Gen4 | `docs/hardware/parts-list.md:99` |
| Filesystem | `ext4` (⇒ `local` + `local-lvm` LVM-thin) | `README.md:343`; `docs/proxmox/installation-and-access.md:74` |
| Install target | `/dev/nvme0n1` | `docs/proxmox/installation-and-access.md:53` |
| NIC | 2.5 GbE on-board; referred to only as `nic0` — **real ifname never recorded** | `docs/network/proxmox-bridge-plan.md:31-45` |
| Management | HTTPS :8006, static IP (value redacted by policy), `root@pam` | `docs/proxmox/installation-and-access.md:31,85,141` |

### 1.2 Network as built

| Bridge | Uplink | Subnet | Status |
|---|---|---|---|
| `vmbr0` | `nic0` | management/WAN — real value redacted, example `10.0.0.0/24` | **Built** |
| `vmbr1` | none | `10.10.10.0/24` SOC LAN | **Built** |
| `vmbr2` | none | isolated/untrusted | **Planned only — no doc records its creation** |

DHCP `10.10.10.100–.200` served by `fw-01`; DHCP hands DNS `10.10.10.10` (`dc-01`) and domain `mutaspace.local` — corrected after initially handing out pfSense itself (`docs/network/internal-dns-validation.md:186-198`).

### 1.3 VM inventory as built

| VM | ID | Guest OS | vCPU | RAM | Disk | Disk bus | NIC model | Bridge | IP | Wazuh agent |
|---|---|---|---|---|---|---|---|---|---|---|
| `fw-01` | **unknown (G1)** | pfSense CE, version unstated | 2 | 4 GB (raised from 2 GB) | 20 GB | — | — (implies VirtIO via `vtnet0/1`) | vmbr0 + vmbr1 | WAN example `10.0.0.x`, LAN `10.10.10.1` | No |
| `test-client-01` | 101 | "Ubuntu Linux", no version | 2 | 2 GB | 20 GB | — | — | vmbr1 | DHCP | No |
| `dc-01` | 102 | Windows Server **2022 Evaluation** | 2 | 4 GB | 60 GB | **SATA** (deliberate) | **E1000** | vmbr1 | `10.10.10.10` | Yes |
| `analyst-01` | 103 | Ubuntu **Desktop 24.04 LTS** | 2 | 4 GB | 40 GB | — | VirtIO | vmbr1 | DHCP | Yes |
| `wazuh-01` | 104 | "Ubuntu Server", version unconfirmed | 4 | 8 GB | 100 GB | — | VirtIO | vmbr1 | `10.10.10.20` | No (self) |
| `win-client-01` | **unknown, `105` inferred (G2)** | **unknown** | — | — | — | — | — | vmbr1 | DHCP | Yes |
| `ubuntu-app-01` | 106 | "Ubuntu Server", no version | 2 | 4 GB | 40 GB | — | VirtIO | vmbr1 | `10.10.10.30` | Yes |
| **Documented total** | | | **14** | **26 GB** | **280 GB** | | | | | 4 agents |

`ubuntu-app-01` runs OpenSSH + Nginx. `dc-01` is the forest root for `mutaspace.local` (NetBIOS `MUTASPACE`), GC enabled, RODC disabled, with A records for `wazuh-01` and `ubuntu-app-01` and a reverse zone whose **name is never recorded (G11)**.

### 1.4 Planned but never built

`sensor-01` (Suricata), `kali-01`, `untrusted-01`, `nlp-01`, the `vmbr2` bridge, `fw-01`'s third (OPT/DMZ) leg, Suricata, Sysmon, TheHive, Shuffle, Velociraptor, Zeek, Sigma, and **any code at all** — the repo contains zero source files despite the Definition of Done requiring a Python automation script (`README.md:462`).

### 1.5 Contradictions the IaC must resolve

| # | Contradiction | Resolution for IaC |
|---|---|---|
| C1 | `ubuntu-analyst-01` (README, network design) vs `analyst-01` (every build/agent doc) | **`analyst-01` wins.** Fix README + `network-design.md`. |
| C2 | `fw-01-firewall-plan.md` is filename-`plan`, content-`build` | Split into a real plan + build when the firewall is rewritten. |
| C3 | `fw-01` memory: table says 4 GB, narrative says raised 2048→4096 MB | **Provision 4096 MB.** |
| C4 | `fw-01` validation checklist "Pending", two other docs record all four "Passed" | Mark Passed; cite `dhcp-validation.md:179-185`. |
| C5 | Host baseline: storage / repo config / updates / dashboard / "Ready for VM planning" all **Pending** — yet six VMs exist | **Blocking.** Close these in Wave 1; they hold the facts IaC needs (§9 R1). |
| C6 | README "In Progress" stops at "web interface accessed" | Rewrite README status after Wave 1. |
| C7/C8 | `dc-01` plan says 2–4 vCPU / 4–6 GB / generic "Windows Server"; build says 2/4 GB / Server 2022 Eval | Target 2 vCPU / 4 GB; **flag the 180-day eval clock** (§7.5). |
| C9 | `wazuh-01` plan prefers Ubuntu 22.04 LTS, build records only "Ubuntu Server" | **Actual release is unknowable from the repo.** Pin **Ubuntu Server 24.04 LTS** going forward; record it. |
| C10 | Wazuh "8 GB minimum" provisioned as exactly 8 GB | Keep 8 GB but **fix the indexer heap** (§3, Wazuh row) — the installer leaves it at 1 GB. |
| C11 | 3 firewall legs planned, 2 built | Build the third leg (`vmbr2`/OPT) in Wave 5. |
| C12 | DHCP DNS server changed post-hoc to `10.10.10.10` | Encode the **final** state only. |
| C13 | Wazuh dashboard port "TBD", never resolved | It is **443** (the AIO installer sets `server.port: 443`, changeable with `-p`). Record it. |
| C14 | README calls Suricata a "Core Lab Tool"; `sensor-01` never built | Build `sensor-01` in Wave 6, or demote the claim. |

---

## 2. Target Architecture

### 2.1 Design principles

1. **Templates are cattle; three VMs are pets.** `fw-01`, `dc-01` and `wazuh-01` carry irreplaceable state (firewall ruleset, AD forest, indexed alerts). They are **adopted** by import and protected. Everything else is **reprovisioned** from a golden template.
2. **Three network planes.** Build traffic never touches `vmbr1`.
3. **Every address is deterministic** — static IPs where the docs already fixed them, and **pinned MACs + DHCP reservations** where DHCP is required, so detection-lab queries survive a rebuild.
4. **The internal `10.10.10.0/24` plane is hard-coded in the repo** (the existing docs already publish it in full); the **`vmbr0` / management plane is variables and secrets only** — this is the repo's binding placeholder policy (`README.md:347`).

### 2.2 Network diagram

```text
                         Home / upstream router
                                   |
                                   | (real subnet = <LAB_MANAGEMENT_IP>/24, never committed)
                          +--------+--------+
                          |  nic0 (enpXsY)  |   <-- real ifname UNRECORDED (G8)
                          +--------+--------+
                                   |
    ===============================+===============================  vmbr0
     |                                             |
     | Proxmox mgmt IP (on the bridge, not the NIC)|
     |                                             |
   [PVE host :8006]                          [ fw-01 net0 = WAN ]
                                                   |
                                             +-----+------------------+
                                             |  OPNsense / pfSense    |
                                             |  DHCP + DNS fwd + NTP  |
                                             +--+------------------+--+
                                 net1 = LAN    |                  |   net2 = OPT
    ===============================+===========+==========  vmbr1  |
     10.10.10.0/24  SOC LAN        |                               |
       .1  fw-01 (gw, DHCP, NTP)   |                               |
       .10 dc-01   AD DS + DNS     |                               |
       .20 wazuh-01 SIEM           |                               |
       .30 ubuntu-app-01           |                               |
       .40 sensor-01 (mgmt NIC)    |                               |
       .50 analyst-01   (DHCP res) |                               |
       .51 win-client-01(DHCP res) |                               |
       .100-.200 DHCP pool         |                               |
                                                                   |
    ===============================+===============================+  vmbr2
     10.10.20.0/24  ISOLATED / UNTRUSTED
       .1  fw-01 OPT (default-deny toward vmbr1)
       .10 kali-01        attack simulation
       .20 untrusted-01   trust-boundary research
       .30 nlp-01         phishing / NLP research

    ===============================================================  vmbr9
     10.99.0.0/24  BUILD PLANE (host-masqueraded, NO physical port)
       .1  PVE host      (iptables MASQUERADE -> nic0)
       .x  Packer build VMs + Packer HTTP seed server
       <-- exists ONLY so template builds can reach the internet
           without depending on fw-01 being up.
```

### 2.3 Bridge definitions (`/etc/network/interfaces`)

`vmbr9` is the piece nobody planned and everything depends on. Proxmox's own masquerade example uses `10.10.10.1/24` — **do not copy it verbatim, that is `fw-01`'s LAN address in this lab.**

```
auto vmbr9
iface vmbr9 inet static
        address  10.99.0.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0
        post-up   echo 1 > /proc/sys/net/ipv4/ip_forward
        post-up   iptables -t nat -A POSTROUTING -s '10.99.0.0/24' -o <nic0> -j MASQUERADE
        post-down iptables -t nat -D POSTROUTING -s '10.99.0.0/24' -o <nic0> -j MASQUERADE
        # If the PVE firewall is enabled, conntrack zones may also be required:
        # iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone 1
```

Apply with `ifreload -a` (ifupdown2, default since PVE 7). Do this **before** any VM exists on the bridge.

### 2.4 VMID allocation policy

`random_vm_ids` (bpg default range 10000–99999) is the wrong default for a single-node teaching lab — IDs are a teaching artifact here. Pin everything:

| Range | Purpose |
|---|---|
| `100–199` | Core infrastructure (adopted + reprovisioned) |
| `200–699` | Per-learner clones — `200 + (learner_index × 10) + role_offset` |
| `800–899` | Scratch / smoke-test range (never touches production IDs) |
| `9000–9099` | Packer golden templates |

`vm_id` is **ForceNew**. Never let it float.

### 2.5 Golden templates (Packer output)

| Template | VMID | Base media | Builder | Consumers |
|---|---|---|---|---|
| `tpl-ubuntu-server-2404` | 9000 | `ubuntu-24.04.4-live-server-amd64.iso` (pinned sha256 `e907d92e…`) | `proxmox-iso` | `wazuh-01`, `ubuntu-app-01`, `sensor-01` |
| `tpl-ubuntu-desktop-2404` | 9001 | `ubuntu-24.04.4-desktop-amd64.iso` (sha256 `3a4c9877…`) | `proxmox-iso` | `analyst-01` |
| `tpl-win-server-2022` | 9002 | **manually uploaded** eval ISO + `virtio-win-0.1.271` | `proxmox-iso` | `dc-01` (future rebuild only) |
| `tpl-win11-client` | 9003 | **manually uploaded** eval/VL ISO + virtio-win | `proxmox-iso` | `win-client-01` |
| `tpl-opnsense-267` | 9004 | `OPNsense-26.7-dvd-amd64.iso` (decompressed from `.bz2`) | `proxmox-iso` | `fw-01` (future rebuild only) |
| `tpl-kali-rolling` | 9005 | Kali installer ISO | `proxmox-iso` | `kali-01`, `untrusted-01` |

**Linked-clone constraint:** pve-docs states *"It is not possible to change the Target storage for linked clones, because this is a storage internal feature."* Packer must therefore write every template to **`local-lvm`** — the same datastore the clones live on — and the OpenTofu `clone` block must **omit `datastore_id` whenever `full = false`**.

### 2.6 Full target VM inventory

Bus/model are stated for every VM — the existing docs record a disk bus for exactly one VM (G3) and a NIC model for four (G4). These are decisions, not observations.

| VM | ID | Template | vCPU | RAM (ded/float) | Disk | Bus / controller | NIC | Bridge(s) | Address | Clone | Agent |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `fw-01` | **TBD → 100** | 9004 (future) | 2 | 4 GB / 0 | 20 GB | `scsi0`, virtio-scsi-single | virtio ×3 | vmbr0, vmbr1, vmbr2 | WAN var; `10.10.10.1`; `10.10.20.1` | **adopted** | No |
| `dc-01` | 102 | 9002 (future) | 2 | 4 GB / 0 | 60 GB | **`sata0`** (as built) | **E1000** (as built) | vmbr1 | `10.10.10.10` | **adopted** | Yes |
| `wazuh-01` | 104 | 9000 | 4 | 8 GB / **0** | 100 GB | `scsi0`, virtio-scsi-single | virtio | vmbr1 | `10.10.10.20` | **adopted** | No |
| `ubuntu-app-01` | 106 | 9000 | 2 | 4 GB / 4 GB | 40 GB | `scsi0` | virtio | vmbr1 | `10.10.10.30` | full | Yes |
| `sensor-01` | **107** | 9000 | 2 | 4 GB / 0 | 60 GB | `scsi0` | virtio ×2 (mgmt + capture) | vmbr1 (mgmt), capture leg | `10.10.10.40` | full | Yes |
| `analyst-01` | 103 | 9001 | 2 | 4 GB / 4 GB | 40 GB | `scsi0` | virtio, **pinned MAC** | vmbr1 | DHCP **reservation** `.50` | full | Yes |
| `win-client-01` | **105** | 9003 | 2 | 4 GB / 0 | 60 GB | `scsi0`, virtio-scsi-single | virtio, **pinned MAC** | vmbr1 | DHCP **reservation** `.51` | full | Yes |
| `kali-01` | **108** | 9005 | 2 | 4 GB / 4 GB | 40 GB | `scsi0` | virtio | **vmbr2** | `10.10.20.10` | linked | No |
| `untrusted-01` | **109** | 9005 | 2 | 2 GB / 2 GB | 20 GB | `scsi0` | virtio | **vmbr2** | `10.10.20.20` | linked | No |
| `nlp-01` | **110** | 9000 | 4 | 8 GB / 4 GB | 80 GB | `scsi0` | virtio | **vmbr2** | `10.10.20.30` | full | No |
| `test-client-01` | 101 | — | — | — | — | — | — | — | — | **DELETE** | — |

**Proposed specs for the four never-built VMs, with rationale:**

- **`sensor-01` (Suricata IDS)** — Ubuntu Server 24.04, 2 vCPU / 4 GB / 60 GB. Two NICs: `net0` on `vmbr1` for management (`10.10.10.40`, Wazuh agent, SSH), `net1` as the capture interface with **`firewall = false` on that NIC** — the per-NIC Proxmox firewall inserts an `fwbr/fwln/fwpr` veth chain and `macfilter` defaults to `1`, which drops exactly the mirrored/spoofed frames an IDS exists to see. ⚠️ **Placement is genuinely unresolved (G5).** A plain Linux bridge does not mirror: a promiscuous NIC on `vmbr1` will not see unicast between other VMs. Two viable designs, and this needs the owner's decision (§9 R4): (a) run Suricata **inline on `fw-01`** (OPNsense ships the Suricata plugin — simplest, no mirror needed, but only sees traffic crossing the firewall); (b) convert the SOC LAN segment to **Open vSwitch with a mirror port** feeding `sensor-01` — sees east-west traffic but is a bigger host-networking change.
- **`kali-01`** — Kali Rolling, 2 vCPU / 4 GB / 40 GB, `vmbr2` only. Linked clone (cheap, reset-often).
- **`untrusted-01`** — Kali/Debian minimal, 2 vCPU / 2 GB / 20 GB, `vmbr2` only, default-deny toward `vmbr1`. Deliberately the smallest VM in the lab; it exists to be a trust boundary, not to do work.
- **`nlp-01`** — Ubuntu Server 24.04, 4 vCPU / 8 GB / 80 GB, `vmbr2`. The 8 GB is for local model/corpus work. **This is the one VM with no bridge assignment anywhere in the docs (G21)**; `vmbr2` is the safe choice because phishing corpora are untrusted input.

### 2.7 Capacity math

**vCPU.** Host = 24 logical CPUs. PVE refuses to start any single VM configured above the host core count (`MAX 24 vcpus allowed per VM on this node`) — no VM here approaches that. Aggregate target = **24 vCPU across 10 VMs = 1.0× subscription**, which is comfortable for a lab where most VMs idle.

**RAM.**

| Set | Sum |
|---|---|
| Core teaching set (`fw-01`, `dc-01`, `wazuh-01`, `ubuntu-app-01`, `analyst-01`, `win-client-01`) | 28 GB |
| + `sensor-01` | 32 GB |
| + `kali-01`, `untrusted-01`, `nlp-01` | 46 GB |
| + PVE host reserve | ~4 GB |
| **All ten running** | **~50 GB of 64 GB — ~14 GB headroom** |

Levers, in order of safety:
- **Ballooning.** bpg's `memory { floating }` defaults to **0**, so ballooning is *off* unless you set `floating = dedicated`. Set floating on `analyst-01`, `ubuntu-app-01`, `kali-01`, `untrusted-01`, `nlp-01`. **Never balloon `wazuh-01`** — the indexer JVM commits its heap (`Xms == Xmx`), and reclaiming it forces swap or the OOM killer. Windows guests need the VirtIO Balloon driver **plus `blnsvr.exe`** (from `virtio-win-gt-x64.msi`) or they pin full dedicated RAM regardless of the HCL.
- **KSM.** Enabled by default in PVE. `[verifier]` The frequently-cited "~49% saving" figure is a **single credativ blog anecdote on PVE 8.2 with 8 idle identical clones**, not a specification — and PVE 9.2 deliberately makes the `mem`/`memhost` status properties ignore KSM, so you will not reproduce those numbers through the UI. Treat KSM as a bonus for identical learner clones, not as a planned budget line. Note the docs' security caveat: KSM can expose VMs to side-channel attacks.
- **Don't run everything.** The research plane (`kali-01`, `untrusted-01`, `nlp-01`, 14 GB) does not need to be on during a Wazuh detection lab. Model it as a `startup` order + an on/off flag in `lab.yaml`.

**Learner clones.** A full per-learner stack (own firewall + DC + Wazuh + endpoints ≈ 26 GB) caps this host at **two learners**. That is not a classroom. The only shape that scales here is **shared infrastructure + per-learner endpoint VMs**: one `win-client-01` clone (4 GB) + one `kali-01` linked clone (4 GB) = 8 GB per learner. With the core set at 32 GB and 4 GB host reserve, ~28 GB remains ⇒ **3 concurrent learners with private endpoints**, or the documented 4/6–8/10+ envelope (`docs/hardware/parts-list.md:172-177`) if learners share endpoints. The stated future 128 GB upgrade roughly triples this.

**Disk.** A default ext4 install on 2 TB yields `maxroot = min(hdsize/4, 96 GB)` ⇒ **~96 GB root LV (`local`)**, swap = 8 GB, `minfree` = 16 GB, and **~1.74 TiB LVM-thin pool (`local-lvm`)**.

| Consumer | Size |
|---|---|
| 10 target VMs, provisioned | 520 GB |
| 6 golden templates | ~250 GB |
| **Total provisioned on `local-lvm`** | **~770 GB of 1.74 TiB** — comfortable |
| ISO shelf on `local` (Win2022 ~5.5 GB, Win11 ~6.5 GB, 2× Ubuntu ~9 GB, virtio-win 0.7 GB, OPNsense 0.5 GB, Kali 4 GB) | **~26 GB of 96 GB** |

⚠️ **The `local` root LV is the real constraint, not the thin pool.** ISOs, snippets, snapshot `vmstate` and `vzdump` output all default to `local`. 26 GB of ISOs plus a couple of multi-GB RAM snapshots plus one full-VM backup will fill a 96 GB root. Mitigations, all required: set `vmstatestorage` explicitly, create a dedicated backup storage on `local-lvm` (or an external target), and **enable `discard = "on"` + `ssd = true` on every VM disk** — deleted guest blocks are otherwise never returned to the thin pool, and a full LVM-thin pool stalls or corrupts writes across *every* VM on the host.

---

## 3. Tooling Decisions

| # | Decision | Chosen | Alternatives considered | Why | Confidence |
|---|---|---|---|---|---|
| D1 | Proxmox provider | **`bpg/proxmox` pinned `= 0.111.1`** (2026-07-03) | `Telmate/proxmox` v3.0.2-**rc08** (RC since 2025-07, no stable 3.0.2 for a year); `danitso/proxmox` (unmaintained, bpg is its fork) | bpg is the de-facto provider, published identically to both registries, actively released. **Pin exactly, not `~>`**: v0.109.0 flipped `agent.wait_for_ip.enabled` → `.disabled` with *inverted semantics* less than two months ago. A semester must not be broken by a minor bump. | **High** |
| D2 | IaC engine | **OpenTofu ≥ 1.12** | Terraform 1.x; Ansible `community.proxmox.proxmox_kvm` only | Three reasons worth writing into the docs, because the research never justified the choice: (1) `tofu plan` is a *teaching artifact* — it shows students the diff before anything changes, which is literally the repo's stated principle "validation over assumptions"; (2) **native state encryption** (`terraform { encryption {} }` with a `pbkdf2` key provider), which plain Terraform lacks and this lab needs because generated passwords land in state; (3) **`tofu test` with `mock_provider`**, which enables offline CI against a host running live coursework. Ansible's `proxmox_kvm` is imperative with no plan phase. | **High** |
| D3 | Write-only attributes | **Do not rely on them** | — | `[verifier]` The bpg README claims OpenTofu 1.10+; that is **wrong** — ephemeral values and write-only attributes landed in **OpenTofu 1.11.0** (2025-12-09). Also, as of v0.111.1 the provider's write-only support is narrow (`acme_dns_plugin.data_wo`, `realm_openid.client_key_wo`, `metrics_server.influx_token`); the general ephemeral-resources issue #2432 is still open. | **High** |
| D4 | VM resource | **`proxmox_virtual_environment_vm` with a `clone {}` block** | `proxmox_cloned_vm` (new Framework resource); `proxmox_vm` | `proxmox_cloned_vm` is **EXPERIMENTAL** and *explicitly cannot manage* cloud-init/`initialization`, the QEMU guest agent, BIOS/machine/boot order, EFI disk or TPM. This lab clones a golden template and injects per-VM hostname/IP/users — that is exactly `initialization`. `proxmox_vm` is flagged **DO NOT USE**. `[verifier]` Note the two migrations are separate: the ADR-007 *name* rename (long→short aliases, a state-move, no recreation) is unrelated to the SDKv2→Framework *implementation* migration deferred to v1.0. Use short names (`proxmox_download_file`, `proxmox_sdn_vnet`, `proxmox_network_linux_bridge`) where they exist — but **not** for VMs. | **High** |
| D5 | Packer plugin | **`github.com/hashicorp/proxmox` `~> 1.2`** (resolves ≥1.2.3) | pin `= 1.2.4`; pin `= 1.2.2` | v1.2.4 shipped **2026-07-21 — the day of this research, zero field exposure**. v1.2.2 silently dropped `cpu_type` (fixed in 1.2.3). `~> 1.2` with a floor of 1.2.3 is the safe window. Revisit after a month. | **High** |
| D6 | Packer builder | **`proxmox-iso` for all templates** | `proxmox-clone` for per-role variants | `proxmox-clone` has a **known EFI-disk creation reliability issue** (special-cased in `step_start_vm.go`), its `disks` blocks *replace* the source template's disks, and open issue #309 suggests it cannot grow a cloned disk. Build golden images from ISO; do per-role differentiation in OpenTofu + Ansible, not in a second Packer pass. | **High** |
| D7 | ISO syntax | **`boot_iso { }` block**, never top-level `iso_file`/`iso_url`/`unmount_iso` | legacy top-level fields | Deprecated in v1.2.x (still work, emit removal warnings). Note the in-block key is `unmount`, **not** `unmount_iso`. Also: `additional_iso_files` blocks using `cd_files`/`cd_content` **must** set `iso_storage_pool` or `Prepare()` hard-fails. | **High** |
| D8 | Guest config | **cloud-init for Linux, Autounattend + Ansible for Windows, Ansible for everything stateful** | cloud-init only; Ansible only | cloud-init handles hostname/IP/user/SSH key/qemu-guest-agent at first boot. **There is no supported IaC provider for AD objects** — HashiCorp archived `terraform-provider-ad` on **2025-08-11** (it was always an "experimental technical preview"). AD DS promotion, DNS records, OUs, users, Wazuh rules and agent enrollment are Ansible's job: `microsoft.ad` **1.12.0** + `ansible.windows` **3.7.0** (both 2026-07-14). | **High** |
| D9 | Windows cloud-init | **Cloudbase-Init in the template, `ostype` set before `cipassword`** | WinRM/Ansible only; no cloud-init | `[verifier]` The widely-repeated "Proxmox Windows cloud-init is unsupported and passwords don't work" is **stale** — that FAQ page was last edited 2022-04-04. Proxmox added first-class Cloudbase-Init support in **qemu-server 8.2.2 (2024-07-12)** and the admin guide now has a dedicated "Cloud-Init on Windows" section. Passwords work via `cipassword` provided: (a) `ostype` is set to a Windows value **before** setting `cipassword` (otherwise PVE crypt-hashes it and Cloudbase-Init uses the hash as plaintext — this ordering trap is the origin of the folklore); (b) the guest's `cloudbase-init.conf` sets `inject_user_password = true`; (c) `ciuser` is ignored on Windows — the username lives in `cloudbase-init.conf`. Current stable installer is **`CloudbaseInitSetup_1_1_8_x64.msi` (2026-04-20)** — the "use the continuous build, stable is from 2020" advice is out of date. Still: use Cloudbase-Init for IP/hostname only and let **Ansible over WinRM** do real configuration. | **Medium** |
| D10 | **Firewall platform** | **OPNsense 26.7** — see §3.1 | pfSense CE 2.8.1; VyOS 1.5; Debian 13 + nftables | See below. | **Medium** |
| D11 | State backend | **Local state + OpenTofu native encryption**, `pbkdf2` key provider (≥16-char passphrase, ≥200k iterations, `aes_gcm` method) | S3-compatible remote; unencrypted local | Single node, single operator, no cluster ⇒ remote state is ceremony. Encryption is not optional: `initialization.user_account.password`, generated Wazuh passwords and the pfSense/OPNsense WAN address all land in plaintext state. Passphrase lives in a gitignored `.envrc` via `direnv`. | **High** |
| D12 | Secrets | **Env vars for credentials + gitleaks pre-commit + GitHub push protection** | committed `.auto.tfvars`; SOPS; Vault | `.auto.tfvars` / `.auto.pkrvars.hcl` are auto-loaded *by design*, which makes `git add -A` a one-keystroke leak. ⚠️ **The two tools want the same secret in different shapes:** Packer `username = "packer@pve!buildtoken"` + `token = "<uuid>"`; bpg `api_token = "terraform@pve!provider=<uuid>"` (one concatenated string). Sharing one variable silently 401s. Commit `.example` files only. | **High** |
| D13 | Wazuh version | **Pin 4.14.6** (2026-07-01) | 5.0 | `[verifier]` Wazuh 5.0 is **not GA** — latest pre-release is **v5.0.0-beta4, published 2026-07-21 12:27 UTC**. There is no 4.15 line. 5.0 **removes Filebeat** in favour of a native indexer connector, so it is a rewrite, not a version bump. Beta packaging exists at `packages-dev.wazuh.com/5.0/` but production automation must target 4.14.x. | **High** |
| D14 | Ansible inventory | **Static, committed inventory** + cloud-init `phone_home` as readiness signal | `local_file` generated from tofu outputs; `community.proxmox.proxmox` dynamic inventory | Every IP is deterministic (either static or a pinned-MAC reservation), so discovery is unnecessary. A `local_file` inside the same run creates a destroy-time chicken-and-egg and leaves stale files after a partial apply. `phone_home` is the clean "the VM is *done*, not just *pinging*" signal — it runs **after all other cloud-init modules complete** and POSTs `instance_id`, `hostname`, `fqdn` and the SSH **host public keys**, which also solves SSH TOFU for a classroom without `StrictHostKeyChecking=no`. | **High** |
| D15 | Snapshots/reset | **`qm snapshot`/`qm rollback` via script, not HCL** | a snapshot resource; `vzdump`/`qmrestore` | bpg **has no snapshot or rollback resource** in v0.111.1. Even a hand-rolled `terraform_data` version means the next apply that drops a VM also destroys the learner baseline. Use OpenTofu's built-in **`terraform_data` with `triggers_replace`** if a trigger must live in HCL — never `null_resource`. | **High** |
| D16 | Networking model | **Manual `vmbrX` bridges in `/etc/network/interfaces`** | Proxmox SDN simple/VLAN zones; VLAN-aware single bridge | SDN zone and VNet IDs are hard-capped at **8 characters** (deliberate, to leave room for autogenerated device names) — `soc-lan`/`isolated` barely fit and `untrusted` does not. SDN **IPAM/DHCP is still tech preview** in PVE 9.x. bpg SDN also requires a `proxmox_sdn_applier` "finalizer" dance with `depends_on` before *and* after VNet creation or config stays permanently pending. Plain bridges + pfSense/OPNsense DHCP is fewer moving parts and matches the existing docs. | **High** |
| D17 | Proxmox firewall | **Enable at datacenter + host level only; `firewall = false` on the sensor capture NIC; stay on the iptables backend** | nftables `proxmox-firewall`; leave disabled | nftables backend is still a **tech preview** in PVE 9.x. ⚠️ Write the management IP set and the :22/:8006 allow rules **before** setting `policy_in DROP`, or you lock yourself out of the classroom host mid-lesson. | **High** |

### 3.1 The firewall decision, in full

This is the least clear-cut call in the document and it deserves the argument rather than a verdict.

**What the research established about pfSense CE:**
- Netgate publishes **no standalone ISO or memstick for 2.8.0/2.8.1**. The official mirror stops at 2.7.2-RELEASE; 2.8.x filenames 404. The only Netgate-provided media for a fresh 2.8.x install is the **Netgate Installer**, a *network* installer obtained by $0.00 checkout with a Netgate Store Account, which fetches the OS over the internet at install time. There is no `iso_url` to pin, no stable checksum, no answer file.
- `[verifier]` The stronger phrasing "very unlikely to happen" came from a community member, not Netgate staff. Staff say: *"New 2.8 installs are via the Net Installer only... there is no 2.8.1 ISO/Memstick image available and it's unlikely there will be. But that doesn't mean the situation won't ever change."*
- `[verifier]` **A second, staff-endorsed path exists:** install **2.7.2 from its still-published offline ISO** and upgrade in place via System > Update. No store account needed. This materially weakens the "pfSense is un-automatable" headline.
- `[verifier]` **Two claimed ECL limitations are REFUTED.** The External Configuration Locator works on **GPT as well as MBR** (fixed in 2.5.0, commit `681d099`) and honours **both** `config.xml` at the drive root **and** `config/config.xml` (fixed in 2.4.4-p1, commit `c688c59`). Current `src/etc/rc.ecl` checks `array("/", "/config/")` and mounts msdosfs, ufs, cd9660 and udf.
- Still true: ECL runs on **every boot**, not just the first — leave the config drive attached and every reboot silently reverts everything students did in class. And the REST API package (`pfrest/pfSense-pkg-RESTAPI` v2.8.3) is **not in Netgate's repo**, so a config restore does *not* reinstall it — a genuine bootstrap ordering problem.

**What the research established about OPNsense:**
- Freely mirrored `dvd`/`vga`/`serial`/`nano` images with published SHA256 checksums and stable mirror URLs. `OPNsense-26.7-dvd-amd64.iso.bz2`, 26.7 released 2026-07-15, 26.7.1 on 2026-07-21.
- **First-party API** (basic auth, key/secret), and 26.1/26.7 migrated firewall rules, interface assignments and gateway groups to MVC/API — declarative management is genuinely good.
- **No official cloud-init.** The installer is interactive (`installer`/`opnsense`), and the config importer needs a keypress plus a device selection. Unattended install = Packer `boot_command` + a secondary FAT image containing `/conf/config.xml`. That `boot_command` is timing-sensitive and **will need re-tuning on every OPNsense version bump**.
- `browningluke/opnsense` OpenTofu provider is at v0.24.0 and **explicitly states it is not recommended for production**. Pin `= 0.24.0` exactly, never a range.

**Recommendation: migrate to OPNsense 26.7, but not in Wave 1.**

The honest framing is that **the firewall is the least automatable VM on either platform.** OPNsense wins on one decisive axis — the artifact is pinnable and checksummed, so "reproducible from source" is at least *approachable* — and on a second, softer axis: a first-party API means firewall rules, DHCP reservations and NTP settings can eventually be declarative rather than a blob of XML.

What it costs the existing docs (~10 files):
- **Full rewrite:** `docs/vms/fw-01-firewall-plan.md` → split into `fw-01-firewall-plan.md` + `fw-01-firewall-build.md`, resolving C2 in the process.
- **Find-and-replace only (~9 files):** every network fact survives unchanged. Both are FreeBSD/pf on VirtIO, so `vtnet0`/`vtnet1` interface names, `10.10.10.1/24`, the `10.10.10.100–200` pool, the DNS/domain DHCP options, and every validation output stay literally correct. Affected: `README.md`, `docs/network/{network-design,proxmox-bridge-plan,dhcp-validation,internal-dns-validation}.md`, `docs/vms/{test-client-01,analyst-01,wazuh-01,ubuntu-app-01}-build.md`.
- **Teaching cost:** a semester's worth of pfSense-specific screenshots and muscle memory. Non-trivial for a classroom.

**Sequencing that respects the brownfield reality:** keep the running pfSense box as an **adopted pet** through Waves 1–4 so the class is never broken. Build the OPNsense template in Wave 5, cut over during a break, and keep the pfSense VM (renamed, powered off, `protection = true`) as a rollback for one term.

**Rejected:** VyOS 1.5 Circinus — prebuilt LTS images and the official Proxmox qcow2 are **subscription-only**; free channels (Stream, nightly rolling) have URLs that 404 on every release; and it has **no web GUI at all**, which kills the GUI-driven firewall/DHCP/DNS teaching that is a stated learning goal. Debian 13 + nftables — trivially automatable (cloud image + cloud-init, zero extra providers) but hands you the job of rebuilding DHCP, DNS and a firewall UI yourself, which is the opposite of the lab's purpose.

---

## 4. Automation Feasibility Matrix

Blunt column: what stays manual, permanently.

| VM / artifact | Packer-able? | OpenTofu-able? | Ansible does | **Genuinely manual, forever** |
|---|---|---|---|---|
| `vmbr0/1/2/9` bridges | n/a | ⚠️ `proxmox_network_linux_bridge` exists (needs `Sys.Modify`) but **`ifreload` behaviour on apply is unconfirmed** | — | **Do bridges by hand, once, before VMs exist.** Modifying a live bridge's ports drops guest traffic. This is a 15-minute task that IaC makes riskier, not safer. |
| **`fw-01`** | ⚠️ OPNsense: yes with a fragile `boot_command`. pfSense CE 2.8.x: **no** — no pinnable ISO. | ✅ clone + NICs + `stop_on_destroy` | ⚠️ `oxlorg.opnsense` (renamed from `ansibleguy.opnsense`) or the first-party API for rules/DHCP/NTP | **The initial install.** Console keystrokes, WAN/LAN assignment, first admin password. Budget re-tuning the `boot_command` on every version bump. |
| **`dc-01`** | ⚠️ Only from a **manually uploaded** ISO — see §4.1 | ✅ clone (once a template exists); **adopted today** | ✅ `microsoft.ad.domain` (idempotent: installs `AD-Domain-Services` + `RSAT-ADDS` itself, calls `Install-ADDSForest` with `NoRebootOnCompletion=$true`, reboots via its own action plugin), `microsoft.ad.ou/user/group`, `ansible.windows.win_dns_record` | **ISO acquisition** (registration-gated) and **eval-clock management**. Reverse DNS zone creation is *not* module-covered — see §4.2. |
| **`wazuh-01`** | ✅ **and it must be** — bake the SIEM into the template | ✅ clone; **adopted today** | ✅ rules/decoders via API, agent groups, `agent.conf` | Initial dashboard password change (installer generates it into `wazuh-install-files.tar`). |
| `ubuntu-app-01` | ✅ | ✅ | ✅ nginx, sshd, Wazuh agent | none |
| `analyst-01` | ✅ (Ubuntu Desktop autoinstall is real — `source: id: ubuntu-desktop`) | ✅ | ✅ browser config, Wazuh agent | none |
| **`win-client-01`** | ⚠️ manual ISO; Autounattend via `cd_files` | ✅ | ✅ `microsoft.ad.membership` (renames + joins in one task), Wazuh agent MSI, Sysmon | **ISO acquisition.** ⚠️ Win11 Enterprise Evaluation is a **90-day timebomb, 2 rearms max (270 days), and cannot be converted in place** — a rebuild is required. Use a VL ISO + GVLK if you have one. |
| `sensor-01` | ✅ | ✅ | ✅ Suricata install + rules | **Traffic mirroring.** No amount of HCL makes a Linux bridge mirror. |
| `kali-01` / `untrusted-01` | ✅ | ✅ (linked clones) | ⚠️ minimal | none |
| `nlp-01` | ✅ | ✅ | ✅ | none |
| **Wazuh custom rules** | ❌ | ❌ | ✅ **This is the detection-as-code seam.** `PUT /rules/files/{filename}` (octet-stream, `overwrite`, `relative_dirname=etc/rules`) then **`PUT /manager/analysisd/reload`** — reloads the ruleset *without* a full manager restart. Prefer it: a restart drops all agent connections and re-queues events mid-class. | none |
| **AD objects** (`test.user`, `lab.user02`, OUs, GPO links) | ❌ | ❌ **no supported provider exists** | ✅ `microsoft.ad.*` | none |

### 4.1 The un-pinnable ISO problem (this is the honest headline)

**Two of the lab's core VMs cannot be built from a URL.**

- **Windows Server 2022 / Windows 11 evaluation ISOs** require registration before download and expose only `go.microsoft.com` redirect links behind that gate. There is no `iso_url` a Packer template can pin.
- **pfSense CE 2.8.x** has no published ISO at all (§3.1).

Consequences the plan must absorb, stated plainly:

1. Windows builds are `boot_iso { iso_file = "local:iso/..." }` against a **manually uploaded** file. `.gitignore` already blocks `*.iso`, so **a fresh clone of this repo cannot build the Windows templates.** That belongs in the README as a first-class caveat, not a footnote.
2. The repo needs a documented **"golden ISO shelf"** — `docs/proxmox/iso-shelf.md` — listing every manually-acquired artifact, where to get it, its SHA256, and where it lives on the host.
3. **The 180-day eval clock + the 10-day activation trap is an architectural constraint, not a licensing footnote.** Microsoft's Evaluation Center warns: *"Evaluation versions of Windows Server must be activated over the internet in the first 10 days to avoid automatic shutdown."* Since `vmbr1` has no route out until `fw-01` is up, **the DC must be allowed outbound during its first 10 days** — a firewall rule that must exist in the IaC and which the "isolated lab" framing actively works against. Server 2022/2025 can be rearmed up to 6× (~1080 days) and converted to retail with `DISM /Set-Edition`; **Win11 Enterprise Evaluation cannot.** ⚠️ `slmgr /rearm` decrements the counter *immediately*, even when run long before expiry — never put it in every Packer build.

### 4.2 Two Ansible gaps worth knowing before you start

- **Reverse DNS zones.** `ansible.windows.win_dns_zone` has **no `NetworkID`/reverse-lookup parameter** — reverse zones are not creatable with it. You must drop to `Add-DnsServerPrimaryZone -NetworkId 10.10.10.0/24 -ReplicationScope Forest` inside `ansible.windows.win_powershell` with a **hand-written `$Ansible.Changed` guard**. ⚠️ `-NetworkId` rounds IPv4 prefixes **up to the next multiple of 8** — a /23 lab would silently get only one /24 zone. Our /24 design is safe. This also closes G11: the zone name is **`10.10.10.in-addr.arpa`**; record it.
- **NTLM cannot delegate.** Any `microsoft.ad.user`/`ou`/`group` play run against a host that is *not* the DC fails with "Failed to contact the AD server" unless you use CredSSP, Kerberos-with-delegation, `become: runas` + `logon_flags=netcredentials_only`, or explicit `domain_username`/`domain_password`. **Simplest design: run all AD-object plays against `dc-01` itself.** Also split the inventory into a *bootstrap* group (local `Administrator`, NTLM/HTTP 5985) and a *domain* group (`MUTASPACE\Administrator`, Kerberos) — the same account changes identity across the promotion reboot.

---

## 5. Proposed Repo Layout

`docs/` stays exactly as it is — it is the product. Code is added alongside it, and every new subsystem gets a `docs/` counterpart so the plan/build convention survives.

```
mutaspace-soc-lab/
├── README.md                          # project overview; ADD: IaC quickstart + manual-prereq caveat
├── Taskfile.yml                       # single entrypoint: task build:ubuntu, task lab:up, task learner:reset
├── .gitleaks.toml                     # custom rules incl. the repo's own placeholder policy
├── .pre-commit-config.yaml            # gitleaks + tofu fmt + packer fmt + yamllint
├── .envrc.example                     # direnv template: PROXMOX_VE_*, PROXMOX_*, TF_ENCRYPTION passphrase
├── .gitignore                         # EXTEND: *.tfstate*, .terraform/, *.auto.tfvars, *.auto.pkrvars.hcl, crash.log
│
├── lab.yaml                           # ★ SINGLE SOURCE OF TRUTH: every VM, ID, IP, MAC, specs, bridge, template
│
├── docs/                              # UNCHANGED conventions: lowercase-hyphen, ---, Learning Reflection
│   ├── README.md                      # documentation standard (unchanged)
│   ├── hardware/                      # unchanged
│   ├── proxmox/
│   │   ├── host-baseline.md           # UPDATE: close the 5 Pending items; RECORD the PVE version
│   │   ├── installation-and-access.md
│   │   ├── iso-shelf.md               # NEW: every manually-acquired ISO/MSI, source, SHA256, host path
│   │   └── api-token-and-role.md      # NEW: pveum commands, version-forked privilege list
│   ├── network/
│   │   ├── network-design.md          # UPDATE: analyst-01 rename (C1), vmbr9 build plane, vmbr2 realised
│   │   ├── proxmox-bridge-plan.md     # UPDATE: record the real nic0 ifname (G8)
│   │   ├── build-plane.md             # NEW: why vmbr9 exists, the masquerade rules, the 10.10.10.1 trap
│   │   ├── dhcp-validation.md
│   │   ├── internal-dns-validation.md
│   │   └── time-synchronisation.md    # NEW: closes G18 — fw-01 NTP, PDC hierarchy, post-rollback resync
│   ├── vms/                           # unchanged naming; ADD the missing docs
│   │   ├── fw-01-firewall-plan.md     # REWRITE (C2) for OPNsense
│   │   ├── fw-01-firewall-build.md    # NEW
│   │   ├── win-client-01-plan.md      # NEW — closes G2
│   │   ├── win-client-01-build.md     # NEW — closes G2
│   │   ├── sensor-01-plan.md          # NEW
│   │   └── ... (existing files, updated)
│   ├── wazuh/                         # existing enrollment docs + NEW detection-as-code doc
│   ├── incident-scenarios/            # unchanged
│   └── iac/                           # NEW AREA — the IaC's own plan/build docs
│       ├── README.md                  # area index; why OpenTofu over Terraform and over Ansible-only
│       ├── design.md                  # this document, committed
│       ├── brownfield-import-plan.md  # per-VM adopt-vs-reprovision decision + import blocks
│       ├── vmid-and-address-policy.md # the 9000/100/200/800 scheme; MAC pinning; BC:24:11 OUI
│       └── testing-strategy.md        # the four-layer pyramid (§8 W2)
│
├── packer/
│   ├── README.md                      # manual prerequisites FIRST; then how to build
│   ├── common.pkrvars.hcl.example     # node, storage pool, build bridge, task_timeout
│   ├── ubuntu-server-2404/
│   │   ├── ubuntu-server.pkr.hcl      # proxmox-iso; boot_iso{}; vm_id=9000; template_name pinned
│   │   ├── http/user-data.pkrtpl.hcl  # subiquity autoinstall (nested under `autoinstall:`)
│   │   ├── http/meta-data             # empty file — required by NoCloud
│   │   └── scripts/cleanup.sh         # ★ the de-subiquity script — see §6 step 8
│   ├── ubuntu-desktop-2404/           # same shape; source.id = ubuntu-desktop
│   ├── win-server-2022/
│   │   ├── win-server.pkr.hcl         # boot_iso{iso_file=...}; additional_iso_files for virtio + cidata
│   │   ├── cd/Autounattend.xml.pkrtpl # windowsPE DriverPaths -> vioscsi\2k22\amd64 etc.
│   │   └── cd/setup.ps1               # WinRM bootstrap; locates its own CD by cd_label
│   ├── win11-client/                  # q35 + ovmf + efi_config + tpm_config; DriverPaths -> w11
│   ├── opnsense-267/                  # boot_command-driven; config.xml seed image
│   ├── kali-rolling/
│   └── manifest.json                  # gitignored; Packer manifest post-processor output
│
├── tofu/
│   ├── versions.tf                    # required_version >= 1.12; bpg = 0.111.1 EXACT; encryption block
│   ├── providers.tf                   # endpoint/api_token/ssh from env; min_tls forked on PVE version
│   ├── locals.tf                      # yamldecode(file("../lab.yaml")) -> the whole lab
│   ├── templates.tf                   # data.proxmox_virtual_environment_vms + plan-time preconditions
│   ├── adopted.tf                     # fw-01, dc-01, wazuh-01: prevent_destroy + protection = true
│   ├── lab-vms.tf                     # for_each over locals.lab.vms -> module.vm
│   ├── learners.tf                    # for_each over locals.learners -> pool + ACL + endpoint clones
│   ├── snippets.tf                    # proxmox_virtual_environment_file cloud-init user/meta-data
│   ├── access.tf                      # proxmox_virtual_environment_pool / _role / proxmox_acl
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── imports/
│   │   └── brownfield.tf              # import{} blocks; deleted after adoption is stable
│   ├── modules/proxmox-vm/            # ONE module. Not one .tf per VM.
│   │   ├── main.tf                    # clone{}, disk{} (all attrs restated), network_device{}, initialization{}
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── tests/
│       ├── network_placement.tftest.hcl   # mock_provider; asserts no lab VM lands on vmbr0
│       ├── vmid_policy.tftest.hcl         # asserts every vm_id is in its documented range
│       └── addressing.tftest.hcl          # asserts MAC/IP maps are 1:1 and in-subnet
│
├── ansible/
│   ├── ansible.cfg
│   ├── requirements.yml               # microsoft.ad 1.12.0, ansible.windows 3.7.0, community.proxmox
│   ├── inventory/
│   │   ├── hosts.yml                  # ★ STATIC and committed — IPs are deterministic
│   │   └── group_vars/{bootstrap_windows,domain_windows,linux,all}.yml
│   ├── roles/                         # wazuh-ansible is git-cloned here, NOT galaxy-installed
│   ├── playbooks/
│   │   ├── 10-dc-promote.yml          # microsoft.ad.domain + reverse zone via win_powershell
│   │   ├── 20-dns-records.yml         # A records for wazuh-01, ubuntu-app-01, sensor-01
│   │   ├── 30-domain-join.yml         # microsoft.ad.membership (rename + join in one task)
│   │   ├── 40-wazuh-agents.yml        # groups first, then enrollment
│   │   ├── 50-detections.yml          # PUT /rules/files + PUT /manager/analysisd/reload
│   │   ├── 60-suricata.yml
│   │   └── 90-lab-seed.yml            # test.user, lab.user02, OUs — makes the incident labs reproducible
│   └── files/wazuh-rules/             # version-controlled local_rules.xml — closes the DoD gap
│
└── scripts/
    ├── bootstrap-host.sh              # ★ step zero: detect PVE version, create role+token, enable snippets
    ├── learner-snapshot.sh            # qm snapshot <vmid> baseline
    ├── learner-reset.sh               # qm rollback <vmid> baseline --start
    └── preflight.sh                   # asserts ISO shelf, template VMIDs, bridges, snippets content type
```

### 5.1 `lab.yaml` — the one file a human edits

Everything else derives from this. GOAD's mistake was rendering `.tf` files through Jinja from Python, which makes `tofu validate`, `tofu fmt`, HCL language servers and CI linting impossible on the source of truth. **Do not copy that.** Plain HCL + `yamldecode` + `for_each` does the same job natively.

```yaml
site:
  node: mutaspace-soc-node01
  datastore: local-lvm          # linked clones cannot cross datastores
  iso_store: local
  snippets_store: local
  domain: mutaspace.local
  netbios: MUTASPACE

networks:
  lan:        { bridge: vmbr1, cidr: 10.10.10.0/24, gateway: 10.10.10.1 }
  isolated:   { bridge: vmbr2, cidr: 10.10.20.0/24, gateway: 10.10.20.1 }
  build:      { bridge: vmbr9, cidr: 10.99.0.0/24,  gateway: 10.99.0.1 }

templates:                       # MUST match packer vm_id; asserted at plan time
  ubuntu-server-2404:  9000
  ubuntu-desktop-2404: 9001
  win-server-2022:     9002
  win11-client:        9003
  opnsense-267:        9004
  kali-rolling:        9005

vms:
  dc-01:
    vm_id: 102
    lifecycle: adopted           # adopted | reprovisioned | linked
    template: win-server-2022
    cores: 2
    memory: { dedicated: 4096, floating: 0 }
    disk:   { size: 60, interface: sata0 }     # as-built; deliberate (VirtIO rejected, see build doc)
    nic:    { bridge: vmbr1, model: e1000, mac: "BC:24:11:10:10:10" }
    ipv4:   { address: 10.10.10.10/24, gateway: 10.10.10.1 }
    agent:  true
  win-client-01:
    vm_id: 105                   # ⚠️ INFERRED — confirm with `qm list` before first apply
    lifecycle: reprovisioned
    template: win11-client
    cores: 2
    memory: { dedicated: 4096, floating: 0 }
    disk:   { size: 60, interface: scsi0 }
    nic:    { bridge: vmbr1, model: virtio, mac: "BC:24:11:10:10:51" }
    ipv4:   dhcp                 # reservation .51 templated into the firewall from this MAC
    agent:  true
  # ... etc

learners:
  - { id: 01, endpoints: [win-client, kali] }
  - { id: 02, endpoints: [win-client, kali] }
  - { id: 03, endpoints: [win-client, kali] }
```

---

## 6. Bootstrap & Ordering

Three chicken-and-egg problems, and how each is broken:

| Circularity | Break |
|---|---|
| **Templates need internet; `vmbr1` has no uplink and its only route is through `fw-01`, which is itself a VM on that bridge.** | `vmbr9`, a host-masqueraded build bridge with no physical port. Packer builds there; OpenTofu re-points `network_device.bridge` to `vmbr1` at clone time — `bridge` is a normal, **non-ForceNew** attribute, so the switch is free. **Corollary nobody drew: the Wazuh installer fetches `wazuh-template.json` from `raw.githubusercontent.com`, so the SIEM must be installed during the Packer build on the build plane, not as a post-clone step.** Bake it; don't install it at deploy time. |
| **Guests need `dc-01` for DNS; `dc-01` is a guest.** | cloud-init/Autounattend sets the resolver to `10.10.10.10` *statically*, so no guest ever depends on DHCP-supplied DNS to find the DC. `depends_on` orders `dc-01` second, right after `fw-01`. Ansible waves are ordered so DNS records exist before anything needs to resolve them. |
| **Wazuh agents need `wazuh-01`; `wazuh-01` needs the DC's DNS A record to be reachable by FQDN.** | Agents enroll by **IP (`10.10.10.20`)** on first contact, not FQDN. The A record is a convenience the docs added *after* the fact (`docs/vms/wazuh-01-build.md:337-351` records exactly this failure). Enroll by IP; create the record; then switch `ossec.conf` to the FQDN in a later play. |
| **DHCP reservations need MACs; Proxmox assigns MACs at create time — which is after the firewall config is written.** | **Make the MAC an input, not an output.** `network_device.mac_address` is `Optional: true, Computed: true` and — contrary to common lore — **not ForceNew** (verified in `network/schema.go`; the historical "MAC taints state" report #734 was LXC-specific and closed as not-planned). Pin MACs in `lab.yaml` using the `BC:24:11` Proxmox OUI and template both the OpenTofu `network_device.mac_address` and the firewall's static mappings from the same map. |

### The sequence

**Phase A — Host facts and prerequisites (manual, one time)**

1. **Record the PVE version.** `pveversion -v | head -1` and `pvesh get /version --output-format json`. Write it into `docs/proxmox/host-baseline.md`. **Everything below forks on this.** If it is 7.x, bpg does not support it and the host must be upgraded before anything else. If 8.x, set `min_tls = "1.2"` in the provider (default is **1.3**, and against a TLS-1.2-only endpoint the failure looks nothing like a TLS problem).
2. **Record the real facts the docs never captured.** `qm list` (⇒ `fw-01`'s VMID (G1) and whether `win-client-01` is really 105 (G2)); `ip -br link` (⇒ the real `nic0` ifname (G8)); `pvesm status` (⇒ storage IDs, thin-provisioning (G9)); `cat /etc/apt/sources.list.d/*` (⇒ repo choice (G10)). Close the five Pending items in `host-baseline.md` (C5).
3. **Decide `test-client-01` (VM 101).** It is declared temporary but its deletion is never documented (G16). **IaC cannot infer intent — this needs a human answer before the first import pass.** If it is left unmanaged and someone later adds VMID 101 to a pool, bpg's `delete_unreferenced_disks_on_destroy` (**default `true`**) can delete disks nobody meant to touch.
4. **Enable the snippets content type.** `pvesm set local --content iso,vztmpl,backup,snippets`. Not on by default; without it every cloud-init snippet resource fails.
5. **Create the API users, role and tokens** — `scripts/bootstrap-host.sh`, version-forked:

```bash
# PVE 9.x
pveum role add IaC -privs "Datastore.Audit Datastore.Allocate Datastore.AllocateSpace \
  Datastore.AllocateTemplate Pool.Audit Pool.Allocate SDN.Audit SDN.Use Sys.Audit \
  Sys.AccessNetwork VM.Allocate VM.Audit VM.Backup VM.Clone VM.Config.CDROM \
  VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory \
  VM.Config.Network VM.Config.Options VM.Console VM.GuestAgent.Audit VM.Migrate \
  VM.PowerMgmt VM.Snapshot VM.Snapshot.Rollback"
# PVE 8.x: DROP SDN.Use (pre-8.2), VM.GuestAgent.Audit, Sys.AccessNetwork; ADD VM.Monitor.

pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role IaC
pveum user token add terraform@pve provider --privsep=0    # ⚠️ the secret is shown ONCE
pveum user add packer@pve
pveum aclmod / -user packer@pve -role IaC
pveum user token add packer@pve buildtoken --privsep=0
```

   ⚠️ **`VM.Monitor` was removed in PVE 9.0** — any role list copied from a pre-2025 tutorial fails outright. ⚠️ `[verifier]` The widely-circulated 23-privilege list is from an **open bug report** (#320) whose build *failed*, on PVE 8.x, and is not validated or officially recommended. ⚠️ `[verifier]` The list above deliberately **omits `Sys.Console` and `Sys.Modify`** — `Sys.Console` alone grants vncshell/termproxy, i.e. a root shell on the node, which nullifies the "without root" goal. `Sys.AccessNetwork` is the modern replacement for relying on `Sys.Modify` in the download-URL check. ⚠️ **Missing `VM.GuestAgent.Audit` does not produce a clean 403 — the bpg provider hangs indefinitely** when `agent { enabled = true }` (issue #2091). Budget for that exact symptom. ⚠️ Without `--privsep=0` the token inherits *nothing* and every call 403s.

6. **Create the SSH path for snippets.** Snippets **cannot** be uploaded via the PVE API — `/nodes/{node}/storage/{storage}/upload` accepts only `iso|vztmpl|import`. bpg silently pivots to SFTP/SSH, which **requires a real PAM (Linux) account**. Create one, install a key, and grant *narrowly* scoped sudo. ⚠️ **The old documented sudoers line is CVE-2026-25499 (High, fixed in provider docs at 0.93.1)** — `tee /var/lib/vz/*` allows `tee /var/lib/vz/../../../etc/sudoers.d/x`, i.e. full root. Use:

```
terraform ALL=(root) NOPASSWD: /usr/sbin/pvesm, /usr/sbin/qm, \
  /usr/bin/tee /var/lib/vz/snippets/[a-zA-Z0-9_][a-zA-Z0-9_.-]*
```
   The absence of `/` in the character class *is* the fix.

7. **Create `vmbr9`** (§2.3) and `vmbr2`; `ifreload -a`; verify with `ip -br link`. Do this **before** VMs exist on those bridges.
8. **Stock the ISO shelf** (§4.1): Ubuntu 24.04.4 server + desktop, Windows Server 2022 eval, Windows 11 media, `virtio-win-0.1.271` (**pin the versioned `archive-virtio/` URL, not `stable-virtio`/`latest-virtio` which are moving 301 redirects — and note 0.1.285/0.1.292 carry a vioscsi read-retry/perf regression, 0.1.271 is the known-good pin**), OPNsense 26.7 DVD (**decompress the `.bz2` first — Packer cannot boot a compressed image**), Kali. Record every SHA256 in `docs/proxmox/iso-shelf.md`. Install `xorriso` on the **Packer host** — `cd_files`/`cd_content` ISOs are built there, not on Proxmox, and the failure without it is confusing.

**Phase B — Templates (Packer, on `vmbr9`)**

9. `task build:ubuntu-server` → VMID 9000. Non-obvious settings, all researched:
   - `memory = 4096` — the plugin default is **512 MB**, which OOMs/kernel-panics subiquity. `[verifier]` 1 GB is no longer adequate; Canonical's current docs state a 1.5 GB minimum and suggest 3 GB+. 2048 is the floor, **4096 is the safer default** for 24.04+.
   - `task_timeout = "10m"` — default is **1 minute**, which covers ISO uploads, clones and template conversion.
   - `cpu_type = "host"`, `scsi_controller = "virtio-scsi-single"`, NIC `model = "virtio"` — the defaults are `kvm64`, `lsi` and `e1000`, all legacy.
   - `template_name` set explicitly — before v1.2.4, `-force` couldn't find auto-named templates (#342).
   - `vm_id = 9000` pinned — see the ForceNew landmine in step 12.
   - Boot command: the **GRUB console method** (`c`, then `linux /casper/vmlinuz ... / initrd /casper/initrd / boot`), *not* the 22.04-era `<esc><esc>e`/`<f6>` menu edit — the ISO menu layout changed. Put the literal token `autoinstall` on the kernel command line or subiquity stops at `Continue with autoinstall? (yes|no)` and Packer hangs until `ssh_timeout`. Single-quote the whole `ds=` value: **an unescaped `;` terminates a GRUB statement**. Keep the trailing slash on the seed URL (`s=http://IP:PORT/`) — `[verifier]` cloud-init has auto-appended it since 23.1, so its absence is *not* the cause of a modern failure, but keep it for portability.
   - ⚠️ If Packer runs anywhere the guest can't route back to (`{{.HTTPIP}}` resolving to a VPN/docker interface is common), abandon `http_directory` and use `cd_files` + `cd_label = "cidata"` instead.
10. **The de-subiquity step is mandatory and is where most people fail.** Subiquity leaves artifacts that *actively disable* cloud-init on clones. `cloud-init clean` alone does **not** remove them. As the last provisioner:

```bash
rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg \
      /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg \
      /etc/cloud/cloud.cfg.d/curtin-preserve-sources.cfg \
      /etc/netplan/00-installer-config.yaml /etc/netplan/50-cloud-init.yaml
echo 'datasource_list: [ NoCloud, ConfigDrive ]' > /etc/cloud/cloud.cfg.d/99-pve.cfg
cloud-init clean --logs --seed --machine-id      # machine-id, NOT rm -- netplan uses it as the DHCP client-id
truncate -s 0 /var/ossec/etc/client.keys 2>/dev/null || true   # never bake an agent identity into a template
```
   Without `99-installer.cfg` removal the template boots fine and **silently ignores OpenTofu's cloud-init drive**. Without `datasource_list` pinning, every clone probes EC2/Azure/GCE metadata endpoints, adding tens of seconds per boot. Without the machine-id reset, every clone gets the **same DHCP lease**. Without truncating `client.keys`, every clone is the same Wazuh agent (`Duplicate agent name`).
   - Also set `storage.layout.sizing-policy: all` in the autoinstall — the default `scaled` deliberately leaves most of a large disk unallocated (e.g. 10 GB root on a 20 GB disk).
   - Install `qemu-guest-agent` **during** autoinstall. Cloud images and ISO installs do not ship it, and `qemu_agent` defaults to `true` in the plugin, which means Packer resolves the SSH host via the guest-agent API and hangs without it.
   - Add `serial_device { device = "socket" }` equivalents where relevant: **Debian 12/Ubuntu guests kernel-panic when a cloud-image boot disk is resized without a serial device** (bpg issues #1639, #1770).
11. Build the remaining templates. Windows specifics:
    - **No floppy support exists** in `proxmox-iso` — `floppy_files`/`floppy_dirs` do not exist. Any tutorial using `A:\autounattend.xml` is from the qemu/virtualbox/hyperv builders. Deliver `Autounattend.xml` via `cd_files`/`cd_content` (Windows Setup searches removable read-only media at drive root for exactly that filename).
    - **Pin `type` + `index` on every ISO device.** Drive letters in `Autounattend.xml` are positional; adding or reordering an `additional_iso_files` block shifts D:/E:/F: and silently breaks driver injection. Have `setup.ps1` locate its own CD **by volume label**, not by letter.
    - VirtIO injection lives in the **windowsPE** pass via `Microsoft-Windows-PnpCustomizationsWinPE/DriverPaths` → `vioscsi\2k22\amd64`, `NetKVM\2k22\amd64`, `Balloon\2k22\amd64` (`w11` for the client).
    - Win11: `machine = "q35"`, `bios = "ovmf"`, `efi_config { pre_enrolled_keys = true, efi_type = "4m" }`, `tpm_config { tpm_version = "v2.0" }`, and `os = "win11"` — the plugin's documented enum stops at `win10` but it performs **no validation** and passes the value straight through as `QemuOs`. An MBR `DiskConfiguration` will not boot under OVMF; you need EFI(FAT32) + MSR(16 MB) + Primary(NTFS) with `InstallTo { DiskID=0, PartitionID=3 }`.
    - `[verifier]` If you need Secure Boot with Microsoft's 2023 certificates (the 2011 set expires **June 2026**), full enrollment including the KEK requires **qemu-server ≥ 9.1.5**, not 9.1.4 as commonly stated. The Packer plugin exposes only a boolean `pre_enrolled_keys` and has no `ms-cert` control.
    - **`proxmox-iso` has no `shutdown_command`** (issue #271, still open). Run sysprep as the **last provisioner** with `/generalize /oobe /mode:vm /quit` — **not `/shutdown`** — and let `stepConvertToTemplate`'s API `ShutdownVm()` stop the VM. `[verifier]` The mechanism is often misdescribed: proxmox-iso never shuts the guest down over the communicator at all; sysprep `/generalize` is what clears WinRM/credential state, and the approach works because Packer stops the VM out-of-band via the API afterwards. Consider a short `Start-Sleep` after sysprep — there is a theoretical race if the ACPI shutdown lands before sysprep flushes.
    - WinRM bootstrap from `FirstLogonCommands`: switch the network profile to Private (**required on client SKUs; `winrm quickconfig` fails otherwise** — the classic "works on Server 2022, hangs on Win11"), `winrm quickconfig -force`, `LocalAccountTokenFilterPolicy = 1`, an explicit inbound TCP 5985 rule, and `sc.exe config WinRM start= delayed-auto`. `[verifier]` The `AutoLogonCount = 0` reset is a **logon-counter fix, not credential hygiene** — it does not scrub `AutoAdminLogon`, `DefaultPassword`, the LSA secret, or the plaintext password in the answer file. Real credential hygiene = sysprep `/generalize` + clearing those keys + scrubbing `C:\Windows\Panther` + rotating the build password.
12. **Assert the handoff.** Packer's `manifest` post-processor writes `artifact_id`, and for the Proxmox builder `Artifact.Id()` is literally `strconv.Itoa(a.artifactID)` — **the template's VMID as a string**. Tempting to feed that straight into `clone { vm_id = ... }`. **Do not.** ⚠️ **The entire `clone` block — `vm_id`, `full`, `datastore_id`, `node_name`, `retries` — is ForceNew (verified in `vm.go`).** A manifest-driven VMID means *every template rebuild destroys and recreates every downstream VM*, which is catastrophic for `dc-01`. Use both mechanisms with different jobs: **pin the VMID in Packer as the contract**, and use the data source as a **plan-time assertion**:

```hcl
data "proxmox_virtual_environment_vms" "templates" {
  filter { name = "name"     values = ["tpl-ubuntu-server-2404"] }
  filter { name = "template" values = ["true"] }
}

resource "proxmox_virtual_environment_vm" "ubuntu_app_01" {
  lifecycle {
    precondition {
      condition     = one(data.proxmox_virtual_environment_vms.templates.vms).vm_id == local.templates["ubuntu-server-2404"]
      error_message = "Template VMID drifted from lab.yaml. Fix Packer's vm_id; do NOT edit lab.yaml, that would recreate every VM."
    }
  }
  clone { vm_id = local.templates["ubuntu-server-2404"]  # a constant, from lab.yaml
          full  = true
          retries = 2 }
  ...
}
```
   A missing or renumbered template becomes a **plan-time error** instead of a silent clone of the wrong VM (GOAD's `lookup(map, key, -1)` will happily try to clone VMID `-1`).

**Phase C — Brownfield adoption (OpenTofu)**

13. **Import the pets.** OpenTofu supports declarative `import` blocks plus config generation:

```hcl
import {
  to = proxmox_virtual_environment_vm.dc01
  id = "mutaspace-soc-node01/102"      # <node>/<vmid>
}
```
   then `tofu plan -generate-config-out=generated.tf`. ⚠️ Config generation is **experimental in OpenTofu 1.6+**, must target a **new** file (it errors on an existing one), warns that generated config for complex schemas can contain **mutually conflicting arguments** you must hand-prune, and may change formatting between minor versions. Treat the output as a first draft.
14. **Expect a large first diff and restate every disk attribute.** The documented clone caveat applies equally to imports: *"If you modify any attributes of an existing disk... you also need to explicitly provide values for any other attributes that differ from the schema defaults."* Setting only `disk { interface = "scsi0"; size = 60 }` silently flips `discard` back to `ignore`, `cache` to `none`, `aio` to `io_uring`, and `ssd`/`iothread` to `false`. **Restate the complete disk block, always.** Iterate until `tofu plan` reports **no changes**. That clean plan is Wave 1's proof.
15. **Protect the pets, both ways:**

```hcl
resource "proxmox_virtual_environment_vm" "dc01" {
  protection = true                       # Proxmox-side: blocks removal
  lifecycle { prevent_destroy = true }    # OpenTofu-side: blocks the plan
  stop_on_destroy = true                  # default is FALSE -> ACPI shutdown that hangs to timeout
  ...
}
```
16. Delete `test-client-01` (VM 101) — **only after step 3's human decision**.

**Phase D — Provision (OpenTofu)**

17. `tofu apply -parallelism=1`. ⚠️ Creating multiple VMs simultaneously causes PVE **lock errors from I/O contention** (issues #1929, #995). Set `clone { retries = 2 }` and raise `timeout_clone`.
18. `fw-01` first (`depends_on`, or apply it in a separate targeted run), then `dc-01`, then everything else.
19. On `agent`: set `agent { enabled = true }` **only where qemu-guest-agent is genuinely baked in**. Otherwise the provider cannot distinguish "agent missing" from "slow boot" and waits out `agent.timeout` (**default 15m**) on **every create and every refresh**, while Proxmox's Shutdown/Reboot take a lock that blocks Stop until it times out. Where it isn't baked in: `agent { enabled = false }` + `stop_on_destroy = true` + static `ip_config` (never read `ipv4_addresses`).
20. ⚠️ **Never put an `initialization` block in the template itself.** Open **P1 bug #1106**: initialization settings inherited from a clone **cannot be cleared** — every apply shows the same removal and never converges.
21. ⚠️ **Snippet versioning is a deliberate two-horn choice, and both horns hurt.** `initialization.user_data_file_id`, `meta_data_file_id`, `vendor_data_file_id`, `network_data_file_id` and `type` are **all ForceNew**. Either (a) keep `file_name` stable — editing snippet content does *not* recreate the VM, but cloud-init also never re-runs, so the change is invisible until a rebuild; or (b) hash/version `file_name` — every snippet edit **destroys and recreates the VM**. **For this lab: choose (a)**, and treat snippet edits as requiring an explicit, deliberate rebuild. Open FR #2901 asks for restart-instead-of-recreate. ⚠️ Also untested: whether changing `source_raw.data` with a constant `file_name` updates in place — logically yes, but the docs don't say so and open issue #677 shows related change-detection weakness. **Test this on the host before designing the strategy around it** (§9 R7).
22. ⚠️ `local-lvm` is the **silent default `datastore_id` for `initialization` and `tpm_state`**, not just for disks. On a non-`local-lvm` host the apply fails with "storage local-lvm does not exist" from a block that never mentions storage. Set it explicitly.

**Phase E — Configure (Ansible)**

23. `10-dc-promote.yml` — only needed on a rebuild; the existing forest is adopted. Do **not** add a separate `win_feature: AD-Domain-Services` task; `microsoft.ad.domain` installs `AD-Domain-Services` and `RSAT-ADDS` itself via `_DomainFeature.psm1`, and the extra task can double-trigger `reboot_required`. Set `reboot: true`. ⚠️ `forest_mode`/`domain_mode` on Server 2022 max out at **`WinThreshold` (Server 2016)** — there is no Win2019/Win2022 functional level. ⚠️ If the OU/user plays fail with "Get-ADUser is not recognized", add an explicit `win_feature: RSAT-AD-PowerShell`.
24. `20-dns-records.yml` — A records + the reverse zone via `win_powershell` (§4.2).
25. `30-domain-join.yml` — `microsoft.ad.membership` renames and joins in one task.
26. `40-wazuh-agents.yml` — ⚠️ **create agent groups first**: `/var/ossec/bin/agent_groups -a -g <name> -q`. Enrolment into a nonexistent group does **not** create it. Then deploy with `WAZUH_MANAGER`/`WAZUH_AGENT_NAME`/`WAZUH_AGENT_GROUP` (identical variable set as MSI properties on Windows). ⚠️ The Ubuntu path needs **DEB amd64**, not the dashboard's default RPM command (`rpm: command not found` — this exact failure is already documented at `docs/wazuh/agent-enrollment-linux.md:92-116`).
27. `50-detections.yml` — push `local_rules.xml` via `PUT /rules/files/{filename}` then `PUT /manager/analysisd/reload`. **This closes three Definition-of-Done gaps at once** (custom rule, tuning journal, automation script).
28. `90-lab-seed.yml` — create `test.user` and `lab.user02` so the two existing incident labs are reproducible rather than hand-built. ⚠️ `microsoft.ad.ou` defaults `protect_from_deletion: true` on creation — set it `false` in a lab, or a rebuild leaves protected OUs blocking cleanup.

---

## 7. Classroom Lifecycle

### 7.1 The reset mechanism

**`qm rollback`, not `vzdump`/`qmrestore`.** `[verifier]` vzdump backups are always *logically* full — it reads the guest-visible disk, so a linked clone's backup contains the base template's data, and `qmrestore` allocates a fresh standalone volume with no backing file. The linked-clone relationship is destroyed and the restored VM is fully independent. (Nuance: the *bytes written* are not full — VMA compresses zero blocks, and a **Proxmox Backup Server** target uploads only changed 4 MiB chunks into a deduplicated datastore, so N clone backups share base chunks. The real cost is paid at **restore** time, where each restored VM consumes full independent disk. PBS remains the right tool for **off-host archival of golden templates**, not for learner resets.)

```bash
# Instructor: take the baseline ONCE, with the VM STOPPED and WITHOUT --vmstate
qm shutdown 205 && qm snapshot 205 baseline --description "start of module 3"

# Learner reset
qm rollback 205 baseline --start
```

⚠️ `[verifier]` **`qm rollback` does NOT restart the VM.** It stops it (if running) and reverts the disk, then leaves it **powered off** unless (a) the snapshot includes RAM state, or (b) you pass `--start` explicitly (API parameter `start`, default `0`). **The web UI's rollback button POSTs with no parameters**, so a GUI rollback of a disk-only snapshot also leaves the guest off. Since a 2025-11-28 qemu-server commit, the start path additionally requires **`VM.PowerMgmt`**, checked up front — relevant if you drive rollbacks with a token holding only `VM.Snapshot.Rollback`.

**Why stopped and without `--vmstate`:** a running 8 GB VM writes a multi-GB RAM image, possibly onto the 96 GB root LV (the `vmstate` storage-selection chain ends at `local`), and rollback then *resumes mid-flight* instead of cold-booting cleanly — which is exactly the wrong classroom semantics. Set `vmstatestorage` explicitly regardless.

**Design constraint:** use **one `baseline` snapshot per learner VM**. ⚠️ Whether rolling back to a non-most-recent snapshot on LVM-thin deletes newer snapshots is **unverified** (ZFS demonstrably requires destroying newer ones). A single baseline sidesteps the question entirely.

### 7.2 Per-learner scoping

```bash
pveum pool add learner01
pveum pool modify learner01 --vms 205,206
pveum role add LearnerReset -privs "VM.Audit VM.Console VM.PowerMgmt VM.Snapshot.Rollback"
pveum acl modify /pool/learner01 --users learner01@pve --roles LearnerReset
```

⚠️ The built-in **`PVEVMUser` does not include `VM.Snapshot` or `VM.Snapshot.Rollback`** — self-service reset needs a custom role. ⚠️ Grant at `/pool/<learner>`, **never** at `/vms` or `/`: deeper paths override upper ones, so a stray root ACL gives every learner every VM.

⚠️ `[verifier]` Verify the built-in role's exact privilege list with `pveum role list` before relying on the absence of `VM.Snapshot.Rollback` — pve-docs only summarises it in prose.

### 7.3 Multi-learner topology

**Shared infrastructure + per-learner endpoints** is the only shape that fits 64 GB (§2.7). Adapt Ludus's addressing idea without adopting Ludus itself (it is a Go server product under AGPLv3, not a repo template — adopting it means giving up your own HCL entirely):

- VMID: `200 + (learner_index × 10) + role_offset` — learner 01 gets 205 (`win-client`) and 206 (`kali`).
- IP: DHCP reservations at `10.10.10.(150 + learner_index × 2)` from pinned MACs.
- Hostname: `wc-l01`, `kali-l01` — via cloud-init/Autounattend, **not** DHCP, so `agent.name` in Wazuh stays stable across resets and the detection-lab queries in `docs/incident-scenarios/*` keep working.
- ⚠️ **Never bake a populated `/var/ossec/etc/client.keys` into a template.** Every clone becomes the same agent → `Duplicate agent name`. Truncate as the last Packer step (§6 step 10) and let the `<enrollment>` block re-register on first boot.

### 7.4 The Wazuh re-enrollment trap (this will look like "the agent just won't connect")

The manager's `ossec.conf` `<auth><force>` block ships with **`disconnected_time = 1h`** and **`after_registration_time = 1h`**. In a classroom where learners revert snapshots repeatedly, this **silently blocks a same-named agent from re-registering for an hour**. **Set both to `0`.** Bake it into the Wazuh Packer template.

### 7.5 Time — the reset mechanism *is* a clock-skew generator

Nobody connected these two facts: `qm rollback` reverts a VM to a snapshot taken days earlier, and Kerberos rejects authentication outside the "Maximum tolerance for computer clock synchronization" policy (**default 5 minutes**). Roll `win-client-01` back to a two-week-old baseline and its clock is two weeks behind the DC ⇒ Kerberos fails ⇒ domain logon fails ⇒ the lab looks broken for reasons unrelated to the exercise. Simultaneously, Wazuh correlation across `dc-01`, `win-client-01` and `ubuntu-app-01` is meaningless if their clocks disagree.

Design (closes G18):
- **`fw-01` is the lab NTP server** on the LAN interface (both pfSense and OPNsense ship one), handed out via the same DHCP options that already carry DNS `10.10.10.10` and domain `mutaspace.local`.
- **`dc-01`** (forest-root PDC emulator) syncs from it: `w32tm /config /manualpeerlist:"10.10.10.1,0x8" /syncfromflags:manual /reliable:yes /update`. All domain members inherit `NT5DS` from the hierarchy.
- **Leave the QEMU guest agent's time sync ON everywhere.** `[verifier]` The blanket "always disable hypervisor time sync on DCs" rule is version- and platform-specific — Microsoft's own 1 ms reference topology syncs the root PDC *from* the Hyper-V host, and for Server 2016+ guests on 2016+ hosts Microsoft states the problem "should no longer exist". On KVM/Proxmox, `guest-set-time` after a rollback is precisely what stops a clone from being hours behind before W32Time ever gets a chance.
- **Add a post-rollback runbook step:** `w32tm /resync` on Windows, `timedatectl` / `chronyc tracking` on Linux.

### 7.6 Template protection

Set `protection = true` on every template VMID. **Deleting or rebuilding a template that linked clones depend on breaks the clones.** Treat template rebuilds as a **new VMID + re-clone cycle**, never an in-place edit — which is also why `vm_id` is pinned per template family (9000, 9001, …) with room in the 9000–9099 block for `9000a`-style successors.

---

## 8. Implementation Waves

Each wave is independently shippable and has a command that proves it.

### Wave 1 — Host truth + a clean brownfield plan
**Scope.** §6 steps 1–6 (host facts, `test-client-01` decision, snippets, role+tokens, SSH sudoers). Close the five Pending items in `docs/proxmox/host-baseline.md` (C5) and record the PVE version, real `nic0` ifname, storage IDs, repo choice, `fw-01`'s VMID and `win-client-01`'s VMID. Write `tofu/versions.tf`, `providers.tf`, and `imports/brownfield.tf` importing **only `dc-01`**.
**Definition of done.** `tofu plan` against the real host reports **`No changes.`** for the imported `dc-01`.
**Verify.**
```bash
pveversion -v | head -1
tofu init && tofu plan -detailed-exitcode   # exit 0 == no changes == success
```
**Why first.** It proves — on the real machine, in an afternoon — endpoint reachability, TLS negotiation (`min_tls` default 1.3), API-token auth, the privilege list, the SSH/snippets path, and that brownfield adoption is viable. If any of those fail, everything downstream is invalid. It also produces the facts (G1, G2, G8, G9, G10, G15) that every later wave depends on, and it touches nothing.

### Wave 2 — Test harness + repo hygiene
**Scope.** `.gitleaks.toml` (including a custom rule for the repo's own placeholder policy — a regex failing any committed non-RFC1918 IPv4 or `10.0.0.` outside a fenced "Example" block), `.pre-commit-config.yaml` (gitleaks **v8.30.1**), extend `.gitignore` (`*.tfstate*`, `.terraform/`, `*.auto.tfvars`, `*.auto.pkrvars.hcl`, `crash.log` — but **commit `.terraform.lock.hcl`**), `.envrc.example`, OpenTofu state encryption, `tofu/tests/*.tftest.hcl` with `mock_provider`, `Taskfile.yml`.
**Definition of done.** A test suite that runs **fully offline** — no Proxmox endpoint — and fails when a VM is placed on `vmbr0`.
**Verify.**
```bash
tofu test            # mock_provider: no host contact
pre-commit run --all-files
```
**Why second.** The host runs live coursework; there is no second Proxmox box. This is the layer that catches "someone put the DC on the WAN bridge" before it reaches the classroom. Enable **GitHub secret scanning + push protection** (free and default-on for public repos) as the server-side backstop — but note it will not catch a lab Wi-Fi SSID, a home LAN subnet or a `wazuh-passwords.txt`, so layer 1 is not optional.

```hcl
mock_provider "proxmox" {
  mock_data "proxmox_virtual_environment_vms" {
    defaults = { vms = [{ vm_id = 9000, node_name = "mutaspace-soc-node01" }] }
  }
}
run "no_lab_vm_escapes_to_the_wan_bridge" {
  command = plan
  assert {
    condition     = alltrue([for v in local.lab.vms : v.nic.bridge != "vmbr0" if v.name != "fw-01"])
    error_message = "A lab VM was placed on vmbr0."
  }
}
```

### Wave 3 — Build plane + first Linux template
**Scope.** `vmbr9` + masquerade (§2.3). `packer/ubuntu-server-2404/` end to end, including the de-subiquity cleanup script. `docs/network/build-plane.md`, `docs/proxmox/iso-shelf.md`.
**Definition of done.** VMID 9000 exists as a template, and a manually cloned VM on `vmbr1` boots with the hostname and static IP that cloud-init gave it.
**Verify.**
```bash
packer build -var-file=packer/common.pkrvars.hcl packer/ubuntu-server-2404/
qm list | grep 9000
qm clone 9000 899 --name smoke-test --full 1 && qm start 899   # 8xx scratch range
```

### Wave 4 — Reprovision the Linux estate
**Scope.** `modules/proxmox-vm/`, `lab.yaml`, `lab-vms.tf`. Rebuild `ubuntu-app-01` (106) and `analyst-01` (103) from templates. Adopt `wazuh-01` (104) and `fw-01`. Static Ansible inventory + `40-wazuh-agents.yml`. Delete `test-client-01`.
**Definition of done.** `ubuntu-app-01` and `analyst-01` are `tofu destroy`-able and `tofu apply`-able, come back with the same IPs/MACs/hostnames, and re-register in Wazuh under the same `agent.name`.
**Verify.**
```bash
tofu apply -parallelism=1
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/40-wazuh-agents.yml
ssh wazuh-01 '/var/ossec/bin/agent_control -l'    # ubuntu-app-01 + analyst-01 Active
```

### Wave 5 — Windows templates + `win-client-01`
**Scope.** `packer/win-server-2022/`, `packer/win11-client/`, virtio-win 0.1.271 pin, Cloudbase-Init. Reprovision `win-client-01` (105). Write the two missing docs (`win-client-01-{plan,build}.md` — closes G2). Ansible domain-join + Wazuh MSI + **Sysmon** (currently absent).
**Definition of done.** `win-client-01` is destroyed and rebuilt from a template, auto-joins `mutaspace.local`, appears in Wazuh as `win-client-01`, and **Lab 01 (Event ID 4625) reproduces end to end** from the rebuilt VM.
**Verify.**
```bash
tofu apply -target=proxmox_virtual_environment_vm.win_client_01
ansible-playbook ... 30-domain-join.yml 40-wazuh-agents.yml
# then in the Wazuh dashboard (Threat Hunting, NOT File Integrity Monitoring):
#   agent.name: "win-client-01" AND data.win.system.eventID: "4625"
```

### Wave 6 — `vmbr2`, `sensor-01`, and the research plane
**Scope.** `vmbr2`, `fw-01`'s third leg (closes C11), `sensor-01` + Suricata (closes the DoD gap and C14), `kali-01`, `untrusted-01`, `nlp-01` (closes G21). **Requires the §9 R4 decision on mirroring first.**
**Definition of done.** Suricata generates at least one alert visible in Wazuh from traffic originated by `kali-01`.
**Verify.** `curl` a known-bad signature from `kali-01`; confirm the alert in the Wazuh dashboard.

### Wave 7 — Detection as code
**Scope.** `ansible/files/wazuh-rules/local_rules.xml` (IDs in the reserved **100000–120000** range), `70-detections.yml` (numbered `50-` in this plan), MITRE mapping, a false-positive tuning journal, `docs/wazuh/detection-as-code.md` — *the rules and the playbook exist; the tuning journal and that document do not yet, because neither can be written honestly before the rules have been observed firing.*
**Definition of done.** A rule edited in git is live on the manager within one playbook run, **without a manager restart**. This closes three Definition-of-Done items (custom rule, tuning journal, Python/automation script).
**Verify.**
```bash
ansible-playbook ... 50-detections.yml
ssh wazuh-01 '/var/ossec/bin/wazuh-logtest'   # rule fires
# manager uptime unchanged -> analysisd reload, not restart
```

### Wave 8 — Firewall migration + classroom lifecycle
**Scope.** `packer/opnsense-267/`, cut `fw-01` over during a break, rewrite `fw-01-firewall-plan.md` + new build doc (closes C2), the ~9-file find-and-replace. Learner pools, ACLs, `learner-snapshot.sh` / `learner-reset.sh`, NTP topology (closes G18), post-rollback runbook.
**Definition of done.** Three learner ranges exist; a learner can reset their own endpoint pair; after reset the VM re-registers in Wazuh **within one minute** (not one hour — §7.4) and Kerberos logon succeeds without manual `w32tm /resync`.
**Verify.**
```bash
./scripts/learner-reset.sh 01
# then on win-client-l01:
klist purge && whoami /groups        # domain auth succeeds
```

---

## 9. Risks & Open Questions

### 9.1 Blocking — needs the lab owner's decision before code is written

| # | Question | Why it blocks | What resolves it |
|---|---|---|---|
| **R1** | **What Proxmox VE version is the host running?** | Forks the `pveum role add` privilege list (`VM.Monitor` removed in 9.0; `VM.GuestAgent.*`/`SDN.Use`/`VM.Replicate` don't exist on 8.x), the apt source format (deb822 `.sources` from 9.0), `min_tls` (1.3 default vs a TLS-1.2 endpoint), and whether bpg supports the host at all (**7.x is explicitly unsupported**). PVE 9.2 additionally requires `VM.PowerMgmt` to *start* a VM after create/restore/rollback. | `pveversion -v \| head -1` — five seconds. Wave 1 step 1. |
| **R2** | **Adopt or rebuild `dc-01`?** | The forest cannot be recreated without recreating the domain, and both incident labs reference `MUTASPACE\test.user` / `lab.user02`. But the underlying media is a **180-day evaluation** with a 10-day online-activation deadline — an adopted DC eventually dies of licensing, not of IaC. | Owner's call. **Recommendation: adopt now, rebuild once from `tpl-win-server-2022` at a semester boundary**, so the rebuild is a planned exercise rather than an emergency. |
| **R3** | **Firewall: migrate to OPNsense, or keep pfSense on the 2.7.2→2.8.1 upgrade path?** | Decides Wave 8 entirely and ~10 documentation files. The migration costs a semester of pfSense-specific teaching material; keeping pfSense costs "reproducible from source". | Owner's call on teaching priority. §3.1 recommends OPNsense but the pfSense path is **staff-endorsed and real** (`[verifier]`). |
| **R4** | **How does `sensor-01` see traffic?** | `docs/network/network-design.md:92,208` says placement is TBD. A plain Linux bridge does **not** mirror — a promiscuous NIC will not see unicast between other VMs. Options: (a) Suricata **inline on the firewall** (simplest, sees only cross-firewall traffic); (b) **Open vSwitch with a mirror port** (sees east-west, bigger host change). Blocks Wave 6. | Owner's call. **Recommendation: (a) for Wave 6**, revisit (b) later. |
| **R5** | **Delete `test-client-01` (VM 101)?** | Declared temporary, never documented as deleted (G16). IaC cannot infer intent, and an unmanaged VMID inside a managed pool can lose its disks to `delete_unreferenced_disks_on_destroy` (bpg default **`true`**). | One `qm destroy 101`, or an explicit "keep and adopt" decision. |
| **R6** | **Is `win-client-01` really VMID 105, and what OS is it?** | The VMID is **inferred from a gap in the 101–106 sequence**; the OS, vCPU, RAM, disk, bus and NIC model are **all missing** (G2, no build doc exists). You cannot write an `import` block or a template for it until someone looks. | `qm list` and `qm config 105`. Wave 1. |

### 9.2 High risk

| # | Risk | Mitigation / what would resolve it |
|---|---|---|
| R7 | **Snippet change-detection is untested.** Whether editing `source_raw.data` with a constant `file_name` updates in place (VM not recreated) is **not stated in the docs**, and open issue #677 shows related weakness for `source_file`. The whole §6-step-21 strategy rests on it. | Test on the host before Wave 4: change a snippet, `tofu plan`, confirm no recreate. |
| R8 | **`agent.enabled = true` without a running agent is the single worst time-waster** — 15-minute timeouts on every create *and* every refresh, plus a Proxmox lock that blocks Stop. On PVE 9 the missing-`VM.GuestAgent.Audit` case **hangs rather than 403s**. | Bake the agent into every template; set `enabled = false` + `stop_on_destroy = true` where it isn't; verify the privilege in Wave 1. |
| R9 | **Both `packer-plugin-proxmox` v1.2.4 and this research date from 2026-07-21.** v1.2.4 has zero field exposure. Its API client (`Telmate/proxmox-api-go`) is pinned to an **Oct-2024 commit, predating PVE 9.0**, and there is **no published PVE 9 compatibility statement**. | Use `~> 1.2` (floor 1.2.3). Build one template early (Wave 3) and treat it as the compatibility test. |
| R10 | **Windows ISO acquisition is manual and gated**, so a fresh clone of the repo cannot build the Windows templates. | Document it as a first-class README caveat + `docs/proxmox/iso-shelf.md`. Not fixable, only disclosed. |
| R11 | **The 96 GB `local` root LV fills silently** from ISOs + snapshot `vmstate` + vzdump, and a full **LVM-thin pool stalls or corrupts writes across every VM**. | Set `vmstatestorage`, add dedicated backup storage, enable `discard = "on"` + `ssd = true` on every disk, and monitor `lvs`. |
| R12 | **OPNsense's unattended install is a timing-sensitive `boot_command`** driving an interactive importer that expects a keypress and a device name. It **will** break across OPNsense releases. | Budget re-tuning per version bump. Pin the OPNsense version for a whole semester. Also pin `browningluke/opnsense = 0.24.0` exactly — it explicitly disclaims stability. |

### 9.3 Medium risk / verify before relying on

| # | Item | Note |
|---|---|---|
| R13 | Main-branch schema details cited in the research (`upload_mode`, `disk.queues`, `agent.wait_for_ip`) may be **ahead of released v0.111.1**. | Confirm with `tofu providers schema -json` against the pin. |
| R14 | **The minimum PVE privilege set is a synthesis, not an authoritative list.** No one publishes a verified minimum for Packer+OpenTofu on PVE 9.2. `[verifier]` The circulating 23-privilege list is from an *open bug report* whose build failed. | PVE returns clear `403 Permission check failed (<path>, <Priv>)` messages. Start narrow, add empirically, record the result. |
| R15 | **Some operations are `root@pam`-only regardless of role**: `arch`, `cpu.affinity`, `memory.hugepages`, `rng`, `initialization.upgrade`, `hostpci.id`, `file_mode`, and generally anything the API guards with `user != root@pam`. bpg documents the failures but does **not enumerate them**. | Keep a `root@pam` username/password fallback available while bringing the lab up. |
| R16 | **Ubuntu Server 24.04 live ISO layer names differ from Desktop.** `[verifier]` Server uses `ubuntu-server-minimal.*.squashfs`; Desktop uses `minimal.standard.live.squashfs`. Whether `layerfs-path` is required with the GRUB-console method is unverified. | If the live session fails to start after `boot`, add `layerfs-path` — it is the first thing to try. |
| R17 | **Unrecognized autoinstall keys are NOT fatal.** `[verifier]` The docs say they *will* be fatal "in future versions"; **no autoinstall v2 exists** as of 2026-07-21, and the published JSON schema has `additionalProperties: true` at the root. Do not design around a fatal-error assumption. | Validate in CI with subiquity's `scripts/validate-autoinstall-user-data.py` instead. |
| R18 | **IDE cloud-init drive cold-boot visibility.** Community reports (no tracked bug ID) that a cloud-init volume on `ide2` is invisible on cold boot but appears after a warm reset. | If clones intermittently ignore cloud-init on first boot, try `cloud_init_disk_type = "scsi"` in Packer and `initialization.interface` accordingly. |
| R19 | **Whether `data.proxmox_virtual_environment_vms` returns Packer-built templates as `template = true` immediately** after a build is untested (the new `skip_convert_to_template` option suggests conversion is a distinct API call). This underpins the Wave-3 precondition. | Verify in Wave 3. |
| R20 | **Whether `proxmox_network_linux_bridge` triggers the ifupdown2 reload itself** (it exposes `timeout_reload`) or leaves config staged in `interfaces.new` is not documented. | Verify with `ip -br link` after apply, not by trusting the plan. This is the main reason §4 recommends doing bridges by hand. |
| R21 | **Open PVE-side flakes to expect and not misdiagnose:** template conversion reporting `Can't convert Vm to template` when the API returns `{"data":null}` **even though the template was created** (#344); stale `/var/lock/qemu-server/lock-<vmid>.conf` from aborted builds blocking shutdown (#290); intermittent `sendkey: EOF` and dropped characters during boot commands (#237, #220). | CI should check for the template's existence before blindly rebuilding. Prefer short boot commands, or sidestep `sendkey` entirely with `cd_files` + `cd_label = "cidata"`. |

### 9.4 Explicitly not a risk (corrections to common lore)

- **`network_device.mac_address` is not ForceNew** — it is `Optional + Computed`. Proxmox-assigned MACs are absorbed into state and do not force replacement. The historical #734 report was LXC-specific and closed as not-planned. This is what makes MAC pinning (§6) safe.
- **`tags` already has an order-insensitive diff suppressor** in code (`SuppressIfListsAreEqualIgnoringOrder`, `DiffSuppressOnRefresh: true`) even though the docs still advise `ignore_changes`.
- **pfSense's ECL works on GPT and honours `/config/config.xml`** — `[verifier]` both were real 2.4.4-era bugs, both fixed (2.5.0 and 2.4.4-p1 respectively). The "MBR only, drive root only" advice is obsolete.
- **Proxmox Windows cloud-init passwords are officially supported** since qemu-server 8.2.2 — `[verifier]` the "not officially supported" FAQ line dates from **April 2022**. The ordering trap (`ostype` before `cipassword`) is the real issue.
- **DetectionLab is not a viable reference** — `[verifier]` `clong/DetectionLab` is EOL (README says so; last commit 2023-03-27; docs domain no longer resolves), and `cyberdefenders/DetectionLabELK` is **not** a maintained fork (its last commit predates upstream's by ~22 months). GOAD and Ludus are the live prior art.

---

## Appendix A — Canonical HCL sketches

**Provider (`tofu/providers.tf`)** — credentials from environment only:

```hcl
terraform {
  required_version = ">= 1.12.0"
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "0.111.1" }   # EXACT. v0.109.0 was breaking.
  }
  encryption {
    key_provider "pbkdf2" "lab" { passphrase = var.state_passphrase }  # >=16 chars, >=200k iterations
    method "aes_gcm" "lab" { keys = key_provider.pbkdf2.lab }
    state { method = method.aes_gcm.lab }
    plan  { method = method.aes_gcm.lab }
  }
}

provider "proxmox" {
  endpoint = var.pve_endpoint          # https://host:8006/  -- NO /api2/json (Packer wants it WITH)
  # api_token via PROXMOX_VE_API_TOKEN -- "terraform@pve!provider=<uuid>", one string
  insecure = true                      # self-signed cert, documented at installation-and-access.md:133
  min_tls  = "1.3"                     # set "1.2" if the host is PVE 8.x
  ssh {
    agent    = true
    username = "terraform"             # REQUIRED with token auth; cannot inherit a non-PAM credential
  }
}
```

**The VM module's core** — every clone landmine addressed:

```hcl
resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  vm_id     = var.vm_id                # pinned, ForceNew
  node_name = var.node
  pool_id   = var.pool_id
  tags      = ["mutaspace", var.role]

  stop_on_destroy = true               # default FALSE -> ACPI shutdown hangs to 1800s on agentless guests
  protection      = var.adopted
  on_boot         = true

  clone {
    vm_id   = var.template_id          # a CONSTANT from lab.yaml. The whole block is ForceNew.
    full    = var.linked ? false : true
    retries = 2                        # PVE lock contention is real
    # datastore_id INTENTIONALLY OMITTED: linked clones cannot change target storage.
  }

  cpu    { cores = var.cores, type = "host" }
  memory { dedicated = var.memory, floating = var.balloon ? var.memory : 0 }

  # Restate EVERY attribute: touching one resets the others to schema defaults.
  disk {
    interface    = var.disk_interface
    datastore_id = var.datastore
    size         = var.disk_size
    discard      = "on"                # or thin-pool blocks are never reclaimed
    ssd          = true                # invalid on virtio disks -- keep interface = scsi/sata
    cache        = "none"
    aio          = "io_uring"
    iothread     = true                # requires virtio-scsi-single
  }

  # ORDER IS THE WIRE: network_device blocks map positionally to net0..netN.
  network_device {
    bridge      = var.bridge           # NOT ForceNew -- build plane -> runtime plane is free
    model       = var.nic_model
    mac_address = var.mac              # pinned; NOT ForceNew (contrary to common lore)
  }

  initialization {
    datastore_id = var.datastore       # 'local-lvm' is the SILENT default here -- set it
    interface    = "ide2"
    upgrade      = false               # default TRUE -> every clone package-upgrades on first boot
    dns { domain = "mutaspace.local", servers = ["10.10.10.10"] }
    dynamic "ip_config" {
      for_each = var.ipv4 == "dhcp" ? [] : [1]
      content { ipv4 { address = var.ipv4, gateway = var.gateway } }
    }
    # user_data_file_id CONFLICTS with user_account; network_data_file_id CONFLICTS with ip_config.
    user_data_file_id = var.user_data_file_id   # ForceNew -- keep file_name stable
  }

  agent { enabled = var.agent_installed }       # true ONLY if baked into the template

  serial_device { device = "socket" }           # Ubuntu/Debian kernel-panic on boot-disk resize without it

  lifecycle {
    prevent_destroy = var.adopted
    precondition {
      condition     = var.role != "firewall" || var.bridge == "vmbr0"
      error_message = "fw-01 net0 must be WAN (vmbr0). NIC order decides which leg is WAN."
    }
  }
}
```

**`fw-01` is the one VM that must NOT be generated from a map** — NIC order silently decides which interface is WAN. Reorder two blocks in a refactor and the firewall boots with WAN and LAN swapped: the lab loses internet, the Proxmox management bridge starts eating DHCP from the firewall, and nothing in the plan output hints at why. Declare `net0`/`net1`/`net2` as explicit, ordered, commented blocks with pinned MACs, and keep the never-built third leg visible as a commented block with a doc reference.

---

## Appendix B — The five gaps this design deliberately leaves open

Not everything can be closed by a design document. These are known-unknowns, listed so nobody mistakes them for oversights:

1. **`fw-01`'s VMID and `win-client-01`'s entire hypervisor config** are not knowable from the repo. They require `qm list` / `qm config` on the host (Wave 1).
2. **`wazuh-01`'s actual Ubuntu release** is unknowable — the plan preferred 22.04, the build recorded only "Ubuntu Server". Going forward the answer is 24.04 LTS; the historical answer is lost.
3. **`dc-01`'s DNS forwarders** are undocumented (G12): it lists only itself as DNS yet resolves `google.com`, so a forwarder or root-hints path exists but was never recorded. Capture it before any rebuild.
4. **Suricata sensor placement** (R4) is a design decision the original docs deliberately deferred, and this document does not have enough information to make it for the owner.
5. **The real management/upstream subnet** is redacted by binding repo policy and must stay that way — it lives in a gitignored `terraform.tfvars`, never in HCL, never in docs.
