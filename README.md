# AetherLink

AetherLink is an elegant solution for creating secure HTTPS tunnels to your local services. It enables you to expose your local development servers, APIs, or any web services to the internet securely with automatic HTTPS certificate management.

The name "AetherLink" draws inspiration from the classical element "aether" - once thought to be the medium through which light traveled through space. Similarly, AetherLink serves as your medium for secure data transmission across the internet.

## Key Features

AetherLink provides a robust set of features while maintaining simplicity:

- Automatic HTTPS certificate management via Caddy
- Health monitoring and automatic recovery
- Detailed logging and metrics
- Connection keepalive and fault tolerance
- Zero configuration on the server side
- Standard SSH client compatibility
- Automatic cleanup of resources

## Quick Start Guide

### Server Setup

1. Clone the repository:
```bash
git clone https://github.com/hhftechnology/AetherLink.git
cd AetherLink
```

2. Run the installation script:
```bash
./install.sh
```

3. Start the AetherLink server:
```bash
aetherlink-server
```

### Creating Tunnels

Let's look at some real-world examples of using AetherLink:

#### Example 1: Exposing a Local Development Server

If you're running a React development server on port 3000:

```bash
# On your local machine
aetherlink dev.yourdomain.com 443 --local-port 3000
```

Now your React app is available at https://dev.yourdomain.com

#### Example 2: Sharing a Local API

If you have an API running on port 8080:

```bash
# On your local machine
aetherlink api.yourdomain.com 443 --local-port 8080
```

Your API is now accessible at https://api.yourdomain.com

#### Example 3: Multiple Services

You can run multiple tunnels simultaneously:

```bash
# In terminal 1 - Frontend
aetherlink app.yourdomain.com 443 --local-port 3000

# In terminal 2 - Backend API
aetherlink api.yourdomain.com 443 --local-port 8080

# In terminal 3 - Database admin
aetherlink db.yourdomain.com 443 --local-port 8081
```

## How It Works

AetherLink operates through a sophisticated yet straightforward process:

1. **Server Component**:
   - Caddy server listens on port 443 for incoming HTTPS connections
   - The admin API runs on port 2019 for dynamic configuration
   - Automatic certificate management handles HTTPS setup

2. **Tunnel Creation**:
   - When you run AetherLink, it:
     a. Verifies the local service is running
     b. Configures Caddy for the new domain
     c. Sets up health monitoring
     d. Manages the secure tunnel

3. **Traffic Flow**:
```
Internet -> HTTPS (443) -> Caddy -> Local Service
                 ↑          ↑           ↑
            TLS Cert    Routing     Health Checks
```

## Advanced Usage

### Custom Configuration

You can customize the AetherLink configuration by modifying `~/.aetherlink/config/aetherlink_config.json`:

```json
{
  "apps": {
    "http": {
      "servers": {
        "aetherlink": {
          "listen": [":443"],
          "routes": [],
          "timeouts": {
            "read_body": "10s",
            "read_header": "10s",
            "write": "30s",
            "idle": "120s"
          }
        }
      }
    }
  }
}
```

### Health Monitoring

AetherLink includes built-in health monitoring. You can access metrics at:
```
https://yourdomain.com/metrics
```

### Logging

Logs are stored in `~/.aetherlink/logs/`:
- `aetherlink.log`: Main application logs
- `server.log`: Caddy server logs
- `access.log`: HTTP access logs

View logs in real-time:
```bash
tail -f ~/.aetherlink/logs/aetherlink.log
```

### Environment Variables

AetherLink supports several environment variables:
```bash
AETHERLINK_HOME=~/.aetherlink    # Base directory
AETHERLINK_LOG_LEVEL=INFO        # Logging level
AETHERLINK_CONFIG=custom.json    # Custom config path
```

### Command-Line Interface

Full command-line options:
```bash
aetherlink --help
```

Options include:
```
positional arguments:
  host                  Host domain
  port                  Port number

optional arguments:
  --local-port PORT     Local port to tunnel
  --log-level LEVEL     Set logging level
```

## Security Considerations

AetherLink prioritizes security:

1. **HTTPS Only**: All connections are encrypted using automatic TLS certificates.
2. **Access Control**: The admin API is only accessible from localhost.
3. **Health Checks**: Continuous monitoring prevents service disruption.
4. **Resource Isolation**: Each tunnel operates independently.

## Troubleshooting

Common issues and solutions:

1. **Connection Refused Errors**:
   ```
   Error: Connection refused on local port
   Solution: Ensure your local service is running
   ```

2. **Certificate Errors**:
   ```
   Error: Failed to obtain certificate
   Solution: Verify DNS settings for your domain
   ```

3. **Port Already in Use**:
   ```
   Error: Address already in use
   Solution: Stop other services using port 443 or change the port
   ```

## Project Structure

```
~/.aetherlink/
├── bin/
│   ├── aetherlink         # Main executable
│   └── caddy              # Caddy server
├── config/
│   └── aetherlink_config.json
├── logs/
│   ├── aetherlink.log
│   ├── server.log
│   └── access.log
├── data/
│   └── certificates/      # TLS certificates
└── certs/                 # Additional certificates
```

## Development and Contributing

We welcome contributions! To get started:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

Please ensure your code:
- Includes comprehensive error handling
- Adds appropriate logging
- Maintains backward compatibility
- Includes tests where appropriate

## License

AetherLink is released under the MIT License. See LICENSE file for details.

## Acknowledgments

AetherLink builds upon several excellent open-source projects:
- Caddy for HTTPS and reverse proxy capabilities
- Python for the management layer
- The broader open-source community

## Support

For questions and support:
- Open an issue on GitHub
- Check the FAQ in the wiki
- Join our community discussions https://forum.hhf.technology/

## Future Roadmap

While maintaining our commitment to simplicity, we're considering:
- Docker integration
- Multiple user support
- Custom middleware support
- Extended metrics and monitoring
- API authentication options

Remember: AetherLink's strength lies in its simplicity and reliability. We carefully consider new features to maintain this balance.

*Made with ❤️ for the our community*

These Project is provided as-is, without warranty of any kind. 
