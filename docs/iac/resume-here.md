# Resume Here

Scratch handoff for picking the work back up. docs/iac/session-handoff.md is the durable
overview; getting-started.md is the operator walkthrough.

**Last updated: 2026-07-23 — the lab is DEPLOYED and mid-configuration. jumpbox-01 is now built
and provisioned as the Ansible control node; config playbooks 50–90 still pending.**

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

- **Proxmox host:** `swc2026` at `10.1.1.2`. SSH alias in `~/.ssh/config`, reached over
  WireGuard from this workstation. Key: `~/.ssh/id_ed25519_proxmox`.
- **The host was given management IPs on the lab bridges** (`10.10.10.2` on vmbr1, `10.10.20.2`
  on vmbr2, persisted via post-up in /etc/network/interfaces) so it can reach the lab VMs. This
  is a stopgap the jumpbox replaces.
- **Ansible runs from the host** right now: `/root/ansible/` (rsynced from this repo), collections
  installed, `python3-winrm` installed, secrets at `/root/ansible/.secrets/env` (mode 600).
- Load the lab creds before any ansible command: `set -a; . /root/ansible/.secrets/env; set +a`
  then `cd /root/ansible`.

### Credentials (in /root/ansible/.secrets/env on the host)
- `MUTASPACE_WIN_ADMIN_PASSWORD` = `***REMOVED-ROTATED-CREDENTIAL***` (also the domain admin password)
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
| 104 | wazuh-01 | running | **Wazuh installed** (all-in-one assistant completed; verify dashboard on :443) |
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
| 40-wazuh-server | **done** — all-in-one assistant completed; next verify the dashboard |
| 50-wazuh-agents | pending |
| 60-endpoints | pending (nginx on ubuntu-app-01; Sysmon needs win-client, not built) |
| 70-detections | pending |
| 80-ai-assist | pending — installs **Ollama on nlp-01** (start nlp-01 first). The `ai/` Python tooling (detection copilot, lab assistant) drives it |
| 90-lab-seed | pending — creates test.user / lab.user02 (the incident scenarios need them) |

Run pattern: `ssh swc2026 'set -a; . /root/ansible/.secrets/env; set +a; cd /root/ansible; ansible-playbook -i inventory/hosts.yml playbooks/<pb>'`

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
   auth; fixed manually via `qm guest exec 102 -- net.exe user Administrator ***REMOVED-ROTATED-CREDENTIAL***`.
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

## Win11 (9003) — NOT built, well-diagnosed

Boot-catch **solved** (spacebar is OVMF's menu hotkey; drive the menu: spam spacebar to park on
HARDDISK, `<down>` to the install DVD, `<enter>`, then answer the CD prompt — in the template's
boot_command now). The install then **silently resets at the WinPE→Setup handoff** — NOT a compat
check (no dialog). Root cause: **virtio-win 0.1.271 crashes the Windows 11 25H2 WinPE kernel**,
plus a deeper vTPM/media reset. **Fix (outside packer/win11-client/):** rebuild
`virtio-winpe-drivers-w11.iso` from a virtio-win that supports 25H2 (build 26100); optionally a
one-off diagnostic build with `tpm_config` removed to isolate the deeper reset. Everything else
in the E2E works without it.

---

## Git

Branch `feat/infrastructure-as-code`, pushed. HEAD = jumpbox commit (`8cd3ef0`). `tofu test` 14/14.
The Windows/OPNsense manual ISOs are on the host's `local:iso` shelf.

---

## The five templates that ARE built (on the host)
9000 ubuntu-server, 9001 ubuntu-desktop, 9002 win-server, 9004 opnsense, 9005 kali. Only
9003 win11 is missing.
