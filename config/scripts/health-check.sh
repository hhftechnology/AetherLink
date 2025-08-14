#!/bin/bash

# AetherLink Health Check Script
# Tests both IP-only and domain modes

set -e

# Configuration
TIMEOUT=5
RETRY_COUNT=3
VERBOSE="${HEALTH_CHECK_VERBOSE:-false}"

# Color codes for output (only if verbose)
if [ "$VERBOSE" = "true" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

log_verbose() {
    if [ "$VERBOSE" = "true" ]; then
        echo -e "$1" >&2
    fi
}

# Function to check HTTP endpoint
check_endpoint() {
    local url="$1"
    local name="$2"
    local extra_args="$3"
    
    log_verbose "${YELLOW}Checking $name: $url${NC}"
    
    if curl -f -s --max-time $TIMEOUT $extra_args "$url" > /dev/null 2>&1; then
        log_verbose "${GREEN}✅ $name health check passed${NC}"
        return 0
    else
        log_verbose "${RED}❌ $name health check failed${NC}"
        return 1
    fi
}

# Function to check if server is responding with valid JSON
check_api_status() {
    local url="$1"
    local name="$2"
    local extra_args="$3"
    
    log_verbose "${YELLOW}Checking $name API status: $url${NC}"
    
    local response
    response=$(curl -f -s --max-time $TIMEOUT $extra_args "$url" 2>/dev/null)
    
    if [ $? -eq 0 ] && echo "$response" | grep -q '"tunnels"'; then
        log_verbose "${GREEN}✅ $name API status check passed${NC}"
        log_verbose "Response: $response"
        return 0
    else
        log_verbose "${RED}❌ $name API status check failed${NC}"
        log_verbose "Response: $response"
        return 1
    fi
}

# Function to perform health check with retries
health_check_with_retry() {
    for attempt in $(seq 1 $RETRY_COUNT); do
        log_verbose "${YELLOW}Health check attempt $attempt/$RETRY_COUNT${NC}"
        
        # Check IP mode (direct server access)
        if check_api_status "http://localhost:8080/api/status" "IP mode"; then
            log_verbose "${GREEN}✅ Health check passed (IP mode)${NC}"
            exit 0
        fi
        
        # Check domain mode HTTP (nginx proxy)
        if check_api_status "http://localhost/api/status" "Domain HTTP mode"; then
            log_verbose "${GREEN}✅ Health check passed (Domain HTTP mode)${NC}"
            exit 0
        fi
        
        # Check domain mode HTTPS (nginx proxy with SSL)
        if check_api_status "https://localhost/api/status" "Domain HTTPS mode" "-k"; then
            log_verbose "${GREEN}✅ Health check passed (Domain HTTPS mode)${NC}"
            exit 0
        fi
        
        # Check nginx health endpoint
        if check_endpoint "http://localhost/nginx-health" "nginx health"; then
            log_verbose "${GREEN}✅ nginx health check passed${NC}"
            # If nginx is healthy but API isn't, check server logs
            if [ -f "/var/log/aetherlink/server.log" ]; then
                log_verbose "${YELLOW}nginx healthy but API unavailable, checking server logs:${NC}"
                tail -n 5 /var/log/aetherlink/server.log >&2 2>/dev/null || true
            fi
            # Don't exit 0 here - nginx healthy doesn't mean the app is healthy
        fi
        
        if [ $attempt -lt $RETRY_COUNT ]; then
            log_verbose "${YELLOW}Retrying in 2 seconds...${NC}"
            sleep 2
        fi
    done
    
    log_verbose "${RED}❌ All health check attempts failed${NC}"
    exit 1
}

# Function to check specific components for debugging
debug_checks() {
    if [ "$VERBOSE" = "true" ]; then
        echo -e "${YELLOW}=== Debug Information ===${NC}" >&2
        
        # Check if processes are running
        echo "Running processes:" >&2
        ps aux | grep -E "(aetherlink|nginx)" | grep -v grep >&2 2>/dev/null || echo "No aetherlink/nginx processes found" >&2
        
        # Check listening ports
        echo "Listening ports:" >&2
        netstat -tlnp 2>/dev/null | grep -E ":80|:443|:8080|:62322" >&2 || echo "No relevant ports listening" >&2
        
        # Check nginx status
        if command -v nginx >/dev/null 2>&1; then
            echo "nginx configuration test:" >&2
            nginx -t >&2 2>&1 || echo "nginx config test failed" >&2
        fi
        
        # Check log files
        echo "Log files:" >&2
        ls -la /var/log/aetherlink/ >&2 2>/dev/null || echo "No aetherlink logs" >&2
        ls -la /var/log/nginx/ >&2 2>/dev/null || echo "No nginx logs" >&2
        
        echo -e "${YELLOW}=========================${NC}" >&2
    fi
}

# Main health check function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --timeout|-t)
                TIMEOUT="$2"
                shift 2
                ;;
            --retries|-r)
                RETRY_COUNT="$2"
                shift 2
                ;;
            --debug|-d)
                VERBOSE=true
                debug_checks
                shift
                ;;
            --help|-h)
                echo "AetherLink Health Check Script"
                echo ""
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --verbose, -v     Enable verbose output"
                echo "  --timeout, -t     Request timeout in seconds (default: 5)"
                echo "  --retries, -r     Number of retry attempts (default: 3)"
                echo "  --debug, -d       Show debug information"
                echo "  --help, -h        Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  HEALTH_CHECK_VERBOSE=true    Enable verbose output"
                echo ""
                echo "Exit Codes:"
                echo "  0    Health check passed"
                echo "  1    Health check failed"
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done
    
    log_verbose "${YELLOW}Starting AetherLink health check...${NC}"
    
    # Perform health check
    health_check_with_retry
}

# Run main function with all arguments
main "$@"