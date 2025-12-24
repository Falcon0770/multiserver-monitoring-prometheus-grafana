# ============================================
#  MSSQL (SQL Server) Exporter Setup for Windows
#  Run as Administrator!
# ============================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============================================
# Configuration
# ============================================
$InstallDir = "C:\monitoring"
$MSSQLExporterVersion = "0.14.3"
$MSSQLExporterPort = 9399

# ============================================
# Banner
# ============================================
Clear-Host
Write-Host ""
Write-Host "+=============================================================+" -ForegroundColor Blue
Write-Host "|         MSSQL (SQL Server) EXPORTER SETUP FOR WINDOWS       |" -ForegroundColor Blue
Write-Host "+=============================================================+" -ForegroundColor Blue
Write-Host ""

# ============================================
# Check Prerequisites
# ============================================
Write-Host "[1/5] Checking prerequisites..." -ForegroundColor Yellow

# Check if monitoring folder exists
if (-not (Test-Path "$InstallDir\tools\nssm.exe")) {
    Write-Host "[ERROR] Please run setup-full-stack.ps1 first!" -ForegroundColor Red
    Write-Host "  NSSM is required to install MSSQL Exporter as a service" -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] NSSM found" -ForegroundColor Green

# Check if MSSQL Exporter already installed
$ExistingME = Get-Service -Name "mssql_exporter" -ErrorAction SilentlyContinue
if ($ExistingME) {
    Write-Host "  [INFO] MSSQL Exporter service already exists" -ForegroundColor Cyan
    $Reinstall = Read-Host "  Do you want to reconfigure it? (y/n)"
    if ($Reinstall -ne "y" -and $Reinstall -ne "Y") {
        Write-Host "  Exiting." -ForegroundColor Yellow
        exit 0
    }
    Stop-Service mssql_exporter -Force -ErrorAction SilentlyContinue
    & "$InstallDir\tools\nssm.exe" remove mssql_exporter confirm 2>$null
}
Write-Host ""

# ============================================
# Get SQL Server Connection Details
# ============================================
Write-Host "[2/5] SQL Server Configuration..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Choose authentication method:" -ForegroundColor Cyan
Write-Host "    1. Windows Authentication (recommended if running on SQL Server)" -ForegroundColor White
Write-Host "    2. SQL Server Authentication (username/password)" -ForegroundColor White
Write-Host ""

$AuthChoice = Read-Host "  Enter choice (1 or 2)"

$SQLServer = Read-Host "  SQL Server instance (default: localhost)"
if ([string]::IsNullOrWhiteSpace($SQLServer)) { $SQLServer = "localhost" }

if ($AuthChoice -eq "2") {
    # SQL Server Authentication
    $SQLUser = Read-Host "  SQL Server Username"
    if ([string]::IsNullOrWhiteSpace($SQLUser)) {
        Write-Host "  [ERROR] Username is required!" -ForegroundColor Red
        exit 1
    }
    
    $SQLPass = Read-Host "  SQL Server Password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SQLPass)
    $SQLPassPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    
    if ([string]::IsNullOrWhiteSpace($SQLPassPlain)) {
        Write-Host "  [ERROR] Password is required!" -ForegroundColor Red
        exit 1
    }
    
    # Build connection string for SQL Auth
    $ConnectionString = "Server=$SQLServer;User Id=$SQLUser;Password=$SQLPassPlain;"
    Write-Host "  [OK] Using SQL Server Authentication" -ForegroundColor Green
}
else {
    # Windows Authentication
    $ConnectionString = "Server=$SQLServer;Integrated Security=True;"
    Write-Host "  [OK] Using Windows Authentication" -ForegroundColor Green
}

Write-Host ""

# ============================================
# Download SQL Server Exporter
# ============================================
Write-Host "[3/5] Downloading SQL Server Exporter..." -ForegroundColor Yellow

$MEDir = "$InstallDir\mssql-exporter"
$MEExe = "$MEDir\sql_exporter.exe"

New-Item -ItemType Directory -Force -Path $MEDir | Out-Null

if (-not (Test-Path $MEExe)) {
    # Using sql_exporter which supports MSSQL
    $MEUrl = "https://github.com/burningalchemist/sql_exporter/releases/download/$MSSQLExporterVersion/sql_exporter-$MSSQLExporterVersion.windows-amd64.zip"
    $MEZip = "$env:TEMP\sql_exporter.zip"
    
    Write-Host "  Downloading SQL Exporter v$MSSQLExporterVersion..." -ForegroundColor Cyan
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
        $ExtractPath = "$env:TEMP\sql_exporter_extract"
        if (Test-Path $ExtractPath) { Remove-Item $ExtractPath -Recurse -Force }
        Expand-Archive -Path $MEZip -DestinationPath $ExtractPath -Force
        
        # Find and copy the exe
        $ExeFile = Get-ChildItem -Path $ExtractPath -Recurse -Filter "sql_exporter.exe" | Select-Object -First 1
        if ($ExeFile) {
            Copy-Item $ExeFile.FullName $MEExe -Force
            Write-Host "  [OK] Extracted to $MEDir" -ForegroundColor Green
        }
        else {
            # Try alternative structure
            Copy-Item "$ExtractPath\sql_exporter-$MSSQLExporterVersion.windows-amd64\sql_exporter.exe" $MEExe -Force
            Write-Host "  [OK] Extracted to $MEDir" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  [ERROR] Extraction failed: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "  [OK] SQL Exporter already exists" -ForegroundColor Green
}
Write-Host ""

# ============================================
# Create Configuration Files
# ============================================
Write-Host "[4/5] Creating configuration..." -ForegroundColor Yellow

# Create sql_exporter.yml configuration
$ConfigPath = "$MEDir\sql_exporter.yml"

$ConfigContent = @"
global:
  scrape_timeout: 10s
  min_interval: 10s

target:
  data_source_name: "$ConnectionString"
  collectors:
    - mssql_standard

collectors:
  - collector_name: mssql_standard
    metrics:
      - metric_name: mssql_up
        type: gauge
        help: "SQL Server is up"
        values: [status]
        query: |
          SELECT 1 AS status

      - metric_name: mssql_connections
        type: gauge
        help: "Number of active connections"
        values: [count]
        query: |
          SELECT COUNT(*) AS count FROM sys.dm_exec_connections

      - metric_name: mssql_deadlocks_total
        type: counter
        help: "Total number of deadlocks"
        values: [count]
        query: |
          SELECT cntr_value AS count
          FROM sys.dm_os_performance_counters
          WHERE counter_name = 'Number of Deadlocks/sec' AND instance_name = '_Total'

      - metric_name: mssql_user_connections
        type: gauge
        help: "Number of user connections"
        values: [count]
        query: |
          SELECT cntr_value AS count
          FROM sys.dm_os_performance_counters
          WHERE counter_name = 'User Connections'

      - metric_name: mssql_batch_requests_total
        type: counter
        help: "Total batch requests"
        values: [count]
        query: |
          SELECT cntr_value AS count
          FROM sys.dm_os_performance_counters
          WHERE counter_name = 'Batch Requests/sec'

      - metric_name: mssql_page_life_expectancy_seconds
        type: gauge
        help: "Page life expectancy in seconds"
        values: [seconds]
        query: |
          SELECT cntr_value AS seconds
          FROM sys.dm_os_performance_counters
          WHERE counter_name = 'Page life expectancy' AND object_name LIKE '%Buffer Manager%'

      - metric_name: mssql_buffer_cache_hit_ratio
        type: gauge
        help: "Buffer cache hit ratio"
        values: [ratio]
        query: |
          SELECT CAST(a.cntr_value AS FLOAT) / CAST(b.cntr_value AS FLOAT) * 100 AS ratio
          FROM sys.dm_os_performance_counters a
          JOIN sys.dm_os_performance_counters b ON a.object_name = b.object_name
          WHERE a.counter_name = 'Buffer cache hit ratio'
            AND b.counter_name = 'Buffer cache hit ratio base'
            AND a.object_name LIKE '%Buffer Manager%'

      - metric_name: mssql_total_server_memory_bytes
        type: gauge
        help: "Total server memory in bytes"
        values: [bytes]
        query: |
          SELECT cntr_value * 1024 AS bytes
          FROM sys.dm_os_performance_counters
          WHERE counter_name = 'Total Server Memory (KB)'

      - metric_name: mssql_target_server_memory_bytes
        type: gauge
        help: "Target server memory in bytes"
        values: [bytes]
        query: |
          SELECT cntr_value * 1024 AS bytes
          FROM sys.dm_os_performance_counters
          WHERE counter_name = 'Target Server Memory (KB)'

      - metric_name: mssql_database_size_bytes
        type: gauge
        help: "Database size in bytes"
        key_labels: [database]
        values: [size_bytes]
        query: |
          SELECT DB_NAME(database_id) AS database, SUM(size) * 8 * 1024 AS size_bytes
          FROM sys.master_files
          GROUP BY database_id

      - metric_name: mssql_database_state
        type: gauge
        help: "Database state (0=ONLINE, 1=RESTORING, 2=RECOVERING, etc)"
        key_labels: [database]
        values: [state]
        query: |
          SELECT name AS database, state AS state FROM sys.databases

      - metric_name: mssql_sql_compilations_total
        type: counter
        help: "SQL compilations per second"
        values: [count]
        query: |
          SELECT cntr_value AS count
          FROM sys.dm_os_performance_counters
          WHERE counter_name = 'SQL Compilations/sec'

      - metric_name: mssql_sql_recompilations_total
        type: counter
        help: "SQL re-compilations per second"
        values: [count]
        query: |
          SELECT cntr_value AS count
          FROM sys.dm_os_performance_counters
          WHERE counter_name = 'SQL Re-Compilations/sec'

      - metric_name: mssql_transactions_total
        type: counter
        help: "Total transactions"
        values: [count]
        query: |
          SELECT cntr_value AS count
          FROM sys.dm_os_performance_counters
          WHERE counter_name = 'Transactions/sec' AND instance_name = '_Total'

      - metric_name: mssql_lock_waits_total
        type: counter
        help: "Lock waits per second"
        values: [count]
        query: |
          SELECT cntr_value AS count
          FROM sys.dm_os_performance_counters
          WHERE counter_name = 'Lock Waits/sec' AND instance_name = '_Total'

      - metric_name: mssql_cpu_percent
        type: gauge
        help: "SQL Server CPU utilization percentage"
        values: [percent]
        query: |
          SELECT TOP 1 
            SQLProcessUtilization AS percent
          FROM (
            SELECT 
              record.value('(./Record/@id)[1]', 'int') AS record_id,
              record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization
            FROM (
              SELECT CONVERT(XML, record) AS record 
              FROM sys.dm_os_ring_buffers 
              WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
                AND record LIKE '%<SystemHealth>%'
            ) AS x
          ) AS y
          ORDER BY record_id DESC
"@

$ConfigContent | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force
Write-Host "  [OK] Configuration created at $ConfigPath" -ForegroundColor Green

# ============================================
# Install as Windows Service
# ============================================
Write-Host "  Installing MSSQL Exporter as Windows service..." -ForegroundColor Cyan

$NssmExe = "$InstallDir\tools\nssm.exe"

try {
    & $NssmExe install mssql_exporter "$MEExe"
    & $NssmExe set mssql_exporter AppParameters "-config.file=$ConfigPath -web.listen-address=:$MSSQLExporterPort"
    & $NssmExe set mssql_exporter AppDirectory "$MEDir"
    & $NssmExe set mssql_exporter DisplayName "MSSQL Exporter (Prometheus)"
    & $NssmExe set mssql_exporter Description "Exports SQL Server metrics for Prometheus"
    & $NssmExe set mssql_exporter Start SERVICE_AUTO_START
    
    Start-Service mssql_exporter
    Write-Host "  [OK] MSSQL Exporter service installed and started" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Failed to install service: $_" -ForegroundColor Red
    exit 1
}

# Open firewall port
try {
    $Existing = Get-NetFirewallRule -DisplayName "MSSQL Exporter (Monitoring)" -ErrorAction SilentlyContinue
    if (-not $Existing) {
        New-NetFirewallRule -DisplayName "MSSQL Exporter (Monitoring)" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $MSSQLExporterPort `
            -Action Allow `
            -Profile Any | Out-Null
        Write-Host "  [OK] Firewall rule created for port $MSSQLExporterPort" -ForegroundColor Green
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

# Check if MSSQL exporter job already exists
$ConfigContent = Get-Content $PromConfig -Raw
if ($ConfigContent -match "mssql-exporter") {
    Write-Host "  [INFO] MSSQL exporter job already exists in prometheus.yml" -ForegroundColor Cyan
}
else {
    # Add MSSQL exporter job
    $MSSQLJob = @"

  # MSSQL (SQL Server) Exporter - Database metrics
  - job_name: 'mssql-exporter'
    static_configs:
      - targets: ['localhost:$MSSQLExporterPort']
        labels:
          instance: '$ServerName'
          server: '$ServerName'
          environment: 'production'
          service: 'mssql'
"@
    
    Add-Content -Path $PromConfig -Value $MSSQLJob
    Write-Host "  [OK] Added MSSQL exporter to prometheus.yml" -ForegroundColor Green
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
Write-Host "Verifying MSSQL Exporter..." -ForegroundColor Yellow

Start-Sleep -Seconds 5

try {
    $response = Invoke-WebRequest -Uri "http://localhost:$MSSQLExporterPort/metrics" -UseBasicParsing -TimeoutSec 10
    
    if ($response.StatusCode -eq 200) {
        if ($response.Content -match "mssql_up\s+1") {
            Write-Host "  [OK] MSSQL Exporter is running and connected to SQL Server!" -ForegroundColor Green
        }
        elseif ($response.Content -match "mssql_") {
            Write-Host "  [OK] MSSQL Exporter is responding with metrics" -ForegroundColor Green
        }
        else {
            Write-Host "  [WARN] MSSQL Exporter running but may not be collecting metrics" -ForegroundColor Yellow
            Write-Host "         Check SQL Server connection and permissions" -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "  [FAIL] MSSQL Exporter not responding on port $MSSQLExporterPort" -ForegroundColor Red
    Write-Host "         Check: Get-Service mssql_exporter" -ForegroundColor Gray
    Write-Host "         Logs:  Check Event Viewer -> Application logs" -ForegroundColor Gray
}

# ============================================
# Done!
# ============================================
Write-Host ""
Write-Host "+=============================================================+" -ForegroundColor Green
Write-Host "|         MSSQL EXPORTER SETUP COMPLETE!                      |" -ForegroundColor Green
Write-Host "+=============================================================+" -ForegroundColor Green
Write-Host ""
Write-Host "  MSSQL Exporter: http://localhost:$MSSQLExporterPort/metrics" -ForegroundColor Cyan
Write-Host ""
Write-Host "-------------------------------------------------------------" -ForegroundColor Blue
Write-Host ""
Write-Host "NEXT STEPS - Import SQL Server Dashboard in Grafana:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Open Grafana: http://localhost:3000" -ForegroundColor White
Write-Host "2. Go to: Dashboards -> Import" -ForegroundColor White
Write-Host "3. Enter Dashboard ID: 17302 (MSSQL Server Dashboard)" -ForegroundColor White
Write-Host "   OR create a custom dashboard with the metrics" -ForegroundColor White
Write-Host "4. Click Load -> Select Prometheus -> Import" -ForegroundColor White
Write-Host ""
Write-Host "Available Metrics:" -ForegroundColor Cyan
Write-Host "  - mssql_up                        : SQL Server is up (1/0)" -ForegroundColor Gray
Write-Host "  - mssql_connections               : Active connections" -ForegroundColor Gray
Write-Host "  - mssql_user_connections          : User connections" -ForegroundColor Gray
Write-Host "  - mssql_deadlocks_total           : Deadlock count" -ForegroundColor Gray
Write-Host "  - mssql_batch_requests_total      : Batch requests" -ForegroundColor Gray
Write-Host "  - mssql_page_life_expectancy      : Page life expectancy" -ForegroundColor Gray
Write-Host "  - mssql_buffer_cache_hit_ratio    : Buffer cache hit ratio" -ForegroundColor Gray
Write-Host "  - mssql_database_size_bytes       : Database sizes" -ForegroundColor Gray
Write-Host "  - mssql_transactions_total        : Transaction count" -ForegroundColor Gray
Write-Host "  - mssql_cpu_percent               : SQL Server CPU usage" -ForegroundColor Gray
Write-Host ""
Write-Host "-------------------------------------------------------------" -ForegroundColor Blue
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Cyan
Write-Host "  Check service:  Get-Service mssql_exporter"
Write-Host "  Restart:        Restart-Service mssql_exporter"
Write-Host "  View config:    notepad $ConfigPath"
Write-Host "  Test metrics:   curl http://localhost:$MSSQLExporterPort/metrics"
Write-Host ""

