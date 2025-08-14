#!/bin/bash

# AetherLink Automated Setup Script
# This script automates the installation and initial setup of AetherLink

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.aetherlink"
GITHUB_REPO="hhftechnology/AetherLink"

# Functions
print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                 AetherLink Setup Script                  ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        if [[ $(uname -m) == "x86_64" ]]; then
            ARCH="amd64"
        elif [[ $(uname -m) == "aarch64" ]]; then
            ARCH="arm64"
        else
            ARCH="unknown"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        if [[ $(uname -m) == "x86_64" ]]; then
            ARCH="amd64"
        elif [[ $(uname -m) == "arm64" ]]; then
            ARCH="arm64"
        else
            ARCH="unknown"
        fi
    else
        OS="unknown"
        ARCH="unknown"
    fi
}

install_from_binary() {
    print_info "Downloading AetherLink binary for $OS-$ARCH..."
    
    # Construct download URL
    local BINARY_NAME="aetherlink-$OS-$ARCH"
    local DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/latest/download/$BINARY_NAME"
    
    # Create install directory
    mkdir -p "$INSTALL_DIR"
    
    # Download binary
    if command -v wget &> /dev/null; then
        wget -q --show-progress -O "$INSTALL_DIR/aetherlink" "$DOWNLOAD_URL"
    elif command -v curl &> /dev/null; then
        curl -L --progress-bar -o "$INSTALL_DIR/aetherlink" "$DOWNLOAD_URL"
    else
        print_error "Neither wget nor curl found. Please install one."
        exit 1
    fi
    
    # Make executable
    chmod +x "$INSTALL_DIR/aetherlink"
    print_success "AetherLink binary installed to $INSTALL_DIR/aetherlink"
}

install_from_cargo() {
    print_info "Installing AetherLink using Cargo..."
    
    # Check if Rust is installed
    if ! command -v cargo &> /dev/null; then
        print_info "Rust not found. Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    
    # Install AetherLink
    cargo install aetherlink
    print_success "AetherLink installed via Cargo"
}

install_from_source() {
    print_info "Building AetherLink from source..."
    
    # Check dependencies
    if ! command -v git &> /dev/null; then
        print_error "Git is required to build from source"
        exit 1
    fi
    
    if ! command -v cargo &> /dev/null; then
        print_info "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    
    # Clone and build
    local TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    git clone "https://github.com/$GITHUB_REPO.git"
    cd AetherLink
    cargo build --release
    
    # Install
    mkdir -p "$INSTALL_DIR"
    cp target/release/aetherlink "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/aetherlink"
    
    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
    
    print_success "AetherLink built and installed from source"
}

setup_path() {
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        print_info "Adding $INSTALL_DIR to PATH..."
        
        # Detect shell and update appropriate config file
        if [[ -f "$HOME/.zshrc" ]]; then
            echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$HOME/.zshrc"
            print_info "Added to ~/.zshrc"
        fi
        
        if [[ -f "$HOME/.bashrc" ]]; then
            echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$HOME/.bashrc"
            print_info "Added to ~/.bashrc"
        fi
        
        # Export for current session
        export PATH="$INSTALL_DIR:$PATH"
    fi
}

initialize_aetherlink() {
    print_info "Initializing AetherLink..."
    
    # Check if already initialized
    if [[ -f "$CONFIG_DIR/config.toml" ]]; then
        print_info "AetherLink already initialized"
    else
        "$INSTALL_DIR/aetherlink" init
        print_success "AetherLink initialized"
    fi
    
    # Get and display Node ID
    NODE_ID=$("$INSTALL_DIR/aetherlink" info | grep "Node ID" | cut -d' ' -f3)
    echo
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Your Node ID: ${YELLOW}$NODE_ID${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
}

setup_server() {
    print_info "Setting up as server..."
    
    # Create systemd service (if on Linux)
    if [[ "$OS" == "linux" ]] && command -v systemctl &> /dev/null; then
        print_info "Would you like to install as a systemd service? (y/n)"
        read -r response
        if [[ "$response" == "y" ]]; then
            create_systemd_service
        fi
    fi
    
    print_success "Server setup complete!"
    echo
    echo "To start the server manually, run:"
    echo "  aetherlink server"
    echo
    echo "To authorize clients, run:"
    echo "  aetherlink authorize <client-node-id>"
}

setup_client() {
    print_info "Setting up as client..."
    
    echo -e "${YELLOW}Enter your server's Node ID:${NC}"
    read -r SERVER_ID
    
    echo -e "${YELLOW}Enter a name for this server (e.g., 'myserver'):${NC}"
    read -r SERVER_NAME
    
    "$INSTALL_DIR/aetherlink" add-server "$SERVER_NAME" "$SERVER_ID"
    print_success "Server '$SERVER_NAME' added"
    
    echo
    echo "Your client Node ID is: $NODE_ID"
    echo "Give this to your server administrator to authorize your connection."
    echo
    echo "Once authorized, create a tunnel with:"
    echo "  aetherlink tunnel <domain> --local-port <port> --server $SERVER_NAME"
}

create_systemd_service() {
    local SERVICE_FILE="/etc/systemd/system/aetherlink.service"
    
    print_info "Creating systemd service..."
    
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=AetherLink Tunnel Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
Environment="AETHERLINK_CONFIG=$CONFIG_DIR"
ExecStart=$INSTALL_DIR/aetherlink server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    print_success "Systemd service created"
    
    echo "To start the service:"
    echo "  sudo systemctl start aetherlink"
    echo "  sudo systemctl enable aetherlink  # Start on boot"
}

# Main installation flow
main() {
    print_header
    
    # Detect OS and architecture
    detect_os
    
    if [[ "$OS" == "unknown" ]] || [[ "$ARCH" == "unknown" ]]; then
        print_error "Unsupported OS or architecture: $OSTYPE $(uname -m)"
        print_info "Falling back to building from source..."
        INSTALL_METHOD="source"
    else
        # Choose installation method
        echo "Choose installation method:"
        echo "1) Download pre-built binary (recommended)"
        echo "2) Install with Cargo"
        echo "3) Build from source"
        echo
        echo -n "Enter choice (1-3): "
        read -r choice
        
        case $choice in
            1) INSTALL_METHOD="binary";;
            2) INSTALL_METHOD="cargo";;
            3) INSTALL_METHOD="source";;
            *) INSTALL_METHOD="binary";;
        esac
    fi
    
    # Install AetherLink
    case $INSTALL_METHOD in
        binary) install_from_binary;;
        cargo) install_from_cargo;;
        source) install_from_source;;
    esac
    
    # Setup PATH
    setup_path
    
    # Initialize
    initialize_aetherlink
    
    # Ask for role
    echo
    echo "How will you use AetherLink?"
    echo "1) As a server (accept incoming tunnels)"
    echo "2) As a client (create tunnels to a server)"
    echo "3) Both"
    echo
    echo -n "Enter choice (1-3): "
    read -r role_choice
    
    case $role_choice in
        1) setup_server;;
        2) setup_client;;
        3) 
            setup_server
            setup_client
            ;;
        *) ;;
    esac
    
    # Final message
    echo
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}          AetherLink Installation Complete!               ${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo
    echo "Quick command reference:"
    echo "  aetherlink --help                    # Show help"
    echo "  aetherlink info                      # Show your Node ID"
    echo "  aetherlink server                    # Start server"
    echo "  aetherlink tunnel <domain> --local-port <port> --server <n>"
    echo
    echo "For more information, see:"
    echo "  https://github.com/$GITHUB_REPO"
    echo
    print_info "Restart your terminal or run: source ~/.bashrc"
}

# Run main function
main "$@"