# 📖 How to Add New Servers to Monitoring

This guide explains how to add new Linux and Windows servers to your Prometheus + Grafana monitoring stack.

---

## 🐧 Adding a Linux Server

### Step 1: Install Node Exporter on the New Server

SSH into the new Linux server and run these commands:

```bash
# Download Node Exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz

# Extract
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz

# Move to /usr/local/bin
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/

# Clean up
rm -rf node_exporter-1.7.0.linux-amd64*

# Create systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=nobody
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Start and enable the service
sudo systemctl daemon-reload
sudo systemctl start node_exporter
sudo systemctl enable node_exporter

# Verify it's running
sudo systemctl status node_exporter

# Test metrics endpoint
curl http://localhost:9100/metrics | head -20
```

### Step 2: Open Firewall Port 9100

```bash
# For Ubuntu/Debian (UFW)
sudo ufw allow 9100/tcp

# For RHEL/CentOS/Rocky (firewalld)
sudo firewall-cmd --add-port=9100/tcp --permanent
sudo firewall-cmd --reload

# For Azure/AWS - Also open port 9100 in your cloud security group/NSG
```

### Step 3: Add Server to Prometheus Config

On your **monitoring server**, edit `prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'node-exporter'
    static_configs:
      # Existing server
      - targets: ['node-exporter:9100']
        labels:
          instance: 'monitoring-server'
          environment: 'production'
      
      # NEW SERVER - Add this block
      - targets: ['192.168.1.101:9100']  # Replace with actual IP
        labels:
          instance: 'web-server-01'       # Friendly name for dashboard
          environment: 'production'        # Environment label
```

### Step 4: Reload Prometheus

```bash
# Option 1: Hot reload (no downtime)
curl -X POST http://localhost:9090/-/reload

# Option 2: Restart container
cd /home/azureadmin/multiserver-monitoring-prometheus-grafana
sudo docker compose restart prometheus
```

### Step 5: Verify in Prometheus

1. Open `http://<monitoring-server-ip>:9090`
2. Go to **Status → Targets**
3. New server should show as **UP**

---

## 🪟 Adding a Windows Server

### Step 1: Download Windows Exporter

Download from: https://github.com/prometheus-community/windows_exporter/releases

Choose the `.msi` installer (e.g., `windows_exporter-0.25.1-amd64.msi`)

### Step 2: Install on Windows Server

```powershell
# Run as Administrator
msiexec /i windows_exporter-0.25.1-amd64.msi ENABLED_COLLECTORS="cpu,cs,logical_disk,memory,net,os,service,system"
```

Or double-click the MSI and follow the wizard.

### Step 3: Open Firewall Port 9182

```powershell
# PowerShell (Run as Administrator)
New-NetFirewallRule -DisplayName "Windows Exporter" -Direction Inbound -Port 9182 -Protocol TCP -Action Allow
```

Or via Windows Firewall GUI:
1. Open **Windows Defender Firewall**
2. Click **Advanced Settings**
3. **Inbound Rules → New Rule**
4. Port → TCP → 9182 → Allow

### Step 4: Verify Windows Exporter

Open in browser: `http://localhost:9182/metrics`

### Step 5: Add to Prometheus Config

On your **monitoring server**, edit `prometheus/prometheus.yml`:

```yaml
scrape_configs:
  # ... existing Linux targets ...

  # Windows Servers
  - job_name: 'windows-exporter'
    static_configs:
      - targets: ['192.168.1.201:9182']  # Replace with actual IP
        labels:
          instance: 'windows-server-01'
          environment: 'production'
          os: 'windows'
```

### Step 6: Import Windows Dashboard in Grafana

1. Open Grafana: `http://<monitoring-server-ip>:3000`
2. Go to **Dashboards → Import**
3. Enter Dashboard ID: **14694** (Windows Exporter Dashboard)
4. Select **Prometheus** as data source
5. Click **Import**

---

## 📊 How Dashboards Work with Multiple Servers

### Single Dashboard, Multiple Servers

The Grafana dashboards use a **dropdown selector** to switch between servers:

```
┌─────────────────────────────────────────────────────────────────┐
│  📈 Dashboard                                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Host: [▼ monitoring-server    ]   ← Select server here        │
│        [  web-server-01        ]                                │
│        [  db-server-01         ]                                │
│        [  windows-server-01    ]                                │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [CPU Graph]    [Memory Graph]    [Disk Graph]                  │
│                                                                 │
│  Shows metrics for the SELECTED server                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Recommended Dashboards

| Dashboard ID | Name | Best For |
|--------------|------|----------|
| **1860** | Node Exporter Full | Detailed Linux server metrics |
| **11074** | Node Exporter Dashboard | Overview of all Linux servers |
| **14694** | Windows Exporter Dashboard | Windows server metrics |
| **13978** | Windows Node | Alternative Windows dashboard |

### Import a Dashboard

1. Open Grafana (`http://<ip>:3000`)
2. Click **Dashboards** → **Import**
3. Enter the Dashboard ID
4. Click **Load**
5. Select **Prometheus** as data source
6. Click **Import**

---

## 📋 Quick Reference: Prometheus Config Template

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: 'prometheus-server'

  # Linux Servers (Node Exporter - Port 9100)
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          instance: 'monitoring-server'
          environment: 'production'
      
      - targets: ['192.168.1.101:9100']
        labels:
          instance: 'linux-server-01'
          environment: 'production'
      
      - targets: ['192.168.1.102:9100']
        labels:
          instance: 'linux-server-02'
          environment: 'staging'

  # Windows Servers (Windows Exporter - Port 9182)
  - job_name: 'windows-exporter'
    static_configs:
      - targets: ['192.168.1.201:9182']
        labels:
          instance: 'windows-server-01'
          environment: 'production'
          os: 'windows'
      
      - targets: ['192.168.1.202:9182']
        labels:
          instance: 'windows-server-02'
          environment: 'production'
          os: 'windows'
```

---

## 🔧 Useful Commands

```bash
# Check container status
sudo docker compose ps

# View Prometheus logs
sudo docker compose logs prometheus

# View Grafana logs
sudo docker compose logs grafana

# Restart all services
sudo docker compose restart

# Reload Prometheus config (no restart)
curl -X POST http://localhost:9090/-/reload

# Check Prometheus targets via API
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool

# Test if a server's exporter is reachable
curl http://<server-ip>:9100/metrics | head -10   # Linux
curl http://<server-ip>:9182/metrics | head -10   # Windows
```

---

## 🌐 Access URLs

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| Prometheus | `http://<monitoring-ip>:9090` | None |
| Grafana | `http://<monitoring-ip>:3000` | admin / admin |
| Node Exporter | `http://<server-ip>:9100/metrics` | None |
| Windows Exporter | `http://<server-ip>:9182/metrics` | None |

---

## ⚠️ Troubleshooting

### Server shows as DOWN in Prometheus

1. **Check if exporter is running:**
   ```bash
   # Linux
   sudo systemctl status node_exporter
   
   # Windows (PowerShell)
   Get-Service windows_exporter
   ```

2. **Check firewall:**
   ```bash
   # From monitoring server, test connectivity
   curl http://<server-ip>:9100/metrics   # Linux
   curl http://<server-ip>:9182/metrics   # Windows
   ```

3. **Check Prometheus config syntax:**
   ```bash
   sudo docker compose logs prometheus | tail -20
   ```

### Dashboard shows "No Data"

1. Verify server is UP in Prometheus Targets
2. Check the time range in Grafana (top right)
3. Verify the correct data source is selected
4. Check the `instance` label matches

---

## 📝 Server Inventory Template

Keep track of your monitored servers:

| Server Name | IP Address | OS | Port | Environment | Status |
|-------------|------------|-----|------|-------------|--------|
| monitoring-server | localhost | Linux | 9100 | production | ✅ |
| | | | | | |
| | | | | | |

---

---

## 🗄️ MySQL Monitoring

### MySQL Exporter Setup

MySQL Exporter is already configured in docker-compose.yml. To monitor MySQL:

#### 1. Create MySQL Monitoring User

```sql
-- Connect to MySQL as root
mysql -u root -p

-- Create monitoring user
CREATE USER 'exporter'@'localhost' IDENTIFIED BY 'exporterpassword123';

-- Grant necessary permissions
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';

-- Apply changes
FLUSH PRIVILEGES;
```

#### 2. Restart Docker Compose

```bash
cd /home/azureadmin/multiserver-monitoring-prometheus-grafana
sudo docker compose up -d
```

#### 3. Import MySQL Dashboard in Grafana

1. Open Grafana: `http://<ip>:3000`
2. Go to **Dashboards → Import**
3. Enter Dashboard ID: **7362** (MySQL Overview)
4. Select **Prometheus** as data source
5. Click **Import**

### MySQL Metrics Collected

| Metric | Description |
|--------|-------------|
| Queries per second | Rate of SQL queries |
| Connections | Active/total connections |
| Buffer pool | InnoDB buffer pool usage |
| Slow queries | Number of slow queries |
| Table locks | Lock wait statistics |
| Replication | Slave status (if applicable) |

### Recommended MySQL Dashboards

| Dashboard ID | Name |
|--------------|------|
| **7362** | MySQL Overview |
| **14057** | MySQL Dashboard |
| **6239** | MySQL Performance Schema |

---

*Last updated: December 2024*

