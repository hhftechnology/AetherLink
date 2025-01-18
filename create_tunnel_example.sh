#!/bin/bash

# AetherLink Tunnel Creator
# This script creates secure SSH tunnels for exposing local services through AetherLink
# with comprehensive error handling, connection management, and security features.

set -euo pipefail

# Default configuration
RETRY_ATTEMPTS=3
RETRY_DELAY=5
KEEP_ALIVE_INTERVAL=60
CONNECTION_TIMEOUT=15
TEMP_DIR="/tmp/aetherlink-$$"
LOG_FILE="${HOME}/.aetherlink/logs/tunnel.log"

# Function to clean up temporary files and processes
cleanup() {
    local exit_code=$?
    echo "Cleaning up resources..."
    
    # Remove temporary directory
    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
    
    # Kill any remaining SSH processes
    if [[ -f "${TEMP_DIR}/tunnel.pid" ]]; then
        local pid
        pid=$(cat "${TEMP_DIR}/tunnel.pid")
        kill "${pid}" 2>/dev/null || true
    fi
    
    exit "${exit_code}"
}

# Set up signal handlers
trap cleanup EXIT
trap 'echo "Interrupted by user"; exit 1' INT TERM

# Function to validate input parameters
validate_inputs() {
    local domain="$1"
    local server_port="$2"
    local local_port="$3"
    
    # Validate domain format
    if ! echo "$domain" | grep -qE '^([a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'; then
        echo "Error: Invalid domain format: $domain" >&2
        return 1
    fi
    
    # Validate ports
    for port in "$server_port" "$local_port"; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            echo "Error: Invalid port number: $port" >&2
            return 1
        fi
    done
}

# Function to check if local service is running
check_local_service() {
    local port="$1"
    if ! nc -z localhost "$port" >/dev/null 2>&1; then
        echo "Error: No service detected on local port $port" >&2
        return 1
    fi
}

# Function to establish SSH tunnel with retries
create_tunnel() {
    local domain="$1"
    local server_port="$2"
    local local_port="$3"
    local attempt=1
    
    while [ $attempt -le $RETRY_ATTEMPTS ]; do
        echo "Attempting to create tunnel (attempt $attempt/$RETRY_ATTEMPTS)..."
        
        # Create SSH tunnel with advanced options
        ssh -N -T -o "ExitOnForwardFailure=yes" \
            -o "ServerAliveInterval=${KEEP_ALIVE_INTERVAL}" \
            -o "ServerAliveCountMax=3" \
            -o "ConnectTimeout=${CONNECTION_TIMEOUT}" \
            -o "StrictHostKeyChecking=accept-new" \
            -R "$server_port:localhost:$local_port" \
            "$domain" "aetherlink $domain $server_port" &
        
        local tunnel_pid=$!
        echo $tunnel_pid > "${TEMP_DIR}/tunnel.pid"
        
        # Wait for tunnel to establish
        sleep 2
        if kill -0 "$tunnel_pid" 2>/dev/null; then
            echo "Tunnel established successfully"
            echo "Local port $local_port is now accessible at https://$domain"
            
            # Monitor tunnel health
            while kill -0 "$tunnel_pid" 2>/dev/null; do
                if ! check_local_service "$local_port"; then
                    echo "Warning: Local service no longer available" >&2
                fi
                sleep 30
            done
            
            echo "Tunnel connection lost. Retrying..."
        else
            echo "Failed to establish tunnel on attempt $attempt" >&2
        fi
        
        ((attempt++))
        sleep "$RETRY_DELAY"
    done
    
    echo "Error: Failed to create tunnel after $RETRY_ATTEMPTS attempts" >&2
    return 1
}

# Setup logging
setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

# Main function
main() {
    # Ensure arguments are provided
    if [ "$#" -ne 3 ]; then
        echo "Usage: $0 <domain> <server_port> <local_port>" >&2
        echo "Example: $0 myapp.example.com 8080 3000" >&2
        exit 1
    fi
    
    local domain="$1"
    local server_port="$2"
    local local_port="$3"
    
    # Create temporary directory
    mkdir -p "${TEMP_DIR}"
    
    # Setup logging
    setup_logging
    
    # Validate inputs and create tunnel
    if validate_inputs "$domain" "$server_port" "$local_port" && \
       check_local_service "$local_port"; then
        create_tunnel "$domain" "$server_port" "$local_port"
    else
        exit 1
    fi
}

main "$@"