# test-client-01 Build

This document records the creation and use of `test-client-01`, a temporary Linux test VM used to validate the internal SOC lab network.

The goal of this VM was not to become a permanent production system. Its purpose was to confirm that `vmbr1`, pfSense DHCP, gateway routing, internet access, and DNS resolution were working before building the main lab systems.

---

## VM Purpose

`test-client-01` was created to test the internal SOC lab LAN.

This VM helped validate:

- Proxmox bridge `vmbr1`
- pfSense LAN gateway
- DHCP assignment
- Internet routing
- DNS resolution
- Basic internal lab connectivity

This test was important because future systems will depend on the same internal network.

---

## VM Configuration

| Setting | Value |
|---|---|
| VM Name | `test-client-01` |
| VM ID | `101` |
| Operating System | Ubuntu Linux |
| vCPU | 2 |
| Memory | 2GB |
| Disk | 20GB |
| Network Bridge | `vmbr1` |
| Network Role | Temporary internal network validation client |

---

## Network Placement

`test-client-01` was connected to:

```text
vmbr1
```

This placed the VM inside the internal SOC lab LAN.

It was intentionally not connected to `vmbr0`.

```text
vmbr0 = Proxmox management / upstream network
vmbr1 = internal SOC lab network
```

---

## Expected Network Behavior

Because `test-client-01` was connected to `vmbr1`, it was expected to receive network configuration from pfSense.

Expected behavior:

| Item | Expected Result |
|---|---|
| IP Address | `10.10.10.x` |
| Gateway | `10.10.10.1` |
| DHCP Source | `fw-01` pfSense LAN |
| Internet Access | Through pfSense |
| DNS Resolution | Working through pfSense/upstream DNS |

---

## Validation Commands

The following commands were used from the test VM.

### Check Network Address

```bash
ip a
```

Purpose:

Confirm that the VM received an internal lab IP address.

---

### Test Gateway Connectivity

```bash
ping 10.10.10.1
```

Purpose:

Confirm that the VM could reach the pfSense LAN gateway.

Result:

```text
Passed
```

---

### Test Internet Connectivity by IP

```bash
ping 1.1.1.1
```

Purpose:

Confirm that the VM could reach the internet using an IP address.

Result:

```text
Passed
```

---

### Test DNS Resolution

```bash
ping google.com
```

Purpose:

Confirm that the VM could resolve a domain name and reach an external host.

Result:

```text
Passed
```

---

## Validation Results

| Test | Result |
|---|---|
| VM connected to `vmbr1` | Passed |
| VM reached pfSense gateway | Passed |
| VM reached external IP address | Passed |
| VM resolved domain name | Passed |
| Internal SOC LAN validated | Passed |

---

## What This Confirms

This test confirmed that the internal SOC lab network is functioning.

The lab now has:

- Working firewall/router VM
- Working LAN bridge
- Working DHCP
- Working gateway
- Working internet routing
- Working DNS resolution

This means the lab is ready for the next systems to be built behind pfSense.

---

## Why This Matters

This validation prevents confusion later.

If Wazuh, Active Directory, Windows, Linux, or Suricata had been built before validating the network, future issues could have been harder to troubleshoot.

By testing the network first, the lab now has a known working foundation.

---

## Learning Reflection

`test-client-01` proved that the network design works.

The VM was simple, but the test was important.

A SOC lab depends on reliable communication between systems. Before building security tools, the network has to work.

This milestone confirmed that the internal SOC lab LAN is ready.