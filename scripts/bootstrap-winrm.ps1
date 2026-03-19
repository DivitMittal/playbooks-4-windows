# bootstrap-winrm.ps1
# Run this script ON THE WINDOWS MACHINE (as Administrator) before running
# any Ansible playbooks from a remote control node (macOS/Linux).
#
# Usage (elevated PowerShell):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\bootstrap-winrm.ps1
#
# After this script completes, you can run from your Mac:
#   ansible-playbook playbooks/bootstrap.yml

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n[>>] $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

# ── 1. Set Execution Policy ────────────────────────────────────────────────────
Write-Step "Setting execution policy to RemoteSigned"
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
Write-OK "ExecutionPolicy = RemoteSigned"

# ── 2. Enable TLS 1.2 (required for Scoop/winget downloads) ──────────────────
Write-Step "Enabling TLS 1.2"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-OK "TLS 1.2 enabled"

# ── 3. Configure WinRM ────────────────────────────────────────────────────────
Write-Step "Configuring WinRM"

# Quick config: enables HTTP listener and sets sensible defaults
winrm quickconfig -Force

# Allow NTLM auth (needed for workgroup machines)
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate -Value $true
Set-Item -Path WSMan:\localhost\Service\Auth\NTLM -Value $true

# Increase shell memory limit (Ansible module output can be large)
Set-Item -Path WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 1024

# Allow connections from any host (restrict this on production systems)
Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

Write-OK "WinRM configured"

# ── 4. Firewall rules ─────────────────────────────────────────────────────────
Write-Step "Configuring Windows Firewall"

$httpRule = Get-NetFirewallRule -DisplayName "WinRM HTTP" -ErrorAction SilentlyContinue
if (-not $httpRule) {
    New-NetFirewallRule -DisplayName "WinRM HTTP" -Direction Inbound `
        -Protocol TCP -LocalPort 5985 -Action Allow | Out-Null
    Write-OK "Created firewall rule: WinRM HTTP (5985)"
} else {
    Write-OK "Firewall rule already exists: WinRM HTTP"
}

$httpsRule = Get-NetFirewallRule -DisplayName "WinRM HTTPS" -ErrorAction SilentlyContinue
if (-not $httpsRule) {
    New-NetFirewallRule -DisplayName "WinRM HTTPS" -Direction Inbound `
        -Protocol TCP -LocalPort 5986 -Action Allow | Out-Null
    Write-OK "Created firewall rule: WinRM HTTPS (5986)"
} else {
    Write-OK "Firewall rule already exists: WinRM HTTPS"
}

# ── 5. Self-signed certificate for HTTPS ─────────────────────────────────────
Write-Step "Creating self-signed certificate for WinRM HTTPS"
$hostname = $env:COMPUTERNAME
$existingCert = Get-ChildItem -Path Cert:\LocalMachine\My |
    Where-Object { $_.Subject -like "*$hostname*" } |
    Select-Object -First 1

if (-not $existingCert) {
    $cert = New-SelfSignedCertificate `
        -DnsName $hostname `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -NotAfter (Get-Date).AddYears(5)
    Write-OK "Created cert: $($cert.Thumbprint)"

    $existingHttps = Get-WSManInstance -ResourceURI winrm/config/listener `
        -SelectorSet @{Transport="HTTPS"} -ErrorAction SilentlyContinue
    if (-not $existingHttps) {
        New-WSManInstance -ResourceURI winrm/config/listener `
            -SelectorSet @{Transport="HTTPS"; Address="*"} `
            -ValueSet @{Hostname=$cert.Subject; CertificateThumbprint=$cert.Thumbprint} `
            | Out-Null
        Write-OK "HTTPS listener created"
    }
} else {
    Write-OK "Certificate already exists: $($existingCert.Thumbprint)"
}

# ── 6. Start and enable WinRM service ─────────────────────────────────────────
Write-Step "Ensuring WinRM service is running"
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM -ErrorAction SilentlyContinue
$svc = Get-Service -Name WinRM
Write-OK "WinRM service status: $($svc.Status)"

# ── 7. Verify ─────────────────────────────────────────────────────────────────
Write-Step "Verifying WinRM configuration"
winrm enumerate winrm/config/listener

$ip = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike "127.*" } |
    Select-Object -First 1).IPAddress

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
Write-Host " Bootstrap complete!" -ForegroundColor Green
Write-Host " Machine IP  : $ip" -ForegroundColor White
Write-Host " WinRM HTTP  : http://${ip}:5985/wsman" -ForegroundColor White
Write-Host " WinRM HTTPS : https://${ip}:5986/wsman" -ForegroundColor White
Write-Host "`n On your Mac, update inventory/hosts.yml:" -ForegroundColor Yellow
Write-Host "   ansible_host: $ip" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Yellow
