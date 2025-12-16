# 📋 Complete Setup Guide: Multi-Server Monitoring with Prometheus & Grafana

> **Purpose**: This document contains everything needed to replicate this monitoring setup from scratch on any new environment.

---

## 📁 Project Structure

```
multiserver-monitoring-prometheus-grafana/
├── docker-compose.yml              # Main compose file (Prometheus + Grafana + Exporters)
├── prometheus/
│   ├── prometheus.yml              # Prometheus configuration (targets, scrape intervals)
│   └── prometheus-multiserver.yml  # Multi-server config template
├── grafana/
│   └── provisioning/
│       └── datasources/
│           └── prometheus.yml      # Auto-configures Prometheus as data source
├── mysql-exporter/
│   └── .my.cnf                     # MySQL credentials for exporter
├── data/
│   ├── prometheus/                 # Prometheus data storage (auto-created)
│   └── grafana/                    # Grafana data storage (auto-created)
└── remote-server/                  # Files to deploy on remote servers
    ├── docker-compose.yml          # Exporters only (no Prometheus/Grafana)
    ├── .my.cnf                     # MySQL credentials template
    └── README.md                   # Remote server setup instructions
```

---

## 🚀 PART 1: Main Server Setup (Fresh Installation)

### Prerequisites
- Linux server (Ubuntu/Debian/CentOS)
- Docker installed
- Docker Compose installed
- Ports 3000, 9090, 9100, 9104 available

### Step 1: Create Project Directory

```bash
mkdir -p ~/multiserver-monitoring-prometheus-grafana
cd ~/multiserver-monitoring-prometheus-grafana
```

### Step 2: Create docker-compose.yml

```bash
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Prometheus - Metrics collection and storage
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./data/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
      - '--web.enable-lifecycle'
    networks:
      - monitoring

  # Node Exporter - Linux system metrics
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - monitoring

  # MySQL Exporter - MySQL database metrics (OPTIONAL - remove if no MySQL)
  mysql-exporter:
    image: prom/mysqld-exporter:latest
    container_name: mysql-exporter
    restart: unless-stopped
    ports:
      - "9104:9104"
    volumes:
      - ./mysql-exporter/.my.cnf:/.my.cnf:ro
    command:
      - '--config.my-cnf=/.my.cnf'
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - monitoring

  # Grafana - Visualization and dashboards
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - ./data/grafana:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    networks:
      - monitoring
    depends_on:
      - prometheus

networks:
  monitoring:
    driver: bridge
EOF
```

### Step 3: Create Prometheus Configuration

```bash
mkdir -p prometheus

cat > prometheus/prometheus.yml << 'EOF'
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

  # Monitor this Linux server via Node Exporter
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          instance: 'main-server'
          server: 'main-server'
          environment: 'production'

  # Monitor MySQL database (remove if no MySQL)
  - job_name: 'mysql-exporter'
    static_configs:
      - targets: ['mysql-exporter:9104']
        labels:
          instance: 'main-server-mysql'
          server: 'main-server'
          environment: 'production'
EOF
```

### Step 4: Create Grafana Datasource Configuration

```bash
mkdir -p grafana/provisioning/datasources

cat > grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
EOF
```

### Step 5: Create MySQL Exporter Config (OPTIONAL)

```bash
mkdir -p mysql-exporter

cat > mysql-exporter/.my.cnf << 'EOF'
[client]
host=host.docker.internal
port=3306
user=exporter
password=your_mysql_password
EOF
```

> **Note**: If you don't have MySQL, remove the `mysql-exporter` service from `docker-compose.yml` and its job from `prometheus/prometheus.yml`

### Step 6: Create Data Directories

```bash
mkdir -p data/prometheus data/grafana
```

### Step 7: Start the Stack

```bash
docker-compose up -d
```

### Step 8: Verify Everything is Running

```bash
# Check all containers are up
docker-compose ps

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].health'

# Check Node Exporter
curl http://localhost:9100/metrics | head -20

# Check Grafana
curl -I http://localhost:3000
```

### Step 9: Access the Dashboards

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| Grafana | http://YOUR_IP:3000 | admin / admin |
| Prometheus | http://YOUR_IP:9090 | No auth |

### Step 10: Import Grafana Dashboards

1. Login to Grafana (http://YOUR_IP:3000)
2. Go to **Dashboards** → **Import**
3. Import these dashboard IDs:
   - **1860** - Node Exporter Full (Linux metrics)
   - **7362** - MySQL Overview (if using MySQL)

---

## 🖥️ PART 2: Adding Remote Servers

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     MAIN SERVER                              │
│  ┌──────────────┐  ┌────────────────┐  ┌─────────────────┐  │
│  │   Grafana    │←─│   Prometheus   │←─│  node-exporter  │  │
│  │  (Dashboard) │  │  (Collects all │  │  mysql-exporter │  │
│  └──────────────┘  │    metrics)    │  └─────────────────┘  │
│                    └───────┬────────┘                        │
└────────────────────────────┼────────────────────────────────┘
                             │ Scrapes over network (ports 9100, 9104)
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                   REMOTE SERVER(S)                           │
│           ┌─────────────────┐                                │
│           │  node-exporter  │ :9100                          │
│           │  mysql-exporter │ :9104 (optional)               │
│           └─────────────────┘                                │
└─────────────────────────────────────────────────────────────┘
```

### On Each Remote Server:

#### Step 1: Create Directory and Files

```bash
mkdir -p ~/monitoring
cd ~/monitoring
```

#### Step 2: Create docker-compose.yml (Exporters Only)

```bash
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Node Exporter - Linux system metrics
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - monitoring

  # MySQL Exporter (OPTIONAL - remove if no MySQL on this server)
  mysql-exporter:
    image: prom/mysqld-exporter:latest
    container_name: mysql-exporter
    restart: unless-stopped
    ports:
      - "9104:9104"
    volumes:
      - ./.my.cnf:/.my.cnf:ro
    command:
      - '--config.my-cnf=/.my.cnf'
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - monitoring

networks:
  monitoring:
    driver: bridge
EOF
```

#### Step 3: Create MySQL Config (if needed)

```bash
cat > .my.cnf << 'EOF'
[client]
host=host.docker.internal
port=3306
user=exporter
password=your_mysql_password
EOF
```

#### Step 4: Start Exporters

```bash
docker-compose up -d
```

#### Step 5: Open Firewall Ports

```bash
# Ubuntu/Debian with UFW
sudo ufw allow 9100/tcp
sudo ufw allow 9104/tcp  # Only if using MySQL exporter

# CentOS/RHEL with firewalld
sudo firewall-cmd --permanent --add-port=9100/tcp
sudo firewall-cmd --permanent --add-port=9104/tcp
sudo firewall-cmd --reload
```

#### Step 6: Verify Exporters are Running

```bash
curl http://localhost:9100/metrics | head -5
curl http://localhost:9104/metrics | head -5  # If MySQL exporter
```

---

### On Main Server: Add Remote Targets

#### Step 1: Edit Prometheus Config

Add the remote server to `prometheus/prometheus.yml`:

```yaml
  # Remote Server 1
  - job_name: 'node-exporter-remote1'
    static_configs:
      - targets: ['REMOTE_IP_1:9100']
        labels:
          instance: 'remote-server-1'
          server: 'remote-server-1'
          environment: 'production'

  - job_name: 'mysql-exporter-remote1'
    static_configs:
      - targets: ['REMOTE_IP_1:9104']
        labels:
          instance: 'remote-server-1-mysql'
          server: 'remote-server-1'
          environment: 'production'

  # Remote Server 2
  - job_name: 'node-exporter-remote2'
    static_configs:
      - targets: ['REMOTE_IP_2:9100']
        labels:
          instance: 'remote-server-2'
          server: 'remote-server-2'
          environment: 'production'
```

#### Step 2: Reload Prometheus

```bash
# Option 1: Hot reload (recommended)
curl -X POST http://localhost:9090/-/reload

# Option 2: Restart container
docker restart prometheus
```

#### Step 3: Verify Targets

1. Go to Prometheus UI: http://MAIN_SERVER_IP:9090
2. Navigate to **Status** → **Targets**
3. All targets should show **UP** status

---

## 🔧 PART 3: MySQL Exporter Setup (Detailed)

### On the MySQL Server (create monitoring user):

```sql
-- Connect to MySQL as root
mysql -u root -p

-- Create exporter user
CREATE USER 'exporter'@'%' IDENTIFIED BY 'your_secure_password';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
FLUSH PRIVILEGES;
```

### Configure .my.cnf:

```ini
[client]
host=host.docker.internal   # Use this for Docker
# host=localhost            # Use this if MySQL is on same host (non-Docker)
# host=192.168.1.50         # Use actual IP if MySQL is on different server
port=3306
user=exporter
password=your_secure_password
```

---

## 📊 PART 4: Grafana Dashboard Setup

### Recommended Dashboards to Import

| Dashboard ID | Name | Use Case |
|--------------|------|----------|
| 1860 | Node Exporter Full | Complete Linux server metrics |
| 7362 | MySQL Overview | MySQL database metrics |
| 14031 | Node Exporter Dashboard | Alternative Linux dashboard |
| 13978 | Windows Exporter | Windows server metrics |

### How to Import:

1. Go to Grafana → **Dashboards** → **Import**
2. Enter the Dashboard ID
3. Select **Prometheus** as data source
4. Click **Import**

### Creating Server Selector Variable:

1. Go to Dashboard → **Settings** (gear icon)
2. Click **Variables** → **Add variable**
3. Configure:
   - Name: `server`
   - Type: Query
   - Data source: Prometheus
   - Query: `label_values(node_uname_info, instance)`
4. Click **Update** → **Save dashboard**

Now you can switch between servers using the dropdown!

---

## 🔄 PART 5: Common Operations

### Restart All Services
```bash
cd ~/multiserver-monitoring-prometheus-grafana
docker-compose restart
```

### View Logs
```bash
docker-compose logs -f prometheus
docker-compose logs -f grafana
docker-compose logs -f node-exporter
```

### Stop All Services
```bash
docker-compose down
```

### Update Images
```bash
docker-compose pull
docker-compose up -d
```

### Backup Grafana Dashboards
```bash
# Dashboards are stored in ./data/grafana
tar -czvf grafana-backup-$(date +%Y%m%d).tar.gz ./data/grafana
```

### Check Prometheus Targets Status
```bash
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health}'
```

---

## 🔐 PART 6: Security Recommendations

### For Production:

1. **Change default passwords**:
   ```yaml
   environment:
     - GF_SECURITY_ADMIN_PASSWORD=your_strong_password
   ```

2. **Use firewall rules** to restrict access:
   ```bash
   # Only allow specific IPs to access Grafana
   sudo ufw allow from 192.168.1.0/24 to any port 3000
   ```

3. **Use VPN** between servers instead of exposing exporter ports publicly

4. **Enable HTTPS** for Grafana using a reverse proxy (nginx/traefik)

---

## 📝 Quick Reference Card

### Ports Used

| Port | Service | Purpose |
|------|---------|---------|
| 3000 | Grafana | Web UI for dashboards |
| 9090 | Prometheus | Metrics storage & queries |
| 9100 | Node Exporter | Linux system metrics |
| 9104 | MySQL Exporter | MySQL database metrics |

### Key URLs

| URL | Purpose |
|-----|---------|
| http://IP:3000 | Grafana Dashboard |
| http://IP:9090 | Prometheus UI |
| http://IP:9090/targets | Check target health |
| http://IP:9100/metrics | Raw node metrics |
| http://IP:9104/metrics | Raw MySQL metrics |

### Key Commands

```bash
# Start stack
docker-compose up -d

# Stop stack
docker-compose down

# View logs
docker-compose logs -f

# Reload Prometheus config
curl -X POST http://localhost:9090/-/reload

# Check if exporter is working
curl http://localhost:9100/metrics | grep node_cpu
```

---

## ✅ Checklist for New Server Setup

### Main Server (First Time):
- [ ] Docker & Docker Compose installed
- [ ] Project directory created
- [ ] docker-compose.yml created
- [ ] prometheus/prometheus.yml created
- [ ] grafana/provisioning/datasources/prometheus.yml created
- [ ] mysql-exporter/.my.cnf created (if using MySQL)
- [ ] `docker-compose up -d` executed
- [ ] All containers running (`docker-compose ps`)
- [ ] Grafana accessible at :3000
- [ ] Prometheus targets showing UP
- [ ] Dashboards imported

### Each Remote Server:
- [ ] Docker & Docker Compose installed
- [ ] docker-compose.yml created (exporters only)
- [ ] .my.cnf created (if using MySQL)
- [ ] `docker-compose up -d` executed
- [ ] Firewall ports opened (9100, 9104)
- [ ] Exporters accessible from main server
- [ ] Target added to main server's prometheus.yml
- [ ] Prometheus reloaded
- [ ] Target showing UP in Prometheus UI

---

*Last Updated: December 2024*

