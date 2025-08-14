# AetherLink Setup Guide

This guide will walk you through setting up AetherLink to create secure tunnels for your local services without opening any ports or configuring firewalls.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Installation Methods](#installation-methods)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Common Use Cases](#common-use-cases)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

## Prerequisites

- **Operating System**: Linux, macOS, or Windows
- **Network**: Internet connection (no special firewall rules needed!)
- **Optional**: Docker (for containerized deployment)

## Installation Methods

### Method 1: Using Pre-built Binaries (Easiest)

1. Download the latest release for your platform:
```bash
# Linux (x86_64)
wget https://github.com/hhftechnology/AetherLink/releases/latest/download/aetherlink-linux-amd64
chmod +x aetherlink-linux-amd64
sudo mv aetherlink-linux-amd64 /usr/local/bin/aetherlink

# macOS (Intel)
wget https://github.com/hhftechnology/AetherLink/releases/latest/download/aetherlink-macos-amd64
chmod +x aetherlink-macos-amd64
sudo mv aetherlink-macos-amd64 /usr/local/bin/aetherlink

# macOS (Apple Silicon)
wget https://github.com/hhftechnology/AetherLink/releases/latest/download/aetherlink-macos-arm64
chmod +x aetherlink-macos-arm64
sudo mv aetherlink-macos-arm64 /usr/local/bin/aetherlink

# Windows
# Download aetherlink-windows.exe from releases page
# Add to your PATH or move to C:\Windows\System32\
```

### Method 2: Using Cargo (Rust Package Manager)

1. Install Rust if you don't have it:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

2. Install AetherLink:
```bash
cargo install aetherlink
```

### Method 3: Building from Source

1. Clone the repository:
```bash
git clone https://github.com/hhftechnology/AetherLink.git
cd AetherLink
```

2. Build and install:
```bash
./build.sh
sudo cp target/release/aetherlink /usr/local/bin/
```

### Method 4: Using Docker

```bash
docker pull ghcr.io/hhftechnology/aetherlink:latest
```

## Quick Start

### Step 1: Set Up the Server

**On your server machine (e.g., VPS, cloud instance, or any machine with a public IP):**

1. Initialize AetherLink:
```bash
aetherlink init
```

2. Get your server's Node ID (save this, you'll need it for clients):
```bash
aetherlink info
# Output: Node ID: nodexxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

3. Start the server:
```bash
aetherlink server
# Server is now running and ready to accept tunnels!
```

### Step 2: Set Up the Client

**On your local development machine:**

1. Initialize AetherLink:
```bash
aetherlink init
```

2. Get your client's Node ID:
```bash
aetherlink info
# Output: Node ID: nodeyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
```

3. Add your server (using the Node ID from Step 1):
```bash
aetherlink add-server myserver nodexxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Step 3: Authorize the Client (on Server)

**Back on your server machine:**

```bash
# Authorize your client using its Node ID from Step 2
aetherlink authorize nodeyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
```

### Step 4: Create Your First Tunnel

**On your client machine:**

```bash
# If you have a web app running on port 3000
aetherlink tunnel myapp.example.com --local-port 3000 --server myserver

# Output:
# ✓ Tunnel registered: myapp.example.com
# HTTP proxy listening on http://127.0.0.1:8080
# Tunnel active: myapp.example.com → localhost:3000
```

Your local service is now accessible through the tunnel! 🎉

## Detailed Setup

### Server Configuration

#### Running as a System Service (Linux)

1. Install the systemd service:
```bash
sudo cp aetherlink.service /etc/systemd/system/
sudo systemctl daemon-reload
```

2. Start and enable the service:
```bash
sudo systemctl start aetherlink
sudo systemctl enable aetherlink  # Start on boot
```

3. Check status:
```bash
sudo systemctl status aetherlink
sudo journalctl -u aetherlink -f  # View logs
```

#### Using Docker Compose

1. Create a `docker-compose.yml`:
```yaml
version: '3.8'

services:
  aetherlink:
    image: ghcr.io/hhftechnology/aetherlink:latest
    container_name: aetherlink-server
    restart: unless-stopped
    volumes:
      - ./data:/home/aetherlink/.aetherlink
    command: server
```

2. Initialize and start:
```bash
# Initialize (first time only)
docker-compose run --rm aetherlink init

# Get Node ID
docker-compose run --rm aetherlink info

# Start server
docker-compose up -d

# Authorize clients
docker-compose exec aetherlink aetherlink authorize <client-node-id>
```

### Client Configuration

#### Setting Default Server

Edit `~/.aetherlink/config.toml`:
```toml
default_server = "myserver"

[servers]
myserver = "nodexxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
production = "nodezzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"
```

Now you can omit `--server` flag:
```bash
aetherlink tunnel app.local --local-port 3000
```

#### Running Multiple Tunnels

Open multiple terminals and run:
```bash
# Terminal 1: Frontend
aetherlink tunnel frontend.local --local-port 3000 --server myserver

# Terminal 2: Backend API
aetherlink tunnel api.local --local-port 8080 --server myserver

# Terminal 3: Admin Panel
aetherlink tunnel admin.local --local-port 9000 --server myserver
```

## Common Use Cases

### 1. Exposing a React Development Server

```bash
# Start your React app
npm start  # Usually runs on port 3000

# In another terminal, create tunnel
aetherlink tunnel myreactapp.dev --local-port 3000 --server myserver
```

### 2. Sharing a Local API with Team

```bash
# Your API running on port 8080
aetherlink tunnel team-api.dev --local-port 8080 --server myserver

# Share the tunnel URL with your team
# They can now access: http://team-api.dev
```

### 3. Testing Webhooks Locally

```bash
# Local webhook endpoint on port 4000
aetherlink tunnel webhooks.test --local-port 4000 --server myserver

# Use http://webhooks.test as your webhook URL in external services
```

### 4. Remote Access to Local Database UI

```bash
# pgAdmin, phpMyAdmin, or MongoDB Compass
aetherlink tunnel db-admin.local --local-port 5050 --server myserver
```

### 5. Demonstrating a Project to Clients

```bash
# Your project on port 3000
aetherlink tunnel demo.clientname.com --local-port 3000 --server production

# Send the link to your client for review
```

## Docker Deployment Examples

### Running Server in Docker

```bash
# Quick run
docker run -d \
  --name aetherlink-server \
  -v aetherlink-data:/home/aetherlink/.aetherlink \
  ghcr.io/hhftechnology/aetherlink:latest \
  server

# Initialize (first time)
docker exec aetherlink-server aetherlink init

# Get Node ID
docker exec aetherlink-server aetherlink info

# Authorize clients
docker exec aetherlink-server aetherlink authorize <client-node-id>
```

### Running Client in Docker

```bash
# Create tunnel from Docker container
docker run -d \
  --name aetherlink-client \
  --network host \
  -v aetherlink-client:/home/aetherlink/.aetherlink \
  ghcr.io/hhftechnology/aetherlink:latest \
  tunnel myapp.local --local-port 3000 --server <server-node-id>
```

## Environment Variables

You can configure AetherLink using environment variables:

```bash
# Configuration directory (default: ~/.aetherlink)
export AETHERLINK_CONFIG=/custom/path

# Log level (trace, debug, info, warn, error)
export AETHERLINK_LOG_LEVEL=debug

# Default server
export AETHERLINK_SERVER=myserver

# Run with environment variables
AETHERLINK_LOG_LEVEL=debug aetherlink server
```

## Configuration File

AetherLink stores configuration in `~/.aetherlink/config.toml`:

```toml
# Default server for tunnels
default_server = "production"

# Server aliases
[servers]
local = "node1234567890abcdef..."
staging = "nodeabcdef1234567890..."
production = "nodefedcba0987654321..."

# Identity (auto-generated, don't edit)
[identity]
secret_key = "base64-encoded-key..."

# Saved tunnel configurations
[[tunnels]]
domain = "app.example.com"
local_port = 3000
enabled = true

[[tunnels]]
domain = "api.example.com"
local_port = 8080
enabled = true
```

## Security Best Practices

1. **Keep Your Node ID Secret**: Your Node ID is your identity. Don't share server Node IDs publicly.

2. **Authorization Management**: Only authorize trusted clients:
```bash
# List authorized clients (check auth directory)
ls ~/.aetherlink/auth/

# Revoke access
aetherlink revoke <client-node-id>
```

3. **Use Specific Domains**: Use descriptive domain names for your tunnels to avoid confusion.

4. **Regular Updates**: Keep AetherLink updated for security patches:
```bash
cargo install --force aetherlink
```

## Troubleshooting

### "Cannot connect to server"
- Verify the server Node ID is correct
- Ensure the server is running: `aetherlink server`
- Check server logs: `tail -f ~/.aetherlink/logs/*.log`

### "Authorization denied"
- Ensure your client is authorized on the server
- On server: `aetherlink authorize <your-client-node-id>`

### "Local service unavailable"
- Verify your local service is running on the specified port
- Test locally: `curl http://localhost:<port>`

### "Address already in use"
- Another process is using the port
- Find process: `lsof -i :<port>` (Linux/macOS) or `netstat -ano | findstr :<port>` (Windows)

### Server doesn't start
- Check if another instance is running: `ps aux | grep aetherlink`
- Remove stale lock files: `rm ~/.aetherlink/*.lock`

## FAQ

**Q: Do I need a public IP or domain name?**
A: No! AetherLink uses Iroh's P2P network which handles NAT traversal automatically.

**Q: How many tunnels can I run simultaneously?**
A: There's no hard limit. It depends on your system resources and network bandwidth.

**Q: Is the traffic encrypted?**
A: Yes, all traffic is encrypted end-to-end using Iroh's built-in encryption.

**Q: Can I use custom domains?**
A: Yes, you can use any domain name for your tunnels. They don't need to be registered.

**Q: How do I update AetherLink?**
A: Use `cargo install --force aetherlink` or download the latest binary.

**Q: Can I run this on a Raspberry Pi?**
A: Yes! Build from source on the Pi or cross-compile for ARM architecture.

**Q: What ports need to be open?**
A: None! AetherLink uses Iroh's NAT traversal to work through firewalls.

**Q: Can multiple clients connect to one server?**
A: Yes, just authorize each client's Node ID on the server.

## Getting Help

- **Documentation**: https://github.com/hhftechnology/AetherLink
- **Issues**: https://github.com/hhftechnology/AetherLink/issues
- **Community**: https://forum.hhf.technology/

## Next Steps

Now that you have AetherLink running:

1.  Star the project on GitHub
2.  Read the [full documentation](README.md)
3.  Contribute to the project
4.  Join our community forum
5.  Report bugs or request features

---

**Happy Tunneling! **