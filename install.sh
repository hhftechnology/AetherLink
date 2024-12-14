# install.sh
#!/bin/bash
set -euo pipefail

# AetherLink Installation Script
# ----------------------------

# Configuration
CADDY_VERSION="2.8.4"
CADDY_ARCH="linux_amd64"
TEMP_DIR=$(mktemp -d)
PROJECT_DIR="$HOME/.aetherlink"

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
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

# Clean up on exit
trap 'rm -rf "$TEMP_DIR"' EXIT

# ASCII Art Banner
echo '
    ___       __  __           __    _      __  
   /   | ____/ /_/ /_  ___   / /   (_)____/ /__
  / /| |/ __  / / __ \/ _ \ / /   / / ___/ //_/
 / ___ / /_/ / / / / /  __// /___/ / /  / ,<   
/_/  |_\__,_/_/_/ /_/\___//_____/_/_/  /_/|_|  
'
echo "Installing AetherLink v${CADDY_VERSION}"
echo "--------------------------------"

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    error "Please don't run as root. Use sudo when needed."
    exit 1
fi

# Create project directory structure
log "Creating project directory structure..."
mkdir -p "${PROJECT_DIR}"/{bin,config,logs,data,certs}

# Download and verify Caddy
log "Downloading Caddy ${CADDY_VERSION}..."
CADDY_FILE="caddy_${CADDY_VERSION}_${CADDY_ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/${CADDY_FILE}"

if ! curl -sS -L --retry 3 --retry-delay 2 "$DOWNLOAD_URL" -o "$TEMP_DIR/$CADDY_FILE"; then
    error "Failed to download Caddy"
    exit 1
fi

# Extract Caddy
log "Extracting Caddy..."
if ! tar xf "$TEMP_DIR/$CADDY_FILE" -C "$TEMP_DIR"; then
    error "Failed to extract Caddy"
    exit 1
fi

# Move binary to project directory
mv "$TEMP_DIR/caddy" "${PROJECT_DIR}/bin/"

# Set capabilities
log "Setting Caddy capabilities..."
if ! sudo setcap 'cap_net_bind_service=+ep' "${PROJECT_DIR}/bin/caddy"; then
    error "Failed to set Caddy capabilities"
    exit 1
fi

# Copy configuration files
log "Setting up configuration files..."
cp config/aetherlink_config.json "${PROJECT_DIR}/config/"
cp aetherlink.py "${PROJECT_DIR}/bin/"
chmod +x "${PROJECT_DIR}/bin/aetherlink.py"

# Create symlinks
log "Creating symlinks..."
sudo ln -sf "${PROJECT_DIR}/bin/aetherlink.py" /usr/local/bin/aetherlink
sudo ln -sf "${PROJECT_DIR}/bin/caddy" /usr/local/bin/aetherlink-caddy

# Set up environment
log "Setting up environment..."
echo 'export AETHERLINK_HOME="$HOME/.aetherlink"' >> "$HOME/.bashrc"
echo 'export PATH="$AETHERLINK_HOME/bin:$PATH"' >> "$HOME/.bashrc"

success "Installation completed successfully!"
echo
echo "AetherLink has been installed to: ${PROJECT_DIR}"
echo "Configuration files are in: ${PROJECT_DIR}/config"
echo "Logs will be stored in: ${PROJECT_DIR}/logs"
echo
echo "To start using AetherLink:"
echo "1. Source your bashrc: source ~/.bashrc"
echo "2. Start the server: aetherlink-server"
echo "3. Create a tunnel: aetherlink yourdomain.com 443 --local-port 8080"
echo
echo "For more information, see the documentation in the project repository."
