# Full Monitoring Stack Setup on Windows Server

This guide installs the complete Prometheus + Grafana + Windows Exporter stack on a Windows Server as native Windows Services (no Docker required).

---

## Prerequisites

- Windows Server 2016 or later
- Administrator access
- Internet connection (to download installers)

---

## Quick Setup (Automated Script)

For a one-click installation, run the `setup-full-stack.ps1` script as Administrator:

```powershell
.\setup-full-stack.ps1
```

Or follow the manual steps below.

---

## Manual Installation

### Step 1: Create Directories

Open PowerShell as Administrator:

```powershell
New-Item -ItemType Directory -Force -Path "C:\monitoring\prometheus"
New-Item -ItemType Directory -Force -Path "C:\monitoring\prometheus\data"
New-Item -ItemType Directory -Force -Path "C:\monitoring\grafana"
New-Item -ItemType Directory -Force -Path "C:\monitoring\tools"
```

---

### Step 2: Install Windows Exporter

```powershell
# Download Windows Exporter
$version = "0.25.1"
$url = "https://github.com/prometheus-community/windows_exporter/releases/download/v$version/windows_exporter-$version-amd64.msi"
Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\windows_exporter.msi"

# Install with common collectors
msiexec /i "$env:TEMP\windows_exporter.msi" ENABLED_COLLECTORS="cpu,cs,logical_disk,memory,net,os,process,service,system,tcp" /qn

# Verify installation
Start-Sleep -Seconds 5
Get-Service windows_exporter
```

---

### Step 3: Install Prometheus

```powershell
# Download Prometheus for Windows
$promVersion = "2.48.0"
$promUrl = "https://github.com/prometheus/prometheus/releases/download/v$promVersion/prometheus-$promVersion.windows-amd64.zip"
Invoke-WebRequest -Uri $promUrl -OutFile "$env:TEMP\prometheus.zip"

# Extract to monitoring folder
Expand-Archive -Path "$env:TEMP\prometheus.zip" -DestinationPath "C:\monitoring" -Force

# Rename folder for easier access
Rename-Item "C:\monitoring\prometheus-$promVersion.windows-amd64" "C:\monitoring\prometheus" -ErrorAction SilentlyContinue
```

---

### Step 4: Create Prometheus Configuration

```powershell
$ServerName = $env:COMPUTERNAME

@"
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Monitor Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: 'prometheus-server'

  # Monitor this Windows server
  - job_name: 'windows-exporter'
    static_configs:
      - targets: ['localhost:9182']
        labels:
          instance: '$ServerName'
          server: '$ServerName'
          environment: 'production'
          os_type: 'windows'
          service: 'os'
"@ | Out-File -FilePath "C:\monitoring\prometheus\prometheus.yml" -Encoding UTF8
```

---

### Step 5: Install NSSM (Service Manager)

NSSM allows us to run Prometheus as a Windows Service:

```powershell
# Download NSSM
Invoke-WebRequest -Uri "https://nssm.cc/release/nssm-2.24.zip" -OutFile "$env:TEMP\nssm.zip"

# Extract
Expand-Archive -Path "$env:TEMP\nssm.zip" -DestinationPath "$env:TEMP\nssm" -Force

# Copy to monitoring folder
Copy-Item "$env:TEMP\nssm\nssm-2.24\win64\nssm.exe" "C:\monitoring\tools\nssm.exe"
```

---

### Step 6: Install Prometheus as Windows Service

```powershell
# Install Prometheus as a Windows service
C:\monitoring\tools\nssm.exe install Prometheus "C:\monitoring\prometheus\prometheus.exe"
C:\monitoring\tools\nssm.exe set Prometheus AppParameters "--config.file=C:\monitoring\prometheus\prometheus.yml --storage.tsdb.path=C:\monitoring\prometheus\data --web.enable-lifecycle --storage.tsdb.retention.time=30d"
C:\monitoring\tools\nssm.exe set Prometheus AppDirectory "C:\monitoring\prometheus"
C:\monitoring\tools\nssm.exe set Prometheus DisplayName "Prometheus Monitoring"
C:\monitoring\tools\nssm.exe set Prometheus Description "Prometheus time-series database"
C:\monitoring\tools\nssm.exe set Prometheus Start SERVICE_AUTO_START

# Start the service
Start-Service Prometheus

# Verify
Get-Service Prometheus
```

---

### Step 7: Install Grafana

```powershell
# Download Grafana
$grafanaVersion = "10.2.2"
$grafanaUrl = "https://dl.grafana.com/oss/release/grafana-$grafanaVersion.windows-amd64.msi"
Invoke-WebRequest -Uri $grafanaUrl -OutFile "$env:TEMP\grafana.msi"

# Install (installs as Windows service automatically)
msiexec /i "$env:TEMP\grafana.msi" /qn

# Wait for installation
Start-Sleep -Seconds 10

# Start service
Start-Service Grafana

# Verify
Get-Service Grafana
```

---

### Step 8: Open Firewall Ports

```powershell
# Windows Exporter (port 9182)
New-NetFirewallRule -DisplayName "Windows Exporter (Monitoring)" -Direction Inbound -Port 9182 -Protocol TCP -Action Allow

# Prometheus (port 9090)
New-NetFirewallRule -DisplayName "Prometheus (Monitoring)" -Direction Inbound -Port 9090 -Protocol TCP -Action Allow

# Grafana (port 3000)
New-NetFirewallRule -DisplayName "Grafana (Monitoring)" -Direction Inbound -Port 3000 -Protocol TCP -Action Allow
```

---

### Step 9: Verify Installation

```powershell
# Check all services are running
Get-Service windows_exporter, Prometheus, Grafana

# Test endpoints
Write-Host "Testing Windows Exporter..." -ForegroundColor Yellow
Invoke-WebRequest -Uri "http://localhost:9182/metrics" -UseBasicParsing | Select-Object StatusCode

Write-Host "Testing Prometheus..." -ForegroundColor Yellow
Invoke-WebRequest -Uri "http://localhost:9090/-/ready" -UseBasicParsing | Select-Object StatusCode

Write-Host "Testing Grafana..." -ForegroundColor Yellow
Invoke-WebRequest -Uri "http://localhost:3000/api/health" -UseBasicParsing | Select-Object StatusCode
```

---

## Post-Installation: Configure Grafana

### 1. Add Prometheus Data Source

1. Open Grafana: `http://localhost:3000`
2. Login: **admin** / **admin** (change password when prompted)
3. Go to: **Connections → Data Sources → Add data source**
4. Select **Prometheus**
5. URL: `http://localhost:9090`
6. Click **Save & Test**

### 2. Import Windows Dashboard

1. Go to: **Dashboards → Import**
2. Enter Dashboard ID: **14694**
3. Click **Load**
4. Select **Prometheus** as data source
5. Click **Import**

---

## Access URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | None |
| Windows Exporter | http://localhost:9182/metrics | None |

Replace `localhost` with your server IP to access remotely.

---

## Useful Commands

```powershell
# Check all services status
Get-Service windows_exporter, Prometheus, Grafana

# Restart all services
Restart-Service windows_exporter, Prometheus, Grafana

# Stop all services
Stop-Service windows_exporter, Prometheus, Grafana

# Start all services
Start-Service windows_exporter, Prometheus, Grafana

# View Prometheus configuration
notepad C:\monitoring\prometheus\prometheus.yml

# Check if ports are listening
netstat -an | findstr "9090 9182 3000"
```

---

## Troubleshooting

### Service won't start

```powershell
# Check Windows Event Log for errors
Get-EventLog -LogName Application -Source "Prometheus" -Newest 10
Get-EventLog -LogName Application -Source "Grafana" -Newest 10

# Check NSSM service status
C:\monitoring\tools\nssm.exe status Prometheus
```

### Port already in use

```powershell
# Find what's using a port
netstat -ano | findstr :9090
```

### Prometheus can't scrape Windows Exporter

```powershell
# Test Windows Exporter locally
curl http://localhost:9182/metrics

# Check Windows Exporter service
Get-Service windows_exporter
Restart-Service windows_exporter
```

---

## Recommended Dashboards

| Dashboard ID | Name | Description |
|--------------|------|-------------|
| 14694 | Windows Exporter Dashboard | Comprehensive Windows metrics |
| 13978 | Windows Node | Alternative Windows dashboard |
| 12566 | Windows Server Dashboard | Another good option |

---

## File Locations

| Component | Location |
|-----------|----------|
| Prometheus | C:\monitoring\prometheus\ |
| Prometheus Config | C:\monitoring\prometheus\prometheus.yml |
| Prometheus Data | C:\monitoring\prometheus\data\ |
| Grafana | C:\Program Files\GrafanaLabs\grafana\ |
| Grafana Config | C:\Program Files\GrafanaLabs\grafana\conf\defaults.ini |
| NSSM | C:\monitoring\tools\nssm.exe |

---

## Uninstall

```powershell
# Stop services
Stop-Service Prometheus, Grafana, windows_exporter -Force

# Remove Prometheus service
C:\monitoring\tools\nssm.exe remove Prometheus confirm

# Uninstall Grafana
msiexec /x "$env:TEMP\grafana.msi" /qn
# Or via Control Panel → Programs → Uninstall

# Uninstall Windows Exporter
msiexec /x "$env:TEMP\windows_exporter.msi" /qn
# Or via Control Panel → Programs → Uninstall

# Remove monitoring folder
Remove-Item -Recurse -Force "C:\monitoring"
```
