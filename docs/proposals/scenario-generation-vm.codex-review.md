> Cross-model review by **codex (gpt-5.5)**, 2026-07-23 — a skeptical second opinion on `scenario-generation-vm.md`.

## Staff Review

### Biggest Risks / Wrong Calls

1. **Reset plan is under-specified and probably too optimistic.**  
   Rolling back `wazuh-01` along with targets may erase the very evidence students are supposed to investigate unless timing is carefully controlled. If students investigate after scenario completion, Wazuh must retain alerts. If `scenario:reset` rolls back Wazuh, that is fine only after grading is complete. The proposal needs an explicit evidence-retention model.

2. **Detection reliability is assumed, not engineered.**  
   “Fires Wazuh rule X” is not enough. Each scenario needs a testable contract: exact log source, decoder, rule, expected fields, expected latency, and a verification command/API check. Otherwise this becomes a demo that works once and fails during class.

3. **Snapshot scope is dangerous.**  
   Shared lab VMs, learner clones, Wazuh manager, AD, Kali, firewall, and app hosts have different reset semantics. Treating them as one rollback set risks losing detection content, breaking agent enrollment, invalidating clocks, or erasing logs. Snapshot groups need roles: target reset, sensor preserve, infra preserve, optional full reset.

4. **Atomic Red Team is being over-trusted.**  
   ART is useful, but many atomics are brittle, environment-sensitive, noisy, blocked by AV, or produce telemetry that does not match the intended rule. Pinning versions helps, but every chosen atomic still needs local validation and probably wrapping.

5. **The offline Suricata path is pedagogically awkward.**  
   Running `suricata -r` on `ubuntu-app-01` and forwarding generated `eve.json` is deterministic, but it is not the same as detecting traffic crossing the inline sensor. That distinction matters in a SOC lab. It is acceptable as a PCAP-analysis scenario, not as “network detection through the lab.”

### Over-Engineered / Fragile

- **Too many tools too soon.** Hydra, sqlmap, Atomic, YARA, auditd, Sysmon, Suricata PCAPs, GHOSTS, LLM hints, AD attacks, OPNsense API changes, snapshot orchestration. For a solo instructor, this is a maintenance trap unless Wave 1 stays ruthlessly small.

- **GHOSTS is likely not worth the operational cost early.** It adds server state, endpoint clients, browser/app dependencies, .NET/runtime issues, timelines, and another reset surface. Synthetic benign logs from cron, web browsing scripts, SSH logins, package updates, and normal AD auth may be enough for v1.

- **Per-scenario firewall mutation is fragile.** Changing OPNsense rules during scenario runs introduces failure modes unrelated to the learning objective. Prefer pre-staged narrow lab rules unless the firewall change itself is part of the lesson.

- **The LLM mentor design is premature.** It depends on reliable ground truth, durable scenario state, and prompt behavior that does not leak answers. Build it after scenarios have machine-verifiable detections and answer keys.

### Missing

- **Scenario acceptance tests.**  
  Every scenario should ship with `run`, `verify`, and `cleanup/reset` checks. Example: query Wazuh API for rule `5712` from `10.10.20.10` within the last N minutes and fail if absent.

- **Reset correctness tests.**  
  After rollback, verify VM power state, hostname/VMID match, Wazuh agent connectivity, time sync, AD health, expected snapshots, absence of known artifacts, and baseline alert count.

- **Evidence lifecycle.**  
  Decide whether Wazuh is part of the rollback set. If Wazuh is reset, alerts disappear. If Wazuh is preserved, scenarios accumulate historical noise. Both are valid, but the instructor workflow must make that explicit.

- **Version and content pinning.**  
  Pin Atomic repo commit, Invoke-Atomic version, Sysmon config release/commit, Suricata ruleset, PCAP hashes, Wazuh version assumptions, and custom rule ID bands.

- **A rule collision and manager-health gate.**  
  Before any class, validate `local_rules.xml`, restart/reload Wazuh in a controlled check, and assert manager health. A broken rules file can kill the whole lab.

- **Safety boundaries.**  
  Some scenarios involve credential dumping, web shells, reverse shells, and AD abuse. The proposal should define isolation guarantees, no-internet assumptions, allowed toolpaths, Defender exclusions, and post-reset secret hygiene.

## Verdict

The direction is mostly right: thin runner, no Caldera-first platform, start with Linux/Wazuh scenarios, snapshot-backed reset. But the proposal is still too tool-centric and not enough reliability-centric. In a teaching lab, “one click” only matters if the alert reliably appears and reset reliably restores a known-good state.

## Top 3 Changes Before Building

1. **Define a scenario contract and verification harness first.**  
   Each scenario needs declared prerequisites, affected VMs, expected alerts, Wazuh API verification, reset checks, and pass/fail output.

2. **Redesign snapshot scope.**  
   Separate targets from sensors/control-plane. Preserve Wazuh evidence during investigation, and provide a deliberate full-baseline reset when the instructor wants to clean history.

3. **Ship only two v1 scenarios.**  
   Build `ssh-bruteforce` and `web-sqli` end to end: run, verify alerts, student investigate, reset, verify clean. Do not add Atomic, GHOSTS, Windows, AD, YARA, or LLM integration until that loop survives repeated class-style runs.
tokens used
## Staff Review

### Biggest Risks / Wrong Calls

1. **Reset plan is under-specified and probably too optimistic.**  
   Rolling back `wazuh-01` along with targets may erase the very evidence students are supposed to investigate unless timing is carefully controlled. If students investigate after scenario completion, Wazuh must retain alerts. If `scenario:reset` rolls back Wazuh, that is fine only after grading is complete. The proposal needs an explicit evidence-retention model.

2. **Detection reliability is assumed, not engineered.**  
   “Fires Wazuh rule X” is not enough. Each scenario needs a testable contract: exact log source, decoder, rule, expected fields, expected latency, and a verification command/API check. Otherwise this becomes a demo that works once and fails during class.

3. **Snapshot scope is dangerous.**  
   Shared lab VMs, learner clones, Wazuh manager, AD, Kali, firewall, and app hosts have different reset semantics. Treating them as one rollback set risks losing detection content, breaking agent enrollment, invalidating clocks, or erasing logs. Snapshot groups need roles: target reset, sensor preserve, infra preserve, optional full reset.

4. **Atomic Red Team is being over-trusted.**  
   ART is useful, but many atomics are brittle, environment-sensitive, noisy, blocked by AV, or produce telemetry that does not match the intended rule. Pinning versions helps, but every chosen atomic still needs local validation and probably wrapping.

5. **The offline Suricata path is pedagogically awkward.**  
   Running `suricata -r` on `ubuntu-app-01` and forwarding generated `eve.json` is deterministic, but it is not the same as detecting traffic crossing the inline sensor. That distinction matters in a SOC lab. It is acceptable as a PCAP-analysis scenario, not as “network detection through the lab.”

### Over-Engineered / Fragile

- **Too many tools too soon.** Hydra, sqlmap, Atomic, YARA, auditd, Sysmon, Suricata PCAPs, GHOSTS, LLM hints, AD attacks, OPNsense API changes, snapshot orchestration. For a solo instructor, this is a maintenance trap unless Wave 1 stays ruthlessly small.

- **GHOSTS is likely not worth the operational cost early.** It adds server state, endpoint clients, browser/app dependencies, .NET/runtime issues, timelines, and another reset surface. Synthetic benign logs from cron, web browsing scripts, SSH logins, package updates, and normal AD auth may be enough for v1.

- **Per-scenario firewall mutation is fragile.** Changing OPNsense rules during scenario runs introduces failure modes unrelated to the learning objective. Prefer pre-staged narrow lab rules unless the firewall change itself is part of the lesson.

- **The LLM mentor design is premature.** It depends on reliable ground truth, durable scenario state, and prompt behavior that does not leak answers. Build it after scenarios have machine-verifiable detections and answer keys.

### Missing

- **Scenario acceptance tests.**  
  Every scenario should ship with `run`, `verify`, and `cleanup/reset` checks. Example: query Wazuh API for rule `5712` from `10.10.20.10` within the last N minutes and fail if absent.

- **Reset correctness tests.**  
  After rollback, verify VM power state, hostname/VMID match, Wazuh agent connectivity, time sync, AD health, expected snapshots, absence of known artifacts, and baseline alert count.

- **Evidence lifecycle.**  
  Decide whether Wazuh is part of the rollback set. If Wazuh is reset, alerts disappear. If Wazuh is preserved, scenarios accumulate historical noise. Both are valid, but the instructor workflow must make that explicit.

- **Version and content pinning.**  
  Pin Atomic repo commit, Invoke-Atomic version, Sysmon config release/commit, Suricata ruleset, PCAP hashes, Wazuh version assumptions, and custom rule ID bands.

- **A rule collision and manager-health gate.**  
  Before any class, validate `local_rules.xml`, restart/reload Wazuh in a controlled check, and assert manager health. A broken rules file can kill the whole lab.

- **Safety boundaries.**  
  Some scenarios involve credential dumping, web shells, reverse shells, and AD abuse. The proposal should define isolation guarantees, no-internet assumptions, allowed toolpaths, Defender exclusions, and post-reset secret hygiene.

## Verdict

The direction is mostly right: thin runner, no Caldera-first platform, start with Linux/Wazuh scenarios, snapshot-backed reset. But the proposal is still too tool-centric and not enough reliability-centric. In a teaching lab, “one click” only matters if the alert reliably appears and reset reliably restores a known-good state.

## Top 3 Changes Before Building

1. **Define a scenario contract and verification harness first.**  
   Each scenario needs declared prerequisites, affected VMs, expected alerts, Wazuh API verification, reset checks, and pass/fail output.

2. **Redesign snapshot scope.**  
   Separate targets from sensors/control-plane. Preserve Wazuh evidence during investigation, and provide a deliberate full-baseline reset when the instructor wants to clean history.

3. **Ship only two v1 scenarios.**  
   Build `ssh-bruteforce` and `web-sqli` end to end: run, verify alerts, student investigate, reset, verify clean. Do not add Atomic, GHOSTS, Windows, AD, YARA, or LLM integration until that loop survives repeated class-style runs.
