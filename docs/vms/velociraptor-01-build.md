VM purpose
velociraptor-01 provides centralized endpoint investigation and evidence-collection capability for the MutaSpace lab. The first enrolled endpoint is kali-01. The server dashboard is accessed from analyst-01 through an SSH tunnel.

The goal is a modular personal learning environment: choose a study topic, activate the relevant systems, build exercises around that objective, preserve results, and reset the appropriate machines afterward. This build establishes the Velociraptor server, client enrollment, access, restart recovery, and snapshots. Student access remains paused. No forensic collection exercise was performed during this build.

VM configuration
Setting	Built configuration
Proxmox node	mutaspace-soc-node01
VM ID / name	115 / velociraptor-01
OS	Ubuntu Server 24.04 LTS, standard installation
CPU	1 socket, 2 cores, type host
RAM	4096 MiB, ballooning disabled
Disk	60 GiB SCSI, I/O thread and discard enabled
Disk controller / cache	VirtIO SCSI single / default, no cache
BIOS / machine / display	Proxmox defaults, SeaBIOS
QEMU Agent option	Enabled
Network device	VirtIO, vmbr1, VLAN tag blank, NIC firewall unchecked
Start at boot	Unchecked
Ubuntu account	velociraptoradmin
Profile display name	Velociraptor Admin
Hostname	velociraptor-01
Management address	10.10.10.80/24, DHCP reservation
Gateway / lab DNS	10.10.10.1 / 10.10.10.10
Velociraptor version	0.77.3, Linux AMD64 Sumo MUSL build
Datastore	/opt/velociraptor
Logs selection	logs, relative to datastore
Deployment type	Self Signed SSL
Internal PKI validity	2 years
Registry client writeback	No
Frontend address / port	10.10.10.80:8000
GUI address / port	127.0.0.1:8889
Dashboard account	velociraptoradmin, separate from the Ubuntu account
Server snapshot	velociraptor-baseline, RAM excluded


The disk was reduced from the initially proposed 100 GiB to 60 GiB to fit the shared host's storage budget. The operating system and software do not require the full allowance; future evidence collections drive growth. Disk expansion and retention choices should follow observed usage.

Private addresses and domain names are authorized lab examples. Adapt them to your environment. MAC addresses, passwords, configuration contents containing private keys, and private installation packages are excluded from this guide. The configuration files and generated packages must not be committed to GitHub.

1. Install Ubuntu
Create the VM using the settings above and select the Ubuntu Server 24.04 ISO. Start the VM and choose Try or Install Ubuntu Server.
1. Select English, English (US) keyboard, and standard Ubuntu Server.
2. Keep automatic DHCP on the management interface. Leave proxy blank and keep the default archive mirror.
3. Use the entire virtual disk. Disable the LVM group option and leave encryption unchecked for this build. Review the layout and confirm writing changes to this VM disk.
4. Set display name Velociraptor Admin, server name velociraptor-01, and username velociraptoradmin. Choose a private password.
5. Skip Ubuntu Pro if prompted.
6. Install OpenSSH server. Password authentication was left enabled; no SSH identity was imported.
7. Select no featured server snaps.
8. Finish installation and reboot. Disconnect the ISO if prompted or if the installer starts again.
9. Sign in as velociraptoradmin.

2. Update and install the guest agent
Run on velociraptor-01. These commands update the OS and install the Proxmox guest agent, download tools, and trusted CA certificates:
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y qemu-guest-agent curl wget ca-certificates
sudo systemctl start qemu-guest-agent
sudo reboot

After login:
systemctl is-active qemu-guest-agent
hostname
ip -4 -brief address

Completed checkpoint: guest agent active, hostname correct, initial address 10.10.10.116/24.

3. Reserve the IP and check lab DNS
The pfSense LAN DHCP pool is 10.10.10.100 through 10.10.10.200. Reserve the unused address 10.10.10.80 outside that pool.

In pfSense Services > DHCP Server > LAN, add a static mapping using the NIC's actual MAC read locally from Proxmox VM Hardware. Enter it directly into pfSense without sharing or publishing it. Set:
- IP address: 10.10.10.80.
- Hostname: velociraptor-01.
- Description: Velociraptor endpoint investigation server.
Save and apply, then restart the VM to obtain the reserved lease:
sudo reboot

After login, run on velociraptor-01:
ip -4 -brief address
ip route show default
getent hosts wazuh-01.mutaspace.local
getent hosts dc-01.mutaspace.local

Completed results: reserved address .80/24, gateway 10.10.10.1, Wazuh resolution 10.10.10.20, and domain controller resolution 10.10.10.10. The guest remains a DHCP client. A DNS record for the Velociraptor hostname was not separately created or verified; endpoint configuration uses its reserved IP.

4. Download and verify Velociraptor
The exact build used was velociraptor-v0.77.3-linux-amd64-sumo-musl.gz. The static MUSL build avoids the Ubuntu 26.04 requirement listed for the regular Linux binary on the download page. Sumo is listed as a server build.

For a future build, check the official download page for the chosen release and its published verification information rather than assuming this pinned release is still current.
Run on velociraptor-01:
mkdir -p ~/velociraptor-setup
chmod 700 ~/velociraptor-setup
cd ~/velociraptor-setup
umask 077

curl -fL -o velociraptor.gz \
  https://github.com/Velocidex/velociraptor/releases/download/v0.77.3/velociraptor-v0.77.3-linux-amd64-sumo-musl.gz

echo 'b67c983f6d3860d9858dc3739a49893f2e0b432969e606b6b30bb3d31d4fdea8  velociraptor.gz' \
  | sha256sum -c -

Require velociraptor.gz: OK before continuing. This hash is the compressed release asset's SHA-256 digest obtained from the official GitHub release metadata.
gunzip velociraptor.gz
echo 'f5909e2510c3b70427e34295a79a486478aa29924f844855633021cea2f2c090  velociraptor' \
  | sha256sum -c -
chmod 750 velociraptor
./velociraptor version

The second hash applies to the unpacked executable and is the value on the official download table. The initial build incorrectly compared that value against the compressed file; using the correct compressed hash resolved the mismatch. Do not treat a mismatch as acceptable without resolving which exact file the expected hash describes.

Completed version output: 0.77.3, commit 7d287b0b9, build time 2026-10-04T10:07:19Z, system Linux, architecture AMD64.

5. Generate the private server configuration
Run on velociraptor-01:
cd ~/velociraptor-setup
umask 077
./velociraptor config generate -i
umask, without an n, restricts newly created files to the current account. The wizard generates security material along with the deployment settings.

Use these selections:
Wizard field	Value
Deployment type	Self Signed SSL
Server OS	Linux
Datastore directory	/opt/velociraptor
Logs directory	logs
Internal PKI expiration	2 Years
Registry for client writeback	No
Public DNS name of Master Frontend	10.10.10.80
DNS type	None, configure DNS manually
Experimental websocket communications	No
Frontend port	8000
GUI port	8889
Admin username	velociraptoradmin
Admin password	A private dashboard password
Additional admin users	Leave next username blank to finish
Output configuration	server.config.yaml


The frontend name field accepts the address clients will use, despite its public-DNS wording. The Ubuntu and dashboard accounts are separate even though their names match.
Edit the generated file locally:
nano ~/velociraptor-setup/server.config.yaml
In the existing Frontend: section, set:
  bind_address: 10.10.10.80

Leave the existing GUI: bind address as 127.0.0.1. Preserve all other configuration and key material. Save with Ctrl+O, Enter, then Ctrl+X:
chmod 600 ~/velociraptor-setup/server.config.yaml
The frontend accepts endpoint communications on the lab interface. The dashboard remains accessible only locally or through an SSH tunnel. Certificate renewal remains a future maintenance task; no renewal was tested in this build.

6. Package and install the server
Run on velociraptor-01:
cd ~/velociraptor-setup
mkdir -p packages
chmod 700 packages
umask 077

./velociraptor debian server \
  --config ./server.config.yaml \
  --output ./packages

ls -lh packages/*.deb

For the installed 0.77.3 binary, --output is an output directory. Supplying a .deb filename caused the initial packaging failure. The successful package was packages/velociraptor-server-0.77.3.amd64.deb.
chmod 600 packages/velociraptor-server-0.77.3.amd64.deb
sudo dpkg -i ./packages/velociraptor-server-0.77.3.amd64.deb
sudo systemctl enable --now velociraptor_server
systemctl is-active velociraptor_server
sudo ss -lntp | grep -E ':(8000|8889)\b'

Completed results: service active, frontend listening at 10.10.10.80:8000, GUI at 127.0.0.1:8889.

The observed installed server executable is /usr/local/bin/velociraptor; its service loads /etc/velociraptor/server.config.yaml. Confirm rather than assume paths when using another release:
sudo systemctl show velociraptor_server -p ExecStart --value --no-pager

The server package contains private configuration and keys. Keep it private like the server configuration itself.

7. Access the dashboard from analyst-01
Run on analyst-01, in a terminal:
ssh -N -L 127.0.0.1:8889:127.0.0.1:8889 velociraptoradmin@10.10.10.80

For a new SSH connection, verify the host key fingerprint against the server through a trusted console before accepting it. Enter the Ubuntu account password, not the dashboard password. A connected tunnel remains open without returning a prompt; no output is normal.
Open the browser on analyst-01 at:
https://127.0.0.1:8889

The self-signed certificate causes a browser warning. Confirm this is the intended local tunnel connection, continue, and sign in with the dashboard account. Dashboard access was successfully verified. Keep the terminal open while using it; Ctrl+C ends the tunnel.

8. Export and validate the client configuration
Run on velociraptor-01. This uses the installed server configuration as the source of truth:
cd ~/velociraptor-setup
umask 077
sudo ./velociraptor \
  --config /etc/velociraptor/server.config.yaml \
  config client > client.fixed.config.yaml
chmod 600 client.fixed.config.yaml

Check the actual certificate value rather than only looking for a YAML field name. This small Python check uses PyYAML, which was available on the Ubuntu server during this build:
python3 - <<'PY'
from pathlib import Path
import yaml

path = Path.home() / "velociraptor-setup/client.fixed.config.yaml"
config = yaml.safe_load(path.read_text()) or {}
client = config.get("Client") or {}
cert = client.get("ca_certificate") or ""

print("Client section present:", bool(client))
print("CA certificate characters:", len(cert))
print("PEM certificate header present:", "-----BEGIN CERTIFICATE-----" in cert)
PY

Completed export results: Client present True, certificate length 1204, PEM header present True; file size 5908 bytes. Other deployments may have different certificate lengths. Require nonempty certificate content and the expected PEM header. If import yaml fails on a new Ubuntu installation, install python3-yaml and repeat the check.

The original client package was built from a different export and failed on Kali with No Client.ca_certificate configured. Replacing the installed client configuration with the verified export above resolved startup. The exact cause of the original configuration problem was not established, so this guide does not attribute it to a particular packaging defect or editing mistake.

9. Build the client package
Run on velociraptor-01. For reproduction, package the validated export:
cd ~/velociraptor-setup
mkdir -p client-packages
chmod 700 client-packages
umask 077

./velociraptor debian client \
  --config ./client.fixed.config.yaml \
  --output ./client-packages

ls -lh client-packages/*.deb

The observed client package naming for this release is velociraptor_client_0.77.3_amd64.deb. The executable used for packaging is embedded by default; both server and Kali are Linux AMD64. The client package and configuration remain private.

10. Transfer and install on Kali
Start kali-01, VM 114. Its local username is kaliadmin and reserved IP is 10.10.10.70. Run on Kali, not on the server:
hostname
mkdir -p ~/velociraptor-setup
chmod 700 ~/velociraptor-setup
cd ~/velociraptor-setup

scp velociraptoradmin@10.10.10.80:/home/velociraptoradmin/velociraptor-setup/client-packages/velociraptor_client_0.77.3_amd64.deb .
chmod 600 velociraptor_client_0.77.3_amd64.deb
sudo dpkg -i ./velociraptor_client_0.77.3_amd64.deb

Verify hostname reports kali-01 before installing or changing client files. Authenticate the SCP transfer using the server's Ubuntu account password.

For the completed build, the initially installed configuration needed replacement. To reproduce the verified final configuration, copy the separately validated export and install it with restricted permissions. On Kali:
cd ~/velociraptor-setup
scp velociraptoradmin@10.10.10.80:/home/velociraptoradmin/velociraptor-setup/client.fixed.config.yaml .
chmod 600 client.fixed.config.yaml

sudo systemctl stop velociraptor_client
sudo cp /etc/velociraptor/client.config.yaml \
  /etc/velociraptor/client.config.yaml.before-fix
sudo install -o root -g root -m 600 client.fixed.config.yaml \
  /etc/velociraptor/client.config.yaml
sudo systemctl restart velociraptor_client
systemctl is-active velociraptor_client

Completed result: active. The installed client binary is /usr/local/bin/velociraptor_client. The service uses /etc/velociraptor/client.config.yaml and runs with root privileges to support endpoint evidence collection.

On analyst-01, search the dashboard clients for kali-01, open the matching endpoint, and check recent last-seen time. Kali appeared in the dashboard, confirming enrollment and communication. A running service alone is not that confirmation.

11. Restart validation
First restart Kali:
sudo reboot

After login, confirm systemctl is-active velociraptor_client returns active, then check Kali remains visible in the dashboard with current activity. The user confirmed the client stayed active and enrolled after reboot.
Next restart velociraptor-01:
sudo reboot

The server reboot closes analyst-01's SSH tunnel. After login, confirm systemctl is-active velociraptor_server returns active. Reopen the tunnel on analyst-01, reload the dashboard, and confirm Kali reconnects with recent last-seen time. The user confirmed this checkpoint succeeded.

12. Recovery snapshots
Shut down each VM from its own terminal with sudo poweroff. In Proxmox, take snapshots with RAM excluded:
VM	Snapshot	Description
115	velociraptor-baseline	Velociraptor 0.77.3; IP .80; frontend 8000; GUI via SSH tunnel; Kali enrolled; restart verified
114	kali-velociraptor-baseline	Working Velociraptor client configuration; enrollment and reboot verified; Wazuh previously active


Both snapshots were confirmed created. Keep the earlier kali-baseline as the pre-Velociraptor rollback point. Snapshot restoration was not tested. These snapshots contain private configuration and client identity material and must remain private.

Snapshots do not cover pfSense reservations or a separate off-host backup. Preserve evidence before rollback. Restoring the server can rewind its datastore and collection history; restoring an endpoint can rewind its client state. Do not clone an enrolled endpoint into a simultaneous duplicate without handling its unique identity. A coordinated recovery plan is needed before future exercises that depend on retained evidence.

Troubleshooting notes
Symptom	Interpretation / next action
Checksum mismatch	Distinguish compressed release asset from unpacked executable; use the matching hash and exact release file
unmask: command not found	Correct shell command is umask 077
Package builder treats .deb name as a directory	In this release, pass an existing directory to --output
/usr/local/bin/velociraptor.bin missing	Actual installed server executable here is /usr/local/bin/velociraptor; inspect the service startup command
Client shows activating (auto-restart)	It is repeatedly failing, not successfully starting; inspect status/logs and run without --quiet
No Client.ca_certificate configured	Validate certificate content in the client configuration and re-export from the active server configuration
Grep reports certificate missing, but key exists	Check the parsed YAML value; a typo in a check or an empty field can mislead; do not assume the configuration is valid from a field-name count alone
Client file missing on server	Client repair commands belong on Kali; confirm the hostname before running them
SSH tunnel stays blank	Normal after successful authentication with ssh -N
Dashboard fails after server reboot	Reopen the SSH tunnel on analyst-01
Local tunnel port already in use	Check whether the previous tunnel is still running; avoid starting duplicate forwards


For client startup diagnostics, run on Kali:
sudo systemctl status velociraptor_client --no-pager -l
sudo journalctl -u velociraptor_client -n 30 --no-pager
sudo systemctl stop velociraptor_client
sudo /usr/local/bin/velociraptor_client \
  --config /etc/velociraptor/client.config.yaml client -v

Read the first error. If the interactive client remains running, press Ctrl+C before restarting the service. Share only necessary error lines, not configuration files, keys, or credentials.

Validation results and remaining scope
Capability	Completed evidence
VM foundation	Ubuntu installed, updates completed, QEMU guest agent active
Network	Reserved .80 address, gateway and lab DNS checked
Download	Correct compressed checksum passed; version 0.77.3 verified
Server	Package installed, service active, intended listeners verified
Dashboard	Access and authentication from analyst-01 through SSH tunnel
Client configuration	Verified export contains a nonempty PEM CA certificate
Kali enrollment	Client active; endpoint visible in dashboard
Restart recovery	Client reboot and server reboot checkpoints passed
Snapshots	Server and updated Kali snapshots created


Future work includes functional artifact collection validation, additional endpoint enrollment, evidence retention and storage policy, off-host backup and restore testing, certificate renewal, and any integrations needed for later study objectives. Velociraptor's server was not enrolled in Wazuh during this build. Kali had Wazuh enrollment before this addition; concurrent post-installation Wazuh health was not rechecked.

Dependencies and weekly activation
- Start pfSense for normal lab routing. Start dc-01 when lab DNS is needed.
- Start velociraptor-01 and the endpoint VMs relevant to the study objective.
- Start analyst-01 for dashboard access and open the SSH tunnel.
- Start Wazuh and sensor-01 when the objective includes endpoint alerts or network observation.
- Preserve results before resetting any endpoint or restoring the server datastore.

Velociraptor can support future DFIR, incident response, endpoint hunting, and artifact-analysis study weeks. For pentesting weeks it can provide an investigation perspective on selected endpoints. This build establishes the control plane and enrollment; future exercises will validate particular evidence-collection capabilities.

Learning reflection
Successful setup required checking each layer separately: network reachability, the server process, listening addresses, dashboard access, client configuration, client enrollment, and recovery after reboot. Two checks prevented misleading conclusions: a hash must correspond to the exact compressed or unpacked file, and an active service must be paired with confirmed server-client communication.

References
- Velociraptor downloads
- Pinned 0.77.3 release metadata
- Deployment quickstart
- Client deployment
- Security configuration