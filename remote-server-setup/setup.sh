#!/bin/bash

# ============================================
#  REMOTE SERVER MONITORING SETUP
#  One-Click Setup Script
# ============================================
#
#  INSTRUCTIONS:
#  1. Create MySQL user (if you have MySQL) - see below
#  2. Run this script: ./setup.sh
#  3. Done! Tell the monitoring team your server IP
#
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════╗"
echo "║       REMOTE SERVER MONITORING SETUP           ║"
echo "║             One-Click Installation             ║"
echo "╚════════════════════════════════════════════════╝"
echo -e "${NC}"

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

echo -e "Server: ${GREEN}$HOSTNAME${NC} ($SERVER_IP)"
echo ""

# ============================================
# Check Prerequisites
# ============================================
echo -e "${YELLOW}[1/5] Checking prerequisites...${NC}"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker is not installed.${NC}"
    echo ""
    echo "Please install Docker first:"
    echo "  curl -fsSL https://get.docker.com | sh"
    echo "  sudo usermod -aG docker \$USER"
    echo "  # Then logout and login again"
    exit 1
fi
echo -e "${GREEN}✓ Docker is installed${NC}"

# Check if Docker Compose is available
if docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}✗ Docker Compose is not installed.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker Compose is available${NC}"

# Check if user can run docker
if ! docker ps &> /dev/null 2>&1; then
    echo -e "${RED}✗ Cannot run Docker. Try: sudo usermod -aG docker \$USER${NC}"
    echo "  Then logout and login again."
    exit 1
fi
echo -e "${GREEN}✓ Docker permissions OK${NC}"
echo ""

# ============================================
# Ask about MySQL
# ============================================
echo -e "${YELLOW}[2/5] MySQL Configuration...${NC}"
echo ""
echo "Does this server have MySQL that needs monitoring?"
read -p "Enter (y/n): " HAS_MYSQL
echo ""

MYSQL_USER=""
MYSQL_PASS=""
MYSQL_HOST="host.docker.internal"
MYSQL_PORT="3306"

if [[ $HAS_MYSQL == "y" || $HAS_MYSQL == "Y" ]]; then
    echo -e "${BLUE}Enter the MySQL monitoring user credentials:${NC}"
    echo "(These should be provided by your DBA)"
    echo ""
    
    read -p "MySQL Username: " MYSQL_USER
    read -s -p "MySQL Password: " MYSQL_PASS
    echo ""
    
    # Ask if MySQL is on this server or remote
    echo ""
    echo "Is MySQL running on this same server?"
    read -p "Enter (y/n): " MYSQL_LOCAL
    
    if [[ $MYSQL_LOCAL != "y" && $MYSQL_LOCAL != "Y" ]]; then
        read -p "Enter MySQL server IP/hostname: " MYSQL_HOST
    fi
    
    read -p "MySQL Port [3306]: " MYSQL_PORT_INPUT
    MYSQL_PORT=${MYSQL_PORT_INPUT:-3306}
    
    echo ""
    echo -e "${GREEN}✓ MySQL credentials saved${NC}"
fi
echo ""

# ============================================
# Create Installation Directory
# ============================================
echo -e "${YELLOW}[3/5] Creating installation...${NC}"

INSTALL_DIR="$HOME/monitoring"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create docker-compose.yml
cat > docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'

services:
  # Node Exporter - System metrics (CPU, RAM, Disk, Network)
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

COMPOSE_EOF

# Add MySQL exporter if needed
if [[ $HAS_MYSQL == "y" || $HAS_MYSQL == "Y" ]]; then
    cat >> docker-compose.yml << 'MYSQL_EOF'
  # MySQL Exporter - Database metrics
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

MYSQL_EOF

    # Create MySQL config file
    cat > .my.cnf << MYCNF_EOF
[client]
user=$MYSQL_USER
password=$MYSQL_PASS
host=$MYSQL_HOST
port=$MYSQL_PORT
MYCNF_EOF

    chmod 600 .my.cnf
    echo -e "${GREEN}✓ MySQL exporter configured${NC}"
fi

# Add networks section
cat >> docker-compose.yml << 'NETWORKS_EOF'
networks:
  monitoring:
    driver: bridge
NETWORKS_EOF

echo -e "${GREEN}✓ Configuration files created${NC}"
echo ""

# ============================================
# Start Services
# ============================================
echo -e "${YELLOW}[4/5] Starting monitoring services...${NC}"

$COMPOSE_CMD pull
$COMPOSE_CMD up -d

sleep 5

# Verify services are running
echo ""
if curl -s http://localhost:9100/metrics > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Node Exporter is running${NC}"
else
    echo -e "${RED}✗ Node Exporter failed to start${NC}"
fi

if [[ $HAS_MYSQL == "y" || $HAS_MYSQL == "Y" ]]; then
    if curl -s http://localhost:9104/metrics > /dev/null 2>&1; then
        MYSQL_UP=$(curl -s http://localhost:9104/metrics | grep "mysql_up " | awk '{print $2}')
        if [[ $MYSQL_UP == "1" ]]; then
            echo -e "${GREEN}✓ MySQL Exporter is running and connected${NC}"
        else
            echo -e "${YELLOW}⚠ MySQL Exporter is running but cannot connect to MySQL${NC}"
            echo "  Check credentials or MySQL access permissions"
        fi
    else
        echo -e "${RED}✗ MySQL Exporter failed to start${NC}"
    fi
fi
echo ""

# ============================================
# Firewall Configuration
# ============================================
echo -e "${YELLOW}[5/5] Firewall configuration...${NC}"
echo ""
echo "The monitoring server needs to access these ports:"
echo "  - Port 9100 (Node Exporter)"
if [[ $HAS_MYSQL == "y" || $HAS_MYSQL == "Y" ]]; then
    echo "  - Port 9104 (MySQL Exporter)"
fi
echo ""

# Try to detect and configure firewall
if command -v ufw &> /dev/null; then
    echo "Detected UFW firewall. Opening ports..."
    sudo ufw allow 9100/tcp 2>/dev/null || echo "  (Run manually: sudo ufw allow 9100/tcp)"
    if [[ $HAS_MYSQL == "y" || $HAS_MYSQL == "Y" ]]; then
        sudo ufw allow 9104/tcp 2>/dev/null || echo "  (Run manually: sudo ufw allow 9104/tcp)"
    fi
    echo -e "${GREEN}✓ Firewall configured${NC}"
elif command -v firewall-cmd &> /dev/null; then
    echo "Detected firewalld. Opening ports..."
    sudo firewall-cmd --permanent --add-port=9100/tcp 2>/dev/null || echo "  (Run manually)"
    if [[ $HAS_MYSQL == "y" || $HAS_MYSQL == "Y" ]]; then
        sudo firewall-cmd --permanent --add-port=9104/tcp 2>/dev/null || echo "  (Run manually)"
    fi
    sudo firewall-cmd --reload 2>/dev/null || true
    echo -e "${GREEN}✓ Firewall configured${NC}"
else
    echo -e "${YELLOW}⚠ Could not detect firewall. Please manually open ports:${NC}"
    echo "  - Port 9100/tcp"
    if [[ $HAS_MYSQL == "y" || $HAS_MYSQL == "Y" ]]; then
        echo "  - Port 9104/tcp"
    fi
fi

# ============================================
# Done!
# ============================================
echo ""
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    SETUP COMPLETE!                        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}SEND THIS INFORMATION TO YOUR MONITORING TEAM:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Server Name:     $HOSTNAME"
echo "  Server IP:       $SERVER_IP"
echo "  Node Exporter:   http://$SERVER_IP:9100"
if [[ $HAS_MYSQL == "y" || $HAS_MYSQL == "Y" ]]; then
echo "  MySQL Exporter:  http://$SERVER_IP:9104"
fi
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Installation directory: $INSTALL_DIR"
echo ""
echo "Useful commands:"
echo "  View status:    cd $INSTALL_DIR && $COMPOSE_CMD ps"
echo "  View logs:      cd $INSTALL_DIR && $COMPOSE_CMD logs -f"
echo "  Restart:        cd $INSTALL_DIR && $COMPOSE_CMD restart"
echo "  Stop:           cd $INSTALL_DIR && $COMPOSE_CMD down"
echo ""

