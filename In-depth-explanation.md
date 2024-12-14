## The way AetherLink works, there are two methods for connecting the client and server:

1. **Direct Client-Server Connection**:
```bash
# On the client machine
aetherlink yourdomain.com 443 --local-port 3000
```
This method requires:
- The server running AetherLink (with Caddy) must be accessible at `yourdomain.com`
- Port 443 (HTTPS) must be open on the server
- Port 2019 must be accessible for Caddy's admin API (preferably only locally)

2. **SSH Tunnel Method** (More secure and recommended):
```bash
# On the client machine
ssh -R 9001:localhost:3000 user@your-server.com aetherlink yourdomain.com 9001
```

Let me explain the connection flow:

1. **Server Setup**:
```
yourserver.com (Public IP: x.x.x.x)
├── Caddy running on port 443
├── Admin API on port 2019 (localhost only)
└── SSH server running on port 22
```

2. **DNS Configuration Required**:
```
yourdomain.com     →  Points to your server's IP (x.x.x.x)
*.yourdomain.com   →  Points to your server's IP (x.x.x.x)
```

3. **Connection Flow**:
```
Internet → HTTPS (443) → Caddy → Local Service
                ↑          ↑         ↑
           DNS Records  Routing   SSH Tunnel
```

To make it work:

1. On your server:
```bash
# Install and start AetherLink server
./install.sh
aetherlink-server
```

2. Configure your DNS:
```
Add A record: yourdomain.com → Your.Server.IP
Add A record: *.yourdomain.com → Your.Server.IP
```

3. On your client machine:
```bash
# Method 1: Direct connection (requires server to accept connections on port 2019)
aetherlink yourdomain.com 443 --local-port 3000

# Method 2: SSH tunnel (more secure, recommended)
ssh -R 9001:localhost:3000 user@yourserver.com aetherlink yourdomain.com 9001
```

The SSH tunnel method is recommended because:
- More secure (uses SSH for tunnel creation)
- No need to expose admin API
- Works through firewalls
- Provides authentication through SSH
