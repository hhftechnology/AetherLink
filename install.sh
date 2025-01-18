#!/usr/bin/env bash
#
# AetherLink Installation Script
# Handles the installation of AetherLink and its dependencies with
# comprehensive error handling, security checks, and system validation.

set -euo pipefail
IFS=$'\n\t'

# Configuration variables
AETHERLINK_VERSION="2.1.1"
CADDY_VERSION="2.7.6"
INSTALL_DIR="${HOME}/.aetherlink"
LOGFILE="${INSTALL_DIR}/logs/install.log"

# Function to set up logging
setup_logging() {
    mkdir -p "$(dirname "$LOGFILE")"
    exec 1> >(tee -a "$LOGFILE")
    exec 2> >(tee -a "$LOGFILE" >&2)
    echo "Installation started at $(date)"
}

# Function to check system requirements
check_system_requirements() {
    echo "Checking system requirements..."
    
    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "Error: This installer only supports Linux systems" >&2
        exit 1
    fi
    
    local required_commands=("curl" "tar" "openssl" "python3" "pip3")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Error: Required command not found: $cmd" >&2
            echo "Please install the missing dependencies and try again" >&2
            exit 1
        fi
    done
    
    local min_python_version="3.7"
    local python_version
    python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    if ! printf '%s\n%s\n' "$min_python_version" "$python_version" | sort -C -V; then
        echo "Error: Python version $python_version is below minimum required version $min_python_version" >&2
        exit 1
    fi
}

# Function to create directory structure
create_directory_structure() {
    echo "Creating directory structure..."
    local directories=(
        "$INSTALL_DIR"
        "$INSTALL_DIR/bin"
        "$INSTALL_DIR/config"
        "$INSTALL_DIR/logs"
        "$INSTALL_DIR/certs"
        "$INSTALL_DIR/data"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        chmod 750 "$dir"
    done
}

# Function to download and verify Caddy
download_caddy() {
    echo "Downloading Caddy ${CADDY_VERSION}..."
    local caddy_url="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz"
    local download_path="/tmp/caddy.tar.gz"
    
    local max_retries=3
    local retry=0
    while [[ $retry -lt $max_retries ]]; do
        if curl -L --fail --silent --show-error "$caddy_url" -o "$download_path"; then
            break
        fi
        ((retry++))
        echo "Download failed, retrying ($retry/$max_retries)..."
        sleep 2
    done
    
    if [[ $retry -eq $max_retries ]]; then
        echo "Error: Failed to download Caddy after $max_retries attempts" >&2
        exit 1
    fi
    
    # Extract Caddy
    tar xzf "$download_path" -C "$INSTALL_DIR/bin" caddy
    rm -f "$download_path"
    chmod 755 "$INSTALL_DIR/bin/caddy"
}

# Function to configure Caddy
configure_caddy() {
    echo "Configuring Caddy..."
    
    # Set up Caddy to bind to privileged ports
    if ! sudo setcap 'cap_net_bind_service=+ep' "$INSTALL_DIR/bin/caddy"; then
        echo "Warning: Failed to set capabilities for Caddy. You may need to run with sudo for ports < 1024"
    fi
    
    # Create default configuration
    cat > "$INSTALL_DIR/config/aetherlink_config.json" << 'EOF'
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
EOF
}

# Function to install Python dependencies
install_python_dependencies() {
    echo "Installing Python dependencies..."
    pip3 install --user --upgrade pip
    pip3 install --user requests urllib3 cryptography
}

# Function to create command line tools
create_cli_tools() {
    echo "Creating command line tools..."
    
    cat > "$INSTALL_DIR/bin/aetherlink" << 'EOF'
#!/bin/bash
AETHERLINK_HOME="${HOME}/.aetherlink"
export PYTHONPATH="${AETHERLINK_HOME}/lib:${PYTHONPATH:-}"
exec python3 "${AETHERLINK_HOME}/bin/aetherlink.py" "$@"
EOF
    
    chmod 755 "$INSTALL_DIR/bin/aetherlink"
    
    local rc_file="${HOME}/.bashrc"
    [[ -f "${HOME}/.zshrc" ]] && rc_file="${HOME}/.zshrc"
    
    if ! grep -q "AETHERLINK_HOME" "$rc_file"; then
        {
            echo "export AETHERLINK_HOME=\"\${HOME}/.aetherlink\""
            echo "export PATH=\"\${AETHERLINK_HOME}/bin:\${PATH}\""
        } >> "$rc_file"
    fi
}

# Function to verify installation
verify_installation() {
    echo "Verifying installation..."
    
    local check_paths=(
        "$INSTALL_DIR/bin/caddy"
        "$INSTALL_DIR/bin/aetherlink"
        "$INSTALL_DIR/config/aetherlink_config.json"
    )
    
    for path in "${check_paths[@]}"; do
        if [[ ! -f "$path" ]]; then
            echo "Error: Missing required file: $path" >&2
            exit 1
        fi
    done
    
    if ! "$INSTALL_DIR/bin/caddy" version >/dev/null 2>&1; then
        echo "Error: Caddy installation verification failed" >&2
        exit 1
    fi
}

# Function to clean up temporary files
cleanup() {
    echo "Cleaning up temporary files..."
    rm -f /tmp/caddy.tar.gz
}

# Main installation process
main() {
    echo "Starting AetherLink installation..."
    
    setup_logging
    check_system_requirements
    create_directory_structure
    download_caddy
    configure_caddy
    install_python_dependencies
    create_cli_tools
    verify_installation
    cleanup
    
    echo "AetherLink installation completed successfully!"
    echo "Please source your shell configuration file or restart your terminal"
    echo "to use the 'aetherlink' command."
}

# Error handling
trap 'echo "Installation failed. Check the log at $LOGFILE for details."; exit 1' ERR

# Run installation
main "$@"