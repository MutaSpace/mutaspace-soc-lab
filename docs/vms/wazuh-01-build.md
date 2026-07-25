# wazuh-01 Wazuh Server Build

This document records the installation, configuration, and validation of `wazuh-01`, the Wazuh server for the MutaSpace SOC Lab.

`wazuh-01` provides the first SIEM and security monitoring platform for the lab.

---

## VM Purpose

`wazuh-01` is the centralized security monitoring server for the SOC lab.

This VM supports:

- Wazuh server deployment
- Wazuh dashboard access
- Security telemetry collection
- Future agent enrollment
- Windows endpoint monitoring
- Linux endpoint monitoring
- Alert review
- Log analysis
- Detection engineering practice
- Future custom rule development
- Future false-positive tuning

This system moves the lab from infrastructure setup into SOC monitoring.

---

## VM Configuration

| Setting | Value |
|---|---|
| VM Name | `wazuh-01` |
| VM ID | `104` |
| Operating System | Ubuntu Server |
| Role | Wazuh SIEM Server |
| vCPU | 4 |
| Memory | 8GB |
| Disk | 100GB |
| Network Bridge | `vmbr1` |
| Network Model | VirtIO |
| Network Role | Internal SOC LAN |

---

## Network Placement

`wazuh-01` is connected to:

```text
vmbr1
```

This places the Wazuh server inside the internal SOC lab network.

It is not connected directly to `vmbr0`.

```text
vmbr0 = Proxmox management / upstream network
vmbr1 = internal SOC lab network
```

---

## IP Configuration

`wazuh-01` was configured with a static IP address.

| Setting | Value |
|---|---|
| IP Address | `10.10.10.20` |
| Subnet | `/24` |
| Default Gateway | `10.10.10.1` |
| DNS Server | `10.10.10.10` |
| DNS Domain | `mutaspace.local` |

---

## Internal DNS Record

A DNS record was added on `dc-01` so the Wazuh server can be resolved by name.

| DNS Record | Value |
|---|---|
| Hostname | `wazuh-01` |
| FQDN | `wazuh-01.mutaspace.local` |
| IP Address | `10.10.10.20` |
| DNS Server | `dc-01` |

This allows internal systems to reach Wazuh by hostname instead of only by IP address.

---

## Wazuh Deployment Type

Wazuh was installed as an all-in-one deployment.

This means the main Wazuh components are running on the same VM.

| Component | Purpose |
|---|---|
| Wazuh Manager | Receives and analyzes agent data |
| Wazuh Indexer | Stores and indexes security events |
| Wazuh Dashboard | Provides the web interface |

An all-in-one deployment is appropriate for the first version of this lab because it is easier to install, validate, troubleshoot, and document.

---

## Installation Method

Wazuh was installed using the official Wazuh installation script.

The installation was completed from the `wazuh-01` Ubuntu Server terminal.

After installation, the Wazuh dashboard became accessible from the internal SOC lab network.

---

## Dashboard Access

The Wazuh dashboard was successfully accessed from the internal lab network.

Dashboard access was validated using:

```text
https://10.10.10.20
```

After the DNS record was added, dashboard access was also available by hostname:

```text
https://wazuh-01.mutaspace.local
```

A browser certificate warning is expected because the dashboard uses a certificate that is not trusted by the browser by default.

---

## Password Update

The default generated Wazuh dashboard password was changed after installation.

The updated password was validated by logging into the Wazuh dashboard successfully.

Passwords are not documented in this repository.

Security note:

```text
Do not commit Wazuh passwords, API keys, tokens, private keys, or screenshots showing credentials.
```

---

## Validation Commands

The following checks were used to validate `wazuh-01`.

### Confirm Hostname

```bash
hostname
```

Expected result:

```text
wazuh-01
```

---

### Confirm Network Configuration

```bash
ip a
```

Expected result:

```text
10.10.10.20
```

---

### Test Gateway Connectivity

```bash
ping 10.10.10.1
```

Result:

```text
Passed
```

---

### Test Domain Controller Connectivity

```bash
ping 10.10.10.10
```

Result:

```text
Passed
```

---

### Test Internet Connectivity

```bash
ping 1.1.1.1
```

Result:

```text
Passed
```

---

### Test Public DNS Resolution

```bash
ping google.com
```

Result:

```text
Passed
```

---

### Test Internal Domain Resolution

```bash
nslookup mutaspace.local
```

Result:

```text
Passed
```

---

### Test Domain Controller Resolution

```bash
nslookup dc-01.mutaspace.local
```

Result:

```text
Passed
```

---

### Test Wazuh DNS Resolution

```bash
nslookup wazuh-01.mutaspace.local
```

Result:

```text
Passed
```

---

## Wazuh Service Validation

The Wazuh services were checked after installation.

Expected services:

```text
wazuh-manager
wazuh-indexer
wazuh-dashboard
```

Expected status:

```text
active (running)
```

---

## Validation Results

| Validation Item | Status |
|---|---|
| Ubuntu Server installed | Completed |
| Static IP configured | Completed |
| Gateway reachable | Completed |
| Domain controller reachable | Completed |
| Internet reachable | Completed |
| Public DNS resolution working | Completed |
| Internal DNS resolution working | Completed |
| DNS record added for `wazuh-01` | Completed |
| `wazuh-01.mutaspace.local` resolves | Completed |
| Wazuh installed | Completed |
| Wazuh dashboard accessible by IP | Completed |
| Wazuh dashboard accessible by hostname | Completed |
| Wazuh password updated | Completed |
| Dashboard login validated | Completed |

---

## Troubleshooting Notes

The Wazuh installation required careful command execution.

During the initial attempt, the install did not run correctly because the command was entered incorrectly and the installer script was not being called from the expected location.

The issue was resolved by identifying the mistake, correcting the command process, and completing the installation successfully.

Another issue occurred when `wazuh-01.mutaspace.local` did not resolve at first.

Root cause:

```text
The Wazuh server had a static IP, but no matching DNS record existed yet on dc-01.
```

Resolution:

```text
Create a DNS A record for wazuh-01 on dc-01 pointing to 10.10.10.20.
```

After the DNS record was added, name resolution worked correctly.

---

## Why This Matters

Wazuh is the first major SOC monitoring platform in the lab.

With Wazuh installed, the lab can now begin collecting endpoint telemetry, reviewing alerts, testing rules, and building detection engineering workflows.

This is the point where the lab begins moving from infrastructure into security operations.

---

## Learning Reflection

Building `wazuh-01` showed that SIEM deployment depends on strong infrastructure.

The firewall, internal bridge, DHCP, DNS, domain controller, and analyst workstation all supported this milestone.

A SIEM does not work in isolation. It depends on reliable systems, stable networking, correct DNS, reachable endpoints, and clean documentation.

The MutaSpace SOC Lab now has its first working security monitoring platform.
