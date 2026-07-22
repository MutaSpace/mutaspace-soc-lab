# Resume Here

A running note for picking the build back up. This is the scratchpad;
docs/iac/session-handoff.md is the durable overview and getting-started.md is the
operator walkthrough.

**Last updated: 2026-07-22 — session stopped, moving to a dev VM to continue.**

---

## Stop state (read this first)

Everything is committed and pushed. Nothing is mid-flight. Host is clean.

| VMID | Template | State |
|---|---|---|
| 9000 | `tpl-ubuntu-server-2404` | **BUILT** — on the host, intact |
| 9001 | `tpl-ubuntu-desktop-2404` | **BUILT** — on the host, clone-verified |
| 9002 | `tpl-win-server-2022` | **NOT built.** Was mid-sysprep when stopped; the build was killed and the half-built VM destroyed. Rebuild from scratch. Everything up to and including sysprep-start was proven to work, so expect it to complete on a clean run. |
| 9003 | `win11-client` | not started. ISO on host; needs a w11 driver ISO |
| 9004 | `opnsense-267` | not started. Needs the OPNsense ISO (decompress the .bz2) |
| 9005 | `kali-rolling` | not started. Public ISO, no blockers |

Confirm on the host, don't trust this table:
```
ssh swc2026 'for f in /etc/pve/qemu-server/*.conf; do grep -q "^template: 1" "$f" && echo "$(basename $f .conf) $(grep ^name: $f)"; done'
```

The host is **swc2026** at 10.1.1.2, reached over SSH (alias in ~/.ssh/config) and over
WireGuard from this workstation.

---

## Moving to a dev VM — what travels and what does not

The git repo travels. **Three things are gitignored and machine-local — they do NOT come
with a `git clone`** and must be handled on the dev VM:

| File | What it holds | On the dev VM |
|---|---|---|
| `.envrc` | API tokens, build password, SSH key path | Recreate. Either `scp` it from this workstation, or re-run `scripts/bootstrap-host.sh --rotate-tokens` on the host to reissue tokens and rebuild it from the printed output. |
| `packer/common.pkrvars.hcl` | endpoint, node, build_bridge, http_bind_address | Recreate from `.example`. **http_bind_address will likely be DIFFERENT** — it is the address the build VM can reach the workstation on, and the dev VM's network path to swc2026 is not this laptop's. Re-derive it (see below). |
| `~/.ssh/id_ed25519_mutaspace_lab` | the build SSH key Packer/cloud-init use | `scp` it over, or generate a new one and update `.envrc` + the tofu `ssh_public_keys`. Simplest to copy the existing pair. |

Fastest move: `scp` `.envrc`, `packer/common.pkrvars.hcl`, and `~/.ssh/id_ed25519_mutaspace_lab*`
from this workstation to the dev VM, then fix `http_bind_address` for the dev VM's network.

### Re-deriving http_bind_address on the dev VM
It must be the dev VM's address ON the network swc2026 can route back to:
```
ip route get 10.1.1.2        # the src address here is your http_bind_address
```
If the dev VM reaches swc2026 over the same WireGuard, it may be a 10.200.x address; if it
is on the 10.1.1.0/24 LAN directly, it is a 10.1.1.x address. Getting this wrong makes the
installer silently hang at its menu — set it, then `task preflight`.

### The API tokens still work
bootstrap-host.sh was already run on swc2026; the tokens exist. If you copied `.envrc`, they
just work from the dev VM. Only rotate if you did not preserve the secrets.

---

## Rebuilding the Windows Server template (9002) — the known-good path

The install is fully solved. On a clean run it should go all the way. Sequence:
```
cd <repo>; set -a; . ./.envrc; set +a
ssh swc2026 '/root/build-winpe-driver-iso.sh'      # rebuilds local:iso/virtio-winpe-drivers.iso
setsid nohup packer build -var-file=packer/common.pkrvars.hcl \
  -var-file=packer/win-server-2022/win-server.pkrvars.hcl packer/win-server-2022/ \
  > /tmp/winsrv.log 2>&1 & echo $! > /tmp/winsrv.pid
```
Watch it: install (~10 min) -> WinRM connects -> guest tools -> Cloudbase-Init -> cleanup ->
sysprep (~15-20 min, console goes black, normal) -> template. ~35-40 min total.

If it stalls at "Waiting for WinRM": check PKR_VAR_windows_admin_password is set (preflight
does). If a NEW `403 Permission check failed (<path>, <Priv>)` appears: add the priv to
build_privs() in scripts/bootstrap-host.sh, scp up, re-run
`bootstrap-host.sh --yes --skip-repos --skip-snippets --skip-network`.

---

## Then, in order of least friction

1. **9005 kali-rolling** — public ISO, nothing gated. Easy.
2. **9003 win11-client** — Windows path solved. First build its own driver ISO:
   `ssh swc2026 '/root/build-winpe-driver-iso.sh --variant w11 --out /var/lib/vz/template/iso/virtio-winpe-drivers-w11.iso'`
   then point the win11 template's `winpe_driver_iso_file` at it. Same
   windows_iso_file / password / sysprep steps as 9002.
3. **9004 opnsense-267** — hardest, timing-sensitive boot_command. Do it last.

Then flip the built machines to `enabled: true` in lab.yaml and `task lab:up`. See
getting-started.md Part 4 for the OpenTofu + Ansible deployment sequence.

---

## The rules that bit us (keep them)

- **Kill a build ONLY by captured PID.** `pkill -x packer` killed a concurrent build;
  `pgrep -f 'packer build.*name'` matched its own shell. Always
  `setsid nohup packer build ... & echo $! > pidfile` then `kill "$(cat pidfile)"`.
- **Verify on the host, never assume.** `qm list`, `qm config <vmid>`, the console
  screendump. This repo does not claim results it did not observe.
- **Read the console when a build stalls** (getting-started.md "When something goes wrong").
- **Fix the script, not just the host** — three missing privileges (SDN.Use,
  VM.GuestAgent.Audit, Datastore.Allocate) are now in bootstrap-host.sh because of this.

---

## What this session accomplished

- Whole pipeline proven end to end: host bootstrap -> API auth -> Packer build -> OpenTofu
  discovery. `tofu plan` against swc2026 succeeds; `tofu test` is 14 passing offline.
- Two templates built (9000, 9001). Windows install fully solved via `$WinPEDriver$`.
- Found and fixed in CODE (so nobody re-hits them): 3 missing PVE privileges, the
  sendkey kernel panic, the masquerade-on-enslaved-port bug, missing build-plane DHCP,
  the http_bind_address multi-NIC trap, the Windows virtio injection, the Desktop
  NetworkManager-match trap, cleanup deleting Packer's own files.
- The repo is now self-guiding: CLAUDE.md + getting-started.md mean an operator can
  check it out, open Claude Code, and be walked through the whole setup.
- Windows licensing recorded: eval media cannot be redistributed as built images, so
  each operator builds Windows locally (iso-shelf.md, CLAUDE.md).
