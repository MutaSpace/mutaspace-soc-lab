# fw-01 Firewall Build

This document records the installation and initial configuration of `fw-01`, the firewall/router VM for the MutaSpace SOC Lab.

The firewall VM is the first major lab VM because it controls how traffic moves between the Proxmox bridges and the internal SOC lab network.

---

## VM Purpose

`fw-01` acts as the firewall and router for the SOC lab.

It provides the network foundation for:

- WAN and LAN separation
- Internal SOC lab routing
- DHCP services
- Gateway services
- Firewall rule testing
- Network troubleshooting
- Future segmentation
- Controlled attack simulation

This VM helps the lab behave more like a real enterprise environment instead of placing every system on one flat network.

---

## Firewall Platform

The firewall platform selected for this build is:

```text
pfSense Community Edition
```

pfSense was selected because it supports firewall, routing, DHCP, DNS forwarding, interface assignment, and web-based administration.

---

## VM Configuration

| Setting | Value |
|---|---|
| VM Name | `fw-01` |
| Platform | pfSense CE |
| vCPU | 2 |
| Memory | 4GB |
| Disk | 20GB |
| Boot Media | Netgate Installer ISO |
| WAN Bridge | `vmbr0` |
| LAN Bridge | `vmbr1` |

---

## Interface Mapping

The firewall VM uses two virtual network interfaces.

| pfSense Interface | Virtual NIC | Proxmox Bridge | Purpose |
|---|---|---|---|
| WAN | `vtnet0` | `vmbr0` | Outside/upstream network |
| LAN | `vtnet1` | `vmbr1` | Internal SOC lab network |

The WAN interface connects to the upstream side of the lab.

The LAN interface connects to the internal SOC lab network.

---

## Network Configuration

Public documentation uses example values instead of live environment details.

| Interface | Example Address | Purpose |
|---|---|---|
| WAN | `10.0.0.x/24` | Upstream network address from the existing network |
| LAN | `10.10.10.1/24` | Internal SOC lab gateway |

The LAN interface was configured as:

```text
10.10.10.1/24
```

This address becomes the default gateway for VMs placed on the internal SOC lab bridge.

---

## DHCP Configuration

DHCP was enabled on the LAN interface.

The DHCP range is:

```text
10.10.10.100 - 10.10.10.200
```

This means internal lab VMs connected to `vmbr1` can automatically receive an IP address from pfSense.

---

## Installation Notes

The pfSense installation used the Netgate Installer ISO for AMD64 virtual machines.

During setup, the installer download was provided as a compressed `.iso.gz` file. The file needed to be extracted into a usable `.iso` before it could be attached to the VM as boot media.

The extraction process caused issues on macOS, so the file had to be handled carefully before the VM could boot from it successfully.

Lesson learned:

Installer format matters during VM creation. Even when the correct installer is downloaded, the file still has to be prepared in a format the hypervisor can boot from.

---

## Boot Issue

The VM originally displayed:

```text
Boot failed: Could not read from CDROM
No bootable device
```

Root cause:

```text
The installer file was still compressed and Proxmox could not boot it as a CD/DVD image.
```

Resolution:

```text
Extract the .iso.gz file into a real .iso file.
Upload the extracted .iso to Proxmox.
Attach the .iso to the fw-01 CD/DVD drive.
Set CD/DVD first in boot order for installation.
```

Lesson learned:

- Installer files may need to be extracted or prepared before a VM can boot from them.

---

## Memory Issue

After installation, the firewall VM showed memory usage above the assigned 2GB.

The VM memory was increased from:

```text
2048 MB
```

to:

```text
4096 MB
```

This resolved instability during the first boot process.

Lesson learned:

Minimum requirements may work, but giving infrastructure VMs more breathing room can prevent confusing behavior during installation and first boot.

---

## Installation Result

pfSense installed successfully and booted from the virtual hard disk.

The ISO was detached after installation so the VM could boot into the installed system.

The pfSense console confirmed:

```text
WAN -> vtnet0
LAN -> vtnet1
```

The LAN interface was changed from the default address to the SOC lab gateway address:

```text
10.10.10.1/24
```

---

## Validation Checklist

| Validation Item | Status |
|---|---|
| pfSense ISO obtained | Completed |
| ISO extracted successfully | Completed |
| ISO uploaded to Proxmox | Completed |
| `fw-01` VM created | Completed |
| WAN connected to `vmbr0` | Completed |
| LAN connected to `vmbr1` | Completed |
| pfSense installed | Completed |
| ISO detached after install | Completed |
| VM booted from hard disk | Completed |
| WAN assigned to `vtnet0` | Completed |
| LAN assigned to `vtnet1` | Completed |
| LAN IP set to `10.10.10.1/24` | Completed |
| DHCP enabled on LAN | Completed |
| DHCP range set | Completed |
| Test VM receives DHCP address | Pending |
| Test VM can ping gateway | Pending |
| Test VM can reach internet | Pending |
| DNS resolution works | Pending |

---

## Troubleshooting Lessons

This build reinforced several important troubleshooting lessons:

- Boot errors are not always VM configuration problems.
- Installer files must be in the correct format.
- A compressed `.iso.gz` file is not the same as an extracted `.iso`.
- VM memory should be reviewed when a service behaves unexpectedly.
- Network interface mapping should be documented immediately.
- WAN and LAN interfaces should not be guessed.
- One change should be made at a time and then validated.

---

## Why This Matters

The firewall VM creates the network foundation for the rest of the SOC lab.

Future systems will depend on this firewall for routing, DHCP, DNS forwarding, segmentation, and controlled traffic flow.

This step teaches that cybersecurity tools depend on infrastructure. Before alerts, detections, dashboards, and investigations can work, the network must be designed and validated.

---

## Learning Reflection

Building `fw-01` showed that firewall setup is not just a checkbox.

It requires understanding how Proxmox bridges, virtual NICs, WAN interfaces, LAN interfaces, DHCP, gateways, and boot media all work together.

This is the first real infrastructure service in the MutaSpace SOC Lab.

The lab now has a network control point.
