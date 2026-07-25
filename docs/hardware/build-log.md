# Custom PC Build Log

This document records the physical build of the custom PC used to run the MutaSpace SOC Lab.

The purpose of the build log is to document the process in a way that is useful for learning, troubleshooting, and future rebuilding.

This is not written as a perfect build guide. It is written as a real build record.

---

## Build Purpose

The custom PC was built to serve as the official Proxmox host for the MutaSpace SOC Lab.

The system needed to support:

- Multiple virtual machines
- Proxmox virtualization
- Wazuh SIEM operations
- Suricata network monitoring
- Windows and Linux endpoints
- Controlled attack simulation
- Active Directory and DNS services
- Research and analysis workloads
- Learner-ready SOC scenarios

The prototype lab helped identify the need for stronger hardware, cleaner planning, and better documentation.

---

## Build Summary

| Item | Status |
|---|---|
| Custom PC assembled | Completed |
| System powered on | Completed |
| BIOS reached | Completed |
| CPU detected | Completed |
| RAM detected | Completed |
| NVMe detected | Completed |
| CPU cooler detected | Completed |
| Proxmox installer booted | Completed |
| Proxmox installed | Completed |
| Proxmox web interface accessed | Completed |

---

## Assembly Order

The physical build followed this general order:

1. Prepared the workspace.
2. Installed the CPU into the motherboard.
3. Installed the RAM into the correct DIMM slots.
4. Installed the NVMe SSD.
5. Mounted the motherboard into the case.
6. Installed the power supply.
7. Mounted the 360mm AIO radiator.
8. Installed the CPU cooler mounting hardware.
9. Mounted the CPU pump/block.
10. Connected motherboard power.
11. Connected CPU power.
12. Connected AIO pump, fan, and VRM fan cables.
13. Connected front panel cables.
14. Connected front USB and audio cables.
15. Connected case fans and ARGB hub.
16. Checked cables before first power-on.
17. Booted into BIOS.
18. Validated hardware detection.
19. Booted into the Proxmox installer.
20. Installed Proxmox VE.
21. Accessed the Proxmox web interface from another device.

---

## Important Build Notes

### CPU Installation

The AMD Ryzen 9 7900X was installed into the AM5 socket.

The CPU was aligned using the triangle marker and placed gently into the socket without force.

Lesson learned:

The CPU should drop into place naturally. If it does not, the alignment is wrong.

---

### RAM Installation

The 64GB DDR5 kit was installed as two 32GB sticks.

The RAM was installed in the recommended two-stick configuration for the motherboard.

Lesson learned:

RAM must be fully seated. A partially seated RAM stick can prevent the system from booting or displaying video.

---

### NVMe Installation

The 2TB NVMe drive was installed into the motherboard M.2 slot.

This drive is used for the Proxmox installation and initial VM storage.

Lesson learned:

Fast internal storage is important because virtual machines depend heavily on disk performance.

---

### Motherboard Installation

The motherboard was mounted into the case using the case standoffs and motherboard screws.

Lesson learned:

The motherboard should sit on standoffs, not directly on the case metal. Standoffs prevent electrical shorts.

---

### Power Supply Installation

The modular 850W power supply was installed in the PSU chamber.

Only the required cables were connected:

- 24-pin motherboard power
- CPU/EPS power
- SATA power for the fan/ARGB hub

Lesson learned:

Modular power supplies help reduce cable clutter, but only the cables that came with the exact PSU should be used.

---

### CPU Cooler Installation

The Arctic Liquid Freezer III Pro 360 A-RGB was installed as the CPU cooler.

The stock AMD plastic mounting brackets were removed, while the CPU retention frame stayed in place.

The AIO mounting brackets were installed, and the pump/block was mounted onto the CPU.

Lesson learned:

The cooler must sit flat on the CPU. If the pump/block is lifted after touching thermal paste, the paste should be cleaned and reapplied to avoid air pockets.

---

### Fan and ARGB Cabling

The build used two different cable types for fans:

| Cable Type | Purpose |
|---|---|
| PWM fan cable | Powers and controls fan speed |
| ARGB cable | Controls lighting |

The Arctic AIO cooling cables were connected to motherboard fan headers.

The case fan cables were connected to the fan/ARGB hub.

Lesson learned:

Fan power and fan lighting are separate systems. A fan can spin even if its lighting is not connected.

---

### Front Panel and USB Cables

The front panel connector was connected to the motherboard `F_PANEL` header.

The front USB cable was connected to the correct front USB motherboard header.

The HD Audio cable was connected to the audio header.

Lesson learned:

Front panel cables are small but important. If the power button does not work, the `F_PANEL` connection should be checked first.

---

## First Boot

On first boot, the system powered on and the fans and lighting turned on.

There was initially no display, which can happen during first boot and DDR5 memory training.

After waiting and checking the display connection, the system successfully reached BIOS.

Lesson learned:

A new DDR5 system may take time to train memory on first boot. A black screen does not always mean the build failed.

---

## BIOS Validation

The system successfully reached BIOS and confirmed:

- GIGABYTE B650 AORUS Elite AX motherboard detected
- AMD Ryzen 9 7900X detected
- 64GB DDR5 RAM detected
- 2TB NVMe storage detected
- CPU fan readings detected
- CPU pump readings detected
- CPU temperature stable

This confirmed that the physical build was stable enough to continue to Proxmox installation.

---

## Proxmox Installation

The Proxmox installer was booted from a USB drive.

Proxmox VE was installed to the internal NVMe drive.

The host was configured with a static management address.

After installation, the Proxmox web interface was successfully accessed from another device.

This confirmed that the system was installed, networked, and reachable.

---

## Troubleshooting Notes

### Issue: No display after first power-on

Possible causes considered:

- DDR5 memory training
- Monitor input selection
- Display cable connection
- RAM seating
- CPU power cable seating

Resolution:

The system eventually reached BIOS after display and boot checks.

Lesson learned:

Troubleshooting should start with the simplest causes before assuming a major hardware issue.

---

### Issue: Confusing fan and ARGB cables

Problem:

Several cables looked similar, including fan cables, ARGB cables, hub cables, and AIO cables.

Resolution:

The cables were separated by purpose:

- AIO cooling cables went to motherboard fan headers.
- Case fan cables went to the hub.
- ARGB lighting cables went to ARGB ports.
- SATA power powered the hub.

Lesson learned:

Cable labels and connector shapes matter. Similar-looking cables can have very different purposes.

---

### Issue: CPU cooler mounting confusion

Problem:

The AIO cooler brackets and original AMD brackets caused confusion during installation.

Resolution:

The original AMD plastic brackets were removed, the AIO brackets were installed, and the pump/block was mounted using the correct bracket orientation.

Lesson learned:

Cooler mounting should be checked carefully before powering on. Incorrect mounting can cause poor CPU contact and high temperatures.

---

## Build Validation Result

The custom PC build was successful.

The system reached BIOS, detected the expected hardware, booted the Proxmox installer, installed Proxmox VE, and allowed access to the Proxmox web interface.

This confirms that the custom PC is ready to begin Proxmox host configuration and SOC lab network planning.

---

## Learning Reflection

This build showed that hardware assembly is part of the cybersecurity lab process.

Before any SIEM, firewall, endpoint, or detection rule can be built, the host system must be stable.

The physical build taught:

- How hardware parts work together
- How to identify cable types
- How to validate a system in BIOS
- Why cooling and power matter
- Why troubleshooting is part of the process
- Why documentation should capture mistakes and fixes

The SOC lab begins with a stable host.
