# Detailed examples for both server and client deployment scenarios.

### Server Deployment

1. First, on your server (e.g., AWS EC2, DigitalOcean Droplet, etc.), clone and install AetherLink:

```bash
# On your server (e.g., ubuntu@your-server)
git clone https://github.com/hhftechnology/AetherLink.git
cd AetherLink
./install.sh
source ~/.bashrc
```

2. Start the AetherLink server:
```bash
# Start the server
aetherlink-server
```

3. Make sure your domain's DNS is configured correctly. Add A records for your domains:
```
your-domain.com         A  → Your.Server.IP.Address
*.your-domain.com      A  → Your.Server.IP.Address  (for wildcard subdomains)
```

### Client Usage Examples

Here are several real-world examples of using AetherLink from a client machine:

#### Example 1: React Development Server

```bash
# On your local development machine
# Assuming your React app runs on port 3000
aetherlink dev.your-domain.com 443 --local-port 3000
```
Your React app will be accessible at: `https://dev.your-domain.com`

#### Example 2: Multiple Services Setup

For a typical development stack with multiple services:

```bash
# Terminal 1: Frontend (React)
aetherlink app.your-domain.com 443 --local-port 3000

# Terminal 2: Backend API (Node.js/Express)
aetherlink api.your-domain.com 443 --local-port 8080

# Terminal 3: Database Admin (e.g., MongoDB Express)
aetherlink db.your-domain.com 443 --local-port 8081
```

Now you have:
- Frontend: `https://app.your-domain.com`
- API: `https://api.your-domain.com`
- DB Admin: `https://db.your-domain.com`

#### Example 3: SSH Tunnel Method

If you prefer using SSH directly:

```bash
# Create an SSH tunnel and start AetherLink
ssh -R 9001:localhost:3000 user@your-server.com aetherlink dev.your-domain.com 9001
```

### Complete Production Example

Here's a complete example for setting up a production environment:

1. **Server Setup (Ubuntu 20.04+)**:
```bash
# On your server
# Install required packages
sudo apt update
sudo apt install -y python3 python3-pip curl jq

# Clone AetherLink
git clone https://github.com/hhftechnology/AetherLink.git
cd AetherLink

# Install AetherLink
./install.sh
source ~/.bashrc

# Create a systemd service for AetherLink
sudo tee /etc/systemd/system/aetherlink.service << EOF
[Unit]
Description=AetherLink Tunnel Server
After=network.target

[Service]
Type=simple
User=ubuntu
Environment=AETHERLINK_HOME=/home/ubuntu/.aetherlink
ExecStart=/usr/local/bin/aetherlink-server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Start and enable the service
sudo systemctl daemon-reload
sudo systemctl enable aetherlink
sudo systemctl start aetherlink

# Check status
sudo systemctl status aetherlink
```

2. **DNS Configuration**:
```
# Add these records to your DNS provider
your-domain.com                 A     → Your.Server.IP.Address
*.your-domain.com              A     → Your.Server.IP.Address
api.your-domain.com            A     → Your.Server.IP.Address
staging.your-domain.com        A     → Your.Server.IP.Address
```

3. **Client Usage in Different Scenarios**:

Development Team Setup:
```bash
# Developer 1 (Frontend)
aetherlink dev1.your-domain.com 443 --local-port 3000

# Developer 2 (Frontend)
aetherlink dev2.your-domain.com 443 --local-port 3000

# API Developer
aetherlink api-dev.your-domain.com 443 --local-port 8080
```

Staging Environment:
```bash
# Staging frontend
aetherlink staging.your-domain.com 443 --local-port 3000

# Staging API
aetherlink api-staging.your-domain.com 443 --local-port 8080
```

Demo Environment:
```bash
# Demo instance
aetherlink demo.your-domain.com 443 --local-port 3000
```

4. **Client Setup Script** (for team members):
```bash
#!/bin/bash
# setup-dev.sh

# Install AetherLink
git clone https://github.com/hhftechnology/AetherLink.git
cd AetherLink
./install.sh
source ~/.bashrc

# Create convenience scripts
mkdir -p ~/dev-scripts

cat > ~/dev-scripts/start-frontend.sh << EOF
#!/bin/bash
aetherlink dev-\$(whoami).your-domain.com 443 --local-port 3000
EOF

cat > ~/dev-scripts/start-api.sh << EOF
#!/bin/bash
aetherlink api-\$(whoami).your-domain.com 443 --local-port 8080
EOF

chmod +x ~/dev-scripts/*.sh

echo "Setup complete! Use ~/dev-scripts/start-frontend.sh or start-api.sh to create tunnels"
```

5. **Monitoring Setup**:

```bash
# On the server, check logs
tail -f ~/.aetherlink/logs/aetherlink.log

# Check active tunnels
curl http://localhost:2019/config/apps/http/servers/aetherlink/routes | jq

# Monitor metrics
curl http://localhost:2019/metrics
```

This setup provides:
- Automatic HTTPS for all connections
- Separate subdomains for each developer
- Systemd service for reliable server operation
- Easy client setup for team members
- Monitoring and logging capabilities
