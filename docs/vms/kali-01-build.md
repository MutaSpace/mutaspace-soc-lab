kali-01 build guide
Completed: October 6, 2026. Repository destination: docs/vms/kali-01-build.md.

VM purpose
kali-01 is the MutaSpace lab's personal pentesting, reconnaissance, web assessment, password auditing, and initial OSINT workstation. It expands the environment's capabilities before focused exercises begin. Student access is paused. Administration currently uses the Proxmox console.
The wider goal is a modular environment: choose a weekly study topic, start the relevant systems, build exercises around that objective, capture results, and reset the appropriate systems afterward. Kali is one component of that environment, not a requirement for every study topic.

VM configuration
Setting	Configuration
Proxmox node	mutaspace-soc-node01
VM ID / name	114 / kali-01
OS	Kali Linux, x86_64/AMD64 Installer ISO
CPU	1 socket, 4 cores, type host
Memory	4096 MiB, ballooning disabled
Disk	80 GiB, SCSI, I/O thread and discard enabled
SCSI controller	VirtIO SCSI single
Disk cache	Default, no cache
BIOS / machine / graphics	Defaults; SeaBIOS
QEMU agent option	Enabled
Network	VirtIO, vmbr1, VLAN tag blank, NIC firewall unchecked
Start at boot	Unchecked
Desktop	Xfce
Local username	kaliadmin
Hostname	kali-01
DNS domain suffix	mutaspace.local
Interface	eth0
Reserved address	10.10.10.70/24
Gateway	10.10.10.1
Lab DNS	10.10.10.10
Wazuh manager	wazuh-01.mutaspace.local, 10.10.10.20
Snapshot	kali-baseline, RAM excluded


Passwords, MAC addresses, and agent enrollment secrets are intentionally excluded. Use locally assigned identifiers when reproducing the build. Private IPs and the lab domain are example values that must be adapted to another network. The exact installed Kali release, kernel, and Wazuh agent version were not recorded in this build session.

Installation
1. Download the standard AMD64 Installer ISO from Kali's official download page. For a new download, follow the official image verification instructions.
2. Upload the ISO to Proxmox's ISO storage and create the VM using the configuration above. Choose available VM disk storage appropriate to your host.
3. Start the VM, open Console, and select Graphical install.
4. Select English, United States, and American English keyboard. Set the time zone to Central for this Houston-based lab.
5. Let DHCP configure the initial network. Set hostname kali-01 and domain suffix mutaspace.local. This does not join Kali to Active Directory.
6. Create local account kaliadmin with a private password. Use a role-based account display name; do not use a personal name. The final display name was not recorded.
7. Select Guided - use entire disk, choose the VM's 80 GiB disk, then All files in one partition. Finish partitioning and confirm writing changes. The disk may appear as approximately 85.9 GB because of unit differences.
8. Keep Xfce, top10, and default selected under Software selection. Leave GNOME and KDE Plasma unselected.
9. Install GRUB on the main virtual disk, usually /dev/sda, when prompted. Finish installation and reboot.
10. If the installer menu appears again, set the VM's CD/DVD drive to Do not use any media and reboot.

Update Kali and install the guest agent

Run these commands in Kali's terminal. They update installed packages and add the guest agent so Proxmox can report guest information and coordinate shutdowns:
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
sudo reboot
During the initial upgrade, Yes was selected for restarting services during package upgrades without asking. After reboot:
systemctl is-active qemu-guest-agent
Completed result: active.
Network placement and IP configuration
vmbr1 connects Kali to the internal lab LAN. pfSense provides the gateway and DHCP. The dynamic pool is 10.10.10.100 through 10.10.10.200; Kali initially received 10.10.10.115/24.

To create the reservation:
1. Read Kali's management NIC MAC locally in Proxmox, under VM Hardware > Network Device. Enter it directly into pfSense. Do not include it in screenshots or public documentation.
2. Open pfSense Services > DHCP Server > LAN and add a static mapping.
3. Set address 10.10.10.70, hostname kali-01, and description Kali pentesting and reconnaissance workstation. Confirm the address is unused before assigning it.
4. Save and apply changes. Restart Kali to request a new lease:
sudo reboot

Kali remains a DHCP client; the reservation supplies a consistent address. After login, check the address, default route, and lab name resolution:
ip -br address
ip route show default
getent hosts wazuh-01.mutaspace.local
getent hosts dc-01.mutaspace.local

Completed results: eth0 has 10.10.10.70/24, the gateway is 10.10.10.1, Wazuh resolves to 10.10.10.20, and the domain controller resolves to 10.10.10.10. Avoid sharing unredacted interface output if it includes identifiers you wish to keep private.

Wazuh agent enrollment
In the existing Wazuh dashboard, open Agents > Deploy new agent:
Wizard field	Value
Package	Linux DEB amd64
Server address	wazuh-01.mutaspace.local
Agent name	kali-01
Group	default


Run the dashboard-generated installation command in Kali. This downloads and installs the agent and sets its manager connection. Use the version generated for your deployment rather than substituting an arbitrary latest agent version.
Then enable and start the agent:
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-agent
systemctl is-active wazuh-agent
Completed result: the user confirmed kali-01 is Active in the Wazuh dashboard. This establishes agent connectivity. No custom Kali detections or exercise-specific alert validation were completed during this build.
Remote access decision
xrdp and its Xorg integration were installed and xrdp was confirmed active:
sudo apt install -y xrdp xorgxrdp
sudo systemctl enable --now xrdp
systemctl is-active xrdp
Guacamole connection setup was then deferred. Remote desktop access was unnecessary for the current personal console workflow, so the service was stopped and disabled:
sudo systemctl disable --now xrdp
The packages remain installed. No Kali Guacamole connection or successful remote desktop login was confirmed. A reproducer using only the Proxmox console can skip installing xrdp entirely. Student access remains paused until explicitly reopened.
Additional tool collections
These commands install the missing members of three Kali-maintained tool groups and their dependencies. Review APT's storage and download totals before confirming:
sudo apt update
sudo apt install kali-tools-information-gathering kali-tools-web kali-tools-passwords
Group	Future use
kali-tools-information-gathering	Reconnaissance, enumeration, and initial OSINT
kali-tools-web	Web application assessment
kali-tools-passwords	Password auditing and recovery


Validate installation without running an assessment:
dpkg-query -W -f='${Package}: ${Status}\n' \
  kali-tools-information-gathering \
  kali-tools-web \
  kali-tools-passwords
Expected for each group: install ok installed. The user reported installation finished and completed the subsequent baseline checkpoint. Installation does not establish that every included tool has been functionally tested. Some tools may require additional configuration, accounts, API keys, targets, or specialized hardware when used later. No GPU passthrough was configured.
Baseline snapshot and recovery
After package validation, shut the VM down:
sudo poweroff
In Proxmox, select VM 114 > Snapshots > Take Snapshot:
- Name: kali-baseline.
- Include RAM: unchecked.
- Description: Kali workstation; kaliadmin; reserved IP 10.10.10.70; QEMU agent; Wazuh active; reconnaissance, web testing and password auditing tools; xrdp disabled.
The user confirmed this checkpoint was completed. Snapshot restoration has not been tested. The snapshot covers the VM, not pfSense's DHCP reservation, the Proxmox host, or other lab systems. Keep a separate backup strategy for those components.
Before a future rollback, preserve any work or evidence needed from Kali. Stop the VM, select the appropriate snapshot, and use Proxmox's rollback action. After starting the restored VM, check network resolution, guest-agent status, and Wazuh connectivity. Rolling back restores older package state, so consider updates before beginning a new study period. Avoid cloning an enrolled VM into a simultaneous active duplicate without changing its identity and Wazuh enrollment.
Dependencies and weekly activation
Study focus	Systems to select when designing future labs
Reconnaissance and pentesting	Kali, pfSense, and the chosen target systems
Active Directory security	Kali, dc-01, appropriate Windows clients/member servers, and relevant telemetry systems
Web application security	Kali and the chosen application host; Wazuh/Zeek for defensive observation
SOC investigation	Wazuh, sensor-01, relevant endpoints, and analyst-01; Kali when generating authorized test activity
OSINT	Kali for initial research; a dedicated OSINT workstation remains a future expansion
Cloud security	Cloud resources and identities chosen for that week's objectives; Kali only where useful


For normal lab connectivity, pfSense must be running. Lab hostname resolution depends on dc-01. Endpoint reporting requires wazuh-01; network observation requires sensor-01 and its host mirroring. The current sensor mirror script periodically includes active ports on vmbr1; Kali-specific mirrored capture was not separately validated in this build.
When choosing a study week, define the objective, start the systems it depends on, verify only the needed capabilities, establish suitable recovery points, and then build the exercises. Finished work and evidence should be preserved before resetting systems. Broader DFIR, cloud, IAM, and other capabilities continue to be built as separate systems.

Troubleshooting notes
Symptom	Next check
Installer starts after installation	Remove the installer ISO from the virtual CD/DVD drive and check boot order
Guest agent is inactive	Confirm the package, Proxmox QEMU Agent option, and service status; a full stop/start may be required after changing the virtual hardware option
Kali retains its old dynamic IP	Confirm the reservation uses the NIC's actual MAC locally, apply changes, and renew the lease/restart
Wazuh hostname does not resolve	Check the configured DNS server, dc-01 availability, and the lab DNS record
Agent is absent from Wazuh	Check service status, configured manager address, connectivity, and /var/ossec/logs/ossec.log
Package install fails	Read the error, check APT repository reachability and available disk space, and resolve the specific failure before taking the baseline snapshot
xrdp is inactive	Expected in the final configuration; personal access currently uses the Proxmox console


Why this matters
Kali adds an offensive and reconnaissance workstation alongside the lab's defensive monitoring. It is ready as an infrastructure baseline for later topic-specific exercises. The build did not include scans, attacks, student access, or full functional validation of every tool.

Learning reflection
This build separated infrastructure readiness from exercises: establish the VM, networking, updates, telemetry, useful tool collections, and a recovery point first. Future study objectives determine which tools and systems need deeper configuration and validation.

References
- Kali installer images
- Kali image verification
- Kali metapackages
- Kali package group details
- Wazuh agent installation
- Kali Xfce and RDP