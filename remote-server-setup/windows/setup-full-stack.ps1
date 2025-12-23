# ============================================
#  FULL MONITORING STACK SETUP FOR WINDOWS
#  Prometheus + Grafana + Windows Exporter
#  Run as Administrator!
# ============================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============================================
# Configuration
# ============================================
$InstallDir = "C:\monitoring"
$PrometheusVersion = "2.48.0"
$GrafanaVersion = "10.2.2"
$WindowsExporterVersion = "0.25.1"
$NssmVersion = "2.24"

# ============================================
# Banner
# ============================================
Clear-Host
Write-Host ""
Write-Host "+=============================================================+" -ForegroundColor Blue
Write-Host "|     FULL MONITORING STACK SETUP FOR WINDOWS                 |" -ForegroundColor Blue
Write-Host "|     Prometheus + Grafana + Windows Exporter                 |" -ForegroundColor Blue
Write-Host "+=============================================================+" -ForegroundColor Blue
Write-Host ""

$ServerName = $env:COMPUTERNAME
$ServerIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*" } | Select-Object -First 1).IPAddress

Write-Host "Server: $ServerName ($ServerIP)" -ForegroundColor Green
Write-Host "Install Directory: $InstallDir" -ForegroundColor Green
Write-Host ""

# ============================================
# Create Directories
# ============================================
Write-Host "[1/7] Creating directories..." -ForegroundColor Yellow

$Directories = @(
    "$InstallDir",
    "$InstallDir\prometheus",
    "$InstallDir\prometheus\data",
    "$InstallDir\grafana",
    "$InstallDir\tools"
)

foreach ($Dir in $Directories) {
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
}

Write-Host "[OK] Directories created" -ForegroundColor Green
Write-Host ""

# ============================================
# Download NSSM (Service Manager)
# ============================================
Write-Host "[2/7] Downloading NSSM (Service Manager)..." -ForegroundColor Yellow

$NssmUrl = "https://nssm.cc/release/nssm-$NssmVersion.zip"
$NssmZip = "$env:TEMP\nssm.zip"
$NssmExe = "$InstallDir\tools\nssm.exe"

if (-not (Test-Path $NssmExe)) {
    try {
        Invoke-WebRequest -Uri $NssmUrl -OutFile $NssmZip -UseBasicParsing
        Expand-Archive -Path $NssmZip -DestinationPath "$env:TEMP\nssm" -Force
        Copy-Item "$env:TEMP\nssm\nssm-$NssmVersion\win64\nssm.exe" $NssmExe
        Write-Host "[OK] NSSM downloaded" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Could not download NSSM: $_" -ForegroundColor Yellow
        Write-Host "  You may need to install services manually" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[OK] NSSM already exists" -ForegroundColor Green
}
Write-Host ""

# ============================================
# Install Windows Exporter
# ============================================
Write-Host "[3/7] Installing Windows Exporter..." -ForegroundColor Yellow

$ExistingWE = Get-Service -Name "windows_exporter" -ErrorAction SilentlyContinue
if ($ExistingWE) {
    Write-Host "[OK] Windows Exporter already installed" -ForegroundColor Green
}
else {
    $WeUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v$WindowsExporterVersion/windows_exporter-$WindowsExporterVersion-amd64.msi"
    $WeMsi = "$env:TEMP\windows_exporter.msi"
    
    Invoke-WebRequest -Uri $WeUrl -OutFile $WeMsi -UseBasicParsing
    
    $MsiArgs = @(
        "/i"
        "`"$WeMsi`""
        "ENABLED_COLLECTORS=`"cpu,cs,logical_disk,memory,net,os,process,service,system,tcp,thermalzone`""
        "/qn"
        "/norestart"
    )
    
    $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $MsiArgs -Wait -PassThru
    
    if ($Process.ExitCode -eq 0) {
        Write-Host "[OK] Windows Exporter installed" -ForegroundColor Green
    }
    else {
        Write-Host "[WARN] Windows Exporter installation returned code: $($Process.ExitCode)" -ForegroundColor Yellow
    }
}
Write-Host ""

# ============================================
# Install Prometheus
# ============================================
Write-Host "[4/7] Installing Prometheus..." -ForegroundColor Yellow

$PromDir = "$InstallDir\prometheus"
$PromExe = "$PromDir\prometheus.exe"

$ExistingProm = Get-Service -Name "Prometheus" -ErrorAction SilentlyContinue
if ($ExistingProm) {
    Write-Host "Stopping existing Prometheus service..." -ForegroundColor Cyan
    Stop-Service Prometheus -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

if (-not (Test-Path $PromExe)) {
    $PromUrl = "https://github.com/prometheus/prometheus/releases/download/v$PrometheusVersion/prometheus-$PrometheusVersion.windows-amd64.zip"
    $PromZip = "$env:TEMP\prometheus.zip"
    
    Write-Host "  Downloading Prometheus v$PrometheusVersion..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $PromUrl -OutFile $PromZip -UseBasicParsing
    
    Write-Host "  Extracting..." -ForegroundColor Cyan
    Expand-Archive -Path $PromZip -DestinationPath "$env:TEMP\prom" -Force
    
    # Copy files to install directory
    Copy-Item "$env:TEMP\prom\prometheus-$PrometheusVersion.windows-amd64\*" $PromDir -Recurse -Force
    
    Write-Host "[OK] Prometheus downloaded and extracted" -ForegroundColor Green
}
else {
    Write-Host "[OK] Prometheus already exists" -ForegroundColor Green
}

# Create Prometheus configuration
Write-Host "  Creating prometheus.yml..." -ForegroundColor Cyan

$PrometheusConfig = @"
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
          instance: '$ServerIP'
          node_name: '$ServerName'
          server: '$ServerName'
          environment: 'production'
          os_type: 'windows'
          service: 'os'
"@

$PrometheusConfig | Out-File -FilePath "$PromDir\prometheus.yml" -Encoding UTF8 -Force

# Install Prometheus as Windows Service
if (-not $ExistingProm) {
    if (Test-Path $NssmExe) {
        Write-Host "  Installing Prometheus as Windows service..." -ForegroundColor Cyan
        
        & $NssmExe install Prometheus "$PromExe"
        & $NssmExe set Prometheus AppParameters "--config.file=$PromDir\prometheus.yml --storage.tsdb.path=$PromDir\data --web.enable-lifecycle --storage.tsdb.retention.time=30d"
        & $NssmExe set Prometheus AppDirectory "$PromDir"
        & $NssmExe set Prometheus DisplayName "Prometheus Monitoring"
        & $NssmExe set Prometheus Description "Prometheus time-series database for monitoring"
        & $NssmExe set Prometheus Start SERVICE_AUTO_START
        
        Start-Service Prometheus
        Write-Host "[OK] Prometheus service installed and started" -ForegroundColor Green
    }
    else {
        Write-Host "[WARN] NSSM not available. Please install Prometheus service manually." -ForegroundColor Yellow
    }
}
else {
    Start-Service Prometheus
    Write-Host "[OK] Prometheus service restarted" -ForegroundColor Green
}
Write-Host ""

# ============================================
# Install Grafana
# ============================================
Write-Host "[5/7] Installing Grafana..." -ForegroundColor Yellow

$ExistingGrafana = Get-Service -Name "Grafana" -ErrorAction SilentlyContinue
if ($ExistingGrafana) {
    Write-Host "[OK] Grafana already installed" -ForegroundColor Green
}
else {
    $GrafanaUrl = "https://dl.grafana.com/oss/release/grafana-$GrafanaVersion.windows-amd64.msi"
    $GrafanaMsi = "$env:TEMP\grafana.msi"
    
    Write-Host "  Downloading Grafana v$GrafanaVersion..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $GrafanaUrl -OutFile $GrafanaMsi -UseBasicParsing
    
    Write-Host "  Installing Grafana..." -ForegroundColor Cyan
    $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$GrafanaMsi`" /qn" -Wait -PassThru
    
    if ($Process.ExitCode -eq 0) {
        Start-Sleep -Seconds 3
        Start-Service Grafana -ErrorAction SilentlyContinue
        Write-Host "[OK] Grafana installed and started" -ForegroundColor Green
    }
    else {
        Write-Host "[WARN] Grafana installation returned code: $($Process.ExitCode)" -ForegroundColor Yellow
    }
}
Write-Host ""

# ============================================
# Configure Firewall
# ============================================
Write-Host "[6/7] Configuring firewall..." -ForegroundColor Yellow

$FirewallRules = @(
    @{Name = "Prometheus"; Port = 9090},
    @{Name = "Grafana"; Port = 3000},
    @{Name = "Windows Exporter"; Port = 9182}
)

foreach ($Rule in $FirewallRules) {
    $Existing = Get-NetFirewallRule -DisplayName "$($Rule.Name) (Monitoring)" -ErrorAction SilentlyContinue
    if (-not $Existing) {
        New-NetFirewallRule -DisplayName "$($Rule.Name) (Monitoring)" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $Rule.Port `
            -Action Allow `
            -Profile Any | Out-Null
        Write-Host "  [OK] Firewall rule created for $($Rule.Name) (port $($Rule.Port))" -ForegroundColor Green
    }
    else {
        Write-Host "  [OK] Firewall rule exists for $($Rule.Name)" -ForegroundColor Green
    }
}
Write-Host ""

# ============================================
# Verify Installation
# ============================================
Write-Host "[7/7] Verifying installation..." -ForegroundColor Yellow

Start-Sleep -Seconds 5

$Services = @(
    @{Name = "windows_exporter"; Port = 9182; Display = "Windows Exporter"},
    @{Name = "Prometheus"; Port = 9090; Display = "Prometheus"},
    @{Name = "Grafana"; Port = 3000; Display = "Grafana"}
)

$AllGood = $true

foreach ($Svc in $Services) {
    $Service = Get-Service -Name $Svc.Name -ErrorAction SilentlyContinue
    if ($Service -and $Service.Status -eq "Running") {
        Write-Host "  [OK] $($Svc.Display) is running" -ForegroundColor Green
        
        # Test port
        try {
            $Response = Invoke-WebRequest -Uri "http://localhost:$($Svc.Port)/" -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
            Write-Host "    -> Port $($Svc.Port) responding" -ForegroundColor Green
        }
        catch {
            Write-Host "    -> Port $($Svc.Port) not responding yet (may take a moment)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  [FAIL] $($Svc.Display) is not running" -ForegroundColor Red
        $AllGood = $false
    }
}
Write-Host ""

# ============================================
# Done!
# ============================================
if ($AllGood) {
    Write-Host "+=============================================================+" -ForegroundColor Green
    Write-Host "|              INSTALLATION COMPLETE!                         |" -ForegroundColor Green
    Write-Host "+=============================================================+" -ForegroundColor Green
}
else {
    Write-Host "+=============================================================+" -ForegroundColor Yellow
    Write-Host "|         INSTALLATION COMPLETE (with warnings)               |" -ForegroundColor Yellow
    Write-Host "+=============================================================+" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "-------------------------------------------------------------" -ForegroundColor Blue
Write-Host "                     ACCESS URLS                             " -ForegroundColor Yellow
Write-Host "-------------------------------------------------------------" -ForegroundColor Blue
Write-Host ""
Write-Host "  Grafana:          http://${ServerIP}:3000" -ForegroundColor Cyan
Write-Host "                    Username: admin" -ForegroundColor Gray
Write-Host "                    Password: admin" -ForegroundColor Gray
Write-Host ""
Write-Host "  Prometheus:       http://${ServerIP}:9090" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Windows Exporter: http://${ServerIP}:9182/metrics" -ForegroundColor Cyan
Write-Host ""
Write-Host "-------------------------------------------------------------" -ForegroundColor Blue
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Open Grafana: http://${ServerIP}:3000" -ForegroundColor White
Write-Host "2. Login with admin / admin" -ForegroundColor White
Write-Host "3. Go to: Connections -> Data Sources -> Add data source" -ForegroundColor White
Write-Host "4. Select 'Prometheus' and set URL to: http://localhost:9090" -ForegroundColor White
Write-Host "5. Click 'Save & Test'" -ForegroundColor White
Write-Host "6. Go to: Dashboards -> Import -> Enter ID: 14694 -> Load -> Import" -ForegroundColor White
Write-Host ""
Write-Host "-------------------------------------------------------------" -ForegroundColor Blue
Write-Host ""
Write-Host "Installation directory: $InstallDir" -ForegroundColor Gray
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Cyan
Write-Host "  Check services:   Get-Service Prometheus, Grafana, windows_exporter"
Write-Host "  Restart all:      Restart-Service Prometheus, Grafana, windows_exporter"
Write-Host ('  View Prom config: notepad ' + $PromDir + '\prometheus.yml')
Write-Host ""
