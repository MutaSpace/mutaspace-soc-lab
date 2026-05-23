# Proxmox Host Baseline

This document records the clean starting point of the Proxmox host before virtual machines are created.

A baseline is important because it captures the state of the system before major changes are made. If something breaks later, the baseline helps show what the host looked like when it was first working.

---

## Baseline Purpose

The purpose of this baseline is to confirm that the Proxmox host is stable, reachable, and ready for lab development.

Before building VMs, the host should have:

- Proxmox installed
- Web interface access confirmed
- Hardware detected
- Storage reviewed
- Network status reviewed
- Repository configuration reviewed
- Initial updates completed
- No unnecessary VMs or services created yet

This helps make sure the lab starts from a known working state.

---

## Host Summary

| Item | Value |
|---|---|
| Host Role | Official MutaSpace SOC Lab Proxmox Host |
| Hostname | `mutaspace-soc-node01` |
| Hypervisor | Proxmox VE |
| Filesystem | `ext4` |
| Target Disk | `/dev/nvme0n1` |
| Management Access | Proxmox web interface |
| Web Interface Port | `8006` |

---

## Hardware Detected

The host successfully detected the expected hardware during BIOS and Proxmox validation.

| Component | Status |
|---|---|
| Motherboard | Detected |
| CPU | Detected |
| Memory | Detected |
| NVMe Storage | Detected |
| CPU Fan | Detected |
| CPU Pump | Detected |
| Network Interface | Detected |

---

## Hardware Summary

| Category | Selected Part |
|---|---|
| Motherboard | GIGABYTE B650 AORUS Elite AX |
| CPU | AMD Ryzen 9 7900X |
| RAM | 64GB DDR5 |
| Storage | 2TB NVMe Gen4 |
| Cooler | Arctic Liquid Freezer III Pro 360 A-RGB |
| PSU | MSI MAG A850GL PCIE5 850W |
| Case | CORSAIR 3500X RS ARGB Mid-Tower |

---

## Management Network

The Proxmox host uses a static management address.

The management network allows another device on the same network to access the Proxmox web interface.

Public documentation should use placeholders instead of live environment details.

| Setting | Public Documentation Value |
|---|---|
| Management IP | `<LAB_MANAGEMENT_IP>/24` |
| Example Management IP | `10.0.0.50/24` |
| Gateway | `<LAB_GATEWAY_IP>` |
| Example Gateway | `10.0.0.1` |
| DNS | `<DNS_SERVER>` |
| Example DNS | `1.1.1.1` |
| Web Interface | `https://<LAB_MANAGEMENT_IP>:8006` |
| Example Web Interface | `https://10.0.0.50:8006` |

---

## Storage Baseline

The internal NVMe drive is the first storage device for the lab.

At this stage, the storage is used for:

- Proxmox system files
- ISO image storage
- Virtual machine disks
- Templates
- Snapshots
- Early lab data

Before creating VMs, storage should be reviewed in the Proxmox web interface.

The builder should confirm:

- Available storage space
- Storage names
- Which storage location supports ISO uploads
- Which storage location supports VM disks
- Whether storage is local or thin-provisioned

---

## Repository Baseline

A fresh Proxmox installation may include enterprise repository settings.

For a non-subscription lab environment, repository settings should be reviewed before system updates.

The builder should understand:

- Proxmox uses repositories to receive updates.
- Enterprise repositories are intended for subscription users.
- No-subscription repositories are commonly used for lab environments.
- Repository configuration should be reviewed before running updates.
- Repository errors are common for new Proxmox users and should be documented.

Repository changes should be made carefully and documented.

---

## Update Baseline

Initial updates should be completed before building VMs.

Updating the host first helps make sure the lab starts from a current and stable system state.

Before creating VMs, confirm:

- Repository configuration has been reviewed.
- Package lists update successfully.
- System updates complete without major errors.
- The host reboots successfully after updates if needed.
- Web access still works after updates.

---

## Proxmox Dashboard Health Check

The Proxmox dashboard should be reviewed before VM creation.

The dashboard should confirm:

- Node is online
- CPU usage is normal
- Memory usage is normal
- Storage is visible
- Network interface is visible
- No unexpected critical errors are present

This is the first health check of the installed host.

---

## Why This Baseline Matters

A baseline gives the lab a known working starting point.

Without a baseline, it becomes harder to know whether a later issue came from:

- Hardware
- Proxmox installation
- Repository configuration
- Network settings
- Storage settings
- VM configuration
- Firewall rules
- Guest operating systems

A baseline supports better troubleshooting.

---

## Common Baseline Mistakes

### Mistake: Creating VMs before reviewing storage

If storage is not reviewed first, ISO files and VM disks may be placed in confusing or inefficient locations.

### Mistake: Updating before checking repositories

A fresh Proxmox installation may show repository errors if the default repository configuration is not appropriate for the environment.

### Mistake: Ignoring network settings

If the management IP, gateway, or DNS settings are wrong, the host may be difficult to access or update.

### Mistake: Skipping documentation

If the clean state is not documented, troubleshooting later becomes harder.

---

## Baseline Validation Checklist

| Validation Item | Status |
|---|---|
| Proxmox installed | Completed |
| Web interface accessible | Completed |
| Hostname configured | Completed |
| Static management address configured | Completed |
| Internal NVMe selected as install target | Completed |
| Hardware detected | Completed |
| Storage reviewed | Pending |
| Repository configuration reviewed | Pending |
| Initial updates completed | Pending |
| Dashboard health checked | Pending |
| Ready for VM planning | Pending |

---

## Learning Reflection

The Proxmox host baseline teaches that infrastructure work should not jump straight into building services.

Before creating firewalls, domain controllers, SIEMs, or endpoints, the host itself must be reviewed and understood.

A stable SOC lab starts with a stable hypervisor.