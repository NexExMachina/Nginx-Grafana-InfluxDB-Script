# Nginx, Grafana, and InfluxDB Installer Script

This script will install Docker, Docker Compose, and create containers for Nginx, Grafana, and InfluxDB. Nginx will act as a reverse proxy for Grafana and InfluxDB and handle the SSL certificate for them.
This script was originally created for the Rust Server community in order to simplify the setup of Rust Server Metrics:
https://github.com/Pinkstink-Rust/Rust-Server-Metrics

Yes, I know this is only one way of configuring these things, not the only way. This setup script was made with security in mind, as opposed to exposing an insecure Grafana and InfluxDB instance over the internet.


# Prerequisites
- Linux VPS - I recommend **Hetzner**. They are cheap and reliable. Ubuntu Server 20.04 or 22.04 is the **required** OS. Other OS choices will not work.
- Domain Name with two DNS Records - one for Grafana (eg. grafana.example.com) and one for InfluxDB (eg. influx.example.com) - These two records should point to your VPS public IPv4 address. Cloudflare proxying is also fine for this. **You will need to create two more TXT records for verification during the install!**
- Firewall rules (if applicable) allowing inbound access to TCP ports **80, 81, and 443**
- Basic knowledge of Linux (How to SSH)

# How To Use
1. SSH to your VPS and run the following command **AS ROOT, not with sudo!**
- ```bash <(curl -s https://raw.githubusercontent.com/lilciv/Nginx-Grafana-InfluxDB-Script/main/nginx-grafana-influx.sh)```
2. Enter a **secure** InfluxDB username and password
3. Enter your Grafana domain as well as your InfluxDB Domain (eg. grafana.example.com and influx.example.com)
4. Create the required DNS TXT records to verify your domain with Let's Encrypt.
4. Once you have your certificate, the script will finish.
5. At this point, your setup is complete. Please follow the Rust Server Metrics instructions to proceed. You should begin at **Step 6**: https://github.com/Pinkstink-Rust/Rust-Server-Metrics
	- Note: Your database URL for Rust Server Metrics will be your InfluxDB subdomain - eg. `https://influx.example.com`.

## FAQ
**What's my database called?**
- The installation script creates a database called **`db01`**
	
**I forgot my database username or password! What do I do?**
- Execute the command **`docker exec InfluxDB /usr/bin/env`** to see this information. It will show the database name, username, and password.
- NOTE: You should use the `INFLUXDB_USER` and `INFLUXDB_USER_PASSWORD`, not the ADMIN credentials when setting up Rust Server Metrics! The standard user has read and write permissions to the `db01` database. Database admin credentials are not needed and not recommended to use for this.

**How do I add my database as a source in Grafana?**
- You can follow this guide (InfluxQL): https://docs.influxdata.com/influxdb/v1.8/tools/grafana/
- The **URL** line is your InfluxDB subdomain - no port needed (eg. https://influx.example.com)

**What is the InfluxDB Retention Policy?**
- This will create a 12-week Retention Policy, along with a 24-hour Shard Group Duration as per the Rust Server Metrics recommendations.

**What happens when my certificate expires?**
- This script auto-creates a cronjob to attempt certificate renewal every day at 23:00, and restart Nginx if successful.

**How do I uninstall all of this?**
- You can run the uninstaller script by executing this command: `bash <(curl -s https://raw.githubusercontent.com/lilciv/Nginx-Grafana-InfluxDB-Script/main/nginx-grafana-influx-uninstall.sh)`
