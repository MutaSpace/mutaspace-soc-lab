# Incident scenarios — running, verifying, resetting

An **incident scenario** is a repeatable attack the class investigates in the Wazuh dashboard,
plus the machine-checkable proof that the attack actually fired the expected Wazuh rule. Nothing
here is declared "working" on a hunch: every scenario proves itself against the live SIEM.

There are two scenarios today, both `kali-01 → ubuntu-app-01` across the firewall `fw-01`:

| id | ATT&CK | attack | fires (built-in rules) | budget |
|---|---|---|---|---|
| `ssh-bruteforce` | T1110 | failed-SSH burst (hydra/ssh) | `5710` + `5712` | ≤ 120 s |
| `web-sqli` | T1190 | SQL-injection request patterns (curl/sqlmap) | `31164` + `31106` | ≤ 120 s |

The catalogue lives in one file — [`ansible/scenarios.yml`](../../ansible/scenarios.yml) — which is
the single source of truth for what each scenario does *and* what proves it. `list`, `run` and
`verify` all read it, so behaviour and pass/fail contract cannot drift apart.

---

## The teaching loop

```
task scenario:list                       # the catalogue: id, attacker→target, rule, budget
task scenario:run    -- ssh-bruteforce   # run the attack, then prove the alert landed
task scenario:verify -- ssh-bruteforce   # (re)prove the alert is in the indexer, no attack
                                          # → students investigate in the Wazuh dashboard
task scenario:reset  -- ssh-bruteforce   # roll the targets back; the alert survives for grading
```

`scenario:run` runs Ansible (it drives the attacker and queries the SIEM), so run it **from the
jumpbox control node**, where the repo, Ansible and the lab routing live:

```
ssh -J <proxmox-host> labadmin@10.10.10.5 -i ~/.ssh/id_ed25519_mutaspace_lab
cd ~/mutaspace-soc-lab/ansible
```

`scenario:snapshot` and `scenario:reset` instead run `qm` **on the Proxmox host** over SSH (set
`LAB_HOST_SSH=root@<host>` first, exactly like the `learner:*` tasks).

---

## Before your first run — two prerequisites

**1. Power kali-01 on.** The attacker (VMID 108) ships `started: false`, so start it once per host
boot before running any scenario:

```
ssh <proxmox-host> 'qm start 108'      # or: qm status 108  → running
```

`scenario:run` will also (re)confirm kali-01 carries the attack tooling (hydra, sqlmap); the tools
themselves are baked into the scenario baseline.

**2. Export the Wazuh indexer password.** `verify` queries the indexer's `_search` API and needs the
admin credential the installer generated. It is **not** read from a file automatically — export it:

```
# on the jumpbox, from ansible/
export MUTASPACE_WAZUH_INDEXER_PASSWORD=$(awk '/Admin user for the web/{f=1} \
  f&&/indexer_password:/{print $2; exit}' .secrets/wazuh-passwords.txt | tr -d "\047\042")
```

> **Gotcha — strip the quotes.** The values in `.secrets/wazuh-passwords.txt` are **single-quoted**
> (`indexer_password: '…'`). If you copy the password *with* the surrounding quotes, the indexer
> answers `401 Unauthorized` and `verify` fails with "returned 0 within 120s". The `tr -d "\047\042"`
> above removes the quotes. The indexer **user** defaults to `admin` (override with
> `MUTASPACE_WAZUH_INDEXER_USER`); the admin/first block in the passwords file is the one to use.

---

## The evidence-retention model — why reset spares the SIEM

This is the design decision that makes the lab gradable. When you reset for the next student:

- **The targets roll back.** `ubuntu-app-01` (106) and `kali-01` (108) are rolled back to the
  `scenario-baseline` snapshot. The attack-window artifacts on their disks — `auth.log` and
  `/var/log/nginx/access.log` lines on the target, tool history on the attacker — **go away with the
  disk.** On-disk the targets are back to a clean, instrumented baseline as if no attack had run.
- **The SIEM is preserved.** `wazuh-01` (104) is **never** touched by `reset` — not stopped, not
  rolled back. The alerts the student's attack fired stay in the indexer for grading. `dc-01`,
  `fw-01` and the jumpbox are likewise outside the reset set.

That split — *clean target, preserved SIEM* — is the whole point, and it is enforced structurally:
`scenario-reset.sh` and `scenario-snapshot.sh` carry a **fixed two-VM target set `{106, 108}`** with a
**name guard** (106 must be `ubuntu-app-01`, 108 must be `kali-01`) and no flag that can widen it. A
mis-numbered edit refuses to act rather than risk rolling back the SIEM.

Prove retention yourself: after a `reset`, run `scenario:verify -- <id>` — a **PASS on a clean target**
is the retention guarantee in action (the alert is still in the indexer though the disk was wiped).

### The deliberate "full reset" (manual, not automated)

The automated path never clears the SIEM — that is deliberate. Two manual operations exist for a real
clean slate between cohorts; neither is wired into `task`, do them knowingly:

- **Re-take the baseline (targets only)** after changing instrumentation:
  `sudo ./scripts/scenario-snapshot.sh --replace`. Moves `scenario-baseline` on 106 & 108; touches no
  alert.
- **Clear alert history (evidence-destroying, wazuh-01 only)** — the *only* way old alerts leave the
  indexer, intentionally not a script:
  `curl -k -u <admin> -XDELETE 'https://127.0.0.1:9200/wazuh-alerts-*'` on wazuh-01. There is no undo;
  confirm the retention window with the instructor first.

---

## The one-time firewall rule

`fw-01` isolates the attack plane (`opt1`/vmbr2) from the SOC LAN (`lan`/vmbr1) by default. Two
**standing** `pass` rules are the sole exception: they let `kali-01` (10.10.20.10) reach
`ubuntu-app-01` (10.10.10.30) on tcp/22 and tcp/80 so the two scenarios can cross the firewall.

- They live **live on fw-01** (applied once during setup) **and** in the template at
  [`packer/opnsense-267/config/config.xml.pkrtpl.hcl`](../../packer/opnsense-267/config/config.xml.pkrtpl.hcl)
  (search `scenario:`), so a rebuilt gateway stays consistent with the running one.
- They **must sit before** the `block opt1→lan` rule or the block eats them and no scenario traffic
  reaches the target. Nothing else on `opt1→lan` is opened; there is **no per-scenario firewall
  mutation** — one standing rule set serves every run.

---

## The one-time baseline snapshot

`scenario-baseline` is a single, **disk-only** snapshot on 106 & 108, taken **once, deliberately,
AFTER** the instrumentation is proven (nginx access-log localfile present, kali tooling installed,
both scenarios verifying). `scenario:run` never auto-snapshots.

```
task scenario:snapshot          # stops 106 & 108, snapshots each disk-only, leaves them stopped
                                # wazuh-01 (104) is never in the set
```

It is disk-only (no `--vmstate`) on purpose: a reset must mean "cold-boot a known-good disk", not
"resume a process from last week". `reset` then starts the VMs and repairs them. Exactly **one**
snapshot per target is kept (use `--replace` to move it) — this sidesteps the unverified question of
whether rolling back a non-latest snapshot on LVM-thin destroys newer ones.

For a pristine baseline, truncate the target's `auth.log` and `/var/log/nginx/access.log` before
snapshotting so students don't start each exercise seeing prior attack lines.

---

## What `reset` repairs and checks

A rollback is a time machine, so `reset` starts each target and then, best-effort:

- forces a **clock resync** (`timedatectl set-ntp true; chronyc makestep`) — a stale clock breaks
  Wazuh correlation and any Kerberos-adjacent auth;
- **restarts the Wazuh agent** — a same-named agent can be blocked from re-registering after a revert;
- **proves the reset landed clean**: VM running, name-guard still matches, agent keyed + service active
  (**target only**), guest clock NTP-synchronised.

> The **attacker (kali-01) runs no Wazuh agent by design** — it is not a monitored endpoint — so
> `reset` skips the agent checks on it. That "agent checks skipped" line is expected, not a fault.

---

## The scenario contract (adding a scenario)

Adding a scenario is meant to be **a list entry in `scenarios.yml` and nothing else** — the verify
harness is generic and loops over `expected_alerts`. Keep the shape:

```yaml
  - id: my-scenario
    title: "..."
    attack: T1234                 # ATT&CK technique id (documentation)
    origin: kali-01               # attacker
    target: ubuntu-app-01         # monitored target
    objective: >- ...             # what the class investigates
    prereqs: >- ...               # tooling / firewall / instrumentation assumed
    reset_targets: [106, 108]     # informational; the reset set is fixed in the scripts
    expected_alerts:
      - rule_id: 5712             # the built-in rule that ACTUALLY fires (confirm on host)
        match:                    # raw indexer field paths → the bool query verify builds
          data.srcip: "10.10.20.10"
          agent.name: "ubuntu-app-01"
        min_count: 1
        latency_budget_seconds: 120
```

Each `expected_alerts` item is the claim: *within `latency_budget_seconds` of the attack, the indexer
holds ≥ `min_count` alerts whose `rule.id` is `rule_id` and whose fields satisfy every key in `match`.*
`match` keys are raw dotted indexer field paths, so what you read is exactly what is asked of the
indexer — no translation layer.

**Confirm rule ids on the host, don't guess.** The proposal's guessed web-attack id was `31103`; the
Wazuh 4.14 ruleset actually fires `31164`. Run the attack, read which rule fired (dashboard or the
indexer), and pin the observed id — this repo does not assert a result it did not observe.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `verify` fails, `401 Unauthorized` from `:9200` | Password copied with its single quotes. Strip them (`tr -d "\047\042"`), see the credential section. |
| `verify` "returned 0 within 120s" but attack ran | Agent not connected, wrong `rule.id`, or the nginx access-log localfile missing (web-sqli). Check `agent_control -l` on wazuh-01 and `ossec.conf` on 106. |
| `run` fails, kali-01 unreachable | kali-01 (108) not powered on — `qm start 108`. |
| `reset` warns "agent … could NOT be confirmed on 108" | Expected on older builds: kali is not monitored. Current `reset` skips agent checks on the attacker. |
| `snapshot` refuses: "already has a snapshot" | The baseline exists. Use `--replace` to move it deliberately. |

## See also

- [`ansible/scenarios.yml`](../../ansible/scenarios.yml) — the catalogue and the verify contract
- [`ansible/playbooks/75-scenario-run.yml`](../../ansible/playbooks/75-scenario-run.yml) — the generic runner + verify
- [`scripts/scenario-snapshot.sh`](../../scripts/scenario-snapshot.sh) / [`scripts/scenario-reset.sh`](../../scripts/scenario-reset.sh) — the snapshot/reset pair
