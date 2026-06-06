# Lab 01: Failed Login Investigation

This lab documents the first investigation activity completed in the MutaSpace SOC Lab.

The goal of this lab was to generate failed login activity on a Windows endpoint and use Wazuh to investigate the event.

---

## Lab Purpose

This lab teaches how failed login activity appears in a SIEM.

The purpose is to help learners understand:

- How endpoint activity becomes SIEM telemetry
- What a failed login event looks like
- How to search for Windows authentication events
- How to identify the affected endpoint
- How to identify the user account involved
- How to write a basic analyst summary

This is the first learner-ready SOC investigation lab in the MutaSpace SOC Lab.

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

The Windows endpoint used in this lab was:

```text
win-client-01
```

The domain used in this lab was:

```text
mutaspace.local
```

---

## Wazuh Agent Coverage

Before starting the lab, the following Wazuh agents were already enrolled and active.

| Agent | System Type | Purpose |
|---|---|---|
| `analyst-01` | Linux workstation | Analyst workstation telemetry |
| `dc-01` | Windows Server | Active Directory and DNS telemetry |
| `win-client-01` | Windows workstation | Windows endpoint telemetry |

This confirmed that Wazuh was already receiving telemetry from the systems needed for the lab.

---

## Event Focus

This lab focused on Windows authentication events.

The primary event ID used was:

```text
4625
```

Windows Event ID `4625` means:

```text
An account failed to log on.
```

A related event is:

```text
4624
```

Windows Event ID `4624` means:

```text
An account was successfully logged on.
```

---

## Lab Scenario

A user attempts to log into a Windows workstation using the wrong password multiple times.

The failed login attempts are then reviewed in Wazuh.

The learner acts as a SOC analyst and investigates the activity.

---

## Lab Steps

### Step 1: Confirm Wazuh Agents Are Active

In the Wazuh dashboard, confirm that the expected agents are active.

Expected active agents:

```text
analyst-01
dc-01
win-client-01
```

This confirms that Wazuh is receiving telemetry from the lab endpoints.

---

### Step 2: Generate Failed Login Activity

On `win-client-01`, attempt to log in with a domain account using the wrong password.

Example account format:

```text
MUTASPACE\test.user
```

Generate several failed login attempts.

Example:

```text
3 to 5 failed login attempts
```

After generating failed attempts, log in successfully if needed to continue the investigation.

---

### Step 3: Open Wazuh from the Analyst Workstation

From `analyst-01`, open the Wazuh dashboard.

```text
https://wazuh-01.mutaspace.local
```

Log in with the Wazuh dashboard account.

---

### Step 4: Search for Failed Login Events

In Wazuh, go to the security event search area.

Depending on the Wazuh view, this may be under:

```text
Threat Hunting
```

or:

```text
Security Events
```

Search for failed login events using Windows Event ID `4625`.

Example search terms:

```text
4625
```

or:

```text
data.win.system.eventID: "4625"
```

To focus on the Windows client, search for:

```text
agent.name: "win-client-01" AND data.win.system.eventID: "4625"
```

---

## Important Navigation Note

During the lab, it is possible to accidentally search in the wrong Wazuh section.

For failed login events, do not use:

```text
File Integrity Monitoring
```

File Integrity Monitoring shows file and registry changes.

Failed login events should be reviewed in the main security event or threat hunting view.

---

## What to Look For

When reviewing the failed login event, identify:

| Field | Question |
|---|---|
| Agent name | Which endpoint generated the event? |
| Event ID | Is this a failed login event? |
| Username | Which account was used? |
| Timestamp | When did the event happen? |
| Source system | Where did the login attempt occur? |
| Rule description | How did Wazuh describe the activity? |

---

## Expected Findings

The expected failed login event should show activity related to:

```text
win-client-01
```

The expected Windows Event ID is:

```text
4625
```

The event should indicate that a login attempt failed.

---

## Investigation Questions

Learners should answer the following questions:

1. Which endpoint generated the failed login event?
2. Which user account was involved?
3. How many failed login attempts occurred?
4. Was there a successful login afterward?
5. Was this expected lab activity or suspicious activity?
6. What evidence supports the conclusion?
7. What should be documented in the analyst notes?

---

## Example Analyst Summary

```text
Multiple failed login attempts were observed for a domain user account on win-client-01. The activity was generated intentionally as part of a lab exercise. The failed login events were visible in Wazuh and confirmed that Windows endpoint authentication telemetry is being collected successfully.

Status: Benign lab activity
Action: Documented and validated telemetry
```

---

## Validation Results

| Validation Item | Status |
|---|---|
| `win-client-01` joined to domain | Completed |
| Wazuh agent active on `win-client-01` | Completed |
| Failed login attempts generated | Completed |
| Failed login events located in Wazuh | Completed |
| Windows Event ID `4625` identified | Completed |
| Analyst summary written | Completed |
| Lab completed and recorded | Completed |

---

## Troubleshooting Notes

### Issue: Failed login events were not visible at first

At first, the failed login events were not visible because the wrong Wazuh section was being viewed.

The File Integrity Monitoring section was open, which shows file and registry activity instead of authentication events.

Resolution:

```text
Use Threat Hunting or Security Events to search for Windows authentication events.
```

Search terms used:

```text
4625
agent.name: "win-client-01"
data.win.system.eventID: "4625"
```

---

## SOC Learning Value

This lab introduces one of the most common SOC investigation areas:

```text
authentication activity
```

Failed logins can be normal user mistakes, but they can also indicate:

- Password guessing
- Brute-force attempts
- Misconfigured services
- Unauthorized access attempts
- Account misuse

This lab teaches learners to avoid guessing and instead use logs to answer basic investigation questions.

---

## Skills Practiced

This lab practiced:

- Wazuh dashboard navigation
- Windows authentication event review
- Failed login investigation
- Endpoint telemetry validation
- Event ID recognition
- Basic SIEM searching
- Analyst note writing
- Evidence-based investigation

---

## Reflection

This lab confirmed that the MutaSpace SOC Lab can support real beginner-friendly SOC investigations.

The lab successfully generated endpoint activity, collected the telemetry in Wazuh, and used that evidence to answer investigation questions.

This is the first completed SOC investigation lab in the environment.