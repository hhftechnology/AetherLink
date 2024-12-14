#!/bin/sh
# Using sh for maximum compatibility

# Strict mode
set -e

# Configuration
CADDY_VERSION="2.8.4"
CADDY_ARCH="linux_amd64"
TEMP_DIR=$(mktemp -d)
PROJECT_DIR="$HOME/.aetherlink"

# Color output (if supported)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    BLUE=''
    NC=''
fi

# Logging functions
log() {
    printf "${BLUE}[%s] %s${NC}\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1"
}

error() {
    printf "${RED}[ERROR] %s${NC}\n" "$1"
    exit 1
}

success() {
    printf "${GREEN}[SUCCESS] %s${NC}\n" "$1"
}

# Clean up on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Check if running as root (POSIX-compliant way)
if [ "$(id -u)" = "0" ]; then 
    error "Please don't run as root. Use sudo when needed."
fi

# ASCII Art Banner
cat << 'EOF'
    ___       __  __           __    _      __  
   /   | ____/ /_/ /_  ___   / /   (_)____/ /__
  / /| |/ __  / / __ \/ _ \ / /   / / ___/ //_/
 / ___ / /_/ / / / / /  __// /___/ / /  / ,<   
/_/  |_\__,_/_/_/ /_/\___//_____/_/_/  /_/|_|  
EOF
echo "Installing AetherLink v${CADDY_VERSION}"
echo "--------------------------------"

# Create project directory structure
log "Creating project directory structure..."
mkdir -p "${PROJECT_DIR}/bin" "${PROJECT_DIR}/config" "${PROJECT_DIR}/logs" "${PROJECT_DIR}/data" "${PROJECT_DIR}/certs"

# Check for required commands
for cmd in curl tar sudo; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "$cmd is required but not installed. Please install $cmd first."
    fi
done

# Download and verify Caddy
log "Downloading Caddy ${CADDY_VERSION}..."
CADDY_FILE="caddy_${CADDY_VERSION}_${CADDY_ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/${CADDY_FILE}"

if ! curl -sS -L --retry 3 --retry-delay 2 "$DOWNLOAD_URL" -o "$TEMP_DIR/$CADDY_FILE"; then
    error "Failed to download Caddy"
fi

# Extract Caddy
log "Extracting Caddy..."
if ! tar xf "$TEMP_DIR/$CADDY_FILE" -C "$TEMP_DIR"; then
    error "Failed to extract Caddy"
fi

# Move binary to project directory
mv "$TEMP_DIR/caddy" "${PROJECT_DIR}/bin/"

# Set capabilities
log "Setting Caddy capabilities..."
if ! sudo setcap 'cap_net_bind_service=+ep' "${PROJECT_DIR}/bin/caddy"; then
    error "Failed to set Caddy capabilities"
fi

# Copy configuration files
log "Setting up configuration files..."
if [ -f "config/aetherlink_config.json" ]; then
    cp config/aetherlink_config.json "${PROJECT_DIR}/config/"
else
    error "Configuration file config/aetherlink_config.json not found"
fi

if [ -f "aetherlink.py" ]; then
    cp aetherlink.py "${PROJECT_DIR}/bin/"
    chmod +x "${PROJECT_DIR}/bin/aetherlink.py"
else
    error "aetherlink.py not found"
fi

# Create symlinks
log "Creating symlinks..."
if ! sudo ln -sf "${PROJECT_DIR}/bin/aetherlink.py" /usr/local/bin/aetherlink; then
    error "Failed to create symlink for aetherlink"
fi

if ! sudo ln -sf "${PROJECT_DIR}/bin/caddy" /usr/local/bin/aetherlink-caddy; then
    error "Failed to create symlink for aetherlink-caddy"
fi

# Set up environment
log "Setting up environment..."
BASHRC="$HOME/.bashrc"
if [ -f "$BASHRC" ]; then
    # Only add if not already present
    if ! grep -q "AETHERLINK_HOME" "$BASHRC"; then
        printf '\n# AetherLink Environment\n' >> "$BASHRC"
        printf 'export AETHERLINK_HOME="%s"\n' "$HOME/.aetherlink" >> "$BASHRC"
        printf 'export PATH="$AETHERLINK_HOME/bin:$PATH"\n' >> "$BASHRC"
    fi
else
    log "Warning: ~/.bashrc not found, skipping environment setup"
fi

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
echo "For more information, see the documentation in the https://github.com/hhftechnology/AetherLink repository."
