# Internal DNS Validation

This document records the successful internal DNS validation for the MutaSpace SOC Lab.

The goal of this validation was to confirm that internal lab clients receive the domain controller as their DNS server and can resolve Active Directory domain names correctly.

---

## Validation Purpose

After `dc-01` was promoted to a domain controller, the lab needed to confirm that internal clients could use it for DNS.

This matters because Active Directory depends heavily on DNS.

If clients use the wrong DNS server, they may fail to:

- Resolve the internal domain
- Locate the domain controller
- Join the domain
- Authenticate properly
- Communicate with internal services
- Generate clean logs for future monitoring

---

## Systems Involved

| System | Role | IP Address |
|---|---|---|
| `fw-01` | pfSense firewall/router and DHCP provider | `10.10.10.1` |
| `dc-01` | Active Directory Domain Controller and DNS server | `10.10.10.10` |
| `analyst-01` | Ubuntu analyst workstation | DHCP address from `10.10.10.0/24` |

---

## Network Placement

All internal lab systems are connected through:

```text
vmbr1
```

`vmbr1` is the internal SOC lab bridge.

```text
vmbr0 = Proxmox management / upstream network
vmbr1 = internal SOC lab network
```

---

## DNS Design

The internal DNS design is:

```text
Internal clients -> dc-01 DNS -> upstream resolution as needed
```

The domain controller provides DNS for the Active Directory domain:

```text
mutaspace.local
```

---

## DHCP DNS Update

pfSense DHCP was updated so internal clients receive `dc-01` as their DNS server.

| DHCP Setting | Value |
|---|---|
| DHCP Server | `fw-01` pfSense |
| LAN Gateway | `10.10.10.1` |
| DNS Server handed to clients | `10.10.10.10` |
| DNS Domain | `mutaspace.local` |

This allows new clients on the internal SOC LAN to automatically use the domain controller for DNS.

---

## Ubuntu DNS Behavior

On Ubuntu, `resolvectl status` showed that `analyst-01` received the correct DNS settings.

Expected values:

```text
Current DNS Server: 10.10.10.10
DNS Servers: 10.10.10.10
DNS Domain: mutaspace.local
```

Ubuntu may show `127.0.0.53` during `nslookup` because Ubuntu uses `systemd-resolved` as a local DNS stub resolver.

That is normal.

The important part is that the upstream DNS server used by the interface is:

```text
10.10.10.10
```

---

## Validation Commands

The following commands were used from `analyst-01`.

### Confirm DNS Server

```bash
resolvectl status
```

Expected result:

```text
DNS Servers: 10.10.10.10
DNS Domain: mutaspace.local
```

---

### Resolve Internal Domain

```bash
nslookup mutaspace.local
```

Result:

```text
Passed
```

---

### Resolve Domain Controller

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
| pfSense DHCP updated | Completed |
| `analyst-01` renewed DHCP | Completed |
| `analyst-01` received DNS server `10.10.10.10` | Completed |
| `analyst-01` received DNS domain `mutaspace.local` | Completed |
| `mutaspace.local` resolved successfully | Completed |
| `dc-01.mutaspace.local` resolved successfully | Completed |
| Internal DNS path validated | Completed |

---

## Why This Matters

This confirms that the internal SOC lab now has a working identity and DNS foundation.

Future systems can use `dc-01` for internal name resolution.

This supports:

- Windows domain joins
- Linux domain integration
- Wazuh agent communication
- Cleaner hostname resolution
- More realistic SOC telemetry
- Better troubleshooting practice

---

## Troubleshooting Lesson

At first, `analyst-01` could reach the gateway, the internet, and public DNS, but it could not resolve the internal Active Directory domain.

The issue was that the client was receiving pfSense as DNS instead of the domain controller.

The fix was to update pfSense DHCP so internal clients receive:

```text
DNS Server: 10.10.10.10
```

After renewing DHCP on `analyst-01`, internal DNS resolution worked.

---

## Learning Reflection

This validation showed why DNS is one of the most important services in an enterprise-style lab.

Networking can appear to work while internal DNS is still wrong.

A system may ping the gateway, reach the internet, and resolve public websites, but still fail to resolve the internal domain.

For Active Directory environments, DNS must be correct before domain joins, authentication, monitoring, and detection work can be trusted.