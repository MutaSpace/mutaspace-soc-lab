# analyst-01 Build

This document records the installation, configuration, and validation of `analyst-01`, the Ubuntu analyst workstation for the MutaSpace SOC Lab.

`analyst-01` is the first analyst workstation in the lab. It provides a normal internal workstation for testing DNS, accessing lab services, performing Linux administration tasks, and later supporting SOC analyst workflows.

---

## VM Purpose

`analyst-01` was created to act as a Linux-based analyst workstation inside the internal SOC lab network.

This VM will support:

- Internal DNS testing
- Linux administration practice
- Network troubleshooting
- Future Wazuh dashboard access
- Future log review and analysis
- Future security tooling
- SOC analyst workflow practice

This system helps validate that internal client systems can communicate properly with the firewall, domain controller, internet, and internal DNS.

---

## VM Configuration

| Setting | Value |
|---|---|
| VM Name | `analyst-01` |
| VM ID | `103` |
| Operating System | Ubuntu Desktop 24.04 LTS |
| Role | Analyst Workstation |
| vCPU | 2 |
| Memory | 4GB |
| Disk | 40GB |
| Network Bridge | `vmbr1` |
| Network Model | VirtIO |
| Network Role | Internal SOC LAN |

---

## Network Placement

`analyst-01` is connected to:

```text
vmbr1
```

This places the VM inside the internal SOC lab network.

It is not connected directly to `vmbr0`.

```text
vmbr0 = Proxmox management / upstream network
vmbr1 = internal SOC lab network
```

The firewall/router VM `fw-01` provides gateway and DHCP services for this network.

---

## Internal Network Services

The internal SOC lab network currently uses:

| Service | System | Address |
|---|---|---|
| Gateway | `fw-01` pfSense LAN | `10.10.10.1` |
| DHCP | `fw-01` pfSense | `10.10.10.100 - 10.10.10.200` |
| DNS | `dc-01` | `10.10.10.10` |
| Active Directory Domain | `dc-01` | `mutaspace.local` |

---

## DNS Configuration

`analyst-01` receives its network settings from pfSense DHCP.

After `dc-01` was promoted to a domain controller, pfSense DHCP was updated so internal clients receive the domain controller as their DNS server.

Expected DNS settings on `analyst-01`:

```text
DNS Server: 10.10.10.10
DNS Domain: mutaspace.local
```

This allows `analyst-01` to resolve internal Active Directory names.

---

## Validation Commands

The following commands were used to validate the workstation.

### Check IP Address

```bash
ip a
```

Purpose:

Confirm that `analyst-01` received an internal SOC lab address from DHCP.

Expected result:

```text
10.10.10.x
```

---

### Confirm DNS Settings

```bash
resolvectl status
```

Expected result:

```text
Current DNS Server: 10.10.10.10
DNS Servers: 10.10.10.10
DNS Domain: mutaspace.local
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

### Test Domain Controller Name Resolution

```bash
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
| Ubuntu Desktop installed | Completed |
| VM connected to `vmbr1` | Completed |
| DHCP address received | Completed |
| Gateway reachable | Completed |
| Domain controller reachable | Completed |
| Internet reachable by IP | Completed |
| Public DNS resolution working | Completed |
| Internal DNS server received from DHCP | Completed |
| `mutaspace.local` resolves | Completed |
| `dc-01.mutaspace.local` resolves | Completed |

---

## Troubleshooting Notes

Initial network connectivity worked successfully.

The workstation could reach:

- pfSense gateway
- Domain controller
- Internet by IP
- Public DNS names

The only issue was internal domain name resolution.

At first, `analyst-01` was receiving pfSense as its DNS server instead of the domain controller. Because of that, internal Active Directory names did not resolve automatically.

The fix was to update pfSense DHCP so clients on the internal SOC LAN receive:

```text
DNS Server: 10.10.10.10
```

After renewing DHCP on `analyst-01`, internal DNS resolution worked.

---

## Why This Matters

`analyst-01` proves that a normal internal workstation can function inside the SOC lab network.

This is important because future analyst and endpoint systems need working:

- DHCP
- Gateway access
- Internet routing
- Internal DNS
- Domain name resolution
- Communication with infrastructure systems

This workstation will also be useful for future Wazuh access, Linux administration, log analysis, and SOC workflow practice.

---

## Learning Reflection

Building `analyst-01` showed that internal workstation validation is an important step before adding security tooling.

A SOC lab needs more than servers. It also needs endpoints and analyst systems that behave like real machines on an internal network.

This VM confirmed that the internal SOC lab network, firewall, DHCP, DNS, and Active Directory name resolution are working together.
