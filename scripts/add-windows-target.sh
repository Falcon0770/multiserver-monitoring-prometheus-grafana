#!/bin/bash

# ============================================
# Add Windows Server Target to Prometheus
# ============================================

set -e

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

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════╗"
echo "║     ADD WINDOWS SERVER TO MONITORING          ║"
echo "╚════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if prometheus.yml exists
if [ ! -f "$PROMETHEUS_CONFIG" ]; then
    echo -e "${RED}Error: prometheus.yml not found at $PROMETHEUS_CONFIG${NC}"
    exit 1
fi

# Get server details
echo -e "${YELLOW}Enter Windows server details:${NC}"
echo ""

read -p "Server IP address: " SERVER_IP
read -p "Server name/hostname: " SERVER_NAME
read -p "Environment (production/development/staging): " ENVIRONMENT
ENVIRONMENT=${ENVIRONMENT:-production}

# Validate IP
if [[ ! $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Invalid IP address format${NC}"
    exit 1
fi

# Test connectivity
echo ""
echo -e "${YELLOW}Testing connectivity to Windows Exporter...${NC}"

if curl -s --connect-timeout 5 "http://$SERVER_IP:9182/metrics" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Windows Exporter is reachable at $SERVER_IP:9182${NC}"
else
    echo -e "${RED}✗ Cannot reach Windows Exporter at $SERVER_IP:9182${NC}"
    echo ""
    echo "Please verify:"
    echo "  1. Windows Exporter is installed and running on the Windows server"
    echo "  2. Windows Firewall allows port 9182"
    echo "  3. Network connectivity between servers"
    echo ""
    read -p "Continue anyway? (y/n): " CONTINUE
    if [[ $CONTINUE != "y" && $CONTINUE != "Y" ]]; then
        exit 1
    fi
fi

# Create backup
BACKUP_FILE="$PROMETHEUS_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
cp "$PROMETHEUS_CONFIG" "$BACKUP_FILE"
echo -e "${GREEN}✓ Backup created: $BACKUP_FILE${NC}"

# Generate job name (sanitize server name)
JOB_NAME="windows-exporter-$(echo "$SERVER_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')"

# Check if already exists
if grep -q "job_name: '$JOB_NAME'" "$PROMETHEUS_CONFIG"; then
    echo -e "${YELLOW}⚠ A job with name '$JOB_NAME' already exists in prometheus.yml${NC}"
    read -p "Overwrite? (y/n): " OVERWRITE
    if [[ $OVERWRITE != "y" && $OVERWRITE != "Y" ]]; then
        exit 0
    fi
    # Remove existing entry (this is a simple removal - may need manual cleanup for complex cases)
    echo -e "${YELLOW}Please manually remove the existing entry and run again.${NC}"
    exit 1
fi

# Add new Windows target to prometheus.yml
echo ""
echo -e "${YELLOW}Adding Windows server to prometheus.yml...${NC}"

# Create the new job configuration
NEW_CONFIG="
  # ============================================
  # $SERVER_NAME (Windows) - $SERVER_IP
  # Added: $(date +%Y-%m-%d)
  # ============================================
  
  - job_name: '$JOB_NAME'
    static_configs:
      - targets: ['$SERVER_IP:9182']
        labels:
          instance: '$SERVER_IP'
          node_name: '$SERVER_NAME'
          server: '$SERVER_NAME'
          environment: '$ENVIRONMENT'
          os_type: 'windows'
          service: 'os'"

# Append to prometheus.yml
echo "$NEW_CONFIG" >> "$PROMETHEUS_CONFIG"

echo -e "${GREEN}✓ Configuration added to prometheus.yml${NC}"

# Reload Prometheus
echo ""
echo -e "${YELLOW}Reloading Prometheus configuration...${NC}"

cd "$PROJECT_DIR"

# Try to reload via API first
if curl -s -X POST "http://localhost:9090/-/reload" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Prometheus configuration reloaded${NC}"
else
    # Fall back to docker restart
    echo -e "${YELLOW}API reload failed, restarting Prometheus container...${NC}"
    if docker compose restart prometheus 2>/dev/null || docker-compose restart prometheus 2>/dev/null; then
        echo -e "${GREEN}✓ Prometheus restarted${NC}"
    else
        echo -e "${RED}✗ Could not reload Prometheus. Please restart manually.${NC}"
    fi
fi

# Verify target is being scraped
echo ""
echo -e "${YELLOW}Waiting for Prometheus to scrape target...${NC}"
sleep 10

# Check target status via Prometheus API
TARGET_STATUS=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null | grep -o "\"$SERVER_IP:9182\"" || echo "")
if [ -n "$TARGET_STATUS" ]; then
    echo -e "${GREEN}✓ Target is registered in Prometheus${NC}"
else
    echo -e "${YELLOW}⚠ Target may take a moment to appear in Prometheus${NC}"
fi

# Done
echo ""
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              WINDOWS SERVER ADDED!                        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "Server Details:"
echo "  Name:        $SERVER_NAME"
echo "  IP:          $SERVER_IP"
echo "  Job Name:    $JOB_NAME"
echo "  Environment: $ENVIRONMENT"
echo ""
echo "Verify in Grafana:"
echo "  1. Go to Grafana → Explore"
echo "  2. Query: up{os_type=\"windows\"}"
echo "  3. Or check: http://localhost:9090/targets"
echo ""

