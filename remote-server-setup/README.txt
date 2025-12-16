================================================================================
                    REMOTE SERVER MONITORING SETUP
                         Quick Start Guide
================================================================================

STEP 1: CREATE MYSQL USER (Only if you have MySQL to monitor)
--------------------------------------------------------------------------------

Ask your DBA to run this SQL command:

    CREATE USER 'exporter'@'%' IDENTIFIED BY 'YourSecurePassword';
    GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'exporter'@'%';
    GRANT SELECT ON performance_schema.* TO 'exporter'@'%';
    FLUSH PRIVILEGES;

Note down the username and password - you'll need them in Step 3.

If you DON'T have MySQL on this server, skip to Step 2.


STEP 2: INSTALL DOCKER (If not already installed)
--------------------------------------------------------------------------------

Run this command:

    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER

Then LOGOUT and LOGIN again for permissions to take effect.


STEP 3: RUN THE SETUP SCRIPT
--------------------------------------------------------------------------------

    chmod +x setup.sh
    ./setup.sh

The script will ask you:
  - Do you have MySQL? (y/n)
  - If yes: MySQL username, password, host, port

That's it! The script handles everything else.


STEP 4: TELL THE MONITORING TEAM
--------------------------------------------------------------------------------

After the script completes, send them:
  - Your server IP address
  - Your server hostname

The script will display this information at the end.


================================================================================
                              THAT'S ALL!
================================================================================

The monitoring team will add your server to the central dashboard.
You don't need to do anything else.


--------------------------------------------------------------------------------
                           TROUBLESHOOTING
--------------------------------------------------------------------------------

Q: How do I check if it's working?
A: Run: curl http://localhost:9100/metrics | head

Q: How do I restart the monitoring?
A: Run: cd ~/monitoring && docker compose restart

Q: How do I stop the monitoring?
A: Run: cd ~/monitoring && docker compose down

Q: How do I update MySQL credentials?
A: Edit ~/monitoring/.my.cnf and restart:
   cd ~/monitoring && docker compose restart mysql-exporter

Q: The script says "Docker permission denied"
A: Run: sudo usermod -aG docker $USER
   Then logout and login again.

--------------------------------------------------------------------------------
                              CONTACT
--------------------------------------------------------------------------------

For any issues, contact the monitoring team.


