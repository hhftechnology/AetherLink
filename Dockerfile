# Build stage
FROM rust:1.75-alpine AS builder

# Install build dependencies
RUN apk add --no-cache musl-dev openssl-dev pkgconfig

# Create app directory
WORKDIR /app

# Copy manifest files
COPY Cargo.toml Cargo.lock ./

# Copy source code
COPY src ./src

# Build the application
RUN cargo build --release --target x86_64-unknown-linux-musl

# Runtime stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache ca-certificates libgcc

# Create non-root user
RUN addgroup -g 1000 aetherlink && \
    adduser -D -u 1000 -G aetherlink aetherlink

# Copy binary from builder
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/aetherlink /usr/local/bin/aetherlink

# Create config directory
RUN mkdir -p /home/aetherlink/.aetherlink && \
    chown -R aetherlink:aetherlink /home/aetherlink

# Switch to non-root user
USER aetherlink
WORKDIR /home/aetherlink

# Environment variables
ENV AETHERLINK_CONFIG=/home/aetherlink/.aetherlink
ENV AETHERLINK_LOG_LEVEL=info

# Expose admin port (can be configured)
EXPOSE 2019

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD aetherlink info || exit 1

# Default command
ENTRYPOINT ["aetherlink"]
CMD ["server"]