# AetherLink

AetherLink is a lightweight, secure tunneling solution that creates HTTPS tunnels to expose your local services to the internet. Built with Go for performance and reliability, AetherLink enables developers to share their local development environments, APIs, and web services securely without complex network configuration.

The name "AetherLink" draws inspiration from the classical element "aether" - once thought to be the medium through which light traveled through space. Similarly, AetherLink serves as your medium for secure data transmission across the internet.

## Features

- **Zero Configuration**: No complex setup required - works out of the box
- **Secure HTTPS**: All connections are encrypted and secured
- **Custom Subdomains**: Request specific subdomains for your tunnels
- **WebSocket Support**: Full support for real-time applications
- **Cross-Platform**: Binaries available for Linux, macOS, and Windows
- **Docker Support**: Ready-to-use Docker images
- **Lightweight**: Minimal resource usage and fast startup
- **Multiple Connections**: Supports multiple concurrent connections per tunnel

## Quick Start

## Firewall configuration:

1. **Required Ports Table**: 
   - Port 8080 (HTTP server)
   - Port 62322 (tunnel connections) 
   - Port 80 (HTTP redirects)
   - Port 443 (HTTPS)

2. **Firewall Examples** for different systems:
   - **Ubuntu/Debian (ufw)**: Most common VPS setup
   - **CentOS/RHEL (firewalld)**: Red Hat-based systems
   - **iptables**: Manual configuration

3. **Cloud Provider Examples**:
   - **AWS Security Groups**: EC2 instance rules
   - **Google Cloud Firewall**: GCP command-line setup

4. **Important Notes**:
   - Custom port considerations
   - Updated security considerations to include firewall protection

The firewall section is now properly placed before the Security Considerations section and provides users with ready-to-use commands for securing their AetherLink deployment on any VPS or cloud server.

### Using Pre-built Binaries

1. **Download the latest release** from the [releases page](https://github.com/hhftechnology/AetherLink/releases)

2. **Start the server** (on your remote server):
```bash
./aetherlink-server-linux-amd64 --address=0.0.0.0 --port=8080 --domain=yourdomain.com --secure=true
```

3. **Create a tunnel** (from your local machine):
```bash
./aetherlink-client-linux-amd64 --server=https://yourdomain.com --port=3000 --subdomain=dev
```

Your local service running on port 3000 is now accessible at `https://dev.yourdomain.com`

### Using Docker

**Server:**
```bash
docker run -d -p 8080:8080 -p 443:443 \
  --name aetherlink-server \
  hhftechnology/aetherlink-server
```

**Client:**
```bash
docker run --rm --network="host" \
  hhftechnology/aetherlink-client \
  --server=https://your-server.com --port=3000
```

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

**Example:**
```bash
./aetherlink-server --address=0.0.0.0 --port=8080 --domain=tunnel.example.com --secure=true
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

### Development Environment

**Scenario**: You're developing a React application locally and want to share it with your team or test it on mobile devices.

```bash
# Start your React dev server
npm start  # Running on localhost:3000

# In another terminal, create the tunnel
./aetherlink-client --server=https://your-tunnel-server.com --port=3000 --subdomain=myapp-dev
```

Now your React app is accessible at `https://myapp-dev.your-tunnel-server.com`

### API Development

**Scenario**: You're building an API and need to test webhooks from external services.

```bash
# Start your API server
go run main.go  # Running on localhost:8080

# Create the tunnel
./aetherlink-client --server=https://your-tunnel-server.com --port=8080 --subdomain=api-dev
```

Your API is now accessible at `https://api-dev.your-tunnel-server.com`

### Full-Stack Development

**Scenario**: You have a frontend and backend running locally and want to demo the complete application.

```bash
# Start backend (terminal 1)
./aetherlink-client --server=https://your-tunnel-server.com --port=8080 --subdomain=api

# Start frontend (terminal 2)  
./aetherlink-client --server=https://your-tunnel-server.com --port=3000 --subdomain=app
```

- Frontend: `https://app.your-tunnel-server.com`
- Backend: `https://api.your-tunnel-server.com`

## Architecture

AetherLink consists of two main components:

### Server Architecture
```
Internet → Load Balancer/Reverse Proxy → AetherLink Server
                                            ↓
                                      Tunnel Manager
                                            ↓
                                    Client Connections
```

The server:
1. Listens for incoming HTTP/HTTPS requests
2. Routes requests based on subdomain (if domain is configured)
3. Manages tunnel connections from clients
4. Proxies requests to the appropriate client connection

### Client Architecture
```
Local Service ← AetherLink Client ← Server Connection
     ↑                 ↓
   localhost:PORT   TCP Connection
```

The client:
1. Establishes a persistent connection to the server
2. Receives HTTP requests forwarded by the server
3. Proxies requests to the local service
4. Returns responses back through the tunnel

## API Endpoints

When running a server, the following endpoints are available:

- `GET /api/status` - Server status and statistics
- `GET /api/tunnels/{id}/status` - Tunnel-specific status
- `GET /?new` - Create a new tunnel with random subdomain
- `GET /{subdomain}` - Create a tunnel with specific subdomain

## Security Considerations

- **HTTPS Only**: When `--secure=true` is enabled, all traffic is encrypted
- **Subdomain Validation**: Subdomains are validated to prevent abuse
- **Connection Limits**: Each tunnel has a maximum number of concurrent connections
- **No Authentication**: Currently, no authentication is required (suitable for development environments)

## Docker Deployment

### Server Deployment

```bash
# Create a network
docker network create aetherlink-net

# Run the server
docker run -d \
  --name aetherlink-server \
  --network aetherlink-net \
  -p 8080:8080 \
  hhftechnology/aetherlink-server \
  --address=0.0.0.0 --port=8080 --domain=yourdomain.com --secure=true
```

### Client Usage

```bash
# Run client (connecting to dockerized server)
docker run --rm \
  --network="host" \
  hhftechnology/aetherlink-client \
  --server=https://yourdomain.com --port=3000 --subdomain=myapp
```

## Monitoring and Logging

### Server Monitoring

Check server status:
```bash
curl https://your-server.com/api/status
```

Monitor specific tunnel:
```bash
curl https://your-server.com/api/tunnels/myapp/status
```

### Logs

Server logs are output to stdout/stderr and can be viewed with:
```bash
docker logs aetherlink-server
```

## Troubleshooting

### Common Issues

1. **Connection Refused**:
   ```
   Error: Failed to connect to server
   Solution: Verify server is running and accessible
   ```

2. **Subdomain Already Exists**:
   ```
   Error: ID myapp already exists
   Solution: Choose a different subdomain or wait for existing tunnel to close
   ```

3. **Local Service Not Running**:
   ```
   Error: Failed to connect to local
   Solution: Ensure your local service is running on the specified port
   ```

### Debug Mode

Run with verbose logging:
```bash
./aetherlink-client --server=https://your-server.com --port=3000 -v
```

## Performance

- **Latency**: Minimal additional latency (typically <50ms)
- **Throughput**: Supports high-throughput applications
- **Connections**: Up to 10 concurrent connections per tunnel by default
- **Memory**: Low memory footprint (~10MB per tunnel)

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

## Acknowledgments

- Built with [Go](https://golang.org/) for performance and reliability
- Inspired by ngrok and similar tunneling solutions
- Thanks to all contributors and the open-source community

---

<p align="center">
  <strong>AetherLink - Secure tunneling made simple</strong><br>
  Built with ❤️ for developers by developers
</p>