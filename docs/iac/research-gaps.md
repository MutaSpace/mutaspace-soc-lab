# Completeness Critique — What the Research Missed

The digest is strong on *component* facts (provider versions, flags, ForceNew landmines) and weak on *system* facts. Below are the gaps I found, ranked, with researched answers. Six of them are seams; three are unexamined assumptions that could invalidate the whole plan.

---

## GAP 1 — Nobody asked the most obvious question: **the lab already exists**

**The gap.** Every research thread assumes a greenfield `tofu apply` into an empty host. But the inventory is explicit: VMs `101, 102, 103, 104, ?105, 106` are *built and running*, `dc-01` holds a live AD forest, `wazuh-01` holds indexed alerts, and two completed incident labs depend on that state. No thread asked how IaC takes over an existing estate, or whether the first `tofu apply` destroys the coursework.

**Why it matters.** This is a fork in the road that changes the whole repo shape. Greenfield ⇒ write HCL, apply, done. Brownfield ⇒ you need an import strategy, and you must decide per-VM whether it is *adopted* (imported, never recreated) or *reprovisioned* (destroyed, rebuilt from a template). `dc-01` in particular cannot be recreated without re-creating the forest — and the digest's own finding that the **entire `clone` block is ForceNew** means an imported VM whose config you later "tidy" gets destroyed silently.

**Answer.** OpenTofu supports declarative `import` blocks plus config generation:

```hcl
import {
  to = proxmox_virtual_environment_vm.dc01
  id = "mutaspace-soc-node01/102"   # <node>/<vmid>, per bpg import docs
}
```
then `tofu plan -generate-config-out=generated_resources.tf`. Config generation is available in **OpenTofu v1.6 as an experimental feature**; you must target a *new* file (it errors on an existing one), and it warns that generated config for complex schemas can contain **mutually conflicting arguments** you must hand-prune, and that later minor versions may change formatting/behaviour ([OpenTofu: Generating Configuration](https://opentofu.org/docs/language/import/generating-configuration/)).

Concrete recommendation:
- **Adopt** `fw-01` (VM ID unknown — resolve it first), `dc-01`, `wazuh-01`. Import them, set `protection = true`, and add `lifecycle { prevent_destroy = true }`. These are pets carrying irreplaceable state.
- **Reprovision** `analyst-01`, `ubuntu-app-01`, `win-client-01`, and delete `test-client-01`. These are the ones worth making cattle.
- Run `tofu plan` after import and expect a large diff: bpg absorbs Proxmox-assigned values into state, and the digest's own note that *cloning silently resets unspecified disk attributes to schema defaults* applies equally to imports — restate every disk attribute (`size`, `discard`, `cache`, `aio`, `ssd`, `iothread`) or the first apply will "correct" them.
- Note the pre-work: **`fw-01`'s VM ID is never recorded anywhere in the repo (G1)**, and `win-client-01` has no build doc at all (G2). You cannot write an `import` block for either until someone runs `qm list` on the host. That is a prerequisite task, not an IaC task.

---

## GAP 2 — The bootstrap order question was asked but never answered: **`vmbr1` has no uplink**

**The gap.** No thread traced what happens on the very first boot of a cloned VM. `vmbr1` is an internal-only bridge with **no physical port** (`docs/network/proxmox-bridge-plan.md:55`). Its only route to the internet is *through `fw-01`*, which is itself a VM on that bridge. So:
- A Packer build VM placed on `vmbr1` cannot reach `archive.ubuntu.com`, `packages.wazuh.com`, or `raw.githubusercontent.com` — which the digest itself established the Wazuh installer requires.
- Packer's `http_directory` server binds on the **Packer host**; the digest flagged that "on a segmented SOC lab network the guest may never reach it" but never resolved which network Packer builds on.
- If `fw-01` is itself IaC-managed, then rebuilding it takes the whole lab's DHCP, DNS forwarding, and default route offline — including whatever the config tool needs to reach the other VMs.

**Why it matters.** This is the single most likely cause of a "worked on my machine, hangs forever in the classroom" failure, and it is invisible until the first real build.

**Answer — three-network model, and it needs a third bridge nobody planned:**

1. **Build plane.** Packer must *not* build on `vmbr1`. Either build on `vmbr0` (which has the real uplink), or create a dedicated NAT'd build bridge on the host. Proxmox documents this exactly — a port-less bridge with host masquerade:
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
```
   ([Proxmox VE: Network Configuration — Masquerading (NAT) with iptables](https://pve.proxmox.com/wiki/Network_Configuration)). ⚠️ The Proxmox wiki's own example uses `10.10.10.1/24` — **do not copy it verbatim**, that is `fw-01`'s LAN address in this lab. Use a distinct range. Also note the documented caveat: "in some masquerade setups with firewall enabled, conntrack zones might be needed", requiring `iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone 1`.
2. **Runtime plane.** OpenTofu clones the template and re-points `network_device.bridge` to `vmbr1`. Since `bridge` is a normal (non-ForceNew) attribute on `proxmox_virtual_environment_vm`, the build-network/runtime-network switch is free.
3. **Ordering.** `fw-01` must be `depends_on`-first for every other VM, and it must be a *stateless, snippet-driven* rebuild or an adopted pet — see Gap 7. `dc-01` must come second (it is DNS for everything else). Everything else can be parallel, subject to the digest's own `-parallelism` warning.

**Corollary nobody drew:** the digest's Wazuh finding that the installer fetches `wazuh-template.json` from `raw.githubusercontent.com` means the Wazuh install **must happen during the Packer build on the build plane**, not as a post-clone step on `vmbr1`. Bake the SIEM; don't install it at deploy time.

---

## GAP 3 — "What configures the VM after OpenTofu, and how does it learn the IP?" was never answered

**The gap.** The digest observed that GOAD uses a *static, committed* Ansible inventory because IPs are deterministic. That works — but it was reported as an observation, not evaluated against the alternatives, and it does not cover this lab's two DHCP hosts (`analyst-01`, `win-client-01`) or the Windows guests.

**Answer — four mechanisms, ranked for this lab:**

| Mechanism | Verdict here |
|---|---|
| **Static committed inventory** | ✅ Primary. `10.10.10.10/.20/.30` are already fixed by the docs. Zero moving parts, survives `tofu destroy`, no chicken-and-egg on `local_file`. |
| **`agent.enabled = true` → `ipv4_addresses`** | ⚠️ Only for the DHCP hosts. The digest already established this is the worst time-waster if the agent isn't running, and PVE 9 requires `VM.GuestAgent.Audit` or the provider **hangs indefinitely** rather than 403ing. |
| **cloud-init `phone_home`** | 🆕 Never mentioned by any thread. A once-per-instance module that POSTs form-encoded `instance_id`, `hostname`, `fqdn` and SSH host public keys (`pub_key_rsa`/`ecdsa`/`ed25519`) to a URL, with `tries` defaulting to 10, running **after all other cloud-init modules complete** ([cloud-init modules reference](https://docs.cloud-init.io/en/latest/reference/modules.html)). This is the clean answer to "how do I know the VM is *done*, not just *pinged*" — and shipping the host keys solves SSH TOFU for a classroom without `StrictHostKeyChecking=no`. |
| **`community.proxmox.proxmox` dynamic inventory** | ⚠️ Useful for discovery, not for bootstrap. Requires `requests >= 1.1` on the controller, auth via `token_id`+`token_secret` (or `PROXMOX_PASSWORD`), config file **must** be named `*.proxmox.yml`/`*.proxmox.yaml`, and supports `want_facts`, `compose`, `groups`, `keyed_groups`, `filters`, `exclude_nodes` ([community.proxmox.proxmox inventory](https://docs.ansible.com/ansible/latest/collections/community/proxmox/proxmox_inventory.html)). ⚠️ Its docs describe `want_proxmox_nodes_ansible_host` as taking the first interface with an IP and **do not state a guest-agent requirement** — but guest IPs are only available from PVE when the agent is running, so treat "works without the agent" as untested. |

**Recommendation:** static inventory for the four static hosts, `phone_home` to a build-host endpoint as a readiness signal, and pin MACs (Gap 9) so even the DHCP hosts become deterministic — at which point the dynamic inventory becomes optional.

---

## GAP 4 — The Packer→OpenTofu handoff has a **third option** nobody listed

**The gap.** The digest presents two choices: hardcode the VMID (GOAD) or look it up with the `proxmox_virtual_environment_vms` data source. It missed the mechanism Packer ships for exactly this.

**Answer.** The `manifest` post-processor writes a JSON file with `builds[]` containing `name`, `builder_type`, `build_time`, `files[]`, **`artifact_id`**, `packer_run_uuid`, and a user-controlled `custom_data` map, plus a top-level `last_run_uuid` ([Packer manifest post-processor](https://developer.hashicorp.com/packer/docs/post-processors/manifest)). And for the Proxmox builder specifically, I checked the source: `Artifact.Id()` is `strconv.Itoa(a.artifactID)` — **the artifact ID is literally the template's VMID as a string** ([artifact.go](https://raw.githubusercontent.com/hashicorp/packer-plugin-proxmox/main/builder/proxmox/common/artifact.go)).

So the seam can be a *file*, not a convention:

```hcl
locals {
  manifest  = jsondecode(file("${path.module}/../packer/manifest.json"))
  templates = { for b in local.manifest.builds : b.name => tonumber(b.artifact_id) }
}
resource "proxmox_virtual_environment_vm" "dc01" {
  clone { vm_id = local.templates["windows-2022"] }
}
```

**But — and this is the decisive point the digest half-found:** the `clone` block is **ForceNew in its entirety**, so a manifest-driven VMID means *every template rebuild destroys and recreates every downstream VM*. That is catastrophic for `dc-01`.

**Verdict:** use manifest/data-source lookup **only as a plan-time assertion**, and pin the VMID in Packer as the actual contract:

```hcl
# packer: vm_id = 9000 (win2022), 9001 (ubuntu-2404), 9002 (ubuntu-desktop)
# tofu:   variable "template_ids" with a precondition that the data source agrees
```
Combine both: hardcode the constant, and add a `lifecycle { precondition }` comparing it to `data.proxmox_virtual_environment_vms` filtered on `name` + `template = true` so a *missing or renumbered* template is a plan-time error rather than a silent clone of the wrong VM. Also set `template_name` explicitly in Packer — the digest's own finding is that `-force` before plugin v1.2.4 couldn't find auto-named templates.

---

## GAP 5 — "How do you test this without a second Proxmox host?" — completely unexamined, and there is a real answer

**The gap.** Nobody researched it. Given the inventory says the Proxmox host is *the only physical machine* and it is running live coursework, this is not academic: an untested `tofu apply` runs against production.

**Answer — a four-layer test pyramid, three layers of which need no Proxmox at all:**

1. **Syntax/lint (no host):** `packer validate`, `packer fmt -check`, `tofu fmt -check`, `tofu validate`, `tflint`. Note `tofu validate` requires `tofu init`, which needs registry access but **not** a Proxmox endpoint.
2. **Unit tests with mocked providers (no host)** — 🆕 nobody mentioned this. `tofu test` supports `mock_provider`, where "creation and retrieval of provider resources and data sources will be skipped", plus `override_resource`/`mock_data` to inject values, enabling **fully offline testing** ([OpenTofu: tofu test](https://opentofu.org/docs/cli/commands/test/)):
```hcl
mock_provider "proxmox" {
  mock_data "proxmox_virtual_environment_vms" {
    defaults = { vms = [{ vm_id = 9000, node_name = "mutaspace-soc-node01" }] }
  }
}
run "every_vm_lands_on_vmbr1" {
  command = plan
  assert {
    condition     = alltrue([for v in values(module.lab.vms) : v.bridge == "vmbr1"])
    error_message = "a lab VM escaped onto vmbr0"
  }
}
```
   This is the layer that catches "someone put the DC on the WAN bridge" before it reaches the classroom.
3. **Nested Proxmox (one host, ~16GB):** run a PVE-in-PVE VM as a scratch target. Set the guest `--cpu host`, and on the physical host `echo "options kvm-amd nested=1" > /etc/modprobe.d/kvm-amd.conf`, reload with `modprobe -r kvm_amd; modprobe kvm_amd`, verify with `cat /sys/module/kvm_amd/parameters/nested` returning `Y`. Documented caveats: nesting "adds an overhead", and VMs with the svm/vmx flag **cannot be live-migrated** ([Proxmox VE: Nested Virtualization](https://pve.proxmox.com/wiki/Nested_Virtualization)). PVE 9.1 additionally offers a `nested-virt` vCPU flag as an alternative to `cpu = host` — but note it must be set on a vendor-matched vCPU type, not a generic `x86-64-v*`. On this Ryzen 9 7900X / 64GB box a nested PVE with 4 vCPU / 12GB is affordable and can host a cut-down 3-VM version of the lab. It is slow but it exercises the *real* API, which is exactly what the mocks can't.
4. **Smoke test on the real host:** a `tofu workspace` / VMID-offset "scratch" range (e.g. VMIDs 8xx, bridge `vmbr9`) that never touches 101–106.

---

## GAP 6 — The secrets question was answered for *credentials* but not for *this repo's actual policy*

**The gap.** The digest correctly says "env vars for the provider, state encryption or SOPS for state." It missed that this repo already has a **binding, documented, doc-level placeholder policy** (`README.md:347`) that IaC will quietly violate, and that nothing enforces it mechanically for code.

Specifically: `.gitignore` covers `.env`, `*.key`, `*.pem`, `secrets/` — but **not** `*.tfstate`, `*.tfstate.backup`, `.terraform/`, `.terraform.lock.hcl` (you *do* want that one committed), `*.auto.tfvars`, `*.auto.pkrvars.hcl`, or `crash.log`. The digest itself notes `.auto.tfvars`/`.auto.pkrvars.hcl` are auto-loaded *by design*, which makes `git add -A` a one-keystroke credential leak. And the repo's placeholder policy protects the **management/upstream plane only** — meaning `<LAB_MANAGEMENT_IP>` and the pfSense WAN address are exactly the values that must live in tfvars and must never be committed.

**Answer — three mechanical layers:**

1. **Pre-commit:** gitleaks, MIT-licensed, current **v8.30.1**, config via `.gitleaks.toml` (custom rules + allowlists) and `.gitleaksignore` (per-finding fingerprints). Hook:
```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.30.1
    hooks: [{ id: gitleaks }]
```
   Add a **custom `.gitleaks.toml` rule for the lab's own placeholder policy** — a regex that fails on any committed non-RFC1918 IPv4 or on `10.0.0.` outside a fenced "Example" block. That turns a prose policy into a gate ([gitleaks](https://github.com/gitleaks/gitleaks)).
2. **Server side:** for a public classroom repo, GitHub **secret scanning runs automatically and free** on public repos, and **push protection for users is free, applies to public repositories, and is enabled by default** — it blocks the push with an explanatory message and can be bypassed, though bypasses only generate alerts if push protection is also enabled at the repository level ([about secret scanning](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning), [about push protection](https://docs.github.com/en/code-security/secret-scanning/introduction/about-push-protection)). ⚠️ It will **not** catch a lab Wi-Fi SSID, a home LAN subnet, or a `wazuh-passwords.txt` — those are unstructured, so layer 1 is not optional.
3. **State:** OpenTofu native `terraform { encryption { ... } }` with a `pbkdf2` key provider (≥16-char passphrase, ≥200k iterations) — a genuine OpenTofu-only advantage worth naming explicitly in the docs as a reason the repo uses OpenTofu rather than Terraform. Even with env-var credentials, `initialization.user_account.password` and any generated Wazuh password land in plaintext state.

Repo shape: commit `terraform.tfvars.example` and `variables.pkrvars.hcl.example` only; teach `direnv`/`.envrc` (gitignored) for `PROXMOX_VE_API_TOKEN` and `PROXMOX_TOKEN`. And note the digest's trap: **Packer wants `username="x@pve!id"` + `token="<uuid>"`; bpg wants one string `api_token="x@pve!id=<uuid>"`.** Two variables, one secret — document it or they'll silently 401.

---

## GAP 7 — `dc-01` is **not reproducible** and no thread said so out loud

**The gap.** The Windows research covered Autounattend, virtio drivers, sysprep, and eval-period rearm counts. It never asked the prior question: *can a Packer build fetch the ISO at all?*

**Answer: no.** The Windows Server 2022 evaluation page **requires registration before download** ("Register, then download and install"), exposes only `go.microsoft.com` redirect links behind that gate, and the evaluation expires in **180 days** with a hard requirement to "activate over the internet in the first 10 days to avoid automatic shutdown" ([Microsoft Evaluation Center — Windows Server 2022](https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022)).

Consequences the plan must absorb:
- There is **no `iso_url` a Packer template can pin** for `dc-01` or `win-client-01`. The build is `boot_iso { iso_file = "local:iso/..." }` against a manually-uploaded ISO, exactly like the digest's pfSense finding — the repo must ship a documented "manual prerequisites" step (ISO + `virtio-win` pinned archive URL + CloudbaseInit MSI if used), and `.gitignore` already blocks `*.iso`, so a fresh clone *cannot* build the Windows templates. That belongs in the README as a first-class caveat, not a footnote.
- The 180-day clock + the 10-day activation trap means an **air-gapped** SOC lab silently self-destructs. Since `vmbr1` has no route out until `fw-01` is up, the DC must be allowed outbound during its first 10 days — a firewall rule that must exist in the IaC, and which the "isolated lab" framing actively works against.
- This is the same class of problem as the digest's pfSense finding. **Two of the lab's core VMs are un-pinnable by URL.** If reproducibility-from-source is the goal, that is the honest headline, and it argues for the digest's OPNsense recommendation *and* for a documented "golden ISO shelf" on the host.

---

## GAP 8 — The load-bearing assumption everybody made: **"the host is PVE 9.x"**

**The gap.** Every thread cites bpg v0.111.1 (tested against **PVE 9.2**), the PVE 9.0 privilege changes (`VM.Monitor` removed, `VM.GuestAgent.*` added, `SDN.Use` required), deb822 `.sources`, and PVE 9.2's new `VM.PowerMgmt`-to-start requirement. The inventory says: **Proxmox VE version is never stated anywhere in the repo** (`README.md:341`), and the host baseline's "Repository configuration reviewed" item is still *Pending*.

**Why it matters.** The `pveum role add` command is version-forked:
- On **PVE 8.x**, `VM.GuestAgent.Audit`, `VM.Replicate` and (before 8.2) `SDN.Use` **do not exist** — the role creation fails.
- On **PVE 9.x**, `VM.Monitor` does not exist — the role creation fails the other way.
- bpg declares **PVE 7.x unsupported**, so if this host was installed on 7.x the entire provider choice is invalid.
- `min_tls` defaults to **1.3**; against an older PVE endpoint the provider fails with an error that looks nothing like TLS.

**Answer.** Make version detection step zero of the bootstrap script, not an assumption:
```bash
pveversion -v | head -1          # pve-manager/9.2.x/...
pvesh get /version --output-format json
```
and branch the privilege list on the major version. Then **record it in `docs/proxmox/host-baseline.md`** — this is a documentation gap (G15) that is now blocking an engineering decision, which is a good argument for closing the repo's Pending checklist items *before* writing HCL. If the host is 8.x, either upgrade (`pve8to9`) or pin an older provider and accept the digest's "8.x testing is not a priority" risk.

---

## GAP 9 — The DHCP-reservation circularity (a seam hiding inside G13)

**The gap.** The inventory flags that `analyst-01` and `win-client-01` are pure DHCP, so their addresses are nondeterministic across rebuilds, "which breaks reproducible detection labs." No thread solved it. The naive fix — DHCP static mappings on the firewall — requires the MAC, which Proxmox assigns at create time, which is *after* the firewall config is written. Circular.

**Answer.** Break the cycle by making the MAC an input, not an output. The digest's own source-level finding is that `network_device.mac_address` is `Optional: true, Computed: true` and — contrary to common lore — **not ForceNew**. So:

```hcl
locals { macs = { analyst-01 = "BC:24:11:10:10:40", win-client-01 = "BC:24:11:10:10:41" } }
```
Pin MACs in the same `lab.yaml` that drives everything else, use the `BC:24:11` Proxmox OUI, and template both the OpenTofu `network_device.mac_address` *and* the firewall's static-mapping config from the same map. The detection-lab queries in `docs/incident-scenarios/*` then keep working across rebuilds, and `agent.name` stays stable because the hostname comes from cloud-init/Autounattend rather than DHCP.

---

## GAP 10 — NIC ordering silently decides which interface is WAN

**The gap.** `fw-01` has `net0 → vmbr0` (WAN, `vtnet0`) and `net1 → vmbr1` (LAN, `vtnet1`). Nobody examined that in HCL, `network_device` blocks map to `net0..netN` **positionally, by declaration order**. Reorder two blocks in a refactor — or let a `for_each` over an unordered map generate them — and the firewall boots with WAN and LAN swapped. Symptom: the lab has no internet, the Proxmox management bridge starts eating DHCP from pfSense, and nothing in the plan output hints at why.

**Answer.** Never generate `fw-01`'s NICs from a map. Declare `net0`/`net1` as explicit, ordered, commented blocks with pinned MACs, and add a `lifecycle { precondition }` asserting `network_device[0].bridge == "vmbr0"`. This is also the natural place to encode the never-built third leg (`vmbr2` / OPT, C11) as a commented-out block with a doc reference, so the gap stays visible.

---

## GAP 11 — Nobody asked who serves **time**

**The gap.** G18 records that no NTP or timezone documentation exists anywhere in the repo. The AD thread established the Kerberos 5-minute skew rule; the classroom-lifecycle thread established that `qm rollback` reverts a VM to a snapshot taken days earlier. Nobody connected them.

**Why it matters.** The classroom reset mechanism *is* a clock-skew generator. Roll `win-client-01` back to a two-week-old baseline and its clock is two weeks behind the DC ⇒ Kerberos fails ⇒ domain logon fails ⇒ the lab looks broken in a way that has nothing to do with the exercise. Simultaneously, Wazuh alert correlation across `dc-01`, `win-client-01` and `ubuntu-app-01` is meaningless if their clocks disagree.

**Answer (design, drawing on the digest's own verified facts).**
- Make **`fw-01` the lab's NTP server** on the LAN interface (both pfSense and OPNsense ship one), and hand it out via the same DHCP options that already carry DNS `10.10.10.10` and domain `mutaspace.local`.
- `dc-01` (the forest-root PDC emulator) syncs from `fw-01` via `w32tm /config /manualpeerlist:"10.10.10.1,0x8" /syncfromflags:manual /reliable:yes /update`; all domain members inherit `NT5DS` from the hierarchy.
- **Do not** disable the QEMU guest agent's time sync on the *clients* — after a snapshot rollback, `guest-set-time` is what stops them from being hours behind before W32Time ever gets a chance. The verifier correction in the digest is important here: the blanket "always disable host time sync on DCs" rule is version- and platform-specific, and Microsoft's own reference topology syncs the root PDC *from* the hypervisor on modern Hyper-V. On KVM/Proxmox, the safe lab configuration is: guest agent time sync **on** everywhere, W32Time authoritative for the *domain*, and `fw-01` authoritative for the *lab*.
- Add a post-rollback validation step to the classroom runbook: `w32tm /resync` on Windows, `timedatectl` / `chronyc tracking` on Linux.

---

## GAP 12 — One tool never evaluated at all: **Ansible as the provisioner instead of OpenTofu**

**The gap.** Packer-vs-nothing and bpg-vs-Telmate were compared. `community.proxmox.proxmox_kvm` — Ansible creating the VMs directly — was never on the table.

**Why it matters for *this* repo specifically.** The lab already needs Ansible for everything in-guest (AD promotion, Wazuh agents, DNS records — the digest correctly established that `terraform-provider-ad` was archived 2025-08-11 and there is no IaC path for AD objects). Adding OpenTofu means two state models, two credential shapes, two tool versions, and the ForceNew landmines. A single `ansible-playbook` that calls `proxmox_kvm` for clone + `microsoft.ad.*` for config has *one* mental model — a real consideration for a teaching repo whose stated principle is "clarity over complexity" (`docs/README.md:40`).

**Verdict — still recommend OpenTofu, but for reasons that should be written down rather than assumed:** desired-state reconciliation and a `plan` step you can show students before anything changes; native state encryption; and `tofu test` with mocked providers (Gap 5), which has no Ansible equivalent short of Molecule with a live host. Ansible's `proxmox_kvm` is imperative and has no plan phase — for a lab whose whole pedagogy is "validate before you assume", `tofu plan` is a teaching artifact in itself. Say that in the docs; the digest never justified the choice at all.

---

## Two smaller unasked questions

- **VMID allocation policy.** IDs 101–106 are taken by hand-built VMs, `105` is an unconfirmed hole, and templates want a reserved block. The digest surfaces bpg's `random_vm_ids` (default range 10000–99999) with file-based locking that still admits conflicts across provider instances — for a single-node teaching lab, *random IDs are the wrong default*. Pin a documented scheme (9000–9099 templates, 100–199 adopted infrastructure, 200+ per-learner clones) and set `vm_id` explicitly everywhere. `vm_id` is ForceNew.
- **`test-client-01` (VM 101).** G16 says its lifecycle is unresolved: declared temporary, never documented as deleted. IaC cannot infer intent. This needs a human decision *before* the first import pass, because a `tofu apply` with no resource for VMID 101 either ignores it (unmanaged drift) or, if someone adds it to a pool with `delete_unreferenced_disks_on_destroy = true` (the bpg default), deletes disks nobody meant to touch.

---

## Sources

- [OpenTofu — Generating Configuration (import blocks, `-generate-config-out`)](https://opentofu.org/docs/language/import/generating-configuration/)
- [OpenTofu — `tofu test` command (`mock_provider`, `override_resource`)](https://opentofu.org/docs/cli/commands/test/)
- [cloud-init — Modules reference (`phone_home`, `ca_certs`, `write_files`)](https://docs.cloud-init.io/en/latest/reference/modules.html)
- [Packer — manifest post-processor](https://developer.hashicorp.com/packer/docs/post-processors/manifest)
- [packer-plugin-proxmox — `builder/proxmox/common/artifact.go`](https://raw.githubusercontent.com/hashicorp/packer-plugin-proxmox/main/builder/proxmox/common/artifact.go)
- [Proxmox VE Wiki — Network Configuration (masquerading/NAT on a port-less bridge)](https://pve.proxmox.com/wiki/Network_Configuration)
- [Proxmox VE Wiki — Nested Virtualization](https://pve.proxmox.com/wiki/Nested_Virtualization)
- [Ansible — `community.proxmox.proxmox` inventory plugin](https://docs.ansible.com/ansible/latest/collections/community/proxmox/proxmox_inventory.html)
- [Microsoft Evaluation Center — Windows Server 2022 download](https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022)
- [GitHub Docs — About secret scanning](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning)
- [GitHub Docs — About push protection](https://docs.github.com/en/code-security/secret-scanning/introduction/about-push-protection)
- [gitleaks (v8.30.1, MIT)](https://github.com/gitleaks/gitleaks)

**Research limitation:** the WebSearch budget for this session was exhausted before I started, so every finding above comes from direct WebFetch of a primary source I named. I could not do discovery searches, which means (a) I may have missed a purpose-built Proxmox API mock or a Proxmox-guest-agent Ansible connection plugin, and (b) the `community.proxmox` inventory plugin's guest-agent dependency is inferred from PVE API behaviour, not confirmed by its docs — verify on the host.