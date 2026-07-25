# dc-01 Domain Controller Build

This document records the installation, configuration, and validation of `dc-01`, the Windows Server domain controller for the MutaSpace SOC Lab.

`dc-01` provides Active Directory Domain Services and DNS for the internal SOC lab network.

---

## VM Purpose

`dc-01` is the domain controller for the internal SOC lab.

This VM provides:

- Active Directory Domain Services
- Internal DNS
- Centralized identity management
- Domain authentication
- A foundation for Windows endpoint administration
- Realistic Windows event generation for future SOC monitoring

This system moves the lab from basic network validation into enterprise-style infrastructure.

---

## VM Configuration

| Setting | Value |
|---|---|
| VM Name | `dc-01` |
| VM ID | `102` |
| Operating System | Windows Server 2022 Evaluation |
| Role | Domain Controller |
| vCPU | 2 |
| Memory | 4GB |
| Disk | 60GB |
| Disk Type | SATA |
| Network Bridge | `vmbr1` |
| Network Model | E1000 |
| Network Role | Internal SOC LAN |

---

## Network Placement

`dc-01` is connected to:

```text
vmbr1
```

This places the server inside the internal SOC lab LAN.

It is not connected directly to `vmbr0`.

```text
vmbr0 = Proxmox management / upstream network
vmbr1 = internal SOC lab network
```

---

## IP Configuration

`dc-01` was configured with a static IP address.

| Setting | Value |
|---|---|
| IP Address | `10.10.10.10` |
| Subnet Mask | `255.255.255.0` |
| Default Gateway | `10.10.10.1` |
| Preferred DNS | `10.10.10.10` |

The preferred DNS server points to `dc-01` because the server now provides DNS for the Active Directory domain.

---

## Domain Configuration

The Active Directory forest was created using the following domain:

```text
mutaspace.local
```

The NetBIOS domain name is:

```text
MUTASPACE
```

This domain is used only for the internal SOC lab environment.

---

## Installed Roles

The following Windows Server roles were installed:

| Role | Purpose |
|---|---|
| Active Directory Domain Services | Provides domain identity and authentication |
| DNS Server | Provides internal name resolution for the domain |

---

## Installation Notes

Windows Server 2022 Evaluation was installed using the ISO installer.

During installation, the Windows installer initially did not detect the virtual hard disk when the disk was configured with the original storage controller.

The disk was changed to SATA so Windows Server could detect it without additional storage drivers.

This kept the first domain controller build simple and allowed the lab to continue without introducing VirtIO driver troubleshooting during the initial Active Directory setup.

---

## Disk Detection Issue

The Windows Server installer originally showed:

```text
We couldn't find any drives.
```

Root cause:

```text
Windows Server did not have the required storage driver for the original virtual disk configuration.
```

Resolution:

```text
Change the virtual disk to SATA.
Restart the Windows Server installer.
Select the 60GB unallocated disk.
Allow Windows to create the required partitions automatically.
```

Lesson learned:

Using VirtIO can improve performance, but Windows may need additional drivers. For a first domain controller build, SATA is simpler and easier to validate.

---

## Initial Network Validation

Before installing Active Directory, the server was configured with a static IP and tested for network connectivity.

The following tests passed:

| Test | Result |
|---|---|
| Ping pfSense gateway `10.10.10.1` | Passed |
| Ping external IP `1.1.1.1` | Passed |
| Resolve external DNS name | Passed |

This confirmed that `dc-01` had working network connectivity before becoming a domain controller.

---

## Active Directory Promotion

After the AD DS and DNS roles were installed, `dc-01` was promoted to a domain controller.

Promotion settings:

| Setting | Value |
|---|---|
| Deployment Type | New forest |
| Root Domain Name | `mutaspace.local` |
| DNS Server | Enabled |
| Global Catalog | Enabled |
| Read Only Domain Controller | Disabled |

The server rebooted after promotion and became the first domain controller in the `mutaspace.local` domain.

---

## Post-Promotion DNS Update

After promotion, the DNS settings were updated so `dc-01` uses itself for DNS.

Final DNS setting:

```text
Preferred DNS server: 10.10.10.10
```

This is important because Active Directory relies on DNS records hosted by the domain controller.

---

## Validation Commands

The following commands were used to validate the domain controller.

### Confirm Hostname

```powershell
hostname
```

Expected result:

```text
dc-01
```

---

### Confirm IP Configuration

```powershell
ipconfig /all
```

Expected values:

```text
IPv4 Address: 10.10.10.10
Default Gateway: 10.10.10.1
DNS Servers: 10.10.10.10
```

---

### Test Gateway Connectivity

```powershell
ping 10.10.10.1
```

Result:

```text
Passed
```

---

### Test Internet Connectivity

```powershell
ping 1.1.1.1
```

Result:

```text
Passed
```

---

### Test Domain DNS Resolution

```powershell
nslookup mutaspace.local
```

Result:

```text
Passed
```

---

### Test Domain Controller DNS Resolution

```powershell
nslookup dc-01.mutaspace.local
```

Result:

```text
Passed
```

---

## Validation Results

| Validation Item | Status |
|---|---|
| Windows Server installed | Completed |
| Server renamed to `dc-01` | Completed |
| Static IP configured | Completed |
| Gateway connectivity confirmed | Completed |
| Internet connectivity confirmed | Completed |
| DNS resolution confirmed | Completed |
| AD DS role installed | Completed |
| DNS role installed | Completed |
| New forest created | Completed |
| Domain `mutaspace.local` created | Completed |
| Server promoted to domain controller | Completed |
| DNS updated to point to `dc-01` | Completed |
| Domain DNS resolution tested | Completed |
| Domain controller DNS resolution tested | Completed |

---

## Why This Matters

`dc-01` gives the SOC lab a realistic identity and DNS foundation.

Many SOC investigations involve identity activity, authentication events, failed logins, account changes, domain joins, and Windows security logs.

By adding Active Directory, the lab can now support more realistic Windows administration, endpoint monitoring, and detection engineering scenarios.

---

## Troubleshooting Lessons

This build reinforced several important lessons:

- A domain controller should use a static IP address.
- Active Directory depends heavily on DNS.
- Domain systems should use the domain controller for DNS.
- Windows Server may need storage drivers depending on the virtual disk type.
- Keeping the first build simple can reduce unnecessary troubleshooting.
- Network validation should happen before role installation.
- DNS validation should happen after promotion.

---

## Learning Reflection

Building `dc-01` showed how infrastructure supports cybersecurity operations.

A SOC lab is not only made of security tools. It also needs the systems those tools monitor.

Active Directory and DNS create realistic conditions for future Windows endpoint telemetry, Wazuh agent enrollment, authentication monitoring, and detection scenarios.

The MutaSpace SOC Lab now has a working identity foundation.
