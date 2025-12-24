# ============================================
#  MySQL Exporter Setup for Windows
#  Run as Administrator!
# ============================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============================================
# Configuration
# ============================================
$InstallDir = "C:\monitoring"
$MySQLExporterVersion = "0.15.1"
$MySQLExporterPort = 9104

# ============================================
# Banner
# ============================================
Clear-Host
Write-Host ""
Write-Host "+=============================================================+" -ForegroundColor Blue
Write-Host "|           MySQL EXPORTER SETUP FOR WINDOWS                  |" -ForegroundColor Blue
Write-Host "+=============================================================+" -ForegroundColor Blue
Write-Host ""

# ============================================
# Check Prerequisites
# ============================================
Write-Host "[1/5] Checking prerequisites..." -ForegroundColor Yellow

# Check if monitoring folder exists
if (-not (Test-Path "$InstallDir\tools\nssm.exe")) {
    Write-Host "[ERROR] Please run setup-full-stack.ps1 first!" -ForegroundColor Red
    Write-Host "  NSSM is required to install MySQL Exporter as a service" -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] NSSM found" -ForegroundColor Green

# Check if MySQL Exporter already installed
$ExistingME = Get-Service -Name "mysqld_exporter" -ErrorAction SilentlyContinue
if ($ExistingME) {
    Write-Host "  [INFO] MySQL Exporter service already exists" -ForegroundColor Cyan
    $Reinstall = Read-Host "  Do you want to reconfigure it? (y/n)"
    if ($Reinstall -ne "y" -and $Reinstall -ne "Y") {
        Write-Host "  Exiting." -ForegroundColor Yellow
        exit 0
    }
    Stop-Service mysqld_exporter -Force -ErrorAction SilentlyContinue
    & "$InstallDir\tools\nssm.exe" remove mysqld_exporter confirm 2>$null
}
Write-Host ""

# ============================================
# Get MySQL Credentials
# ============================================
Write-Host "[2/5] MySQL Configuration..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  You need a MySQL user with monitoring permissions." -ForegroundColor Cyan
Write-Host "  If you don't have one, ask your DBA to run:" -ForegroundColor Cyan
Write-Host ""
Write-Host "    CREATE USER 'exporter'@'localhost' IDENTIFIED BY 'your_password';" -ForegroundColor White
Write-Host "    GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';" -ForegroundColor White
Write-Host "    FLUSH PRIVILEGES;" -ForegroundColor White
Write-Host ""

$MySQLHost = Read-Host "  MySQL Host (default: localhost)"
if ([string]::IsNullOrWhiteSpace($MySQLHost)) { $MySQLHost = "localhost" }

$MySQLPort = Read-Host "  MySQL Port (default: 3306)"
if ([string]::IsNullOrWhiteSpace($MySQLPort)) { $MySQLPort = "3306" }

$MySQLUser = Read-Host "  MySQL Username"
if ([string]::IsNullOrWhiteSpace($MySQLUser)) {
    Write-Host "  [ERROR] Username is required!" -ForegroundColor Red
    exit 1
}

$MySQLPass = Read-Host "  MySQL Password" -AsSecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($MySQLPass)
$MySQLPassPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

if ([string]::IsNullOrWhiteSpace($MySQLPassPlain)) {
    Write-Host "  [ERROR] Password is required!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  [OK] Credentials captured" -ForegroundColor Green
Write-Host ""

# ============================================
# Download MySQL Exporter
# ============================================
Write-Host "[3/5] Downloading MySQL Exporter..." -ForegroundColor Yellow

$MEDir = "$InstallDir\mysql-exporter"
$MEExe = "$MEDir\mysqld_exporter.exe"

New-Item -ItemType Directory -Force -Path $MEDir | Out-Null

if (-not (Test-Path $MEExe)) {
    $MEUrl = "https://github.com/prometheus/mysqld_exporter/releases/download/v$MySQLExporterVersion/mysqld_exporter-$MySQLExporterVersion.windows-amd64.zip"
    $MEZip = "$env:TEMP\mysqld_exporter.zip"
    
    Write-Host "  Downloading MySQL Exporter v$MySQLExporterVersion..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $MEUrl -OutFile $MEZip -UseBasicParsing
        Write-Host "  [OK] Downloaded" -ForegroundColor Green
    }
    catch {
        Write-Host "  [ERROR] Download failed: $_" -ForegroundColor Red
        Write-Host "  Try downloading manually from: $MEUrl" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "  Extracting..." -ForegroundColor Cyan
    try {
        Expand-Archive -Path $MEZip -DestinationPath "$env:TEMP\mysql_exporter_extract" -Force
        Copy-Item "$env:TEMP\mysql_exporter_extract\mysqld_exporter-$MySQLExporterVersion.windows-amd64\mysqld_exporter.exe" $MEExe -Force
        Write-Host "  [OK] Extracted to $MEDir" -ForegroundColor Green
    }
    catch {
        Write-Host "  [ERROR] Extraction failed: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "  [OK] MySQL Exporter already exists" -ForegroundColor Green
}
Write-Host ""

# ============================================
# Create MySQL Config File
# ============================================
Write-Host "[4/5] Creating configuration..." -ForegroundColor Yellow

$MyCnfPath = "$MEDir\.my.cnf"

$MyCnfContent = @"
[client]
host=$MySQLHost
port=$MySQLPort
user=$MySQLUser
password=$MySQLPassPlain
"@

$MyCnfContent | Out-File -FilePath $MyCnfPath -Encoding ASCII -Force
Write-Host "  [OK] MySQL config created at $MyCnfPath" -ForegroundColor Green

# ============================================
# Install as Windows Service
# ============================================
Write-Host "  Installing MySQL Exporter as Windows service..." -ForegroundColor Cyan

$NssmExe = "$InstallDir\tools\nssm.exe"

try {
    & $NssmExe install mysqld_exporter "$MEExe"
    & $NssmExe set mysqld_exporter AppParameters "--config.my-cnf=$MyCnfPath --web.listen-address=:$MySQLExporterPort"
    & $NssmExe set mysqld_exporter AppDirectory "$MEDir"
    & $NssmExe set mysqld_exporter DisplayName "MySQL Exporter (Prometheus)"
    & $NssmExe set mysqld_exporter Description "Exports MySQL metrics for Prometheus"
    & $NssmExe set mysqld_exporter Start SERVICE_AUTO_START
    
    Start-Service mysqld_exporter
    Write-Host "  [OK] MySQL Exporter service installed and started" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Failed to install service: $_" -ForegroundColor Red
    exit 1
}

# Open firewall port
try {
    $Existing = Get-NetFirewallRule -DisplayName "MySQL Exporter (Monitoring)" -ErrorAction SilentlyContinue
    if (-not $Existing) {
        New-NetFirewallRule -DisplayName "MySQL Exporter (Monitoring)" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $MySQLExporterPort `
            -Action Allow `
            -Profile Any | Out-Null
        Write-Host "  [OK] Firewall rule created for port $MySQLExporterPort" -ForegroundColor Green
    }
}
catch {
    Write-Host "  [WARN] Could not create firewall rule" -ForegroundColor Yellow
}
Write-Host ""

# ============================================
# Update Prometheus Config
# ============================================
Write-Host "[5/5] Updating Prometheus configuration..." -ForegroundColor Yellow

$PromConfig = "$InstallDir\prometheus\prometheus.yml"
$ServerName = $env:COMPUTERNAME

# Check if MySQL exporter job already exists
$ConfigContent = Get-Content $PromConfig -Raw
if ($ConfigContent -match "mysql-exporter") {
    Write-Host "  [INFO] MySQL exporter job already exists in prometheus.yml" -ForegroundColor Cyan
}
else {
    # Add MySQL exporter job
    $MySQLJob = @"

  # MySQL Exporter - Database metrics
  - job_name: 'mysql-exporter'
    static_configs:
      - targets: ['localhost:$MySQLExporterPort']
        labels:
          instance: '$ServerName'
          server: '$ServerName'
          environment: 'production'
          service: 'mysql'
"@
    
    Add-Content -Path $PromConfig -Value $MySQLJob
    Write-Host "  [OK] Added MySQL exporter to prometheus.yml" -ForegroundColor Green
}

# Restart Prometheus to pick up new config
Write-Host "  Restarting Prometheus..." -ForegroundColor Cyan
try {
    Restart-Service Prometheus -ErrorAction Stop
    Write-Host "  [OK] Prometheus restarted" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Could not restart Prometheus: $_" -ForegroundColor Yellow
    Write-Host "  Please restart manually: Restart-Service Prometheus" -ForegroundColor Yellow
}
Write-Host ""

# ============================================
# Verify Installation
# ============================================
Write-Host "Verifying MySQL Exporter..." -ForegroundColor Yellow

Start-Sleep -Seconds 3

try {
    $response = Invoke-WebRequest -Uri "http://localhost:$MySQLExporterPort/metrics" -UseBasicParsing -TimeoutSec 5
    
    # Check if mysql_up metric is 1
    if ($response.Content -match "mysql_up\s+1") {
        Write-Host "  [OK] MySQL Exporter is running and connected to MySQL!" -ForegroundColor Green
    }
    elseif ($response.Content -match "mysql_up\s+0") {
        Write-Host "  [WARN] MySQL Exporter is running but CANNOT connect to MySQL" -ForegroundColor Yellow
        Write-Host "         Check your MySQL credentials and permissions" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [OK] MySQL Exporter is responding" -ForegroundColor Green
    }
}
catch {
    Write-Host "  [FAIL] MySQL Exporter not responding on port $MySQLExporterPort" -ForegroundColor Red
    Write-Host "         Check: Get-Service mysqld_exporter" -ForegroundColor Gray
}

# ============================================
# Done!
# ============================================
Write-Host ""
Write-Host "+=============================================================+" -ForegroundColor Green
Write-Host "|           MySQL EXPORTER SETUP COMPLETE!                    |" -ForegroundColor Green
Write-Host "+=============================================================+" -ForegroundColor Green
Write-Host ""
Write-Host "  MySQL Exporter: http://localhost:$MySQLExporterPort/metrics" -ForegroundColor Cyan
Write-Host ""
Write-Host "-------------------------------------------------------------" -ForegroundColor Blue
Write-Host ""
Write-Host "NEXT STEPS - Import MySQL Dashboard in Grafana:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Open Grafana: http://localhost:3000" -ForegroundColor White
Write-Host "2. Go to: Dashboards -> Import" -ForegroundColor White
Write-Host "3. Enter Dashboard ID: 7362 (MySQL Overview)" -ForegroundColor White
Write-Host "4. Click Load -> Select Prometheus -> Import" -ForegroundColor White
Write-Host ""
Write-Host "Other MySQL Dashboards:" -ForegroundColor Cyan
Write-Host "  - 7362  : MySQL Overview (recommended)" -ForegroundColor Gray
Write-Host "  - 14057 : MySQL Dashboard" -ForegroundColor Gray
Write-Host "  - 6239  : MySQL Performance Schema" -ForegroundColor Gray
Write-Host ""
Write-Host "-------------------------------------------------------------" -ForegroundColor Blue
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Cyan
Write-Host "  Check service:  Get-Service mysqld_exporter"
Write-Host "  Restart:        Restart-Service mysqld_exporter"
Write-Host "  View config:    notepad $MyCnfPath"
Write-Host ""

