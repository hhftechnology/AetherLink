# AetherLink: In-Depth Technical Explanation

This document provides a comprehensive technical explanation of how AetherLink works, its architecture, connection flow, and implementation details.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Connection Flow](#connection-flow)
- [Protocol Details](#protocol-details)
- [Server Implementation](#server-implementation)
- [Client Implementation](#client-implementation)
- [Traffic Routing](#traffic-routing)
- [WebSocket Support](#websocket-support)
- [Security Model](#security-model)
- [Performance Characteristics](#performance-characteristics)
- [Deployment Considerations](#deployment-considerations)

## Architecture Overview

AetherLink follows a client-server architecture where the server acts as a reverse proxy and the client creates persistent connections to tunnel local traffic.

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Internet      │    │   AetherLink    │    │   Local         │
│   Client        │◄──►│   Server        │◄──►│   Service       │
│                 │    │                 │    │                 │
│ Browser/App     │    │ Reverse Proxy   │    │ localhost:3000  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │   AetherLink    │
                       │   Client        │
                       │                 │
                       │ Tunnel Manager  │
                       └─────────────────┘
```

### Key Components

1. **AetherLink Server** (`cmd/lt-server`):
   - HTTP/HTTPS server for incoming requests
   - Tunnel manager for client connections
   - Request router and proxy

2. **AetherLink Client** (`cmd/lt-client`):
   - Tunnel initiator and maintainer
   - Local service proxy
   - Connection multiplexer

## Connection Flow

### Initial Setup Phase

1. **Server Startup**:
```go
// Server starts and listens on multiple ports
server := &Server{
    HTTPPort:   8080,        // Main HTTP server
    TunnelPort: 62322,       // Tunnel connections
}
```

2. **Client Registration**:
```bash
# Client requests a tunnel
curl "https://server.com/?new"
# or with custom subdomain
curl "https://server.com/myapp"
```

Response:
```json
{
  "id": "happy-blue-tiger",
  "port": 62322,
  "max_conn_count": 10,
  "url": "https://happy-blue-tiger.server.com"
}
```

3. **Tunnel Establishment**:
```
Client                    Server
  │                         │
  ├─── TCP Connect ─────────►│ :62322
  ├─── Send ID + "\n" ──────►│
  │                         ├─── Register Connection
  │◄──── Connection Ready ───┤
  │                         │
```

### Request Handling Flow

When a user visits the tunnel URL:

```
Internet Request → Server → Route to Client → Local Service → Response Back

1. https://myapp.server.com/api/users
2. Server identifies client "myapp"
3. Server forwards request to client connection
4. Client proxies to localhost:3000/api/users
5. Local service responds
6. Response travels back through tunnel
```

## Protocol Details

### Tunnel Protocol

AetherLink uses a simple TCP-based protocol for tunnel connections:

```
┌─────────────────┐
│   Client ID     │  (terminated by \n)
├─────────────────┤
│                 │
│   HTTP Request  │  (standard HTTP/1.1 format)
│   Stream        │
│                 │
└─────────────────┘
```

### HTTP Request Forwarding

The server forwards complete HTTP requests through the tunnel:

```http
GET /api/users HTTP/1.1
Host: myapp.server.com
User-Agent: Mozilla/5.0...
Accept: application/json
```

The client receives this and proxies it to the local service:

```go
// Client reads the HTTP request
req, err := http.ReadRequest(bufio.NewReader(conn))

// Modify target to point to local service
req.URL.Scheme = "http"
req.URL.Host = "127.0.0.1:3000"

// Forward to local service
localConn, err := net.Dial("tcp", req.URL.Host)
req.Write(localConn)
```

## Server Implementation

### Core Server Structure

```go
type Server struct {
    address string
    port    string
    manager *ClientManager
}

type ClientManager struct {
    clients        sync.Map  // map[string]*Client
    domain         string
    secure         bool
    tunnelListener net.Listener
}

type Client struct {
    id      string
    port    int
    maxConn int
    conns   []net.Conn  // Pool of tunnel connections
    next    int         // Round-robin index
    mutex   sync.Mutex
}
```

### Request Routing Logic

```go
func (m *ClientManager) handler(w http.ResponseWriter, r *http.Request) {
    // 1. Check for API endpoints
    if path == "/api/status" {
        // Return server statistics
    }
    
    // 2. Check for tunnel creation
    if path == "/?new" || isValidSubdomain(path) {
        // Create new tunnel
    }
    
    // 3. Route to existing tunnel
    clientId := extractClientIdFromHost(r.Host)
    client := m.GetClient(clientId)
    
    if isWebSocketUpgrade(r) {
        client.handleUpgrade(w, r)
    } else {
        client.handleRequest(w, r)
    }
}
```

### Connection Management

The server maintains multiple connections per client for load balancing:

```go
func (c *Client) handleRequest(w http.ResponseWriter, r *http.Request) {
    c.mutex.Lock()
    if len(c.conns) == 0 {
        c.mutex.Unlock()
        http.Error(w, "No available connections", http.StatusBadGateway)
        return
    }
    
    // Round-robin connection selection
    conn := c.conns[c.next]
    c.next = (c.next + 1) % len(c.conns)
    c.mutex.Unlock()
    
    // Forward request through tunnel
    if err := r.Write(conn); err != nil {
        c.removeConn(conn)
        http.Error(w, "Proxy error", http.StatusBadGateway)
        return
    }
    
    // Read and forward response
    resp, err := http.ReadResponse(bufio.NewReader(conn), r)
    // ... handle response
}
```

## Client Implementation

### Client Connection Management

```go
func MaintainConnection(tcpAddr, localAddr, id string) {
    for {
        // Establish tunnel connection
        conn, err := net.Dial("tcp", tcpAddr)
        if err != nil {
            time.Sleep(time.Second)
            continue
        }
        
        // Send client ID
        conn.Write([]byte(id + "\n"))
        
        // Handle requests on this connection
        HandleConnection(conn, localAddr)
    }
}
```

### Request Processing

```go
func HandleConnection(conn net.Conn, localPort string) {
    defer conn.Close()
    
    for {
        // Read HTTP request from tunnel
        br := bufio.NewReader(conn)
        req, err := http.ReadRequest(br)
        if err != nil {
            return
        }
        
        // Modify request for local service
        req.URL.Scheme = "http"
        req.URL.Host = "127.0.0.1:" + localPort
        
        // Connect to local service
        localConn, err := net.Dial("tcp", req.URL.Host)
        if err != nil {
            // Send error response
            sendErrorResponse(conn, http.StatusBadGateway)
            continue
        }
        
        // Forward request
        req.Write(localConn)
        
        // Read and forward response
        localBR := bufio.NewReader(localConn)
        resp, err := http.ReadResponse(localBR, req)
        if err != nil {
            localConn.Close()
            continue
        }
        
        // Handle WebSocket upgrade or regular HTTP
        if isWebSocketUpgrade(req, resp) {
            handleWebSocketTunnel(conn, localConn, resp)
            return
        } else {
            resp.Write(conn)
            resp.Body.Close()
        }
        
        localConn.Close()
    }
}
```

## Traffic Routing

### Subdomain-based Routing

When a domain is configured, the server uses subdomain-based routing:

```go
func (m *ClientManager) GetClientIdFromHostname(host string) string {
    if m.domain == "" {
        return ""
    }
    
    // Extract subdomain from host
    h := strings.TrimSuffix(host, "."+m.domain)
    if h == host {
        return ""  // Not a subdomain
    }
    
    return h  // Return subdomain as client ID
}
```

Example routing:
- `api.tunnel.example.com` → Client ID: `api`
- `frontend.tunnel.example.com` → Client ID: `frontend`
- `staging-v2.tunnel.example.com` → Client ID: `staging-v2`

### Path-based Routing (No Domain)

Without a configured domain, routing is path-based:

```
https://server.com/myapp/api/users → Client ID: myapp, Path: /api/users
https://server.com/demo/           → Client ID: demo, Path: /
```

## WebSocket Support

AetherLink provides full WebSocket support through connection hijacking:

### Server-side WebSocket Handling

```go
func (c *Client) handleUpgrade(w http.ResponseWriter, r *http.Request) {
    // Hijack the HTTP connection
    hj, ok := w.(http.Hijacker)
    if !ok {
        http.Error(w, "Webserver doesn't support hijacking", http.StatusInternalServerError)
        return
    }
    
    netConn, _, err := hj.Hijack()
    if err != nil {
        return
    }
    defer netConn.Close()
    
    // Forward upgrade request through tunnel
    conn := c.getNextConnection()
    r.Write(conn)
    
    // Bidirectional copy for WebSocket traffic
    go io.Copy(conn, netConn)
    io.Copy(netConn, conn)
}
```

### Client-side WebSocket Handling

```go
if req.Header.Get("Upgrade") == "websocket" && resp.StatusCode == 101 {
    // Send upgrade response back through tunnel
    resp.Write(conn)
    
    // Start bidirectional copying
    go io.Copy(localConn, conn)
    io.Copy(conn, localConn)
    
    // Connection stays open for WebSocket lifetime
    return
}
```

## Security Model

### Current Security Features

1. **HTTPS Support**: When `--secure=true` is enabled
2. **Subdomain Validation**: Prevents injection attacks
3. **Connection Isolation**: Each tunnel is isolated
4. **Resource Limits**: Maximum connections per tunnel

### Security Considerations

```go
// Subdomain validation
var idRegex = regexp.MustCompile(`^(?:[a-z0-9][a-z0-9\-]{1,61}[a-z0-9]|[a-z0-9]{4,63})$`)

func validateSubdomain(subdomain string) bool {
    if len(subdomain) > 63 || len(subdomain) < 4 {
        return false
    }
    return idRegex.MatchString(subdomain)
}
```

### Limitations

- No authentication mechanism
- No rate limiting
- No access control lists
- Suitable for development/internal use

## Performance Characteristics

### Connection Pooling

Each client maintains multiple connections for better performance:

```go
const DefaultMaxConnections = 10

type Client struct {
    conns   []net.Conn
    next    int  // Round-robin index
    maxConn int
}
```

### Memory Usage

- Server: ~10MB base + ~1MB per active tunnel
- Client: ~5MB base + minimal per connection
- No persistent storage required

### Latency

- Additional latency: 10-50ms (depending on server location)
- Connection overhead: ~1ms per request
- WebSocket: Real-time with minimal buffering

### Throughput

- Limited by network bandwidth and local service performance
- Multiple connections allow parallel request handling
- No artificial throttling or rate limiting

## Deployment Considerations

### Network Requirements

**Server:**
- Port 8080 (or configured port) for HTTP traffic
- Port 62322 for tunnel connections
- Optionally port 443 for HTTPS (with reverse proxy)

**Client:**
- Outbound access to server ports
- Local access to target service port

### DNS Configuration

For subdomain-based routing:
```
*.tunnel.example.com  A  → Server.IP.Address
tunnel.example.com    A  → Server.IP.Address
```

### Reverse Proxy Setup

For production HTTPS termination:

```nginx
server {
    listen 443 ssl http2;
    server_name tunnel.example.com *.tunnel.example.com;
    
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### Monitoring Endpoints

```bash
# Server status
curl https://tunnel.example.com/api/status

# Tunnel-specific status  
curl https://tunnel.example.com/api/tunnels/myapp/status
```

Response format:
```json
{
  "tunnels": 5,
  "mem": {
    "alloc": 1048576,
    "totalAlloc": 2097152,
    "sys": 4194304,
    "heapAlloc": 1048576
  }
}
```

This technical explanation provides the foundation for understanding, deploying, and potentially extending AetherLink for various use cases.