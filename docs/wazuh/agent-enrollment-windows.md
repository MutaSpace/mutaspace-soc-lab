# Windows Wazuh Agent Enrollment

This document records the Windows Wazuh agent enrollment for `dc-01`, the Windows Server domain controller in the MutaSpace SOC Lab.

The goal of this step was to connect `dc-01` to the Wazuh server so the lab can begin collecting Windows Server and Active Directory telemetry.

---

## Enrollment Purpose

Wazuh agents collect endpoint telemetry and send it to the Wazuh manager for analysis.

Enrolling `dc-01` is important because it allows Wazuh to collect security data from the domain controller.

This gives the lab visibility into Windows Server and Active Directory activity.

---

## Systems Involved

| System | Role | IP Address |
|---|---|---|
| `wazuh-01` | Wazuh server / manager | `10.10.10.20` |
| `dc-01` | Windows Server Domain Controller / Wazuh agent | `10.10.10.10` |
| `fw-01` | Gateway / firewall | `10.10.10.1` |
| `analyst-01` | Analyst workstation | DHCP address |

---

## Agent Target

The Windows agent was installed on:

```text
dc-01
```

`dc-01` is the domain controller for:

```text
mutaspace.local
```

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

Both `dc-01` and `wazuh-01` are connected to:

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

The selected operating system was:

```text
Windows
```

The generated PowerShell command was run on `dc-01` using PowerShell as Administrator.

---

## Agent Name

The agent was enrolled as:

```text
dc-01
```

The agent name should match the endpoint being monitored.

This makes it easier to identify systems inside the Wazuh dashboard.

---

## Service Validation

After installation, the Wazuh service was validated on `dc-01`.

PowerShell command:

```powershell
Get-Service WazuhSvc
```

Expected result:

```text
Running
```

---

## Dashboard Validation

The Wazuh dashboard showed `dc-01` under agents.

This confirmed that:

- The Windows agent installed successfully
- The Wazuh service started successfully
- `dc-01` could reach `wazuh-01`
- The Wazuh manager received the agent connection
- Windows Server telemetry collection has started

---

## Validation Results

| Validation Item | Status |
|---|---|
| Windows agent package selected | Completed |
| Wazuh agent installed on `dc-01` | Completed |
| Wazuh agent service started | Completed |
| Wazuh agent service running | Completed |
| Agent connected to Wazuh manager | Completed |
| `dc-01` visible in Wazuh dashboard | Completed |

---

## Why This Matters

This is the first successful Windows Server telemetry connection in the MutaSpace SOC Lab.

The lab now has:

- A Wazuh server
- A Linux endpoint sending telemetry
- A Windows Server domain controller sending telemetry
- Active Directory and DNS visibility starting in Wazuh

This is important because many SOC investigations involve Windows and identity activity.

---

## Security Events This Enables

With `dc-01` enrolled, future labs can investigate activity such as:

- Successful logins
- Failed logins
- Account creation
- Password changes
- Group membership changes
- Domain authentication events
- Windows service activity
- Security log events

These events will support future detection engineering and incident investigation labs.

---

## Troubleshooting Notes

This enrollment completed successfully.

No major troubleshooting was required after running the Windows agent deployment command from the Wazuh dashboard.

This confirms that DNS, network access, and manager connectivity were working correctly.

---

## Learning Reflection

Enrolling `dc-01` showed why the earlier infrastructure work mattered.

The firewall, internal bridge, DNS, Active Directory, and Wazuh server all had to work together before Windows telemetry could flow into the SIEM.

The MutaSpace SOC Lab now has both Linux and Windows telemetry reaching Wazuh.