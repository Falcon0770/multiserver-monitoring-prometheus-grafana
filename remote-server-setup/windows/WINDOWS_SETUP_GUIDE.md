# Windows Server Monitoring Setup Guide

## Overview
For Windows servers, we use **Windows Exporter** (formerly WMI Exporter) instead of Node Exporter.
This collects Windows-specific metrics like CPU, Memory, Disk, Network, Services, and more.

---

## Quick Setup (PowerShell - Run as Administrator)

### Option 1: One-Line Installation (Recommended)

Open PowerShell as Administrator and run:

```powershell
# Download and run the setup script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/prometheus-community/windows_exporter/master/installer/install.ps1" -OutFile "$env:TEMP\install-windows-exporter.ps1"; & "$env:TEMP\install-windows-exporter.ps1"
```

Or use the manual method below for more control.

---

### Option 2: Manual Installation

#### Step 1: Download Windows Exporter

```powershell
# Create directory
New-Item -ItemType Directory -Force -Path "C:\Program Files\windows_exporter"

# Download latest release (check https://github.com/prometheus-community/windows_exporter/releases for latest)
$version = "0.25.1"
$url = "https://github.com/prometheus-community/windows_exporter/releases/download/v$version/windows_exporter-$version-amd64.msi"
Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\windows_exporter.msi"
```

#### Step 2: Install as Windows Service

```powershell
# Install with default collectors
msiexec /i "$env:TEMP\windows_exporter.msi" ENABLED_COLLECTORS="cpu,cs,logical_disk,net,os,service,system,memory,process" /qn

# Or install with all common collectors
msiexec /i "$env:TEMP\windows_exporter.msi" ENABLED_COLLECTORS="cpu,cs,logical_disk,memory,net,os,process,service,system,tcp,thermalzone" /qn
```

#### Step 3: Configure Firewall

```powershell
# Allow Windows Exporter through firewall
New-NetFirewallRule -DisplayName "Windows Exporter" -Direction Inbound -Port 9182 -Protocol TCP -Action Allow
```

#### Step 4: Verify Installation

```powershell
# Check service status
Get-Service windows_exporter

# Test metrics endpoint
Invoke-WebRequest -Uri "http://localhost:9182/metrics" -UseBasicParsing | Select-Object -First 20
```

---

## After Installation - Send This Info to Monitoring Team

```
Server Name:     <YOUR_HOSTNAME>
Server IP:       <YOUR_IP_ADDRESS>
Windows Exporter: http://<YOUR_IP>:9182/metrics
```

---

## Available Collectors

Windows Exporter supports many collectors. Common ones include:

| Collector | Description |
|-----------|-------------|
| `cpu` | CPU usage metrics |
| `cs` | Computer system info |
| `logical_disk` | Disk space and I/O |
| `memory` | Memory usage |
| `net` | Network interface stats |
| `os` | OS version and uptime |
| `process` | Process metrics |
| `service` | Windows service status |
| `system` | System calls and threads |
| `iis` | IIS web server metrics |
| `mssql` | SQL Server metrics |
| `exchange` | Exchange Server metrics |
| `ad` | Active Directory metrics |

---

## Useful Commands

```powershell
# Check service status
Get-Service windows_exporter

# Restart service
Restart-Service windows_exporter

# Stop service
Stop-Service windows_exporter

# Start service
Start-Service windows_exporter

# View service configuration
sc.exe qc windows_exporter

# Check if port is listening
netstat -an | findstr 9182
```

---

## Troubleshooting

### Service won't start
```powershell
# Check Windows Event Log
Get-EventLog -LogName Application -Source windows_exporter -Newest 10
```

### Can't access from remote
1. Check Windows Firewall rule exists
2. Check if port 9182 is open: `netstat -an | findstr 9182`
3. Test from monitoring server: `curl http://<WINDOWS_IP>:9182/metrics`

### Metrics not showing
```powershell
# Reinstall with specific collectors
msiexec /x "$env:TEMP\windows_exporter.msi" /qn
msiexec /i "$env:TEMP\windows_exporter.msi" ENABLED_COLLECTORS="cpu,cs,logical_disk,net,os,service,system,memory" /qn
```

---

## Port Reference

| Exporter | Port | Description |
|----------|------|-------------|
| Windows Exporter | 9182 | Windows system metrics |
| Node Exporter | 9100 | Linux system metrics (not for Windows) |
| MySQL Exporter | 9104 | MySQL database metrics |
| MSSQL Exporter | 9399 | SQL Server metrics |


