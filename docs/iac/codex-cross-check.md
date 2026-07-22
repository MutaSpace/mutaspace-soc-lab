# Codex Cross-Check Review

Independent review by OpenAI Codex (gpt-5.5, high reasoning effort), run against the full
repository contents on 2026-07-21 as a cross-check on the primary IaC design research.

See [design.md](design.md) for the synthesized design this was checked against.

---

**Technical Review**

I read the inlined repository as the source of truth. The repo is docs-only: there is no `packer/`, `tofu/`, `ansible/`, VM manifest, variable file, or machine-readable inventory yet.

**1. Inventory**

| VM | VM ID | Guest OS | vCPU | RAM | Disk | Disk Controller | NIC Model | Bridge | IP/DHCP | Role | Wazuh Agent |
|---|---:|---|---:|---:|---:|---|---|---|---|---|---|
| `fw-01` | Missing | pfSense CE | 2 | 4GB | 20GB | Missing | VirtIO implied by `vtnet0/vtnet1` | `vmbr0`, `vmbr1`; optional `vmbr2` planned | WAN `10.0.0.x/24` example/upstream DHCP likely; LAN `10.10.10.1/24` | Firewall/router, DHCP, gateway | None documented |
| `test-client-01` | 101 | Ubuntu Linux | 2 | 2GB | 20GB | Missing | Missing | `vmbr1` | DHCP, expected `10.10.10.x` | Temporary network validation VM | None documented |
| `dc-01` | 102 | Windows Server 2022 Evaluation | 2 | 4GB | 60GB | SATA | E1000 | `vmbr1` | Static `10.10.10.10/24`, GW `10.10.10.1`, DNS self | AD DS, DNS, domain controller | Windows Wazuh agent named `dc-01` |
| `analyst-01` | 103 | Ubuntu Desktop 24.04 LTS | 2 | 4GB | 40GB | Missing | VirtIO | `vmbr1` | DHCP from `10.10.10.0/24`, DNS `10.10.10.10` | Ubuntu analyst workstation | Linux Wazuh agent named `analyst-01` |
| `wazuh-01` | 104 | Ubuntu Server; plan prefers 22.04 LTS, build does not state exact release | 4 | 8GB | 100GB | Missing | VirtIO | `vmbr1` | Static `10.10.10.20/24`, GW `10.10.10.1`, DNS `10.10.10.10` | Wazuh all-in-one SIEM | No endpoint agent documented; runs manager/indexer/dashboard |
| `win-client-01` | Missing | Windows client, exact Windows 10/11 missing | Missing | Missing | Missing | Missing | Missing | `vmbr1` | DHCP address | Windows domain workstation | Windows Wazuh agent named `win-client-01` |
| `ubuntu-app-01` | 106 | Ubuntu Server, exact release missing | 2 | 4GB | 40GB | Missing | VirtIO | `vmbr1` | Static `10.10.10.30/24`, GW `10.10.10.1`, DNS `10.10.10.10` | Linux app/server target, SSH, Nginx | Linux Wazuh agent named `ubuntu-app-01` |
| `sensor-01` | Missing | Missing; role implies Linux/Suricata appliance | Missing | Missing | Missing | Missing | Missing | “Depends on monitoring design” | Missing | Suricata IDS | Missing |
| `kali-01` | Missing | Kali Linux implied | Missing | Missing | Missing | Missing | Missing | `vmbr2` planned | Missing; `vmbr2` subnet absent | Controlled attack simulation | Missing |
| `untrusted-01` | Missing | Missing | Missing | Missing | Missing | Missing | Missing | `vmbr2` planned | Missing | Trust-boundary research VM | Missing |
| `nlp-01` | Missing | Missing | Missing | Missing | Missing | Missing | Missing | Missing | Missing | Phishing/NLP research VM | Missing |

Contradictions and gaps:

| Issue | Evidence |
|---|---|
| README planned architecture lists `ubuntu-analyst-01`, but built/scenario docs use `analyst-01`. | `README.md:110-112`; `docs/vms/analyst-01-build.md:1-40`; `docs/incident-scenarios/failed-login-investigation.md:30-36` |
| `fw-01` is completed but has no VM ID. | `docs/vms/fw-01-firewall-plan.md:40-52`, `192-209` |
| `win-client-01` clearly exists and is domain-joined/enrolled, but no build doc gives VM ID/resources/disk/NIC. | `docs/wazuh/agent-enrollment-windows-client.md:183-195` |
| `sensor-01`, `kali-01`, `untrusted-01`, `nlp-01` are architecture/planning entries only; no reproducible build specs. | `README.md:104-115`; `docs/network/network-design.md:198-209` |
| `sensor-01` placement is explicitly undecided. | `docs/network/network-design.md:92`, `208` |
| VM ID sequence skips 105; likely `win-client-01`, but never stated. | Known IDs from `docs/vms/*`: 101, 102, 103, 104, 106 |
| Disk controller is only stated for `dc-01`; Windows used SATA because VirtIO storage drivers were not loaded. | `docs/vms/dc-01-domain-controller-build.md:36-40`, `107-145` |
| README says “first version” includes 10 systems, but current completed VM docs cover only core subset plus temp test VM. | `README.md:100-116`; `docs/vms/` files |

**2. Network Truth**

| Network | Actual/Documented Truth | Problems |
|---|---|---|
| Proxmox management / WAN | `vmbr0`, connected to physical `nic0`; host management IP is placeholder `<LAB_MANAGEMENT_IP>/24`; example `10.0.0.50/24`; gateway placeholder, example `10.0.0.1`; Proxmox URL `https://<LAB_MANAGEMENT_IP>:8006`. | Real management IP/gateway/DNS are intentionally hidden, but IaC needs them as variables. `nic0` may be a sanitized name; real Linux NIC name is not documented. |
| Internal SOC LAN | `vmbr1`, no physical port, subnet `10.10.10.0/24`, gateway `10.10.10.1`, DHCP `10.10.10.100-10.10.10.200`. | This is the strongest network truth in the repo. |
| Internal DNS | DHCP was changed so clients receive `10.10.10.10` and DNS domain `mutaspace.local`. | Earlier docs say DNS works through pfSense/upstream during pre-AD testing; after AD, clients must use `dc-01`. That is evolution, not a contradiction, but IaC must encode phase/order. |
| AD domain | FQDN `mutaspace.local`, NetBIOS `MUTASPACE`, DC/DNS `dc-01` at `10.10.10.10`. | `.local` can collide with mDNS in some environments; acceptable for a lab, but it is a known annoyance. |
| Isolated/untrusted | `vmbr2` planned, no physical port, intended for Kali/untrusted/trust-boundary systems; optional pfSense OPT/DMZ. | No subnet, gateway, DHCP scope, DNS policy, firewall rules, or actual `fw-01` OPT interface config. Not IaC-ready. |

Key citations: `docs/network/dhcp-validation.md:54-72`, `docs/network/internal-dns-validation.md:28-79`, `docs/network/network-design.md:46-55`, `docs/network/proxmox-bridge-plan.md:29-57`, `docs/vms/dc-01-domain-controller-build.md:63-90`.

**3. IaC Feasibility**

Tooling reality checked against current primary docs: Packer has `proxmox-iso` and `proxmox-clone` builders for creating Proxmox templates from ISOs/templates; bpg/proxmox supports VM clone/cloud-init and Linux bridge resources; Wazuh documents an all-in-one quickstart installer; Microsoft documents `Autounattend.xml`, `Install-ADDSForest`, and `Add-Computer`; Netgate documents `config.xml` restore during pfSense install, but I did not find an official clean unattended pfSense CE installer flow. Sources: HashiCorp Packer docs, bpg/proxmox docs, Wazuh docs, Microsoft Learn, Netgate docs.  

| VM | Feasibility | Mechanism |
|---|---|---|
| `fw-01` | Semi-automatable | Best path: create a pfSense template once, then seed/restore `config.xml`. Netgate supports config restore from media/ECL, but full unattended OS install is the hard part. Packer `boot_command` console automation may work but is brittle. pfSense config is XML-backed, so DHCP/LAN/firewall rules can be restored from a known `config.xml`. |
| `dc-01` | Fully automatable, with care | Packer `proxmox-iso` + `Autounattend.xml`; use SATA as docs did, or VirtIO with driver ISO injection. Post-install PowerShell installs AD DS/DNS and runs `Install-ADDSForest`; OpenTofu clones/starts; Ansible/WinRM handles promotion and validation. |
| `wazuh-01` | Fully automatable | Ubuntu cloud image or Packer template + cloud-init static IP + Ansible. Run Wazuh quickstart `wazuh-install.sh -a`, capture `wazuh-passwords.txt` into secrets storage, disable package repo afterward. |
| `analyst-01` | Fully automatable | Ubuntu Desktop is less pleasant than Server but still automatable with autoinstall/cloud-init. Use Packer template + OpenTofu clone + Ansible for packages and Wazuh agent. |
| `ubuntu-app-01` | Fully automatable | Ubuntu Server cloud-init static IP, DNS record on `dc-01`, Ansible for SSH/Nginx/Wazuh agent. |
| `win-client-01` | Fully automatable if specs are added | Packer Windows client template with `Autounattend.xml`; OpenTofu clone; PowerShell/Ansible WinRM domain join using `Add-Computer`, then Wazuh MSI install. Missing OS edition/resources/VMID block implementation. |
| `test-client-01` | Fully automatable | Disposable Ubuntu cloud-init DHCP VM; probably should not be long-lived IaC except as a validation target. |
| `sensor-01` | Not currently automatable from repo | Need OS, NIC count/bridge placement, SPAN/TAP strategy, Suricata config, log forwarding path. |
| `kali-01` | Semi until specs exist | Kali can be built from installer/prebuilt image, but repo lacks resources, IP, users, and containment rules. |
| `untrusted-01` | Not automatable from repo | No OS/spec/network policy. |
| `nlp-01` | Not automatable from repo | Only mentioned in README; no OS/spec/network/storage/GPU/data requirements. |

**4. Risks**

The build order matters more than the docs currently encode. OpenTofu can create `vmbr1`/`vmbr2`, but all internal VM provisioning depends on `fw-01` routing/NAT and later on `dc-01` DNS. After AD promotion, DHCP must hand out `10.10.10.10`, or domain joins and Wazuh hostnames fail. That problem is already documented from the manual build in `docs/network/internal-dns-validation.md:186-198`.

The biggest chicken-and-egg issue is pfSense. If `fw-01` is not up, internal VMs can be created but cannot install packages, reach Wazuh, or complete domain workflows unless provisioning happens through Proxmox guest agents, attached ISOs, or an alternate temporary network. Keep OpenTofu control traffic on `vmbr0`; do not require access into `vmbr1` until routing is validated.

Single-node state is fragile. The Proxmox host has one 2TB NVMe and no documented backup target yet (`docs/hardware/parts-list.md:183-194`). Snapshots are useful for classroom reset, but they are not backups and Wazuh/indexer state can grow quickly. Define which VMs are golden templates, which are mutable scenario VMs, and which are reset after each class.

Secrets are currently intentionally omitted, which is correct, but IaC needs a real strategy: Proxmox API token, Windows local admin, domain admin or delegated join account, Wazuh admin password, Wazuh enrollment material, pfSense admin password, SSH keys. Do not put these in `*.tfvars` committed to Git.

Idempotency will be rough around AD DS promotion, pfSense XML restore, Wazuh installer reruns, Windows domain join, and DNS record creation. Those should be guarded with checks, not blind reruns.

For classroom resets, prefer template-linked workflows: immutable Packer templates, OpenTofu creates named scenario clones, Ansible configures baseline, Proxmox snapshots mark “start of lab,” and reset scripts revert learners to known snapshots. Multiple simultaneous learners on one 64GB node probably need shared/team VMs, not one full isolated environment per learner; the hardware doc already says full isolated student environments require future scaling (`docs/hardware/parts-list.md:170-179`).

**5. Recommended Repo Layout**

```text
docs/
packer/
  README.md
  templates/
    ubuntu-server/
    ubuntu-desktop/
    windows-server-2022/
    windows-client/
    pfsense/
  answer-files/
    ubuntu/
    windows/
    pfsense/
tofu/
  README.md
  envs/
    lab-single-node/
      main.tf
      providers.tf
      variables.tf
      terraform.tfvars.example
      locals.vms.tf
      outputs.tf
  modules/
    proxmox_vm/
    proxmox_bridge/
ansible/
  README.md
  inventories/
    lab/
      hosts.yml
      group_vars/
  roles/
    common_linux/
    wazuh_server/
    wazuh_agent_linux/
    wazuh_agent_windows/
    windows_ad/
    windows_domain_join/
    ubuntu_app/
    dns_records/
  playbooks/
    00-validate-network.yml
    10-domain-controller.yml
    20-wazuh.yml
    30-endpoints.yml
    90-classroom-reset.yml
scripts/
  validate/
  reset/
secrets/
  README.md
  .gitkeep
```

Use a single OpenTofu root with `for_each` over a typed VM map for this lab, not many deep modules. The environment is small, single-node, teaching-oriented, and full of per-VM exceptions. A `for_each` map keeps the inventory visible and reviewable. Use small modules only for repeated Proxmox primitives: “clone VM from template,” “Linux bridge,” maybe “download ISO/image.” Avoid hiding `dc-01`, `fw-01`, and `wazuh-01` behind generic modules until the manual truth is fully captured.

The next doc-to-IaC step should be a canonical `docs/inventory.md` or `tofu/envs/lab-single-node/locals.vms.tf` that resolves missing VM IDs, OS versions, disk controllers, NIC models, static/DHCP choices, and `vmbr2` subnet/policy before writing automation.
