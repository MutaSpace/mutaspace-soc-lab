# vuln-01 build guide

Completed: October 8, 2026, America/Chicago. Repository destination: `docs/vms/vuln-01-build.md`.

## Purpose and scope

`vuln-01` provides vulnerability management capability through Greenbone Community Edition containers. It will support authorized scanning, findings triage, remediation tracking, and retesting within the MutaSpace personal lab.

This build establishes the operating system, Docker deployment, private dashboard access, current feeds, scanner connectivity, reboot recovery, and baseline snapshot. No vulnerability scan or assessment exercise was performed. Student access remains paused. The lab goal is to select a study topic, start the relevant systems, preserve results, and reset the appropriate baselines.

## Configuration

| Setting | Built configuration |
| --- | --- |
| Proxmox node | `mutaspace-soc-node01` |
| VM ID / name | `116` / `vuln-01` |
| Operating system | Ubuntu Server 24.04 LTS, standard installation |
| CPU | 1 socket, 4 cores, type `host` |
| RAM | 8192 MiB, ballooning disabled |
| Disk | 80 GiB SCSI, discard and I/O thread enabled |
| Controller / BIOS | VirtIO SCSI single / SeaBIOS |
| QEMU Agent | Enabled in Proxmox and running in Ubuntu |
| Network | VirtIO on `vmbr1`, NIC firewall unchecked |
| Start at boot | Disabled |
| Ubuntu account / display name | `vulnadmin` / `Vulnerability Admin` |
| Management address | `10.10.10.90/24`, pfSense DHCP reservation |
| Lab gateway / DNS design | `10.10.10.1` / `10.10.10.10` |
| Deployment folder | `~/greenbone-community-edition` |
| Compose file | `compose.yaml`, downloaded from Greenbone documentation |
| Container project | `greenbone-community-edition` |
| Dashboard binding | Host loopback HTTPS port 443; official file also publishes loopback port 9392 |
| Dashboard access | SSH tunnel from `analyst-01`, local port 8443 |
| Greenbone account | `admin`, with a private replacement password |
| Snapshot | `greenbone-baseline`, VM powered off, RAM excluded |

The 80 GiB disk allows room for Ubuntu, container images, feed data, persistent volumes, and future results. Greenbone's documentation recommends 4 cores, 8 GB RAM, and 60 GB available storage. This is an initial allocation; growth depends on scan history and retention.

Private IP addresses and hostnames are reproducible lab examples. Replace them with your own network values. No MAC addresses, passwords, keys, or tokens are included. Exact Docker and Greenbone component versions and image digests were not captured in the build record. `stable` and `latest` tags can change; future reproductions may receive different versions.

## 1. Create the VM and install Ubuntu

Create VM 116 in Proxmox using the settings above and the Ubuntu Server 24.04 ISO.

1. Select English, your keyboard layout, and standard Ubuntu Server installation.
2. Leave networking on DHCP. Leave proxy blank and keep the default Ubuntu mirror.
3. Use the entire new VM disk. Disable LVM and encryption for this build. Confirm changes to that VM's virtual disk.
4. Set display name `Vulnerability Admin`, server name `vuln-01`, and username `vulnadmin`. Choose a private password.
5. Skip Ubuntu Pro. Install OpenSSH server with password authentication enabled; no SSH identity was imported.
6. Select no featured server snaps.
7. Finish, reboot, and detach the ISO if prompted.
8. Log in as `vulnadmin`.

## 2. Update Ubuntu and install the guest agent

Run on **vuln-01**. This updates Ubuntu and installs Proxmox integration and download prerequisites:

```bash
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y qemu-guest-agent curl ca-certificates
sudo systemctl start qemu-guest-agent
sudo reboot
```

After logging back in:

```bash
systemctl is-active qemu-guest-agent
ip -4 -brief address
```

Confirmed: guest agent `active`. Initial DHCP address was `10.10.10.117/24`.

## 3. Reserve the management address

In pfSense, open **Services → DHCP Server → LAN → Static Mappings → Add**.

| Field | Value |
| --- | --- |
| MAC | Enter VM 116's network MAC locally; do not publish or share it |
| IP address | `10.10.10.90`, after checking it is unused |
| Hostname | `vuln-01` |
| Description | `Greenbone vulnerability management server` |

The reservation is outside this lab's `.100–.200` dynamic pool. Save and apply. Reboot vuln-01, then check `ip -4 -brief address`. Confirmed address: `10.10.10.90/24`.

## 4. Install Docker Engine and Compose

This fresh VM had no previously installed Docker packages. On a reused system, follow Docker's official conflict-removal instructions first.

The signing key and repository let Ubuntu obtain verified packages from Docker's Ubuntu 24.04 repository:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

Check the service, Compose plugin, and container execution:

```bash
systemctl is-active docker
sudo docker compose version
sudo docker run --rm hello-world
```

All three passed: `active`, a Compose version, and `Hello from Docker!`. Docker commands use `sudo`; the account was not added to the Docker group.

## 5. Download and start Greenbone

The official Compose file defines services and persistent volumes. Download it, validate its syntax, and pull its images:

```bash
mkdir -p ~/greenbone-community-edition
cd ~/greenbone-community-edition
curl -fL https://greenbone.github.io/docs/latest/_static/compose.yaml -o compose.yaml
sudo docker compose -f compose.yaml config --quiet
sudo docker compose -f compose.yaml pull
```

Validation returned no errors and the pull completed. Start the services:

```bash
sudo docker compose -f compose.yaml up -d
sudo docker compose -f compose.yaml ps -a
```

Initial status showed running main services and healthy checks where configured. Setup services such as `configure-openvas`, `gpg-data`, `gvm-config`, and `pg-gvm-migrator` completed with `Exited (0)`. An exit code of zero is expected for successful one-time setup tasks. Feed services in this deployment remained running with healthy status.

Starting containers does not launch a scan. Feed import can continue after services start.

## 6. Replace the default Greenbone password

The Ubuntu account and Greenbone dashboard account are separate. Replace the initial Greenbone `admin` password before use. This prompts privately rather than placing the literal password in shell history:

```bash
cd ~/greenbone-community-edition
read -r -s -p "New Greenbone admin password: " GREENBONE_ADMIN_PASSWORD
echo
sudo docker compose -f compose.yaml exec -T -u gvmd gvmd \
  gvmd --user=admin --new-password="$GREENBONE_ADMIN_PASSWORD"
unset GREENBONE_ADMIN_PASSWORD
```

The command completed without error. Store the password privately. Do not commit credential files or record password-entry steps.

## 7. Open the dashboard from analyst-01

The official Compose file binds the dashboard to vuln-01's loopback interface. Keep that binding and use an SSH tunnel instead of exposing the dashboard on all interfaces.

On **analyst-01**, run:

```bash
ssh -N -L 127.0.0.1:8443:127.0.0.1:443 vulnadmin@10.10.10.90
```

Authenticate with the Ubuntu `vulnadmin` password. The occupied terminal normally produces no further output. Leave it open.

In the analyst-01 browser, visit **https://127.0.0.1:8443**. A warning is expected for the deployment's self-signed certificate. Continue for this known local tunnel and sign in as `admin` using the replacement Greenbone password.

Confirmed: dashboard opened and login succeeded. Close the tunnel with Ctrl+C when finished.

## 8. Check feeds and scanner connectivity

In Greenbone:

1. Open **Administration → Feed Status**. Confirm feed status is current.
2. Open **Configuration → Scanners → OpenVAS Default**, then verify the scanner.

Confirmed: feeds current and scanner verification passed. This proves feed readiness and manager-to-scanner connectivity, not scan accuracy or successful target assessment.

## 9. Check reboot recovery

On vuln-01, run `sudo reboot`. This disconnects the SSH tunnel.

After the VM boots, log in and run:

```bash
cd ~/greenbone-community-edition
sudo docker compose -f compose.yaml ps -a
```

Allow initialization and health checks to complete. Reopen the SSH tunnel on analyst-01, sign in to the dashboard, and verify the scanner again.

Confirmed: dashboard access returned and scanner verification passed after reboot.

## 10. Take the baseline snapshot

On vuln-01:

```bash
sudo poweroff
```

After Proxmox shows VM 116 stopped, open **Snapshots → Take Snapshot**:

- Name: `greenbone-baseline`
- Description: `Ubuntu 24.04; Docker and Greenbone configured; feeds current; scanner verified; SSH tunnel access and reboot recovery passed.`
- Include RAM: unchecked.

Confirmed: snapshot completed October 8, 2026. Snapshot restoration was not tested. A snapshot is not an independent backup.

## Operating notes and troubleshooting

- Start VM 116 when this capability is needed, then reopen the SSH tunnel. The VM does not start automatically with the host.
- If the browser cannot connect, first confirm the VM is running, the tunnel is still open, and the containers are up.
- If local port 8443 is occupied, select another unused local port in the SSH command and use that same port in the browser.
- If startup reports an error, inspect it with `sudo docker compose -f compose.yaml logs --tail=100 SERVICE`, replacing `SERVICE` with the affected service, such as `gvmd` or `ospd-openvas`.
- If feeds are importing, allow them to finish before assessing scan readiness. Check the official troubleshooting guide rather than repeatedly recreating containers.
- Persistent state is in Docker volumes. Do not use `docker compose down -v` during routine maintenance: it deletes the deployment's volumes.
- Future scans must use explicitly authorized targets and appropriate target-network boundaries. No targets or scan tasks were created in this build.

## Deferred work

- First scan and validated findings, remediation, and retest workflow.
- Isolated disposable target environment.
- Wazuh agent enrollment for vuln-01, which was not performed here.
- Feed refresh schedule and controlled image-update procedure.
- Result/log retention, resource measurements under scan load, and storage growth monitoring.
- Independent backup and tested restoration of Greenbone data/configuration.
- Exact version/image-digest capture for a pinned deployment record.
- Snapshot rollback test and student access, if later requested.

## Official references

- [Greenbone Community Containers](https://greenbone.github.io/docs/latest/22.4/container/index.html)
- [Greenbone container troubleshooting](https://greenbone.github.io/docs/latest/22.4/container/troubleshooting.html)
- [Docker Engine installation on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)

The downloaded Compose file and image tags may change. Read the current official instructions before reproducing or upgrading this deployment. The original build used the official file available October 7, 2026, with baseline verification completed October 8.
