sensor-01: Zeek network sensor and Wazuh integration
Build completed: October 6, 2026. Suggested repository path: docs/vms/sensor-01-build.md.

VM purpose
sensor-01 adds passive network visibility to the MutaSpace lab. Proxmox copies traffic from the lab bridge to a dedicated capture interface. Zeek turns that traffic into connection, DNS, HTTP, and TLS metadata. The Wazuh agent collects selected JSON logs for manager processing.

This infrastructure supports future SOC, defensive security, pentesting, incident response, and research work. This build establishes the capability; exercises and custom detections come later.

Configuration and network placement
Setting	Built configuration
Hypervisor	Proxmox, node mutaspace-soc-node01
VM name / ID	sensor-01 / 113
OS	Ubuntu Server 24.04 LTS
CPU	1 socket, 2 cores, CPU type host
RAM	4 GB, fixed allocation
Disk	60 GiB SCSI, VirtIO SCSI single, I/O thread enabled
Installation storage	Entire disk, without LVM
Firmware / machine	Proxmox defaults
Administrative user	sensorsoc
Management NIC	VirtIO net0, guest ens18, bridge vmbr1
Capture NIC	VirtIO net1, guest ens19, bridge vmbr2, NIC firewall unchecked
Management address	10.10.10.60/24, DHCP reservation
Gateway	10.10.10.1, pfSense LAN
DNS	10.10.10.10, lab domain controller
Lab domain	mutaspace.local
Wazuh manager	wazuh-01.mutaspace.local, 10.10.10.20
Zeek	8.0.10, installed under /opt/zeek
Wazuh agent	4.14.5, dashboard agent ID 009


These private addresses are example lab values. Reproducing the build requires adapting the subnet, DNS, manager address, VM ID, interface names, and storage selection to the destination environment. No passwords, enrollment secrets, or private keys are included.

vmbr1 is the existing internal lab LAN. 
vmbr2 is a dedicated capture bridge with no physical uplink, host IP address, or gateway. A bridge alone does not mirror traffic: the host script below supplies the copies.

1. Install and prepare Ubuntu
Create the VM with the settings above and install standard Ubuntu Server 24.04. Install OpenSSH if remote administration is desired. Use your own administrative password.

Run these commands on sensor-01. They update the OS and install the guest agent, download tools, and packet-capture utility:
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y qemu-guest-agent curl wget tcpdump
sudo systemctl start qemu-guest-agent
sudo reboot

In Proxmox, enable Options > QEMU Guest Agent. Fully shut down and start the VM after enabling the option so the virtual guest-agent channel is available. Confirm the service after boot:
sudo systemctl status qemu-guest-agent --no-pager

2. Reserve the management IP
The VM initially received 10.10.10.114. The pfSense LAN DHCP pool is 10.10.10.100 through 10.10.10.200, with no pre-existing static mappings at the time of this build.

In the pfSense LAN DHCP configuration, create and apply a static mapping for the VM's management NIC MAC, address 10.10.10.60, and hostname sensor-01. The reservation is outside the dynamic pool. Use the actual MAC shown by Proxmox; do not copy another VM's MAC.

Restart the VM or renew its DHCP lease. On sensor-01:
ip -br address
ip route
resolvectl status
getent hosts wazuh-01.mutaspace.local

Confirm ens18 has 10.10.10.60/24, the default route uses 10.10.10.1, and the lab DNS resolves the Wazuh manager. The reservation controls the IP; the guest remains a DHCP client.

3. Add the capture bridge and NIC
On the Proxmox node, open System > Network > Create > Linux Bridge:
- Name: vmbr2.
- Autostart: enabled.
- IPv4/IPv6 addresses, gateways, and bridge ports: blank.
- VLAN aware: unchecked for this build.

Apply the configuration. Add a second VirtIO network device to sensor-01 using vmbr2, with the NIC firewall unchecked. Start the VM and identify the new interface with ip -br link. This build uses ens19.

The following file disables IP addressing on the capture NIC. It leaves the existing management configuration in place. Run on sensor-01, replacing ens19 if your interface differs:
sudo tee /etc/netplan/60-sensor-capture.yaml >/dev/null <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    ens19:
      dhcp4: false
      dhcp6: false
      accept-ra: false
      link-local: []
      optional: true
EOF
sudo chmod 600 /etc/netplan/60-sensor-capture.yaml
sudo netplan apply
ip -br address

Checkpoint: ens18 retains the management address. ens19 has no IPv4 or IPv6 address and becomes active when the capture application opens it.

4. Mirror lab traffic on the Proxmox host
All commands in this section run on the Proxmox host, not inside sensor-01.
For VM 113, tap113i1 is the capture NIC's host interface on vmbr2; tap113i0 is its management NIC on vmbr1. Verify these relationships before configuring rules:
ls /sys/class/net/vmbr1/brif/
ls /sys/class/net/vmbr2/brif/
ip link show tap113i1

Adapt both names if you use another VM ID. Proxmox firewall settings can change the bridge-facing interface names, so inspect actual bridge membership rather than assuming every source port is a tap interface.
This script attaches an ingress mirror to each current lab bridge port, excluding the sensor's management port. Packets entering the bridge from VMs and the router are copied to the capture NIC. It preserves existing ingress/clsact qdiscs and uses filter priority 49152 for this build's mirror rules. Reserve that priority for this script.
cat > /usr/local/sbin/mutaspace-mirror <<'EOF'
#!/bin/bash
set -eu

capture_port="tap113i1"

# Wait until the sensor capture interface exists.
[ -d "/sys/class/net/$capture_port" ] || exit 0
[ -e "/sys/class/net/vmbr2/brif/$capture_port" ] || exit 1

for path in /sys/class/net/vmbr1/brif/*; do
  [ -e "$path" ] || continue
  port="${path##*/}"

  # Exclude sensor management traffic as a mirror source.
  [ "$port" = "tap113i0" ] && continue

  case "$(tc qdisc show dev "$port")" in
    *clsact*|*ingress*) ;;
    *) tc qdisc add dev "$port" clsact ;;
  esac

  existing_rule="$(tc filter show dev "$port" ingress pref 49152)"

  if [[ "$existing_rule" != *"Egress Mirror to device $capture_port)"* ]]; then
    if [ -n "$existing_rule" ]; then
      tc filter del dev "$port" ingress protocol all pref 49152
    fi

    tc filter add dev "$port" ingress protocol all \
      pref 49152 handle 1 matchall \
      action mirred egress mirror dev "$capture_port"
  fi

  echo "Mirroring $port to sensor-01"
done
EOF
chmod 750 /usr/local/sbin/mutaspace-mirror
bash -n /usr/local/sbin/mutaspace-mirror
/usr/local/sbin/mutaspace-mirror

The service and timer below rerun the script after boot and every 15 seconds. This accommodates VM ports appearing or being recreated after a VM restart. If the capture interface is absent, the script exits successfully and waits for a later timer run.
cat > /etc/systemd/system/mutaspace-mirror.service <<'EOF'
[Unit]
Description=MutaSpace lab traffic mirroring
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/mutaspace-mirror
EOF

cat > /etc/systemd/system/mutaspace-mirror.timer <<'EOF'
[Unit]
Description=Maintain MutaSpace traffic mirror rules

[Timer]
OnBootSec=30s
OnUnitActiveSec=15s
AccuracySec=1s
Unit=mutaspace-mirror.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now mutaspace-mirror.timer
systemctl start mutaspace-mirror.service
systemctl status mutaspace-mirror.timer --no-pager
journalctl -u mutaspace-mirror.service -n 20 --no-pager
Checkpoint: timer is active and waiting, with mirror confirmations in the service journal. A oneshot mirror service becoming inactive after a successful run is expected.

Example read-only inspection on the host:
tc filter show dev tap100i1 ingress pref 49152
Use an actual source bridge port. Expected action: mirred (Egress Mirror to device tap113i1).

On sensor-01, verify that packets reach the capture NIC:
sudo tcpdump -ni ens19 -c 10

This build observed traffic in both directions and zero kernel drops in that brief sample. This does not establish loss-free capture under sustained load. The script covers vmbr1 only; future network segments require additional mirror design.

5. Install Zeek
Run on sensor-01. The repository supplies the zeek-8.0 release train for Ubuntu 24.04. The completed build installed version 8.0.10; a later install may receive a newer patch from that train. See the official package instructions linked below if package naming or supported releases change.
sudo apt install -y curl gnupg ca-certificates
curl -fsSL -o /tmp/zeek-release.key \
  https://download.opensuse.org/repositories/security:/zeek/xUbuntu_24.04/Release.key
sudo gpg --dearmor -o /usr/share/keyrings/zeek-archive-keyring.gpg \
  /tmp/zeek-release.key
echo 'deb [signed-by=/usr/share/keyrings/zeek-archive-keyring.gpg] https://download.opensuse.org/repositories/security:/zeek/xUbuntu_24.04/ /' \
  | sudo tee /etc/apt/sources.list.d/zeek.list
sudo apt update
sudo apt install -y zeek-8.0
/opt/zeek/bin/zeek --version

If the dependency installation presents a Postfix dialog, this build selected Local only with mail system name sensor-01.mutaspace.local.
Back up the initial Zeek files, then configure a standalone sensor on the capture NIC:
sudo cp /opt/zeek/etc/node.cfg /opt/zeek/etc/node.cfg.original
sudo cp /opt/zeek/etc/networks.cfg /opt/zeek/etc/networks.cfg.original
sudo cp /opt/zeek/share/zeek/site/local.zeek \
  /opt/zeek/share/zeek/site/local.zeek.before-json

sudo tee /opt/zeek/etc/node.cfg >/dev/null <<'EOF'
[zeek]
type=standalone
host=localhost
interface=ens19
EOF

sudo tee /opt/zeek/etc/networks.cfg >/dev/null <<'EOF'
10.10.10.0/24    MutaSpace Lab LAN
EOF

Edit /opt/zeek/share/zeek/site/local.zeek with sudo nano and add the following line once, preserving the existing contents. It switches Zeek logs to JSON for Wazuh collection:
@load policy/tuning/json-logs
Validate and deploy:
sudo /opt/zeek/bin/zeekctl check
sudo /opt/zeek/bin/zeekctl deploy
sudo /opt/zeek/bin/zeekctl status
sudo tail -n 3 /opt/zeek/logs/current/conn.log

Checkpoint: check reports scripts are OK, the node is running, and connection log lines are JSON. Other log families appear when matching traffic is observed; an absent HTTP log does not by itself establish a failed deployment.

6. Start Zeek automatically
No Zeek systemd unit was present in this installation. Create this unit on sensor-01 to deploy Zeek at boot and stop it during shutdown:
sudo tee /etc/systemd/system/mutaspace-zeek.service >/dev/null <<'EOF'
[Unit]
Description=MutaSpace Zeek network monitoring
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/zeek/bin/zeekctl deploy
ExecStop=/opt/zeek/bin/zeekctl stop
TimeoutStartSec=120
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now mutaspace-zeek.service
sudo /opt/zeek/bin/zeekctl status

The unit can show active (exited) because ZeekControl launches the process. Use zeekctl status to check the actual Zeek process.

7. Enroll the Wazuh agent
Use the Wazuh dashboard's Deploy new agent wizard for Linux DEB AMD64. Choose agent name sensor-01, the manager address, and the default group. Use a package version compatible with your manager; the command below records the package used in this build.

Run on sensor-01:
wget https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.5-1_amd64.deb
sudo WAZUH_MANAGER='wazuh-01.mutaspace.local' \
  WAZUH_AGENT_NAME='sensor-01' \
  dpkg -i ./wazuh-agent_4.14.5-1_amd64.deb
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-agent
sudo systemctl status wazuh-agent --no-pager

Checkpoint: service is running and the dashboard shows sensor-01 as Active. Its assigned ID in this build is 009; another deployment will receive its own ID.

8. Collect Zeek JSON logs
On sensor-01, back up and edit the agent configuration:
sudo cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.before-zeek
sudo nano /var/ossec/etc/ossec.conf

Insert these blocks inside an existing <ossec_config> section, outside other nested sections. Preserve the existing configuration:
<localfile>
  <location>/opt/zeek/logs/current/conn.log</location>
  <log_format>json</log_format>
</localfile>
<localfile>
  <location>/opt/zeek/logs/current/dns.log</location>
  <log_format>json</log_format>
</localfile>
<localfile>
  <location>/opt/zeek/logs/current/http.log</location>
  <log_format>json</log_format>
</localfile>
<localfile>
  <location>/opt/zeek/logs/current/ssl.log</location>
  <log_format>json</log_format>
</localfile>

These blocks instruct the agent to read the four log streams. They do not create custom detection rules or enable raw-event indexing.
sudo /var/ossec/bin/wazuh-logcollector -t
sudo systemctl restart wazuh-agent
sudo systemctl status wazuh-agent --no-pager
Checkpoint: configuration validation returns no errors and the agent remains running.

9. Verify delivery at the Wazuh manager
All commands in this section run on wazuh-01, not sensor-01. Temporarily enabling JSON archives makes ordinary received events visible for delivery validation. It can increase disk usage, so restore the prior setting after the check.
sudo grep -nE '<logall_json>|<logall>' /var/ossec/etc/ossec.conf
sudo cp /var/ossec/etc/ossec.conf \
  /var/ossec/etc/ossec.conf.before-zeek-check
sudo nano /var/ossec/etc/ossec.conf

In the existing manager <global> section, change the existing setting from <logall_json>no</logall_json> to:
<logall_json>yes</logall_json>

Keep <logall>no</logall> unchanged. Validate, restart, and allow fresh lab traffic to arrive:
sudo /var/ossec/bin/wazuh-analysisd -t
sudo systemctl restart wazuh-manager
sudo grep -F '/opt/zeek/logs/current/' \
  /var/ossec/logs/archives/archives.json | tail -n 3

Completed result: events showed agent 009, name sensor-01, address 10.10.10.60, location /opt/zeek/logs/current/conn.log, and the JSON decoder with connection data. This proves receipt and JSON decoding of connection records, not individual delivery of every configured log family or a detection alert.

Edit the manager configuration again and restore the previous <logall_json>no</logall_json> value. Validate and restart:
sudo /var/ossec/bin/wazuh-analysisd -t
sudo systemctl restart wazuh-manager

Final state: JSON archiving is off. Wazuh processes collected events, but ordinary Zeek records are not all retained as raw manager archives or searchable dashboard records. Alerts require matching rules. Zeek's own logs remain available on sensor-01.

10. Configure rotation and retention
On sensor-01, back up and edit ZeekControl's configuration:
sudo cp /opt/zeek/etc/zeekctl.cfg /opt/zeek/etc/zeekctl.cfg.before-retention
sudo nano /opt/zeek/etc/zeekctl.cfg

Set the existing entries to these values, without adding duplicate entries:
LogRotationInterval = 3600
LogExpireInterval = 7 day

These configure hourly rotation and expiration of archived logs older than seven days. ZeekControl's maintenance command must run regularly to apply expiration.
sudo /opt/zeek/bin/zeekctl check
sudo /opt/zeek/bin/zeekctl deploy
sudo apt install -y cron
sudo systemctl enable --now cron
sudo tee /etc/cron.d/mutaspace-zeek >/dev/null <<'EOF'
*/5 * * * * root /opt/zeek/bin/zeekctl cron
EOF
sudo chmod 644 /etc/cron.d/mutaspace-zeek
sudo /opt/zeek/bin/zeekctl cron
sudo /opt/zeek/bin/zeekctl status

The cron file must end with a newline. Configuration validation and the manual maintenance run completed successfully. Seven-day expiration was configured, but deletion of seven-day-old logs was not observed during this new build. Retention is not a hard disk-space cap; future traffic volume may require adjusting it.

11. Restart validation and snapshot
During the completed build, sensor-01 was fully shut down and started again from Proxmox. Zeek started automatically with a new process ID, the host timer restored mirroring, and fresh connection, DNS, HTTP, and TLS logs appeared. A TLS connection included bidirectional byte counts. This validates recovery after the sensor VM's stop/start; a Proxmox host reboot was not tested.

After the final retention changes, Zeek configuration checks and status passed. A Proxmox snapshot named zeek-wazuh-baseline was created with RAM excluded.
Suggested snapshot description:
Ubuntu Server 24.04; management 10.10.10.60; capture ens19; Zeek 8.0.10; Wazuh agent and JSON log collection; automatic startup; hourly rotation and seven-day retention.

The VM snapshot does not include host bridge configuration, the mirroring script, or its service/timer. Keep separate copies of those host files and the Proxmox network configuration, preferably off the host. This guide records their contents; an off-host backup was not completed as part of this build. A snapshot is a rollback point, not a substitute for backup. Do not clone the enrolled VM into another active sensor without giving it a unique identity and Wazuh enrollment.


Troubleshooting notes
Symptom	Interpretation or resolution
RTNETLINK answers: File exists when applying a mirror	A qdisc or filter may already exist. Inspect it. The final script preserves a matching rule and replaces stale rules at its reserved priority rather than blindly adding duplicates.
Script reports an unexpected end of file	A partial paste or missing terminator can leave incomplete shell syntax. Replace the whole script and run bash -n before executing it.
Host bridge includes fwpr... ports	Proxmox firewall topology can insert intermediate bridge ports. Mirror the actual ports listed under vmbr1/brif.
Mirror service shows inactive after running	Expected for a successful oneshot service. Check the timer, journal, and installed filters.
No packets on ens19	Check VM capture NIC, vmbr2 membership, host destination interface, source filters, and whether lab traffic is being generated.
0 unit files listed for Zeek	This installation did not supply an existing Zeek unit. Create the documented mutaspace-zeek.service.
Zeek unit says active, but no logs appear	Use zeekctl status, inspect capture traffic, and check configuration. The unit's state alone is not process health.
Agent download returns HTTP 403	Check the full official URL. The failed attempt omitted the /wazuh-agent/ directory after /main/w/.
wazuh-agent.service not found	Confirm the agent package installed successfully before starting the service.
Grep for manager archiving options returns nothing on sensor-01	Those options belong to the manager configuration. Run that inspection on wazuh-01.
No Zeek hits in the Wazuh dashboard	Agent connectivity does not imply raw event indexing or matching detection rules. Validate manager receipt using temporary archives as documented.


Validation results and remaining scope
Capability	Evidence / status
Management connectivity	Reserved .60 address and expected DNS/network configuration confirmed
Capture isolation	Dedicated NIC without an IP address on isolated vmbr2
Host mirroring	Eight existing source ports confirmed; sensor management port excluded
Packet receipt	Packet capture observed bidirectional traffic
Zeek deployment	Version 8.0.10; scripts OK; process running; JSON logs present
Automatic recovery	Sensor stop/start restored Zeek and mirrored traffic
Wazuh enrollment	Agent active, ID 009
Collection configuration	Four JSON log paths configured; collector validation passed
Manager delivery	Connection events received and decoded as JSON
Retention	Hourly rotation, seven-day expiry, five-minute maintenance configured
Snapshot	zeek-wazuh-baseline, without RAM
Custom Zeek detections	Future work
Full raw-event indexing	Future design decision; not enabled
Sustained capture quality / host reboot	Not tested in this build


Why this matters
The lab now has endpoint visibility through Wazuh and passive network metadata through Zeek. This provides a foundation for later attack-and-defense scenarios, investigations, and recorded demonstrations. The next build is kali-01, expanding offensive tooling and initial OSINT capability while the wider environment continues to grow.
Learning reflection
The main implementation lesson was to separate the roles clearly: Proxmox mirrors packets, the capture NIC receives them, Zeek interprets them, and Wazuh collects and processes selected records. Each role needs its own validation. A running service or an active agent alone does not prove packet capture, record delivery, or detection.

References
- Zeek binary packages
- ZeekControl configuration and maintenance
- Linux tc mirroring actions
- Wazuh Linux agent installation
- Wazuh configuration validation
