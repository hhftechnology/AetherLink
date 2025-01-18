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

# Function to check if we're running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root. Please use sudo or run as root." >&2
        exit 1
    fi
}

# Function to detect OS and version
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS="${ID}"
        VERSION="${VERSION_ID}"
        echo "Detected OS: ${OS} ${VERSION}"
    else
        echo "Unable to detect OS. This script requires Ubuntu or Debian." >&2
        exit 1
    fi
}

# Function to install system dependencies
install_system_dependencies() {
    echo "Installing required system packages..."
    
    local packages=(
        curl
        tar
        openssl
        python3
        python3-venv
        python3-full
        python3-pip
        build-essential
        libssl-dev
        libffi-dev
        netcat
    )
    
    case "${OS}" in
        "ubuntu"|"debian")
            apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
            ;;
        *)
            echo "Unsupported operating system: ${OS}" >&2
            exit 1
            ;;
    esac
}

# Function to verify system Python setup
verify_python_setup() {
    echo "Verifying Python installation..."
    
    local min_python_version="3.7"
    local python_version
    python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    
    if ! printf '%s\n%s\n' "$min_python_version" "$python_version" | sort -C -V; then
        echo "Error: Python version $python_version is below minimum required version $min_python_version" >&2
        exit 1
    fi
    
    # Verify venv module is working
    if ! python3 -c "import venv" >/dev/null 2>&1; then
        echo "Error: Python venv module not working properly" >&2
        exit 1
    fi
}

# Function to set up logging
setup_logging() {
    mkdir -p "$(dirname "$LOGFILE")"
    exec 1> >(tee -a "$LOGFILE")
    exec 2> >(tee -a "$LOGFILE" >&2)
    echo "Installation started at $(date)"
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
        "$INSTALL_DIR/lib"
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
    if ! setcap 'cap_net_bind_service=+ep' "$INSTALL_DIR/bin/caddy"; then
        echo "Error: Failed to set capabilities for Caddy" >&2
        exit 1
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

# Function to set up Python virtual environment and install dependencies
setup_python_environment() {
    echo "Setting up Python virtual environment..."
    
    # Create virtual environment
    python3 -m venv "${INSTALL_DIR}/venv"
    
    # Activate virtual environment and install dependencies
    # shellcheck source=/dev/null
    . "${INSTALL_DIR}/venv/bin/activate"
    
    # Upgrade pip in virtual environment
    "${INSTALL_DIR}/venv/bin/pip" install --upgrade pip
    
    # Install required packages
    "${INSTALL_DIR}/venv/bin/pip" install requests urllib3 cryptography
    
    deactivate
}

# Function to install AetherLink Python script
install_aetherlink_script() {
    echo "Installing AetherLink Python script..."
    
    # Copy the Python script
    cp sirtunnel.py "${INSTALL_DIR}/bin/aetherlink.py"
    chmod 755 "${INSTALL_DIR}/bin/aetherlink.py"
    
    # Create the launcher script
    cat > "$INSTALL_DIR/bin/aetherlink" << 'EOF'
#!/bin/bash
AETHERLINK_HOME="${HOME}/.aetherlink"
export PYTHONPATH="${AETHERLINK_HOME}/lib:${PYTHONPATH:-}"
exec "${AETHERLINK_HOME}/venv/bin/python3" "${AETHERLINK_HOME}/bin/aetherlink.py" "$@"
EOF
    
    chmod 755 "$INSTALL_DIR/bin/aetherlink"
}

# Function to configure shell environment
configure_shell_environment() {
    echo "Configuring shell environment..."
    
    local shell_config
    if [[ -f "${HOME}/.zshrc" ]]; then
        shell_config="${HOME}/.zshrc"
    else
        shell_config="${HOME}/.bashrc"
    fi
    
    # Add environment variables if not already present
    if ! grep -q "AETHERLINK_HOME" "$shell_config"; then
        {
            echo
            echo "# AetherLink environment configuration"
            echo "export AETHERLINK_HOME=\"\${HOME}/.aetherlink\""
            echo "export PATH=\"\${AETHERLINK_HOME}/bin:\${PATH}\""
        } >> "$shell_config"
    fi
}

# Function to verify installation
verify_installation() {
    echo "Verifying installation..."
    
    local check_paths=(
        "$INSTALL_DIR/bin/caddy"
        "$INSTALL_DIR/bin/aetherlink"
        "$INSTALL_DIR/bin/aetherlink.py"
        "$INSTALL_DIR/config/aetherlink_config.json"
        "$INSTALL_DIR/venv/bin/python3"
    )
    
    for path in "${check_paths[@]}"; do
        if [[ ! -f "$path" ]]; then
            echo "Error: Missing required file: $path" >&2
            exit 1
        fi
    done
    
    # Verify Caddy installation
    if ! "$INSTALL_DIR/bin/caddy" version >/dev/null 2>&1; then
        echo "Error: Caddy installation verification failed" >&2
        exit 1
    fi
    
    # Verify Python environment
    if ! "${INSTALL_DIR}/venv/bin/python3" -c "import requests, urllib3, cryptography" >/dev/null 2>&1; then
        echo "Error: Python dependencies verification failed" >&2
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
    
    check_root
    detect_os
    install_system_dependencies
    verify_python_setup
    setup_logging
    create_directory_structure
    download_caddy
    configure_caddy
    setup_python_environment
    install_aetherlink_script
    configure_shell_environment
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