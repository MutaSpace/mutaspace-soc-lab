# dc-01 Domain Controller Plan

This document explains the plan for `dc-01`, the Windows Server virtual machine that will provide Active Directory and DNS services for the MutaSpace SOC Lab.

`dc-01` will become one of the core infrastructure systems in the lab because many enterprise environments rely on centralized identity, authentication, and name resolution.

---

## VM Purpose

`dc-01` will act as the domain controller for the internal SOC lab network.

This VM will provide:

- Active Directory Domain Services
- Internal DNS
- Centralized identity management
- Domain authentication
- A foundation for Windows endpoint administration
- A realistic enterprise service for SOC monitoring

This system helps the lab move from basic networking into enterprise-style infrastructure.

---

## Why Active Directory Comes Next

Active Directory should be built early because many future lab systems can depend on it.

Active Directory will help support:

- Windows endpoint domain joins
- Centralized user accounts
- Authentication events
- Group Policy learning
- DNS troubleshooting
- Windows event log analysis
- Wazuh Windows agent testing
- Security event generation

A SOC analyst often investigates identity-related activity, so the lab needs a realistic identity service.

---

## Planned Operating System

The planned operating system is:

```text
Windows Server
```

The server will be promoted to a domain controller after installation.

---

## Planned VM Configuration

| Setting | Value |
|---|---|
| VM Name | `dc-01` |
| Role | Domain Controller |
| Operating System | Windows Server |
| vCPU | 2 to 4 |
| Memory | 4GB to 6GB |
| Disk | 60GB |
| Network Bridge | `vmbr1` |
| Network Type | Internal SOC LAN |
| Static IP | `10.10.10.10/24` |
| Gateway | `10.10.10.1` |
| DNS | `10.10.10.10` after DNS role is installed |

---

## Network Placement

`dc-01` will be connected to:

```text
vmbr1
```

This places the domain controller inside the internal SOC lab LAN.

It should not be connected directly to `vmbr0`.

```text
vmbr0 = Proxmox management / upstream network
vmbr1 = internal SOC lab network
```

The firewall/router VM `fw-01` will remain the gateway for the internal lab network.

---

## Planned IP Addressing

| System | Role | IP Address |
|---|---|---|
| `fw-01` | pfSense LAN gateway | `10.10.10.1` |
| `dc-01` | Domain Controller and DNS | `10.10.10.10` |
| DHCP Clients | General internal lab VMs | `10.10.10.100 - 10.10.10.200` |

`dc-01` should use a static IP address because DNS and domain services should not move around.

---

## Planned Domain

The planned internal lab domain is:

```text
mutaspace.local
```

This domain is for the internal lab only.

It should not be confused with a public website domain.

---

## DNS Plan

DNS is one of the most important parts of this VM.

After Active Directory is installed, `dc-01` will provide internal DNS for domain systems.

This matters because Active Directory depends heavily on DNS.

DNS will support:

- Domain controller discovery
- Domain joins
- Authentication
- Hostname resolution
- Internal service lookup
- Cleaner SIEM logs

---

## Important DNS Change

At first, pfSense provides DNS forwarding for the internal lab.

After `dc-01` is configured, domain-joined systems should use `dc-01` as their DNS server.

The planned DNS direction is:

```text
Domain systems -> dc-01 DNS -> pfSense/upstream DNS
```

This allows internal names to resolve through Active Directory while still allowing external internet names to resolve.

---

## Why DNS Is Critical

DNS problems can cause many confusing issues.

If DNS is wrong, the lab may experience:

- Domain join failures
- Login failures
- Group Policy failures
- Wazuh agent hostname confusion
- Windows event log confusion
- Internal service discovery problems

Many Active Directory problems are actually DNS problems.

This lab will document DNS carefully because it is one of the most important infrastructure skills for SOC work.

---

## Planned Active Directory Services

`dc-01` will provide:

| Service | Purpose |
|---|---|
| Active Directory Domain Services | Central identity and authentication |
| DNS | Internal name resolution |
| Domain Controller Role | Allows systems to join the domain |
| User and Computer Management | Supports Windows administration practice |

---

## Planned Validation Goals

The `dc-01` build is successful when:

- Windows Server installs successfully
- Static IP is configured
- Server can ping the pfSense gateway
- Server can reach the internet
- Server can resolve external DNS names
- Active Directory Domain Services installs successfully
- DNS role installs successfully
- Domain is created successfully
- Server reboots successfully after promotion
- Domain login works
- DNS resolves the internal domain
- Another VM can eventually join the domain

---

## Common Beginner Mistakes

### Mistake: Leaving the domain controller on DHCP

A domain controller should have a static IP address.

If the IP changes, clients may not know where to find DNS or Active Directory services.

### Mistake: Using the router as DNS for domain-joined systems

For Active Directory, domain systems should use the domain controller for DNS.

Using the wrong DNS server can prevent domain joins and authentication.

### Mistake: Building AD before validating the network

The internal network should work before Active Directory is installed.

This lab already validated `vmbr1`, DHCP, gateway access, internet access, and DNS using `test-client-01`.

### Mistake: Choosing a confusing domain name

The lab domain should be simple and internal.

This plan uses:

```text
mutaspace.local
```

---

## Troubleshooting Mindset

If Active Directory or DNS does not work, ask:

1. Is `dc-01` connected to `vmbr1`?
2. Does `dc-01` have the correct static IP?
3. Can `dc-01` ping `10.10.10.1`?
4. Can `dc-01` reach the internet?
5. Can `dc-01` resolve external names?
6. Is the DNS role installed?
7. Are clients using `dc-01` as DNS?
8. Can clients resolve the domain name?
9. Can clients find the domain controller?
10. What do the Windows event logs show?

The goal is to troubleshoot logically instead of guessing.

---

## SOC Learning Value

Active Directory creates valuable SOC learning opportunities.

It can generate logs related to:

- User logins
- Failed logins
- Account creation
- Password changes
- Group membership changes
- Domain joins
- Authentication failures
- Privilege-related activity

These events will be useful later when Wazuh and Windows telemetry are added.

---

## Learning Reflection

`dc-01` will move the lab closer to a real enterprise environment.

A SOC lab should not only contain security tools. It should also include the infrastructure those tools monitor.

Active Directory and DNS will help make the lab more realistic, more teachable, and more useful for detection engineering practice.
