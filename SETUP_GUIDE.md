# AetherLink Troubleshooting Guide

This guide helps you resolve common issues with AetherLink.

## Table of Contents
- [Installation Issues](#installation-issues)
- [Connection Problems](#connection-problems)
- [Authorization Issues](#authorization-issues)
- [Performance Issues](#performance-issues)
- [Docker Issues](#docker-issues)
- [Platform-Specific Issues](#platform-specific-issues)
- [Debug Mode](#debug-mode)
- [Getting Help](#getting-help)

## Installation Issues

### Binary not found after installation

**Problem**: `aetherlink: command not found`

**Solutions**:
1. Add to PATH:
   ```bash
   # Linux/macOS
   export PATH="$HOME/.local/bin:$PATH"
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   
   # Windows (PowerShell)
   $env:Path += ";$env:LOCALAPPDATA\AetherLink"
   ```

2. Use full path:
   ```bash
   ~/.local/bin/aetherlink --help
   ```

### Permission denied when running

**Problem**: `Permission denied` error

**Solution**:
```bash
chmod +x /path/to/aetherlink
```

### Cargo install fails

**Problem**: `cargo install aetherlink` fails

**Solutions**:
1. Update Rust:
   ```bash
   rustup update
   ```

2. Clear cargo cache:
   ```bash
   cargo clean
   rm -rf ~/.cargo/registry/cache
   ```

3. Install with verbose output:
   ```bash
   cargo install --verbose aetherlink
   ```

## Connection Problems

### Cannot connect to server

**Problem**: `Failed to connect to server`

**Diagnostic steps**:

1. **Verify server is running**:
   ```bash
   # On server
   ps aux | grep aetherlink
   aetherlink info  # Should show Node ID
   ```

2. **Check Node ID is correct**:
   ```bash
   # On client
   grep "servers" ~/.aetherlink/config.toml
   ```

3. **Test with full Node ID**:
   ```bash
   aetherlink tunnel test.local --local-port 3000 --server nodeXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
   ```

4. **Check firewall** (server shouldn't need open ports, but check anyway):
   ```bash
   # Linux
   sudo iptables -L
   sudo ufw status
   
   # Windows
   netsh advfirewall firewall show rule name=all
   ```

### Connection times out

**Problem**: Connection attempts timeout

**Solutions**:

1. **Enable debug logging**:
   ```bash
   AETHERLINK_LOG_LEVEL=debug aetherlink tunnel test.local --local-port 3000 --server myserver
   ```

2. **Check network connectivity**:
   ```bash
   # Can you reach the internet?
   ping 8.8.8.8
   
   # DNS working?
   nslookup google.com
   ```

3. **Try with increased timeout** (edit `~/.aetherlink/config.toml`):
   ```toml
   [network]
   connection_timeout = 60  # seconds
   ```

### Tunnel connects but no data flows

**Problem**: Tunnel establishes but HTTP requests fail

**Solutions**:

1. **Verify local service**:
   ```bash
   curl http://localhost:3000  # Replace with your port
   ```

2. **Check tunnel status**:
   ```bash
   aetherlink list --server myserver
   ```

3. **Test with simple HTTP server**:
   ```bash
   # Python
   python3 -m http.server 8000
   
   # Then tunnel it
   aetherlink tunnel test.local --local-port 8000 --server myserver
   ```

## Authorization Issues

### Authorization denied

**Problem**: `Unauthorized client` error

**Solutions**:

1. **Get your client ID**:
   ```bash
   aetherlink info
   # Copy the Node ID
   ```

2. **On server, authorize the client**:
   ```bash
   aetherlink authorize <client-node-id>
   ```

3. **Verify authorization**:
   ```bash
   # On server
   ls ~/.aetherlink/auth/
   ```

### Lost authorization after server restart

**Problem**: Previously working client now unauthorized

**Solution**:
Check if auth files were deleted:
```bash
# On server
ls ~/.aetherlink/auth/
# Re-authorize if needed
aetherlink authorize <client-node-id>
```

## Performance Issues

### Slow connection speed

**Solutions**:

1. **Check if using relay** (debug logs will show):
   ```bash
   AETHERLINK_LOG_LEVEL=debug aetherlink tunnel ...
   ```

2. **Test bandwidth**:
   ```bash
   # Simple speed test
   curl -o /dev/null http://speedtest.tele2.net/100MB.zip
   ```

3. **Optimize buffer sizes** (in config.toml):
   ```toml
   [performance]
   buffer_size = 65536  # bytes
   ```

### High CPU usage

**Solutions**:

1. **Check for loops**:
   ```bash
   # See what's consuming CPU
   top -p $(pgrep aetherlink)
   ```

2. **Reduce logging verbosity**:
   ```bash
   AETHERLINK_LOG_LEVEL=warn aetherlink server
   ```

## Docker Issues

### Container exits immediately

**Problem**: Docker container stops right after starting

**Solutions**:

1. **Check logs**:
   ```bash
   docker logs aetherlink-server
   ```

2. **Run interactively**:
   ```bash
   docker run -it --rm ghcr.io/hhftechnology/aetherlink:latest /bin/sh
   ```

3. **Verify initialization**:
   ```bash
   docker exec aetherlink-server aetherlink info
   ```

### Cannot access tunneled service from Docker

**Problem**: Tunnel works but can't access from container

**Solution** - Use host network:
```bash
docker run --network host ...
```

Or expose ports:
```bash
docker run -p 8080:8080 ...
```

### Permission issues in container

**Problem**: `Permission denied` errors in Docker

**Solution** - Fix volume permissions:
```bash
# Create volume with correct permissions
docker volume create aetherlink-data
docker run -v aetherlink-data:/home/aetherlink/.aetherlink ...
```

## Platform-Specific Issues

### Linux

#### Systemd service won't start

**Check status**:
```bash
sudo systemctl status aetherlink
sudo journalctl -u aetherlink -n 50
```

**Common fixes**:
```bash
# Fix permissions
sudo chown -R aetherlink:aetherlink /etc/aetherlink

# Reload after config changes
sudo systemctl daemon-reload
sudo systemctl restart aetherlink
```

### macOS

#### "Developer cannot be verified" error

**Solution**:
```bash
# Remove quarantine attribute
xattr -d com.apple.quarantine /path/to/aetherlink

# Or allow in System Preferences > Security & Privacy
```

#### Firewall blocking connections

**Solution**:
```bash
# Add to firewall exceptions
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /path/to/aetherlink
```

### Windows

#### Windows Defender blocks AetherLink

**Solution**:
1. Open Windows Security
2. Go to Virus & threat protection
3. Add exclusion for AetherLink folder

#### PowerShell execution policy error

**Solution**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### Service won't start

**Check service**:
```powershell
Get-Service AetherLink
Get-EventLog -LogName System -Source AetherLink -Newest 10
```

## Debug Mode

### Enable verbose logging

```bash
# Maximum verbosity
AETHERLINK_LOG_LEVEL=trace aetherlink server

# Or in config.toml
[logging]
level = "trace"
```

### Log locations

- Linux/macOS: `~/.aetherlink/logs/`
- Windows: `%APPDATA%\AetherLink\logs\`
- Docker: `/home/aetherlink/.aetherlink/logs/`

### Analyze logs

```bash
# View latest errors
grep ERROR ~/.aetherlink/logs/*.log

# Follow logs in real-time
tail -f ~/.aetherlink/logs/*.log

# Check for specific issues
grep -i "connection refused" ~/.aetherlink/logs/*.log
```

### Network debugging

```bash
# Check if ports are listening
netstat -tuln | grep aetherlink
lsof -i :2019  # Admin port

# Test connectivity
nc -zv localhost 3000  # Your local service
```

## Common Error Messages

### "Already in use"

**Error**: `Address already in use`

**Fix**:
```bash
# Find process using port
lsof -i :3000
kill <PID>

# Or use different port
aetherlink tunnel test.local --local-port 3001 --server myserver
```

### "No such file or directory"

**Error**: `No such file or directory: config.toml`

**Fix**:
```bash
aetherlink init
```

### "Invalid node ID"

**Error**: `Invalid node ID format`

**Fix**: Node IDs should be 52 characters, starting with "node":
```
node5t7u8i9o0p1a2s3d4f5g6h7j8k9l0z1x2c3v4b5n6m7q8w9e0r
```

### "Local service unavailable"

**Error**: `Failed to connect to local service`

**Fix**:
1. Ensure service is running
2. Check correct port
3. Try 127.0.0.1 instead of localhost

## Getting Help

### Collect diagnostic information

```bash
# Create