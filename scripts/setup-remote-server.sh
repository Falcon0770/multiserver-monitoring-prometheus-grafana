#!/bin/bash

# ============================================
# Remote Server Setup Script
# Node Exporter + MySQL Exporter (No Prometheus/Grafana)
# ============================================

set -e

echo "=========================================="
echo "  Multi-Server Monitoring Setup"
echo "  Remote Server (Exporters Only)"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_DIR="${1:-$HOME/monitoring}"

echo -e "${YELLOW}Installation directory: $PROJECT_DIR${NC}"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
    echo "Run: curl -fsSL https://get.docker.com | sh"
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}Docker Compose is not installed. Please install Docker Compose first.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Docker and Docker Compose are installed${NC}"

# Create directory
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Create docker-compose.yml
echo -e "${YELLOW}Creating docker-compose.yml...${NC}"
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
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

  # MySQL Exporter - Remove this service if no MySQL on this server
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

# Create MySQL config
echo -e "${YELLOW}Creating MySQL exporter config...${NC}"
cat > .my.cnf << 'EOF'
[client]
host=host.docker.internal
port=3306
user=exporter
password=CHANGE_THIS_PASSWORD
EOF

echo -e "${GREEN}✓ Configuration files created${NC}"

# Start exporters
echo -e "${YELLOW}Starting exporters...${NC}"
docker-compose up -d

# Wait for services
sleep 5

# Check status
echo ""
echo "=========================================="
echo "  Remote Server Setup Complete!"
echo "=========================================="
echo ""
docker-compose ps
echo ""

# Get IP address
SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}Exporters are running:${NC}"
echo "  Node Exporter: http://$SERVER_IP:9100/metrics"
echo "  MySQL Exporter: http://$SERVER_IP:9104/metrics"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Open firewall ports (if needed):"
echo "   sudo ufw allow 9100/tcp"
echo "   sudo ufw allow 9104/tcp"
echo ""
echo "2. On your MAIN server, add this to prometheus/prometheus.yml:"
echo ""
echo "  - job_name: 'node-exporter-$(hostname)'"
echo "    static_configs:"
echo "      - targets: ['$SERVER_IP:9100']"
echo "        labels:"
echo "          instance: '$(hostname)'"
echo "          server: '$(hostname)'"
echo "          environment: 'production'"
echo ""
echo "3. Reload Prometheus on main server:"
echo "   curl -X POST http://MAIN_SERVER_IP:9090/-/reload"
echo ""

