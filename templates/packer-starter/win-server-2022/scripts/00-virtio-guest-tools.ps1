# packer/win-server-2022/scripts/00-virtio-guest-tools.ps1
#
# WHAT THIS IS
#   The first Packer provisioner. It installs the full virtio-win guest tools package
#   from the driver CD that is still attached at this point in the build.
#
# WHY IT EXISTS
#   Driver injection in windowsPE only loaded what Setup needed to reach the disk and
#   the network. This installs the rest properly, into the running OS:
#
#     * vioscsi / NetKVM / vioserial   - already loaded, now registered as real
#                                        driver packages so Windows Update does not
#                                        replace them with something worse
#     * Balloon + blnsvr.exe           - the balloon DRIVER alone does nothing. A
#                                        Windows guest without blnsvr.exe running as
#                                        a service pins its full dedicated RAM no
#                                        matter what the hypervisor asks for. dc-01
#                                        runs floating = 0 so it will not balloon,
#                                        but every other Windows clone from a similar
#                                        template will, and the service belongs in
#                                        the image either way.
#     * qemu-ga                        - already installed by cd/setup.ps1; the MSI
#                                        here upgrades/repairs it harmlessly.
#     * vioinput, viorng, pvpanic, etc.
#
# WHY NOT JUST DOWNLOAD IT
#   Because the build plane is deliberately allowed only enough internet access to
#   fetch what it cannot get locally, and the driver ISO is already mounted. Fewer
#   network dependencies is fewer things that break a build in a year's time.

$ErrorActionPreference = 'Stop'

Write-Host 'Locating the virtio-win CD by content rather than by drive letter'

$virtioRoot = $null
foreach ($vol in (Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' -and $_.DriveLetter })) {
    $root = '{0}:\' -f $vol.DriveLetter
    if (Test-Path (Join-Path $root 'virtio-win-gt-x64.msi')) {
        $virtioRoot = $root
        break
    }
}

if (-not $virtioRoot) {
    throw @'
virtio-win-gt-x64.msi was not found on any attached CD-ROM.

Check that virtio_win_iso_file points at a real virtio-win ISO that has already been
uploaded to Proxmox (this repo never downloads it for you), and that the ISO is not
still compressed.
'@
}

Write-Host "Found virtio-win media at $virtioRoot"

# ---------------------------------------------------------------------------
# Trust the Red Hat driver publisher certificate first.
#
# Without this, the driver installs still succeed but Windows raises a trust prompt
# for each unsigned-to-this-machine package. A prompt on a machine nobody is looking
# at is a hung build.
# ---------------------------------------------------------------------------
$certSource = Join-Path $virtioRoot 'virtio-win-gt-x64.msi'
try {
    $cert = (Get-AuthenticodeSignature -FilePath $certSource).SignerCertificate
    if ($cert) {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store 'TrustedPublisher', 'LocalMachine'
        $store.Open('ReadWrite')
        $store.Add($cert)
        $store.Close()
        Write-Host 'Added the virtio-win signing certificate to TrustedPublisher'
    }
} catch {
    Write-Host "WARNING: could not stage the driver signing certificate: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# Guest tools (drivers + blnsvr)
# ---------------------------------------------------------------------------
Write-Host 'Installing virtio-win-gt-x64.msi'
$p = Start-Process -FilePath 'msiexec.exe' `
    -ArgumentList '/i', ('"{0}virtio-win-gt-x64.msi"' -f $virtioRoot), '/qn', '/norestart', '/l*v', 'C:\Windows\Temp\virtio-gt.log' `
    -Wait -PassThru

# 3010 is ERROR_SUCCESS_REBOOT_REQUIRED. It is a success, and the windows-restart
# provisioner that follows this script is what handles it.
if ($p.ExitCode -notin @(0, 3010)) {
    throw "virtio-win-gt-x64.msi failed with exit code $($p.ExitCode). See C:\Windows\Temp\virtio-gt.log"
}
Write-Host "virtio-win-gt-x64.msi exit code $($p.ExitCode)"

# ---------------------------------------------------------------------------
# QEMU guest agent (idempotent - cd/setup.ps1 already installed it)
# ---------------------------------------------------------------------------
$agentMsi = Join-Path $virtioRoot 'guest-agent\qemu-ga-x86_64.msi'
if (Test-Path $agentMsi) {
    Write-Host 'Ensuring the QEMU guest agent is installed and current'
    $p = Start-Process -FilePath 'msiexec.exe' `
        -ArgumentList '/i', ('"{0}"' -f $agentMsi), '/qn', '/norestart' `
        -Wait -PassThru
    if ($p.ExitCode -notin @(0, 3010, 1638)) {
        # 1638 = "another version of this product is already installed", which is fine.
        throw "qemu-ga-x86_64.msi failed with exit code $($p.ExitCode)"
    }
}

# ---------------------------------------------------------------------------
# Verify rather than assume (docs/README.md: "validation over assumptions")
# ---------------------------------------------------------------------------
$svc = Get-Service -Name 'QEMU-GA' -ErrorAction SilentlyContinue
if (-not $svc) {
    throw 'The QEMU-GA service does not exist after installation. Packer and OpenTofu both depend on it.'
}
Set-Service -Name 'QEMU-GA' -StartupType Automatic
Write-Host "QEMU-GA service status: $($svc.Status)"

$blnsvr = Get-Service -Name 'BalloonService' -ErrorAction SilentlyContinue
if ($blnsvr) {
    Write-Host "BalloonService status: $($blnsvr.Status)"
} else {
    Write-Host 'WARNING: BalloonService (blnsvr.exe) is not present. Ballooning will not reclaim memory from this guest.'
}

Write-Host 'virtio guest tools complete'
