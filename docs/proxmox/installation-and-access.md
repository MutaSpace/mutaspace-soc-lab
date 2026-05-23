# Proxmox Installation and Access

This document records the Proxmox VE installation and web access validation for the MutaSpace SOC Lab host.

Proxmox is the hypervisor that runs the virtual machines for the lab. Installing Proxmox is the step that turns the custom PC from a normal computer into a virtualization host.

---

## Installation Purpose

The purpose of this installation was to prepare the custom PC to run the MutaSpace SOC Lab.

After installation, the system should be able to:

- Run Proxmox VE as the hypervisor
- Store virtual machine disks on the internal NVMe drive
- Use a static management address
- Be accessed through the Proxmox web interface
- Support future virtual machines for firewall, SIEM, endpoints, sensors, and learner scenarios

---

## Installation Summary

| Item | Configuration |
|---|---|
| Hypervisor | Proxmox VE |
| Hostname | `mutaspace-soc-node01` |
| Filesystem | `ext4` |
| Target Disk | `/dev/nvme0n1` |
| Management Access | Proxmox web interface |
| Web Interface Port | `8006` |

---

## Installation Media

Proxmox VE was installed using a USB installer.

The installer was booted from the custom PC, and Proxmox was installed onto the internal NVMe drive.

The internal NVMe drive was selected as the target disk.

The USB installer was not selected as the installation target.

---

## Target Disk

The target disk for Proxmox installation was:

```text
/dev/nvme0n1
```

This disk is the internal NVMe drive.

The NVMe drive is used for:

- Proxmox VE installation
- ISO storage
- Virtual machine disks
- Initial templates
- Initial snapshots
- Early lab data

---

## Filesystem Choice

The selected filesystem was:

```text
ext4
```

This filesystem was selected because it is simple, stable, and appropriate for the first version of the lab.

The goal for this stage is to keep the host understandable and reliable before adding more advanced storage designs.

---

## Management Network

The Proxmox host was configured with a static management address.

The management address is used to access the Proxmox web interface from another device on the same network.

Public documentation should use placeholders instead of live environment details.

| Setting | Public Documentation Value |
|---|---|
| Hostname | `mutaspace-soc-node01` |
| Management IP | `<LAB_MANAGEMENT_IP>/24` |
| Example Management IP | `10.0.0.50/24` |
| Gateway | `<LAB_GATEWAY_IP>` |
| Example Gateway | `10.0.0.1` |
| DNS | `<DNS_SERVER>` |
| Example DNS | `1.1.1.1` |
| Web Interface | `https://<LAB_MANAGEMENT_IP>:8006` |
| Example Web Interface | `https://10.0.0.50:8006` |

---

## Why Static Management Matters

A static management address makes the Proxmox host easier to find and manage.

If the host used a changing address, the web interface could become harder to reach after reboots or network changes.

A static management address helps with:

- Reliable web access
- Consistent documentation
- Easier troubleshooting
- Future network planning
- Stable administrative workflows

---

## Web Interface Access

After installation, the Proxmox web interface was accessed from another device on the same network.

The web interface uses HTTPS and port `8006`.

Example format:

```text
https://<LAB_MANAGEMENT_IP>:8006
```

The browser may show a certificate warning during first access. This is expected because a fresh Proxmox installation uses a self-signed certificate.

---

## Login Realm

The initial login uses the Linux PAM authentication realm.

| Field | Value |
|---|---|
| Username | `root` |
| Realm | `Linux PAM standard authentication` |
| Password | Root password created during installation |

The root password should never be committed to GitHub.

---

## Web Access Validation

Successful web access confirms:

- Proxmox installed correctly
- The host booted from the internal NVMe drive
- The management network is working
- The static management address is reachable
- The Proxmox web service is running
- Another device on the network can manage the host

This is an important milestone because it confirms the custom PC is now functioning as a Proxmox host.

---

## Security Notes

The Proxmox web interface controls the entire lab host.

Access should be protected.

Do not publish:

- Root password
- Real public IP addresses
- MAC addresses
- SSH keys
- API tokens
- Sensitive screenshots
- Router details
- Port forwarding details

Public documentation should use placeholders or example values.

---

## Common Installation Mistakes

### Mistake: Selecting the wrong disk

The Proxmox installer erases the selected target disk.

The internal NVMe drive should be selected, not the USB installer.

### Mistake: Using Wi-Fi for host management

A Proxmox host should use wired Ethernet for management.

Ethernet is more stable and better suited for virtualization infrastructure.

### Mistake: Forgetting the web interface port

The Proxmox web interface uses port `8006`.

The correct format is:

```text
https://<LAB_MANAGEMENT_IP>:8006
```

### Mistake: Panicking at the certificate warning

The browser certificate warning is expected on a fresh Proxmox installation.

This happens because Proxmox uses a self-signed certificate by default.

---

## Troubleshooting Approach

If the Proxmox web interface does not load:

1. Confirm the Proxmox host is powered on.
2. Confirm the Ethernet cable is connected.
3. Confirm the management IP address.
4. Confirm the client device is on the same network.
5. Try pinging the Proxmox management address.
6. Confirm the URL includes `https`.
7. Confirm the URL includes port `8006`.
8. Check the Proxmox console for network errors.

Troubleshooting should start with network basics before assuming Proxmox is broken.

---

## Validation Result

Proxmox VE was successfully installed on the custom SOC lab host.

The Proxmox web interface was successfully accessed from another device on the same network.

This confirms that the host is installed, networked, and ready for baseline configuration.