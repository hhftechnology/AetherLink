#!/bin/bash

# AetherLink Server Runner
# This script manages the AetherLink server process with proper error handling,
# logging, and process management.

set -euo pipefail

# Configuration
AETHERLINK_HOME="${AETHERLINK_HOME:-${HOME}/.aetherlink}"
CONFIG_FILE="${AETHERLINK_HOME}/config/aetherlink_config.json"
LOG_DIR="${AETHERLINK_HOME}/logs"
PID_FILE="${AETHERLINK_HOME}/aetherlink.pid"
CADDY_BIN="./caddy"

# Logging configuration
LOG_FILE="${LOG_DIR}/server.log"
ERROR_LOG="${LOG_DIR}/error.log"

# Ensure required directories exist
setup_directories() {
    local dirs=("${LOG_DIR}" "${AETHERLINK_HOME}/config" "${AETHERLINK_HOME}/certs")
    for dir in "${dirs[@]}"; do
        if ! mkdir -p "${dir}"; then
            echo "Error: Failed to create directory: ${dir}" >&2
            exit 1
        fi
    done
}

# Validate configuration file
validate_config() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "Error: Configuration file not found: ${CONFIG_FILE}" >&2
        exit 1
    fi

    if ! "${CADDY_BIN}" validate --config "${CONFIG_FILE}" > /dev/null 2>&1; then
        echo "Error: Invalid configuration file" >&2
        exit 1
    fi
}

# Check if required binaries are available
check_requirements() {
    if [ ! -x "${CADDY_BIN}" ]; then
        echo "Error: Caddy binary not found or not executable: ${CADDY_BIN}" >&2
        exit 1
    fi
}

# Check if server is already running
check_running() {
    if [ -f "${PID_FILE}" ]; then
        local pid
        pid=$(cat "${PID_FILE}")
        if kill -0 "${pid}" 2>/dev/null; then
            echo "Error: Server is already running with PID ${pid}" >&2
            exit 1
        else
            rm -f "${PID_FILE}"
        fi
    fi
}

# Setup signal handlers
setup_signal_handlers() {
    trap cleanup SIGTERM SIGINT
}

# Cleanup function
cleanup() {
    echo "Shutting down AetherLink server..."
    if [ -f "${PID_FILE}" ]; then
        local pid
        pid=$(cat "${PID_FILE}")
        kill "${pid}" 2>/dev/null || true
        rm -f "${PID_FILE}"
    fi
    exit 0
}

# Start the server
start_server() {
    echo "Starting AetherLink server..."
    
    # Start Caddy in background
    "${CADDY_BIN}" run --config "${CONFIG_FILE}" \
        --adapter caddyfile \
        --pidfile "${PID_FILE}" >> "${LOG_FILE}" 2>> "${ERROR_LOG}" &
    
    local pid=$!
    echo "${pid}" > "${PID_FILE}"
    
    # Wait for server to start
    local retries=0
    local max_retries=30
    local started=false
    
    while [ ${retries} -lt ${max_retries} ]; do
        if curl -s -o /dev/null http://localhost:2019/config/; then
            started=true
            break
        fi
        sleep 1
        ((retries++))
    done
    
    if [ "${started}" = true ]; then
        echo "AetherLink server started successfully (PID: ${pid})"
        echo "Log file: ${LOG_FILE}"
        echo "Error log: ${ERROR_LOG}"
    else
        echo "Error: Failed to start server after ${max_retries} seconds" >&2
        cleanup
        exit 1
    fi
}

# Monitor server health
monitor_server() {
    local pid
    pid=$(cat "${PID_FILE}")
    
    while true; do
        if ! kill -0 "${pid}" 2>/dev/null; then
            echo "Error: Server process died unexpectedly" >&2
            cleanup
            exit 1
        fi
        
        if ! curl -s -o /dev/null http://localhost:2019/config/; then
            echo "Warning: Server health check failed" >&2
            # Log the failure but don't exit - let the process try to recover
        fi
        
        sleep 30
    done
}

main() {
    # Setup
    setup_directories
    check_requirements
    validate_config
    check_running
    setup_signal_handlers
    
    # Start and monitor
    start_server
    monitor_server
}

main "$@"