.PHONY: help build release test clean install docker docker-build docker-push run-server run-client fmt clippy

# Default target
help:
	@echo "AetherLink Development Makefile"
	@echo "==============================="
	@echo ""
	@echo "Available targets:"
	@echo "  make build        - Build debug version"
	@echo "  make release      - Build release version"
	@echo "  make test         - Run tests"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make install      - Install locally"
	@echo "  make docker       - Build Docker image"
	@echo "  make fmt          - Format code"
	@echo "  make clippy       - Run clippy linter"
	@echo "  make run-server   - Run server locally"
	@echo "  make run-client   - Run example client"

# Build debug version
build:
	cargo build

# Build release version
release:
	cargo build --release
	@echo "Binary size: $$(du -h target/release/aetherlink | cut -f1)"

# Run tests
test:
	cargo test --verbose

# Clean build artifacts
clean:
	cargo clean
	rm -rf ~/.aetherlink/logs/*

# Install locally
install: release
	@mkdir -p ~/.local/bin
	@cp target/release/aetherlink ~/.local/bin/
	@echo "Installed to ~/.local/bin/aetherlink"
	@echo "Make sure ~/.local/bin is in your PATH"

# Build Docker image
docker:
	docker build -t aetherlink:latest .

# Build and push Docker image
docker-push: docker
	docker tag aetherlink:latest ghcr.io/hhftechnology/aetherlink:latest
	docker push ghcr.io/hhftechnology/aetherlink:latest

# Run server locally
run-server:
	cargo run -- server

# Run example client
run-client:
	cargo run -- tunnel example.local --local-port 3000

# Format code
fmt:
	cargo fmt

# Run clippy
clippy:
	cargo clippy -- -D warnings

# Development setup
dev-setup:
	rustup component add rustfmt clippy
	cargo install cargo-watch
	@echo "Development environment ready!"

# Watch for changes and rebuild
watch:
	cargo watch -x build -x test

# Generate documentation
docs:
	cargo doc --no-deps --open

# Check everything before commit
pre-commit: fmt clippy test
	@echo "✓ All checks passed!"