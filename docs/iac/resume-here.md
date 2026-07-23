# Resume Here

A running note for picking the build back up. This is the scratchpad;
docs/iac/session-handoff.md is the durable overview and getting-started.md is the
operator walkthrough.

**Last updated: 2026-07-23 — end of the template-build session. 4 of 6 templates built.**

---

## Stop state (read this first)

Everything is committed and pushed. No builds running. Host is clean.

| VMID | Template | State |
|---|---|---|
| 9000 | `tpl-ubuntu-server-2404` | **BUILT** — on the host |
| 9001 | `tpl-ubuntu-desktop-2404` | **BUILT** — clone-verified |
| 9002 | `tpl-win-server-2022` | **BUILT** — see the salvage note below; the rebuild path has a known race |
| 9004 | `tpl-opnsense-267` | **BUILT** — the hard one; config seed verified on disk, not yet on boot |
| 9003 | `win11-client` | **NOT built.** Reaches WinPE, aborts before partitioning. Diagnosed — see below |
| 9005 | `kali-rolling` | **NOT built.** Installs fully, then first boot hangs before the guest agent starts. Diagnosed — see below |

Confirm on the host, don't trust this table:
```
ssh swc2026 'for f in /etc/pve/qemu-server/*.conf; do grep -q "^template: 1" "$f" && echo "$(basename $f .conf) $(grep ^name: $f)"; done'
```

Host is **swc2026** at 10.1.1.2 (SSH alias in ~/.ssh/config; reached over WireGuard from this
workstation). Four gitignored, machine-local files that do NOT travel with `git clone`:
`.envrc`, `packer/common.pkrvars.hcl`, `packer/kali-rolling/kali.pkrvars.hcl`, and the build
SSH key `~/.ssh/id_ed25519_mutaspace_lab*`. On a different machine, recreate or `scp` them,
and re-derive `http_bind_address` for that machine's network.

---

## The two templates that do NOT build yet — each has a clear next step

### 9005 Kali — first boot hangs before the guest agent starts
The installer now runs fully unattended (fixed: `http_bind_address`, `boot_keygroup_interval`,
a 404'd ISO URL, an `iso_file` name collision) and reaches "installing the base system" — then
fails at "Timeout waiting for SSH". **Diagnosed:** the qemu guest agent never responds across
the whole wait, not even loopback. Since the agent speaks over virtio-serial (network-
independent) and Debian auto-starts it on install, its total absence means **first boot never
reaches multi-user.target** — most likely a cloud-init first-boot hang.

**The one test that decides it next session:** during the SSH-wait window, screendump the
console. A login prompt ⇒ boot finished (agent/package problem). A frozen cloud-init line or an
emergency shell ⇒ the boot hang. (Prior attempts screenshotted during *install*, so the
evidence auto-deleted with the VM. Do it during the wait.) Likely fix, in `packer/kali-rolling/`:
disable cloud-init's first-boot network management via the preseed `late_command`, keeping
cloud-init for clone identity. `ssh_timeout` is currently 15m for fast iteration; restore 60m
when green.

### 9003 Windows 11 — WinPE aborts, but the real blocker is catching the CD
Setup aborts in WinPE before partitioning (scsi0 verified blank). Two hypotheses, unchanged:
**(A, leading)** a "This PC can't run Windows 11" compat-halt, because the LabConfig bypass runs
via `RunSynchronous` *after* Setup's compat scan; **(B)** the w11 vioscsi driver didn't load.

**The meta-problem that blocks the diagnosis:** the "Press any key to boot from CD" prompt is a
~6-second window that recurs only once per ~40–60s firmware boot loop, because the boot order
grinds through PXE-v4 → PXE-v6 → HTTP-v4 → HTTP-v6 with multi-second timeouts each. This is NOT
host-load-dependent (confirmed at load 0.08). A bounded keystroke burst cannot reliably land in
the 6s window; only a ~200-press flood catches it — and that flood dismisses the WinPE error
dialog before it can be read. So until the CD can be caught with a *bounded* burst, the dialog
that would pick A vs B can't be seen.

**Fix the boot-catch FIRST next session:** shorten the firmware's network-boot fallthrough so the
CD prompt recurs quickly (e.g. trim the boot order / disable PXE+HTTP netboot in the VM's OVMF
boot entries so it goes straight back to the CD), OR use a boot method that doesn't depend on the
narrow window. Then read the dialog: if compat-halt (A), move the LabConfig bypass earlier
(winpeshl.ini before setup.exe) WITHOUT weakening the real vTPM; if "no drives" (B),
Shift+F10 → `wmic diskdrive get size` to check the w11 driver, as the Server template was solved.
Full detail is in the big `boot_command` comment in `packer/win11-client/win11-client.pkr.hcl`.

---

## 9002 Windows Server was SALVAGED — the rebuild path has a race

9002 is a valid generalized template, but note HOW it got there: the build completed sysprep
(`GeneralizationState = 0x7`, verified) and then HUNG. `sysprep /generalize` restarts WinRM,
which severs Packer's held session; Packer then blocks on a dead socket until a ~2h timeout, at
which point its cleanup would DESTROY the VM. The image was salvaged manually: SIGKILL the hung
packer PIDs (so no destroy-cleanup runs), then `qm stop 9002`, detach the build CDs
(`qm set 9002 --delete sata0,sata1,sata2,sata3`), `qm template 9002`.

**This is an intermittent race** (an earlier run won it and reached teardown normally). For the
"instructors rebuild Windows locally" model to be reliable, HARDEN it: have `99-sysprep.ps1` use
`/shutdown` and let the builder detect the shutdown, instead of `/quit` + waiting on WinRM. Until
then, a clean rebuild may hit the 2h hang, and the salvage recipe above is the recovery.

---

## Design correction landed this session
Suricata is **core** in OPNsense 26.7, not a plugin. Decision D-04 assumed installing
`os-suricata`; that package does not exist in 26.7 and its absence was aborting the whole
install. Fixed in the OPNsense template; **decisions.md D-04 still needs updating to match.**

---

## What was committed this session
- OPNsense template (built) — commit "Build the OPNsense firewall template (9004)"
- Kali progress (not building) — "Kali template: real fixes, still blocked on a first-boot hang"
- Win11 progress (not building) — "Windows 11 template: real fixes, still blocked in WinPE"
- Plus earlier: the `enabled` flag, three PVE privileges (SDN.Use, VM.GuestAgent.Audit,
  Datastore.Allocate), the `$WinPEDriver$` Windows fix, the netplan-match Desktop fix, and the
  self-guiding CLAUDE.md + getting-started.md.

## The rules that bit us (keep them)
- **Kill a build ONLY by captured PID.** `pkill -x packer` killed a concurrent build;
  `pgrep -f 'packer build.*name'` matched its own shell. Always
  `setsid nohup packer build ... & echo $! > pidfile`, then `kill "$(cat pidfile)"`.
- **Verify on the host, never assume.** `qm list`, `qm config`, the console screendump.
- **Screendump during the phase you're debugging**, not the previous one — the VM auto-deletes
  on failure and takes the evidence with it (both Kali attempts lost evidence this way).
- **Fix the script, not just the host** — the three privileges are in bootstrap-host.sh because
  of this.

## Next-session order (least friction first)
1. **Kali** — one screendump during SSH-wait decides the cloud-init hypothesis; likely a small
   preseed change. Probably the quickest win.
2. **Win11** — solve the boot-catch (trim the OVMF netboot fallthrough) first, THEN read the
   dialog and apply fix A or B.
3. Update **decisions.md D-04** for the Suricata correction, and **harden the Windows Server
   sysprep/shutdown** path.
4. Then flip built machines to `enabled: true` in lab.yaml and start on `tofu apply` +
   the Ansible layer — none of which has been exercised yet (see getting-started.md Part 4).
