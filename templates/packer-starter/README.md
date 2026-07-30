# packer-starter — a Proxmox Packer skeleton, with the traps already mapped

A copy-out starting point for building golden templates on Proxmox with Packer, taken
from a lab where all six of these templates are built, cloned and running in anger.

**The code is the smaller half of what is here.** The valuable half is the comments: this
kit is derived from a Windows 11 template that took **25 builds** to get right, and nearly
every non-obvious failure is written down at the point in the file where it bites. Read
the comments before you "simplify" anything — several of the strangest-looking lines are
load-bearing and are marked as such.

---

## What you get

| Directory | Builds | Notes |
|---|---|---|
| `win11-client/` | Windows 11 (client SKU) | The hard one. Read the Windows section below. |
| `win-server-2022/` | Windows Server 2022 | Same shape, materially easier — see why below. |
| `ubuntu-server-2404/` | Ubuntu Server 24.04 | autoinstall over the Packer HTTP server. |
| `ubuntu-desktop-2404/` | Ubuntu Desktop 24.04 | as above, with a desktop seed. |
| `kali-rolling/` | Kali Rolling | Debian preseed. |
| `opnsense-267/` | OPNsense appliance | Seeds a `config.xml`, so a build comes up API-ready with no console steps. |
| `shared/` | helper scripts | answer-file validator, Windows ISO remaster, VirtIO driver ISO builder. |

## Adopting it

1. Copy the directories you want into `packer/` in your project.
2. Copy `common.pkrvars.hcl.example` → `packer/common.pkrvars.hcl` and fill in the two
   values that cannot be defaulted:
   - **`build_bridge`** — a bridge that serves DHCP and can reach the internet.
   - **`http_bind_address`** — the address on your workstation the build VM can route
     back to. **If your workstation has several interfaces (Docker, VPN, libvirt), this
     MUST be pinned** or the installer hangs with no error.
3. Copy each template's `*.pkrvars.hcl.example` → `*.pkrvars.hcl`.
4. Wire `shared/validate-answer-files.sh` into pre-commit if you build Windows.
5. **Change `template_vmid` and `template_name`** in each `*.pkr.hcl` you keep. They are
   hardcoded locals, not variables — deliberately, because in the project this came from
   the VMID is a contract that OpenTofu clones by number. In a new project they will
   collide with whatever already occupies 9000–9005, so edit them before your first build.
6. Search for `example` / `pve-node01` / `example.local` and replace with your own names.

Credentials come from the environment (`PKR_VAR_*`); no varfile in this kit contains one,
and none should in yours.

`iso_file` and `virtio_win_iso_file` are **commented out** in the common varfile on
purpose — see the note beside them about a `windows_iso_file` name collision. All six
templates validate without them.

### This kit was adopted and built before it was published

Not a claim, a test: it was copied into an empty project, wired up per the steps above,
and used to build `tpl-starter-ubuntu` on real hardware — `A template was created: 9100`,
17m39s, from `packer init` to a converted template. All six templates pass
`packer validate` in that clean project.

That trial is also what found the OPNsense `lab_yaml_path` bug below. Validation alone
would not have caught it; copying the kit out did.

---

## ⭐ Windows: the rules that cost 25 builds

If you take nothing else from this kit, take this section.

### 1. Pick ONE account model. Never both.

Every maintained public Windows-client Packer template does exactly one of:

- **A** — build as the built-in `Administrator`, with **no** `<LocalAccounts>`; or
- **B** — build as a dedicated local admin, with **no** `<AdministratorPassword>`.

This kit is **Camp B**. Doing both is what broke the original build for days: setting
`AdministratorPassword` enables the built-in account for OOBE, and **client Windows
disables it again when OOBE finishes** — by design, per the `Accounts: Administrator
account status` policy, whose effective default is *Disabled on client, Enabled on
Server*. That is also the entire reason `win-server-2022` builds easily and
`win11-client` does not.

### 2. The build gets ONE WinRM shell. Spend it on the work.

Shortly after WinRM first answers, Windows stops granting **new** shells; every attempt
returns `Couldn't create shell: http response error: 401 - invalid content type`. A shell
**already running** is unaffected — one ran for 3m39s straight through the cutoff and
completed sysprep.

So the template:

- ships the provisioner scripts **on the seed CD** (`cd_content`) instead of uploading
  them — every `file` provisioner costs a shell;
- avoids `environment_vars`, which makes Packer upload a separate env-vars script;
- sets **`skip_clean = true`**, because after a provisioner returns Packer opens *another*
  shell to delete what it uploaded. That one line is the difference between a finished
  template and a build that completes sysprep and then throws itself away.

### 3. `RunSynchronousCommand` exiting non-zero ABORTS Windows Setup

The console shows *"The computer restarted unexpectedly or encountered an unexpected
error"* — identical to a malformed answer file, even when the XML is perfect. If you add
one, wrap it so it cannot fail (`try/catch` + explicit `exit 0`) and do not have it touch
the CD, which has no reliable drive letter during `specialize`.

### 4. Placement decides survival: first-boot machinery belongs in the IMAGE

**Anything registered before OOBE completes is wiped when it does** — scheduled tasks,
directories under `C:\ProgramData`, the lot. Measured three separate times.

Cloud-init user-data runs during the clone's `specialize` pass, on the wrong side of that
line. It will happily log `$env:COMPUTERNAME` as the *template's* name, because the machine
has no identity yet — and at that moment it has no usable network either, so
`winrm quickconfig` and even an explicit `winrm create Listener` both fail.

The fix is a task registered by `99-sysprep.ps1` **before sysprep**, dormant in the image,
firing on the clone. This kit ships two, both self-unregistering:

| Task | Job |
|---|---|
| `ExampleEnsureWinRM` | wait for real IPv4, flip Public→Private, create the HTTP listener |
| `ExampleRemovePackerProfile` | delete the leftover build-account profile |

⚠️ The clone's cloud-init must **not** register these — its registration starts with
`Unregister-ScheduledTask`, which would delete the template's working task and replace it
with one that is then wiped.

⚠️ **`RunOnce` does not work** for this: it fires at the first *interactive* logon, and
nobody logs into a headless VM. Use `AtStartup` with a SYSTEM principal.

### 5. sysprep

- `/unattend:` **must point at a path with no spaces**. Passing
  `'/unattend:"C:\Program Files\..."` as one element of a `-ArgumentList` array gets
  re-quoted by PowerShell, sysprep rejects the command line, and then raises a **modal
  dialog** nobody can dismiss — so the build hangs forever with no output. Stage the file
  somewhere space-free first.
- **Never use `-Wait` without a deadline.** `99-sysprep.ps1` waits with a timeout, then
  kills sysprep and prints `setuperr.log` into the Packer log — which is the difference
  between a legible failure and a silent hang.
- Inject `<SkipRearm>1</SkipRearm>` into the `generalize` pass. Without it, generalize
  calls `SLReArmWindows` and can fail with `0xC004F075`; with evaluation media it also
  spends one of a very small number of lifetime rearms **per build**.
- `/quit`, not `/shutdown`, on `proxmox-iso`: that builder has no `shutdown_command` and
  stops the VM through the API after the last provisioner returns.
- Trust `Sysprep_succeeded.tag` and the exit code. `GeneralizationState` reads the *other*
  way round from what people assume — `7` means "clean, not generalised"; `3`/`4` means it
  has run.

### 6. Debugging a Windows build

`packer build -on-error=abort` — **without it Packer destroys the VM on failure, taking
the logs with it.** Then, on the host:

```bash
LOOP=$(losetup --find --show --partscan --read-only /dev/pve/vm-9003-disk-1)  # base-* once templated
mount -t ntfs-3g -o ro "${LOOP}p3" /mnt/w
tail -40 /mnt/w/Windows/Panther/setuperr.log                      # Setup / specialize / OOBE
tail -40 /mnt/w/Windows/System32/Sysprep/Panther/setuperr.log     # sysprep itself
umount /mnt/w; losetup -d "$LOOP"
```

`blkid` on that partition is also a free BitLocker check — `TYPE="BitLocker"` means Windows
encrypted itself and sysprep will never finish. `PreventDeviceEncryption` in the
`specialize` pass stops it.

`PACKER_LOG=1` is worth reaching for sooner than feels necessary: it is what finally showed
a provisioner running for 3m39s and returning 5973 bytes of output on a build whose UI
suggested nothing had run at all.

---

## Linux and the appliance

Comparatively uneventful, and included so a mixed estate starts from one place:

- **Ubuntu** uses autoinstall served by Packer's HTTP server — hence the
  `http_bind_address` warning above, which is the single most common cause of "the
  installer just sits there".
- **Kali** uses a Debian preseed in the same shape.
- **OPNsense** seeds a `config.xml` so the appliance boots API- and SSH-ready. This is the
  pattern worth stealing: an appliance that needs console clicks is an appliance that
  cannot be rebuilt unattended.

  ⚠️ It is the **only** template here that reads an external inventory, because seeding
  DHCP reservations means knowing the addressing of the machines around it. Point
  `lab_yaml_path` at your own file, or at the bundled `lab.example.yaml`:

  ```bash
  packer build -var 'lab_yaml_path=../lab.example.yaml' \
    -var-file=packer/common.pkrvars.hcl packer/opnsense-267
  ```

  It used to hard-code `../../lab.yaml`, which meant every reference failed with
  `Unsupported attribute` the moment the kit was copied anywhere else — a message that
  reads like a broken template rather than a missing file. If you are not building
  OPNsense, delete that directory and `lab.example.yaml`; nothing else reads them.

---

## Provenance and honesty

Extracted from a working Proxmox lab on 2026-07-30. Everything here has built and cloned
successfully on real hardware; the Windows template was rebuilt **four consecutive times**
to prove it was reproducible rather than lucky, and a clone was taken from nothing to
domain-joined and monitored with no manual step.

What is **not** carried over: that project's `lab.yaml`, its OpenTofu module, its Ansible,
and its host-specific addressing. This is a Packer starting point, not a lab.

Two things it inherits that you should know about:

- The Windows evaluation media is **registration-gated**. There is no stable URL to pin,
  so `windows_iso_file` refers to a file you upload to Proxmox by hand. A fresh clone of
  this kit cannot build Windows without your own media, and the built image cannot be
  redistributed. That is a licence constraint, not an oversight.
- One unexplained intermittent remains: the Cloudbase-Init MSI download occasionally
  stalls for 30+ minutes between provisioners. Adding a timeout and retry to that
  download would be a sensible first improvement.
