# 🔒 Security Guide for Prometheus Monitoring Setup

This guide covers security best practices to protect your monitoring infrastructure from unauthorized access.

---

## ⚠️ Security Risks of Open Exporter Ports

When exporter ports (9100, 9104, 9182) are open to the world, attackers can:

| Risk | What They Can See |
|------|------------------|
| **System Reconnaissance** | CPU count, memory size, disk capacity, OS version |
| **Network Mapping** | Network interfaces, IP addresses, connection states |
| **Process Discovery** | Running processes, services, application names |
| **Database Intelligence** | MySQL version, table sizes, query patterns, user accounts |
| **Capacity Planning** | Server load patterns, usage trends |

---

## 🛡️ Security Layers (Implement All That Apply)

### Layer 1: Firewall IP Whitelisting (ESSENTIAL)

**Only allow your Prometheus server IP to access exporter ports.**

#### Linux (UFW)
```bash
# Remove open rules
sudo ufw delete allow 9100/tcp
sudo ufw delete allow 9104/tcp

# Allow ONLY from Prometheus server (10.20.0.39)
sudo ufw allow from 10.20.0.39 to any port 9100 proto tcp
sudo ufw allow from 10.20.0.39 to any port 9104 proto tcp
sudo ufw reload
```

#### Linux (firewalld)
```bash
# Remove open ports
sudo firewall-cmd --permanent --remove-port=9100/tcp
sudo firewall-cmd --permanent --remove-port=9104/tcp

# Add IP-restricted rules
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.0.39" port protocol="tcp" port="9100" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.0.39" port protocol="tcp" port="9104" accept'
sudo firewall-cmd --reload
```

#### Linux (iptables)
```bash
# Allow only from Prometheus server
sudo iptables -A INPUT -p tcp -s 10.20.0.39 --dport 9100 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 9100 -j DROP
sudo iptables -A INPUT -p tcp -s 10.20.0.39 --dport 9104 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 9104 -j DROP

# Save rules (Debian/Ubuntu)
sudo iptables-save > /etc/iptables/rules.v4
```

#### Windows (PowerShell)
```powershell
# Remove existing rule
Remove-NetFirewallRule -DisplayName "Windows Exporter (Prometheus)" -ErrorAction SilentlyContinue

# Add IP-restricted rule
New-NetFirewallRule -DisplayName "Windows Exporter (Prometheus)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 9182 `
    -Action Allow `
    -RemoteAddress "10.20.0.39" `
    -Description "Allow only Prometheus server to scrape metrics"
```

---

### Layer 2: Network Segmentation (RECOMMENDED)

Place your monitoring infrastructure in a separate network segment:

```
┌─────────────────────────────────────────────────────────────┐
│                    MONITORING VLAN/SUBNET                    │
│  ┌─────────────────┐                                        │
│  │   Prometheus    │◄────── Only this can reach exporters   │
│  │   10.20.0.39    │                                        │
│  └─────────────────┘                                        │
└─────────────────────────────────────────────────────────────┘
         │
         │ Firewall rules allow only 10.20.0.39
         ▼
┌─────────────────────────────────────────────────────────────┐
│                    PRODUCTION SERVERS                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │ Server A │  │ Server B │  │ Server C │                  │
│  │ :9100    │  │ :9100    │  │ :9182    │                  │
│  │ :9104    │  │ :9104    │  │          │                  │
│  └──────────┘  └──────────┘  └──────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

#### Azure NSG Rules Example
```bash
# Allow Prometheus server to reach exporters
az network nsg rule create \
  --resource-group YOUR_RG \
  --nsg-name YOUR_NSG \
  --name AllowPrometheusExporters \
  --priority 100 \
  --source-address-prefixes 10.20.0.39 \
  --destination-port-ranges 9100 9104 9182 \
  --access Allow \
  --protocol Tcp

# Deny all other access to exporter ports
az network nsg rule create \
  --resource-group YOUR_RG \
  --nsg-name YOUR_NSG \
  --name DenyExporterPorts \
  --priority 200 \
  --destination-port-ranges 9100 9104 9182 \
  --access Deny \
  --protocol Tcp
```

---

### Layer 3: TLS Encryption (ADVANCED)

Encrypt metrics traffic using TLS certificates.

#### Step 1: Generate Certificates

```bash
# Create CA and certificates directory
mkdir -p /etc/prometheus/certs
cd /etc/prometheus/certs

# Generate CA private key
openssl genrsa -out ca.key 4096

# Generate CA certificate
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
  -out ca.crt -subj "/CN=Prometheus CA"

# Generate server key and CSR (for each exporter)
openssl genrsa -out node-exporter.key 2048
openssl req -new -key node-exporter.key -out node-exporter.csr \
  -subj "/CN=node-exporter"

# Sign the certificate
openssl x509 -req -in node-exporter.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out node-exporter.crt -days 365 -sha256
```

#### Step 2: Configure Node Exporter with TLS

Create `/etc/node_exporter/web-config.yml`:
```yaml
tls_server_config:
  cert_file: /etc/prometheus/certs/node-exporter.crt
  key_file: /etc/prometheus/certs/node-exporter.key
  client_auth_type: RequireAndVerifyClientCert
  client_ca_file: /etc/prometheus/certs/ca.crt
```

Run node exporter with TLS:
```bash
node_exporter --web.config.file=/etc/node_exporter/web-config.yml
```

#### Step 3: Configure Prometheus to Use TLS

Update `prometheus.yml`:
```yaml
scrape_configs:
  - job_name: 'node-exporter-secure'
    scheme: https
    tls_config:
      ca_file: /etc/prometheus/certs/ca.crt
      cert_file: /etc/prometheus/certs/prometheus.crt
      key_file: /etc/prometheus/certs/prometheus.key
    static_configs:
      - targets: ['10.20.0.38:9100']
```

---

### Layer 4: Basic Authentication (ADVANCED)

Add username/password authentication to exporters.

#### Node Exporter with Basic Auth

Create `/etc/node_exporter/web-config.yml`:
```yaml
basic_auth_users:
  # Generate hash: htpasswd -nBC 10 "" | tr -d ':\n'
  prometheus: $2y$10$HASH_HERE
```

#### Prometheus Configuration
```yaml
scrape_configs:
  - job_name: 'node-exporter-auth'
    basic_auth:
      username: prometheus
      password: YOUR_PASSWORD
    static_configs:
      - targets: ['10.20.0.38:9100']
```

---

### Layer 5: VPN/Private Network (ENTERPRISE)

For maximum security, run all monitoring traffic through a VPN:

```
┌─────────────────────────────────────────┐
│           VPN TUNNEL (WireGuard)         │
│                                          │
│  Prometheus ◄──────────► Remote Servers  │
│  10.10.0.1                10.10.0.x      │
│                                          │
│  All traffic encrypted & authenticated   │
└─────────────────────────────────────────┘
```

#### WireGuard Quick Setup

On Prometheus server:
```bash
# Install WireGuard
sudo apt install wireguard

# Generate keys
wg genkey | tee privatekey | wg pubkey > publickey

# Configure /etc/wireguard/wg0.conf
[Interface]
PrivateKey = <prometheus_private_key>
Address = 10.10.0.1/24
ListenPort = 51820

[Peer]
PublicKey = <remote_server_public_key>
AllowedIPs = 10.10.0.2/32
```

On remote servers:
```bash
[Interface]
PrivateKey = <remote_private_key>
Address = 10.10.0.2/24

[Peer]
PublicKey = <prometheus_public_key>
Endpoint = prometheus.example.com:51820
AllowedIPs = 10.10.0.1/32
PersistentKeepalive = 25
```

Then configure Prometheus to scrape via VPN IPs:
```yaml
- targets: ['10.10.0.2:9100']  # VPN IP instead of public IP
```

---

## 🔐 Securing the Prometheus Server Itself

### Grafana Security
```yaml
# docker-compose.yml
grafana:
  environment:
    - GF_SECURITY_ADMIN_USER=admin
    - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}  # Use env var!
    - GF_USERS_ALLOW_SIGN_UP=false
    - GF_AUTH_ANONYMOUS_ENABLED=false
    - GF_SECURITY_DISABLE_GRAVATAR=true
    - GF_SECURITY_COOKIE_SECURE=true  # If using HTTPS
```

### Prometheus Security
```yaml
# Bind to localhost only if behind reverse proxy
prometheus:
  command:
    - '--web.listen-address=127.0.0.1:9090'
```

### Reverse Proxy with Authentication (nginx)
```nginx
server {
    listen 443 ssl;
    server_name prometheus.example.com;
    
    ssl_certificate /etc/ssl/certs/prometheus.crt;
    ssl_certificate_key /etc/ssl/private/prometheus.key;
    
    location / {
        auth_basic "Prometheus";
        auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://127.0.0.1:9090;
    }
}
```

---

## 📋 Security Checklist

### Minimum Security (Do This Now!)
- [ ] Firewall IP whitelist on all remote servers
- [ ] Change default Grafana admin password
- [ ] Disable Grafana anonymous access

### Recommended Security
- [ ] Network segmentation (separate VLAN/subnet)
- [ ] Azure NSG / AWS Security Group rules
- [ ] Regular security updates for all exporters

### Advanced Security
- [ ] TLS encryption for all exporter traffic
- [ ] Basic authentication on exporters
- [ ] VPN for all monitoring traffic
- [ ] Reverse proxy with auth for Prometheus/Grafana

---

## 🔍 Verify Your Security

### Test Firewall Rules
```bash
# From an unauthorized IP (should fail/timeout)
curl -s --connect-timeout 5 http://TARGET_SERVER:9100/metrics

# From Prometheus server (should work)
curl -s http://TARGET_SERVER:9100/metrics | head -5
```

### Check Open Ports
```bash
# On remote server - see what's listening
sudo ss -tlnp | grep -E '9100|9104|9182'

# From Prometheus server - verify connectivity
nmap -p 9100,9104,9182 TARGET_SERVER
```

### Audit Firewall Rules
```bash
# UFW
sudo ufw status verbose

# firewalld
sudo firewall-cmd --list-all

# iptables
sudo iptables -L -n -v

# Windows
Get-NetFirewallRule -DisplayName "*Exporter*" | Format-Table
```

---

## 🚨 Incident Response

If you suspect unauthorized access to your metrics:

1. **Immediately** restrict firewall rules
2. **Check** exporter access logs (if available)
3. **Review** what data was exposed
4. **Rotate** any credentials visible in metrics
5. **Implement** additional security layers

---

## 📚 Additional Resources

- [Prometheus Security Model](https://prometheus.io/docs/operating/security/)
- [Node Exporter TLS Configuration](https://prometheus.io/docs/guides/tls-encryption/)
- [Grafana Security Best Practices](https://grafana.com/docs/grafana/latest/administration/security/)

