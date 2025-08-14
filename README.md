# AetherLink - Secure Tunneling Solution

AetherLink is a lightweight, secure tunneling solution that creates HTTPS tunnels to expose your local services to the internet. Built with Go for performance and reliability, AetherLink enables developers to share their local development environments, APIs, and web services securely without complex network configuration.

The name "AetherLink" draws inspiration from the classical element "aether" - once thought to be the medium through which light traveled through space. Similarly, AetherLink serves as your medium for secure data transmission across the internet.

## 🆕 New Features in v1.1.0

- **🔐 Token-Based Authentication**: Secure your tunnels with JWT-based authentication
- **🛡️ Access Control**: Prevent unauthorized access to your tunnel server
- **📊 Enhanced Monitoring**: Improved status endpoints with authentication info
- **⏰ Auto-Cleanup**: Automatic cleanup of inactive tunnels
- **🔑 Flexible Auth Options**: Enable/disable authentication as needed

## Features

- **Zero Configuration**: No complex setup required - works out of the box
- **Secure HTTPS**: All connections are encrypted and secured
- **Token Authentication**: Optional JWT-based authentication for enhanced security
- **Custom Subdomains**: Request specific subdomains for your tunnels
- **WebSocket Support**: Full support for real-time applications
- **Cross-Platform**: Binaries available for Linux, macOS, and Windows
- **Docker Support**: Ready-to-use Docker images
- **Lightweight**: Minimal resource usage and fast startup
- **Multiple Connections**: Supports multiple concurrent connections per tunnel

## Quick Start

### Firewall Configuration

**Required Ports**:
- Port 8080 (HTTP server)
- Port 62322 (tunnel connections) 
- Port 80 (HTTP redirects)
- Port 443 (HTTPS)

**Ubuntu/Debian (ufw)**:
```bash
sudo ufw allow 8080
sudo ufw allow 62322
sudo ufw allow 80
sudo ufw allow 443
```

**CentOS/RHEL (firewalld)**:
```bash
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --add-port=62322/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload
```

### Using Pre-built Binaries

1. **Download the latest release** from the [releases page](https://github.com/hhftechnology/AetherLink/releases)

2. **Start the server** (on your remote server):

**Without Authentication** (Development):
```bash
./aetherlink-server-linux-amd64 --address=0.0.0.0 --port=8080 --domain=yourdomain.com --secure=true
```

**With Authentication** (Production):
```bash
./aetherlink-server-linux-amd64 \
  --address=0.0.0.0 \
  --port=8080 \
  --domain=yourdomain.com \
  --secure=true \
  --auth \
  --auth-token=your-secret-key-here
```

3. **Create a tunnel** (from your local machine):
```bash
./aetherlink-client-linux-amd64 --server=https://yourdomain.com --port=3000 --subdomain=dev
```

Your local service running on port 3000 is now accessible at `https://dev.yourdomain.com`

### Using Docker

**Server without Authentication:**
```bash
docker run -d -p 8080:8080 -p 62322:62322 \
  --name aetherlink-server \
  hhftechnology/aetherlink-server \
  --address=0.0.0.0 --port=8080 --domain=yourdomain.com --secure=true
```

**Server with Authentication:**
```bash
docker run -d -p 8080:8080 -p 62322:62322 \
  --name aetherlink-server \
  -e AETHERLINK_AUTH_SECRET=your-secret-key-here \
  hhftechnology/aetherlink-server \
  --address=0.0.0.0 --port=8080 --domain=yourdomain.com --secure=true --auth
```

**Client:**
```bash
docker run --rm --network="host" \
  hhftechnology/aetherlink-client \
  --server=https://your-server.com --port=3000
```

## Authentication

### Server Authentication Options

| Flag | Environment Variable | Description |
|------|---------------------|-------------|
| `--auth` | - | Enable token-based authentication |
| `--auth-token=SECRET` | `AETHERLINK_AUTH_SECRET` | Set authentication secret key |
| `--issuer=NAME` | - | Set token issuer name (default: "aetherlink-server") |

### Authentication Examples

**Basic Authentication Setup:**
```bash
# Server with authentication
./aetherlink-server --auth --auth-token=my-super-secret-key

# Client automatically receives and uses the token
./aetherlink-client --server=https://your-server.com --port=3000
```

**Production Setup with Environment Variable:**
```bash
# Set environment variable for security
export AETHERLINK_AUTH_SECRET=your-very-secure-random-key-here

# Start server
./aetherlink-server --address=0.0.0.0 --port=8080 --domain=tunnel.company.com --secure=true --auth
```

**Docker with Authentication:**
```bash
docker run -d \
  -p 8080:8080 -p 62322:62322 \
  -e AETHERLINK_AUTH_SECRET=your-secret-key \
  hhftechnology/aetherlink-server \
  --address=0.0.0.0 --auth
```

### How Authentication Works

1. **Tunnel Creation**: Client requests a tunnel from the server
2. **Token Generation**: Server generates a JWT token for the tunnel
3. **Token Delivery**: Token is sent back to the client in the response
4. **Connection Authentication**: Client includes the token with each tunnel connection
5. **Token Validation**: Server validates the token before accepting connections

### Security Features

- **JWT Tokens**: Industry-standard JSON Web Tokens for authentication
- **Token Expiration**: Tokens expire after 24 hours by default
- **IP Validation**: Tokens can include client IP for additional security
- **Automatic Cleanup**: Inactive tunnels are automatically removed
- **Secure Defaults**: Random secret generation if none provided

## Installation

### From Source

```bash
git clone https://github.com/hhftechnology/AetherLink.git
cd AetherLink
go mod download
go build -o aetherlink-server ./cmd/lt-server
go build -o aetherlink-client ./cmd/lt-client
```

### Using Go Install

```bash
go install github.com/hhftechnology/AetherLink/cmd/lt-server@latest
go install github.com/hhftechnology/AetherLink/cmd/lt-client@latest
```

## Usage

### Server Configuration

The server accepts the following command-line arguments:

```bash
./aetherlink-server [options]
```

**Options:**
- `--address`: Server bind address (default: "127.0.0.1")
- `--port`: Server port (default: "8080")
- `--domain`: Domain for subdomain routing (optional)
- `--secure`: Enable HTTPS mode (default: false)
- `--auth`: Enable token-based authentication (default: false)
- `--auth-token`: Authentication secret key (optional)
- `--issuer`: Token issuer name (default: "aetherlink-server")
- `--version`: Show version information

**Example:**
```bash
./aetherlink-server \
  --address=0.0.0.0 \
  --port=8080 \
  --domain=tunnel.example.com \
  --secure=true \
  --auth \
  --auth-token=my-secret-key
```

### Client Configuration

The client accepts the following command-line arguments:

```bash
./aetherlink-client [options]
```

**Options:**
- `--server`: Server URL (default: "http://localhost:80")
- `--port`: Local port to expose (default: "80")
- `--subdomain`: Request specific subdomain (optional)
- `--version`: Show version information

**Examples:**

1. **Basic tunnel** (random subdomain):
```bash
./aetherlink-client --server=https://tunnel.example.com --port=3000
```

2. **Custom subdomain**:
```bash
./aetherlink-client --server=https://tunnel.example.com --port=3000 --subdomain=myapp
```

3. **Multiple services**:
```bash
# Terminal 1 - Frontend
./aetherlink-client --server=https://tunnel.example.com --port=3000 --subdomain=frontend

# Terminal 2 - API
./aetherlink-client --server=https://tunnel.example.com --port=8080 --subdomain=api

# Terminal 3 - Database Admin
./aetherlink-client --server=https://tunnel.example.com --port=5432 --subdomain=db
```

## Real-World Examples

### Secure Development Environment

**Scenario**: You want to securely share your development environment with your team.

```bash
# Start secure server with authentication
./aetherlink-server \
  --address=0.0.0.0 \
  --port=8080 \
  --domain=dev.company.com \
  --secure=true \
  --auth \
  --auth-token=company-dev-secret

# Start your React dev server
npm start  # Running on localhost:3000

# Create authenticated tunnel
./aetherlink-client \
  --server=https://dev.company.com \
  --port=3000 \
  --subdomain=myapp-dev
```

Your secure React app is now accessible at `https://myapp-dev.dev.company.com`

### Team Development with Authentication

```bash
# Each team member gets their own authenticated tunnel
./aetherlink-client --server=https://dev.company.com --port=3000 --subdomain=frontend-john
./aetherlink-client --server=https://dev.company.com --port=8080 --subdomain=api-jane
./aetherlink-client --server=https://dev.company.com --port=5432 --subdomain=db-mike
```

## API Endpoints

When running a server, the following endpoints are available:

- `GET /api/status` - Server status and statistics
- `GET /api/tunnels/{id}/status` - Tunnel-specific status
- `GET /?new` - Create a new tunnel with random subdomain
- `GET /{subdomain}` - Create a tunnel with specific subdomain

**Enhanced Status Response (with authentication):**
```json
{
  "tunnels": 3,
  "auth_enabled": true,
  "tunnel_port": 62322,
  "mem": {
    "alloc": 1048576,
    "totalAlloc": 2097152,
    "sys": 4194304,
    "heapAlloc": 1048576
  }
}
```

## Security Considerations

### Authentication Security
- **Strong Secrets**: Use long, random authentication secrets in production
- **Environment Variables**: Store secrets in environment variables, not command line
- **Token Rotation**: Tokens automatically expire and are renewed
- **IP Validation**: Tokens can be tied to specific client IPs

### Network Security
- **HTTPS Only**: When `--secure=true` is enabled, all traffic is encrypted
- **Subdomain Validation**: Subdomains are validated to prevent abuse
- **Connection Limits**: Each tunnel has a maximum number of concurrent connections
- **Firewall Protection**: Ensure proper firewall configuration

### Deployment Security
- **Private Networks**: Deploy servers in private networks when possible
- **Access Control**: Use authentication for any production deployments
- **Monitoring**: Monitor tunnel usage and authentication attempts
- **Regular Updates**: Keep AetherLink updated to the latest version

## Docker Deployment

### Secure Server Deployment

```yaml
# docker-compose.yml
services:
  aetherlink-server:
    image: hhftechnology/aetherlink-server:latest
    container_name: aetherlink-server
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "62322:62322"
    environment:
      - AETHERLINK_AUTH_SECRET=your-very-secure-secret-key-here
      - TZ=UTC
    command: [
      "--address=0.0.0.0",
      "--port=8080", 
      "--domain=tunnel.yourdomain.com",
      "--secure=true",
      "--auth"
    ]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/status"]
      interval: 30s
      timeout: 10s
      retries: 3
```

## Monitoring and Logging

### Authentication Logs

The server logs authentication events:

```bash
# Successful authentication
2024/01/15 10:30:45 Authentication enabled with issuer: aetherlink-server

# Failed authentication attempts
2024/01/15 10:31:20 Invalid token for tunnel myapp: token is expired
2024/01/15 10:31:25 Token tunnel ID mismatch: expected myapp, got wrongapp
```

### Status Monitoring

```bash
# Check server status with auth info
curl https://your-server.com/api/status

# Response includes authentication status
{
  "tunnels": 2,
  "auth_enabled": true,
  "tunnel_port": 62322,
  "mem": {...}
}
```

## Migration Guide

### Upgrading from v1.0.x to v1.1.0

**Server Changes:**
- Add `--auth` flag to enable authentication
- Optionally add `--auth-token` for custom secret
- No breaking changes - existing deployments continue to work

**Client Changes:**
- No changes required - clients automatically handle authentication
- Update to latest binary for best compatibility

**Docker Changes:**
```bash
# Old (still works)
docker run hhftechnology/aetherlink-server

# New with authentication
docker run -e AETHERLINK_AUTH_SECRET=secret hhftechnology/aetherlink-server --auth
```

## Troubleshooting

### Authentication Issues

1. **Token Validation Failed**:
   ```
   Error: Invalid token for tunnel myapp: token is expired
   Solution: Restart client to get new token, or check server time sync
   ```

2. **Missing Authentication**:
   ```
   Error: No token provided
   Solution: Ensure server authentication is properly configured
   ```

3. **Token Mismatch**:
   ```
   Error: Token tunnel ID mismatch
   Solution: Use the correct tunnel ID that matches the token
   ```

### Common Issues

1. **Connection Refused**:
   ```
   Error: Failed to connect to server
   Solution: Verify server is running and accessible, check firewall
   ```

2. **Subdomain Already Exists**:
   ```
   Error: ID myapp already exists
   Solution: Choose a different subdomain or wait for existing tunnel to close
   ```

## Performance

- **Latency**: Minimal additional latency (typically <50ms)
- **Throughput**: Supports high-throughput applications
- **Connections**: Up to 10 concurrent connections per tunnel by default
- **Memory**: Low memory footprint (~10MB per tunnel)
- **Authentication**: JWT validation adds <1ms per request

## Contributing

We welcome contributions! Please see our [contributing guidelines](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/hhftechnology/AetherLink/issues)
- **Discussions**: [GitHub Discussions](https://github.com/hhftechnology/AetherLink/discussions)
- **Documentation**: [Wiki](https://github.com/hhftechnology/AetherLink/wiki)

## Changelog

### v1.1.0 (Latest)
- ✅ Added JWT-based token authentication
- ✅ Enhanced security with optional access control
- ✅ Improved monitoring and status endpoints
- ✅ Automatic cleanup of inactive tunnels
- ✅ Better error handling and logging

### v1.0.0
- ✅ Initial release with basic tunneling
- ✅ HTTP/HTTPS support
- ✅ WebSocket tunneling
- ✅ Docker images
- ✅ Cross-platform binaries

## Acknowledgments

- Built with [Go](https://golang.org/) for performance and reliability
- JWT authentication powered by [golang-jwt](https://github.com/golang-jwt/jwt)
- Inspired by ngrok and similar tunneling solutions
- Thanks to all contributors and the open-source community

---

<p align="center">
  <strong>AetherLink - Secure tunneling made simple</strong><br>
  Built with ❤️ for developers by developers
</p>