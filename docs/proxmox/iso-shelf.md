# ISO Shelf

The installer media the MutaSpace SOC Lab builds from, where each file comes from, and the SHA256
of the exact copy on this host.

---

## What This Document Is For

Packer builds six golden templates. Three of them (Ubuntu Server, Ubuntu Desktop, Kali) can fetch
their own installer over HTTPS. Three of them cannot:

- **Windows Server 2022 Evaluation** and **Windows 11 Enterprise Evaluation** sit behind a
  Microsoft registration form. There is no stable, unauthenticated URL to pin.

  > **Licensing — this decides what you can share.** These are *evaluation* editions. The
  > license permits evaluation use, but it does **not** grant redistributing a built image.
  > That means the Ubuntu, Kali and OPNsense templates can be copied between hosts freely,
  > and the Windows ones **cannot** — every operator downloads their own eval ISO here and
  > builds the Windows templates on their own host. This is a license constraint, not a
  > technical one; the reproducible Packer recipe is exactly what makes it painless. The
  > evaluation clock (180 days for Server, 90 for the client) is a separate matter tracked
  > in [../iac/decisions.md](../iac/decisions.md) D-03.

- **OPNsense** publishes its DVD image bzip2-compressed. Proxmox cannot boot a compressed image, so
  the file has to be decompressed on the host before Packer ever sees it — which means the artifact
  Packer boots is not the artifact upstream published a checksum for.

Those files are acquired by hand, uploaded to the `local` datastore once, and then referenced from
the Packer templates as `local:iso/<filename>.iso`. Nothing in this repository can verify them
automatically, so this document is where the verification lives.

**This file is one half of a cross-file contract.** `scripts/preflight.sh` carries a hard-coded list
of the filenames it expects to find on the shelf, and the `*_iso_file` variable defaults in
`packer/*/` carry the same names. If you rename a file, three places have to change together:

| Where | What |
|---|---|
| `docs/proxmox/iso-shelf.md` | this table |
| `scripts/preflight.sh` | `DEFAULT_ISO_SHELF` |
| `packer/*/` | the `windows_iso_file` / `virtio_win_iso_file` / `opnsense_iso_file` defaults |

---

## The Shelf

Upload target: the `local` datastore, which on a default Proxmox install is a directory storage
carved out of the root logical volume at `/var/lib/vz/template/iso/`.

| Filename on `local:iso` | What it is | Source | SHA256 |
|---|---|---|---|
| `windows-server-2022-eval.iso` | Windows Server 2022 Evaluation, 180-day | Microsoft Evaluation Center (registration required) | *(record after download)* |
| `windows-11-enterprise-eval.iso` | Windows 11 Enterprise Evaluation, 90-day | Microsoft Evaluation Center (registration required) | *(record after download)* |
| `virtio-win-0.1.271.iso` | VirtIO drivers + guest agent for Windows | Fedora `archive-virtio/virtio-win-0.1.271/` | *(record after download)* |
| `OPNsense-26.7-dvd-amd64.iso` | OPNsense 26.7 installer, **decompressed** | OPNsense mirror, `.iso.bz2` then `bunzip2` | *(record after decompression)* |

The SHA256 column is deliberately empty in the committed copy of this file. **Do not paste a hash
you have not computed on this host.** A checksum copied from a blog post is worse than no checksum,
because it looks like verification and is not. Fill the column in on the machine, from the file that
is actually there.

---

## Watch The Root Volume, Not The Thin Pool

`local` is roughly **96 GB** on a default 2 TB Proxmox install, and it is where ISOs, cloud-init
snippets, snapshot RAM state and `vzdump` backups all land by default. The shelf above is about
**26 GB** once the Windows media is on it.

The LVM-thin pool that holds VM disks is not the constraint here. The root volume is. Running it out
of space does not fail cleanly — snippet uploads start failing, which looks like a cloud-init
problem rather than a disk-space problem.

```bash
df -h /var/lib/vz
ls -lh /var/lib/vz/template/iso/
```

---

## Acquiring Each File

### Windows Server 2022 Evaluation

Download from the Microsoft Evaluation Center. It requires a form, so there is no `curl` recipe.
Rename the download to `windows-server-2022-eval.iso` — the Packer default expects that name, and
Microsoft's own filename changes.

```bash
# on the Proxmox host, after uploading through the web UI or scp
cd /var/lib/vz/template/iso
sha256sum windows-server-2022-eval.iso
```

The licence is a real constraint on the lab and worth understanding rather than working around: it
is 180 days, and it must **activate over the internet within the first 10 days** or the machine
starts shutting itself down. That is why the firewall's seeded configuration carries a rule letting
`10.10.10.10` out to anywhere. See `packer/opnsense-267/README.md`.

### Windows 11 Enterprise Evaluation

Same process, renamed to `windows-11-enterprise-eval.iso`. 90-day licence, two rearms, no in-place
conversion to a full edition — a rebuild is the only path out.

### virtio-win-0.1.271.iso

```bash
cd /var/lib/vz/template/iso
curl -fLO https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.271/virtio-win-0.1.271.iso
sha256sum virtio-win-0.1.271.iso
```

**Fetch from the versioned `archive-virtio/` directory, not `stable-virtio/` or `latest-virtio/`.**
Those two are moving 301 redirects, so "stable" means a different build every month and a template
that built last week may not build today. 0.1.271 is pinned deliberately: 0.1.285 and 0.1.292 carry
a `vioscsi` read-retry regression.

### OPNsense 26.7

This is the awkward one.

```bash
cd /var/lib/vz/template/iso
curl -fLO https://mirror.dns-root.de/opnsense/releases/26.7/OPNsense-26.7-dvd-amd64.iso.bz2
curl -fLO https://mirror.dns-root.de/opnsense/releases/26.7/OPNsense-26.7-checksums-amd64.sha256

# Verify the COMPRESSED artifact against the project's published checksums.
sha256sum -c --ignore-missing OPNsense-26.7-checksums-amd64.sha256

bunzip2 OPNsense-26.7-dvd-amd64.iso.bz2

# Now compute the checksum of the file Packer will actually boot, and record it below.
sha256sum OPNsense-26.7-dvd-amd64.iso
```

Note the asymmetry. The project publishes a checksum for the `.bz2`, and that is the one worth
verifying against upstream — it proves the download. The decompressed `.iso` has **no published
checksum**, because upstream never distributes it. The value you compute yourself is only useful as
a *tripwire on rebuild*: record it here, and if it ever differs, something changed locally.

---

## Verifying The Shelf

`scripts/preflight.sh` checks that every expected filename is present on the datastore before any
build starts. It does not check checksums — it cannot, because it has no trusted values to compare
against, and inventing some would be exactly the kind of fake validation this repository avoids.

```bash
./scripts/preflight.sh
```

To re-verify by hand after filling in the table above:

```bash
cd /var/lib/vz/template/iso
sha256sum -c mutaspace-iso-shelf.sha256   # a file you generate from this table
```

---

## What Has Not Been Verified

At the time of writing, **nothing in this table has been downloaded or hashed.** The Proxmox host
does not exist yet; this document was authored alongside the infrastructure code so that the shelf
has somewhere to be recorded the moment it is stocked.

The filenames are real commitments — they are what `preflight.sh` and the Packer defaults expect —
but the SHA256 column, the file sizes, and the assertion that any of these URLs still resolve are
all unverified. Fill them in from the machine, and correct anything here that turns out to be wrong.

---

## Learning Reflection

The interesting thing about this document is that it exists because of a gap between two ideas that
usually travel together: *pinning* and *verifying*.

Infrastructure-as-code culture treats a pinned version as if it were a verified artifact. Pin the
version, get the same bytes. That holds for a container image with a digest, or a Terraform provider
with a lock file. It does not hold here. The Windows ISOs cannot be pinned at all — they are behind
a form, and Microsoft rotates the filename. The OPNsense image *can* be pinned upstream, but the
file Packer boots is a locally-produced derivative of it, so the upstream checksum stops applying at
exactly the moment the artifact becomes usable.

Both cases end in the same place: a human has to look at a file, write down what it was, and compare
later. That is not a failure of automation, it is a boundary of it — and the honest response is to
give the manual step a documented home rather than to pretend the pin covered it.

The second thing worth noticing is where the pressure lands. The obvious storage worry on a
hypervisor is "will the VM disks fit", and the answer is a 2 TB thin pool, comfortably. The actual
constraint is the 96 GB root volume that nobody sizes on purpose, holding 26 GB of installer media
alongside the snippets that cloud-init depends on. The resource that runs out is rarely the one that
was planned.
