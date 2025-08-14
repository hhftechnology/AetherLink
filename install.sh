#!/bin/bash
set -e

# AetherLink Installation Script
echo "AetherLink Installer"
echo "==================="

# Check if running as root for system install
if [ "$EUID" -eq 0 ]; then 
    INSTALL_MODE="system"
    BIN_DIR="/usr/local/bin"
    CONFIG_DIR="/etc/aetherlink"
    SERVICE_DIR="/etc/systemd/system"
    USER="aetherlink"
else
    INSTALL_MODE="user"
    BIN_DIR="$HOME/.local/bin"
    CONFIG_DIR="$HOME/.aetherlink"
    SERVICE_DIR="$HOME/.config/systemd/user"
    USER="$USER"
fi

echo "Installation mode: $INSTALL_MODE"
echo ""

# Check for Rust
if ! command -v cargo &> /dev/null; then
    echo "Rust is not installed. Would you like to install it? (y/n)"
    read -r response
    if [ "$response" = "y" ]; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        source "$HOME/.cargo/env"
    else
        echo "Please install Rust from https://rustup.rs/ and run this script again."
        exit 1
    fi
fi

# Build AetherLink
echo "Building AetherLink..."
cargo build --release

# Create directories
echo "Creating directories..."
mkdir -p "$BIN_DIR"
mkdir -p "$CONFIG_DIR"

# Install binary
echo "Installing binary to $BIN_DIR..."
cp target/release/aetherlink "$BIN_DIR/"
chmod +x "$BIN_DIR/aetherlink"

# Create system user if installing system-wide
if [ "$INSTALL_MODE" = "system" ]; then
    if ! id -u aetherlink >/dev/null 2>&1; then
        echo "Creating aetherlink user..."
        useradd -r -s /bin/false -d /var/lib/aetherlink -m aetherlink
    fi
    
    # Set permissions
    chown -R aetherlink:aetherlink "$CONFIG_DIR"
    
    # Install systemd service
    if [ -f aetherlink.service ]; then
        echo "Installing systemd service..."
        mkdir -p "$SERVICE_DIR"
        cp aetherlink.service "$SERVICE_DIR/"
        systemctl daemon-reload
        echo ""
        echo "To start the service, run:"
        echo "  sudo systemctl start aetherlink"
        echo "  sudo systemctl enable aetherlink  # To start on boot"
    fi
fi

# Initialize configuration
echo ""
echo "Initializing AetherLink..."
"$BIN_DIR/aetherlink" init || true

# Add to PATH if needed
if [ "$INSTALL_MODE" = "user" ]; then
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        echo ""
        echo "Adding $BIN_DIR to PATH..."
        echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$HOME/.bashrc"
        echo "Please run: source ~/.bashrc"
    fi
fi

# Display completion message
echo ""
echo "✓ AetherLink installed successfully!"
echo ""
echo "Configuration directory: $CONFIG_DIR"
echo "Binary location: $BIN_DIR/aetherlink"
echo ""
echo "Next steps:"
echo "1. Get your Node ID: aetherlink info"
echo "2. Start server: aetherlink server"
echo "3. Create tunnel: aetherlink tunnel <domain> --local-port <port>"
echo ""
echo "For more information, see: https://github.com/hhftechnology/AetherLink"