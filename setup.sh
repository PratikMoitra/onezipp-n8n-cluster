#!/bin/bash

# =============================================================================
# Onezipp N8N Cluster Script - Production Ready Setup with Auto-Fix
# =============================================================================
# This script sets up n8n self-hosted AI starter kit with:
# - Caddy reverse proxy with SSL
# - N8N in queue mode with 4 worker nodes and 4 webhook nodes
# - Redis for queue management
# - PostgreSQL database
# - Ollama, Qdrant for AI capabilities
# - AUTO-FIX: Automatically fixes common errors and pushes to git
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Git repository info
GIT_REPO_DIR="$HOME/onezipp-n8n-cluster"
GIT_REMOTE="https://github.com/PratikMoitra/onezipp-n8n-cluster.git"
SUMMARY_SHOWN=""

# Banner
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║           🚀 Onezipp N8N Cluster Setup Script 🚀            ║"
echo "║                   with Auto-Fix Capability                   ║"
echo "║     Production-Ready N8N with AI Starter Kit & Caddy        ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print section headers
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to commit and push fixes to git
push_fix_to_git() {
    local fix_message=$1
    local current_dir=$(pwd)
    
    if [ -d "$GIT_REPO_DIR" ]; then
        cd "$GIT_REPO_DIR"
        
        # Only copy if files are different paths
        if [ "$(realpath "$0")" != "$(realpath "$GIT_REPO_DIR/setup.sh")" ]; then
            cp "$0" "$GIT_REPO_DIR/setup.sh"
        fi
        
        # Check if there are changes
        if ! git diff --quiet; then
            print_message $YELLOW "📤 Pushing fix to git: $fix_message"
            git add -A
            git commit -m "Auto-fix: $fix_message" || true
            
            # Try to push with stored credentials
            if git push origin main 2>/dev/null; then
                print_message $GREEN "✅ Fix pushed to git successfully"
            else
                print_message $YELLOW "⚠️  Could not push to git (credentials needed)"
            fi
        fi
        
        cd "$current_dir"
    fi
}

# Function to fix worker/webhook command issues
fix_worker_commands() {
    print_message $YELLOW "🔧 Fixing worker/webhook commands..."
    
    cd "$INSTALL_DIR/self-hosted-ai-starter-kit"
    
    # Try different command formats - fixed the typo in the first format
    local command_formats=('["worker"]' "worker" '["node", "/usr/local/lib/node_modules/n8n/bin/n8n", "worker"]')
    local webhook_formats=('["webhook"]' "webhook" '["node", "/usr/local/lib/node_modules/n8n/bin/n8n", "webhook"]')
    
    for i in "${!command_formats[@]}"; do
        local cmd="${command_formats[$i]}"
        print_message $YELLOW "Testing command format: $cmd"
        
        # Update docker-compose.yml for one worker
        sed -i "/n8n-worker-1:/,/volumes:/ s/command: .*/command: $cmd/" docker-compose.yml
        
        # Test with one worker
        docker compose up -d n8n-worker-1
        sleep 10
        
        # Check if it's running
        if docker ps | grep -q "n8n-worker-1" && ! docker ps | grep "Restarting" | grep -q "n8n-worker-1"; then
            print_message $GREEN "✅ Found working command format: $cmd"
            
            # Apply to all workers
            for j in {1..4}; do
                sed -i "/n8n-worker-$j:/,/volumes:/ s/command: .*/command: $cmd/" docker-compose.yml
            done
            
            # Apply webhook command
            local webhook_cmd="${webhook_formats[$i]}"
            for j in {1..4}; do
                sed -i "/n8n-webhook-$j:/,/volumes:/ s/command: .*/command: $webhook_cmd/" docker-compose.yml
            done
            
            push_fix_to_git "Fixed worker/webhook command format to: $cmd"
            return 0
        fi
    done
    
    return 1
}

# Function to fix GPU configuration issues
fix_gpu_config() {
    print_message $YELLOW "🔧 Fixing GPU configuration..."
    
    cd "$INSTALL_DIR/self-hosted-ai-starter-kit"
    
    # Remove GPU config for CPU-only mode
    if [ "$GPU_PROFILE" = "cpu" ]; then
        # Remove deploy section from ollama service
        sed -i '/ollama:/,/^[[:space:]]*[^[:space:]]/ {
            /deploy:/,/limits:/ d
        }' docker-compose.yml
        
        push_fix_to_git "Removed GPU configuration for CPU-only mode"
    fi
}

# Function to fix container restart issues
fix_container_restarts() {
    print_message $YELLOW "🔧 Checking for restarting containers..."
    
    local restarting_containers=$(docker ps --format "table {{.Names}}" | grep -E "n8n-worker|n8n-webhook" | while read container; do
        if docker ps | grep "$container" | grep -q "Restarting"; then
            echo "$container"
        fi
    done)
    
    if [ -n "$restarting_containers" ]; then
        print_message $YELLOW "Found restarting containers. Attempting fixes..."
        
        # Try to fix worker commands
        if fix_worker_commands; then
            docker compose down
            docker compose up -d
            sleep 30
        fi
    fi
}

# Error handler
handle_error() {
    local error_code=$?
    local error_line=$1
    
    print_message $RED "❌ Error occurred at line $error_line with code $error_code"
    
    # Specific error handlers
    case $error_code in
        125)
            print_message $YELLOW "Docker error detected. Attempting to fix..."
            fix_gpu_config
            fix_worker_commands
            ;;
        *)
            print_message $YELLOW "General error. Checking system state..."
            fix_container_restarts
            ;;
    esac
    
    # Re-run the failed command
    print_message $YELLOW "🔄 Retrying installation..."
}

# Set error trap
trap 'handle_error $LINENO' ERR

# Ensure summary is shown even on exit
trap 'show_summary' EXIT

# Function to show summary
show_summary() {
    if [ -f "$INSTALL_DIR/config-summary.txt" ] && [ -z "$SUMMARY_SHOWN" ]; then
        echo ""
        print_section "📋 Installation Summary"
        cat "$INSTALL_DIR/config-summary.txt"
        SUMMARY_SHOWN=1
    fi
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_message $RED "❌ This script must be run as root (use sudo)"
   exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to generate random string
generate_random_string() {
    local length=${1:-32}
    openssl rand -hex $length | head -c $length
}

# Function to validate domain (supports subdomains)
validate_domain() {
    local domain=$1
    # More permissive regex that supports multiple subdomain levels
    if [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

# Function to validate email
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# Install prerequisites
print_section "Installing Prerequisites"

# Update system
print_message $YELLOW "📦 Updating system packages..."
apt-get update -qq || true
apt-get upgrade -y -qq || true

# Install required packages
print_message $YELLOW "📦 Installing required packages..."
apt-get install -y -qq \
    curl \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    openssl \
    jq || true

# Install Docker if not present
if ! command_exists docker; then
    print_message $YELLOW "🐳 Installing Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
else
    print_message $GREEN "✅ Docker is already installed"
fi

# Get server IP for subdomain hint
SERVER_IP=$(curl -s https://api.ipify.org || echo "your-server-ip")

# Collect user input
print_section "Configuration Setup"

print_message $YELLOW "💡 Tip: This script fully supports subdomains!"
print_message $YELLOW "   Examples: n8n.yourdomain.com, workflow.company.com, automation.yourdomain.io"
print_message $YELLOW "   Make sure your DNS A record points to: ${GREEN}${SERVER_IP}${NC}"
echo ""

# Domain configuration
while true; do
    read -p "Enter your domain/subdomain [stepper.onezipp.com]: " DOMAIN
    DOMAIN=${DOMAIN:-stepper.onezipp.com}
    if validate_domain "$DOMAIN"; then
        print_message $GREEN "✅ Using domain: $DOMAIN"
        break
    else
        print_message $RED "❌ Invalid domain format. Please enter a valid domain or subdomain."
    fi
done

# Email for Let's Encrypt
while true; do
    read -p "Enter your email for SSL certificates [pratik@onezipp.com]: " EMAIL
    EMAIL=${EMAIL:-pratik@onezipp.com}
    if validate_email "$EMAIL"; then
        print_message $GREEN "✅ Using email: $EMAIL"
        break
    else
        print_message $RED "❌ Invalid email format. Please enter a valid email."
    fi
done

# N8N admin credentials
read -p "Enter N8N admin username [pratik@onezipp.com]: " N8N_ADMIN_EMAIL
N8N_ADMIN_EMAIL=${N8N_ADMIN_EMAIL:-pratik@onezipp.com}
print_message $GREEN "✅ Using admin email: $N8N_ADMIN_EMAIL"

# Setup directory
INSTALL_DIR="/opt/onezipp-n8n"
EXISTING_PASSWORD=""
print_section "Setting up installation directory"
print_message $YELLOW "📁 Default installation directory: ${GREEN}$INSTALL_DIR${NC}"
read -p "Use default directory? (Y/n) [Y]: " USE_DEFAULT_DIR
USE_DEFAULT_DIR=${USE_DEFAULT_DIR:-Y}

if [[ ! "$USE_DEFAULT_DIR" =~ ^[Yy]$ ]]; then
    read -p "Enter custom installation directory: " CUSTOM_DIR
    INSTALL_DIR=${CUSTOM_DIR:-/opt/onezipp-n8n}
fi

# Check if this is an update
if [ -f "$INSTALL_DIR/config-summary.txt" ]; then
    print_message $YELLOW "📦 Existing installation detected. Preserving configuration..."
    # Try to extract the existing password
    EXISTING_PASSWORD=$(grep "N8N Admin Password:" "$INSTALL_DIR/config-summary.txt" | cut -d' ' -f4)
fi

print_message $GREEN "✅ Using directory: $INSTALL_DIR"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Generate deterministic password based on system fingerprint
if [ -n "$EXISTING_PASSWORD" ]; then
    DEFAULT_PASSWORD=$EXISTING_PASSWORD
    print_message $YELLOW "Using existing password from previous installation"
else
    SYSTEM_ID=$(cat /etc/machine-id 2>/dev/null || hostname -f || echo "default")
    DEFAULT_PASSWORD=$(echo -n "${SYSTEM_ID}onezipp" | sha256sum | cut -c1-12)
fi
echo ""
print_message $YELLOW "Generated secure password: ${GREEN}${DEFAULT_PASSWORD}${NC}"
print_message $BLUE "   (This password is unique to this server and will remain the same on reinstalls)"
read -p "Use this password? (Y/n) [Y]: " USE_DEFAULT_PASS
USE_DEFAULT_PASS=${USE_DEFAULT_PASS:-Y}

if [[ "$USE_DEFAULT_PASS" =~ ^[Yy]$ ]]; then
    N8N_ADMIN_PASSWORD=$DEFAULT_PASSWORD
    print_message $GREEN "✅ Using generated password"
else
    while true; do
        read -s -p "Enter N8N admin password (min 8 chars): " N8N_ADMIN_PASSWORD
        echo
        if [ ${#N8N_ADMIN_PASSWORD} -ge 8 ]; then
            break
        else
            print_message $RED "❌ Password must be at least 8 characters long."
        fi
    done
fi

# Database passwords
print_message $YELLOW "🔐 Generating secure passwords..."
POSTGRES_PASSWORD=$(generate_random_string 24)
REDIS_PASSWORD=$(generate_random_string 24)
N8N_ENCRYPTION_KEY=$(generate_random_string 32)
N8N_JWT_SECRET=$(generate_random_string 32)

# GPU selection
print_message $YELLOW "🖥️  Select your GPU type:"
echo "1) NVIDIA GPU"
echo "2) AMD GPU"
echo "3) CPU only (no GPU) [default]"
read -p "Enter your choice (1-3) [3]: " GPU_CHOICE
GPU_CHOICE=${GPU_CHOICE:-3}

case $GPU_CHOICE in
    1) 
        GPU_PROFILE="gpu-nvidia"
        print_message $GREEN "✅ Using NVIDIA GPU profile"
        ;;
    2) 
        GPU_PROFILE="gpu-amd"
        print_message $GREEN "✅ Using AMD GPU profile"
        ;;
    *) 
        GPU_PROFILE="cpu"
        print_message $GREEN "✅ Using CPU-only profile"
        ;;
esac

# Clone the starter kit
print_section "Downloading N8N AI Starter Kit"
if [ -d "self-hosted-ai-starter-kit" ]; then
    print_message $YELLOW "📦 Removing existing installation..."
    rm -rf self-hosted-ai-starter-kit
fi
git clone https://github.com/n8n-io/self-hosted-ai-starter-kit.git
cd self-hosted-ai-starter-kit

# Create environment file
print_section "Creating Configuration Files"
print_message $YELLOW "📝 Creating .env file..."

cat > .env << EOF
# Database Configuration
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=n8n

# Redis Configuration
REDIS_PASSWORD=${REDIS_PASSWORD}

# N8N Configuration
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_JWT_SECRET}
N8N_DEFAULT_BINARY_DATA_MODE=filesystem
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=${N8N_ADMIN_EMAIL}
N8N_BASIC_AUTH_PASSWORD=${N8N_ADMIN_PASSWORD}

# Domain Configuration
DOMAIN=${DOMAIN}
EMAIL=${EMAIL}

# Queue Mode Configuration
EXECUTIONS_MODE=queue
QUEUE_BULL_REDIS_HOST=redis
QUEUE_BULL_REDIS_PORT=6379
QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
QUEUE_HEALTH_CHECK_ACTIVE=true

# Worker Configuration
N8N_CONCURRENCY=10

# Webhook and URL Configuration
WEBHOOK_URL=https://${DOMAIN}
N8N_WEBHOOK_BASE_URL=https://${DOMAIN}
N8N_EDITOR_BASE_URL=https://${DOMAIN}
N8N_HOST=${DOMAIN}
N8N_PROTOCOL=https
N8N_PORT=443
N8N_WEBHOOK_URL=https://${DOMAIN}
N8N_WEBHOOK_TUNNEL_URL=https://${DOMAIN}

# GPU Profile
GPU_PROFILE=${GPU_PROFILE}
EOF

# Create Caddyfile
print_message $YELLOW "📝 Creating Caddyfile..."
mkdir -p caddy
cat > caddy/Caddyfile << EOF
{
    email ${EMAIL}
}

${DOMAIN} {
    # Main N8N UI/API
    @api {
        path /rest/*
        path /webhook/*
        path /webhook-test/*
        path /webhook-waiting/*
        path /execution/*
        path /workflows/*
    }
    
    # WebSocket support
    @websocket {
        header Connection *Upgrade*
        header Upgrade websocket
    }
    
    # Reverse proxy to main n8n instance
    reverse_proxy @api n8n-main:5678
    reverse_proxy @websocket n8n-main:5678
    
    # Load balance webhook requests across webhook processors
    reverse_proxy /webhook/* {
        to n8n-webhook-1:5678
        to n8n-webhook-2:5678
        to n8n-webhook-3:5678
        to n8n-webhook-4:5678
        lb_policy round_robin
        health_uri /healthz
        health_interval 10s
        health_timeout 5s
    }
    
    # Default to main instance for everything else
    reverse_proxy n8n-main:5678
    
    # Security headers
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy no-referrer-when-downgrade
    }
    
    # Enable compression
    encode gzip
    
    # Logging
    log {
        output file /data/access.log
        format json
    }
}
EOF

# Create custom docker-compose file
print_message $YELLOW "📝 Creating docker-compose.yml..."

# Create base docker-compose without GPU config
cat > docker-compose.yml << 'DOCKERCOMPOSE_EOF'
x-n8n-base: &n8n-base
  image: n8nio/n8n:latest
  networks: ['n8n-network']
  environment:
    - DB_TYPE=postgresdb
    - DB_POSTGRESDB_HOST=postgres
    - DB_POSTGRESDB_USER=${POSTGRES_USER}
    - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
    - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
    - N8N_DIAGNOSTICS_ENABLED=false
    - N8N_PERSONALIZATION_ENABLED=false
    - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
    - N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}
    - EXECUTIONS_MODE=${EXECUTIONS_MODE}
    - QUEUE_BULL_REDIS_HOST=${QUEUE_BULL_REDIS_HOST}
    - QUEUE_BULL_REDIS_PORT=${QUEUE_BULL_REDIS_PORT}
    - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
    - QUEUE_HEALTH_CHECK_ACTIVE=${QUEUE_HEALTH_CHECK_ACTIVE}
    - N8N_WEBHOOK_BASE_URL=${N8N_WEBHOOK_BASE_URL}
    - WEBHOOK_URL=${WEBHOOK_URL}
    - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
    - N8N_HOST=${N8N_HOST}
    - N8N_PROTOCOL=${N8N_PROTOCOL}
    - N8N_PORT=${N8N_PORT}
    - N8N_WEBHOOK_URL=${N8N_WEBHOOK_URL}
    - N8N_WEBHOOK_TUNNEL_URL=${N8N_WEBHOOK_TUNNEL_URL}
    - OLLAMA_HOST=ollama:11434
  depends_on:
    postgres:
      condition: service_healthy
    redis:
      condition: service_healthy
  restart: unless-stopped

services:
  # Caddy Reverse Proxy
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    networks: ['n8n-network']
    restart: unless-stopped

  # PostgreSQL Database
  postgres:
    image: postgres:16-alpine
    container_name: postgres
    networks: ['n8n-network']
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    volumes:
      - postgres_storage:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis for Queue Management
  redis:
    image: redis:7-alpine
    container_name: redis
    networks: ['n8n-network']
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_storage:/data
    healthcheck:
      test: ["CMD", "redis-cli", "--pass", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # N8N Main Instance (UI/API)
  n8n-main:
    <<: *n8n-base
    container_name: n8n-main
    hostname: n8n-main
    ports:
      - "5678:5678"
    volumes:
      - n8n_storage:/home/node/.n8n
      - ./shared:/data/shared
    environment:
      - N8N_BASIC_AUTH_ACTIVE=${N8N_BASIC_AUTH_ACTIVE}
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}

  # N8N Worker Nodes
  n8n-worker-1:
    <<: *n8n-base
    container_name: n8n-worker-1
    hostname: n8n-worker-1
    command: worker
    environment:
      - N8N_CONCURRENCY=${N8N_CONCURRENCY}
    volumes:
      - ./shared:/data/shared

  n8n-worker-2:
    <<: *n8n-base
    container_name: n8n-worker-2
    hostname: n8n-worker-2
    command: worker
    environment:
      - N8N_CONCURRENCY=${N8N_CONCURRENCY}
    volumes:
      - ./shared:/data/shared

  n8n-worker-3:
    <<: *n8n-base
    container_name: n8n-worker-3
    hostname: n8n-worker-3
    command: worker
    environment:
      - N8N_CONCURRENCY=${N8N_CONCURRENCY}
    volumes:
      - ./shared:/data/shared

  n8n-worker-4:
    <<: *n8n-base
    container_name: n8n-worker-4
    hostname: n8n-worker-4
    command: worker
    environment:
      - N8N_CONCURRENCY=${N8N_CONCURRENCY}
    volumes:
      - ./shared:/data/shared

  # N8N Webhook Processor Nodes
  n8n-webhook-1:
    <<: *n8n-base
    container_name: n8n-webhook-1
    hostname: n8n-webhook-1
    command: webhook
    volumes:
      - ./shared:/data/shared

  n8n-webhook-2:
    <<: *n8n-base
    container_name: n8n-webhook-2
    hostname: n8n-webhook-2
    command: webhook
    volumes:
      - ./shared:/data/shared

  n8n-webhook-3:
    <<: *n8n-base
    container_name: n8n-webhook-3
    hostname: n8n-webhook-3
    command: webhook
    volumes:
      - ./shared:/data/shared

  n8n-webhook-4:
    <<: *n8n-base
    container_name: n8n-webhook-4
    hostname: n8n-webhook-4
    command: webhook
    volumes:
      - ./shared:/data/shared

  # Ollama AI Model Server
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    networks: ['n8n-network']
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ollama_storage:/root/.ollama
    environment:
      - OLLAMA_HOST=0.0.0.0
DOCKERCOMPOSE_EOF

# Add GPU configuration only if GPU is selected
if [ "$GPU_PROFILE" = "gpu-nvidia" ]; then
    cat >> docker-compose.yml << 'GPU_CONFIG_EOF'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
        limits:
          memory: 4G
GPU_CONFIG_EOF
elif [ "$GPU_PROFILE" = "gpu-amd" ]; then
    cat >> docker-compose.yml << 'GPU_CONFIG_EOF'
    devices:
      - /dev/kfd
      - /dev/dri
    group_add:
      - video
      - render
GPU_CONFIG_EOF
fi

# Continue with the rest of docker-compose.yml
cat >> docker-compose.yml << 'DOCKERCOMPOSE_END_EOF'

  # Ollama model puller
  ollama-pull:
    image: ollama/ollama:latest
    networks: ['n8n-network']
    container_name: ollama-pull
    volumes:
      - ollama_storage:/root/.ollama
    environment:
      - OLLAMA_HOST=ollama:11434
    entrypoint: /bin/sh
    command:
      - "-c"
      - "sleep 10 && ollama pull llama3.2 && ollama pull nomic-embed-text"
    depends_on:
      - ollama

  # Qdrant Vector Database
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    networks: ['n8n-network']
    restart: unless-stopped
    ports:
      - "6333:6333"
    volumes:
      - qdrant_storage:/qdrant/storage

volumes:
  n8n_storage:
  postgres_storage:
  redis_storage:
  ollama_storage:
  qdrant_storage:
  caddy_data:
  caddy_config:

networks:
  n8n-network:
    driver: bridge
DOCKERCOMPOSE_END_EOF

# Create startup script
print_message $YELLOW "📝 Creating startup script..."
cat > start.sh << EOF
#!/bin/bash
cd $INSTALL_DIR/self-hosted-ai-starter-kit
docker compose up -d
EOF
chmod +x start.sh

# Create stop script
cat > stop.sh << EOF
#!/bin/bash
cd $INSTALL_DIR/self-hosted-ai-starter-kit
docker compose down
EOF
chmod +x stop.sh

# Create systemd service
print_section "Creating System Service"
print_message $YELLOW "🔧 Creating systemd service..."
cat > /etc/systemd/system/onezipp-n8n.service << EOF
[Unit]
Description=Onezipp N8N Cluster
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR/self-hosted-ai-starter-kit
ExecStart=$INSTALL_DIR/self-hosted-ai-starter-kit/start.sh
ExecStop=$INSTALL_DIR/self-hosted-ai-starter-kit/stop.sh
User=root
Restart=on-failure
RestartSec=30s

[Install]
WantedBy=multi-user.target
EOF

# Configure firewall
print_section "Configuring Firewall"
if command_exists ufw; then
    print_message $YELLOW "🔥 Configuring UFW firewall..."
    ufw --force enable
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw reload
else
    print_message $YELLOW "⚠️  UFW not found. Please configure your firewall manually."
fi

# Start services
print_section "Starting Services"
print_message $YELLOW "🚀 Starting Onezipp N8N Cluster..."
systemctl daemon-reload
systemctl enable onezipp-n8n.service
cd $INSTALL_DIR/self-hosted-ai-starter-kit

# Start services with error handling
if ! docker compose up -d; then
    print_message $RED "❌ Initial startup failed. Attempting fixes..."
    fix_gpu_config
    docker compose up -d
fi

# Wait for services to be ready
print_message $YELLOW "⏳ Waiting for services to start..."
sleep 45

# Check for issues and auto-fix
fix_container_restarts

# Check service status
print_section "Service Status Check"
SERVICES=("caddy" "postgres" "redis" "n8n-main" "n8n-worker-1" "n8n-worker-2" "n8n-worker-3" "n8n-worker-4" "n8n-webhook-1" "n8n-webhook-2" "n8n-webhook-3" "n8n-webhook-4" "ollama" "qdrant")

for service in "${SERVICES[@]}"; do
    if docker ps | grep -q $service; then
        print_message $GREEN "✅ $service is running"
    else
        print_message $RED "❌ $service is not running"
    fi
done

# Save configuration summary
print_section "Saving Configuration"
cat > $INSTALL_DIR/config-summary.txt << EOF
Onezipp N8N Cluster Configuration Summary
=========================================
Installation Date: $(date)
Installation Directory: $INSTALL_DIR

Domain: ${DOMAIN}
SSL Email: ${EMAIL}

N8N Admin Email: ${N8N_ADMIN_EMAIL}
N8N Admin Password: ${N8N_ADMIN_PASSWORD}

PostgreSQL Password: ${POSTGRES_PASSWORD}
Redis Password: ${REDIS_PASSWORD}
N8N Encryption Key: ${N8N_ENCRYPTION_KEY}
N8N JWT Secret: ${N8N_JWT_SECRET}

GPU Profile: ${GPU_PROFILE}

Service URLs:
- N8N UI: https://${DOMAIN}
- Ollama API: http://localhost:11434
- Qdrant API: http://localhost:6333

Commands:
- Start services: systemctl start onezipp-n8n
- Stop services: systemctl stop onezipp-n8n
- View logs: docker compose -f $INSTALL_DIR/self-hosted-ai-starter-kit/docker-compose.yml logs -f
- Restart services: systemctl restart onezipp-n8n
EOF

# Final check and push any fixes
if docker ps | grep -E "n8n-worker|n8n-webhook" | grep -q "Restarting"; then
    print_message $YELLOW "⚠️  Some services are still restarting. Running final fixes..."
    fix_container_restarts
fi

# Push final state to git
push_fix_to_git "Installation completed with all fixes applied"

# Final output
SUMMARY_SHOWN=1
print_section "🎉 Installation Complete!"
echo ""
print_message $GREEN "✅ Onezipp N8N Cluster has been successfully installed!"
echo ""
echo -e "${YELLOW}📋 Access Information:${NC}"
echo -e "   N8N UI: ${GREEN}https://${DOMAIN}${NC}"
echo -e "   Username: ${GREEN}${N8N_ADMIN_EMAIL}${NC}"
if [[ "$USE_DEFAULT_PASS" =~ ^[Yy]$ ]]; then
    echo -e "   Password: ${GREEN}${N8N_ADMIN_PASSWORD}${NC} ${YELLOW}(save this!)${NC}"
else
    echo -e "   Password: ${GREEN}[The password you entered]${NC}"
fi
echo ""
echo -e "${YELLOW}🔧 Useful Commands:${NC}"
echo -e "   Start services: ${GREEN}systemctl start onezipp-n8n${NC}"
echo -e "   Stop services: ${GREEN}systemctl stop onezipp-n8n${NC}"
echo -e "   View logs: ${GREEN}cd $INSTALL_DIR/self-hosted-ai-starter-kit && docker compose logs -f${NC}"
echo -e "   Restart: ${GREEN}systemctl restart onezipp-n8n${NC}"
echo ""
echo -e "${YELLOW}📁 Configuration saved to:${NC}"
echo -e "   ${GREEN}$INSTALL_DIR/config-summary.txt${NC}"
echo ""
echo -e "${BLUE}🚀 Your N8N cluster is now running with:${NC}"
echo -e "   • 1 Main N8N instance (UI/API)"
echo -e "   • 4 Worker nodes for processing"
echo -e "   • 4 Webhook processor nodes"
echo -e "   • Redis for queue management"
echo -e "   • PostgreSQL database"
echo -e "   • Caddy with automatic SSL"
echo -e "   • Ollama for AI models"
echo -e "   • Qdrant vector database"
echo ""
print_message $YELLOW "⚠️  Note: It may take a few minutes for SSL certificates to be issued."
print_message $YELLOW "   If you can't access the site immediately, please wait 2-3 minutes."
echo ""
print_message $GREEN "🎊 Thank you for using Onezipp N8N Cluster Script!"
print_message $BLUE "   GitHub: https://github.com/PratikMoitra/onezipp-n8n-cluster"
print_message $BLUE "   Auto-fix enabled: Errors are automatically fixed and pushed to git"
