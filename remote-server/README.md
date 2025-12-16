# Remote Server Setup for Multi-Server Monitoring

This folder contains the configuration to run on **remote servers** that you want to monitor.

## Prerequisites

1. Docker and Docker Compose installed on the remote server
2. Network connectivity between main server and remote server on ports 9100 (node-exporter) and 9104 (mysql-exporter)
3. Firewall rules allowing traffic on these ports

## Setup Instructions

### Step 1: Copy files to remote server

Copy this entire `remote-server` folder to your remote server:

```bash
# From your main server, copy to remote server
scp -r ./remote-server user@REMOTE_SERVER_IP:/home/user/monitoring/
```

### Step 2: Configure MySQL Exporter (if needed)

If the remote server has MySQL, edit `.my.cnf` with the correct credentials:

```ini
[client]
host=host.docker.internal
port=3306
user=exporter
password=your_actual_password
```

If no MySQL, remove the mysql-exporter service from `docker-compose.yml`.

### Step 3: Start the exporters on remote server

SSH into the remote server and run:

```bash
cd /home/user/monitoring/remote-server
docker-compose up -d
```

### Step 4: Configure firewall (if needed)

Allow incoming connections on exporter ports:

```bash
# Ubuntu/Debian with UFW
sudo ufw allow 9100/tcp  # Node Exporter
sudo ufw allow 9104/tcp  # MySQL Exporter

# CentOS/RHEL with firewalld
sudo firewall-cmd --permanent --add-port=9100/tcp
sudo firewall-cmd --permanent --add-port=9104/tcp
sudo firewall-cmd --reload
```

### Step 5: Update Prometheus config on main server

On your **main server**, update `prometheus/prometheus.yml` to include the remote server targets.

Replace `REMOTE_SERVER_1_IP` with the actual IP address:

```yaml
# Remote Server 1
- job_name: 'node-exporter-remote1'
  static_configs:
    - targets: ['192.168.1.100:9100']  # <-- Your remote server IP
      labels:
        instance: 'remote-server-1'
        server: 'remote-server-1'
        environment: 'production'
```

### Step 6: Reload Prometheus

After updating the config, reload Prometheus:

```bash
# Option 1: Restart container
docker restart prometheus

# Option 2: Hot reload (if web.enable-lifecycle is enabled)
curl -X POST http://localhost:9090/-/reload
```

## Verify Setup

1. Check if exporters are running on remote server:
   ```bash
   curl http://localhost:9100/metrics  # Node Exporter
   curl http://localhost:9104/metrics  # MySQL Exporter
   ```

2. Check if Prometheus can reach remote exporters:
   - Go to Prometheus UI: `http://MAIN_SERVER_IP:9090`
   - Navigate to Status → Targets
   - Verify all targets show "UP"

## Security Recommendations

For production environments, consider:

1. **Use a VPN** between servers instead of exposing ports publicly
2. **Add authentication** using a reverse proxy (nginx/traefik) with basic auth
3. **Use TLS** for encrypted communication
4. **Restrict IP access** in firewall rules to only allow your main server

