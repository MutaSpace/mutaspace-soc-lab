# wazuh-01 Wazuh Server Plan

This document explains the plan for `wazuh-01`, the Wazuh server for the MutaSpace SOC Lab.

`wazuh-01` will become the main SIEM and security monitoring platform for the lab. It will collect, analyze, and display security telemetry from Windows, Linux, and future lab systems.

---

## VM Purpose

`wazuh-01` will provide centralized security monitoring for the SOC lab.

This VM will support:

- Wazuh server deployment
- Wazuh dashboard access
- Agent enrollment
- Windows endpoint monitoring
- Linux endpoint monitoring
- Security alerting
- Log analysis
- Detection engineering practice
- Future custom rules
- Future MITRE ATT&CK mapping
- Future false-positive tuning

This system is one of the core SOC tools in the lab.

---

## Why Wazuh Comes Next

The lab now has the infrastructure foundation needed for Wazuh:

- Proxmox is installed and working
- pfSense is routing the internal SOC LAN
- DHCP is working
- Internal DNS is working
- Active Directory is installed
- `analyst-01` can resolve internal domain names

Wazuh comes next because the lab is ready to begin collecting and analyzing telemetry.

---

## Planned Operating System

The planned operating system is:

```text
Ubuntu Server 22.04 LTS or Ubuntu Server 24.04 LTS
```

The preferred first choice is:

```text
Ubuntu Server 22.04 LTS
```

Reason:

Wazuh documentation and examples commonly reference Ubuntu Server 22.04 LTS, and it is a stable choice for a first SIEM deployment.

---

## Planned VM Configuration

| Setting | Value |
|---|---|
| VM Name | `wazuh-01` |
| Role | Wazuh Server |
| Operating System | Ubuntu Server 22.04 LTS |
| vCPU | 4 |
| Memory | 8GB minimum |
| Disk | 100GB minimum |
| Network Bridge | `vmbr1` |
| Network Model | VirtIO |
| Static IP | `10.10.10.20/24` |
| Gateway | `10.10.10.1` |
| DNS | `10.10.10.10` |

---

## Network Placement

`wazuh-01` will be connected to:

```text
vmbr1
```

This places Wazuh inside the internal SOC lab network.

It should not be connected directly to `vmbr0`.

```text
vmbr0 = Proxmox management / upstream network
vmbr1 = internal SOC lab network
```

---

## Planned IP Addressing

| System | Role | IP Address |
|---|---|---|
| `fw-01` | pfSense LAN gateway | `10.10.10.1` |
| `dc-01` | Domain Controller and DNS | `10.10.10.10` |
| `wazuh-01` | Wazuh Server | `10.10.10.20` |
| `analyst-01` | Ubuntu Analyst Workstation | DHCP address |
| DHCP Clients | General internal lab VMs | `10.10.10.100 - 10.10.10.200` |

`wazuh-01` should use a static IP address because agents and analysts need a stable address for communication and dashboard access.

---

## Planned Hostname

The planned hostname is:

```text
wazuh-01
```

After DNS is configured, the expected internal name will be:

```text
wazuh-01.mutaspace.local
```

---

## Wazuh Components

A Wazuh deployment includes several major components.

| Component | Purpose |
|---|---|
| Wazuh Server | Receives and analyzes agent data |
| Wazuh Indexer | Stores and indexes security data |
| Wazuh Dashboard | Web interface for alerts and monitoring |
| Wazuh Agents | Installed on endpoints to send telemetry |

For the first deployment, these components will be installed together on `wazuh-01`.

This is simpler for a lab and easier to validate before splitting components later.

---

## Why All-in-One First

An all-in-one Wazuh deployment means the server, indexer, and dashboard run on the same VM.

This is the best first step because it is:

- Easier to install
- Easier to troubleshoot
- Easier to document
- Good enough for a small lab
- More beginner-friendly

Later, the lab can explore separating Wazuh components if needed.

---

## Planned Access

The Wazuh dashboard will eventually be accessed from:

```text
analyst-01
```

Expected dashboard access format:

```text
https://wazuh-01.mutaspace.local
```

or:

```text
https://10.10.10.20
```

The exact port and URL will be documented after installation.

---

## Planned Agent Enrollment

Wazuh agents will eventually be installed on:

| System | Purpose |
|---|---|
| `dc-01` | Windows Server and Active Directory telemetry |
| `analyst-01` | Linux workstation telemetry |
| Future Windows client | Windows endpoint telemetry |
| Future Linux server | Linux server telemetry |

Agent enrollment will be documented separately after the Wazuh server is installed.

---

## Telemetry Goals

Wazuh should eventually collect:

- Windows security logs
- Windows system logs
- Windows authentication events
- Active Directory events
- Linux authentication logs
- Linux system logs
- File integrity monitoring data
- Service activity
- User activity
- Security alerts

This telemetry will support detection engineering and SOC investigation practice.

---

## Planned Validation Goals

The `wazuh-01` build is successful when:

- Ubuntu Server installs successfully
- Static IP is configured
- Hostname is set to `wazuh-01`
- Server can ping the pfSense gateway
- Server can ping `dc-01`
- Server can reach the internet
- Server can resolve public DNS names
- Server can resolve `mutaspace.local`
- Server can resolve `dc-01.mutaspace.local`
- Wazuh installs successfully
- Wazuh dashboard loads from `analyst-01`
- Initial login to the Wazuh dashboard works

---

## Common Beginner Mistakes

### Mistake: Under-provisioning Wazuh

Wazuh needs more resources than a basic Linux VM.

If the VM has too little memory or disk space, installation or indexing may fail.

### Mistake: Using DHCP for the Wazuh server

A SIEM server should have a static IP address.

Agents and analysts need a stable destination.

### Mistake: Installing agents before the server is validated

The Wazuh server should be installed and confirmed working before agents are deployed.

### Mistake: Ignoring DNS

If `wazuh-01` cannot resolve internal names, agent enrollment and dashboard access may become harder to troubleshoot.

### Mistake: Skipping snapshots

A snapshot should be taken before major install steps when possible.

This makes it easier to recover from failed installations.

---

## Troubleshooting Mindset

If Wazuh installation or access fails, ask:

1. Is `wazuh-01` connected to `vmbr1`?
2. Does it have the correct static IP?
3. Can it ping `10.10.10.1`?
4. Can it ping `10.10.10.10`?
5. Can it resolve `dc-01.mutaspace.local`?
6. Can it reach the internet?
7. Is the Wazuh service running?
8. Are the required ports listening?
9. Is the dashboard service running?
10. What do the Wazuh logs show?

The goal is to troubleshoot the system logically, not just rerun install commands.

---

## SOC Learning Value

Wazuh introduces the SOC monitoring layer.

It will help teach:

- SIEM deployment
- Agent enrollment
- Log collection
- Alert review
- Security telemetry
- Rule tuning
- False positives
- Detection engineering
- Incident investigation workflows

This is where the lab begins moving from infrastructure setup into security operations.

---

## Learning Reflection

`wazuh-01` will be the first major security monitoring platform in the MutaSpace SOC Lab.

The earlier infrastructure work matters because Wazuh depends on stable networking, DNS, routing, endpoints, and logs.

A SIEM is only useful when the systems around it are configured well enough to produce meaningful telemetry.