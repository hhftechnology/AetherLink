#!/bin/bash
set -e

# AetherLink Universal Entrypoint Script
# Handles both IP-only and domain modes with automatic detection

BINARY_PATH="/usr/local/bin/aetherlink-server"

# Default environment variables
MODE="${MODE:-auto}"
DOMAIN="${DOMAIN:-}"
USE_SSL="${USE_SSL:-auto}"
SERVER_ADDRESS="${SERVER_ADDRESS:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-8080}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo "=== AetherLink Universal Docker Image ==="
echo "Mode: $MODE"
echo "Domain: ${DOMAIN:-none}"
echo "SSL: $USE_SSL"
echo "Arguments: $*@" 
echo "========================================="

# Function to detect mode from arguments and environment
detect_mode() {
    for arg in "$@"; do
        case $arg in
            --domain=*)
                DOMAIN="${arg#*=}"
                ;;
            --secure=true|--secure)
                USE_SSL=true
                ;;
            --secure=false)
                USE_SSL=false
                ;;
        esac
    done
    
    if [ "$MODE" = "auto" ]; then
        if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "" ]; then
            MODE="domain"
            log_info "Auto-detected: Domain mode (domain: $DOMAIN)"
        else
            MODE="ip"
            log_info "Auto-detected: IP-only mode"
        fi
    fi
    
    if [ "$USE_SSL" = "auto" ]; then
        if [ "$MODE" = "domain" ]; then
            USE_SSL=true
            log_info "Auto-enabled SSL for domain mode"
        else
            USE_SSL=false
            log_info "SSL disabled for IP-only mode"
        fi
    fi
}

# Function to validate configuration
validate_config() {
    # Verify binary exists
    if [ ! -f "$BINARY_PATH" ]; then
        log_error "AetherLink server binary not found at $BINARY_PATH"
        echo "Available files:"
        find / -name "*aetherlink*" -o -name "*server*" 2>/dev/null | head -10
        exit 1
    fi
    
    chmod +x "$BINARY_PATH"
    
    # Validate domain mode requirements
    if [ "$MODE" = "domain" ] && [ -z "$DOMAIN" ]; then
        log_error "Domain mode requires DOMAIN environment variable or --domain argument"
        exit 1
    fi
    
    # Check if required directories exist
    mkdir -p /var/log/aetherlink /var/run/nginx
}

# Function to start server only (IP mode)
start_server_only() {
    log_info "Starting AetherLink server in IP-only mode..."
    
    # Update arguments for IP mode
    ARGS=""
    ADDRESS_SET=false
    for arg in "$@"; do
        case $arg in
            --address=*)
                ARGS="$ARGS --address=0.0.0.0"
                ADDRESS_SET=true
                ;;
            *)
                ARGS="$ARGS $arg"
                ;;
        esac
    done
    
    if [ "$ADDRESS_SET" = "false" ]; then
        ARGS="--address=0.0.0.0 $ARGS"
    fi
    
    log_info "Server will listen on: 0.0.0.0:$SERVER_PORT"
    log_info "Command: $BINARY_PATH $ARGS"
    
    # Start server
    exec $BINARY_PATH $ARGS
}

# Function to configure nginx
configure_nginx() {
    log_info "Configuring nginx for domain mode..."
    
    if [ "$USE_SSL" = "true" ]; then
        log_info "Using HTTPS configuration"
        cp /etc/nginx/templates/nginx-https.conf.template /etc/nginx/nginx.conf
    else
        log_info "Using HTTP-only configuration"
        cp /etc/nginx/templates/nginx-http.conf.template /etc/nginx/nginx.conf
    fi
    
    # Test nginx configuration
    if ! nginx -t; then
        log_error "nginx configuration test failed"
        cat /etc/nginx/nginx.conf
        exit 1
    fi
    
    log_success "nginx configuration validated"
}

# Function to start server and nginx (domain mode)
start_server_and_nginx() {
    log_info "Starting AetherLink server with nginx proxy..."
    
    # Configure nginx
    configure_nginx
    
    # Update server arguments for domain mode
    ARGS=""
    ADDRESS_SET=false
    for arg in "$@"; do
        case $arg in
            --address=*)
                ARGS="$ARGS --address=127.0.0.1"
                ADDRESS_SET=true
                ;;
            *)
                ARGS="$ARGS $arg"
                ;;
        esac
    done
    
    if [ "$ADDRESS_SET" = "false" ]; then
        ARGS="--address=127.0.0.1 $ARGS"
    fi
    
    # Start server in background
    log_info "Server will listen on: 127.0.0.1:$SERVER_PORT"
    log_info "Starting server: $BINARY_PATH $ARGS"
    
    $BINARY_PATH $ARGS > /var/log/aetherlink/server.log 2>&1 &
    SERVER_PID=$!
    
    # Wait for server to start
    log_info "Waiting for server to start..."
    for i in {1..15}; do
        sleep 1
        if curl -s http://127.0.0.1:$SERVER_PORT/api/status > /dev/null 2>&1; then
            log_success "Server started successfully (PID: $SERVER_PID)"
            break
        fi
        if [ $i -eq 15 ]; then
            log_error "Server failed to start within 15 seconds"
            echo "Server logs:"
            cat /var/log/aetherlink/server.log 2>/dev/null || echo "No logs available"
            exit 1
        fi
        echo -n "."
    done
    
    # Display access information
    if [ "$USE_SSL" = "true" ]; then
        log_info "nginx proxy: 80 -> 443 (HTTPS) -> 127.0.0.1:$SERVER_PORT"
        log_success "Access URL: https://$DOMAIN"
    else
        log_info "nginx proxy: 80 -> 127.0.0.1:$SERVER_PORT"
        log_success "Access URL: http://$DOMAIN"
    fi
    
    # Start nginx in foreground
    log_info "Starting nginx..."
    exec nginx -g 'daemon off;'
}

# Function to show usage help
show_help() {
    echo ""
    echo "AetherLink Universal Docker Image"
    echo "================================"
    echo ""
    echo "Environment Variables:"
    echo "  MODE=auto|ip|domain      - Operating mode (default: auto)"
    echo "  DOMAIN=example.com       - Domain name for domain mode"
    echo "  USE_SSL=auto|true|false  - Enable SSL (default: auto)"
    echo "  SERVER_PORT=8080         - Internal server port"
    echo ""
    echo "Examples:"
    echo ""
    echo "  IP-only mode:"
    echo "    docker run -p 8080:8080 -p 62322:62322 \\"
    echo "      -e AETHERLINK_AUTH_SECRET=your-secret \\"
    echo "      your-image --auth"
    echo "    Access: http://YOUR_IP:8080"
    echo ""
    echo "  Domain HTTP mode:"
    echo "    docker run -p 80:80 -p 62322:62322 \\"
    echo "      -e DOMAIN=tunnel.com -e USE_SSL=false \\"
    echo "      -e AETHERLINK_AUTH_SECRET=your-secret \\"
    echo "      your-image --domain=tunnel.com --auth"
    echo "    Access: http://tunnel.com"
    echo ""
    echo "  Domain HTTPS mode:"
    echo "    docker run -p 443:443 -p 62322:62322 \\"
    echo "      -e DOMAIN=tunnel.com -e USE_SSL=true \\"
    echo "      -e AETHERLINK_AUTH_SECRET=your-secret \\"
    echo "      your-image --domain=tunnel.com --secure=true --auth"
    echo "    Access: https://tunnel.com"
    echo ""
    echo "For more information, visit: https://github.com/hhftechnology/AetherLink"
    echo ""
}

# Function to show configuration summary
show_config_summary() {
    echo ""
    echo "📋 Configuration Summary"
    echo "======================="
    echo "Mode: $MODE"
    
    if [ "$MODE" = "domain" ]; then
        echo "Domain: $DOMAIN"
        echo "SSL: $USE_SSL"
        echo "Tunnel Port: 62322"
        if [ "$USE_SSL" = "true" ]; then
            echo "Access: https://$DOMAIN"
            echo "Ports: 443 (HTTPS), 62322 (tunnels)"
        else
            echo "Access: http://$DOMAIN"
            echo "Ports: 80 (HTTP), 62322 (tunnels)"
        fi
    else
        echo "Access: http://YOUR_IP:8080"
        echo "Ports: 8080 (HTTP), 62322 (tunnels)"
    fi
    
    echo "Binary: $BINARY_PATH"
    echo ""
}

# Handle special arguments
for arg in "$@"; do
    case $arg in
        --help|-h|help)
            show_help
            exec $BINARY_PATH --help
            ;;
        --version|-v|version)
            echo "AetherLink Universal Docker Image"
            exec $BINARY_PATH --version
            ;;
    esac
done

# Main execution flow
main() {
    # Validate configuration
    validate_config
    
    # Detect and configure mode
    detect_mode "$@"
    
    # Show configuration summary
    show_config_summary
    
    # Start appropriate mode
    if [ "$MODE" = "ip" ]; then
        start_server_only "$@"
    else
        start_server_and_nginx "$@"
    fi
}

# Trap signals for graceful shutdown
trap 'log_info "Received shutdown signal, stopping services..."; exit 0' SIGTERM SIGINT

# Run main function
main "$@"