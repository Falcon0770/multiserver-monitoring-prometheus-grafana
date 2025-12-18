# ============================================
#  WINDOWS SERVER MONITORING SETUP
#  PowerShell Setup Script
#  Run as Administrator!
# ============================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Blue
Write-Host "║     WINDOWS SERVER MONITORING SETUP            ║" -ForegroundColor Blue
Write-Host "║          Windows Exporter Installation         ║" -ForegroundColor Blue
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Blue
Write-Host ""

# Get server info
$ServerName = $env:COMPUTERNAME
$ServerIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*" } | Select-Object -First 1).IPAddress

Write-Host "Server: $ServerName ($ServerIP)" -ForegroundColor Green
Write-Host ""

# ============================================
# Configuration
# ============================================
$WindowsExporterVersion = "0.25.1"
$WindowsExporterPort = 9182
$InstallDir = "C:\Program Files\windows_exporter"
$DownloadUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v$WindowsExporterVersion/windows_exporter-$WindowsExporterVersion-amd64.msi"
$MsiPath = "$env:TEMP\windows_exporter.msi"

# Collectors to enable
$Collectors = "cpu,cs,logical_disk,memory,net,os,process,service,system,tcp"

# ============================================
# Check if already installed
# ============================================
Write-Host "[1/5] Checking existing installation..." -ForegroundColor Yellow

$ExistingService = Get-Service -Name "windows_exporter" -ErrorAction SilentlyContinue
if ($ExistingService) {
    Write-Host "Windows Exporter is already installed." -ForegroundColor Cyan
    Write-Host "Current status: $($ExistingService.Status)" -ForegroundColor Cyan
    Write-Host ""
    $Reinstall = Read-Host "Do you want to reinstall? (y/n)"
    if ($Reinstall -ne "y" -and $Reinstall -ne "Y") {
        Write-Host "Exiting. Use 'Restart-Service windows_exporter' to restart if needed." -ForegroundColor Yellow
        exit 0
    }
    
    # Stop and uninstall existing
    Write-Host "Stopping existing service..." -ForegroundColor Yellow
    Stop-Service windows_exporter -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    # Find and uninstall existing MSI
    $Installed = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*windows_exporter*" }
    if ($Installed) {
        Write-Host "Uninstalling existing version..." -ForegroundColor Yellow
        $Installed.Uninstall() | Out-Null
    }
}

Write-Host "✓ Ready for installation" -ForegroundColor Green
Write-Host ""

# ============================================
# Download Windows Exporter
# ============================================
Write-Host "[2/5] Downloading Windows Exporter v$WindowsExporterVersion..." -ForegroundColor Yellow

try {
    # Use TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $MsiPath -UseBasicParsing
    Write-Host "✓ Downloaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to download: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please download manually from:" -ForegroundColor Yellow
    Write-Host "  $DownloadUrl" -ForegroundColor Cyan
    exit 1
}
Write-Host ""

# ============================================
# Install Windows Exporter
# ============================================
Write-Host "[3/5] Installing Windows Exporter..." -ForegroundColor Yellow

try {
    $MsiArgs = @(
        "/i"
        "`"$MsiPath`""
        "ENABLED_COLLECTORS=`"$Collectors`""
        "LISTEN_PORT=`"$WindowsExporterPort`""
        "/qn"
        "/norestart"
    )
    
    $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $MsiArgs -Wait -PassThru
    
    if ($Process.ExitCode -eq 0) {
        Write-Host "✓ Installation completed" -ForegroundColor Green
    }
    else {
        throw "MSI installer returned exit code: $($Process.ExitCode)"
    }
}
catch {
    Write-Host "✗ Installation failed: $_" -ForegroundColor Red
    exit 1
}
Write-Host ""

# ============================================
# Configure Firewall
# ============================================
Write-Host "[4/5] Configuring firewall..." -ForegroundColor Yellow

try {
    # Remove existing rule if any
    Remove-NetFirewallRule -DisplayName "Windows Exporter (Prometheus)" -ErrorAction SilentlyContinue
    
    # Add new rule
    New-NetFirewallRule -DisplayName "Windows Exporter (Prometheus)" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $WindowsExporterPort `
        -Action Allow `
        -Profile Any `
        -Description "Allow Prometheus to scrape Windows Exporter metrics" | Out-Null
    
    Write-Host "✓ Firewall rule created for port $WindowsExporterPort" -ForegroundColor Green
}
catch {
    Write-Host "⚠ Could not configure firewall automatically: $_" -ForegroundColor Yellow
    Write-Host "  Please manually open port $WindowsExporterPort in Windows Firewall" -ForegroundColor Yellow
}
Write-Host ""

# ============================================
# Verify Installation
# ============================================
Write-Host "[5/5] Verifying installation..." -ForegroundColor Yellow

Start-Sleep -Seconds 3

# Check service
$Service = Get-Service -Name "windows_exporter" -ErrorAction SilentlyContinue
if ($Service -and $Service.Status -eq "Running") {
    Write-Host "✓ Windows Exporter service is running" -ForegroundColor Green
}
else {
    Write-Host "⚠ Service not running. Attempting to start..." -ForegroundColor Yellow
    Start-Service windows_exporter -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $Service = Get-Service -Name "windows_exporter"
    if ($Service.Status -eq "Running") {
        Write-Host "✓ Service started successfully" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Could not start service. Check Event Viewer for errors." -ForegroundColor Red
    }
}

# Test metrics endpoint
try {
    $Response = Invoke-WebRequest -Uri "http://localhost:$WindowsExporterPort/metrics" -UseBasicParsing -TimeoutSec 5
    if ($Response.StatusCode -eq 200) {
        Write-Host "✓ Metrics endpoint is responding" -ForegroundColor Green
    }
}
catch {
    Write-Host "⚠ Could not reach metrics endpoint: $_" -ForegroundColor Yellow
}

# ============================================
# Done!
# ============================================
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    SETUP COMPLETE!                        ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "SEND THIS INFORMATION TO YOUR MONITORING TEAM:" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host ""
Write-Host "  Server Name:       $ServerName"
Write-Host "  Server IP:         $ServerIP"
Write-Host "  Windows Exporter:  http://${ServerIP}:${WindowsExporterPort}/metrics"
Write-Host "  OS Type:           Windows"
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Cyan
Write-Host "  Check status:   Get-Service windows_exporter"
Write-Host "  Restart:        Restart-Service windows_exporter"
Write-Host "  View metrics:   Start-Process http://localhost:$WindowsExporterPort/metrics"
Write-Host ""

# Cleanup
Remove-Item $MsiPath -Force -ErrorAction SilentlyContinue

