# Custom PC Parts List

This document lists the hardware selected for the official MutaSpace SOC Lab host.

The SOC lab runs on a custom PC because the environment needs enough power to support multiple virtual machines, security tools, endpoint telemetry, network monitoring, snapshots, templates, and future expansion.

The goal of this build is not gaming performance.

The goal is virtualization, stability, learning, detection engineering, and hands-on cybersecurity training.

---

## Approved Hardware

| Category | Selected Part |
|---|---|
| Motherboard | GIGABYTE B650 AORUS Elite AX |
| CPU | AMD Ryzen 9 7900X |
| PSU | MSI MAG A850GL PCIE5 850W |
| RAM | Silicon Power DDR5 64GB, 2 x 32GB, 6000 MT/s |
| Case | CORSAIR 3500X RS ARGB Mid-Tower |
| CPU Cooler | Arctic Liquid Freezer III Pro 360 A-RGB |
| Storage | Silicon Power 2TB UD90 NVMe Gen4 |

---

## Motherboard

**Selected Part:** GIGABYTE B650 AORUS Elite AX

The motherboard is the foundation of the build. It determines the CPU platform, memory type, storage options, network support, expansion slots, and future upgrade path.

This motherboard was selected because it supports:

- AMD AM5 processors
- DDR5 memory
- Multiple M.2 NVMe drives
- 2.5GbE wired networking
- ATX form factor
- Future expansion

For a SOC lab, the motherboard matters because the lab needs stable networking, enough storage expansion, and enough memory support to grow over time.

---

## CPU

**Selected Part:** AMD Ryzen 9 7900X

The CPU provides the processing power for the Proxmox host and the virtual machines running inside it.

This CPU was selected because it provides:

- 12 cores
- 24 threads
- Strong virtualization performance
- Enough processing power for multiple lab systems

In this lab, the CPU will support workloads such as:

- Proxmox host operations
- Firewall/router VM
- Wazuh SIEM
- Suricata sensor
- Windows endpoints
- Linux endpoints
- Kali attack simulation VM
- Research and analysis VMs

A SOC lab needs a strong CPU because multiple systems may run at the same time.

---

## RAM

**Selected Part:** Silicon Power DDR5 64GB, 2 x 32GB, 6000 MT/s

RAM controls how many virtual machines can run at the same time.

This build starts with 64GB of DDR5 memory. The RAM was installed as a 2 x 32GB kit so the system can be upgraded later if needed.

This matters because every VM needs memory.

Examples:

- Wazuh needs memory.
- Windows needs memory.
- Linux needs memory.
- Kali needs memory.
- The firewall needs memory.
- Research tools need memory.

For this lab, 64GB is enough to begin the first full version of the SOC lab while still leaving room for future expansion.

---

## Storage

**Selected Part:** Silicon Power 2TB UD90 NVMe Gen4

Storage holds the Proxmox installation, virtual machines, ISO files, logs, templates, snapshots, and lab data.

An NVMe drive was selected because virtual machines perform better on fast storage.

This drive will initially support:

- Proxmox VE installation
- VM disks
- ISO storage
- Lab templates
- Early snapshots
- Initial Wazuh and endpoint data

A second NVMe drive may be added later if the lab needs more space for logs, datasets, snapshots, or research work.

---

## Power Supply

**Selected Part:** MSI MAG A850GL PCIE5 850W

The power supply provides stable power to the entire system.

This PSU was selected because it provides:

- 850W power capacity
- 80+ Gold efficiency
- Fully modular cabling
- Room for future expansion

A reliable power supply matters because the SOC lab may run for long periods. Stability is more important than appearance.

---

## Case

**Selected Part:** CORSAIR 3500X RS ARGB Mid-Tower

The case holds the system and supports airflow, cable management, cooling, and future expansion.

This case was selected because it supports:

- ATX motherboard installation
- 360mm liquid cooling
- Multiple fans
- Clean cable routing
- Future upgrades
- A clear build layout for documentation and teaching

The visual design also makes it easier to document the build through photos and videos.

---

## CPU Cooler

**Selected Part:** Arctic Liquid Freezer III Pro 360 A-RGB

The CPU cooler keeps the Ryzen 9 7900X stable during long-running workloads.

This cooler was selected because the SOC lab may run multiple VMs and services at the same time. Sustained workloads can create heat, so the CPU needs strong cooling.

Cooling matters because an unstable host can affect every VM running inside the lab.

---

## Hardware Capacity Summary

This build is designed to support the first version of the MutaSpace SOC Lab.

The expected starting capacity is:

| Use Case | Expected Capacity |
|---|---|
| Individual hands-on learners | 4 learners comfortably |
| Paired or team-based learners | 6 to 8 learners |
| Instructor-led demo | 10 or more learners observing |
| Full isolated student environments | Requires future scaling |

This first host is strong enough for the initial SOC lab build, but larger cohorts will require more RAM, additional storage, multiple lab hosts, or a team-based learning model.

---

## Future Hardware Expansion

Possible future upgrades include:

| Category | Future Addition |
|---|---|
| RAM | Upgrade to 128GB |
| Storage | Add a second 2TB NVMe |
| Backup | Add external backup storage or Proxmox Backup Server |
| Power | Add a UPS battery backup |
| Network | Add a dual-port NIC or managed switch |

These upgrades are not required for the first working version, but they may become useful as the lab grows.

---

## Learning Reflection

This hardware build teaches that a SOC lab is not just about installing tools.

The physical host determines what the lab can realistically support.

The CPU affects how many workloads can run.
The RAM affects how many VMs can stay powered on.
The storage affects performance, snapshots, and data retention.
The cooler affects long-term stability.
The power supply affects reliability.
The motherboard affects expansion and networking.

A strong SOC lab starts with understanding the system that runs it.
