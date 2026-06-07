# Lab 02: Account Creation Investigation

This lab documents an Active Directory account creation investigation in the MutaSpace SOC Lab.

The goal of this lab was to create a new domain user account and use Wazuh to identify the related Windows security event.

---

## Lab Purpose

This lab teaches how account creation activity appears in a SIEM.

The purpose is to help learners understand:

- How Active Directory account changes create security events
- How Windows Server telemetry reaches Wazuh
- How to search for account management events
- How to identify the account that was created
- How to identify where the event occurred
- How to write a basic analyst summary

This lab builds on Lab 01 by moving from login activity to identity administration activity.

---

## Lab Environment

The following systems were used in this lab.

| System | Role |
|---|---|
| `fw-01` | pfSense firewall/router |
| `dc-01` | Active Directory Domain Controller and DNS server |
| `wazuh-01` | Wazuh SIEM server |
| `analyst-01` | Ubuntu analyst workstation |
| `win-client-01` | Windows domain workstation |

---

## Network Context

All lab systems are connected through the internal SOC lab network.

```text
Internal SOC LAN: 10.10.10.0/24
Gateway: 10.10.10.1
DNS Server: 10.10.10.10
Domain: mutaspace.local
```

---

## Wazuh Agent Coverage

Before starting the lab, the following Wazuh agents were active.

| Agent | System Type | Purpose |
|---|---|---|
| `analyst-01` | Linux workstation | Analyst workstation telemetry |
| `dc-01` | Windows Server | Active Directory and DNS telemetry |
| `win-client-01` | Windows workstation | Windows endpoint telemetry |

For this lab, the most important agent was:

```text
dc-01
```

The account creation event appeared from the domain controller because the account was created in Active Directory.

---

## Event Focus

This lab focused on Windows account management events.

The primary event ID was:

```text
4720
```

Windows Event ID `4720` means:

```text
A user account was created.
```

Related event IDs include:

```text
4722 = A user account was enabled
4726 = A user account was deleted
4738 = A user account was changed
4732 = A member was added to a security-enabled local group
```

---

## Lab Scenario

A new domain user account was created in Active Directory.

The learner acted as a SOC analyst and investigated the account creation event in Wazuh.

The goal was to determine:

- What account was created
- Where the event occurred
- Which system reported the event
- Whether the activity was expected or suspicious

---

## Lab Steps

### Step 1: Confirm Wazuh Agents Were Active

In the Wazuh dashboard, the expected agents were confirmed as active.

Expected active agents:

```text
analyst-01
dc-01
win-client-01
```

This confirmed that Wazuh was receiving telemetry from the systems needed for the lab.

---

### Step 2: Create a New Domain User

On `dc-01`, Active Directory Users and Computers was opened from:

```text
Server Manager > Tools > Active Directory Users and Computers
```

The `Users` container was used to create a test user.

Example lab user:

```text
First name: Lab
Last name: User02
User logon name: lab.user02
```

A lab password was set for the account.

No real personal password was used.

---

### Step 3: Open Wazuh from the Analyst Workstation

From `analyst-01`, the Wazuh dashboard was opened.

```text
https://wazuh-01.mutaspace.local
```

---

### Step 4: Search for Account Creation Events

In Wazuh, the security event search area was used.

The event was searched using Windows Event ID `4720`.

Example search terms:

```text
4720
```

or:

```text
data.win.system.eventID: "4720"
```

To focus on the domain controller, the search can be narrowed to:

```text
agent.name: "dc-01" AND data.win.system.eventID: "4720"
```

---

## What Was Found

The account creation event was successfully located in Wazuh.

The event confirmed:

| Field | Finding |
|---|---|
| Agent name | `dc-01` |
| Event ID | `4720` |
| Event meaning | A user account was created |
| Created account | `lab.user02` |
| Event source | Active Directory domain controller |
| Status | Expected lab activity |

---

## Investigation Questions

Learners should answer the following questions:

1. Which system generated the account creation event?
2. What event ID identifies account creation?
3. What user account was created?
4. Which account created the new user?
5. What time did the event occur?
6. Was this expected lab activity or suspicious activity?
7. What evidence supports the conclusion?
8. What should be documented in the analyst notes?

---

## Example Analyst Summary

```text
A new domain user account named lab.user02 was created in Active Directory. The event was observed from dc-01 and matched Windows Event ID 4720. The activity was generated intentionally as part of a lab exercise.

Status: Benign lab activity
Action: Documented account creation event and validated Active Directory telemetry in Wazuh
```

---

## Validation Results

| Validation Item | Status |
|---|---|
| `dc-01` active in Wazuh | Completed |
| New domain user created | Completed |
| Event ID `4720` searched in Wazuh | Completed |
| Account creation event located | Completed |
| Created username identified | Completed |
| Event source confirmed as `dc-01` | Completed |
| Analyst summary written | Completed |
| Lab completed successfully | Completed |

---

## Troubleshooting Notes

This lab completed successfully.

No major troubleshooting was required after generating the account creation event and searching Wazuh.

If the event does not appear immediately in future runs, check:

- The Wazuh time range
- Whether `dc-01` is active as an agent
- Whether the event exists in Windows Event Viewer
- Whether the search is being performed in Threat Hunting or Security Events
- Whether the search is focused on the correct agent

---

## SOC Learning Value

Account creation is important in SOC investigations because unauthorized account creation can indicate:

- Privilege misuse
- Persistence
- Insider activity
- Account compromise
- Unauthorized administrative changes

Not every new account is suspicious, but every unexpected account creation should be explainable.

This lab teaches learners how to verify account creation activity using evidence from logs.

---

## Skills Practiced

This lab practiced:

- Active Directory user creation
- Windows security event review
- Wazuh dashboard navigation
- Event ID recognition
- Account management investigation
- Identity monitoring
- Analyst note writing
- Evidence-based investigation

---

## Reflection

This lab showed how Active Directory administrative activity becomes SIEM telemetry.

By creating a domain user and finding the matching Wazuh event, learners can see how identity changes are tracked and investigated.

This lab builds the foundation for future investigations involving account changes, group membership changes, suspicious privilege activity, and persistence techniques.