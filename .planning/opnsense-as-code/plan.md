# OPNsense-as-code — Implementation Plan

Status: DRAFT for approval, revision 3. Wave 1 is COMPLETE (commit 87e80d0); do not execute
further waves until approved.
Reference design: `docs/proposals/opnsense-as-code.md` (Milestone 1 only).
Cross-review folded in: `.planning/opnsense-as-code/plan.codex-review.md` — see "Codex review
disposition" at the end. Two primary-source research spikes folded in at revision 3 — see
"Spike findings disposition".
Billing contract: **N/A** — `.planning/` here has no `PROJECT.md` / `ROADMAP.md` / `MILESTONES.md`;
nothing Quotient parses is touched.

IP policy note (review finding 11): lab-internal ranges `10.10.10.0/24`, `10.10.20.0/24`,
`10.99.0.0/24` are committable per project CLAUDE.md and appear literally below. The host's
real management address is a secret and appears only as the placeholder `<LAB_MANAGEMENT_IP>`.

---

## Goal

"Done" means fw-01 (OPNsense, VMID 100) is fully configured-as-code and **an instructor does
no manual firewall configuration during a deploy**, proven from scratch — not by live
reconcile:

1. Template `tpl-opnsense-267` (VMID 9004) is rebuilt with root SSH `<authorizedkeys>` AND
   `<apikeys>` baked into the config.xml seed (both fully OFFLINE — the API key/secret pair
   is generated locally; the secret hash is a deterministic-format `$6$` SHA-512 crypt, no
   live-box bootstrap needed), with the known root password/hash wired in and a scripted,
   build-blocking preflight proving the hash verifies against the password.
2. fw-01 is redeployed ONCE from that template via
   `tofu apply -replace='module.vm["fw-01"].proxmox_virtual_environment_vm.this' -parallelism=1`
   (NOT `-target` — the clone block is unchanged, so `-target` is a no-op; the proposal's step 5
   wording is corrected here). The SINGLE cutover brings up BOTH key SSH and API auth.
3. The redeployed fw-01 reproduces the live config — filter rules incl. the scenario allow
   rules, NAT/outbound, interfaces/gateways, Kea DHCP reservations, DNS posture (unbound
   present-but-disabled; dc-01 is the resolver) — verified against a pre-cutover config.xml
   backup and live lab checks (routing, DHCP, DNS, NTP, scenario run→verify).
4. Key-based root SSH AND API auth
   (`curl -k -u "$FW_API_KEY:$FW_API_SECRET" https://10.10.10.1/api/core/firmware/status`
   → 200) work on the redeployed box with zero manual configuration.
5. fw-01 deltas are managed as code: `ansible/playbooks/05-fw-config.yml` over the
   **`oxlorg.opnsense`** API collection (standing scenario rules asserted from config.xml,
   a content-scoped toggleable research-plane egress rule that CANNOT bypass SOC-LAN
   isolation, Suricata enable + EVE→Wazuh), exposed as `task fw:*` verbs — implementation
   gated on a read-only spike.
6. All existing gates stay green: `tofu -chdir=tofu test`, `packer validate`, gitleaks
   pre-commit; no secret and no real management IP is committed.

**Ordering (explicit):** the nlp-01 Ollama model pull and the Suricata go-live happen AFTER
the Wave 2 cutover lands. Suricata *configuration* is Wave 4; its go-live and the Ollama pull
are downstream follow-ups, not core waves.

---

## Context

Key files and facts (explorer-verified, file:line; spike facts primary-source-verified):

- **fw-01 is a tofu-managed full CLONE, greenfield** — `decisions.md:21` (D-01) overrides
  design.md's "adopted". Resource `module.vm["fw-01"].proxmox_virtual_environment_vm.this`,
  clone `vm_id = 9004`, `full = true` (`tofu/modules/proxmox-vm/main.tf:57-74`,
  `tofu/lab-vms.tf:71-122`, `lab.yaml:227-256`). `stop_on_destroy = true` (main.tf:42),
  `protection = false`, `agent: false` (`lab.yaml:249`) — so **no guest agent; recovery is
  the Proxmox serial/noVNC console**.
- **Template rebuild trap:** Packer proxmox-iso collides with the existing VMID 9004 — the
  old template must be `qm destroy 9004` first (no repo doc covers this yet; Wave 5 fixes
  that). AND the `terraform_data.template_exists` gate (`tofu/templates.tf:65-107`, check at
  77-86) fails ANY `tofu apply` in the window between destroying 9004 and the new build
  finishing — so the destroy→build→verify sequence is owned by ONE wrapper task
  (`task fw:rebuild-template`, built in Wave 2) plus an operational lock marker, not run as
  loose manual steps.
- **config.xml seed** (`packer/opnsense-267/config/config.xml.pkrtpl.hcl`):
  - root `<user>` block lines 96-108, `<password>${root_password_hash}</password>` at 106 —
    `<authorizedkeys>` (base64, DONE in Wave 1) and `<apikeys>` (Wave 2 offline bake) live
    here.
  - **API-key storage format (spike-verified from OPNsense source, ApiKeyField.php /
    Auth/API.php):** under a `<user>`,
    `<apikeys><item><key>PLAINTEXT_KEY</key><secret>$6$…HASH</secret></item></apikeys>`.
    The `<key>` is stored PLAINTEXT (80-char base64, sent as the HTTP Basic username); the
    `<secret>` is a SHA-512 crypt (`$6$`) of a chosen plaintext — NO per-install salt,
    deterministic and reproducible offline. Auth is `password_verify()` against the stored
    hash, so a random-salt `openssl passwd -6` hash works. **Therefore the API key is baked
    fully offline; no live-box bootstrap, no discovery step, no second cutover.** (An on-box
    PHP path — driving the User model via `/usr/local/bin/php`, csh-piped — exists but is a
    fallback only, not needed.)
  - `<IDS>` already templated at 485-512 (`suricata_enabled` default true,
    `suricata_ips_mode` false, `suricata_interfaces` "lan,opt1"); `<syslog_eve>0</syslog_eve>`
    at 508 is only a toggle — EVE→Wazuh ALSO needs a remote syslog destination (`<syslog/>`
    empty at 515), a downloaded/enabled ruleset (`<rules>`/`<policies>` empty at 486-487),
    AND a Wazuh-side syslog listener (Wave 4; Wazuh's Suricata decoders are built-in).
  - Scenario allow rules at 311-340 (must reproduce on redeploy). These are LEGACY
    `<filter>` rules — see the automation-vs-legacy ordering fact under Wave 4.
  - DHCP is Kea, `<OPNsense><Kea><dhcp4>` at 417-459 with the reservation loop; `<unbound>`
    present but disabled.
- **Packer var plumbing:** `templatefile()` map `packer/opnsense-267/opnsense.pkr.hcl:175-211`;
  var declarations `packer/opnsense-267/variables.pkr.hcl` (`root_password` 212-227;
  `root_password_hash` 229-244; `openssl passwd -6` documented at 236). Wave 1 added
  `root_authorized_keys` in that shape; Wave 2 adds `api_key`/`api_secret_hash` the same way.
  `base64encode()` is available template-side.
- **.envrc.example** OPNsense block = section 6 (root pw/hash + authorized key wired in
  Wave 1); Wave 2 adds the API pair.
- **Ansible:** fw-01 in `ansible/inventory/hosts.yml:45-51` (group `firewall`, ssh, root,
  "reachability-only"; OPNsense root shell is csh). The OPNsense collection: **`oxlorg.opnsense`
  (the RENAMED, active successor of `ansibleguy.opnsense`; versions track OPNsense; newest
  release 26.1.11 tracks 26.1 — host is 26.7, one minor ahead, REST API stable across the
  minor; re-check for a 26.7.x release at go-live).** Pin `oxlorg.opnsense: "26.1.11"`
  exactly in `ansible/requirements.yml`; use `oxlorg.opnsense.*` FQCNs. Install on the
  JUMPBOX (control node 10.10.10.5) via `scripts/bootstrap-jumpbox.sh` (`install_collections()`
  at ~427-439, `collections_path = collections`; idempotent re-run). Per
  `ansible/roles/README.md:8-16`, single-host work is a NUMBERED PLAYBOOK →
  `05-fw-config.yml` (05 slot free; existing: 00, 10, 20, 30, 40, 50, 60, 70, 75, 80, 90).
  The Wazuh-side syslog listener depends on 40-wazuh-server and lands beside 70-detections.
- **Taskfile:** `build:opnsense` at 208-214 → `packer:run` at 152-178; deploy `lab:up` at
  332-363 (`tofu apply -parallelism=1`), `lab:down` 365-381. `fw:*` verbs modeled on
  `scenario:*`/`learner:*` for shape; **transport decision (resolved): API verbs wrap an
  `ansible-playbook` run ON the jumpbox**, not the `LAB_HOST_SSH` scp-to-/tmp pattern.
- **Recovery surface:** the management path (workstation→WireGuard→host `<LAB_MANAGEMENT_IP>`;
  host bridge IPs 10.10.10.2/10.10.20.2; jumpbox static 10.10.10.5) does NOT route through
  fw-01 and survives the cutover blip. What breaks during the blip: lab DHCP/NTP/routing/
  internet + cross-segment traffic. Bad-fw-01 recovery = Proxmox serial/noVNC console; the
  pre-cutover config.xml export is the **config-level** rollback and a pre-replace `vzdump`
  of VMID 100 is the **VM-level** rollback (review finding 6).
- **Stays green:** `tofu -chdir=tofu test` (offline) after any lab.yaml/tofu change;
  `packer validate` after seed/var changes; gitleaks pre-commit. fw-01 MACs are pinned
  (`lab.yaml:243-247`) so addressing survives the replace. `lab.yaml` is NOT expected to
  change in this plan.
- **Scenario invocation (review finding 12, confirmed non-issue):**
  `task scenario:run -- ssh-bruteforce` / `task scenario:verify -- ssh-bruteforce` is the
  correct, working syntax — verified live this session.

**Decisions baked in — do not re-open:**

1. **Root password:** operator sets `PKR_VAR_root_password` (lab-standard value) +
   `PKR_VAR_root_password_hash` = `openssl passwd -6` of it. Build-blocked by
   `scripts/fw-preflight.sh` / `task fw:preflight` (shipped in Wave 1, commit 87e80d0):
   empty fails Packer validation; mismatched hash fails the preflight; the preflight is a
   hard prerequisite of `qm destroy 9004` (review finding 1).
2. **`fw:*` transport:** Ansible on the jumpbox, wrapped by Taskfile verbs.
3. **fw-01 config is a numbered playbook** (`05-fw-config.yml`), not a role.
4. **Redeploy verb** is `-replace`, never `-target` (no-op) and never destroy-then-apply.
5. **API key is baked OFFLINE and rides the single Wave 2 cutover** (spike finding; replaces
   revision 2's disposable-clone bootstrap). The "second load-bearing redeploy" concern
   (review finding 2) is designed out entirely: there is exactly ONE `-replace` in this plan.
6. **Egress rule is content-scoped, never order-scoped** (spike finding): the automation
   filter table evaluates BEFORE legacy single-interface rules, so the research-plane egress
   rule must EXCLUDE the SOC LAN by content (`destination_net: 10.10.10.0/24` +
   `destination_invert: true`), not rely on placement relative to the legacy block rule.

---

## Waves

### Wave 1 — Bake SSH key, wire root password, build the hard preflight — **COMPLETE (commit 87e80d0)**

Shipped: `.envrc.example` section-6 updates; non-empty `validation {}` on
`root_password`/`root_password_hash`; `variable "root_authorized_keys"` + templatefile map
entry + `<authorizedkeys>` in the seed's root `<user>` block; `scripts/fw-preflight.sh`
(hash↔password crypt cross-check, pubkey plausibility, rendered-config XML sanity) wired as
`task fw:preflight` and as a precondition of `task build:opnsense`. Exit criteria met:
`packer validate` red-on-empty/green-on-set; preflight blocks a mismatched hash;
`tofu -chdir=tofu test` green; pre-commit green. No host contact occurred.

### Wave 2 — Offline API-key bake + from-scratch rebuild + the SINGLE `-replace` cutover

The API bake is offline and mechanically identical to Wave 1's SSH-key bake (spike-verified
format), so it folds into THIS wave, before the rebuild. Nothing destructive runs until the
named **ALL-LOCAL-GATES-GREEN** checkpoint passes; destroy→build→verify is owned by one
wrapper task.

| # | Task | Files / host | Verify |
|---|------|--------------|--------|
| 2.1 | **Offline API-key bake (was Wave 3; now offline per spike).** (a) Generate locally: `FW_API_KEY=$(openssl rand 60 | openssl base64 -A)`, `FW_API_SECRET=$(openssl rand 60 | openssl base64 -A)`, `FW_API_SECRET_HASH=$(openssl passwd -6 "$FW_API_SECRET")`. Both plaintexts live in gitignored `.envrc` (lab creds, never committed); document all of it in `.envrc.example` section 6 (`PKR_VAR_api_key`, `PKR_VAR_api_secret_hash`, plus `FW_API_KEY`/`FW_API_SECRET` for API clients). (b) Add `api_key` + `api_secret_hash` vars to `variables.pkr.hcl` (sensitive, non-empty validation) + templatefile map entries in `opnsense.pkr.hcl`, same shape as `root_authorized_keys`. (c) Add `<apikeys><item><key>${api_key}</key><secret>${api_secret_hash}</secret></item></apikeys>` to the seed's root `<user>` block (root carries all privileges, so the automation's page access is covered; if a dedicated user is ever split out, it must be granted the needed privs explicitly). (d) Extend `scripts/fw-preflight.sh`: API pair set + hash begins `$6$`. | `packer/opnsense-267/{variables.pkr.hcl,opnsense.pkr.hcl,config/config.xml.pkrtpl.hcl}`, `.envrc.example`, `scripts/fw-preflight.sh` | `packer validate` green (and red with API vars empty); `task fw:preflight` green, red on a non-`$6$` hash; gitleaks passes. |
| 2.2 | **Build `task fw:rebuild-template` (review finding 5).** One Taskfile verb owning the whole no-template window atomically: (a) runs the ALL-LOCAL-GATES-GREEN checkpoint (2.3a); (b) writes a lock marker (local `.planning/opnsense-as-code/.rebuild-in-progress` AND a marker file on the host) meaning "NO `tofu apply` of any kind — template_exists gate will fail"; (c) `qm destroy 9004`; (d) launches the detached Packer build with a captured PID file; (e) polls to completion, verifies the new template (`qm list` + `grep '^template: 1'`), only then removes the lock. Operators never run the partial steps by hand; the runbook (Wave 5) says so. | `Taskfile.yml` (+ helper in `scripts/` if needed) | Dry review; its first real run IS task 2.4. |
| 2.3 | **GATE.** (a) **ALL-LOCAL-GATES-GREEN checkpoint:** `task fw:preflight` (now incl. API pair) AND `packer validate` AND full pre-commit/gitleaks — all green, recorded in the wave log. (b) **Rollback artifacts:** export live fw-01 `config.xml` to the workstation (one authorized password-SSH or console `cat /conf/config.xml`), stored OUTSIDE the repo — the CONFIG-level rollback. Take a `vzdump` backup of VMID 100 (snapshot mode) — the VM-level rollback (review finding 6). (c) Confirm serial/noVNC console access to VMID 100 works NOW. (d) Announce the lab-impact window (DHCP/NTP/routing/internet + cross-segment blip; management path unaffected). | live host, local `.envrc` | Checkpoint log all green; backup file locally with plausible size + `<filter>` content; `vzdump` archive listed; console reachable. |
| 2.4 | Run `task fw:rebuild-template`: lock on → `qm destroy 9004` (VM 100 keeps running — full clone) → detached `packer build` per house rules (`setsid nohup ... & echo $! > pidfile`; kill only by `kill "$(cat pidfile)"`; screendump the console before theorising on a stall). ~30-60 min, zero live impact. Lock stays on — no `tofu apply` anywhere — until the new template verifies. | live host, `packer/opnsense-267/` | `qm list` shows 9004 `tpl-opnsense-267`; `grep '^template: 1' /etc/pve/qemu-server/9004.conf`; lock removed. |
| 2.5 | The SINGLE cutover: `tofu apply -replace='module.vm["fw-01"].proxmox_virtual_environment_vm.this' -parallelism=1` (`stop_on_destroy=true` handles the old VM). Watch the boot on the serial console. | live host | Apply completes; VM 100 running; console shows OPNsense up on 10.10.10.1. |
| 2.6 | **Reproduction + access verification** (jumpbox + host): (a) key SSH: `ssh root@10.10.10.1` from the jumpbox — no password; (b) **API auth (folded in from old Wave 3):** `curl -k -u "$FW_API_KEY:$FW_API_SECRET" https://10.10.10.1/api/core/firmware/status` returns 200/JSON; (c) `scp` the NEW `/conf/config.xml`, diff vs the 2.3 backup — filter rules (incl. scenario allows, seed 311-340), `<nat>`/`<outbound>`, `<gateways>`/`<interfaces>`, Kea `<dhcp4>` reservations, unbound-disabled all reproduce (expected diffs: `<authorizedkeys>`, `<apikeys>`, revision/uuids, root hash); (d) lab-live checks: cross-segment routing (jumpbox→10.10.20.x), Kea lease renew, DNS via dc-01, NTP; (e) end-to-end: `task scenario:run -- ssh-bruteforce` + `task scenario:verify -- ssh-bruteforce` (crosses fw-01 opt1→lan; syntax verified live). | live lab | All checks pass; scenario verify exits 0. |
| 2.7 | **Rollback path (only if 2.6 fails)** — scope precise (review finding 6): FIRST TIER (config-level): serial console, restore the 2.3 `config.xml` to `/conf/config.xml`, reboot — restores SERVICE; VM remains a clone of the NEW template. SECOND TIER (VM-level, if the template itself is bad): restore VMID 100 from the `vzdump` archive. Then stop and diagnose — do not iterate live. | live host | Documented in the wave log; exercised only on failure. |

**Wave 2 exit:** fw-01 is a from-scratch clone of the code-defined template, reproduces the
live config, and BOTH key SSH and API auth work — **zero manual firewall CONFIGURATION during
the deploy** (the config export, vzdump and console checks in 2.3 are approved SAFETY gates,
not configuration). Update `docs/iac/resume-here.md` + memory note with the new live state.

### Wave 3 — (largely designed out by the spike) residual close-out

The revision-2 Wave 3 (live discovery → bake → disposable-clone proof) is obsolete: the API
key format is deterministic and baked offline in 2.1, proven live in 2.6, in ONE cutover.
What remains is small:

| # | Task | Files | Verify |
|---|------|-------|--------|
| 3.1 | Document the on-box FALLBACK path (drive the OPNsense User model via `/usr/local/bin/php`, csh-piped) in the Wave 5 runbook material — for the day an operator must mint an extra API key on a live box without a rebuild. Fallback only; not part of any deploy path. | notes → `docs/iac/` runbook (written in 5.2) | Runbook section exists. |
| 3.2 | Record standing state in `docs/iac/resume-here.md`: template and live fw-01 are in lockstep incl. API access; any future fw-01 `-replace` follows the Wave 2 gate runbook verbatim. | docs | Note present. |

**Wave 3 exit:** bookkeeping done; no host contact.

### Wave 4 — fw-01 managed by Ansible: `05-fw-config.yml` + Suricata/EVE→Wazuh

**Critical design fact (spike-verified):** `oxlorg.opnsense.rule` manages OPNsense's
AUTOMATION filter table, which is SEPARATE from the legacy `<filter>` rules the seed ships,
and automation single-interface rules evaluate BEFORE legacy single-interface rules. An
automation `pass 10.10.20.30 → any` on opt1 would therefore be evaluated BEFORE the seed's
legacy `opt1→lan` block and PUNCH THROUGH SOC-LAN isolation ("any" includes 10.10.10.0/24).
The egress rule is content-scoped (decision 6), never order-scoped. Corollary: the `rule`
module CANNOT see or assert the seeded LEGACY scenario allow rules (no REST API for legacy
`<filter>`) — the standing-allows check reads `/conf/config.xml` instead, with the seed as
source of truth.

| # | Task | Files | Verify |
|---|------|-------|--------|
| 4.0 | **Read-only spike — gate for 4.3/4.4.** Against live fw-01's API (GET/list only): (a) confirm the `os-ids` plugin surface is present; (b) confirm exact route casing for the write calls used later — `/api/ids/service/reloadRules`, `/api/ids/settings/{searchInstalledRulesets,toggleRuleset,setRuleset}`, `/api/syslog/settings/{searchDestinations,addDestination,setDestination,toggleDestination,delDestination}` + `/api/syslog/service/reconfigure`, `/api/firewall/filter/{searchRule,addRule,setRule/{uuid},toggleRule/{uuid}/{0|1},delRule,apply}`; (c) via `searchInstalledRulesets`, discover the exact version-specific FILENAME of the ET Open **emerging-attack_response** ruleset (holds the testmynids verification signature). Record the mapping table (module ↔ endpoint ↔ uri-fallback) in the playbook header. No writes before this lands. | spike notes → `05-fw-config.yml` header | Each capability row names an `oxlorg.opnsense` module or an explicit uri-fallback, each exercised READ-ONLY; ruleset filename recorded. |
| 4.1 | Add **`oxlorg.opnsense: "26.1.11"`** (exact pin — renamed successor of `ansibleguy.opnsense`; version tracks OPNsense 26.1, one minor behind the 26.7 host, REST API stable across the minor; re-check for a 26.7.x release at go-live) to `ansible/requirements.yml`, comment in the file's exact-pin style (load-bearing firewall control; bump deliberately). | `ansible/requirements.yml` | yamllint/pre-commit; pin matches the jumpbox after 4.2. |
| 4.2 | Install on the jumpbox: re-run `scripts/bootstrap-jumpbox.sh` (idempotent `install_collections()`; use skip flags for irreversible steps). Fix the script, not just the host, if a change is needed. | jumpbox | `jb_ssh 'ansible-galaxy collection list | grep oxlorg.opnsense'` shows 26.1.11. |
| 4.3 | New `ansible/playbooks/05-fw-config.yml` (after 00-preflight, before routing-dependent plays), run on the jumpbox against the fw API, authed by `FW_API_KEY`/`FW_API_SECRET` via env-lookup + `no_log` (copy the `wazuh_api_*` pattern in `ansible/inventory/group_vars/all.yml`). Content, idempotent with closing asserts, using `oxlorg.opnsense.*` FQCNs: (a) **standing scenario allows:** assert by reading `/conf/config.xml` (slurp over key SSH) — NOT via the `rule` module (legacy rules invisible to the API); seed is source of truth. (b) **research-plane egress rule** via `oxlorg.opnsense.rule`: `source_net: 10.10.20.30`, `destination_net: 10.10.10.0/24`, `destination_invert: true`, default `enabled: false`, toggled via `-e fw_egress_state=open|closed` — content-scoped so SOC-LAN isolation holds regardless of automation-vs-legacy ordering (decision 6). (c) **Suricata** via `oxlorg.opnsense.ids_general` (enabled, interfaces `lan,opt1`, IPS off, `syslog_output: true` — this IS the seed's `<syslog_eve>` toggle) + one-time `reloadRules` (downloads/updates ET Open so the signature exists) + `oxlorg.opnsense.ids_ruleset` enabling ONLY the emerging-attack_response ruleset discovered in 4.0 (`ids_policy` not needed for one ruleset; broader curation deferred to go-live/tuning). (d) **EVE→Wazuh, fw half:** remote syslog DESTINATION via `oxlorg.opnsense.syslog` — target 10.10.10.20, port 514, transport udp4, program suricata, level info (the toggle alone is inert; the seed ships neither object wired). Keep the `firewall` inventory reachability entry unchanged. | `ansible/playbooks/05-fw-config.yml`, `ansible/inventory/group_vars/all.yml` | First run applies; SECOND run changed=0; asserts pass. **Isolation regression check:** with egress OPEN, from 10.10.20.30 confirm internet egress works AND 10.10.10.0/24 (e.g. 10.10.10.30:80, 10.10.10.20) is STILL blocked. |
| 4.4 | **EVE→Wazuh, Wazuh half** (beside 70-detections; depends on 40-wazuh-server): add a `<remote><connection>syslog</connection><port>514</port><protocol>udp</protocol><allowed-ips>10.10.10.1</allowed-ips></remote>` listener to ossec.conf on wazuh-01. **Deviation flagged:** a NEW `<remote>` listener requires a full MANAGER RESTART, not the reload-only pattern 70-detections uses — sequence the restart in a maintenance moment so agents aren't dropped mid-class (agents buffer and reconnect, but do it deliberately). No custom decoder: Wazuh ships built-in Suricata decoders (json decoder, rule ids ~86xxx). | `ansible/playbooks/70-detections.yml` (or adjacent, matching its structure) | `curl http://testmynids.org/uid/index.html` from a lab VM across fw-01 → a Suricata alert (86xxx-range rule) appears in the Wazuh indexer/dashboard. |
| 4.5 | Egress toggle proof: `-e fw_egress_state=open` → nlp-01 (research plane) can `curl` out; `-e fw_egress_state=closed` → blocked again; SOC-LAN unreachable from the research plane in BOTH states. | — | All three observations logged. |

**Wave 4 exit:** fw-01 deltas are code; the egress rule cannot bypass segmentation by
construction; Suricata is on with the minimal verification ruleset and EVE flows to Wazuh
(go-live/tuning + the Ollama pull are the downstream follow-ups, in that order, using this
wave's egress toggle).

### Wave 5 — `task fw:*` verbs, docs, zero-touch deploy path

| # | Task | Files | Verify |
|---|------|-------|--------|
| 5.1 | Complete the Taskfile `fw:*` namespace (`fw:preflight` shipped in W1; `fw:rebuild-template` in W2): `fw:config` (run 05-fw-config.yml on the jumpbox), `fw:egress-open` / `fw:egress-close` (wrap the `-e` toggle), `fw:status` (API health curl via jumpbox). Each API verb = ssh to the jumpbox → `ansible-playbook -i inventory ...` in the synced repo dir. | `Taskfile.yml` | `task --list` shows the verbs; `task fw:status` returns JSON; `fw:egress-open`/`close` reproduce 4.5. |
| 5.2 | Docs — the trap and the verb: a "rebuilding the OPNsense template / redeploying fw-01" runbook covering (a) `task fw:rebuild-template` is THE way (never manual `qm destroy 9004` + loose builds), lock-marker meaning, the template_exists no-apply window; (b) `task fw:preflight` green before any rebuild; (c) `-replace` (never `-target`); (d) rollback tiers (config.xml = config-level; vzdump of VMID 100 = VM-level); (e) exact scenario invocation `task scenario:run -- <id>` / `task scenario:verify -- <id>`; (f) the on-box PHP API-key fallback (from 3.1). Place in `docs/iac/` beside the existing walkthrough. | `docs/iac/getting-started.md` (+/or linked page) | Doc renders; an operator can follow it cold. |
| 5.3 | Update `docs/iac/getting-started.md` deploy path + `docs/iac/resume-here.md`: firewall requires zero manual configuration on deploy; `.envrc` OPNsense vars (root pw/hash/key + API pair) called out with the hash-mismatch trap and the preflight; note the `oxlorg.opnsense` 26.7.x re-check at go-live; mark `docs/proposals/opnsense-as-code.md` implemented (Milestone 1). | docs | Grep confirms no doc still instructs manual fw configuration in the deploy path. |
| 5.4 | Final guard sweep: `tofu -chdir=tofu test`, `packer validate`, `task fw:preflight`, full pre-commit; confirm `lab.yaml` untouched; confirm no real management IP committed (placeholder policy). | — | All green. |

---

## Verification

Per-wave (run by the verifier each wave):

- **W1 (done, 87e80d0):** `packer validate` red-on-empty/green-on-set; `task fw:preflight`
  fails a mismatched hash, passes a matching pair, render check catches an induced typo;
  `tofu -chdir=tofu test`; pre-commit.
- **W2:** preflight also gates the API pair (`$6$` check); ALL-LOCAL-GATES-GREEN logged
  BEFORE `qm destroy 9004`; config.xml backup + VMID-100 vzdump exist; new 9004 template
  verified on-host; post-replace: key SSH from jumpbox with no password, **API curl returns
  200**, config.xml diff clean apart from expected fields, DHCP/DNS/NTP/cross-segment checks,
  `task scenario:run -- ssh-bruteforce` + `task scenario:verify -- ssh-bruteforce` exit 0.
- **W3:** runbook fallback section + resume-here lockstep note present (docs-only).
- **W4:** 4.0 mapping table complete with read-only proof + attack_response ruleset filename;
  `oxlorg.opnsense` 26.1.11 pinned and on the jumpbox; second run of `05-fw-config.yml`
  changed=0; **isolation regression: egress OPEN still cannot reach 10.10.10.0/24 from the
  research plane**; testmynids curl → 86xxx Suricata alert in the indexer; manager restart
  for the `<remote>` listener done deliberately, agents healthy after; egress toggle proven
  both ways from nlp-01.
- **W5:** `task fw:status`/`fw:egress-open`/`fw:egress-close` end-to-end; `task --list`
  clean; final `tofu -chdir=tofu test` + `packer validate` + `task fw:preflight` +
  pre-commit; no real management IP committed.

End-to-end (the goal's own test): starting from no 9004 template, an operator with a filled
`.envrc` runs `task fw:preflight` → `task fw:rebuild-template` → the single `-replace` →
`task fw:config`, and at no point performs manual firewall CONFIGURATION — while
rules/NAT/DHCP/DNS/routing match the pre-cutover backup, SSH + API auth work from first boot,
and the scenario verify passes. The safety gates (config backup, vzdump, console-reachability
check) are the only manual touches, and they are deliberate.

House rules in force throughout: verify on the host, never assume; detached builds with
captured PIDs only; screendump the console before theorising; fix scripts, not just the host;
no secrets or real management IPs committed.

---

## Out of scope

- **The reusable OPNsense MCP server** (proposal §3 / Milestone 2) — its own repo and its own
  `/plan`, later. Nothing here may pre-build for it beyond the API key it will eventually use.
- **Ollama model pull on nlp-01** — downstream; it merely CONSUMES `task fw:egress-open`/`close`.
- **Suricata go-live/tuning** (rulesets beyond emerging-attack_response, update scheduling,
  alert-volume tuning, IPS mode, triage) — Wave 4 enables the minimal set only;
  `suricata_ips_mode` stays false. Also downstream: re-checking for an `oxlorg.opnsense`
  26.7.x release.
- Any change to `lab.yaml` topology, VMIDs, MACs, or other VMs; any restructuring of
  `.planning/` (billing contract N/A — no Quotient-parsed files exist).
- Adopting/reconciling the OLD live fw-01 in place (greenfield `-replace` only, per D-01).

---

## Spike findings disposition (revision 3)

1. **API key bakeable offline (OPNsense source: ApiKeyField.php / Auth/API.php):**
   `<apikeys>` = plaintext 80-char base64 `<key>` + `$6$` SHA-512-crypt `<secret>`, verified
   via `password_verify()` — no per-install salt, fully deterministic. → Old Wave 3
   (live discovery → bake → disposable-clone proof) DELETED; the bake moved into Wave 2 (task
   2.1) alongside the SSH key; ONE cutover total; API auth verified in 2.6(b). The on-box PHP
   creation path is documented as a fallback only (3.1/5.2). Review finding 2's second-redeploy
   concern is designed out; finding 3's discovery step is obsolete (format known from source).
2. **Collection renamed:** `ansibleguy.opnsense` → **`oxlorg.opnsense`** (active successor;
   versions track OPNsense). Pinned exactly at `26.1.11` (tracks 26.1; host 26.7 is one minor
   ahead, REST API stable across the minor; re-check for 26.7.x at go-live). All FQCNs and
   plan references updated.
3. **Automation-vs-legacy rule ordering (isolation bug avoided):** automation-table rules
   evaluate BEFORE legacy single-interface rules, so a `pass → any` egress rule on opt1 would
   bypass the seed's legacy `opt1→lan` block. → Egress rule is CONTENT-scoped
   (`destination_net: 10.10.10.0/24` + `destination_invert: true`, default disabled); an
   isolation regression check is a required W4 verification. Never rely on rule placement.
4. **Legacy `<filter>` invisible to the REST API:** the standing-allows assertion reads
   `/conf/config.xml`; the seed is source of truth.
5. **Suricata specifics:** `ids_general.syslog_output` == the seed's `<syslog_eve>` toggle;
   minimal ruleset = ET Open emerging-attack_response (holds the testmynids signature; exact
   filename discovered live via `searchInstalledRulesets` in 4.0); ET Open must be
   downloaded once via `reloadRules` before the signature exists; `ids_policy` unnecessary
   for one ruleset.
6. **EVE→Wazuh is two objects + a listener:** ids_general syslog toggle (inert alone) + an
   `oxlorg.opnsense.syslog` destination (10.10.10.20:514/udp4, program suricata, level info)
   + a Wazuh `<remote>` syslog listener (allowed-ips 10.10.10.1) — the latter needs a full
   MANAGER RESTART (the one deviation from 70-detections' reload-only rule; sequenced
   deliberately). Wazuh's Suricata decoders are built-in (86xxx) — no custom decoder.
7. **Raw-`uri` fallbacks captured** for every area (filter/ids/syslog endpoint lists recorded
   in W4.0); the 4.0 spike now only confirms route casing + `os-ids` presence + the ruleset
   filename, read-only.

## Codex review disposition (plan.codex-review.md, finding by finding)

1. **Password/hash not build-blocked** → FIXED (shipped in W1, commit 87e80d0):
   `scripts/fw-preflight.sh` + `task fw:preflight` cross-checks the hash; wired into
   `build:opnsense` and a hard prerequisite of the destroy inside `fw:rebuild-template`.
2. **Second live `-replace` treated as cheap** → DESIGNED OUT (revision 3): the API key is
   baked offline (spike-verified format), so there is exactly ONE cutover; no disposable-clone
   bootstrap needed. Any future replace follows the W2 gate runbook.
3. **API-key bootstrap underspecified** → OBSOLETE (revision 3): format known from OPNsense
   source; no live bootstrap exists. The on-box PHP path is documented as fallback only.
4. **Destroy before local gates** → FIXED: ALL-LOCAL-GATES-GREEN checkpoint required before
   `qm destroy 9004` (W2.3a), enforced inside `fw:rebuild-template`.
5. **No-apply window unguarded** → FIXED: `task fw:rebuild-template` owns
   destroy→build→verify atomically with lock markers; runbook forbids partial manual steps.
6. **Rollback scope imprecise** → FIXED: config.xml restore = CONFIG-level only; pre-replace
   `vzdump` of VMID 100 = VM-level rollback (W2.3b, W2.7).
7. **EVE→Wazuh module feasibility unproven** → RESOLVED by spike + narrowed W4.0 gate:
   modules and raw endpoints are now cited; the spike verifies route casing, `os-ids`
   presence and the ruleset filename read-only before writes.
8. **ET Open unscoped noise** → FIXED: only emerging-attack_response enabled; curation
   deferred to go-live/tuning.
9. **Floating collection version** → FIXED (updated for the rename): `oxlorg.opnsense`
   pinned exactly at `26.1.11`.
10. **W2 exit overclaim** → FIXED: "zero manual firewall CONFIGURATION during the deploy";
    safety gates named as such.
11. **Secrets-policy hit (real management IP)** → FIXED: `<LAB_MANAGEMENT_IP>` placeholder
    throughout; lab ranges remain literal per project CLAUDE.md.
12. **Scenario invocation syntax** → CONFIRMED NON-ISSUE: verified live; used verbatim.
