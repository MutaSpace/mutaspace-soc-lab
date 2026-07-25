# DHCP and Network Validation

This document records the first successful network validation for the MutaSpace SOC Lab internal LAN.

The goal of this validation was to confirm that the firewall VM, Proxmox bridge configuration, DHCP service, gateway routing, and DNS resolution were working before building the rest of the SOC lab systems.

---

## Validation Purpose

Before creating Wazuh, Windows endpoints, Linux servers, Active Directory, Suricata, or attack simulation systems, the internal lab network needed to be tested.

This validation confirms that a virtual machine connected to the internal SOC lab bridge can:

- Receive network access from the lab network
- Reach the pfSense LAN gateway
- Reach the internet by IP address
- Resolve DNS names
- Communicate through the firewall/router VM

This matters because the rest of the lab depends on this network foundation.

---

## Network Components Tested

| Component | Role |
|---|---|
| `fw-01` | pfSense firewall/router VM |
| `vmbr0` | Proxmox management/upstream bridge |
| `vmbr1` | Internal SOC lab LAN bridge |
| `test-client-01` | Temporary test VM used to validate network access |

---

## Current Network Layout

```text
Proxmox management/upstream network
        |
      vmbr0
        |
      fw-01
 pfSense firewall/router
        |
      vmbr1
        |
 Internal SOC Lab LAN
 10.10.10.0/24
```

---

## Firewall Interface Mapping

| pfSense Interface | Virtual NIC | Proxmox Bridge | Purpose |
|---|---|---|---|
| WAN | `vtnet0` | `vmbr0` | Upstream network access |
| LAN | `vtnet1` | `vmbr1` | Internal SOC lab network |

---

## LAN Configuration

The pfSense LAN interface was configured as the gateway for the internal SOC lab network.

| Setting | Value |
|---|---|
| LAN Gateway | `10.10.10.1/24` |
| Internal Network | `10.10.10.0/24` |
| DHCP Range | `10.10.10.100 - 10.10.10.200` |
| Internal Bridge | `vmbr1` |

---

## Test VM

A temporary Linux test VM was created to validate the network.

| Setting | Value |
|---|---|
| VM Name | `test-client-01` |
| VM ID | `101` |
| Network Bridge | `vmbr1` |
| Purpose | Validate DHCP, gateway, internet, and DNS |

The most important configuration detail was that `test-client-01` was connected to `vmbr1`, not `vmbr0`.

This confirmed that the test VM was placed inside the internal SOC lab LAN instead of directly on the Proxmox management/upstream network.

---

## Validation Tests

The following tests were performed from `test-client-01`.

### Test 1: Ping the pfSense LAN Gateway

Command:

```bash
ping 10.10.10.1
```

Result:

```text
Successful replies received from 10.10.10.1
```

Meaning:

The test VM could reach the pfSense LAN interface.

This confirmed that:

- `test-client-01` was connected to the internal lab bridge
- `vmbr1` was working
- pfSense LAN was reachable
- The gateway address was active

---

### Test 2: Ping an External IP Address

Command:

```bash
ping 1.1.1.1
```

Result:

```text
Successful replies received from 1.1.1.1
```

Meaning:

The test VM could reach the internet by IP address.

This confirmed that:

- pfSense routing was working
- The test VM could leave the internal LAN through the firewall
- WAN connectivity through `vmbr0` was working
- Basic NAT/routing behavior was functioning

---

### Test 3: Ping a Domain Name

Command:

```bash
ping google.com
```

Result:

```text
google.com resolved to an IP address and returned replies
```

Meaning:

DNS resolution was working.

This confirmed that:

- The test VM could resolve domain names
- DNS traffic was successfully passing through the network path
- The internal lab network had working name resolution

---

## Validation Results

| Test | Result |
|---|---|
| Test VM connected to `vmbr1` | Passed |
| Test VM reached pfSense LAN gateway | Passed |
| Test VM reached external IP address | Passed |
| Test VM resolved a domain name | Passed |
| Internal SOC lab LAN validated | Passed |

---

## What This Confirms

This validation confirms that the internal SOC lab network is working.

The lab now has:

- A functioning firewall/router VM
- WAN and LAN separation
- A working internal SOC lab bridge
- A LAN gateway
- DHCP services
- Internet routing
- DNS resolution

This means future lab systems can be placed behind pfSense on `vmbr1`.

Systems that can now be built on the internal lab network include:

- Wazuh SIEM
- Windows endpoint
- Linux endpoint
- Ubuntu analyst workstation
- Active Directory domain controller
- Suricata sensor, depending on final placement

---

## Why This Matters

This is a major infrastructure milestone.

A SOC lab depends on network visibility, routing, and reliable communication. If the network does not work, security tools cannot collect useful telemetry, endpoints cannot communicate properly, and troubleshooting becomes harder.

Validating the network early prevents confusion later.

This step confirms that the lab is ready to begin building internal systems.

---

## Troubleshooting Notes

The validation worked successfully.

No major troubleshooting was required during the DHCP and connectivity test.

This is important to document because not every milestone requires a problem. Sometimes the value is confirming that the architecture worked as planned.

---

## Learning Reflection

This validation showed that the network foundation is working.

The firewall VM is routing traffic.
The internal bridge is carrying lab traffic.
The test VM can reach the gateway.
The test VM can reach the internet.
DNS is resolving correctly.

This confirms that the MutaSpace SOC Lab is ready to move beyond infrastructure setup and begin building internal lab services.

The lab now has a working internal network.
