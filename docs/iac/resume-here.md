# Resume Here

A running note for picking the build back up. Newest state at the top. This is the
scratchpad; docs/iac/session-handoff.md is the durable overview.

Last updated: 2026-07-22, mid-build pause.

---

## Where the templates stand

| VMID | Template | State |
|---|---|---|
| 9000 | `tpl-ubuntu-server-2404` | **BUILT** |
| 9001 | `tpl-ubuntu-desktop-2404` | **BUILT**, clone-verified |
| 9002 | `tpl-win-server-2022` | **IN FLIGHT** at pause - see below |
| 9003 | `win11-client` | not started. ISO on host; needs the w11 driver ISO |
| 9004 | `opnsense-267` | not started. Needs the OPNsense ISO (decompress the .bz2) |
| 9005 | `kali-rolling` | not started. Public ISO, no blockers |

Check the truth on the host, never from memory:
```
ssh swc2026 'for f in /etc/pve/qemu-server/*.conf; do grep -q "^template: 1" "$f" && echo "$(basename $f .conf) $(grep ^name: $f)"; done'
```

## The Windows Server 2022 build (9002) was RUNNING when we paused

It was on `99-sysprep.ps1`, ~26 minutes in, console black (normal for sysprep's final
shutdown). It runs DETACHED (`setsid nohup`), so it kept going after the session ended.
On resume, the FIRST thing to check is whether it finished:

```
tail -20 /tmp/claude-*/scratchpad/packer-winsrv7.log    # or wherever the log went
ssh swc2026 'qm list | grep 9002; grep "^template: 1" /etc/pve/qemu-server/9002.conf'
```

Three outcomes:
- **`A template was created: 9002`** in the log and `template: 1` on the host -> DONE.
  Flip dc-01 back to `enabled: true` in lab.yaml (it is currently disabled).
- **Errored / no artifacts** -> read the tail, fix, and rebuild:
  ```
  ssh swc2026 'qm stop 9002; sleep 2; qm destroy 9002'
  set -a; . ./.envrc; set +a
  setsid nohup packer build -var-file=packer/common.pkrvars.hcl \
    -var-file=packer/win-server-2022/win-server.pkrvars.hcl packer/win-server-2022/ \
    > /tmp/winsrv.log 2>&1 & echo $! > /tmp/winsrv.pid
  ```
- **Still `running` and log unchanged for >15 min** -> likely hung. Screenshot the
  console (see below) before killing. If dead, destroy 9002 and rebuild.

The install itself is fully solved; the only thing 9002 has never done is finish sysprep
and convert. If it fails, it fails at the very end.

## The one hazard that bit us repeatedly

NEVER kill a build by process name. `pkill -x packer` and even
`pgrep -f 'packer build.*<name>'` match the wrong things and killed a concurrent build
and their own shell respectively. ALWAYS capture the PID:
```
setsid nohup packer build ... > LOG 2>&1 & echo $! > PIDFILE
kill "$(cat PIDFILE)"   # only ever this
```

## Next templates, in order of least friction

1. **9005 kali-rolling** - public ISO, nothing gated. Good confidence-builder.
2. **9003 win11-client** - Windows path is now solved. Needs its own $WinPEDriver$ ISO:
   `ssh swc2026 '/root/build-winpe-driver-iso.sh --variant w11 --out /var/lib/vz/template/iso/virtio-winpe-drivers-w11.iso'`
   and point the win11 template's winpe_driver_iso_file at it. Watch for the same
   windows_iso_file / password / sysprep steps 9002 went through.
3. **9004 opnsense-267** - hardest and most fragile (timing-sensitive boot_command).
   Do it last.

Then: set the built machines `enabled: true` in lab.yaml and `tofu apply`.

## Debugging a guest (the single most useful tool)
```
ssh swc2026 'echo "screendump /tmp/x.ppm" | qm monitor <vmid> >/dev/null 2>&1'
scp swc2026:/tmp/x.ppm /tmp/ && python3 -c "from PIL import Image; Image.open('/tmp/x.ppm').save('/tmp/x.png')"
# then Read /tmp/x.png
ssh swc2026 'qm guest cmd <vmid> network-get-interfaces'   # once the agent is up
```

## Credentials live only on this workstation
`.envrc` and `packer/common.pkrvars.hcl` are gitignored and hold the API tokens, the
build SSH key and the Windows build password. They do NOT travel with the repo. On a
different machine, recreate them (bootstrap-host.sh --rotate-tokens to reissue tokens).

## Privileges found the hard way (all now in bootstrap-host.sh)
SDN.Use, VM.GuestAgent.Audit, Datastore.Allocate. If a NEW `403 Permission check failed
(<path>, <Priv>)` appears, add the named priv to build_privs(), scp the script up, and
re-run `bootstrap-host.sh --yes --skip-repos --skip-snippets --skip-network`.
