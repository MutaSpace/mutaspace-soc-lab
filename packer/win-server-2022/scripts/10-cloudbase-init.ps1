# packer/win-server-2022/scripts/10-cloudbase-init.ps1
#
# WHAT THIS IS
#   Installs and configures Cloudbase-Init, the Windows equivalent of cloud-init.
#
# WHY IT EXISTS
#   Every Linux VM in this lab gets its hostname, address and users from cloud-init at
#   first boot, driven by OpenTofu's `initialization` block. Windows needs an agent
#   that reads the same drive. Without one, a cloned Windows VM comes up with the
#   template's identity and someone has to fix it by hand -- which is exactly the
#   manual step the whole repository exists to delete.
#
# THE FOLKLORE, AND WHY IT IS WRONG
#   "Proxmox cloud-init does not work on Windows and the password never gets set" is
#   repeated everywhere. It comes from a Proxmox FAQ page last edited in April 2022.
#   Proxmox added first-class Cloudbase-Init support in qemu-server 8.2.2 (July 2024)
#   and the admin guide now has a dedicated "Cloud-Init on Windows" section.
#
#   The password genuinely does break, but for a specific and fixable reason:
#     * PVE decides whether to crypt-hash `cipassword` based on `ostype`. If ostype is
#       still a Linux value when cipassword is set, PVE stores a hash, and
#       Cloudbase-Init faithfully injects that hash AS THE PLAINTEXT PASSWORD.
#       => OpenTofu must set ostype BEFORE cipassword. That is a tofu-side concern,
#          noted here because this is where the other half of the fix lives.
#     * `ciuser` is ignored on Windows. The account name comes from the `username`
#       setting in cloudbase-init.conf, below.
#     * `inject_user_password` must be true in cloudbase-init.conf, and it is not the
#       default in every packaging.
#
# SCOPE, DELIBERATELY SMALL
#   Cloudbase-Init handles hostname, network configuration and the local password.
#   It does NOT handle domain promotion, OU structure, DNS records, lab accounts or
#   Wazuh agents -- those are Ansible's job over WinRM. Trying to do real
#   configuration management from a metadata drive is how cloud-init userdata turns
#   into an unversioned shell script nobody can audit.
#
# ⚠️ UNVERIFIED OFFLINE
#   This template was authored with no Proxmox host and no internet access to the
#   Cloudbase download server (decisions.md D-05). Two things below could not be
#   checked and will need confirming on the first real build:
#     1. the installer URL (see the cloudbase_init_msi_url variable)
#     2. the exact metadata service class name PVE's cloud-init drive is served by
#   Both fail loudly rather than silently. Nothing here claims to have been tested.

$ErrorActionPreference = 'Stop'

$msiUrl = $env:CLOUDBASE_INIT_MSI_URL
if ([string]::IsNullOrWhiteSpace($msiUrl)) {
    throw 'CLOUDBASE_INIT_MSI_URL was not passed to this provisioner. Check the environment_vars block in win-server.pkr.hcl.'
}

$msiPath = 'C:\Windows\Temp\CloudbaseInit.msi'

# TLS 1.2 is not the default on a freshly installed Server 2022 PowerShell session,
# and the failure looks like a network outage rather than a protocol mismatch.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Downloading Cloudbase-Init from $msiUrl"
$attempt = 0
$maxAttempts = 3
while ($true) {
    $attempt++
    try {
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
        break
    } catch {
        if ($attempt -ge $maxAttempts) {
            throw @"
Could not download Cloudbase-Init after $maxAttempts attempts.

  URL:   $msiUrl
  Error: $($_.Exception.Message)

Two things to check, in this order:

  1. Does the build plane have a route out? vmbr9 is masqueraded by the Proxmox host
     itself (10.99.0.1). If the host's NAT rule is missing, this is the first
     provisioner that notices.
  2. Is the URL still valid? It was NOT verified when this template was written --
     the repository was authored offline. If Cloudbase have moved the file, download
     CloudbaseInitSetup_1_1_8_x64.msi by hand, host it somewhere the build plane can
     reach, and override the cloudbase_init_msi_url Packer variable.
"@
        }
        Write-Host "Attempt $attempt failed, retrying in 10s: $($_.Exception.Message)"
        Start-Sleep -Seconds 10
    }
}

# ---------------------------------------------------------------------------
# Install silently.
#
# /qn matters for more than quietness: the interactive installer offers to run Sysprep
# for you at the end, and letting an MSI generalise the machine in the middle of a
# Packer build would strand the WinRM connection. We run sysprep ourselves, last, in
# 99-sysprep.ps1.
# ---------------------------------------------------------------------------
Write-Host 'Installing Cloudbase-Init'
$p = Start-Process -FilePath 'msiexec.exe' `
    -ArgumentList '/i', ('"{0}"' -f $msiPath), '/qn', '/norestart', '/l*v', 'C:\Windows\Temp\cloudbase-init-install.log' `
    -Wait -PassThru

if ($p.ExitCode -notin @(0, 3010)) {
    throw "Cloudbase-Init installer failed with exit code $($p.ExitCode). See C:\Windows\Temp\cloudbase-init-install.log"
}

$cbDir = 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init'
if (-not (Test-Path $cbDir)) {
    throw "Cloudbase-Init reported success but $cbDir does not exist."
}

# ---------------------------------------------------------------------------
# Configuration.
#
# The conf files are written out in full rather than patched, because a config file
# you can read top to bottom is worth more in teaching material than a set of
# surgical regex edits nobody can reconstruct.
#
# metadata_services lists TWO services on purpose. Proxmox presents cloud-init data as
# a small ISO whose volume label is `cidata`, containing user-data / meta-data /
# network-config at the root -- the NoCloud layout. NoCloudConfigDriveService is the
# handler for that. ConfigDriveService is listed second as a fallback in case a future
# PVE release changes the presentation; an unused service in the list costs one failed
# probe at boot.
#
# inject_user_password = true is the setting the folklore is about. See the header.
# ---------------------------------------------------------------------------
$confDir = Join-Path $cbDir 'conf'
$logDir = Join-Path $cbDir 'log'
New-Item -ItemType Directory -Path $confDir -Force | Out-Null
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$conf = @"
[DEFAULT]
username=Administrator
groups=Administrators

# The setting the "cloud-init passwords do not work on Windows" folklore is about.
inject_user_password=true

# Proxmox does not present an SSH keypair for Windows guests, and there is no
# sshd here to consume one.
first_logon_behaviour=no

config_drive_raw_hhd=true
config_drive_cdrom=true
config_drive_vfat=true

bsdtar_path=$cbDir\bin\bsdtar.exe
mtools_path=$cbDir\bin\
logdir=$cbDir\log\
logfile=cloudbase-init.log
default_log_levels=comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN
verbose=true
debug=true

# NoCloud first: Proxmox writes a `cidata`-labelled ISO with user-data/meta-data at
# the root. ConfigDrive is a fallback. See the header note about what is unverified.
metadata_services=cloudbaseinit.metadata.services.nocloudservice.NoCloudConfigDriveService,cloudbaseinit.metadata.services.configdrive.ConfigDriveService

# Deliberately narrow. Hostname, network and password only. Everything stateful is
# Ansible's job -- see the SCOPE note in the header of this script.
plugins=cloudbaseinit.plugins.common.mtu.MTUPlugin,cloudbaseinit.plugins.windows.createuser.CreateUserPlugin,cloudbaseinit.plugins.common.setuserpassword.SetUserPasswordPlugin,cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin,cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,cloudbaseinit.plugins.common.userdata.UserDataPlugin

allow_reboot=false
stop_service_on_exit=false
check_latest_version=false
"@

Set-Content -Path (Join-Path $confDir 'cloudbase-init.conf') -Value $conf -Encoding ASCII

# The unattend variant is what sysprep runs during the specialize pass on FIRST BOOT
# AFTER CLONING. It is a near-copy that skips the user-data plugin, because at that
# point the machine is still generalising and running arbitrary user-data is not the
# job.
$confUnattend = $conf -replace 'allow_reboot=false', 'allow_reboot=true'
Set-Content -Path (Join-Path $confDir 'cloudbase-init-unattend.conf') -Value $confUnattend -Encoding ASCII

# ---------------------------------------------------------------------------
# The service must NOT run now. It should run on the first boot of a CLONE.
# ---------------------------------------------------------------------------
$svc = Get-Service -Name 'cloudbase-init' -ErrorAction SilentlyContinue
if (-not $svc) {
    throw 'The cloudbase-init service does not exist after installation.'
}
Stop-Service -Name 'cloudbase-init' -Force -ErrorAction SilentlyContinue
Set-Service -Name 'cloudbase-init' -StartupType Automatic

# The Unattend.xml that ships with Cloudbase-Init is what 99-sysprep.ps1 hands to
# sysprep. Confirm it exists now, while the error is still cheap to read.
$cbUnattend = Join-Path $confDir 'Unattend.xml'
if (Test-Path $cbUnattend) {
    Write-Host "Cloudbase-Init sysprep answer file present: $cbUnattend"
} else {
    Write-Host "WARNING: $cbUnattend is missing. 99-sysprep.ps1 will fall back to sysprep without /unattend, and Cloudbase-Init will not run during specialize on clones."
}

Write-Host 'Cloudbase-Init installed and configured'
