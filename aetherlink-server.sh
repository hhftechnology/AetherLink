#!/bin/bash
set -euo pipefail

# Configuration
AETHERLINK_HOME="${AETHERLINK_HOME:-/opt/aetherlink}"
CONFIG_FILE="${AETHERLINK_HOME}/config/aetherlink_config.json"
LOG_FILE="${AETHERLINK_HOME}/logs/server.log"
PID_FILE="${AETHERLINK_HOME}/aetherlink.pid"

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file $CONFIG_FILE not found"
    exit 1
fi

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

echo "Starting AetherLink server..."
echo "Configuration: $CONFIG_FILE"
echo "Log file: $LOG_FILE"

# Run Caddy with logging
exec "${AETHERLINK_HOME}/bin/caddy" run \
    --config "$CONFIG_FILE" \
    --pidfile "$PID_FILE" 2>&1 | tee -a "$LOG_FILE"