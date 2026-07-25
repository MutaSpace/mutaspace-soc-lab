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
cannot skip. Remaining: **Win11 template (9003)** — boot prompt FIXED, but Setup still writes nothing
to disk (see below) — and a formal recorded `70-detections` run.**

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
  2026-07-24** — the previous shared value leaked into this file and is burned; see
  `scripts/rotate-lab-credentials.sh`.
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

The two-scenario incident runner is **built and proven on the live host**. Full instructor guide:
[docs/scenarios/README.md](../scenarios/README.md). Non-obvious live facts the next operator inherits:

- **Both scenarios verify end-to-end** (run from the jumpbox, `ansible/`):
  `ssh-bruteforce` fires built-in rules 5710+**5712**, `web-sqli` fires **31164**+31106
  (31164, *not* the proposal's guessed 31103). Attack path: kali-01 (10.10.20.10, vmbr2) →
  ubuntu-app-01 (10.10.10.30, vmbr1) across fw-01.
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
| 70-detections | **effectively applied** — custom rules 100010/100011/100020/100021 loaded on wazuh-01 (match repo local_rules.xml); Suricata decoder + syslog listener live and rule 86601 proven end-to-end. Only gap: one *recorded* full-play run via `task ansible:detections`, which needs `MUTASPACE_WAZUH_API_PASSWORD` exported on the jumpbox (the jumpbox `.secrets/env` is still missing the `MUTASPACE_WAZUH_API_*` pair — add from `.secrets/wazuh-passwords.txt`). |
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

## Win11 (9003) — NOT built. TWO failures; the first is FIXED, the second is isolated.

Updated 2026-07-24. The previous note treated this as one problem. It is two, and separating
them is most of the progress.

### Failure 1 — the boot prompt. FIXED, verified, committed.

Windows media prints `Press any key to boot from CD or DVD......` and gives ~5 seconds. Nothing
pressed it, the firmware fell through to the empty disk, and the run died at
`BdsDxe: No bootable option or device was found.` — after which Packer waited its full 2 h
`winrm_timeout` for a machine that never started installing.

The template had been fighting this with 55 spacebars + 30 `<enter>`s spanning ~130 s. It kept
missing: a vTPM makes POST vary from ~45 s to >120 s, spacebar on this OVMF is the boot-menu
hotkey rather than "any key", and QEMU's `sendkey` drops keystrokes under load.

**Fix: `scripts/remaster-windows-iso.sh`** rebuilds the ISO with
`efi/microsoft/boot/efisys_noprompt.bin` as the UEFI El Torito image instead of `efisys.bin`.
Microsoft ships both in every Windows ISO. `boot_command` is now `[]` — with
`boot = "order=scsi0;sata0"` the whole sequence is deterministic and needs no input:

```
BdsDxe: failed to load Boot0003 "UEFI QEMU QEMU HARDDISK" : Not Found   <- empty disk
BdsDxe: loading  Boot0002 "UEFI QEMU DVD-ROM QM00013"                   <- falls through
BdsDxe: starting Boot0002 "UEFI QEMU DVD-ROM QM00013"                   <- boots, no prompt
```

Two tool facts, both now in the script: **xorriso cannot do this** (`install.wim` is ~7 GB so
the image needs UDF, and xorriso has no UDF support — `-as mkisofs: Unsupported option '-udf'`);
and genisoimage has **no `-eltorito-platform`** (its `-e` *is* `-efi-boot` and already implies
the EFI platform id; passing the flag gives `Invalid node - 'efi'`).

### Failure 2 — Setup never writes to the disk. NOT fixed. This is where to start.

With failure 1 fixed the build gets materially further and then loops:

1. Boots WinPE from the DVD — **no prompt, confirmed on the console.**
2. Reaches Windows Setup — the indigo Setup background appears (~11 min in).
3. **Writes nothing.** `vm-9003-disk-1` (64 GB) sits at **0.01 % used** after 26 minutes.
4. Resets and boots the DVD again. Console frames are byte-identical 75 s apart.

So this is **not** the boot prompt and **not** a WinPE driver crash — WinPE boots fine now.
Setup starts and fails at or before partitioning. The earlier note's "virtio-win 0.1.271 crashes
the 25H2 WinPE kernel" diagnosis is superseded for this stage: the WinPE driver ISO is already
built from **0.1.285** (`DriverVer 100.101.104.28500`, vs `...27100` in the `.271bak`), and WinPE
now boots.

**The 285/271 split on the host is deliberate — leave it.** `virtio-winpe-drivers-w11.iso` is
0.1.285 (fixes the 25H2 WinPE kernel); `virtio_win_iso_file` stays 0.1.271 for the installed OS
(0.1.285/0.1.292 regress vioscsi). Each version is used where it belongs.

**Next step, in order:**

1. Read Setup's own log rather than guessing. Boot the ISO, `<shift><F10>` at the Setup screen
   for a console, and read `X:\Windows\Panther\setupact.log` and `setuperr.log`. That file
   names the actual failure; everything above this line is inference from outside the guest.
2. Check whether Setup can see the disk at all: `diskpart` → `list disk` in that same console.
   Empty means the vioscsi driver is not loaded in the **Setup** phase (a different phase from
   WinPE, and `$WinPEDriver$` only covers the latter).
3. If the disk IS visible, suspect the `Autounattend.xml` `DiskConfiguration` block.
4. Only then try the one-off diagnostic build with `tpm_config` removed, to rule out the vTPM.

Everything else in the lab works without 9003. What it blocks: `win-client-01` (VMID 105), the
Windows half of `60-endpoints` (Sysmon + 4625 auditing), and `50-wazuh-agents` for that host.

---

## Git

Branch `feat/infrastructure-as-code`, pushed. HEAD = jumpbox commit (`8cd3ef0`). `tofu test` 14/14.
The Windows/OPNsense manual ISOs are on the host's `local:iso` shelf.

---

## The five templates that ARE built (on the host)
9000 ubuntu-server, 9001 ubuntu-desktop, 9002 win-server, 9004 opnsense, 9005 kali. Only
9003 win11 is missing.
