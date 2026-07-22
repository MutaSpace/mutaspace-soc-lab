# Documentation Images

The illustrations in this folder are **AI-generated** (Higgsfield, Nano Banana Pro).
They are decorative and conceptual. They are not screenshots, not evidence, and not
a source of truth about the lab.

That distinction matters in a repository that otherwise treats its documentation as
a record of what was actually observed. Nothing here was photographed, captured from
a running system, or verified against hardware.

---

## Where Each Image Is Used

| File | Used by | Depicts |
|---|---|---|
| `hero-soc-lab.webp` | [`README.md`](../../README.md) | One host fanning out into the lab's VMs, isolated segment in amber |
| `network-segmentation.webp` | [`network-design.md`](../network/network-design.md) | The firewall as the only path between trusted and untrusted lanes |
| `proxmox-install.webp` | [`installation-and-access.md`](../proxmox/installation-and-access.md) | USB installer → hypervisor layer → web interface on `:8006` |
| `iac-pipeline.webp` | [`iac/README.md`](../iac/README.md) | One source file stamping out identical machines |
| `classroom-reset-cycle.webp` | [`scripts/README.md`](../../scripts/README.md) | Snapshot → break → reset |

---

## Diagrams Are Not Images

Anything carrying **real** lab facts — bridge names, IP addresses, VMIDs, NIC order —
is a [Mermaid](https://mermaid.js.org/) block in the Markdown, not a picture. Mermaid
renders natively on GitHub, diffs as text, and can be corrected when `lab.yaml`
changes.

Generated images are the wrong tool for that job: an image model will happily render
`vmbr0` as `vrnbr0`, and a diagram that has drifted from the code is worse than no
diagram. If a visual needs to state a fact, it belongs in Mermaid.

---

## Format

Source generations were 2K PNG (~4.5 MB each). They are committed as WebP, resized to
1600 px wide at quality 82 — about 332 KB for all five, down from 23.5 MB. A
documentation repository should not carry 23 MB of decoration.

To regenerate at a different size, the conversion was:

```python
from PIL import Image
im = Image.open(src).convert("RGB")
im = im.resize((1600, round(im.height * 1600 / im.width)), Image.LANCZOS)
im.save(dst, "WEBP", quality=82, method=6)
```

---

## Style

If more images are added, the set shares a deliberate look so the documentation reads
as one thing: deep navy background, cyan for trusted and routine elements, amber for
isolated, untrusted or host-side elements, flat vector shapes, no photorealism and no
people. The amber/cyan split is load-bearing rather than decorative — it matches the
trusted/untrusted split the lab itself teaches.
