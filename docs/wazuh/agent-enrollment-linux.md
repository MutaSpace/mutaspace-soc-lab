# Linux Wazuh Agent Enrollment

This document records the first Linux Wazuh agent enrollment in the MutaSpace SOC Lab.

The goal of this step was to install the Wazuh agent on `analyst-01` and confirm that it successfully connected to the Wazuh server.

---

## Enrollment Purpose

Wazuh agents collect telemetry from endpoints and send it to the Wazuh manager for analysis.

This enrollment confirms that the lab can now collect endpoint data from an internal Linux workstation.

---

## Systems Involved

| System | Role | IP Address |
|---|---|---|
| `wazuh-01` | Wazuh server / manager | `10.10.10.20` |
| `analyst-01` | Ubuntu analyst workstation / Wazuh agent | DHCP address |
| `dc-01` | DNS server | `10.10.10.10` |
| `fw-01` | Gateway / firewall | `10.10.10.1` |

---

## Agent Target

The first Linux agent was installed on:

```text
analyst-01
```

This system is the Ubuntu analyst workstation inside the internal SOC lab network.

---

## Manager Target

The Wazuh manager is:

```text
wazuh-01
```

The Wazuh manager can be reached at:

```text
10.10.10.20
```

and by DNS name:

```text
wazuh-01.mutaspace.local
```

---

## Network Placement

Both `analyst-01` and `wazuh-01` are connected to:

```text
vmbr1
```

This places both systems inside the internal SOC lab network.

---

## Installation Method

The agent was installed using the Wazuh dashboard deployment workflow.

In the Wazuh dashboard:

```text
Agents > Deploy new agent
```

The correct package type for Ubuntu was:

```text
DEB amd64
```

---

## Important Package Note

The first attempt used an RPM-based command.

That did not work on Ubuntu because Ubuntu uses DEB packages, not RPM packages.

Error observed:

```text
rpm: command not found
```

Root cause:

```text
The generated command was for an RPM-based Linux distribution instead of Ubuntu.
```

Resolution:

```text
Select DEB amd64 in the Wazuh agent deployment screen.
Use the DEB-based installation command for Ubuntu.
```

---

## Agent Name

The agent was enrolled as:

```text
analyst-01
```

The agent name should match the endpoint being monitored.

---

## Validation Commands

After installation, the Wazuh agent service was started and validated.

```bash
sudo systemctl status wazuh-agent
```

Expected result:

```text
active (running)
```

---

## Dashboard Validation

The Wazuh dashboard showed `analyst-01` under agents.

This confirmed that:

- The agent installed successfully
- The agent service started successfully
- `analyst-01` could reach `wazuh-01`
- The Wazuh manager received the agent connection
- Endpoint telemetry collection has started

---

## Validation Results

| Validation Item | Status |
|---|---|
| Correct DEB agent package selected | Completed |
| Wazuh agent installed on `analyst-01` | Completed |
| Wazuh agent service started | Completed |
| Wazuh agent service running | Completed |
| Agent connected to Wazuh manager | Completed |
| `analyst-01` visible in Wazuh dashboard | Completed |

---

## Why This Matters

This is the first successful endpoint telemetry connection in the MutaSpace SOC Lab.

The lab now has:

- A Wazuh server
- A Linux endpoint
- A working Wazuh agent
- Endpoint visibility in the dashboard

This is the foundation for future log analysis, alert review, detection engineering, and incident simulation.

---

## Learning Reflection

This step showed that SIEM deployment is not complete until endpoints are connected.

A dashboard alone is not enough.

The value of Wazuh comes from the systems sending data into it.

By enrolling `analyst-01`, the lab moved from having a SIEM installed to having the first monitored endpoint.
