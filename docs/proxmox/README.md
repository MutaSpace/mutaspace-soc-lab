# Proxmox Documentation

This folder documents the Proxmox setup for the MutaSpace SOC Lab.

Proxmox is the virtualization platform that allows one physical computer to run multiple virtual machines. In this lab, Proxmox is the foundation that will host the firewall, SIEM, network sensor, Windows endpoint, Linux endpoint, attack simulation VM, and research systems.

---

## What Proxmox Does in This Lab

Proxmox acts as the hypervisor.

A hypervisor is software that allows one physical machine to run multiple virtual machines. Each virtual machine behaves like its own computer, even though it is sharing the same physical hardware.

In the MutaSpace SOC Lab, Proxmox will allow the custom PC to run:

- Firewall/router VM
- Wazuh SIEM VM
- Suricata network sensor VM
- Windows endpoint VM
- Linux endpoint VM
- Kali attack simulation VM
- Active Directory and DNS services
- Analysis and research VMs

This makes it possible to build a realistic SOC environment without needing a separate physical computer for every system.

---

## Why Proxmox Was Selected

Proxmox was selected because it supports:

- Virtual machines
- Linux containers
- Virtual networking
- Network bridges
- Web-based management
- Snapshots
- Templates
- Local storage
- Future clustering options

For this lab, the most important features are virtual machines, network bridges, snapshots, and the web interface.

---

## Why Virtualization Matters

Virtualization is important because SOC labs need multiple systems.

A realistic security lab should include more than one machine. There should be systems that generate logs, systems that monitor logs, systems that route traffic, and systems that simulate attacks or suspicious behavior.

Without virtualization, each of those systems would require its own physical computer.

With Proxmox, one physical host can run many virtual systems.

This helps teach:

- Infrastructure design
- Network segmentation
- Firewall placement
- Endpoint monitoring
- SIEM deployment
- Log collection
- Troubleshooting
- Incident simulation

---

## Proxmox Concepts Used in This Lab

| Concept | Meaning |
|---|---|
| Node | The physical Proxmox host |
| VM | A virtual machine running inside Proxmox |
| Bridge | A virtual switch used to connect VMs to networks |
| Storage | The location where ISO files, VM disks, and backups are stored |
| ISO | An installation image used to install operating systems |
| Snapshot | A saved state of a VM that can be restored later |
| Template | A reusable VM base image |
| Console | Browser-based access to a VM screen |
| Management IP | The address used to access the Proxmox web interface |

---

## Proxmox Role in the SOC Lab

Proxmox is not the SIEM, firewall, or endpoint.

It is the platform that runs them.

The SOC tools will run inside virtual machines. Proxmox provides the environment where those virtual machines live.

This separation matters because it helps keep the lab organized:

- Proxmox manages the infrastructure.
- pfSense will manage routing and firewall rules.
- Wazuh will collect and analyze security data.
- Suricata will inspect network traffic.
- Windows and Linux endpoints will generate telemetry.
- Kali will support controlled attack simulation.

---

## Learning Goals

By working with Proxmox, the builder should learn how to explain:

- What a hypervisor is
- Why virtualization is useful for cybersecurity labs
- How one physical machine can run multiple virtual systems
- What a Proxmox node is
- What virtual machines are
- What Proxmox bridges do
- Why storage planning matters
- Why snapshots and templates are useful
- Why the management network should be protected

---

## Security Considerations

The Proxmox web interface controls the entire lab host. Access to Proxmox should be treated as sensitive.

Public documentation should not expose:

- Real credentials
- Public IP addresses
- MAC addresses
- SSH keys
- API tokens
- Sensitive screenshots
- Router details
- Port forwarding details

Example IP addresses may be used for documentation, but live environment details should be sanitized before publishing.

---

## Current Proxmox Status

Proxmox VE has been installed on the custom SOC lab host.

The Proxmox web interface has been successfully accessed from another device on the same network.

This confirms that the host is installed, reachable, and ready for baseline configuration.