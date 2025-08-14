# AetherLink Deployment Scenarios

This guide provides detailed deployment scenarios for both server and client configurations across different environments and use cases.

## Table of Contents

- [Server Deployment](#server-deployment)
- [Client Usage Scenarios](#client-usage-scenarios)
- [Production Deployments](#production-deployments)
- [Development Team Setups](#development-team-setups)
- [Cloud Platform Deployments](#cloud-platform-deployments)
- [Monitoring and Maintenance](#monitoring-and-maintenance)

## Server Deployment

### Basic VPS Deployment

Deploy AetherLink server on a Virtual Private Server (Ubuntu 20.04+):

```bash
# 1. Update system and install dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget unzip

# 2. Download AetherLink server binary
wget https://github.com/hhftechnology/AetherLink/releases/latest/download/aetherlink-server-linux-amd64
chmod +x aetherlink-server-linux-amd64
sudo mv aetherlink-server-linux-amd64 /usr/local/bin/aetherlink-server

# 3. Create systemd service
sudo tee /etc/systemd/system/aetherlink.service << EOF
[Unit]
Description=AetherLink Tunnel Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=www-data
Group=www-data
ExecStart=/usr/local/bin/aetherlink-server --address=0.0.0.0 --port=8080 --domain=tunnel.yourdomain.com --secure=true
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 4. Start and enable service
sudo systemctl daemon-reload
sudo systemctl enable aetherlink
sudo systemctl start aetherlink

# 5. Check status
sudo systemctl status aetherlink
```

### Docker Server Deployment

```bash
# 1. Create docker-compose.yml
cat > docker-compose.yml << EOF
services:
  aetherlink-server:
    image: hhftechnology/aetherlink-server:latest
    container_name: aetherlink-server
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "62322:62322"  # Tunnel port
    command: [
      "--address=0.0.0.0",
      "--port=8080", 
      "--domain=tunnel.yourdomain.com",
      "--secure=true"
    ]
    environment:
      - TZ=UTC
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/status"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Optional: Add reverse proxy for HTTPS termination
  nginx:
    image: nginx:alpine
    container_name: aetherlink-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - aetherlink-server
EOF

# 2. Deploy
docker-compose up -d

# 3. Monitor logs
docker-compose logs -f aetherlink-server
```

### Kubernetes Deployment

```yaml
# aetherlink-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aetherlink-server
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aetherlink-server
  template:
    metadata:
      labels:
        app: aetherlink-server
    spec:
      containers:
      - name: aetherlink-server
        image: hhftechnology/aetherlink-server:latest
        args:
          - "--address=0.0.0.0"
          - "--port=8080"
          - "--domain=tunnel.yourdomain.com"
          - "--secure=true"
        ports:
        - containerPort: 8080
        - containerPort: 62322
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /api/status
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/status
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: aetherlink-service
spec:
  selector:
    app: aetherlink-server
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: tunnel
      port: 62322
      targetPort: 62322
  type: LoadBalancer
```

## Client Usage Scenarios

### Local Development Environment

**Scenario 1: Single Service Development**

```bash
# Start your local development server
npm run dev  # React app on port 3000

# In another terminal, create tunnel
./aetherlink-client --server=https://tunnel.yourdomain.com --port=3000 --subdomain=dev-myapp

# Access your app at: https://dev-myapp.tunnel.yourdomain.com
```

**Scenario 2: Full-Stack Development**

```bash
# Terminal 1: Backend API
./aetherlink-client --server=https://tunnel.yourdomain.com --port=8080 --subdomain=api-dev

# Terminal 2: Frontend App
./aetherlink-client --server=https://tunnel.yourdomain.com --port=3000 --subdomain=app-dev

# Terminal 3: Database Admin Interface
./aetherlink-client --server=https://tunnel.yourdomain.com --port=5555 --subdomain=db-dev
```

### Team Development Setup

Create convenience scripts for team members:

```bash
# create-dev-scripts.sh
#!/bin/bash

USER=$(whoami)
DOMAIN="tunnel.yourdomain.com"

mkdir -p ~/aetherlink-scripts

# Frontend tunnel script
cat > ~/aetherlink-scripts/frontend.sh << EOF
#!/bin/bash
echo "Starting frontend tunnel for $USER..."
./aetherlink-client --server=https://$DOMAIN --port=3000 --subdomain=frontend-$USER
EOF

# Backend tunnel script
cat > ~/aetherlink-scripts/backend.sh << EOF
#!/bin/bash
echo "Starting backend tunnel for $USER..."
./aetherlink-client --server=https://$DOMAIN --port=8080 --subdomain=api-$USER
EOF

# Database tunnel script
cat > ~/aetherlink-scripts/database.sh << EOF
#!/bin/bash
echo "Starting database tunnel for $USER..."
./aetherlink-client --server=https://$DOMAIN --port=5432 --subdomain=db-$USER
EOF

chmod +x ~/aetherlink-scripts/*.sh

echo "Scripts created in ~/aetherlink-scripts/"
echo "Frontend: https://frontend-$USER.$DOMAIN"
echo "Backend:  https://api-$USER.$DOMAIN"
echo "Database: https://db-$USER.$DOMAIN"
```

### CI/CD Integration

**GitHub Actions Example:**

```yaml
# .github/workflows/deploy-preview.yml
name: Deploy Preview

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  deploy-preview:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '18'
        
    - name: Install dependencies
      run: npm ci
      
    - name: Build application
      run: npm run build
      
    - name: Download AetherLink client
      run: |
        wget https://github.com/hhftechnology/AetherLink/releases/latest/download/aetherlink-client-linux-amd64
        chmod +x aetherlink-client-linux-amd64
        
    - name: Start preview server
      run: |
        npm run preview &
        sleep 10
        
    - name: Create tunnel
      run: |
        ./aetherlink-client-linux-amd64 \
          --server=https://tunnel.yourdomain.com \
          --port=4173 \
          --subdomain=pr-${{ github.event.number }} &
        sleep 5
        
    - name: Comment PR
      uses: actions/github-script@v6
      with:
        script: |
          github.rest.issues.createComment({
            issue_number: context.issue.number,
            owner: context.repo.owner,
            repo: context.repo.repo,
            body: '🚀 Preview deployed at: https://pr-${{ github.event.number }}.tunnel.yourdomain.com'
          })
```

## Production Deployments

### High Availability Setup

```bash
# Load balancer configuration (nginx)
upstream aetherlink_backend {
    server 10.0.1.10:8080 max_fails=3 fail_timeout=30s;
    server 10.0.1.11:8080 max_fails=3 fail_timeout=30s;
    server 10.0.1.12:8080 max_fails=3 fail_timeout=30s;
}

server {
    listen 443 ssl http2;
    server_name tunnel.yourdomain.com *.tunnel.yourdomain.com;
    
    ssl_certificate /etc/ssl/certs/yourdomain.com.crt;
    ssl_certificate_key /etc/ssl/private/yourdomain.com.key;
    
    location / {
        proxy_pass http://aetherlink_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

### AWS Deployment

**Using EC2 with Application Load Balancer:**

```bash
# 1. Launch EC2 instances
aws ec2 run-instances \
    --image-id ami-0c02fb55956c7d316 \
    --instance-type t3.small \
    --key-name your-key-pair \
    --security-group-ids sg-xxxxxxxxx \
    --subnet-id subnet-xxxxxxxxx \
    --user-data file://user-data.sh \
    --count 2

# 2. Create Application Load Balancer
aws elbv2 create-load-balancer \
    --name aetherlink-alb \
    --subnets subnet-xxxxxxxxx subnet-yyyyyyyyy \
    --security-groups sg-xxxxxxxxx

# 3. Create target group
aws elbv2 create-target-group \
    --name aetherlink-targets \
    --protocol HTTP \
    --port 8080 \
    --vpc-id vpc-xxxxxxxxx \
    --health-check-path /api/status
```

**User data script (user-data.sh):**

```bash
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker

# Run AetherLink server
docker run -d \
    --name aetherlink-server \
    --restart unless-stopped \
    -p 8080:8080 \
    -p 62322:62322 \
    hhftechnology/aetherlink-server:latest \
    --address=0.0.0.0 --port=8080 --domain=tunnel.yourdomain.com --secure=true
```

### Google Cloud Platform Deployment

```yaml
# clouddeploy.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aetherlink-config
data:
  domain: "tunnel.yourdomain.com"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aetherlink-server
spec:
  replicas: 3
  selector:
    matchLabels:
      app: aetherlink-server
  template:
    metadata:
      labels:
        app: aetherlink-server
    spec:
      containers:
      - name: aetherlink-server
        image: hhftechnology/aetherlink-server:latest
        args:
          - "--address=0.0.0.0"
          - "--port=8080"
          - "--domain=$(DOMAIN)"
          - "--secure=true"
        env:
        - name: DOMAIN
          valueFrom:
            configMapKeyRef:
              name: aetherlink-config
              key: domain
        ports:
        - containerPort: 8080
        - containerPort: 62322
---
apiVersion: v1
kind: Service
metadata:
  name: aetherlink-service
spec:
  selector:
    app: aetherlink-server
  ports:
  - name: http
    port: 80
    targetPort: 8080
  - name: tunnel
    port: 62322
    targetPort: 62322
  type: LoadBalancer
```

## Development Team Setups

### Large Team Configuration

For teams with 10+ developers, consider this setup:

```bash
# Server configuration with team separation
./aetherlink-server \
    --address=0.0.0.0 \
    --port=8080 \
    --domain=dev.company.com \
    --secure=true

# Team-specific subdomain patterns:
# Frontend team: frontend-{developer}.dev.company.com
# Backend team:  api-{developer}.dev.company.com  
# Mobile team:   mobile-{developer}.dev.company.com
```

**Team onboarding script:**

```bash
#!/bin/bash
# team-setup.sh

TEAM=$1
DEVELOPER=$2
DOMAIN="dev.company.com"

if [ -z "$TEAM" ] || [ -z "$DEVELOPER" ]; then
    echo "Usage: $0 <team> <developer>"
    echo "Teams: frontend, backend, mobile, devops"
    exit 1
fi

# Download client if not exists
if [ ! -f "./aetherlink-client" ]; then
    wget -O aetherlink-client https://github.com/hhftechnology/AetherLink/releases/latest/download/aetherlink-client-linux-amd64
    chmod +x aetherlink-client
fi

# Create team-specific scripts
mkdir -p ~/tunnels

case $TEAM in
    "frontend")
        cat > ~/tunnels/start-frontend.sh << EOF
#!/bin/bash
./aetherlink-client --server=https://$DOMAIN --port=3000 --subdomain=frontend-$DEVELOPER
EOF
        ;;
    "backend")
        cat > ~/tunnels/start-backend.sh << EOF
#!/bin/bash  
./aetherlink-client --server=https://$DOMAIN --port=8080 --subdomain=api-$DEVELOPER
EOF
        ;;
    "mobile")
        cat > ~/tunnels/start-mobile.sh << EOF
#!/bin/bash
./aetherlink-client --server=https://$DOMAIN --port=19006 --subdomain=mobile-$DEVELOPER
EOF
        ;;
esac

chmod +x ~/tunnels/*.sh

echo "Setup complete for $DEVELOPER ($TEAM team)"
echo "Your tunnel will be available at: https://$TEAM-$DEVELOPER.$DOMAIN"
echo "Start tunnel with: ~/tunnels/start-$TEAM.sh"
```

## Monitoring and Maintenance

### Health Monitoring

```bash
# health-check.sh
#!/bin/bash

DOMAIN="tunnel.yourdomain.com"
TELEGRAM_BOT_TOKEN="your-bot-token"
TELEGRAM_CHAT_ID="your-chat-id"

check_server_health() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/api/status")
    if [ "$response" != "200" ]; then
        send_alert "AetherLink server is down! HTTP status: $response"
        return 1
    fi
    return 0
}

send_alert() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id=$TELEGRAM_CHAT_ID \
        -d text="🚨 $message"
}

# Main monitoring loop
while true; do
    if ! check_server_health; then
        echo "$(date): Server health check failed"
    else
        echo "$(date): Server is healthy"
    fi
    sleep 300  # Check every 5 minutes
done
```

### Log Monitoring

```bash
# Setup log rotation for Docker deployment
cat > /etc/logrotate.d/aetherlink << EOF
/var/lib/docker/containers/*/*-json.log {
    rotate 7
    daily
    compress
    size=100M
    missingok
    delaycompress
    copytruncate
}
EOF
```

### Backup and Recovery

```bash
# backup-config.sh
#!/bin/bash

BACKUP_DIR="/backup/aetherlink"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup configuration
docker exec aetherlink-server cat /etc/aetherlink/config.json > $BACKUP_DIR/config_$DATE.json

# Backup certificates (if any)
docker cp aetherlink-server:/etc/ssl/certs $BACKUP_DIR/certs_$DATE/

# Keep only last 30 backups
find $BACKUP_DIR -name "config_*.json" -mtime +30 -delete
find $BACKUP_DIR -name "certs_*" -mtime +30 -exec rm -rf {} \;

echo "Backup completed: $DATE"
```

This deployment guide covers various scenarios from simple development setups to enterprise-grade production deployments. Choose the appropriate configuration based on your needs and scale accordingly.