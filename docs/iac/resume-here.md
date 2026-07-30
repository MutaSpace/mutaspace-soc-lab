# Resume Here

Scratch handoff for picking the work back up. docs/iac/session-handoff.md is the durable
overview; getting-started.md is the operator walkthrough.

**Last updated: 2026-07-24 — the lab is DEPLOYED. jumpbox-01 is the Ansible control node.
Scenario-runner MVP live-proven; fw-01 is now zero-touch Infrastructure-as-Code (opnsense-as-code,
see below); nlp-01 Ollama is up. **opnsense-as-code W4+W5 COMPLETE** (2026-07-24): EVE→Wazuh pipeline
proven end-to-end, 05-fw-config idempotent, all `fw:*` Taskfile verbs shipped. 60-endpoints (Linux)
and 90-lab-seed verified already-applied.

**2026-07-24 (later) — distribution-readiness pass.** The leaked shared password is ROTATED (it was
public in git history) and `scripts/rotate-lab-credentials.sh` now exists; pre-commit is installed so
the scanner actually runs; `var.pve_node` + a plan-time node check make the repo work on another
instructor's host; the stale "21-add/21-destroy" tofu warning was false and the real drift is now
APPLIED (`plan` returns no changes); getting-started.md gained the three steps a fresh instructor
cannot skip. **Win11 template (9003) is BUILT and win-client-01 is DEPLOYED, domain-joined and
monitored (2026-07-29)** — see the Win11 section for the build recipe and the win-client-01 section
for what a fresh clone still needs by hand.**

---

## opnsense-as-code — fw-01 is now zero-touch IaC (2026-07-24)

fw-01 (OPNsense) was rebuilt from scratch so its config.xml seed BAKES a root SSH key + an API
key/secret — a from-scratch deploy now comes up API/SSH-ready with **zero manual firewall steps**.
Plan + full state: `.planning/opnsense-as-code/plan.md`; design: `docs/proposals/opnsense-as-code.md`.

- **Reach fw-01 now (no more sshpass):** `ssh -J swc2026 -i ~/.ssh/id_ed25519_mutaspace_lab
  -o StrictHostKeyChecking=no root@10.10.10.1 '<cmd>'` (root shell is **csh** — no bash redirects;
  pipe bash syntax to `sh -c`). API creds `FW_API_KEY`/`FW_API_SECRET` in `.envrc`:
  `curl -sk -u "$FW_API_KEY:$FW_API_SECRET" https://10.10.10.1/api/...` (verified 200). Root console
  pw is in `.secrets/rotated-credential.txt` / your password manager (also
  `PKR_VAR_root_password`+`_hash` in `.envrc`; fw-preflight crypt-checks the pair). **Rotated
  2026-07-24** — the previous shared value leaked into this file, was rotated, and has since been
  **PURGED FROM GIT HISTORY** (`git filter-repo --replace-text`, force-pushed 2026-07-25). It now
  reads `***REMOVED-ROTATED-CREDENTIAL***` in the three commits that carried it. See
  `scripts/rotate-lab-credentials.sh`.

  ⚠️ **Every commit SHA on this branch changed.** If you had a clone from before 2026-07-25 it has
  diverged permanently and `git pull` will not reconcile it — re-clone, or
  `git fetch && git reset --hard origin/feat/infrastructure-as-code` and lose local commits. The
  old tip was `eec8ffe`; the rewritten tip is `16a78cf`. Commit count is unchanged at 98, and a
  pre-rewrite backup bundle of every ref was taken before the operation.
- **✅ RESOLVED 2026-07-24 — a bare `tofu apply` is safe again. `-target` is no longer needed.**
  This entry used to carry a CRITICAL warning that a bare apply wanted 21-add/21-destroy and would
  recreate the whole lab, so every apply had to be `-target`ed at
  `module.vm["fw-01"].proxmox_virtual_environment_vm.this`. **That was stale.** The real pending diff
  was `0 to add, 6 to change, 0 to destroy` — nothing destructive — and it has now been applied.
  `tofu plan -detailed-exitcode` returns **0 (no changes)**; state matches configuration.
  - What the 6 changes actually were: `started: true -> false` on the research plane (`kali-01`,
    `untrusted-01`, `nlp-01` and the three `kali-l0*` clones — `lab.yaml` declares them off by
    default, and they had been started by hand), plus the committed isolated-plane DNS change
    (`10.10.20.1` → `1.1.1.1`, the OPNsense Unbound-in-chroot workaround), plus read-only computed
    drift on `ipv4_addresses`/`ipv6_addresses`/`network_interface_names`.
  - **The research plane is now STOPPED**, which is its declared state. `qm start 108` (and 109/110)
    before running a scenario that needs an attacker or Ollama.
  - Verified after the apply: fw-01, jumpbox-01, dc-01, analyst-01, wazuh-01 and ubuntu-app-01 all
    still running, and `agent_control -l` still shows ubuntu-app-01, analyst-01 and dc-01 **Active**.
    The SIEM was not disturbed.
  - Still true and worth keeping: **`plan` first and read the replace set** before any apply. VM-level
    rollback is `qmrestore /var/lib/vz/dump/vzdump-qemu-100-*.vma.zst 100 --force`.
  - Lesson worth keeping: a warning like the one this replaced is itself a hazard once it goes stale.
    It taught "always use `-target`", which suppresses exactly the whole-config plan that would have
    shown the drift was harmless.
- **W4 EVE→Wazuh pipeline is PROVEN END-TO-END live (2026-07-24).** `curl testmynids` from
  ubuntu-app-01 across fw-01 → Suricata **sid 2100498** ("GPL ATTACK_RESPONSE id check returned
  root") → EVE-over-syslog → wazuh-01:514 → **Wazuh rule 86601** (`ids,suricata`, level 3) in
  alerts.json. Every hop was walked and captured on the wire. The non-obvious blockers found &
  fixed:
  - **Wazuh ships Suricata *rules* (86xxx) but NO decoder for the SYSLOG path.** The built-in `json`
    decoder only matches logs starting with `{`; the syslog frame `suricata[pid]: {json}` defeats it
    → `wazuh-logtest` said "No decoder matched" and the pipeline was silent. **Fix, now codified:**
    `ansible/files/wazuh-decoders/suricata-eve.xml` — a `<decoder name="json">` scoped by
    `program_name suricata` running `JSON_Decoder`, named `json` so `decoded_as json` fires rule
    86600→86601. Deployed by 70-detections.yml (API upload, beside the rules) + placed live already;
    local_decoder.xml hand-edit was reverted, box now matches code.
  - **`syslog_eve=1` in config.xml is inert until an IDS reconfigure** regenerates suricata.yaml with
    the second `eve-log` block (`type: syslog`, identity suricata, facility local5). ids_general
    carries RELOAD_MOD_ARG so the module handles this; I triggered it by hand this session.
  - **The download endpoint is `updateRules`, NOT `reloadRules`** (reloadRules only recompiles). Draft
    fixed. `emerging-attack_response.rules` is the ruleset (enabled + on disk, 1627 rules).
  - Resolved read-only: the `oxlorg.opnsense.all` action group **does** exist (module_defaults is
    valid); `syslog_output` is the right param (== the syslog_eve toggle).
  - fw-01 syslog **destination** (program suricata → 10.10.10.20:514/udp4) and the Wazuh `<remote>`
    listener are both LIVE. syslog-ng forwards fine (ping/tcpdump confirmed; my early `-i any -c`
    captures were racy — trust a foreground `-i eth0` capture).
  - **05-fw-config.yml now RUNS idempotently (2026-07-24):** re-run is `ok=6 changed=1 failed=0` (the
    1 is the always-changed updateRules download). Four oxlorg.opnsense 26.1.11 bugs fixed doing it:
    (1) needs **`python3-httpx`** on the jumpbox (now in bootstrap-jumpbox.sh); (2) ids_general wants
    `mode: pcap` + `local_networks`, not `ips`/`homenet`; (3) ids_ruleset matches by DESCRIPTION
    ("ET open/emerging-attack_response"), not filename; (4) syslog task needs `description` +
    `match_fields` or it duplicates the dest. Live box reconciled to code (hand-made TEMP egress rule
    deleted; only codified `mutaspace-research-plane-egress` remains, disabled). Pipeline re-verified
    (86601) after the run. Design note: seed allows `opt1→internet` for the whole research plane —
    decide if untrusted-01 should be air-gapped too.
  - **ansible→nlp `-b`/sudo hang RESOLVED (2026-07-24):** it was stale ControlPersist SSH sockets
    from the fw-01 rebuild, not sudo. `80-ai-assist.yml` now runs codified end-to-end (ok=11,
    changed=3, failed=0, ~3.6s). If it recurs after a future fw-01 rebuild: `rm -f ~/.ansible/cp/*`
    on the jumpbox (or wait 60s for ControlPersist to age out). **Ollama models present on nlp-01.**
  - **fw-01 SSH host key changed** after the W2 rebuild — clear the stale known_hosts line
    (`ssh-keygen -R 10.10.10.1`) or use `-o UserKnownHostsFile=/dev/null`.

---

## Scenario-runner — LIVE STATE (2026-07-24)

The incident runner is **built and proven on the live host — THREE scenarios, all passing**. Full instructor guide:
[docs/scenarios/README.md](../scenarios/README.md). Non-obvious live facts the next operator inherits:

- **ALL THREE scenarios verify end-to-end — re-confirmed live 2026-07-30** (run from the
  jumpbox, `ansible/`). Attack path for every one: kali-01 (10.10.20.10, vmbr2) →
  ubuntu-app-01 (10.10.10.30, vmbr1) **across fw-01**.

  | scenario | attack | verify | observed |
  |---|---|---|---|
  | `ssh-bruteforce` | `ok=6 changed=3` | `ok=6 failed=0` | 5710, **5712** |
  | `web-sqli` | `ok=4 changed=1` | `ok=6 failed=0` | **31164** ×3, 31106 ×2 |
  | `web-dir-bruteforce` | `ok=4 changed=1` | `ok=6 failed=0` | **31101** ×20, **31151** ×1 |

  31164 is the real rule, *not* the proposal's guessed 31103. `web-dir-bruteforce` was
  described here as unproven until 2026-07-30 — it is not, and the catalogue entry had
  said so since 2026-07-24. It needs the agent forwarding `/var/log/nginx/access.log`
  (from `60-endpoints`); without that localfile 31101/31151 cannot fire at all.

  A green run is a live end-to-end check of far more than the attack: traffic crosses two
  segments through fw-01, the endpoint agent produces the telemetry, and the verify play
  then ASSERTS each expected `rule.id` landed in the indexer inside its latency budget.
  A scenario that fires but detects nothing fails the play.
- **`scenario-baseline` snapshot EXISTS** on VMIDs **106 (ubuntu-app-01) and 108 (kali-01)** —
  disk-only, taken 2026-07-24 after instrumentation was proven and the targets' logs truncated.
  wazuh-01 (104) has **no** such snapshot and is never touched by reset (verified: uptime unbroken
  through two full reset cycles). Re-take with `sudo ./scripts/scenario-snapshot.sh --replace`.
- **The standing fw-01 allow rules are LIVE** (kali-01→ubuntu-app-01 tcp/22 and tcp/80), sitting
  before the `block opt1→lan` rule. They are reconciled into the template at
  `packer/opnsense-267/config/config.xml.pkrtpl.hcl` (search `scenario:`). No per-scenario firewall
  mutation — this one rule set serves every run.
- **`verify` credential gotcha:** export `MUTASPACE_WAZUH_INDEXER_PASSWORD` from
  `ansible/.secrets/wazuh-passwords.txt`, but the value is **single-quoted** — strip the quotes or
  the indexer 401s. One-liner:
  `export MUTASPACE_WAZUH_INDEXER_PASSWORD=$(awk '/Admin user for the web/{f=1} f&&/indexer_password:/{print $2;exit}' .secrets/wazuh-passwords.txt | tr -d "\047\042")`.
- **kali-01 (108) ships `started: false`** — `qm start 108` once per host boot before running.
- kali-01 runs **no** Wazuh agent by design (it is the attacker, not a monitored endpoint); the
  reset script now skips agent checks on it rather than warning.

---

## One-paragraph state

Five core VMs are cloned from templates and running. dc-01 is a promoted domain controller
(`mutaspace.local`), DNS (forward + reverse) resolves, and the Wazuh SIEM finished installing on
wazuh-01. Ansible currently runs **from the Proxmox host** (manual state — see
below); a `jumpbox-01` VM was just added to lab.yaml to replace that but is **not applied yet**.
Win11 (9003) is the one unbuilt template, now well-diagnosed. Everything is committed and
pushed except nothing — the tree is clean at the jumpbox commit.

---

## The host and how to reach things

- **Proxmox host:** `swc2026` at `<LAB_MANAGEMENT_IP>`. SSH alias in `~/.ssh/config`, reached over
  WireGuard from this workstation. Key: `~/.ssh/id_ed25519_proxmox`.
- **The host was given management IPs on the lab bridges** (`10.10.10.2` on vmbr1, `10.10.20.2`
  on vmbr2, persisted via post-up in /etc/network/interfaces) so it can reach the lab VMs. This
  is a stopgap the jumpbox replaces.
- **Ansible runs from the host** right now: `/root/ansible/` (rsynced from this repo), collections
  installed, `python3-winrm` installed, secrets at `/root/ansible/.secrets/env` (mode 600).
- Load the lab creds before any ansible command: `set -a; . /root/ansible/.secrets/env; set +a`
  then `cd /root/ansible`.

### Credentials (in /root/ansible/.secrets/env on the host)
- `MUTASPACE_WIN_ADMIN_PASSWORD` = the rotated shared credential (also the domain admin
  password, because promotion converts the local account into the domain account). Never write
  the value here — it lives in the jumpbox `.secrets/env` and your password manager.
- `MUTASPACE_SAFE_MODE_PASSWORD`, `MUTASPACE_LAB_USER_PASSWORD` = generated, in the file
- `MUTASPACE_LINUX_USER` = `labadmin`, `MUTASPACE_LINUX_SSH_KEY` = `/root/.ssh/lab_key`
  (a copy of `~/.ssh/id_ed25519_mutaspace_lab`)
- `ANSIBLE_HOST_KEY_CHECKING=False` (lab VMs are resettable; keys change)

---

## VM state (verify: `ssh swc2026 'qm list'`)

| VMID | VM | State | Configured |
|---|---|---|---|
| 100 | fw-01 | running | OPNsense gateway; config seed applied; routes + NATs; serves DHCP |
| 102 | dc-01 | running | **Promoted DC** `mutaspace.local`; DNS forward+reverse; admin pw reset (see gaps) |
| 103 | analyst-01 | running | Ubuntu Desktop; DHCP reservation .50 |
| 104 | wazuh-01 | running | **Wazuh healthy** (reinstalled 2026-07-23; disk grown 18→58G; 3 agents Active) |
| 106 | ubuntu-app-01 | running | bare clone; nginx/ssh pending (60-endpoints) |
| 108/109/110 | kali-01 / untrusted-01 / nlp-01 | **created, started:false** | need `qm start` before configuring |
| 206/216/226 | kali learners | created, started:false | learner plane |
| 101 | **jumpbox-01** | **NOT created** | in lab.yaml, not applied |
| 105 | win-client-01 | **disabled** | template 9003 not built |

---

## Ansible playbook progress (in /root/ansible/playbooks/, run from the host)

| Playbook | Status |
|---|---|
| 10-dc-promote | **done** (finished manually — see the reboot gap below) |
| 20-dns-records | **done** (A + reverse zone + PTR resolve) |
| 40-wazuh-server | **done (reinstalled 2026-07-23)** — healthy: manager+indexer+dashboard active, API :55000, dashboard :443. Hardened with preflight + diagnostics. |
| 50-wazuh-agents | **done for powered-on hosts** — agents Active: ubuntu-app-01, analyst-01, dc-01 (+ wazuh-01 local). Off hosts (kali/untrusted/nlp) + unbuilt win-client-01 not enrolled → the playbook's final assert fails on those; re-run when they're up. |
| 60-endpoints | **Linux half done** (verified 2026-07-24: nginx 1.24 + openssh + landing page + wazuh nginx-localfile block on ubuntu-app-01; `--check --limit ubuntu-app-01` = ok=7 changed=0). Windows half (Sysmon + 4625 auditing on win-client-01) **blocked** — VM 105/template 9003 not built. Run scoped: `--limit ubuntu-app-01` (unscoped noisily fails on the unreachable win-client). |
| 70-detections | **done — recorded run 2026-07-24.** `MUTASPACE_WAZUH_API_USER`/`_PASSWORD` are now in the jumpbox `.secrets/env` (parsed from the `api_username`/`api_password` pair in `.secrets/wazuh-passwords.txt` — values are single-quoted there, strip the quotes). A full `ansible-playbook playbooks/70-detections.yml` run is `ok=15 changed=4 failed=0 skipped=1`. Verified: all four custom rules (100010/100011/100020/100021) present in the manager's `local_rules.xml`, the Suricata decoder uploaded, and **4 agents still Active afterwards**. ⚠️ **It reloads, it does not restart** — `systemctl show wazuh-manager -p ActiveEnterTimestamp` is byte-identical before and after (`Fri 2026-07-24 20:22:29 UTC`), which is the whole point: a manager restart drops every agent connection and re-queues events mid-class. The `changed=4` on a repeat run is **expected and not a bug**: the four are "stage the rules file", "stage the decoder", "reload analysisd" and "remove the staged copies" — transient temp-file scaffolding and a command, none of them state divergence. Every task that asserts *real* state (rules loaded, decoder present, `<remote>` listener in ossec.conf) reports `ok`. If you want the recap to read cleanly you could add `changed_when: false` to the stage/remove tasks, but that was deliberately NOT done: the play is verified working and the cosmetic gain is not worth touching it. |
| 80-ai-assist | **done (ran clean 2026-07-24: ok=11, changed=3, failed=0)** — Ollama + models present on nlp-01, bound to 127.0.0.1. The `ai/` Python tooling (detection copilot, lab assistant) drives it |
| 90-lab-seed | **done** (verified 2026-07-24: test.user + lab.user02 both exist + enabled in `OU=Lab Users,OU=MutaSpace Lab`; a real re-run is changed=0, `update_password: on_create` won't reset them). ⚠️ NOT check-mode-clean: `--check` fails at the assert because `win_powershell` doesn't execute in check mode — gate on a REAL run, not `--check`. |

Run pattern (now from the **jumpbox**, not the host):
`ssh -J swc2026 labadmin@10.10.10.5 -i ~/.ssh/id_ed25519_mutaspace_lab` then
`cd ~/mutaspace-soc-lab/ansible; set -a; . .secrets/env; set +a; ansible-playbook -i inventory/hosts.yml playbooks/<pb>`

### ✅ WAZUH-01 rebuilt + the root cause fixed lab-wide (2026-07-23)

The "zombie" (`/var/ossec` gone, daemons running from deleted inodes) turned out to be a symptom of
a **disk that filled during install**: the Wazuh all-in-one installer got partway, hit
`No space left on device` unpacking the dashboard, and its OWN failure-cleanup purged the packages
and `/var/ossec` — leaving the earlier zombie. Root cause: **wazuh-01's root FS was 18 GB on a 60 GB
disk.** Every Ubuntu template freezes its root partition at BUILD size; clones onto bigger disks
never grow because cloud-init's growpart does not handle LVM.

What was done:
- Purged the broken partial install, **grew wazuh-01 root 18 GB → 58 GB** (growpart→pvresize→lvextend→resize2fs),
  re-ran the hardened `40-wazuh-server` — clean. Then `50-wazuh-agents`: ubuntu-app-01, analyst-01,
  dc-01 enrolled and **Active**.
- **Fixed the root cause in IaC** so it can't recur: `tofu/templates/user-data-linux.tftpl` now
  self-grows root to fill the disk on first boot (all future clones); `00-preflight.yml` gained a
  non-fatal per-host "root FS vs disk" check; `40-wazuh-server.yml` raised its disk floor 5→10 GB and
  now points a disk-full failure at the grow fix.
- **Remediated every already-cloned running VM** (cloud-init only helps fresh clones): jumpbox 18→28,
  analyst-01 28→38, ubuntu-app-01 18→38, wazuh-01 →58. **Still undersized (grow on next boot):** the
  off VMs kali-01/untrusted-01/nlp-01. Windows dc-01 (60 GB) and OPNsense fw-01 use different disk
  layouts — not covered by the Ubuntu grow; check separately if they ever run short.
- Earlier repo bug also fixed: `ansible.cfg` used the removed `community.general.yaml` callback → now
  `default` + `result_format = yaml`.

---

## jumpbox-01 — BUILT AND PROVISIONED (2026-07-23)

The control node is live. Done this session:
1. **`tofu -chdir=tofu apply`** — created jumpbox-01 (VMID 101, 10.10.10.5). Running; guest agent
   reports the IP; cloud-init `status: done`. The other 11 VMs were `No changes`.
2. **`scripts/bootstrap-jumpbox.sh`** written (mirrors `bootstrap-host.sh`'s style) — a
   *workstation-run* provisioner: `ssh -J swc2026`, apt-installs ansible + python3-winrm + git +
   rsync, rsyncs `ansible/` and `ai/` (with the .gitignore exclusions), stages the lab SSH key
   (`~/.ssh/mutaspace_lab_ed25519`, 600) and credentials (`ansible/.secrets/env`, 600, with
   `MUTASPACE_LINUX_SSH_KEY` pinned to the jumpbox path), installs the pinned collections, verifies.
   Idempotent; `--dry-run` / `--skip-*` flags.
3. **Ran it — succeeded.** ansible-core 2.16.3 + pywinrm on the jumpbox; collections microsoft.ad
   1.12.0, ansible.windows 3.7.0, community.proxmox 2.0.0, community.general 13.2.0 in the project
   `collections/`. Verify passed; `ansible linux -m ping` → analyst-01/ubuntu-app-01/wazuh-01 pong
   (the vmbr2 isolated hosts time out only because they are `started:false`).
   - The workstation cred file is `ansible/lab-credentials.env` (gitignored), copied verbatim from
     the host's `/root/ansible/.secrets/env`. It is **missing `MUTASPACE_WAZUH_API_*`** — add those
     from the host's `.secrets/wazuh-passwords.txt` before running 70-detections.

**Reach the jumpbox:** `ssh -J swc2026 labadmin@10.10.10.5 -i ~/.ssh/id_ed25519_mutaspace_lab`
then `cd ~/mutaspace-soc-lab/ansible; set -a; . .secrets/env; set +a`.

### THE NEXT STEP: run the config playbooks FROM the jumpbox
- 50-wazuh-agents (Linux hosts are up; enroll them). Then 60/70/80/90 in order — note 80-ai-assist
  needs nlp-01 started, and several plays need the `started:false` VMs powered on first.
- After the jumpbox is doing the runs, retire the host's stopgap vmbr1/vmbr2 mgmt IPs and the
  `/root/ansible/` tree on the host.
- **Not committed yet:** `scripts/bootstrap-jumpbox.sh` is untracked; `f28848e` is still unpushed.

---

## Design gaps found this session (each needs a code fix for reproducibility)

1. **Windows admin password is non-deterministic after sysprep.** The Windows cloud-init snippet
   (`tofu/templates/user-data-windows.tftpl`) deliberately sets no password, and dc-01 uses
   `cicustom` so there is no `cipassword` — Cloudbase-Init leaves it random. Ansible could not
   auth; fixed manually via `qm guest exec 102 -- net.exe user Administrator '<password>'`
   (or, properly, `scripts/rotate-lab-credentials.sh`).
   **Fix:** have the snippet set a known password from a variable.
2. **dc-promote reboot.** `microsoft.ad.domain` completed the forest but exited code 4 (reboot
   required) and the module's post-reboot re-auth failed (local admin → domain admin). `reboot:
   true` is already set. Rebooted manually. **Fix:** tune the post-promotion reconnect, and note
   the reverse-zone task lives after promotion in 10-dc-promote (it never ran because of this,
   which is why 20-dns needed the zone created by hand).
3. **Provider SSH needs a PAM user** — used root (`PROXMOX_VE_SSH_USERNAME=root`, key in agent).
   bootstrap-host.sh should create a `terraform` PAM user with narrow sudo.
4. **Three provision privileges** found on first apply — `Sys.Modify`, `Realm.AllocateUser`,
   `User.Modify` — already added to bootstrap-host.sh (provision role at 31 privs).
5. **Disk floors:** a clone cannot shrink below its template base. dc-01 50→60, Win11 60/50→64.

---

## Win11 (9003) — ✅ BUILT (2026-07-29, build 22). Here is what actually worked

Updated 2026-07-28 (second pass). This went from "boots and loops forever" to a full install that
completes OOBE, connects WinRM and runs every provisioner. The last hang — sysprep — was finally
read off the disk rather than guessed at: a malformed `/unattend:` argument, bug 7 below. Every fix
is committed. **Nobody has yet watched a build reach `qm template`.** Do not mark 9003 done until
you have seen a `template: 1` line in `/etc/pve/qemu-server/9003.conf`.

### FIXED — 1. The boot prompt (`scripts/remaster-windows-iso.sh`)

`Press any key to boot from CD or DVD` timed out unanswered, the firmware fell through to an empty
disk, and Packer waited out its 2 h timeout. Keystroke-spraying could not win the race (vTPM makes
POST vary 45→120 s; spacebar is the OVMF menu hotkey, not "any key"; `sendkey` drops keys).
Remastering the ISO with `efi/microsoft/boot/efisys_noprompt.bin` deletes the race instead.
`boot_command` is now `[]`. Two tool facts: **xorriso cannot do this** (needs UDF for the ~7 GB
`install.wim`; it has none), and genisoimage has **no `-eltorito-platform`** (its `-e` *is*
`-efi-boot`).

### FIXED — 2. A double hyphen in an XML comment made `Autounattend.xml` malformed ★ the real blocker

The file contained, inside a COMMENT, a command line with an unspaced `--` before "variant". That is
illegal in an XML comment, so the whole answer file was invalid. **Setup does not report this** — it
parses, fails, and silently resets. Symptom: boots WinPE, draws the Setup background with no UI,
writes nothing, reboots, loops forever. Looks exactly like a driver or firmware fault.

Found by bisection: the same ISO on the same firmware **with no answer file** gave a perfect stable
interactive Setup, leaving the answer file as the only variable. A warning now sits at the top of
that file, because the next person to paste a command line into a comment will reintroduce it.

Four hypotheses were eliminated and should not be re-tested:
- **WIM index** — index 6 really is Windows 11 Pro (`wiminfo`)
- **vTPM** — a build with `tpm_config` removed loops IDENTICALLY, refuting the old note's theory
- **the remastered ISO** — `install.wim` sha256 matches the original across all 7.06 GB
- **WinPE drivers** — WinPE boots fine on 0.1.285

### FIXED — 3. No product key for consumer multi-edition media

With valid XML, Setup consumed the answer file and stopped at its interactive **Product key** page.
`product_key` defaulted to empty and the docs covered only evaluation media and Volume Licensing.
The third case is the one in use: consumer multi-edition media carries 11 editions and
`/IMAGE/INDEX` alone does **not** suppress that page. Set the published generic Pro key (selects the
edition, does not activate), matched to `windows_image_index = 6`. Allowlisted in `.gitleaks.toml` —
the pre-commit hook correctly blocked the commit first time.

### FIXED — 4. `90-cleanup.ps1` deleted Packer's own provisioner scripts

An unconditional `Remove-Item 'C:\Windows\Temp\*'`. Packer stages **both**
`packer-ps-env-vars-<uuid>.ps1` *and* `script-<uuid>.ps1` — the provisioner script itself — in that
directory. So cleanup deleted the next script; `99-sysprep.ps1` never ran, the VM never shut down,
and Packer waited on a shutdown that was never coming. Now excludes `packer-*` and `script-*`.
`win-server-2022` already excluded `packer-*` (which is why Server built and Win11 did not) and has
been hardened the same way so the two stop diverging.

### FIXED — 5. Windows 11 encrypted its own disk (real, but NOT the sysprep hang)

⚠️ **The commit that made this fix (`82b4916`) named it as the cause of the sysprep hang. That
was wrong** — see bug 7. Preventing auto-encryption is still correct and still required, and it is
now *proven* to work: a build that ran all the way through OOBE on 2026-07-28 left the Windows
partition as plain NTFS (`blkid` → `TYPE="ntfs"`, no `-FVE-FS-` signature) where the earlier one
showed `BitLocker`. Keep it. It was simply not what hung sysprep.

Also worth recording, because it wasted time: the *first* NTFS reading proved nothing. That build
died in the specialize pass, and auto-encryption happens during **OOBE** — so it never got far
enough to encrypt anything either way. Only a build that completes OOBE can test this fix.


Win11 turns device encryption ON BY ITSELF during OOBE when the firmware and a TPM support it —
which is exactly this template (q35 + OVMF + vTPM 2.0, all mandatory for Win11). Nothing in the
answer file asks for it. **Sysprep /generalize cannot run on a BitLocker volume**, so it never
returned: 25+ minutes of no output, a static disk, a black console, and a VM that never shut down,
so Packer waited on a shutdown that was never coming.

Fix: `PreventDeviceEncryption=1` in the **specialize** pass, which runs before OOBE. A provisioner
cannot do this — by then encryption has started and would need a full decrypt.

This also explains why the vTPM looked guilty: it IS involved, but as the trigger for
auto-encryption, not as a reset. Removing `tpm_config` alone left the build broken for the other
reasons still live at the time, so that experiment gave a false negative.

### FIXED — 6. Two `Microsoft-Windows-Deployment` components in one settings pass

Fix 5 was added as its own `<component>` block in `specialize`, beside the existing one that writes
`BypassNRO`. **A settings pass may name a component only once.** The file is still well-formed XML —
so `validate-answer-files.sh` passed it — but Windows rejects the whole answer file, and Setup
stopped at *"The computer restarted unexpectedly or encountered an unexpected error"* with a
24-hour build parked on `Waiting for WinRM`.

Windows names the fault precisely, and only on the disk:

```
SMI data results dump: Source = Name: Microsoft-Windows-Deployment, ...
SMI data results dump: Description = The same namespace should not appear twice in a single settings section.
The provided unattend file is not valid; hrResult = 0x8022001b
```

Fix: both commands now live in one component (`PreventDeviceEncryption` Order 1, `BypassNRO`
Order 2), and `scripts/validate-answer-files.sh` gained a duplicate-component check that reports
both line numbers. Verified it fails on a reinjected duplicate and passes both real templates.

That is **three** distinct ways this repo has shipped a silently-invalid answer file (`--` in a
comment, twice; a duplicate component, once). Every one of them looked like a different kind of
fault from the console. When Setup misbehaves, suspect the answer file first and run the validator
before theorising.

### FIXED — 7. `/unattend:` with spaces in it — ★ the real sysprep hang

`99-sysprep.ps1` passed `'/unattend:"C:\Program Files\Cloudbase Solutions\...\Unattend.xml"` as one
element of a `-ArgumentList` **array**. PowerShell re-quotes every array element, so sysprep
actually received `/unattend:C:\Program` and then a bare `Files\Cloudbase`, and threw the whole
command line out:

```
SYSPRP ParseCommands:Found supported command line option 'UNATTEND'
SYSPRP ParseCommands:Malformed command line detected; no dash or slash present in option
SYSPRP WinMain: Unable to parse command-line arguments to sysprep; GLE = 0x0
```

Sysprep then raised a **modal error dialog**. The script runs over WinRM on a non-interactive
session, so nothing could dismiss it and `Start-Process -Wait` waited forever. That is the entire
hang: no output, black console, idle guest, VM never shuts down, Packer waiting on a shutdown that
is never coming.

It cost about two days and was misdiagnosed twice — as the vTPM, then as BitLocker — because from
outside, every one of those looks the same. **The answer was always in
`Windows\System32\Sysprep\Panther\setuperr.log`**, which is four lines long and says exactly what is
wrong. Read that file FIRST next time; it needs `-on-error=abort` and the mount procedure below.

Fixed in **both** `packer/win11-client/scripts/99-sysprep.ps1` and
`packer/win-server-2022/scripts/99-sysprep.ps1` — the Server template carried the identical bug and
had simply not tripped it. Three changes each:
1. the answer file is copied to `C:\Windows\Temp\cloudbase-unattend.xml` (no spaces, so no quoting
   question at all) and passed from there;
2. the argument list is joined into ONE string before `Start-Process`, so PowerShell hands it over
   verbatim instead of re-quoting;
3. **`-Wait` is gone.** It now waits with a 15-minute deadline, then kills sysprep, prints
   setuperr.log and throws. A future dialog costs 15 minutes and a readable error instead of an
   unbounded hang.

Both scripts were parse-checked with `[Parser]::ParseFile` on dc-01 (real Windows PowerShell 5.1)
before committing — there is no `pwsh` on the workstation.

### ✅ IT BUILDS. The recipe, and why each part is load-bearing

`tpl-win11-client` (9003) exists and carries `template: 1`. All six templates are now
built. It took 22 builds; almost all of that was one problem, and the fix is four things.

**1. Pick ONE account model — this was the actual root cause.** Every maintained public
Windows-*client* Packer template uses either the built-in Administrator with **no**
`<LocalAccounts>`, or a dedicated local admin with **no** `<AdministratorPassword>`. Ours
did *both*, which no working reference does. Setting `AdministratorPassword` enables the
built-in account for OOBE, and client Windows then disables it again when OOBE finishes —
[documented, by design](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/enable-and-disable-the-built-in-administrator-account),
via the `Accounts: Administrator account status` policy whose effective default is
**Disabled on client and Enabled on Server**. That is also the real reason
`win-server-2022` always built fine with the identical arrangement.
→ No `<AdministratorPassword>`; autologon and WinRM both use `packer`; 99-sysprep deletes
the account before sealing. This is the shape of `Pumba98/proxmox-packer-templates`, the
closest published analogue (proxmox-iso + Win11 Enterprise **Evaluation** + WinRM).

**2. `winrm_use_ntlm = true`.** Basic re-sends the credential on every WS-Man POST and
depends on `service/auth Basic` + `AllowUnencrypted`, which ship **disabled**. NTLM is on
by default and unaffected if anything restores those defaults.

**3. One WinRM shell for the whole build.** Windows stops granting *new* shells shortly
after WinRM first answers, but a shell **already running** is unaffected — it ran 3m39s
through the cutoff and completed sysprep. So the scripts ride on the seed CD
(`cd_content`) and a single provisioner runs them from there. Anything that needs a second
shell — `file` provisioners, `environment_vars` (it uploads a separate env-vars script) —
loses the race. Four uploads lost; one directory upload lost; zero uploads won.

**4. `skip_clean = true`.** After a provisioner returns, Packer opens **another** shell to
delete what it uploaded. Build 18 completed sysprep and then threw the whole thing away on
exactly that. This is the single most expensive line in the file.

Sysprep itself needed two fixes, both proven: `/unattend:` must point at a **space-free**
path (`Start-Process -ArgumentList` re-quotes array elements and mangles
`C:\Program Files\...`, after which sysprep raises a modal dialog nobody can dismiss), and
`SkipRearm=1` is injected into the generalize pass so `SLReArmWindows` cannot fail with
`0xC004F075` — which also protects the evaluation media's two lifetime rearms.

#### Verify a build rather than trusting it

Mount the finished template read-only — note the LV is renamed `base-<vmid>-disk-N` once
Proxmox converts it:

```bash
LOOP=$(losetup --find --show --partscan --read-only /dev/pve/base-9003-disk-1)
mount -t ntfs-3g -o ro "${LOOP}p3" /mnt/w11tpl
ls /mnt/w11tpl/Windows/System32/Sysprep/Sysprep_succeeded.tag   # the marker that counts
ls /mnt/w11tpl/Windows/Panther/*.log                            # should be scrubbed
ls /mnt/w11tpl/Users/packer                                     # build account profile
umount /mnt/w11tpl; losetup -d "$LOOP"
```

#### Known cosmetic issues in the FIRST built template (9003 as it stands today)

Fixed in code afterwards, but **the template on the host predates the fixes** — they are
unexercised until the next rebuild:

- `C:\Windows\Temp\packer-ps-env-vars-*.ps1` and `script-*.ps1` are present. Read off the
  disk: no credentials (`PACKER_BUILDER_TYPE`, the build name, and the public
  Cloudbase-Init URL). `90-cleanup` could never remove them — it deliberately preserves
  `packer-*` and `script-*` — so 99-sysprep now deletes them explicitly.
- `C:\Users\packer` remains. The *account* is deleted; the profile directory cannot be,
  because the build is logged in as it. 99-sysprep now registers a `RunOnce` to remove it
  on a clone's first boot.
- The build logged `WARNING: GeneralizationState is '4', expected 7` — a **false alarm**.
  7 is the CLEAN state (sysprep has not run); 3/4 means it has. The check had the sense
  backwards and now expects 3/4, and additionally asserts `Sysprep_succeeded.tag`.

#### Six theories that were DISPROVED on the running guest — do not re-test

Kept because each cost a build: AutoLogon `LogonCount` (raised 2→5, verified on the
mounted CD, no effect — and Microsoft says the built-in account *stays active* after
expiry); `90-cleanup` deleting the Winlogon autologon values; the `cloudbase-init` local
admin created by the MSI (removed via `RUN_SERVICE_AS_LOCAL_SYSTEM=1`); Defender
quarantining a watchdog; the `windows-restart` provisioner; and simply doing less work
inside the window.

#### ⛔ Do NOT move the WinRM bootstrap to SetupComplete.cmd

Tried twice (`87c0061`, `58763a7`); cost two builds including a 15-hour overnight run.
**A specialize-pass `RunSynchronousCommand` that exits non-zero ABORTS WINDOWS SETUP** —
the console shows *"The computer restarted unexpectedly or encountered an unexpected
error"*, identical to a malformed answer file even when the XML is fine. `FirstLogonCommands`
is the carrier that works.

#### What the research could not find

Four independent searches found **no** report of: a `<LocalAccount>` declared in the answer
file being *deleted* at OOBE completion; anything that removes scheduled tasks and
`C:\ProgramData` directories minutes into first boot; or "WinRM answers, then refuses new
shells while a running one survives". The public Packer 401 issues were bulk-closed as
stale in 2025 and `winrmcp` is unmaintained, so there is no upstream fix pending. If those
symptoms recur, they are still uncharacterised.

### win-client-01 (VMID 105) — DEPLOYED, DOMAIN-JOINED, MONITORED (2026-07-29)

The first machine ever cloned from 9003. Live state, all verified rather than assumed:

| Check | State |
|---|---|
| `tofu apply` | `3 to add, 0 to change, 0 to destroy` — nothing else in the lab touched |
| VM | 105 running, guest agent up, DHCP reservation **10.10.10.51** honoured |
| Identity | renamed `WIN-CLIENT-01`, `PartOfDomain=True` on `mutaspace.local` |
| Sysmon + 4625 auditing | installed and running (`60-endpoints`) |
| Wazuh agent | **ID 004, Active** on the manager — five agents total |
| Re-run idempotency | `60-endpoints` second pass: ubuntu-app-01 `changed=0`, no failures |

`lab.yaml` now has `win-client-01: enabled` (the `enabled: false` guard is gone), and
`tofu/tests/enabled_flag.tftest.hcl` lost its "at least one machine is disabled"
assertion — on the instruction that assertion itself carried. `tofu test` is 14/14.

**`learner_endpoints.win-client` is deliberately still `enabled: false`.** Those are
LINKED clones: creating them pins template 9003 so it cannot be rebuilt or deleted while
any of them exists. Leave them off until the template is settled.

#### First-boot bootstrap — ✅ VERIFIED HANDS-OFF (2026-07-30)

A clone now goes from nothing to domain-joined and monitored with **no manual step**.
Proven on a machine that was never touched by hand:

```
template 9003 (build 25)
  -> tofu clone, DHCP reservation 10.10.10.51 honoured
  -> cloud-init enables Administrator from TF_VAR_windows_admin_password
  -> template-registered task converges WinRM, then unregisters itself
  -> template-registered task removes C:\Users\packer
  -> ansible win-client-01-bootstrap -m win_ping  ->  pong
  -> 30-domain-join   ok=6  changed=1  failed=0   (mutaspace.local)
  -> 50-wazuh-agents  ok=7  changed=5  failed=0   (agent ID 005, Active)
  -> 60-endpoints     ok=12 changed=8  failed=0   (Sysmon + 4625)
```

Guest evidence:

```
WinRM status:    Running
WinRM listener:  ListeningOn = 10.10.10.51, 127.0.0.1, ::1, ...
ensure task:     False          <- unregistered itself after succeeding
C:\Users\packer: False
ensure-winrm starting / listener up: ... / task unregistered - done
```

#### ⭐ THE RULE THAT MAKES WINDOWS FIRST-BOOT WORK: PLACEMENT DECIDES SURVIVAL

**Anything registered before OOBE completes is WIPED when it does.** Measured three
times: the build-time watchdog's scheduled task and `C:\ProgramData\mutaspace` vanished
mid-build, and a converge task registered from the clone's cloud-init was gone after the
first reboot with its log never written.

The OpenTofu user-data runs during the clone's **specialize** pass, which is on the wrong
side of that line. It proved it by logging `$env:COMPUTERNAME` as **PKR-WIN11-TPL — the
template's own name** — before OOBE had assigned an identity. At that moment there is no
usable network either, so `winrm quickconfig` and even an explicit `winrm create Listener`
both fail.

So first-boot machinery must live **in the image**, registered by `99-sysprep.ps1` before
sysprep. Two tasks now ship that way, and both are verified firing on a clone:

| Task | Job | Self-removes |
|---|---|---|
| `MutaSpaceEnsureWinRM` | wait for real IPv4, flip Public→Private, create the HTTP listener | yes, once listening |
| `MutaSpaceRemovePackerProfile` | delete the leftover `C:\Users\packer` | yes, after deleting |

⚠️ **The clone's cloud-init must NOT register either task.** An earlier version did, and
its registration begins with `Unregister-ScheduledTask` — on a clone that DELETES the
template's working task and replaces it with one that is then wiped. Strictly worse than
doing nothing. The user-data now only does cheap idempotent work (service, firewall,
token policy, DNS, time) and defers the listener to the template task.

⚠️ **`RunOnce` does not work here.** It fires at the first *interactive* logon and nobody
logs into a headless lab VM — the value sat unfired with the profile still present. Use an
`AtStartup` SYSTEM task instead.

⚠️ **No computer-name rename in the user-data.** It cannot stick from specialize (OOBE
overwrote `win-client-01` with `DESKTOP-RA0MI6L`), and `30-domain-join` renames and joins
in one `microsoft.ad.membership` operation anyway. Cloudbase-Init cannot do it either:
`cicustom user=` ships user-data with no meta-data, so `SetHostNamePlugin` logs
"Hostname not found in metadata".

#### ⚠️ THREE VARIABLES MUST CARRY THE SAME WINDOWS PASSWORD

They did NOT match on this host, and that alone would have made a clone unreachable:

| Variable | Used by |
|---|---|
| `PKR_VAR_windows_admin_password` | Packer, during the build |
| `TF_VAR_windows_admin_password` | OpenTofu cloud-init, sets it at first boot |
| `MUTASPACE_WIN_ADMIN_PASSWORD` | Ansible, authenticates with it |

`TF_VAR_` must equal the **Ansible** one. `.envrc.example` wires them together; compare
with `sha256sum` before cloning rather than trusting that they match.

#### Re-cloning a Windows guest: the stale artefacts are fine

Destroying and re-cloning leaves an AD computer object and a Wazuh agent registration
behind. Both resolved themselves on 2026-07-30: `microsoft.ad.membership` reused the
existing computer object, and the agent re-enrolled as a NEW id (004 → 005) with the stale
entry replaced. No manual cleanup was needed.

#### Playbook order matters: 50 BEFORE 60

`60-endpoints` finishes by adding the Sysmon channel to the Wazuh agent's `ossec.conf`,
which does not exist until `50-wazuh-agents` has installed the agent. Running 60 first
gives `ok=9 changed=6 failed=1` with
`Cannot find path 'C:\Program Files (x86)\ossec-agent\ossec.conf'`. The numbering encodes
the dependency; follow it. Re-running 60 afterwards clears it (`ok=12 changed=2 failed=0`).

#### Known, expected failure in 50-wazuh-agents

Its closing assert wants `kali-01`, `nlp-01` and `untrusted-01` registered. Those are
`started: false` by design, so the play reports `wazuh-01 ... failed=1` while every host it
could actually reach succeeds. Scope it with
`--limit "wazuh_manager:<host>"` to avoid the noise, or power the research plane on first.

### Reading the disk when a build fails — proven procedure

⚠️ **Packer DESTROYS the VM when a build is interrupted or fails.** `qm destroy` runs in its
cleanup path, so killing a hung build always takes the disk — and therefore the logs — with it.
This was learned twice in a row: the VM was stopped to mount the disk and the disk had already
been deleted. Nothing can be recovered afterwards.

The fix is a Packer flag, not a repo change:

```bash
# -on-error=abort exits WITHOUT cleanup, leaving VM 9003 and its disk in place.
packer build -on-error=abort \
  -var-file=packer/common.pkrvars.hcl \
  -var-file=packer/win11-client/win11-client.pkrvars.hcl \
  packer/win11-client/
```

Let it reach the hang, then kill it **by its captured PID**. The VM survives — this was walked
end-to-end on 2026-07-28 and is what found bug 6. Then, ON THE HOST:

```bash
qm stop 9003                                   # stop, do NOT destroy
lvchange -ay /dev/pve/vm-9003-disk-1
LOOP=$(losetup --find --show --partscan --read-only /dev/pve/vm-9003-disk-1)
lsblk -o NAME,SIZE,FSTYPE "$LOOP"              # p3 is the 63G Windows partition

mkdir -p /mnt/w11disk
mount -t ntfs-3g -o ro "${LOOP}p3" /mnt/w11disk

# WHICH LOG ANSWERS THE QUESTION DEPENDS ON WHERE IT DIED
#   Setup / specialize / OOBE  ->  Windows\Panther
tail -40 /mnt/w11disk/Windows/Panther/setuperr.log
tail -20 /mnt/w11disk/Windows/Panther/UnattendGC/setuperr.log
#   sysprep itself             ->  Windows\System32\Sysprep\Panther
tail -40 /mnt/w11disk/Windows/System32/Sysprep/Panther/setuperr.log

umount /mnt/w11disk; losetup -d "$LOOP"
qm destroy 9003                                # clear the way for the next build
```

`ntfs-3g` is already installed on the host (`apt-get install -y ntfs-3g`, done 2026-07-26).
`guestmount` is NOT installed; `losetup --partscan` + `ntfs-3g` is enough and avoids libguestfs.
`losetup --partscan` is more reliable here than `partx -a`, which is what the earlier draft used.

**`blkid` on that partition is also a free BitLocker check:** `TYPE="ntfs"` means encryption did
not happen; `TYPE="BitLocker"` (or `-FVE-FS-` in the first sector) means it did, and sysprep will
never finish.

**Also seen on the last attempt: a SECOND, different hang.** One run stalled for 30+ minutes
between provisioner 1 and 2 — after `00-virtio-guest-tools.ps1` printed "virtio guest tools
complete" and before `10-cloudbase-init.ps1` produced any output. That script downloads the
Cloudbase-Init MSI from the internet, so a slow or hanging fetch is the obvious suspect. It is
NOT the sysprep hang (that was BitLocker, bug 5) and may be intermittent; another run got past this
point cleanly. Worth adding a timeout and a retry to that download regardless — still open.

What 9003 still blocks: `win-client-01` (VMID 105), the Windows half of `60-endpoints` (Sysmon +
4625 auditing), and `50-wazuh-agents` for that host. Nothing else depends on it — both incident
scenarios run Linux-to-Linux.

---

## Git

Branch `feat/infrastructure-as-code`, pushed. HEAD is the answer-file duplicate-component fix
(2026-07-28). `tofu test` 14/14. The Windows/OPNsense manual ISOs are on the host's `local:iso`
shelf. Note the aborted builds leave stray `packer<digits>.iso` files there — harmless, but they
accumulate.

---

## All six templates are built (on the host)
9000 ubuntu-server, 9001 ubuntu-desktop, 9002 win-server, **9003 win11-client**,
9004 opnsense, 9005 kali. Verify with `ssh swc2026 'qm list'` plus
`grep '^template: 1' /etc/pve/qemu-server/<vmid>.conf`.
