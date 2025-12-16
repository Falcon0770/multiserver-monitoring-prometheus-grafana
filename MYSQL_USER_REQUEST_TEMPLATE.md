# MySQL Monitoring User Request Template

## 📧 Email/Request Template for Server Admins

Use this template to request MySQL monitoring user credentials from your DBAs or server administrators:

---

**Subject: Request for MySQL Monitoring User - [Server Name]**

Hi Team,

We are setting up centralized monitoring using Prometheus and Grafana. To monitor MySQL database metrics (connections, queries, performance), we need a **read-only MySQL user** on the following server(s):

**Server(s):** [List server names/IPs]

### Required User Permissions

Please create a MySQL user with the following **minimal, read-only permissions**:

```sql
-- Create monitoring user
CREATE USER 'monitoring_exporter'@'%' IDENTIFIED BY 'your_secure_password';

-- Grant minimal required permissions (read-only, no data access)
GRANT PROCESS ON *.* TO 'monitoring_exporter'@'%';
GRANT REPLICATION CLIENT ON *.* TO 'monitoring_exporter'@'%';
GRANT SELECT ON performance_schema.* TO 'monitoring_exporter'@'%';

FLUSH PRIVILEGES;
```

### What These Permissions Allow (Read-Only):
- `PROCESS` - View running queries and connections (no modification)
- `REPLICATION CLIENT` - View replication status (no modification)  
- `SELECT ON performance_schema` - Read performance metrics (no data tables)

### What This User CANNOT Do:
- ❌ Read any actual data from your tables
- ❌ Modify any data or schema
- ❌ Create/drop databases or tables
- ❌ Grant permissions to others

### Information We Need Back:

| Field | Value |
|-------|-------|
| Username | |
| Password | |
| MySQL Host | (IP or hostname) |
| MySQL Port | (default: 3306) |
| Any firewall ports to open? | |

### Security Notes:
- The password will be stored securely on our monitoring server
- Connection is only from our monitoring server IP: [YOUR_MONITORING_SERVER_IP]
- You can restrict the user to only connect from our IP:
  ```sql
  CREATE USER 'monitoring_exporter'@'MONITORING_SERVER_IP' IDENTIFIED BY 'password';
  ```

Thank you!
[Your Name]

---

## 📋 Checklist When You Receive Credentials

Once you receive the credentials, update the configuration:

### For Main Server MySQL:
Edit: `mysql-exporter/.my.cnf`

```ini
[client]
user=USERNAME_THEY_PROVIDED
password=PASSWORD_THEY_PROVIDED
host=host.docker.internal    # If MySQL is on same server
# host=192.168.1.50          # If MySQL is on different server
port=3306
```

### For Remote Server MySQL:
Edit: `remote-server/.my.cnf`

```ini
[client]
user=USERNAME_THEY_PROVIDED
password=PASSWORD_THEY_PROVIDED
host=host.docker.internal    # If MySQL is on same server as exporter
# host=192.168.1.50          # If MySQL is on different server
port=3306
```

### Then Restart the Exporter:
```bash
docker-compose restart mysql-exporter
```

### Verify It's Working:
```bash
# Check if metrics are being collected
curl http://localhost:9104/metrics | grep mysql_up

# Should show: mysql_up 1 (1 = connected, 0 = failed)
```

---

## 🔒 Alternative: More Restrictive User (IP-Locked)

If they want to restrict the user to only your monitoring server:

```sql
-- Replace MONITORING_IP with your actual monitoring server IP
CREATE USER 'monitoring_exporter'@'192.168.1.100' IDENTIFIED BY 'secure_password';
GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'monitoring_exporter'@'192.168.1.100';
GRANT SELECT ON performance_schema.* TO 'monitoring_exporter'@'192.168.1.100';
FLUSH PRIVILEGES;
```

---

## ❓ FAQ for Server Admins

**Q: Can this user see our actual data?**
A: No. The permissions only allow viewing metadata (query counts, connection stats, performance metrics). No SELECT on actual data tables.

**Q: Can this user modify anything?**
A: No. All permissions are read-only.

**Q: What if we don't want to monitor MySQL?**
A: That's fine! Just tell us and we'll skip MySQL monitoring for that server. We can still monitor CPU, memory, disk, and network.

**Q: Can we use an existing read-only user?**
A: Yes, as long as it has PROCESS and REPLICATION CLIENT permissions.

