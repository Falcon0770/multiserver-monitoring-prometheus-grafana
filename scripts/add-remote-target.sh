#!/bin/bash

# ============================================
#  ADD REMOTE SERVER TO MONITORING
#  Run this after they send you their IP
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROMETHEUS_CONFIG="$PROJECT_DIR/prometheus/prometheus.yml"

clear
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════╗"
echo "║       ADD REMOTE SERVER TO MONITORING          ║"
echo "╚════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# ============================================
# Get Server Details
# ============================================

echo -e "${YELLOW}Enter the remote server details:${NC}"
echo ""

# Get IP
read -p "Server IP Address: " REMOTE_IP

# Validate IP format
if [[ ! $REMOTE_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}✗ Invalid IP address format${NC}"
    exit 1
fi

# Get name
echo ""
echo "Enter a name for this server (this will appear in Grafana)"
echo "Examples: web-server-01, database-prod, app-server-staging"
read -p "Server Name: " SERVER_NAME

# Validate name (no spaces, lowercase)
SERVER_NAME=$(echo "$SERVER_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

# Get environment
echo ""
echo "Select environment:"
echo "  1) production"
echo "  2) staging"
echo "  3) development"
read -p "Enter choice [1]: " ENV_CHOICE

case $ENV_CHOICE in
    2) ENVIRONMENT="staging" ;;
    3) ENVIRONMENT="development" ;;
    *) ENVIRONMENT="production" ;;
esac

# Check for MySQL
echo ""
read -p "Does this server have MySQL monitoring? (y/n) [n]: " HAS_MYSQL
HAS_MYSQL=${HAS_MYSQL:-n}

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}You are adding:${NC}"
echo ""
echo "  Server Name:   $SERVER_NAME"
echo "  IP Address:    $REMOTE_IP"
echo "  Environment:   $ENVIRONMENT"
echo "  MySQL:         $([ "$HAS_MYSQL" == "y" ] && echo "Yes" || echo "No")"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -p "Continue? (y/n): " CONFIRM

if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
    echo "Cancelled."
    exit 0
fi

# ============================================
# Test Connectivity
# ============================================
echo ""
echo -e "${YELLOW}Testing connectivity...${NC}"

if curl -s --connect-timeout 5 "http://$REMOTE_IP:9100/metrics" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Node Exporter is reachable at $REMOTE_IP:9100${NC}"
else
    echo -e "${RED}✗ Cannot reach Node Exporter at $REMOTE_IP:9100${NC}"
    echo ""
    echo "Possible issues:"
    echo "  - Firewall blocking port 9100"
    echo "  - Node Exporter not running on remote server"
    echo "  - Wrong IP address"
    echo ""
    read -p "Add anyway? (y/n): " ADD_ANYWAY
    if [[ $ADD_ANYWAY != "y" ]]; then
        exit 1
    fi
fi

if [[ $HAS_MYSQL == "y" || $HAS_MYSQL == "Y" ]]; then
    if curl -s --connect-timeout 5 "http://$REMOTE_IP:9104/metrics" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ MySQL Exporter is reachable at $REMOTE_IP:9104${NC}"
    else
        echo -e "${YELLOW}⚠ Cannot reach MySQL Exporter at $REMOTE_IP:9104${NC}"
    fi
fi

# ============================================
# Backup Config
# ============================================
echo ""
echo -e "${YELLOW}Backing up current config...${NC}"
cp "$PROMETHEUS_CONFIG" "$PROMETHEUS_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
echo -e "${GREEN}✓ Backup created${NC}"

# ============================================
# Add to Prometheus Config
# ============================================
echo ""
echo -e "${YELLOW}Adding server to Prometheus config...${NC}"

# Remove trailing empty lines from config
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$PROMETHEUS_CONFIG"

# Add new server config
cat >> "$PROMETHEUS_CONFIG" << EOF

  # ============================================
  # $SERVER_NAME ($REMOTE_IP)
  # Added: $(date '+%Y-%m-%d %H:%M:%S')
  # ============================================
  
  - job_name: 'node-exporter-$SERVER_NAME'
    static_configs:
      - targets: ['$REMOTE_IP:9100']
        labels:
          instance: '$SERVER_NAME'
          server: '$SERVER_NAME'
          environment: '$ENVIRONMENT'
EOF

if [[ $HAS_MYSQL == "y" || $HAS_MYSQL == "Y" ]]; then
cat >> "$PROMETHEUS_CONFIG" << EOF

  - job_name: 'mysql-exporter-$SERVER_NAME'
    static_configs:
      - targets: ['$REMOTE_IP:9104']
        labels:
          instance: '$SERVER_NAME-mysql'
          server: '$SERVER_NAME'
          environment: '$ENVIRONMENT'
EOF
fi

echo -e "${GREEN}✓ Server added to prometheus.yml${NC}"

# ============================================
# Reload Prometheus
# ============================================
echo ""
echo -e "${YELLOW}Reloading Prometheus...${NC}"

if curl -s -X POST http://localhost:9090/-/reload > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Prometheus reloaded successfully${NC}"
else
    echo -e "${YELLOW}⚠ Hot reload failed. Restarting Prometheus container...${NC}"
    cd "$PROJECT_DIR"
    docker restart prometheus > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Prometheus restarted${NC}"
    else
        docker-compose restart prometheus > /dev/null 2>&1
        echo -e "${GREEN}✓ Prometheus restarted${NC}"
    fi
fi

# Wait for Prometheus to be ready
sleep 3

# ============================================
# Verify Target
# ============================================
echo ""
echo -e "${YELLOW}Verifying target status...${NC}"
sleep 2

TARGET_STATUS=$(curl -s "http://localhost:9090/api/v1/targets" | grep -o "\"$SERVER_NAME\"" 2>/dev/null)

if [ -n "$TARGET_STATUS" ]; then
    echo -e "${GREEN}✓ Target '$SERVER_NAME' is registered in Prometheus${NC}"
else
    echo -e "${YELLOW}⚠ Target added. Check status at http://localhost:9090/targets${NC}"
fi

# ============================================
# Done!
# ============================================
echo ""
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════╗"
echo "║              SERVER ADDED!                     ║"
echo "╚════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "Server '$SERVER_NAME' has been added to monitoring."
echo ""
echo "View targets:    http://localhost:9090/targets"
echo "View in Grafana: http://localhost:3000"
echo ""
echo "In Grafana dashboards, select '$SERVER_NAME' from the"
echo "instance/server dropdown to view this server's metrics."
echo ""
