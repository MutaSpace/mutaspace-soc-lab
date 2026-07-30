# Scenario Authoring, Portability and Sharing — Design Proposal

**Status:** Proposal for approval — precedes any `/plan`
**Date:** 2026-07-30
**Supersedes nothing.** Extends the shipped scenario runner (`ansible/scenarios.yml`,
`ansible/playbooks/75-scenario-run.yml`, `task scenario:*`), which works and has three
scenarios passing live.

---

## 1. The requirement

Four capabilities, none of which the current design supports:

1. **Many more scenarios** than the three that exist.
2. **An authoring surface** so an instructor can design their own without writing Ansible.
3. **Portability** — export a scenario, import it on a *different* lab.
4. **Contribution** — submit a scenario upstream so every adopter gets it.

---

## 2. Why the current design blocks all four

A scenario today is **code, not data**. Each one is a hand-written play inside a shared
playbook:

```yaml
- name: Run the web-dir-bruteforce attack from kali-01
  hosts: kali-01
  tags: [web-dir-bruteforce]
  vars:
    scenario_web_target: "http://10.10.10.30"
    scenario_dirbrute_paths: [admin, login, wp-admin, ...]
```

That produces four hard blocks:

| Requirement | Why it fails today |
|---|---|
| More scenarios | Every one appends a play to one file. 3 scenarios already make it long; 50 makes it unmaintainable and merge-hostile. |
| Authoring | Requires editing Ansible in a shared playbook. Not something a UI can safely generate, and not something a teacher should have to learn. |
| Portability | There is no unit to move. "A scenario" is a tagged play plus catalogue entries in a second file — you would hand someone a diff. |
| Portability *even then* | `hosts: kali-01` and `http://10.10.10.30` are **this lab's** names. On another instructor's lab those do not exist, and the scenario fails silently — it runs, fires nothing, and the verify step reports missing alerts with no clue why. |

The catalogue half is already right. `scenarios.yml` declares `expected_alerts` with
`rule_id`, `match.data.srcip`, `match.agent.name` and a latency budget, and the runner
**asserts** them. That contract is the thing worth preserving and building on.

---

## 3. Design

### 3.1 Address by ROLE, not by hostname

The single change that makes portability possible.

```yaml
# today                          # proposed
origin: kali-01                  origin: { role: attacker }
target: ubuntu-app-01            target: { role: web-server }
scenario_web_target: "http://10.10.10.30"   # resolved at run time from lab.yaml
```

The runner resolves roles against `lab.yaml` at execution time. A lab whose attacker is
called `redteam-vm` at a different address runs the same scenario unmodified.

`lab.yaml` already carries a `role` per VM, so the mapping largely exists.

### 3.2 Attacks become declarative primitives

Most scenarios are "run this primitive, with these parameters, from here to there". A small
primitive set covers the catalogue:

| Primitive | Covers | Existing scenario it replaces |
|---|---|---|
| `http_requests` | path sweeps, SQLi strings, any URL list | `web-sqli`, `web-dir-bruteforce` |
| `auth_attempts` | SSH/RDP/SMB credential attacks | `ssh-bruteforce` |
| `atomic_red_team` | any ATT&CK technique in the Atomic Red Team library | the growth path — see §6 |
| `shell` | escape hatch, arbitrary command | complex one-offs |

The teacher then authors **data**, which is what makes both a UI editor and a portable file
possible. All three existing scenarios reduce to `http_requests` or `auth_attempts` plus
parameters.

### 3.3 One scenario = one self-contained bundle

```
scenarios/
  ssh-bruteforce/
    scenario.yml        manifest: metadata, requires, attack, expected_alerts,
                        answer_key, intel card, playbook reference
    assets/             optional: wordlists, payloads, pcaps
    VERIFIED.json       self-test result (see §5)
```

The runner **discovers** bundles instead of carrying a play per scenario, so
`75-scenario-run.yml` stops growing and becomes a generic executor.

### 3.4 `requires:` — fail loudly on the wrong lab

```yaml
requires:
  roles: [attacker, web-server]        # must exist in lab.yaml
  capabilities: [nginx-access-log-forwarded]
  wazuh_ruleset_min: "4.14.0"
```

A scenario needing a Windows endpoint must say so. Import and run both check `requires:`
first and refuse with a readable message, rather than firing an attack that produces no
alerts and looks like a broken detection pipeline mid-lesson.

This is the difference between "portable" and "portable *and* trustworthy".

---

## 4. ⚠️ Importing a scenario is importing code

**This is the security decision the feature cannot avoid.** The "share it with another
instructor" path means running someone else's content as root, on a lab that is
deliberately full of attack tooling, inside a school network.

Two bundle classes, distinguished by the schema:

| Class | Contains | Import behaviour |
|---|---|---|
| **Declarative** | manifest + parameters only; no `shell`, no raw tasks | Validate against the schema and import. Safe by construction. |
| **Code-bearing** | `shell` primitive or a raw `tasks:` file | **Explicit trust gate**: show the exact commands, require confirmation, record who accepted it. Never auto-import, never bulk-import. |

Upstream submissions get human review in the PR, so that path is covered. Peer-to-peer
sharing needs the distinction or this feature becomes a malware delivery channel aimed at a
security classroom — which is a genuinely bad thing to ship into a school.

**Recommendation: build the declarative class first and ship it alone.** The escape hatch
can wait until there is a scenario that actually needs it.

---

## 5. Verification is what makes a shared scenario trustworthy

The runner already asserts that declared alerts actually fired. That makes **"does this
scenario work?" machine-checkable** — which almost no scenario-sharing ecosystem can claim.

A bundle carries its own test result:

```json
{ "verified_at": "2026-07-30T19:44:27Z",
  "wazuh_version": "4.14.6",
  "observed": { "31101": 20, "31151": 1 },
  "lab_profile": "single-node-proxmox" }
```

- `task scenario:verify-bundle` re-runs it locally after import, so an instructor knows it
  works on *their* lab before relying on it in class.
- Upstream CI can require a passing `VERIFIED.json` before merge.
- A scenario whose rule IDs have drifted (Wazuh ruleset update) is detected by re-running,
  not by a student finding out.

---

## 6. Getting significantly more scenarios

Not by hand-writing fifty playbooks.

- **Wrap Atomic Red Team as a primitive.** ATT&CK-indexed, MIT, actively maintained, with
  per-technique cleanup, and already recommended by `docs/proposals/scenario-generation-vm.md`.
  Each technique becomes a scenario with a manifest, not bespoke Ansible.
- **Make the editor emit bundles**, so every scenario an instructor writes is automatically
  portable and submittable. The editor is a form over the schema — it is the *last* piece,
  not the first.

The schema and the bundle format are the real work. Everything else follows from them.

---

## 7. Migration path for the three working scenarios

**Non-negotiable: the three passing scenarios must keep passing at every step.** They are
the regression test for this whole change.

| Step | Change | How it is proven |
|---|---|---|
| **0** | Record today's baseline: run all three, capture observed rule IDs and counts. | The numbers already in `resume-here.md` (5710/5712; 31164×3/31106×2; 31101×20/31151×1) |
| **1** | Add the bundle schema + a generic executor **alongside** the existing tagged plays. Nothing is removed. | Existing `task scenario:run -- ssh-bruteforce` unchanged and still passing |
| **2** | Convert **one** scenario (`ssh-bruteforce`, the simplest) to a bundle. Both paths coexist. | Bundle run produces the *same* rule IDs as step 0 |
| **3** | Convert the other two. | Same-output check for each |
| **4** | Delete the per-scenario plays; `75-scenario-run.yml` becomes the generic executor + the shared verify contract. | All three pass via bundles only; the file no longer grows per scenario |
| **5** | Add `requires:` and role-addressing; verify against a second, deliberately different lab profile. | A scenario refuses to run when a required role is absent, with a readable message |

Step 4 is the only irreversible one and it is a deletion of code that is already proven
redundant by step 3.

---

## 8. Where the editor fits

Last. Once bundles are the unit and the schema is stable, the editor is a form that emits a
bundle and calls `scenario:verify-bundle`. Building it earlier means designing a UI against
a format that is still moving.

Sequence: **schema → generic executor → migrate the three → role addressing → Atomic Red Team
primitive → editor → sharing/import UX**.

---

## 9. Risks and open questions

1. **The generic executor must not become a worse Ansible.** If the primitive set keeps
   growing to accommodate one-off scenarios, stop and use the `shell` escape hatch instead.
   Four primitives that cover 90% is the goal; twenty is a failure.
2. **Role vocabulary is a contract.** `attacker`, `web-server`, `windows-endpoint`,
   `dc` — once shared bundles depend on these names they are hard to change. Define the
   initial set deliberately and version the schema.
3. **Rule IDs drift.** Wazuh ruleset updates can change which rule fires. `VERIFIED.json`
   detects it after the fact; nothing prevents it. Re-verification should be part of the
   upgrade runbook.
4. **Unanswered: how much of a scenario is the *narrative*?** A technically identical attack
   with a different pretext, intel card and playbook is arguably a different teaching
   scenario. Whether those are separate bundles or variants of one is a content question
   this design does not settle.
5. **Unanswered: per-student answer variation.** The assessment research recommends a
   `marker:` field so students cannot share answers. It fits the bundle contract, but costs
   one attack run per student. Prototype on one scenario before committing the catalogue.
