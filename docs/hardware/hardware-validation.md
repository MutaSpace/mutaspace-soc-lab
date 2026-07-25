# Hardware Validation

This document records how the custom PC was validated before continuing with Proxmox configuration and SOC lab setup.

Hardware validation matters because the lab depends on one physical host. If the host is unstable, every virtual machine, service, network, and security tool running on it can be affected.

---

## Validation Goal

The goal of hardware validation is to confirm that the custom PC can safely and reliably support the MutaSpace SOC Lab.

Before building virtual machines, the system should confirm:

- The motherboard detects the CPU.
- The motherboard detects the installed RAM.
- The motherboard detects the NVMe storage.
- The CPU cooler is mounted correctly.
- Fans and pump readings appear in BIOS.
- CPU temperature is stable.
- The system can boot from a USB installer.
- Proxmox can install to the internal NVMe drive.
- The Proxmox web interface can be reached from another device.

---

## Hardware Validation Checklist

| Validation Item | Status |
|---|---|
| System powers on | Completed |
| Fans turn on | Completed |
| RGB/ARGB lighting turns on | Completed |
| BIOS loads successfully | Completed |
| CPU detected | Completed |
| RAM detected | Completed |
| NVMe storage detected | Completed |
| CPU fan reading detected | Completed |
| CPU pump reading detected | Completed |
| CPU temperature stable in BIOS | Completed |
| Proxmox USB installer boots | Completed |
| Proxmox installs to internal NVMe | Completed |
| Proxmox web interface is reachable | Completed |

---

## BIOS Validation

The system successfully reached BIOS.

BIOS confirmed:

- Motherboard: GIGABYTE B650 AORUS Elite AX
- CPU: AMD Ryzen 9 7900X
- Memory: 64GB DDR5
- Storage: 2TB NVMe SSD
- CPU fan readings present
- CPU pump readings present
- CPU temperature stable

This confirmed that the core hardware was detected and stable enough to continue.

---

## Cooling Validation

The CPU cooler was validated by checking BIOS temperature and fan readings.

Cooling validation is important because the CPU may run multiple virtual machines and services for long periods.

A cooling issue can cause:

- High CPU temperatures
- System instability
- Unexpected shutdowns
- Poor virtual machine performance
- Damage over time

The CPU temperature remained stable in BIOS, which confirmed that the cooler was making contact and that the pump and fans were working.

---

## Memory Validation

The system detected 64GB of DDR5 memory.

Memory validation is important because Proxmox will allocate RAM to multiple virtual machines.

If RAM is not seated correctly or is not detected, the system may:

- Fail to boot
- Show no display
- Crash under load
- Fail during VM creation
- Report incorrect available memory

The installed memory was detected successfully in BIOS.

---

## Storage Validation

The system detected the internal NVMe SSD.

Storage validation is important because the NVMe drive stores:

- Proxmox VE
- VM disks
- ISO images
- Templates
- Snapshots
- Logs
- Lab data

The NVMe drive was detected in BIOS and selected as the target disk for Proxmox installation.

---

## Network Validation

The Proxmox installer detected the wired network interface.

The Proxmox host was configured with a static management address so it could be accessed from another device on the same network.

The web interface was successfully reached after installation.

This confirmed:

- The wired network interface was working.
- The host was reachable on the management network.
- The Proxmox web service was running.
- The static management configuration worked.

---

## Proxmox Web Access Validation

The Proxmox web interface was successfully accessed from another device using the management address.

Public documentation should use placeholders instead of live environment details.

Example format:

| Setting | Public Documentation Value |
|---|---|
| Web Interface | `https://<LAB_MANAGEMENT_IP>:8006` |
| Example Web Interface | `https://10.0.0.50:8006` |

This confirms that the Proxmox host is ready for initial configuration.

---

## Common Hardware Validation Problems

### No display after power-on

Possible causes:

- DDR5 memory training
- Monitor set to the wrong input
- Display cable connected to the wrong port
- RAM not fully seated
- CPU power cable not fully connected

Troubleshooting approach:

1. Wait several minutes for DDR5 memory training.
2. Confirm the monitor input.
3. Confirm the display cable is connected to the motherboard video output.
4. Reseat RAM.
5. Confirm the CPU/EPS power cable is connected.

---

### Fans spin but no BIOS

Possible causes:

- RAM issue
- CPU power issue
- Display output issue
- BIOS training delay

Troubleshooting approach:

1. Check motherboard debug indicators if available.
2. Reseat RAM.
3. Try one RAM stick.
4. Confirm CPU power.
5. Clear CMOS if needed.

---

### CPU temperature rises quickly

Possible causes:

- CPU cooler not mounted correctly
- Thermal paste issue
- Pump not connected
- Plastic film left on cooler cold plate
- Radiator fans not spinning

Troubleshooting approach:

1. Power off immediately.
2. Check cooler mounting pressure.
3. Confirm thermal paste was applied correctly.
4. Confirm the pump cable is connected.
5. Confirm radiator fans are spinning.

---

### Fan lights do not turn on

Possible causes:

- ARGB cable not connected
- Hub not receiving SATA power
- ARGB connected to wrong header
- Remote/controller not active

Troubleshooting approach:

1. Confirm the fan power cable and ARGB cable are separate.
2. Confirm the ARGB cable is connected to a 5V ARGB port.
3. Confirm the hub has SATA power.
4. Do not connect 5V ARGB to 12V RGB headers.

---

## Validation Result

The custom PC passed hardware validation.

The system powered on, reached BIOS, detected the expected hardware, booted the Proxmox installer, installed Proxmox VE, and allowed access to the Proxmox web interface from another device.

This means the host is ready for Proxmox baseline configuration and virtual network planning.

---

## Learning Reflection

Hardware validation is a security lab skill.

Before building SIEMs, endpoints, firewalls, and detection rules, the underlying system must be trusted to run correctly.

This step teaches that infrastructure work is part of cybersecurity work. A SOC lab depends on stable hardware, clear networking, working storage, and careful validation.
