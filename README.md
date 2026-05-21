# MutaSpace SOC Lab

This repository documents the design, build, and development of the MutaSpace SOC Lab, a Proxmox-based cybersecurity lab focused on SOC analyst training, detection engineering, network monitoring, endpoint telemetry, and hands-on cybersecurity education.

This lab is intentionally documented end-to-end, including hardware decisions, configuration choices, troubleshooting, validation, and lessons learned. The goal is to reflect real-world cybersecurity and infrastructure work rather than a perfect lab environment.

---

## Lab Overview

The MutaSpace SOC Lab is being built to simulate a practical security operations environment where learners can work with real tools, real systems, and realistic investigation workflows.

The lab is designed to support:

- Proxmox virtualization
- Segmented virtual networks
- Firewall and routing controls
- Wazuh SIEM operations
- Suricata network monitoring
- Windows endpoint telemetry
- Linux endpoint telemetry
- Controlled attack simulation
- Detection engineering
- Phishing and NLP analysis
- Trust-boundary experiments
- Learner-ready SOC scenarios

The purpose of the lab is to help learners move beyond theory and practice the kind of work expected in real cybersecurity roles.

---

## Prototype to Official Build

The first version of the lab was a prototype.

It served its purpose by helping validate the idea, test Proxmox, explore virtual networking, and understand what a hands-on SOC learning environment would need.

The prototype was not a failure. It was the learning phase.

After working through the original setup, it became clear that the next version needed stronger hardware, cleaner documentation, better planning, and more room to support realistic SOC workflows.

The lab is now being rebuilt on a dedicated custom PC designed for virtualization, security monitoring, learner scenarios, and research-driven experimentation.

---

## Official Lab Host

The official MutaSpace SOC Lab runs on a custom PC built for virtualization.

| Category | Selected Part |
|---|---|
| Motherboard | GIGABYTE B650 AORUS Elite AX |
| CPU | AMD Ryzen 9 7900X |
| PSU | MSI MAG A850GL PCIE5 850W |
| RAM | Silicon Power DDR5 64GB, 2 x 32GB, 6000 MT/s |
| Case | CORSAIR 3500X RS ARGB Mid-Tower |
| CPU Cooler | Arctic Liquid Freezer III Pro 360 A-RGB |
| Storage | Silicon Power 2TB UD90 NVMe Gen4 |

This hardware was selected to support multiple virtual machines, long-running lab workloads, security monitoring tools, snapshots, templates, and future expansion.

---

## Planned Architecture

The first version of the lab will include the following systems:

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

## Completed Milestones

- Custom PC assembled
- System successfully reached BIOS
- CPU detected
- 64GB RAM detected
- 2TB NVMe storage detected
- CPU fan and pump readings detected
- CPU temperature validated in BIOS
- Proxmox VE installer successfully booted
- Proxmox VE installed to the internal NVMe drive
- Proxmox web interface successfully accessed from another device

---

## Current Architecture

**Infrastructure**

- Hypervisor: Proxmox VE
- Hostname: `mutaspace-soc-node01`
- Filesystem: `ext4`
- Target Disk: `/dev/nvme0n1`
- Management Access: Proxmox web interface

**Security Note:** Public documentation uses example values and placeholders. Real credentials, public IP addresses, MAC addresses, SSH keys, API tokens, and sensitive screenshots should not be published.

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

## In Progress

- Proxmox dashboard validation
- Storage review
- Repository configuration
- Initial system updates
- Baseline host documentation
- Virtual network design

---

## Learning Goals

By building this lab, the builder should learn how to explain:

- Why hardware capacity matters for virtualization
- Why Proxmox is used as the hypervisor
- How virtual networks and bridges separate lab traffic
- How SIEM, endpoint telemetry, and network telemetry work together
- How detection rules are written, tested, and tuned
- How false positives affect SOC workflows
- How learner scenarios can measure real cybersecurity skill
- How documentation makes a lab reproducible
- How a cybersecurity lab can support training and research

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

## Lessons Learned
A prototype is valuable when it helps clarify what the real build needs.
Hardware capacity matters when a lab depends on multiple virtual machines.
Cable management and hardware validation are part of the learning process.
BIOS validation should happen before installing services.
Proxmox web access confirms that the host is reachable on the management network.
Documentation should explain both what was done and why it matters.

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

## Road Map
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

