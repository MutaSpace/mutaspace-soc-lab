# MutaSpace SOC Lab — IaC Reproduction Inventory

Source of truth: 26 markdown files (`README.md` + `docs/**`), repo root `/home/profz/projects/mutaspace-soc-lab`, branch `main`, HEAD `f1150f8`. Every fact below is cited as `path:line`.

---

## 1. Proxmox Host (the only physical machine)

### 1.1 Host identity and install parameters

| Attribute | Value | Citation |
|---|---|---|
| Role | Official MutaSpace SOC Lab Proxmox Host | `docs/proxmox/host-baseline.md:32` |
| Hostname | `mutaspace-soc-node01` | `README.md:342`; `docs/proxmox/installation-and-access.md:28,93`; `docs/proxmox/host-baseline.md:33` |
| Hypervisor | Proxmox VE (version **never stated**) | `README.md:341`; `docs/proxmox/installation-and-access.md:27` |
| Filesystem | `ext4` | `README.md:343`; `docs/proxmox/installation-and-access.md:29,74`; `docs/proxmox/host-baseline.md:35` |
| Target install disk | `/dev/nvme0n1` (internal NVMe) | `README.md:344`; `docs/proxmox/installation-and-access.md:30,53`; `docs/proxmox/host-baseline.md:36` |
| Install media | USB installer; USB explicitly NOT the target | `docs/proxmox/installation-and-access.md:38,44`; `docs/hardware/build-log.md:219-221` |
| Management access | Proxmox web UI, HTTPS, port `8006` | `docs/proxmox/installation-and-access.md:31-32,125`; `docs/proxmox/host-baseline.md:37-38` |
| Login realm | `root` / `Linux PAM standard authentication` | `docs/proxmox/installation-and-access.md:141-145` |
| Certificate | Self-signed, warning expected on first access | `docs/proxmox/installation-and-access.md:133,213-215` |
| Management addressing | **Static** (value redacted — see §5) | `docs/proxmox/installation-and-access.md:85`; `docs/proxmox/host-baseline.md:74`; `docs/hardware/hardware-validation.md:123` |
| Management link type | Wired Ethernet mandatory; Wi-Fi explicitly rejected | `docs/proxmox/installation-and-access.md:195-199` |

### 1.2 Physical hardware capacity

Identical parts table appears **four times** (a duplication hazard for IaC/doc drift):
`README.md:63-72`, `docs/hardware/README.md:19-27`, `docs/hardware/parts-list.md:15-23`, `docs/proxmox/host-baseline.md:60-68`.

| Category | Part | Capacity facts | Citation |
|---|---|---|---|
| Motherboard | GIGABYTE B650 AORUS Elite AX | AM5, DDR5, multiple M.2, **2.5GbE**, ATX | `docs/hardware/parts-list.md:29,35-40` |
| CPU | AMD Ryzen 9 7900X | **12 cores / 24 threads** | `docs/hardware/parts-list.md:48,54-55` |
| RAM | Silicon Power DDR5 64GB (2×32GB) 6000 MT/s | **64GB**; 2-DIMM config chosen to allow future 128GB | `docs/hardware/parts-list.md:76,80`; `docs/hardware/build-log.md:92-94` |
| Storage | Silicon Power 2TB UD90 NVMe Gen4 | **2TB**, single drive | `docs/hardware/parts-list.md:99` |
| PSU | MSI MAG A850GL PCIE5 850W | 80+ Gold, fully modular | `docs/hardware/parts-list.md:120,126-128` |
| Case | CORSAIR 3500X RS ARGB Mid-Tower | ATX, 360mm AIO support | `docs/hardware/parts-list.md:137,143-144` |
| Cooler | Arctic Liquid Freezer III Pro 360 A-RGB | 360mm AIO | `docs/hardware/parts-list.md:156` |

Planned future expansion (not built): 128GB RAM, second 2TB NVMe, Proxmox Backup Server / external backup, UPS, dual-port NIC or managed switch — `docs/hardware/parts-list.md:187-193`.

Stated learner capacity envelope: 4 individual learners; 6–8 paired; 10+ observing; full isolated per-student environments require scaling — `docs/hardware/parts-list.md:172-177`.

### 1.3 Host storage / repo / update state — **all still "Pending"**

`docs/proxmox/host-baseline.md:208-222` baseline checklist:

| Item | Documented status |
|---|---|
| Proxmox installed | Completed (`:211`) |
| Web interface accessible | Completed (`:212`) |
| Hostname configured | Completed (`:213`) |
| Static management address | Completed (`:214`) |
| Internal NVMe as install target | Completed (`:215`) |
| Hardware detected | Completed (`:216`) |
| **Storage reviewed** | **Pending** (`:217`) |
| **Repository configuration reviewed** | **Pending** (`:218`) |
| **Initial updates completed** | **Pending** (`:219`) |
| **Dashboard health checked** | **Pending** (`:220`) |
| **Ready for VM planning** | **Pending** (`:221`) |

Consequence for IaC: **no Proxmox storage IDs are ever named** (`local`, `local-lvm`, thin-pool, etc.). `docs/proxmox/host-baseline.md:106-115` only says the builder *should confirm* storage names, which storage supports ISO upload vs VM disks, and whether storage is thin-provisioned. Likewise repo config is described conceptually (enterprise vs no-subscription, `docs/proxmox/host-baseline.md:118-132`) but **the chosen repository is never recorded**.

---

## 2. Network

### 2.1 Bridges

| Bridge | Uplink | Role | Citation |
|---|---|---|---|
| `vmbr0` | `nic0` (physical Ethernet) | Proxmox management **and** firewall WAN | `README.md:127`; `docs/network/network-design.md:52`; `docs/network/proxmox-bridge-plan.md:54,60-78` |
| `vmbr1` | none (internal only) | Internal SOC LAN — all built VMs live here | `README.md:128`; `docs/network/network-design.md:53`; `docs/network/proxmox-bridge-plan.md:55,85-108` |
| `vmbr2` | none (internal only) | Isolated / untrusted (Kali, trust-boundary) — **planned, never built** | `README.md:129`; `docs/network/network-design.md:54`; `docs/network/proxmox-bridge-plan.md:56,112-133` |

Physical NIC is referred to only as `nic0` — `docs/network/proxmox-bridge-plan.md:31-45`. This is a documentation abstraction, not a real Linux ifname (expect `enp*`/`eno*`); the real interface name is never recorded. Proxmox management IP is assigned **to the bridge**, not the NIC — `docs/network/proxmox-bridge-plan.md:71,210-216`.

### 2.2 Subnets and addressing

| Item | Value | Citation |
|---|---|---|
| Internal SOC LAN | `10.10.10.0/24` | `docs/network/dhcp-validation.md:49,70`; `docs/incident-scenarios/failed-login-investigation.md:45`; `docs/incident-scenarios/account-creation-investigation.md:45` |
| LAN gateway (pfSense LAN) | `10.10.10.1/24` | `docs/vms/fw-01-firewall-plan.md:77,82,187`; `docs/network/dhcp-validation.md:70` |
| DHCP pool | `10.10.10.100 – 10.10.10.200` | `docs/vms/fw-01-firewall-plan.md:96`; `docs/network/dhcp-validation.md:71`; `docs/vms/dc-01-domain-controller-plan.md:102`; `docs/vms/analyst-01-build.md:72` |
| DHCP server | `fw-01` pfSense, LAN interface | `docs/vms/fw-01-firewall-plan.md:91`; `docs/network/internal-dns-validation.md:75` |
| DNS handed to DHCP clients | `10.10.10.10` (`dc-01`) — changed from pfSense | `docs/network/internal-dns-validation.md:77,192-198`; `docs/vms/analyst-01-build.md:247-255` |
| DNS domain handed via DHCP | `mutaspace.local` | `docs/network/internal-dns-validation.md:78` |
| Management/WAN subnet | **placeholder only** — example `10.0.0.0/24`, gw `10.0.0.1` | `README.md:349-358`; `docs/proxmox/installation-and-access.md:91-101` |
| pfSense WAN address | example `10.0.0.x/24`; DHCP-vs-static **never stated** | `docs/vms/fw-01-firewall-plan.md:76` |

Static IP allocation convention (implicit, never stated as a rule):

| Host | IP | Citation |
|---|---|---|
| `fw-01` LAN | `10.10.10.1` | `docs/vms/fw-01-firewall-plan.md:82` |
| `dc-01` | `10.10.10.10` | `docs/vms/dc-01-domain-controller-build.md:69` |
| `wazuh-01` | `10.10.10.20` | `docs/vms/wazuh-01-build.md:73` |
| `ubuntu-app-01` | `10.10.10.30` | `docs/vms/ubuntu-app-01-build.md:70` |
| `analyst-01` | DHCP | `docs/network/internal-dns-validation.md:32`; `docs/vms/wazuh-01-plan.md:110` |
| `win-client-01` | DHCP | `docs/wazuh/agent-enrollment-windows-client.md:33` |

### 2.3 Active Directory / DNS

| Item | Value | Citation |
|---|---|---|
| AD forest / root domain | `mutaspace.local` (new forest) | `docs/vms/dc-01-domain-controller-build.md:83,174` |
| NetBIOS domain name | `MUTASPACE` | `docs/vms/dc-01-domain-controller-build.md:89` |
| Login format (domain) | `MUTASPACE\Administrator` | `docs/wazuh/agent-enrollment-windows-client.md:238` |
| Login format (local) | `.\localusername` | `docs/wazuh/agent-enrollment-windows-client.md:244` |
| DNS server | `dc-01` @ `10.10.10.10`, DNS Server role | `docs/vms/dc-01-domain-controller-build.md:100-103` |
| Global Catalog | Enabled | `docs/vms/dc-01-domain-controller-build.md:175` |
| RODC | Disabled | `docs/vms/dc-01-domain-controller-build.md:176` |
| Forward A record | `wazuh-01.mutaspace.local` → `10.10.10.20` | `docs/vms/wazuh-01-build.md:85-90` |
| Forward A record | `ubuntu-app-01.mutaspace.local` → `10.10.10.30` | `docs/vms/ubuntu-app-01-build.md:82-87` |
| Reverse zone | "added for the internal SOC lab network" — **zone name never stated** | `docs/vms/ubuntu-app-01-build.md:89-91`, checklist `:234` |
| DNS resolution chain (design) | Internal clients → `dc-01` DNS → upstream as needed | `docs/network/internal-dns-validation.md:58`; `docs/vms/dc-01-domain-controller-plan.md:150` |
| Ubuntu stub resolver caveat | `127.0.0.53` via systemd-resolved is expected/normal | `docs/network/internal-dns-validation.md:96-105` |
| AD user objects created | `test.user` (lab 01), `lab.user02` (lab 02) | `docs/incident-scenarios/failed-login-investigation.md:144`; `docs/incident-scenarios/account-creation-investigation.md:146-149` |

### 2.4 Planned traffic flow (design intent for IaC firewall rules)

```
Outside Network -> nic0 -> vmbr0 -> Firewall VM -> { vmbr1 SOC LAN, vmbr2 Isolated }
```
`docs/network/proxmox-bridge-plan.md:153-164`; `docs/network/network-design.md:155-164`.

Planned firewall interface map (3 legs) — `docs/network/network-design.md:131-135`; `docs/network/proxmox-bridge-plan.md:141-145`. **Only 2 legs were actually built** (see §4).

---

## 3. VM Inventory — BUILT

Legend: "—" = never stated anywhere in the repo (an IaC gap).

### 3.1 `fw-01` — pfSense firewall/router

| Field | Value | Citation |
|---|---|---|
| VM ID | **— never stated** | absent from `docs/vms/fw-01-firewall-plan.md`, `docs/network/dhcp-validation.md:27` |
| Guest OS | pfSense Community Edition; **version never stated** | `docs/vms/fw-01-firewall-plan.md:33,45` |
| Boot media | Netgate Installer ISO, AMD64 VM variant, shipped as `.iso.gz` | `docs/vms/fw-01-firewall-plan.md:49,105-107` |
| vCPU | 2 | `docs/vms/fw-01-firewall-plan.md:46` |
| RAM | 4GB / 4096MB (raised from 2048MB post-install) | `docs/vms/fw-01-firewall-plan.md:47,148-163` |
| Disk | 20GB | `docs/vms/fw-01-firewall-plan.md:48` |
| Disk controller/bus | **—** | — |
| NIC model | **—** in Proxmox terms; pfSense sees `vtnet0`/`vtnet1` ⇒ VirtIO implied, never stated | `docs/vms/fw-01-firewall-plan.md:61-62,180-181` |
| NICs / bridges | net0 → `vmbr0` (WAN/`vtnet0`), net1 → `vmbr1` (LAN/`vtnet1`) | `docs/vms/fw-01-firewall-plan.md:50-51,59-62` |
| WAN IP | example `10.0.0.x/24`; method **—** | `docs/vms/fw-01-firewall-plan.md:76` |
| LAN IP | `10.10.10.1/24` static | `docs/vms/fw-01-firewall-plan.md:77,82` |
| Role | Firewall, router, gateway, DHCP server, DNS forwarder | `docs/vms/fw-01-firewall-plan.md:11-22,36` |
| Services | DHCP on LAN (`10.10.10.100-200`); DNS forwarding; DHCP option DNS = `10.10.10.10`, domain `mutaspace.local` | `docs/vms/fw-01-firewall-plan.md:91-99`; `docs/network/internal-dns-validation.md:73-78` |
| Wazuh agent | **No** — never enrolled anywhere | absent from all `docs/wazuh/*` |
| Post-install | ISO detached, boot from virtual disk | `docs/vms/fw-01-firewall-plan.md:175,201-204` |

### 3.2 `test-client-01` — temporary validation VM

| Field | Value | Citation |
|---|---|---|
| VM ID | `101` | `docs/vms/test-client-01-build.md:31`; `docs/network/dhcp-validation.md:82` |
| Guest OS | "Ubuntu Linux" — **no version, no desktop/server variant** | `docs/vms/test-client-01-build.md:32` |
| vCPU / RAM / Disk | 2 / 2GB / 20GB | `docs/vms/test-client-01-build.md:33-35` |
| Disk bus / NIC model | **— / —** | — |
| Bridge | `vmbr1` (explicitly not `vmbr0`) | `docs/vms/test-client-01-build.md:36,43-58` |
| Addressing | DHCP, expected `10.10.10.x`, gw `10.10.10.1` | `docs/vms/test-client-01-build.md:66-72` |
| Role | Temporary network validation client | `docs/vms/test-client-01-build.md:37,5` |
| Services | none | — |
| Wazuh agent | **No** | — |
| Lifecycle | Called "temporary", "not a permanent production system"; **deletion never documented** | `docs/vms/test-client-01-build.md:5` |

### 3.3 `dc-01` — Windows Server domain controller

| Field | Value | Citation |
|---|---|---|
| VM ID | `102` | `docs/vms/dc-01-domain-controller-build.md:31` |
| Guest OS | Windows Server **2022 Evaluation** | `docs/vms/dc-01-domain-controller-build.md:32,109` |
| vCPU | 2 | `docs/vms/dc-01-domain-controller-build.md:34` |
| RAM | 4GB | `docs/vms/dc-01-domain-controller-build.md:35` |
| Disk | 60GB | `docs/vms/dc-01-domain-controller-build.md:36` |
| **Disk controller/bus** | **SATA** (deliberate; VirtIO rejected to avoid driver injection) | `docs/vms/dc-01-domain-controller-build.md:37,111-115,136` |
| **NIC model** | **E1000** (only VM in the lab not on VirtIO) | `docs/vms/dc-01-domain-controller-build.md:39` |
| Bridge | `vmbr1` | `docs/vms/dc-01-domain-controller-build.md:38` |
| IP | static `10.10.10.10`, mask `255.255.255.0`, gw `10.10.10.1`, DNS `10.10.10.10` (self) | `docs/vms/dc-01-domain-controller-build.md:69-72,189` |
| Role | AD DS + DNS, first DC of new forest `mutaspace.local` | `docs/vms/dc-01-domain-controller-build.md:33,100-103,170-178` |
| Services installed | Active Directory Domain Services; DNS Server | `docs/vms/dc-01-domain-controller-build.md:100-103` |
| Wazuh agent | **Yes** — enrolled as `dc-01`, service `WazuhSvc` Running | `docs/wazuh/agent-enrollment-windows.md:104,120-128,151-155` |

### 3.4 `analyst-01` — Ubuntu analyst workstation

| Field | Value | Citation |
|---|---|---|
| VM ID | `103` | `docs/vms/analyst-01-build.md:32` |
| Guest OS | **Ubuntu Desktop 24.04 LTS** | `docs/vms/analyst-01-build.md:33` |
| vCPU / RAM / Disk | 2 / 4GB / 40GB | `docs/vms/analyst-01-build.md:35-37` |
| Disk bus | **—** | — |
| NIC model | VirtIO | `docs/vms/analyst-01-build.md:39` |
| Bridge | `vmbr1` | `docs/vms/analyst-01-build.md:38` |
| Addressing | **DHCP** from pfSense; DNS `10.10.10.10`, search domain `mutaspace.local` | `docs/vms/analyst-01-build.md:80-89`; `docs/network/internal-dns-validation.md:32` |
| Domain-joined? | **No** — never stated as joined to `mutaspace.local` | — |
| Role | Analyst workstation; Wazuh dashboard client | `docs/vms/analyst-01-build.md:34,11-22` |
| Services | none installed; uses `resolvectl`, browser | `docs/vms/analyst-01-build.md:118-128` |
| Wazuh agent | **Yes** — enrolled as `analyst-01`, DEB amd64 | `docs/wazuh/agent-enrollment-linux.md:31-33,86-88,121-125` |

### 3.5 `wazuh-01` — Wazuh SIEM (all-in-one)

| Field | Value | Citation |
|---|---|---|
| VM ID | `104` | `docs/vms/wazuh-01-build.md:36` |
| Guest OS | "Ubuntu Server" — **version not confirmed in build** (plan preferred 22.04 LTS) | `docs/vms/wazuh-01-build.md:37`; `docs/vms/wazuh-01-plan.md:51-58` |
| vCPU / RAM / Disk | 4 / 8GB / 100GB | `docs/vms/wazuh-01-build.md:39-41` |
| Disk bus | **—** | — |
| NIC model | VirtIO | `docs/vms/wazuh-01-build.md:43` |
| Bridge | `vmbr1` | `docs/vms/wazuh-01-build.md:42` |
| IP | static `10.10.10.20/24`, gw `10.10.10.1`, DNS `10.10.10.10`, domain `mutaspace.local` | `docs/vms/wazuh-01-build.md:73-77` |
| Hostname | `wazuh-01`; FQDN `wazuh-01.mutaspace.local` | `docs/vms/wazuh-01-build.md:165-172,88` |
| Role | SIEM: Wazuh manager + indexer + dashboard on one VM | `docs/vms/wazuh-01-build.md:38,98-107` |
| Install method | Official Wazuh installation script, run locally | `docs/vms/wazuh-01-build.md:114-116` |
| Wazuh version | **— never stated** | — |
| Dashboard URL | `https://10.10.10.20` and `https://wazuh-01.mutaspace.local` — **port never stated** | `docs/vms/wazuh-01-build.md:130,135`; cf. plan `docs/vms/wazuh-01-plan.md:186` |
| Services | `wazuh-manager`, `wazuh-indexer`, `wazuh-dashboard` (active/running) | `docs/vms/wazuh-01-build.md:294-304` |
| Credentials | Default generated dashboard password changed post-install; **never committed** | `docs/vms/wazuh-01-build.md:144-153` |
| Wazuh agent on itself | **No** — not documented | — |

### 3.6 `ubuntu-app-01` — Linux application server

| Field | Value | Citation |
|---|---|---|
| VM ID | `106` | `docs/vms/ubuntu-app-01-build.md:33` |
| Guest OS | "Ubuntu Server" — **no version** | `docs/vms/ubuntu-app-01-build.md:34` |
| vCPU / RAM / Disk | 2 / 4GB / 40GB | `docs/vms/ubuntu-app-01-build.md:36-38` |
| Disk bus | **—** | — |
| NIC model | VirtIO | `docs/vms/ubuntu-app-01-build.md:40` |
| Bridge | `vmbr1` | `docs/vms/ubuntu-app-01-build.md:39` |
| IP | static `10.10.10.30/24`, gw `10.10.10.1`, DNS `10.10.10.10`, domain `mutaspace.local` | `docs/vms/ubuntu-app-01-build.md:70-74` |
| DNS records | A `ubuntu-app-01.mutaspace.local` → `10.10.10.30` on `dc-01`; reverse zone added | `docs/vms/ubuntu-app-01-build.md:82-91` |
| Role | Linux application server / monitored target | `docs/vms/ubuntu-app-01-build.md:35` |
| Services installed | **OpenSSH Server** (`systemctl enable --now ssh`), **Nginx** (default welcome page served over HTTP) | `docs/vms/ubuntu-app-01-build.md:99-154` |
| Wazuh agent | **Yes** — agent name `ubuntu-app-01`, manager `wazuh-01.mutaspace.local`, DEB | `docs/vms/ubuntu-app-01-build.md:165-194,213-223` |

### 3.7 `win-client-01` — Windows domain workstation ⚠️ **built but has NO build doc**

Only evidence is the agent-enrollment doc; every hypervisor-level parameter is missing.

| Field | Value | Citation |
|---|---|---|
| VM ID | **— never stated** (VM ID `105` is unused in the 101→106 sequence, strongly implying this VM) | inferred from `101`/`102`/`103`/`104`/`106` |
| Guest OS | **— never stated** (Windows 10? 11? Server?) | — |
| vCPU / RAM / Disk / bus / NIC model | **— all missing** | — |
| Bridge | `vmbr1` (explicitly not `vmbr0`) | `docs/wazuh/agent-enrollment-windows-client.md:78-91` |
| Addressing | DHCP | `docs/wazuh/agent-enrollment-windows-client.md:33` |
| Domain | Joined to `mutaspace.local`; DC `dc-01`; DNS `10.10.10.10` | `docs/wazuh/agent-enrollment-windows-client.md:97-113,189` |
| Computer rename | Renamed to `win-client-01` | `docs/wazuh/agent-enrollment-windows-client.md:188` |
| Role | Standard Windows domain workstation / telemetry source | `docs/wazuh/agent-enrollment-windows-client.md:13` |
| Services | none beyond OS + agent; **Sysmon NOT installed** | — |
| Wazuh agent | **Yes** — agent name `win-client-01`, `WazuhSvc` Running | `docs/wazuh/agent-enrollment-windows-client.md:140-166` |

### 3.8 Built-VM roll-up (for host sizing)

| VM | ID | vCPU | RAM | Disk | Bridge | Agent |
|---|---|---|---|---|---|---|
| `fw-01` | — | 2 | 4GB | 20GB | vmbr0+vmbr1 | No |
| `test-client-01` | 101 | 2 | 2GB | 20GB | vmbr1 | No |
| `dc-01` | 102 | 2 | 4GB | 60GB | vmbr1 | Yes |
| `analyst-01` | 103 | 2 | 4GB | 40GB | vmbr1 | Yes |
| `wazuh-01` | 104 | 4 | 8GB | 100GB | vmbr1 | Yes |
| `win-client-01` | ?105 | — | — | — | vmbr1 | Yes |
| `ubuntu-app-01` | 106 | 2 | 4GB | 40GB | vmbr1 | Yes |
| **Documented total** | | **14 vCPU** | **26GB** | **280GB** | | 4 agents |

Against a 24-thread / 64GB / 2TB host — comfortable headroom, but `win-client-01`'s unknown footprint means the true total is undocumented.

---

## 4. VMs in the README "Planned Architecture" table that were NEVER built

`README.md:104-115` lists ten VMs. Build/plan doc coverage:

| Planned VM (`README.md`) | Purpose (README) | Doc status | Verdict |
|---|---|---|---|
| `fw-01` (`:106`) | Firewall/router | `docs/vms/fw-01-firewall-plan.md` (is actually a build record) | **Built** |
| `dc-01` (`:107`) | AD DC + DNS | plan + build | **Built** |
| `wazuh-01` (`:108`) | SIEM | plan + build | **Built** |
| **`sensor-01`** (`:109`) | Suricata network IDS | **no plan, no build** | **NEVER BUILT — future work** |
| `win-client-01` (`:110`) | Windows endpoint w/ telemetry | agent-enrollment doc only, **no build doc** | Built but undocumented |
| `ubuntu-app-01` (`:111`) | Linux target/server | build doc | **Built** |
| `ubuntu-analyst-01` (`:112`) | Ubuntu analyst workstation | built under the **different name `analyst-01`** | Built, name mismatch |
| **`kali-01`** (`:113`) | Controlled attack simulation | **no plan, no build** | **NEVER BUILT — future work** |
| **`untrusted-01`** (`:114`) | Trust-boundary research VM | **no plan, no build** | **NEVER BUILT — future work** |
| **`nlp-01`** (`:115`) | Phishing/NLP research VM | **no plan, no build**; also absent from the vNIC placement table `docs/network/network-design.md:198-208` | **NEVER BUILT — future work; no bridge assigned** |

Additionally never built despite being named as core infrastructure:
- **`vmbr2`** bridge — planned in `README.md:129`, `docs/network/network-design.md:54`, `docs/network/proxmox-bridge-plan.md:56,112-133`; **no doc records its creation**, and `fw-01` was built with only 2 NICs (`docs/vms/fw-01-firewall-plan.md:50-51,57`).
- **`fw-01` OPT/DMZ interface** on `vmbr2` — planned `docs/network/network-design.md:135`, `docs/network/proxmox-bridge-plan.md:145`; not present in the build.
- **Suricata**, **Sysmon**, **Kali**, **TheHive**, **Shuffle**, **Velociraptor**, **Zeek**, **Sigma** — listed in `README.md:230-241,532-551` but no deployment doc.
- **Python automation scripts** — required by Definition of Done (`README.md:462`), roadmap (`README.md:513-516`); repo contains **zero code files** (docs-only; `.gitignore` present but no `src/`, no scripts).

---

## 5. Contradictions and Gaps

### 5.1 Hard contradictions between documents

| # | Contradiction | Citations |
|---|---|---|
| C1 | **VM name mismatch.** README + network design call the analyst workstation `ubuntu-analyst-01`; every build/validation/agent doc calls it `analyst-01`. | `README.md:112`, `docs/network/network-design.md:205` **vs** `docs/vms/analyst-01-build.md:30`, `docs/network/internal-dns-validation.md:32`, `docs/wazuh/agent-enrollment-linux.md:31` |
| C2 | **Filename says "plan", content is a build.** `fw-01-firewall-plan.md` opens with `# fw-01 Firewall Build` and records completed installation, boot errors, and validation. Breaks the repo's own plan/build split. | `docs/vms/fw-01-firewall-plan.md:1,3` (filename vs H1) |
| C3 | **fw-01 memory changed mid-document.** Config table declares 4GB; the "Memory Issue" section says the VM was originally assigned 2048MB and raised to 4096MB after instability. IaC must provision 4096MB, not 2048. | `docs/vms/fw-01-firewall-plan.md:47` **vs** `:148-163` |
| C4 | **fw-01 validation checklist stale.** Lists "Test VM receives DHCP address / ping gateway / reach internet / DNS resolution" as **Pending**, but two other docs record all four as **Passed**. | `docs/vms/fw-01-firewall-plan.md:210-213` **vs** `docs/network/dhcp-validation.md:179-185`, `docs/vms/test-client-01-build.md:148-154` |
| C5 | **Host baseline checklist stale.** "Storage reviewed / Repository configuration reviewed / Initial updates completed / Dashboard health checked / **Ready for VM planning**" are all *Pending* — yet six VMs, a SIEM, and two incident labs were subsequently built. | `docs/proxmox/host-baseline.md:217-221` vs the whole of `docs/vms/**` |
| C6 | **README "In Progress" / "Completed Milestones" stale.** README stops at "Proxmox web interface accessed" and lists virtual network design, storage review, repo config as *in progress*; it never mentions any built VM, the domain, Wazuh, agents, or the two completed labs. | `README.md:362-385` vs `docs/vms/**`, `docs/wazuh/**`, `docs/incident-scenarios/**` |
| C7 | **dc-01 sizing range vs actual.** Plan: vCPU "2 to 4", Memory "4GB to 6GB". Build: 2 vCPU / 4GB. Plan also omits disk bus and NIC model entirely. | `docs/vms/dc-01-domain-controller-plan.md:64-65` **vs** `docs/vms/dc-01-domain-controller-build.md:34-35` |
| C8 | **dc-01 OS specificity.** Plan says generic "Windows Server"; build says "Windows Server 2022 Evaluation". Evaluation media expires — a reproducibility hazard never flagged. | `docs/vms/dc-01-domain-controller-plan.md:50` **vs** `docs/vms/dc-01-domain-controller-build.md:32,109` |
| C9 | **wazuh-01 OS version lost.** Plan explicitly prefers Ubuntu Server 22.04 LTS (over 24.04); build records only "Ubuntu Server". The actual installed release is unknowable from the repo. | `docs/vms/wazuh-01-plan.md:51-62` **vs** `docs/vms/wazuh-01-build.md:37` |
| C10 | **wazuh-01 "minimum" vs fixed.** Plan says "8GB minimum" / "100GB minimum"; build provisioned exactly 8GB/100GB. Wazuh all-in-one at 8GB is at the documented floor. | `docs/vms/wazuh-01-plan.md:74-75` **vs** `docs/vms/wazuh-01-build.md:40-41` |
| C11 | **fw-01 planned 3 interfaces, built 2.** Network design and bridge plan both specify an OPT/DMZ leg on `vmbr2`; the build has only WAN+LAN. | `docs/network/network-design.md:131-135`, `docs/network/proxmox-bridge-plan.md:141-145` **vs** `docs/vms/fw-01-firewall-plan.md:50-51,57` |
| C12 | **DHCP DNS server changed after the fact.** pfSense initially handed itself as DNS; docs record the corrective change to `10.10.10.10`. IaC must encode the *final* state, not the first. | `docs/network/internal-dns-validation.md:186-198`; `docs/vms/analyst-01-build.md:245-255` |
| C13 | **Dashboard access "port TBD" never resolved.** Plan: "The exact port and URL will be documented after installation." Build documents URLs with no port. | `docs/vms/wazuh-01-plan.md:186` **vs** `docs/vms/wazuh-01-build.md:130,135` |
| C14 | **README claims Suricata is a "Core Lab Tool"** and Definition of Done requires "Suricata generating alerts", while `sensor-01` was never built and its placement is undecided. | `README.md:238,457` vs §5.2 G6 |

### 5.2 Gaps — facts IaC needs that no document supplies

| # | Gap | Where it should have been |
|---|---|---|
| G1 | **`fw-01` VM ID never stated.** Every other built VM has one. | `docs/vms/fw-01-firewall-plan.md:42-52`; also absent `docs/network/dhcp-validation.md:27-32` |
| G2 | **`win-client-01` VM ID, OS, vCPU, RAM, disk, bus, NIC model all missing** — no build doc exists at all. VM ID `105` is the only hole in the 101–106 sequence. | would be `docs/vms/win-client-01-build.md` (absent) |
| G3 | **Disk controller/bus stated for exactly one VM** (`dc-01` = SATA). All others (`fw-01`, `test-client-01`, `analyst-01`, `wazuh-01`, `ubuntu-app-01`) have no bus recorded — IaC must guess SCSI/VirtIO-SCSI vs SATA vs IDE. | all `docs/vms/*-build.md` config tables |
| G4 | **NIC model missing for `fw-01` and `test-client-01`.** `fw-01`'s pfSense interface names `vtnet0/vtnet1` imply VirtIO but this is never asserted. | `docs/vms/fw-01-firewall-plan.md:42-52`; `docs/vms/test-client-01-build.md:28-38` |
| G5 | **Sensor placement explicitly TBD.** "Suricata sensor placement, depending on final design" and "`sensor-01` — Placement depends on monitoring design". No mirror port, no bridge, no promiscuous config. | `docs/network/network-design.md:92,208`; `docs/network/dhcp-validation.md:212` |
| G6 | **Real management network values are placeholders by policy.** `<LAB_MANAGEMENT_IP>/24`, `<LAB_GATEWAY_IP>`, `<DNS_SERVER>`; examples `10.0.0.50/24`, `10.0.0.1`, `1.1.1.1`. The genuine upstream subnet is deliberately absent — IaC needs a variable/secret, not a literal. | `README.md:349-358`; `docs/proxmox/installation-and-access.md:91-101`; `docs/proxmox/host-baseline.md:80-89`; `docs/hardware/hardware-validation.md:144-147` |
| G7 | **pfSense WAN addressing method unknown** — DHCP from the home router or static `10.0.0.x`? Only an "Example Address" is given. | `docs/vms/fw-01-firewall-plan.md:74-77` |
| G8 | **Physical NIC name is a fiction (`nic0`).** Real Proxmox ifname (e.g. `enp*`) never recorded; `vmbr0` bridge-ports value is therefore unknown. | `docs/network/proxmox-bridge-plan.md:31-45` |
| G9 | **No Proxmox storage IDs.** `local` / `local-lvm` / thin-pool names, sizes, and content-types are never recorded (baseline says to review them — still Pending). | `docs/proxmox/host-baseline.md:93-115,217` |
| G10 | **Repository choice never recorded** (enterprise vs no-subscription). | `docs/proxmox/host-baseline.md:118-132,218` |
| G11 | **Reverse DNS zone name never stated** (presumably `10.10.10.in-addr.arpa`); scavenging/updates policy absent. | `docs/vms/ubuntu-app-01-build.md:89-91` |
| G12 | **`dc-01` DNS forwarders undocumented.** `dc-01` lists only itself as DNS, yet resolves `google.com` — a forwarder or root-hints path must exist but is never recorded. | `docs/vms/dc-01-domain-controller-build.md:72,189` vs `:246-254` |
| G13 | **No DHCP reservations.** `analyst-01` and `win-client-01` are pure DHCP; their addresses are nondeterministic across rebuilds, which breaks reproducible detection labs. | `docs/vms/analyst-01-build.md:80`; `docs/wazuh/agent-enrollment-windows-client.md:33` |
| G14 | **No Netplan/`resolved` config captured** for the static Linux hosts, despite Netplan being a stated learning area. Only `resolvectl status` output is shown. | `README.md:176`; `docs/vms/wazuh-01-build.md:71-77`; `docs/vms/ubuntu-app-01-build.md:70-74` |
| G15 | **Versions missing across the board:** Proxmox VE, pfSense CE, Wazuh, Ubuntu Server (×2), Windows client OS. Only `dc-01` (Server 2022 Eval) and `analyst-01` (Ubuntu Desktop 24.04 LTS) are pinned. | see §3 |
| G16 | **`test-client-01` lifecycle unresolved** — declared temporary, never documented as deleted. IaC cannot tell whether to create it. | `docs/vms/test-client-01-build.md:5,37` |
| G17 | **Wazuh agent enrollment details thin:** dashboard-generated commands only; no agent groups, no registration key/authd config, no `ossec.conf` content, no agent versions, no FIM/`localfile` tuning. | `docs/wazuh/agent-enrollment-linux.md:74-88`; `docs/wazuh/agent-enrollment-windows.md:80-96`; `docs/wazuh/agent-enrollment-windows-client.md:117-133` |
| G18 | **No NTP/time-sync or timezone documentation** anywhere — critical for SIEM correlation and for AD Kerberos. | absent repo-wide |
| G19 | **No firewall rule set documented.** pfSense rules, NAT, and inter-bridge policy are described only as intent ("traffic between networks is controlled by firewall rules"). | `docs/network/network-design.md:285`; `docs/network/proxmox-bridge-plan.md:247` |
| G20 | **AD objects created ad hoc in lab docs** (`test.user`, `lab.user02`) with no OU structure, group policy, or user-provisioning doc. | `docs/incident-scenarios/failed-login-investigation.md:144`; `docs/incident-scenarios/account-creation-investigation.md:146-149` |
| G21 | **`nlp-01` has no bridge assignment** — omitted from the vNIC placement table that covers the other nine planned VMs. | `README.md:115` vs `docs/network/network-design.md:198-208` |
| G22 | **No snapshot/template/backup policy implemented.** Snapshots are recommended ("Mistake: Skipping snapshots") but none are recorded as taken. | `docs/vms/wazuh-01-plan.md:265-269` |
| G23 | **No Wazuh custom rules, MITRE mapping, tuning journal** — required by Definition of Done but absent. | `README.md:458-459` |

### 5.3 Known-issue / troubleshooting facts that constrain IaC choices

These are documented root causes an IaC implementation must preserve or deliberately override:

- **pfSense ISO ships as `.iso.gz`** and must be decompressed before upload, else `Boot failed: Could not read from CDROM / No bootable device` — `docs/vms/fw-01-firewall-plan.md:105-143`.
- **Windows Server installer shows "We couldn't find any drives"** on the default (non-SATA) controller; resolved by switching the disk to SATA rather than injecting VirtIO drivers — `docs/vms/dc-01-domain-controller-build.md:120-144`.
- **Wazuh dashboard's default generated agent command is RPM**; Ubuntu requires selecting `DEB amd64` (`rpm: command not found`) — `docs/wazuh/agent-enrollment-linux.md:92-116`.
- **Wazuh agent package `403 Forbidden`** from a wrong download path; correct path includes the `wazuh-agent` directory and DEB format — `docs/vms/ubuntu-app-01-build.md:211-223`.
- **`wazuh-01.mutaspace.local` did not resolve** until an A record was manually created on `dc-01` (static-IP Linux hosts do not self-register in AD DNS) — `docs/vms/wazuh-01-build.md:337-351`.
- **Clients received pfSense as DNS instead of the DC**, breaking internal AD resolution until the DHCP DNS option was changed to `10.10.10.10` — `docs/network/internal-dns-validation.md:186-198`.
- **DDR5 first-boot memory training** causes a long black screen; not a build failure — `docs/hardware/build-log.md:187-198`.
- **Wazuh install script must be invoked from the expected location**; a mistyped invocation caused the first attempt to fail — `docs/vms/wazuh-01-build.md:329-335`.

---

## 6. Detection / Scenario Content (state that IaC must seed)

| Lab | File | Event IDs | Agent | Key artifacts |
|---|---|---|---|---|
| Lab 01: Failed Login Investigation | `docs/incident-scenarios/failed-login-investigation.md` | `4625` (primary), `4624` (related) — `:86,98` | `win-client-01` | Account `MUTASPACE\test.user`, 3–5 failed attempts (`:144,152`); query `agent.name: "win-client-01" AND data.win.system.eventID: "4625"` (`:204`) |
| Lab 02: Account Creation Investigation | `docs/incident-scenarios/account-creation-investigation.md` | `4720` (primary); related `4722`, `4726`, `4738`, `4732` — `:80,92-96` | `dc-01` | User `lab.user02` (Lab / User02) created in `Users` container via ADUC (`:135-152`); query `agent.name: "dc-01" AND data.win.system.eventID: "4720"` (`:188`) |

Documented pitfall shared by both: searching **File Integrity Monitoring** instead of **Threat Hunting / Security Events** — `docs/incident-scenarios/failed-login-investigation.md:209-221,297-308`.

Wazuh agent coverage asserted at lab time: `analyst-01`, `dc-01`, `win-client-01` (note: **`ubuntu-app-01` is absent from both lab agent tables** even though it was enrolled) — `docs/incident-scenarios/failed-login-investigation.md:69-73`; `docs/incident-scenarios/account-creation-investigation.md:57-61` vs `docs/vms/ubuntu-app-01-build.md:244-246`.

---

## 7. Documentation Conventions

### 7.1 Directory and file naming

```
README.md                                  # project-level overview
docs/README.md                             # documentation standard + principles
docs/<area>/README.md                       # area index (hardware/, proxmox/ only)
docs/hardware/{parts-list,build-log,hardware-validation}.md
docs/proxmox/{installation-and-access,host-baseline}.md
docs/network/{network-design,proxmox-bridge-plan,dhcp-validation,internal-dns-validation}.md
docs/vms/<vm-name>[-<role>]-{plan,build}.md
docs/wazuh/agent-enrollment-<platform>[-<variant>].md
docs/incident-scenarios/<topic>-investigation.md
```

- **All lowercase, hyphen-separated**, `.md` only. No dates, no numeric prefixes in filenames.
- `README.md` is the only capitalized filename; area READMEs exist for `hardware/` and `proxmox/` but **not** for `network/`, `vms/`, `wazuh/`, `incident-scenarios/` (an inconsistency).
- VM doc naming is **inconsistent about the role segment**: `dc-01-domain-controller-{plan,build}.md` and `fw-01-firewall-plan.md` include a role; `wazuh-01-{plan,build}.md`, `analyst-01-build.md`, `test-client-01-build.md`, `ubuntu-app-01-build.md` do not.
- Incident labs are titled `Lab 01:` / `Lab 02:` **inside** the file but the numbering is not in the filename — `docs/incident-scenarios/failed-login-investigation.md:1`, `docs/incident-scenarios/account-creation-investigation.md:1`.

### 7.2 The plan-vs-build split

The repo's declared pattern: a `-plan.md` written *before* the work, then a `-build.md` recording *what actually happened*.

| VM | plan | build | Notes |
|---|---|---|---|
| `dc-01` | ✅ `dc-01-domain-controller-plan.md` | ✅ `dc-01-domain-controller-build.md` | canonical example of the pattern |
| `wazuh-01` | ✅ `wazuh-01-plan.md` | ✅ `wazuh-01-build.md` | canonical |
| `fw-01` | ⚠️ filename `-plan.md`, content is a build | ❌ | **pattern violated** (C2) |
| `analyst-01`, `test-client-01`, `ubuntu-app-01` | ❌ | ✅ | build-only |
| `win-client-01` | ❌ | ❌ | neither (only an enrollment doc) |

Structural signatures:
- **Plan docs** use future tense ("will provide"), "Planned X" headings (`Planned Operating System`, `Planned VM Configuration`, `Planned IP Addressing`, `Planned Validation Goals`), plus `Common Beginner Mistakes` and `Troubleshooting Mindset` (numbered 1–10 diagnostic question lists) — e.g. `docs/vms/dc-01-domain-controller-plan.md:46,57,96,189,208,240`; `docs/vms/wazuh-01-plan.md:46,66,103,224,243,273`.
- **Build docs** use past tense, an exact `VM Configuration` table, an `IP Configuration` table, a per-command `Validation Commands` section (fenced `bash`/`powershell` + `Expected result` / `Result: Passed`), a `Validation Results` status table, `Troubleshooting Notes`, `Why This Matters`, and `Learning Reflection` — e.g. `docs/vms/dc-01-domain-controller-build.md:26,63,196,286,317,331`.

### 7.3 Section vocabulary (recurring, near-mandatory)

Every substantive doc closes with a `## Learning Reflection`. Other high-frequency headings: `VM Purpose`, `Network Placement`, `Validation Purpose`, `Validation Commands`, `Validation Results`, `Why This Matters`, `Troubleshooting Notes` / `Troubleshooting Lessons` / `Troubleshooting Mindset`, `Common Beginner Mistakes` / `Common Mistakes`, `SOC Learning Value`, `Skills Practiced`, `Lessons Learned`.

Formatting conventions:
- `---` horizontal rules between every major section (universal).
- Two-column `| Setting | Value |` tables for configuration; `| Validation Item | Status |` tables where Status ∈ {`Completed`, `Pending`, `Passed`}.
- Fenced ```` ```text ```` blocks used for *emphasis of single values* (hostnames, IPs, domains, error strings), not just code — e.g. `docs/vms/wazuh-01-build.md:52-54`, `docs/vms/fw-01-firewall-plan.md:121-124`.
- Root causes and resolutions are written as fenced `text` blocks under `Root cause:` / `Resolution:` — `docs/vms/dc-01-domain-controller-build.md:126-140`, `docs/vms/wazuh-01-build.md:339-349`.
- ASCII network diagrams in ```` ```text ```` blocks — `docs/network/proxmox-bridge-plan.md:153-164`, `docs/network/dhcp-validation.md:38-50`.
- Backticks around every hostname, bridge, IP, path, and filename inline.
- **No emoji, no images, no external links, no code files** anywhere in the repo.

### 7.4 Tone

Second-person-free, plain declarative prose. Short paragraphs (often one sentence). Explicitly teaching-oriented: "explain not only what was built, but why each decision matters" (`docs/README.md:14`). Failure is documented as first-class content — "This lab is not documented as a perfect environment… including setup decisions, troubleshooting, corrections, and lessons learned" (`docs/README.md:32-34`), and "Documentation during failure is just as valuable as documentation during success" (`README.md:440`). Successful steps with no problems are still documented as such — "not every milestone requires a problem" (`docs/network/dhcp-validation.md:234`).

The five stated documentation principles — `docs/README.md:40-56`: 1. Clarity over complexity; 2. Validation over assumptions; 3. Troubleshooting is part of the lab; 4. Security matters; 5. Teaching matters.

The build philosophy block, verbatim (`README.md:417-424`):
```text
Build it.
Understand it.
Validate it.
Document it.
Teach it.
Research it.
```

### 7.5 Security / placeholder policy for public docs

This is a **binding repo policy** that IaC must respect (real values belong in variables/secrets, never in committed docs).

- Canonical statement — `README.md:347`: *"Public documentation uses example values and placeholders. Real credentials, public IP addresses, MAC addresses, SSH keys, API tokens, and sensitive screenshots should never be published."*
- Placeholder token style: angle-bracket UPPER_SNAKE — `<LAB_MANAGEMENT_IP>`, `<LAB_GATEWAY_IP>`, `<DNS_SERVER>` — always paired with an adjacent "Example …" row giving an RFC1918 sample. Repeated verbatim in four places: `README.md:349-358`, `docs/proxmox/installation-and-access.md:91-101`, `docs/proxmox/host-baseline.md:80-89`, `docs/hardware/hardware-validation.md:144-147`.
- Prohibited-publication list (superset across docs): root/Wazuh passwords, real public IPs, MAC addresses, SSH keys, API tokens, private keys, sensitive screenshots, **router details**, **port-forwarding details** — `docs/proxmox/README.md:126-137`, `docs/proxmox/installation-and-access.md:147,172-183`, `docs/vms/wazuh-01-build.md:148-155`, `docs/README.md:51-52`.
- **Notably, `10.10.10.0/24` internal lab addresses are published in full** — the placeholder policy is applied only to the *management/upstream* network (which touches the builder's real home LAN), not to the purely virtual internal lab. IaC can hard-code the `10.10.10.0/24` plane and must parameterize the `vmbr0` plane.
- `.gitignore` enforces the policy mechanically: `.env`, `*.key`, `*.pem`, `*.crt`, `*.token`, `secrets/`, `credentials/`, `id_rsa`, `*.ppk`, VM images (`*.iso`, `*.qcow2`, `*.vmdk`, `*.ova`, `*.ovf`, `*.img`, `*.raw`, `*.vdi`), and review-gated dirs `private-screenshots/`, `sensitive/`, `redacted-needed/`, `private-notes/`, `scratch/` — `.gitignore:14-51`.

---

## 8. Version 1 "Definition of Done" — status against the docs

`README.md:445-463`:

| DoD item | Status per docs |
|---|---|
| Custom PC assembled and validated | ✅ `docs/hardware/build-log.md:290-296`; `docs/hardware/hardware-validation.md:232-238` |
| Proxmox installed and accessible | ✅ `docs/proxmox/installation-and-access.md:236-241` |
| Network bridges configured | ⚠️ `vmbr0`+`vmbr1` proven working (`docs/network/dhcp-validation.md:179-185`); **`vmbr2` never confirmed created** |
| Firewall/router VM installed | ✅ `docs/vms/fw-01-firewall-plan.md:171-188` |
| Active Directory and DNS configured | ✅ `docs/vms/dc-01-domain-controller-build.md:286-303` |
| Wazuh installed | ✅ `docs/vms/wazuh-01-build.md:308-325` |
| ≥1 Windows endpoint sending logs | ✅ `docs/wazuh/agent-enrollment-windows-client.md:183-195` (also `dc-01`) |
| ≥1 Linux endpoint sending logs | ✅ `docs/wazuh/agent-enrollment-linux.md:161-170` (also `ubuntu-app-01`) |
| Suricata generating alerts | ❌ **not built** |
| One custom Wazuh rule | ❌ **absent** |
| One false-positive tuning journal | ❌ **absent** |
| One learner-ready SOC scenario | ✅ two exist (`docs/incident-scenarios/*`) |
| One Python automation script | ❌ **absent — repo contains no code** |
| One research progress summary | ❌ **absent** |