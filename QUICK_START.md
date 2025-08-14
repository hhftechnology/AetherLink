# AetherLink Quick Start 

Get your tunnel running in under 5 minutes!

##  Install AetherLink

### Option A: Download Binary (Fastest)
```bash
# Linux/macOS
wget https://github.com/hhftechnology/AetherLink/releases/latest/download/aetherlink-$(uname -s)-$(uname -m)
chmod +x aetherlink-*
sudo mv aetherlink-* /usr/local/bin/aetherlink

# Windows: Download from releases page
```

### Option B: Install with Cargo
```bash
cargo install aetherlink
```

### Option C: Use Docker
```bash
docker pull ghcr.io/hhftechnology/aetherlink:latest
```

##  Server Setup (on VPS/Cloud/Remote Machine)

```bash
# Initialize
aetherlink init

# Get your server ID (SAVE THIS!)
aetherlink info
# Example output: Node ID: node5t7u8i9o0p1a2s3d4f5g6h7j8k9l0z1x2c3v4b5n6m7q8w9e0r

# Start server
aetherlink server
```

##  Client Setup (on Your Local Machine)

```bash
# Initialize
aetherlink init

# Get your client ID (you'll need this for authorization)
aetherlink info
# Example output: Node ID: nodeq9w8e7r6t5y4u3i2o1p0a9s8d7f6g5h4j3k2l1z0x9c8v7b6n

# Save your server for easy access
aetherlink add-server myserver <SERVER-NODE-ID-FROM-STEP-2>
```

##  Authorize Your Client (on Server)

```bash
# On the server, authorize your client
aetherlink authorize <CLIENT-NODE-ID-FROM-STEP-3>
```

##  Create Your Tunnel! (on Client)

```bash
# Expose your local web app (e.g., running on port 3000)
aetherlink tunnel myapp.local --local-port 3000 --server myserver
```

 **Done!** Your local service is now accessible through the tunnel!

---

##  Example: React App

```bash
# Terminal 1: Start your React app
npm start  # Runs on http://localhost:3000

# Terminal 2: Create tunnel
aetherlink tunnel myreactapp.dev --local-port 3000 --server myserver

# Your app is now accessible via the tunnel!
```

##  Example: Multiple Services

```bash
# Frontend (Terminal 1)
aetherlink tunnel frontend.local --local-port 3000 --server myserver

# Backend API (Terminal 2)
aetherlink tunnel api.local --local-port 8080 --server myserver

# Database UI (Terminal 3)
aetherlink tunnel db.local --local-port 5432 --server myserver
```

##  Docker Quick Start

### Server
```bash
# Run server
docker run -d --name aether-server \
  -v aether-data:/home/aetherlink/.aetherlink \
  ghcr.io/hhftechnology/aetherlink:latest server

# Initialize and get ID
docker exec aether-server aetherlink init
docker exec aether-server aetherlink info

# Authorize clients
docker exec aether-server aetherlink authorize <client-id>
```

### Client
```bash
# Run tunnel
docker run -d --name aether-client \
  --network host \
  -v aether-client:/home/aetherlink/.aetherlink \
  ghcr.io/hhftechnology/aetherlink:latest \
  tunnel myapp.local --local-port 3000 --server <server-id>
```

##  Common Commands

```bash
# Check your Node ID
aetherlink info

# List active tunnels
aetherlink list --server myserver

# Add a server alias
aetherlink add-server <name> <node-id>

# Authorize a client (on server)
aetherlink authorize <client-node-id>

# Revoke access (on server)
aetherlink revoke <client-node-id>

# View help
aetherlink --help
```

##  Troubleshooting

| Problem | Solution |
|---------|----------|
| "Cannot connect to server" | Check server ID is correct and server is running |
| "Authorization denied" | Run `aetherlink authorize <your-id>` on server |
| "Local service unavailable" | Ensure your app is running on the specified port |
| "Address already in use" | Kill the process using that port or choose another |

##  Links

- **Full Setup Guide**: [SETUP_GUIDE.md](SETUP_GUIDE.md)
- **Documentation**: [README.md](README.md)
- **GitHub**: https://github.com/hhftechnology/AetherLink
- **Issues**: https://github.com/hhftechnology/AetherLink/issues

---

**Need help?** Check the [full setup guide](SETUP_GUIDE.md) or open an issue on GitHub!