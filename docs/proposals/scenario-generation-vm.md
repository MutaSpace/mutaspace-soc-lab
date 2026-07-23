# Scenario-Generation Capability for the MutaSpace SOC Lab — Design & Implementation Proposal

## 1. Executive summary

**Recommendation: do not adopt a heavyweight scenario platform. Build a thin "scenario runner" out of the machinery this repo already has — one new Ansible playbook whose tags are the scenarios, fronted by `task scenario:*` verbs, with reset delegated to Proxmox snapshot rollback modelled on the existing `learner-snapshot.sh` / `learner-reset.sh`.** The one-button UX is a Task verb over a fixed catalogue of MITRE ATT&CK technique IDs; each ID already maps to a Wazuh/Suricata detection students diagnose.

Drive activity with **three complementary layers**, not one mega-tool:

| Layer | Tool | Why it wins |
|---|---|---|
| **Endpoint attack (primary)** | **Atomic Red Team** (`redcanaryco/atomic-red-team`, last commit 2026-07-20, MIT) | Best-maintained in the category; ATT&CK-indexed (scenario = a technique ID); per-technique `-Cleanup`; officially documented Wazuh+Sysmon path. |
| **Tier-1 Linux/web attack (no tooling)** | **Hydra / sqlmap / curl from `kali-01`** against the **Wazuh built-in ruleset** (4.14.6, current) | SSH brute force and nginx SQLi fire out-of-box with **zero custom rules** — the highest-reliability "lights up instantly" demos, and they work **today** without the un-built Windows template. |
| **Benign noise (phase 3)** | **GHOSTS** (`cmu-sei/GHOSTS`, v9.0.0 2026-06-03, commits today) | The only maintained real-process benign-user simulator; gives students a noise floor so "diagnose what's going on" is non-trivial. |

Network-signature scenarios use **offline `suricata -r` on a curated malware-traffic-analysis.net PCAP** (deterministic, topology-independent) rather than live replay, because `fw-01`'s Suricata is **inline with no SPAN** — a PCAP replayed onto `vmbr1` is never seen by the sensor.

**Explicitly AVOID** (verified defunct or wrong-category, and matching the instructor's "defunct/complicated" complaint):

- **MITRE/Apache Caldera** as the *primary* tool — needs a standing server + per-endpoint beaconing agent that **breaks on snapshot rollback**, plus CVE-2025-27364 (unauth RCE). Optional *phase-4* campaign tier only, pinned to the isolated plane.
- **RTA** (dead since 2018, Python 2.7), **DetectionLab** (sunset 2023-01-01), **Prelude Operator** (free build withdrawn; company pivoted commercial), **APTSimulator** & **Infection Monkey** (author-declared unmaintained / frozen).
- **Stratus Red Team**, **Leonidas**, **Splunk Attack Range v5** — cloud-only (AWS/Azure/GCP/K8s audit logs); **zero footprint** in an on-prem Wazuh/Suricata lab.
- **flightsim** as anything but a narrow optional — most modules pull live destinations from the AlphaSOC API (stale binary bolted to a third-party feed) and fight the lab's isolation intent.

The cost of admission is telemetry the lab *already plans*: Sysmon on the Windows hosts, auditd on Linux, and a Suricata `eve.json`→Wazuh pipeline. Those are one-time, Ansible-automatable, and survive rollback.

---

## 2. Recommended architecture

### 2.1 No new attack-engine VM

The generators are **agentless or self-contained binaries invoked from the existing Ansible control node (`jumpbox-01`)**. This is the decisive architectural choice — it sidesteps the "standing server that dies on rollback" failure that sinks Caldera, and it fits the repo's existing pattern (a numbered playbook + a role, driven from `jumpbox-01`).

- **Endpoint attacks** run *on the target endpoint itself* (`ubuntu-app-01`, `analyst-01`, later `win-client-01`, `dc-01`). Atomic Red Team is installed once per endpoint by an Ansible role; a technique is then invoked over the existing WinRM/SSH connection. Telemetry originates locally and reaches Wazuh through the agent that is **already enrolled** there.
- **Tier-1 network attacks** (brute force, SQLi) run **from `kali-01`** (VMID 108, `vmbr2`, 10.10.20.10) across `fw-01` toward `ubuntu-app-01` (VMID 106, `vmbr1`, 10.10.10.30) — which is why `ubuntu-app-01` sits on the LAN with a service worth attacking. This requires one `fw-01` rule permitting `vmbr2→ubuntu-app-01:22,80` (the firewall is default-deny isolated→LAN); that rule is part of the scenario, not a lab-wide hole.
- **Network-signature scenarios** run **offline** (`suricata -r sample.pcap`) on `ubuntu-app-01`, emitting `eve.json` that its Wazuh agent forwards — deterministic and independent of the inline-Suricata topology trap.

**Where things live on the network:**

- Attack *origination* for LAN-visible network scenarios: `kali-01` on **vmbr2** (isolated), reaching LAN targets through `fw-01`'s inline Suricata (authentic — the traffic actually crosses the IDS).
- Endpoint-detonation and benign noise: **on the vmbr1 endpoints themselves**, no new placement.
- **Phase-3 GHOSTS API server** (Docker Compose: Postgres + API + Grafana): a small server-side component. Put it on **`jumpbox-01`** (already the control node, already has Docker-able footprint) or, if you prefer isolation, a new `gen-01` `vmbr1` entry in `lab.yaml`. GHOSTS *clients* are an Ansible-deployed role on the endpoints.

### 2.2 How it fits Packer / OpenTofu / Ansible

Almost entirely in **Ansible** — the layer meant for "configure and drive," which is exactly what scenario generation is:

- **Packer** changes are limited to a **one-time telemetry bake**: Sysmon (`olafhartong/sysmon-modular`, actively maintained, ATT&CK-tagged — *not* the stale 2021 SwiftOnSecurity config) plus a Defender exclusion for the Atomic/attack toolpath baked into the `win-server-2022` (9002) and `win11-client` (9003) templates. The **`win11-client` template is not built yet** — that gates every Windows/AD scenario and is the single biggest prerequisite.
- **OpenTofu / `lab.yaml`**: **no change required for phases 1–2.** The runner reuses existing VMs. Phase 3 optionally adds a `gen-01` VM entry to `lab.yaml` (OpenTofu reads it via `yamldecode()`), which will need `tofu -chdir=tofu test` re-run per CLAUDE.md.
- **Ansible**: the bulk of the work — new roles (`attack_atomic_linux`, `attack_atomic_windows`, `telemetry_sysmon`, `telemetry_auditd`, `suricata_eve_forward`, later `ghosts_client`/`ghosts_server`) and new playbooks. Detection content extends the existing `ansible/files/wazuh-rules/local_rules.xml`, pushed by the existing `70-detections.yml`.

### 2.3 Why these tools

Atomic Red Team is the ATT&CK-emulation standard, MIT-licensed, continuously updated, and **officially documented by Wazuh** for the ART+Sysmon→Wazuh loop — meaning the detection path is validated, not speculative. It's per-technique addressable, so "scenario = technique ID list" is the tool's native grammar. Its `-Cleanup` is best-effort; the lab's snapshot rollback backstops it. Caldera adds chained C2 campaigns Atomic can't, but at the cost of a rollback-fragile standing agent — correct as an optional phase-4 tier, wrong as the default. The Wazuh built-in ruleset gives two zero-config Tier-1 wins on infrastructure that exists **today**; GHOSTS supplies the benign half of the instructor's "malicious **and** benign" requirement, which no attack tool provides.

---

## 3. Instructor one-button UX

The interface is a **Task verb over Ansible tags**. Scenarios are `ansible-playbook` tags on a single playbook (`75-scenario-run.yml`); tags are the lowest-friction selector with no daemon, no web UI, nothing to keep alive across resets.

### 3.1 The Taskfile surface (new `scenario:` namespace)

```yaml
# Taskfile.yml  (new block, sibling to the existing learner: tasks)

  scenario:list:
    desc: Show the scenario catalogue (id, tier, ATT&CK IDs, target, what fires).
    silent: true
    cmds:
      - '{{.SCRIPTS_DIR}}/scenario-catalog.sh'   # prints the table from scenarios.yml

  scenario:run:
    desc: >-
      Snapshot the in-scope VMs, then run one scenario by id.
      Usage: task scenario:run -- ssh-bruteforce
    preconditions:
      - sh: 'test -n "{{.CLI_ARGS}}"'
        msg: 'Pick a scenario: task scenario:run -- <id>   (see task scenario:list)'
      - sh: 'test -n "$PROXMOX_VE_ENDPOINT"'
        msg: 'Credentials not loaded. Copy .envrc.example to .envrc and run `direnv allow`.'
    cmds:
      - task: scenario:snapshot          # bracket the run with a rollback point
      - ansible-playbook -i {{.INVENTORY}} {{.ANSIBLE_DIR}}/playbooks/75-scenario-run.yml
          --tags "{{.CLI_ARGS}}"

  scenario:reset:
    desc: >-
      Roll every in-scope VM back to the pre-scenario snapshot. Usage: task scenario:reset
    cmds:
      - task: scenario:rollback

  scenario:snapshot:   # internal — see §4
  scenario:rollback:   # internal — see §4
```

### 3.2 What the instructor actually types

```console
$ task scenario:list
ID                 TIER          ATT&CK          TARGET          FIRES IN
ssh-bruteforce     1 Foundation  T1110           ubuntu-app-01   Wazuh 5712/5720 (auth.log)
web-sqli           1 Foundation  T1190           ubuntu-app-01   Wazuh 31103/31106 (nginx)
malware-drop       2 Intermed.   T1105 T1204     ubuntu-app-01   Wazuh FIM + YARA
netcat-shell       2 Intermed.   T1059 T1071     ubuntu-app-01   Wazuh 100050/100051
linux-persist      2 Intermed.   T1053.003 T1087 analyst-01      Wazuh auditd/ART rules
suricata-c2        2 Intermed.   T1071 T1571     ubuntu-app-01   Wazuh<-Suricata eve.json
lsass-dump         3 Advanced    T1003.001       win-client-01   Wazuh Sysmon EID10 rules
kerberoast         3 Advanced    T1558.003       dc-01           Wazuh 4769 AD rules
dcsync             4 Expert      T1003.006       dc-01           Wazuh 4662 AD rules
proc-injection     4 Expert      T1055.001/.012  win-client-01   Wazuh Sysmon EID8/25

$ task scenario:run -- ssh-bruteforce
==> snapshot 'scenario-baseline' taken on 102,103,104,106  (disk-only, VMs left running)
==> PLAY [Scenario: SSH brute force (T1110) against ubuntu-app-01] ...
==> hydra: 27 login attempts, 1 success (labadmin)
==> done. Watch the Wazuh dashboard: rule 5712/5720, MITRE T1110.

$ task scenario:reset
==> rolling 102,103,104,106 back to 'scenario-baseline' ... started. Clean.
```

A non-red-teamer never touches Hydra, PowerShell, or a technique ID by hand — they pick a catalogue entry. A `whiptail`/TUI menu or a small local Flask page (`ai/` already ships Python tooling) can front the Taskfile later, but the Task/tag layer ships first because it is testable and reset-safe.

### 3.3 Scenario definition format

One committed YAML catalogue, `ansible/scenarios.yml`, drives both `scenario:list` and the playbook's `when:`/tag logic:

```yaml
# ansible/scenarios.yml
- id: ssh-bruteforce
  tier: 1
  attack: [T1110]
  driver: hydra
  origin: kali-01
  target: ubuntu-app-01
  fires: ["wazuh:5712", "wazuh:5720"]
  objective: "Recognise a password-guessing burst and identify the source IP."
```

---

## 4. Reset / cleanup flow

**Snapshot-bracket every run; roll back to clean.** This is a home-grown Ludus "testing mode" scoped to the lab, using the mechanism the repo already ships.

The existing `scripts/learner-snapshot.sh` / `learner-reset.sh` operate on **per-learner VM blocks** (VMID `200 + (id-1)*10 + offset`). Scenarios instead run against the **shared lab set** (`dc-01` 102, `analyst-01` 103, `wazuh-01` 104, `win-client-01` 105, `ubuntu-app-01` 106, `kali-01` 108). So add two **sibling scripts** modelled line-for-line on the learner ones, differing only in which VMIDs they target and the snapshot name:

- `scripts/scenario-snapshot.sh` → `qm snapshot <vmid> scenario-baseline` across the in-scope set. **Disk-only, VMs left running** (same choice as `learner-snapshot.sh`: `--vmstate` would land an 8 GB memory image on the 96 GB root LV). It reuses the learner script's **name-verification guard** (a VMID whose config name doesn't match the expected role aborts) so a mis-numbered edit can't snapshot the wrong machine.
- `scripts/scenario-reset.sh` → `qm rollback <vmid> scenario-baseline && qm start <vmid>`, then force an NTP resync (Kerberos on `dc-01` is time-sensitive — the learner reset script already documents this trap).

Both run **on the host over SSH from the Taskfile**, exactly like `learner:snapshot`/`learner:reset` (`scp` the script to `/tmp`, `ssh sudo bash`, remove).

**Why snapshot rollback over tool `-Cleanup`:** several drivers deliberately leave artefacts (Atomic without `-Cleanup`, dumped hashes, forged tickets, dropped known-bad files, FIM-tripped paths). Rollback erases disk **and any collateral, partial-failure, or log state** in one deterministic step — far more reliable than trusting each tool's teardown. `Invoke-AtomicTest -Cleanup` remains a *lightweight per-technique* option for fast iteration within a single scenario; full rollback is the authoritative between-scenario reset.

**One correctness note for Wazuh:** custom rules/decoders and telemetry config live on `wazuh-01` and the agents and must **not** be wiped by a scenario reset. Take the `scenario-baseline` snapshot **after** telemetry + detection content is deployed (i.e. after `65-telemetry.yml` and `70-detections.yml` have run once). Then rollback restores a clean-but-instrumented lab, and detection content isn't lost as "reset drift."

---

## 5. Scenario catalog

Ordered as a difficulty progression. Tiers follow CyberDefenders' shape: **1 Foundational → 4 Expert**. "Fires" cites the concrete rule/event so it doubles as the answer key.

> **Availability gate:** scenarios 1–6 run on infrastructure that exists **today** (Linux endpoints + `kali-01` + inline Suricata). Scenarios 7–10 require the **`win11-client` template built** and **Sysmon + audit-policy deployed** — sequence them last.

---

### Tier 1 — Foundational

**1. SSH brute force**
- **ATT&CK:** T1110 (Brute Force)
- **Driver / origin → target:** `hydra` from `kali-01` → `ubuntu-app-01:22`
- **Telemetry/config required:** *none beyond default* — Wazuh Linux agent collects `/var/log/auth.log` out of the box. One `fw-01` rule allowing `vmbr2→10.10.10.30:22`.
- **Fires:** Wazuh **5710** (invalid user), **5712/5720** (≥8 failures/120s from one source, level 10, tagged **T1110**).
- **Learning objective:** recognise an authentication-failure burst; pivot from alert → source IP → affected account.
- **Expected findings:** a spike of failed logons from 10.10.20.10 within a 2-minute window, one eventual success; classify as external brute force, recommend source block + credential rotation.

**2. Nginx web attack / SQL injection**
- **ATT&CK:** T1190 (Exploit Public-Facing Application)
- **Driver:** `sqlmap` / crafted `curl` from `kali-01` → `ubuntu-app-01:80`
- **Config:** one `<localfile>` on the agent pointing at `/var/log/nginx/access.log` (two lines; part of `60-endpoints.yml`).
- **Fires:** Wazuh **31103** (SQL injection attempt, level 7, ATT&CK T1190), **31106** (successful web attack, HTTP 200).
- **Objective:** read web-server logs as an attack surface; distinguish probe from successful exploitation via response code.
- **Expected findings:** sequence of `UNION SELECT`/`' OR 1=1` patterns against a query string; identify which returned 200 vs 403.

---

### Tier 2 — Intermediate

**3. Malicious file drop (FIM + YARA)**
- **ATT&CK:** T1105 (Ingress Tool Transfer), T1204 (User Execution)
- **Driver:** Ansible drops an EICAR test file / benign web-shell into a FIM-watched path on `ubuntu-app-01`.
- **Config:** Wazuh **FIM** on `/var/www` + `/tmp`; **YARA** active-response (per the Wazuh PoC guide).
- **Fires:** FIM `550/554` (file added/changed), YARA match → active-response removal alert.
- **Objective:** file-integrity monitoring and automated malware response.
- **Expected findings:** a new file in a monitored directory, YARA verdict, auto-quarantine event; correlate drop time with a preceding network transfer.

**4. Unauthorized process / netcat reverse shell**
- **ATT&CK:** T1059 (Command & Scripting Interpreter), T1071 (Application Layer Protocol)
- **Driver:** Atomic Red Team T1059.004 / scripted `nc` listener + connect on `ubuntu-app-01`.
- **Config:** Wazuh **command monitoring** (`<localfile><log_format>command`) + **two custom manager rules 100050/100051** (from the Wazuh netcat PoC) added to `local_rules.xml`.
- **Fires:** 100050/100051 (unexpected listening process / netcat).
- **Objective:** detect a live reverse shell from process telemetry, not just network.
- **Expected findings:** an unexpected listener bound to a high port, a shell child process, outbound connect to `kali-01`.

**5. Linux discovery + persistence (Atomic)**
- **ATT&CK:** T1053.003 (cron), T1087 (Account Discovery)
- **Driver:** `Invoke-AtomicTest T1053.003`, `T1087.001` on `analyst-01` (pwsh + module installed by `attack_atomic_linux`).
- **Config:** **auditd** `execve` rules (role `telemetry_auditd`) forwarded by the Wazuh agent.
- **Fires:** Wazuh auditd rules on `crontab`/`/etc/cron.*` writes and `cat /etc/passwd`-class discovery; ATT&CK-tagged via custom rules keyed off the atomic.
- **Objective:** spot low-and-slow discovery + a persistence foothold in endpoint process telemetry.
- **Expected findings:** enumeration commands followed by a new cron entry; map both to ATT&CK, note the persistence mechanism survives reboot.

**6. Suricata network signature / C2 beacon**
- **ATT&CK:** T1071 (Application Layer Protocol), T1571 (Non-Standard Port)
- **Driver:** `suricata -r /opt/pcaps/<sample>.pcap` **offline** on `ubuntu-app-01` (curated malware-traffic-analysis.net infection PCAP — Emotet/Qakbot/C2). *Offline, not live replay* — `fw-01`'s inline Suricata has no SPAN, so a replay onto `vmbr1` is invisible to it.
- **Config:** **Suricata→Wazuh `eve.json` pipeline** (role `suricata_eve_forward`) — the highest-value prerequisite for all network scenarios; also forwards `fw-01`'s live inline `eve.json` for the Tier-1 attacks.
- **Fires:** Wazuh Suricata decoder / `0475-suricata_rules.xml`, ET Open signatures for the sample's C2/DNS pattern.
- **Objective:** read IDS alerts; pivot from a signature to the offending flow and destination.
- **Expected findings:** repeated beacon to a known-bad host at a fixed interval; identify C2 domain/IP and periodicity. (MTA.net ships **answer keys** — ideal for graded diagnosis.)

---

### Tier 3 — Advanced *(requires `win11-client` template + Sysmon)*

**7. LSASS credential dump**
- **ATT&CK:** T1003.001 (LSASS Memory)
- **Driver:** `Invoke-AtomicTest T1003.001` on `win-client-01`.
- **Config:** **Sysmon** (`olafhartong/sysmon-modular`) logging **EID 10** (ProcessAccess to `lsass.exe`); Wazuh agent forwarding `Microsoft-Windows-Sysmon/Operational`; custom rules from the Wazuh ART blog keyed off `win.eventdata.ruleName`.
- **Fires:** Sysmon EID 10 access to `lsass.exe` with a dump-tool call trace → custom credential-access rule.
- **Objective:** the marquee endpoint-detection lesson — credential theft visible via process-access telemetry.
- **Expected findings:** a non-system process opening `lsass` with `PROCESS_VM_READ`; identify the tool and the granted access mask.

**8. Kerberoasting**
- **ATT&CK:** T1558.003 (Kerberoasting)
- **Driver:** Atomic / `Rubeus`/`GetUserSPNs` from `win-client-01` → `dc-01`.
- **Config:** **advanced audit policy via GPO on `dc-01`** — *Audit Kerberos Service Ticket Operations* (Event **4769**) is **off by default**; deploy the GPO in `65-telemetry.yml`. Wazuh AD-attack blog rules in `local_rules.xml`.
- **Fires:** Event 4769 with **encryption type 0x17 (RC4)** and TicketOptions `0x40810000` → Kerberoasting rule.
- **Objective:** identity-plane attack detection from Kerberos audit events.
- **Expected findings:** a burst of RC4 service-ticket requests for SPN accounts from one workstation; name the targeted service account.

---

### Tier 4 — Expert *(requires DC audit policy + Sysmon; leaves artefacts → rollback mandatory)*

**9. DCSync**
- **ATT&CK:** T1003.006 (DCSync)
- **Driver:** Atomic / `mimikatz lsadump::dcsync` from `win-client-01` against `dc-01`.
- **Config:** GPO **Audit Directory Service Access** (Event **4662**) — off by default; the Wazuh AD blog rules matching the DRSR replication GUIDs `{1131f6aa-…}` / `{19195a5b-…}`.
- **Fires:** Event 4662 replication-access rule (DCSync).
- **Objective:** detect replication abuse — a domain-dominance technique with no malware on disk.
- **Expected findings:** a non-DC principal requesting directory replication; recognise the GUIDs as the DCSync signature, escalate as Tier-1 incident.

**10. Process injection**
- **ATT&CK:** T1055.001 (DLL), T1055.012 (Hollowing)
- **Driver:** `Invoke-AtomicTest T1055` on `win-client-01`.
- **Config:** **Sysmon EID 8 (CreateRemoteThread) and EID 25 (ProcessTampering)** — verify the modular config's `<ProcessTampering>` block is present (the stale SwiftOnSecurity config **omits EID 25** and this silently never fires). Custom rule 100201.
- **Fires:** Sysmon EID 8/25 → process-injection/hollowing rule (level 12).
- **Objective:** detect defence-evasion via injection; understand why Sysmon config, not the rule, is usually why an alert "didn't fire."
- **Expected findings:** a remote thread created in a benign process / a hollowed image; identify source and target process.

---

## 6. AI-assist integration

The lab's local Ollama on `nlp-01` and the `ai/` copilot become a **guided investigator, not an answer key.** Each scenario in `ansible/scenarios.yml` carries an `objective` and an `answer_key`; the copilot is fed the key with a hard **"never reveal, only nudge toward"** system constraint.

- **Role-lock the system prompt:** "You are a SOC mentor. The student is diagnosing an incident. You know the ground truth but must NEVER state the technique, the answer, or the exact rule ID. Ask questions that move them toward the evidence."
- **Grounded on ATT&CK ground truth:** because every scenario ships a technique ID and a named Wazuh rule as the expected finding, the copilot can check a student's hypothesis against the label and steer without leaking it — e.g. student asks "what is rule 5712?", copilot responds with "what do the timestamps and source IPs on those alerts have in common?" rather than "it's brute force."
- **Fading hint hierarchy:** self-reflection prompt → concept redirect → targeted scaffold, escalating only after earlier hints fail (SocraticAI/LearnLM pattern).
- **Alert-enrichment path:** Wazuh's own PoC #16 ("Leveraging LLMs for alert enrichment") is the integration point — **repoint it at the local Ollama endpoint on `nlp-01`** (the shipped recipe uses OpenAI; substitute the local model). Students paste a live alert and get context, not the verdict.
- **Isolation caveat:** `nlp-01` is on `vmbr2`. The copilot must reach it without giving students an egress path that alters the scenario — proxy the enrichment call through `jumpbox-01` or the `ai/` service, don't open `vmbr1→vmbr2` broadly.

---

## 7. Phased implementation plan

Concrete waves against this repo's layout. **Build Wave 1 first for a minimal end-to-end demo: one scenario, visible in Wazuh, resettable — with no new VM and no Windows template.**

### Wave 1 — Minimal end-to-end (SSH brute force). *Ship this first.*
1. `scripts/scenario-snapshot.sh` + `scripts/scenario-reset.sh` — copy `learner-snapshot.sh`/`learner-reset.sh`, retarget to the shared set (102,103,104,106,108), snapshot name `scenario-baseline`.
2. `ansible/scenarios.yml` — catalogue, seeded with `ssh-bruteforce`.
3. `ansible/playbooks/75-scenario-run.yml` — tag `ssh-bruteforce`: install `hydra` on `kali-01`, add the `fw-01` allow rule, run the burst.
4. `Taskfile.yml` — `scenario:list`, `scenario:run`, `scenario:reset`, `scenario:snapshot`, `scenario:rollback` (mirror the `learner:` precondition guards).
5. **Verify on the host** (per CLAUDE.md): run it, confirm rule 5712/5720 in Wazuh, `task scenario:reset`, confirm clean.

*Deliverable: `task scenario:run -- ssh-bruteforce` → alert in Wazuh → `task scenario:reset` → clean. No Windows, no Sysmon.*

### Wave 2 — Linux/web Tier-1 & 2 breadth
- `ansible/roles/attack_atomic_linux` (pwsh + `Invoke-AtomicRedTeam` module + atomics on `ubuntu-app-01`/`analyst-01`).
- `ansible/roles/telemetry_auditd`, `ansible/roles/suricata_eve_forward` (OPNsense inline + offline `eve.json` → Wazuh). New playbook `65-telemetry.yml`.
- Extend `ansible/files/wazuh-rules/local_rules.xml` with netcat 100050/100051 etc.; deploy via existing `70-detections.yml`.
- Add scenarios `web-sqli`, `malware-drop`, `netcat-shell`, `linux-persist`, `suricata-c2`.
- Re-run `tofu -chdir=tofu test` if `lab.yaml` touched; it isn't in this wave.

### Wave 3 — Benign noise (GHOSTS)
- `ansible/roles/ghosts_server` (Docker Compose on `jumpbox-01`, or new `gen-01` entry in `lab.yaml` → run `tofu -chdir=tofu test`).
- `ansible/roles/ghosts_client` (.NET runtime + client + timeline JSON on the Linux endpoints; browsers/webdriver where needed).
- Make benign noise an always-on backdrop toggled by `task scenario:noise:start|stop`.

### Wave 4 — Windows / AD Tier 3–4 *(gated on the un-built `win11-client` template)*
- **Build the `win11-client` (9003) Packer template** — the hard prerequisite.
- Bake Sysmon (`olafhartong/sysmon-modular`) + Defender exclusion into `win-server-2022`/`win11-client` Packer builds; `packer validate` + verify EID 8/10/25 on host.
- `ansible/roles/telemetry_sysmon`, `ansible/roles/attack_atomic_windows`; audit-policy GPOs (4662/4769) into `65-telemetry.yml`.
- Import the Wazuh AD-attack and process-injection blog rules into `local_rules.xml`.
- Add `lsass-dump`, `kerberoast`, `dcsync`, `proc-injection`. **Re-take `scenario-baseline` after Sysmon/rules land.**

### Wave 5 (optional) — Campaign tier
- Caldera on the **isolated plane only** (CVE-2025-27364, never exposed), as `task scenario:campaign:*`, with Ansible-wired Sandcat redeploy so agents survive rollback.

---

## 8. Risks & open questions

- **`win11-client` template unbuilt** — blocks all of Tier 3–4. Windows uses eval media each operator must build locally (licensing; can't ship a prebuilt image). Biggest schedule risk; Waves 1–3 are deliberately Windows-free so value ships before it's resolved.
- **Rule-ID collisions** — the lab already authors `local_rules.xml`; the Wazuh AD/injection blogs use `110xxx`/`100xxx` and SOCFortress uses `100000+/200000+/700000+`. A collision makes **`wazuh-manager` fail to restart** — a SIEM-down event mid-class. Reserve a band for lab rules and reconcile before importing any pack; the existing `70-detections.yml` uses `reload`, not `restart`, which softens but doesn't remove this.
- **Snapshot scope vs learner clones** — `scenario-*` scripts target the shared set (102–108); ensure they never collide with the `200+` learner blocks. Reuse the learner scripts' name-verification guard verbatim.
- **`fw-01` scenario rules** — Tier-1 network scenarios need a `vmbr2→ubuntu-app-01` allow. OPNsense isn't Ansible-managed yet (configured by API/`config.xml`); either script the rule via the OPNsense API in the scenario or pre-stage a scoped rule. **Open question:** API-driven per-scenario rules vs a standing narrow rule.
- **Inline Suricata may DROP, not alert** — `fw-01` runs Suricata **inline/IPS**; a matched C2 signature could drop the beacon and change the exercise. Prefer the **offline `suricata -r`** path for network scenarios; run live attacks alert-only if used.
- **Snapshot rollback + Kerberos time skew** — rolling `dc-01` back to an old snapshot desyncs the clock; Kerberos breaks until NTP resyncs. The learner reset script already documents this — carry the same forced resync into `scenario-reset.sh`.
- **Atomic Red Team runner cadence** — the *atomics library* is updated continuously (2026-07-20) but `invoke-atomicredteam` (the runner) is slower (v2.3.0, 2025-02; commits to 2025-09). Pin a known-good runner version in the Ansible role rather than tracking `latest`.
- **GHOSTS operational weight** — heaviest component (per-endpoint .NET + webdriver + real apps). Rightly Wave 3, not gating the one-button deliverable. Known Postgres-container-IP gotcha to watch.
- **Verify-on-host discipline** — per CLAUDE.md, confirm each detection actually fires (`Microsoft-Windows-Sysmon/Operational` events present, rule IDs in the dashboard) before declaring a scenario functional; do not claim results unobserved.

**Bottom line:** one new Ansible playbook (`75-scenario-run.yml`), a scenario catalogue, a telemetry playbook (`65-telemetry.yml`), a pair of snapshot scripts mirroring the learner ones, and a `scenario:` Taskfile namespace — driving Atomic Red Team + `kali-01` one-liners against the lab's own Wazuh/Suricata, reset by snapshot rollback. Four hard requirements met with **zero new long-running services** in phases 1–2, and every technique an ATT&CK ID the local-LLM copilot can reason about against ground truth.
