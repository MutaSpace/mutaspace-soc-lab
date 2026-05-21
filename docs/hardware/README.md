# Hardware Documentation

This folder documents the custom PC hardware used to run the MutaSpace SOC Lab.

The hardware matters because this lab is built on virtualization. Every virtual machine needs CPU, memory, storage, and network resources. If the host does not have enough capacity, the lab will become slow, unstable, or difficult to expand.

## Purpose

The purpose of this folder is to document:

- The custom PC parts selected for the official lab host
- Why each part was important to the build
- How the hardware supports Proxmox virtualization
- How the system was assembled and validated
- What future hardware upgrades may be needed

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

## Why Hardware Capacity Matters

A SOC lab is not one computer doing one job.

It is one physical system running many virtual systems at the same time. The custom PC needs enough resources to support:

- Proxmox as the hypervisor
- A firewall/router VM
- A Wazuh SIEM VM
- A Suricata sensor VM
- Windows endpoint VMs
- Linux server/endpoint VMs
- Kali for controlled attack simulation
- Research and analysis VMs
- Snapshots, templates, and lab resets

## Hardware Learning Goals

By documenting this hardware build, the builder should learn how to explain:

1. Why CPU cores and threads matter for virtualization.
2. Why RAM affects how many virtual machines can run at once.
3. Why NVMe storage is preferred for VM disks.
4. Why cooling matters for long-running lab workloads.
5. Why a reliable power supply matters.
6. Why hardware validation should happen before installing services.
7. Why documentation makes a lab easier to rebuild or troubleshoot.

## Current Hardware Status

The custom PC has been assembled and successfully reached BIOS.

The system confirmed:

- CPU detected
- 64GB RAM detected
- NVMe storage detected
- CPU fan and pump readings detected
- CPU temperature stable during BIOS validation
- Proxmox installer successfully booted
