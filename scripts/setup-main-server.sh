#!/bin/bash

# ============================================
# Main Server Setup Script
# Prometheus + Grafana + Node Exporter + MySQL Exporter
# ============================================

set -e

echo "=========================================="
echo "  Multi-Server Monitoring Setup"
echo "  Main Server Installation"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${YELLOW}Project directory: $PROJECT_DIR${NC}"

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

# Create directories
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p "$PROJECT_DIR/prometheus"
mkdir -p "$PROJECT_DIR/grafana/provisioning/datasources"
mkdir -p "$PROJECT_DIR/mysql-exporter"
mkdir -p "$PROJECT_DIR/data/prometheus"
mkdir -p "$PROJECT_DIR/data/grafana"

# Create docker-compose.yml if it doesn't exist
if [ ! -f "$PROJECT_DIR/docker-compose.yml" ]; then
    echo -e "${YELLOW}Creating docker-compose.yml...${NC}"
    cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
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
fi

# Create prometheus.yml if it doesn't exist
if [ ! -f "$PROJECT_DIR/prometheus/prometheus.yml" ]; then
    echo -e "${YELLOW}Creating prometheus/prometheus.yml...${NC}"
    cat > "$PROJECT_DIR/prometheus/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: 'prometheus-server'

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          instance: 'main-server'
          server: 'main-server'
          environment: 'production'

  - job_name: 'mysql-exporter'
    static_configs:
      - targets: ['mysql-exporter:9104']
        labels:
          instance: 'main-server-mysql'
          server: 'main-server'
          environment: 'production'
EOF
fi

# Create Grafana datasource config
if [ ! -f "$PROJECT_DIR/grafana/provisioning/datasources/prometheus.yml" ]; then
    echo -e "${YELLOW}Creating Grafana datasource config...${NC}"
    cat > "$PROJECT_DIR/grafana/provisioning/datasources/prometheus.yml" << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
EOF
fi

# Create MySQL exporter config
if [ ! -f "$PROJECT_DIR/mysql-exporter/.my.cnf" ]; then
    echo -e "${YELLOW}Creating MySQL exporter config...${NC}"
    cat > "$PROJECT_DIR/mysql-exporter/.my.cnf" << 'EOF'
[client]
host=host.docker.internal
port=3306
user=exporter
password=CHANGE_THIS_PASSWORD
EOF
    echo -e "${RED}⚠ Remember to update mysql-exporter/.my.cnf with your MySQL credentials!${NC}"
fi

echo -e "${GREEN}✓ All configuration files created${NC}"

# Start the stack
echo -e "${YELLOW}Starting Docker containers...${NC}"
cd "$PROJECT_DIR"
docker-compose up -d

# Wait for services to start
echo -e "${YELLOW}Waiting for services to start...${NC}"
sleep 10

# Check status
echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
docker-compose ps
echo ""
echo -e "${GREEN}Access your services:${NC}"
echo "  Grafana:    http://$(hostname -I | awk '{print $1}'):3000  (admin/admin)"
echo "  Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Login to Grafana and change the admin password"
echo "  2. Import dashboard ID 1860 for Node Exporter"
echo "  3. Import dashboard ID 7362 for MySQL (if applicable)"
echo "  4. Update mysql-exporter/.my.cnf if using MySQL monitoring"
echo ""

