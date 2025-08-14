#!/bin/bash
set -e

# AetherLink Build Script
echo "Building AetherLink..."

# Check for Rust
if ! command -v cargo &> /dev/null; then
    echo "Error: Rust is not installed. Please install from https://rustup.rs/"
    exit 1
fi

# Build in release mode
echo "Compiling release build..."
cargo build --release

# Strip the binary for smaller size
if command -v strip &> /dev/null; then
    echo "Stripping binary..."
    strip target/release/aetherlink
fi

# Display build info
echo ""
echo "Build complete!"
echo "Binary location: target/release/aetherlink"
echo "Binary size: $(du -h target/release/aetherlink | cut -f1)"
echo ""
echo "To install system-wide, run:"
echo "  sudo cp target/release/aetherlink /usr/local/bin/"
echo ""
echo "To run directly:"
echo "  ./target/release/aetherlink --help"