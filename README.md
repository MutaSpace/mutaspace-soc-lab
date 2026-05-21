# MutaSpace SOC Lab

The MutaSpace SOC Lab is a hands-on cybersecurity lab environment designed to support practical learning, SOC analyst training, detection engineering, security monitoring, and cybersecurity education.

This repository documents the build from the ground up so that beginners, students, educators, recruiters, and cybersecurity professionals can follow the process clearly.

The goal is not only to build a lab, but to understand it, validate it, document it, and make it useful for learning.

---

## Project Status

The MutaSpace SOC Lab is being rebuilt from the ground up as a custom PC-powered cybersecurity lab, training platform, and research environment.

The previous lab was intentionally wiped because the project had outgrown the original experimental setup. That first lab was valuable because it helped validate the idea, test Proxmox, explore virtual networking, and understand what a hands-on SOC learning environment could become.

It was not a failure.

It was the prototype.

The new lab is being rebuilt on a custom PC because MutaSpace is ready to support more serious work, including detection engineering, Wazuh SIEM operations, Suricata network monitoring, Windows and Linux endpoint telemetry, phishing/NLP research, trust-boundary experiments, learner scenarios, snapshots, templates, and reproducible documentation.

---

## Lab Purpose

This lab supports three connected goals:

1. **MutaSpace training**  
   Build a hands-on SOC lab where learners can practice real cybersecurity work.

2. **Independent research**  
   Study low-cost SOC cyber ranges, detection engineering as a learning outcome, telemetry confidence, and reproducible cybersecurity education.

3. **SOC lab research alignment**  
   Support work involving SIEM telemetry, phishing detection, trust boundaries, alert tuning, learner workflows, and cybersecurity training design.

---

## Official Host Direction

The official lab runs on a custom PC designed for virtualization.

This machine is the main Proxmox host for the MutaSpace SOC Lab.

### Confirmed Parts

| Category | Selected Part |
|---|---|
| Motherboard | GIGABYTE B650 AORUS Elite AX |
| CPU | AMD Ryzen 9 7900X |
| PSU | MSI MAG A850GL PCIE5 850W |
| RAM | Silicon Power DDR5 64GB, 2 x 32GB, 6000 MT/s |
| Case | CORSAIR 3500X RS ARGB Mid-Tower |
| CPU Cooler | Arctic Liquid Freezer III Pro 360 A-RGB |
| Storage | Silicon Power 2TB UD90 NVMe Gen4 |

### Planned Future Additions

| Category | Future Addition |
|---|---|
| RAM | Upgrade to 128GB later if needed |
| Storage | Add second 2TB NVMe |
| Backup | Add external SSD/HDD or Proxmox Backup Server |
| Power | Add UPS battery backup |
| Network | Add dual-port NIC and managed switch later if needed |

---

## Planned Lab Architecture

The first version of the lab will include:

| VM | Purpose |
|---|---|
| `fw-01` | Firewall/router VM |
| `wazuh-01` | SIEM and alerting platform |
| `sensor-01` | Suricata network IDS |
| `win-client-01` | Windows endpoint with telemetry |
| `ubuntu-app-01` | Linux target/server |
| `kali-01` | Controlled attack simulation VM |
| `untrusted-01` | Trust-boundary research VM |
| `nlp-01` | Phishing/NLP research VM |
| `dc-01` | Future Active Directory domain controller |

---

## Learning Goals

By rebuilding this lab, the builder should learn how to explain:

1. Why hardware capacity matters for virtualization.
2. Why Proxmox is used as the hypervisor.
3. How network bridges separate lab traffic.
4. How SIEM, endpoint telemetry, and network telemetry work together.
5. How detection rules are written, tested, and tuned.
6. How false positives affect SOC work.
7. How learner scenarios can measure real cybersecurity skill.
8. How documentation makes a lab reproducible.
9. How a cybersecurity lab can support both training and research.

---

## Build Philosophy

This project follows a simple standard:

```text
Build it.
Understand it.
Validate it.
Document it.
Teach it.
Research it.
```

Every major step should produce evidence, documentation, and a learning reflection.

---

## Version 1 Definition of Done

Version 1 is complete when the lab has:

1. Custom PC assembled and validated.
2. Proxmox installed.
3. Proxmox web interface successfully accessed.
4. Network bridges configured.
5. Firewall/router VM installed.
6. Wazuh installed.
7. At least one Windows endpoint sending logs.
8. At least one Linux endpoint sending logs.
9. Suricata generating alerts.
10. One custom Wazuh rule.
11. One false-positive tuning journal.
12. One learner-ready SOC scenario.
13. One research progress summary.

---

## Current Build Status

The MutaSpace SOC Lab has officially moved from prototype planning into custom hardware deployment.

The prototype environment helped validate the direction of the project. It served its purpose by allowing early testing of Proxmox, virtual networking ideas, SOC tooling concepts, and documentation structure.

The next phase required stronger infrastructure, so the lab is now being rebuilt on a dedicated custom PC designed to support a more realistic SOC training and research environment.

### Current Phase

**Phase 02: Proxmox Host Installation and Validation**

Status: Completed  
Milestone reached: Proxmox VE installed and successfully accessed through the web interface

---

## Confirmed Hardware and Proxmox Validation

The custom SOC lab host successfully reached BIOS and confirmed:

- GIGABYTE B650 AORUS Elite AX motherboard detected
- AMD Ryzen 9 7900X detected
- 64GB DDR5 RAM detected
- 2TB NVMe storage detected
- CPU fan and pump readings detected
- CPU temperature stable during BIOS validation
- Proxmox VE installer successfully booted from USB
- Proxmox VE installed to the internal NVMe drive
- Proxmox web interface successfully accessed from another machine

---

## Proxmox Management Configuration

The Proxmox host was configured with a static management address so it can be accessed from another device on the same network.

> **Security Note:** The values below are documented as lab examples. Do not publish real credentials, public IP addresses, MAC addresses, SSH keys, API tokens, or screenshots containing sensitive management information.

| Setting | Value |
|---|---|
| Hostname | `mutaspace-soc-node01` |
| Management IP | `<LAB_MANAGEMENT_IP>/24` |
| Example Management IP | `10.0.0.50/24` |
| Gateway | `<LAB_GATEWAY_IP>` |
| Example Gateway | `10.0.0.1` |
| DNS | `<DNS_SERVER>` |
| Example DNS | `1.1.1.1` |
| Management Interface | `<PROXMOX_MANAGEMENT_INTERFACE>` |
| Example Management Interface | `nic0` |
| Filesystem | `ext4` |
| Target Disk | `/dev/nvme0n1` |
| Web Interface | `https://<LAB_MANAGEMENT_IP>:8006` |
| Example Web Interface | `https://10.0.0.50:8006` |

---

## Learning Goals for This Phase

By the end of this phase, the builder should understand:

- How to select compatible hardware for a virtualization-based SOC lab
- How to assemble a custom PC safely
- How to validate CPU, RAM, storage, fans, and cooling in BIOS
- How to distinguish between fan power, ARGB, front panel, USB, and PSU cables
- How to install Proxmox VE onto a dedicated host machine
- How to configure a static management IP for Proxmox
- How to access the Proxmox web interface from another device
- Why Ethernet is preferred over Wi-Fi for virtualization hosts
- Why successful web access confirms that the host is reachable on the management network

---

## Immediate Next Steps

The next work will focus on validating and preparing Proxmox before creating any virtual machines.

### Step 1: Confirm Proxmox Dashboard Health

Check that Proxmox correctly sees:

- CPU
- Memory
- Storage
- Network interface
- Node status
- System uptime

This confirms that the host is stable after installation.

### Step 2: Review Storage

Review how Proxmox configured the internal NVMe drive.

The goal is to understand:

- Where ISO files will be stored
- Where VM disks will be stored
- How much usable space is available
- How storage will be organized before VMs are created

### Step 3: Update Proxmox Repositories

Update the repository configuration so the system can receive updates correctly.

This step will be documented carefully because repository errors are common for new Proxmox users.

### Step 4: Run Initial System Updates

Run the first Proxmox update after repository settings are reviewed.

This helps make sure the host is current before building lab services.

### Step 5: Create the First Proxmox Baseline Document

Document the clean starting point of the host before any virtual machines are created.

This baseline should include:

- Proxmox version
- Node name
- Storage status
- Network status
- Hardware detected
- Current phase
- Notes from installation

### Step 6: Plan the First Virtual Network Layout

Before creating virtual machines, plan the first network layout.

This will include:

- Management network
- Lab network
- Firewall/router placement
- Future SIEM and sensor placement
- Which systems should be isolated from each other

### Step 7: Create the First VM Plan

After the network layout is approved, the first VM plan will be created.

The first VM will likely be the firewall/router VM because it will control how lab traffic moves.