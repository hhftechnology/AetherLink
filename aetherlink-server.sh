# aetherlink-server.sh
#!/usr/bin/env bash
set -euo pipefail

# AetherLink Server Runner
# ----------------------

# Configuration
AETHERLINK_HOME="${AETHERLINK_HOME:-$HOME/.aetherlink}"
CONFIG_FILE="${AETHERLINK_HOME}/config/aetherlink_config.json"
LOG_FILE="${AETHERLINK_HOME}/logs/server.log"
PID_FILE="${AETHERLINK_HOME}/aetherlink.pid"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# ASCII Art Banner
echo '
    ___       __  __           __    _      __  
   /   | ____/ /_/ /_  ___   / /   (_)____/ /__
  / /| |/ __  / / __ \/ _ \ / /   / / ___/ //_/
 / ___ / /_/ / / / / /  __// /___/ / /  / ,<   
/_/  |_\__,_/_/_/ /_/\___//_____/_/_/  /_/|_|  
                  Server
'

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    error "Config file $CONFIG_FILE not found"
fi

# Validate JSON config
if ! command -v jq &> /dev/null; then
    log "Installing jq for JSON validation..."
    sudo apt-get update && sudo apt-get install -y jq
fi

if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    error "Invalid JSON in config file"
fi

# Check if already running
if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        error "AetherLink server is already running (PID: $pid)"
    else
        log "Removing stale PID file"
        rm "$PID_FILE"
    fi
fi

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

log "Starting AetherLink server..."
log "Configuration: $CONFIG_FILE"
log "Log file: $LOG_FILE"

# Run Caddy with logging and monitoring
"${AETHERLINK_HOME}/bin/caddy" run \
    --config "$CONFIG_FILE" \
    --pidfile "$PID_FILE" 2>&1 | tee -a "$LOG_FILE"
