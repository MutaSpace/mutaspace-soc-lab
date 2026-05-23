# MutaSpace SOC Lab

This repository documents the design, build, and development of the MutaSpace SOC Lab, a Proxmox-based cybersecurity lab focused on SOC analyst training, detection engineering, virtual networking, SIEM operations, endpoint telemetry, infrastructure troubleshooting, and hands-on cybersecurity education.

This lab is intentionally documented end-to-end, including hardware decisions, architecture choices, configuration steps, troubleshooting, validation, mistakes, rebuilds, and lessons learned. The goal is to reflect real-world cybersecurity and infrastructure work rather than a perfect lab environment.

The MutaSpace SOC Lab is also a learning-by-doing environment. I learn best by building, breaking, troubleshooting, and explaining what happened. This lab is designed to support that process while also becoming a teaching environment for MutaSpace learners.

---

## Lab Overview

The MutaSpace SOC Lab is being built to simulate a practical security operations environment where learners can work with real tools, real systems, and realistic investigation workflows.

The lab is designed to support:

- Proxmox virtualization
- Virtual networking concepts
- Proxmox bridge configuration
- WAN and LAN separation
- Firewall and routing controls
- DNS troubleshooting
- Linux administration
- Windows administration
- Active Directory services
- Wazuh SIEM deployment
- Wazuh agent enrollment
- Suricata network monitoring
- Endpoint telemetry collection
- Log analysis
- Detection engineering
- Python automation
- Incident simulation
- Service troubleshooting
- Infrastructure debugging
- Systemd service analysis
- Learner-ready SOC scenarios

The purpose of the lab is to help learners move beyond theory and practice the kind of work expected in real cybersecurity roles.

---

## Prototype to Official Build

The first version of the lab was a prototype.

It served its purpose by helping validate the idea, test Proxmox, explore virtual networking, and understand what a hands-on SOC learning environment would need.

The prototype was not a failure. It was the learning phase.

After working through the original setup, it became clear that the next version needed stronger hardware, cleaner documentation, better planning, and more room to support realistic SOC workflows.

The lab is now being rebuilt on a dedicated custom PC designed for virtualization, security monitoring, learner scenarios, and research-driven experimentation.

This reflects an important real-world skill: knowing when to stop patching a fragile environment and rebuild correctly with better architecture, stronger documentation, and clearer validation.

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

## Why Hardware Capacity Matters

A SOC lab is not one computer doing one job.

It is one physical system running many virtual systems at the same time. Each virtual machine needs CPU, memory, storage, and network resources.

The custom PC needs enough capacity to support:

- Proxmox as the hypervisor
- A firewall/router VM
- A Wazuh SIEM VM
- A Suricata sensor VM
- Windows endpoint VMs
- Linux endpoint/server VMs
- Kali for controlled attack simulation
- Active Directory services
- Research and analysis VMs
- Snapshots, templates, and lab resets

Hardware decisions affect how stable, scalable, and realistic the lab can become.

---

## Planned Architecture

The first version of the lab will include the following systems:

| VM | Purpose |
|---|---|
| `fw-01` | Firewall/router VM |
| `dc-01` | Active Directory domain controller and DNS server |
| `wazuh-01` | SIEM and alerting platform |
| `sensor-01` | Suricata network IDS |
| `win-client-01` | Windows endpoint with telemetry |
| `ubuntu-app-01` | Linux target/server |
| `ubuntu-analyst-01` | Ubuntu analyst workstation |
| `kali-01` | Controlled attack simulation VM |
| `untrusted-01` | Trust-boundary research VM |
| `nlp-01` | Phishing/NLP research VM |

---

## Planned Network Design

The lab will use Proxmox bridges to separate management traffic from lab traffic.

The first planned network design includes:

| Bridge | Purpose |
|---|---|
| `vmbr0` | Proxmox management network and external access |
| `vmbr1` | Internal SOC lab LAN |
| `vmbr2` | Isolated or untrusted lab network |

This separation helps teach virtual networking concepts and mirrors real enterprise infrastructure principles.

---

## Why Network Segmentation Matters

Network segmentation is important because not every system should be able to freely communicate with every other system.

In this lab:

- The Proxmox host should remain protected.
- The firewall/router VM should control lab traffic.
- SOC tools should monitor activity without exposing the management network.
- Attack simulation systems should remain controlled and isolated.
- Learner systems should generate realistic telemetry without putting the host at unnecessary risk.

This design helps teach how enterprise environments separate management, user, server, monitoring, and untrusted traffic.

---

## Key Learning Areas

This lab is designed to teach both technical skills and troubleshooting habits.

The build process will teach:

- Hardware preparation
- BIOS checks
- Proxmox installation
- Storage planning
- SSD usage strategy
- Resource allocation
- Proxmox bridge configuration
- WAN versus LAN separation
- Virtual NIC concepts
- pfSense interface assignments
- DHCP configuration
- LAN gateway setup
- Firewall basics
- Windows Server installation
- Static IP configuration
- Active Directory installation
- DNS setup
- Domain creation
- Ubuntu installation
- Netplan configuration
- Linux administration
- Windows administration
- Wazuh server deployment
- Wazuh indexer, server, and dashboard concepts
- Wazuh agent onboarding
- Linux agent enrollment
- Windows agent enrollment
- Telemetry validation
- Failed login event generation
- File integrity monitoring
- Windows event analysis
- Service manipulation events
- Account creation events
- Custom Wazuh rules
- MITRE ATT&CK mapping
- Alert tuning
- False positive analysis
- Python automation
- Wazuh log parsing
- Alert enrichment
- IP reputation checking
- Small SOC automation scripts
- Architecture documentation
- Change logs
- Technical project summaries

---

## SOC Lab Research Areas

This lab also supports independent cybersecurity education and SOC lab research.

Research areas include:

- Low-cost SOC cyber ranges
- Detection engineering as a learning outcome
- Telemetry confidence
- Alert tuning
- SIEM telemetry
- Phishing detection
- Phishing and NLP analysis
- Trust boundaries in virtualized environments
- Reproducible cybersecurity education
- Learner performance in hands-on SOC scenarios

The goal is to study how a practical, affordable lab can help learners build real cybersecurity skill.

---

## Core Lab Tools

The lab will use a combination of infrastructure, monitoring, endpoint, and analysis tools.

| Tool | Purpose |
|---|---|
| Proxmox VE | Hypervisor used to run the virtual lab |
| pfSense | Firewall/router for network segmentation |
| Windows Server | Active Directory, DNS, and domain services |
| Ubuntu Server | Linux servers and analyst systems |
| Wazuh | SIEM, alerting, endpoint monitoring, and detection engineering |
| Suricata | Network intrusion detection |
| Kali Linux | Controlled attack simulation |
| Sysmon | Windows endpoint telemetry |
| Python | Automation, parsing, enrichment, and analysis |
| GitHub | Documentation and portfolio tracking |

---

## Wazuh Architecture

Wazuh will be used as the main SIEM and endpoint monitoring platform.

The lab will teach how Wazuh components communicate:

| Component | Purpose |
|---|---|
| Wazuh Server | Receives and analyzes security data |
| Wazuh Indexer | Stores and indexes alert data |
| Wazuh Dashboard | Provides the web interface for viewing alerts |
| Wazuh Agent | Runs on endpoints and sends telemetry to the server |

Understanding this architecture is important because SIEM tools are not one single thing. They are made of services that collect, process, store, and display security data.

---

## Why DNS Is Critical

DNS is one of the most important services in this lab.

Many cybersecurity and infrastructure problems are actually DNS problems.

DNS affects:

- Active Directory domain joins
- Windows authentication
- Linux domain integration
- Wazuh agent communication
- Hostname resolution
- Internal service discovery
- SIEM log clarity
- Troubleshooting accuracy

If DNS is broken, systems may appear offline, agents may fail to enroll, domain joins may fail, and logs may become harder to understand.

This lab will intentionally document DNS troubleshooting because it is one of the most important skills for infrastructure and SOC work.

---

## Troubleshooting Philosophy

This lab is not only about getting commands to work.

It is about learning how to think through problems.

Troubleshooting should follow a clear process:

1. Identify what should be happening.
2. Identify what is actually happening.
3. Check the simplest possible cause first.
4. Confirm network connectivity.
5. Confirm DNS resolution.
6. Check service status.
7. Read logs.
8. Change one thing at a time.
9. Validate the result.
10. Document what was learned.

The goal is to build the habit of thinking like an analyst and infrastructure troubleshooter.

---

## Realistic Troubleshooting Scenarios

This lab will include realistic troubleshooting scenarios such as:

| Scenario | Skill Practiced |
|---|---|
| VM cannot reach the internet | Network routing and gateway troubleshooting |
| VM can ping IPs but not hostnames | DNS troubleshooting |
| Linux service fails to start | `systemctl` and journal analysis |
| Wazuh dashboard does not load | Service dependency troubleshooting |
| Wazuh agent fails to enroll | Agent-server communication and DNS validation |
| Windows endpoint does not send logs | Agent status and event log troubleshooting |
| Suricata sees no traffic | Sensor placement and interface validation |
| Domain join fails | DNS and Active Directory troubleshooting |
| Alerts are too noisy | False positive analysis and tuning |
| Expected alert does not fire | Rule logic and log source validation |

Each troubleshooting scenario should document:

- The problem
- The expected behavior
- The actual behavior
- The investigation steps
- The root cause
- The fix
- The lesson learned

---

## Current Architecture

**Infrastructure**

- Hypervisor: Proxmox VE
- Hostname: `mutaspace-soc-node01`
- Filesystem: `ext4`
- Target Disk: `/dev/nvme0n1`
- Management Access: Proxmox web interface

**Security Note:** Public documentation uses example values and placeholders. Real credentials, public IP addresses, MAC addresses, SSH keys, API tokens, and sensitive screenshots should never be published.

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
- How WAN and LAN separation works in a virtual lab
- How virtual NICs connect VMs to different networks
- Why DNS is critical in enterprise and SOC environments
- How Active Directory depends on DNS
- How SIEM components communicate
- How endpoint telemetry reaches a SIEM
- How network telemetry supports investigations
- How detection rules are written, tested, and tuned
- How false positives affect SOC workflows
- How logs reveal system behavior
- How systemd services are managed and troubleshot
- How Python can support SOC automation
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

- A prototype is valuable when it helps clarify what the real build needs.
- Hardware capacity matters when a lab depends on multiple virtual machines.
- Cable management and hardware validation are part of the learning process.
- BIOS validation should happen before installing services.
- Proxmox web access confirms that the host is reachable on the management network.
- DNS must be correct before many enterprise services will work.
- Install order matters more than expected.
- Rebuilding can be better than continuing to patch a fragile environment.
- Documentation during failure is just as valuable as documentation during success.
- A lab should teach troubleshooting, not just installation.

---

## Version 1 Definition of Done

Version 1 is complete when the lab has:

- Custom PC assembled and validated
- Proxmox installed and accessible
- Network bridges configured
- Firewall/router VM installed
- Active Directory and DNS configured
- Wazuh installed
- At least one Windows endpoint sending logs
- At least one Linux endpoint sending logs
- Suricata generating alerts
- One custom Wazuh rule
- One false-positive tuning journal
- One learner-ready SOC scenario
- One Python automation script
- One research progress summary

---

## Roadmap

### Infrastructure Foundation

- Proxmox host baseline
- Storage review
- Repository configuration
- Initial Proxmox updates
- Virtual network design
- Network bridge configuration
- pfSense firewall/router deployment

### Enterprise Services

- Windows Server deployment
- Active Directory installation
- DNS configuration
- Domain creation
- Windows endpoint setup
- Ubuntu analyst VM setup
- Linux administration and troubleshooting

### Monitoring and Detection

- Wazuh server deployment
- Wazuh indexer setup
- Wazuh dashboard setup
- Linux agent enrollment
- Windows agent enrollment
- Telemetry validation
- Suricata deployment
- Sysmon integration

### Detection Engineering

- Failed login detection
- File integrity monitoring
- Windows event analysis
- Service manipulation detection
- Account creation event detection
- Custom Wazuh rules
- MITRE ATT&CK mapping
- Alert tuning
- False positive analysis

### Automation and Analysis

- Python log parsing
- Alert enrichment
- IP reputation checking
- Small SOC automation scripts
- Technical summaries
- Change logs
- Architecture diagrams

### Learner Scenarios

- Failed login investigation
- Phishing triage
- Network reconnaissance investigation
- Suspicious account creation
- Service manipulation investigation
- Basic incident report writing

---

## Future Expansion Ideas

Future expansions may include:

- TheHive for case management
- Shuffle SOAR for automation
- Suricata for network detection
- Kali Linux for controlled attack simulation
- Sysmon for Windows telemetry
- Sigma rules for detection logic
- Velociraptor for endpoint visibility
- Zeek for network analysis
- Python security tooling
- Threat intelligence integrations
- Additional Windows endpoints
- Additional Linux endpoints
- Active Directory attack and defense scenarios
- More advanced phishing analysis
- More learner-ready investigation scenarios

---

## Documentation

This repository is a living project.

Documentation will be added as the lab evolves, with a focus on clarity, reproducibility, troubleshooting, and learning.

The goal is for this repository to be useful to multiple audiences:

- Beginners who want to understand how SOC labs are built
- Students who need hands-on cybersecurity practice
- Educators designing practical cybersecurity labs
- Recruiters or employers reviewing technical portfolio work
- Cybersecurity professionals interested in Proxmox-based SOC lab design
- MutaSpace learners using the lab for guided training