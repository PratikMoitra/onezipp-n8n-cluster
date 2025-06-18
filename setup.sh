#!/bin/bash

# =============================================================================
# Onezipp N8N Cluster Script - Production Ready Setup
# =============================================================================
# This script sets up n8n self-hosted AI starter kit with:
# - Caddy reverse proxy with SSL
# - N8N in queue mode with 4 worker nodes and 4 webhook nodes
# - Redis for queue management
# - PostgreSQL database
# - Ollama, Qdrant for AI capabilities
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║           🚀 Onezipp N8N Cluster Setup Script 🚀            ║"
echo "║                                                              ║"
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
apt-get update -qq
apt-get upgrade -y -qq

# Install required packages
print_message $YELLOW "📦 Installing required packages..."
apt-get install -y -qq \
    curl \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    openssl \
    jq

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
    read -p "Enter your domain/subdomain [n8n.example.com]: " DOMAIN
    DOMAIN=${DOMAIN:-n8n.example.com}
    if validate_domain "$DOMAIN"; then
        print_message $GREEN "✅ Using domain: $DOMAIN"
        break
    else
        print_message $RED "❌ Invalid domain format. Please enter a valid domain or subdomain."
    fi
done

# Email for Let's Encrypt
while true; do
    read -p "Enter your email for SSL certificates [admin@${DOMAIN#*.}]: " EMAIL
    EMAIL=${EMAIL:-admin@${DOMAIN#*.}}
    if validate_email "$EMAIL"; then
        print_message $GREEN "✅ Using email: $EMAIL"
        break
    else
        print_message $RED "❌ Invalid email format. Please enter a valid email."
    fi
done

# N8N admin credentials
read -p "Enter N8N admin username [admin@${DOMAIN#*.}]: " N8N_ADMIN_EMAIL
N8N_ADMIN_EMAIL=${N8N_ADMIN_EMAIL:-admin@${DOMAIN#*.}}
print_message $GREEN "✅ Using admin email: $N8N_ADMIN_EMAIL"

# Generate default password
DEFAULT_PASSWORD=$(generate_random_string 12)
echo ""
print_message $YELLOW "Generated secure password: ${GREEN}${DEFAULT_PASSWORD}${NC}"
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

# Setup directory
INSTALL_DIR="/opt/onezipp-n8n"
print_section "Setting up installation directory"
print_message $YELLOW "📁 Default installation directory: ${GREEN}$INSTALL_DIR${NC}"
read -p "Use default directory? (Y/n) [Y]: " USE_DEFAULT_DIR
USE_DEFAULT_DIR=${USE_DEFAULT_DIR:-Y}

if [[ ! "$USE_DEFAULT_DIR" =~ ^[Yy]$ ]]; then
    read -p "Enter custom installation directory: " CUSTOM_DIR
    INSTALL_DIR=${CUSTOM_DIR:-/opt/onezipp-n8n}
fi

print_message $GREEN "✅ Using directory: $INSTALL_DIR"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

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

# Webhook Configuration
WEBHOOK_URL=https://${DOMAIN}
N8N_WEBHOOK_BASE_URL=https://${DOMAIN}
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
cat > docker-compose.yml << 'EOF'
version: '3.8'

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
    command: n8n worker
    environment:
      - N8N_CONCURRENCY=${N8N_CONCURRENCY}
    volumes:
      - ./shared:/data/shared

  n8n-worker-2:
    <<: *n8n-base
    container_name: n8n-worker-2
    hostname: n8n-worker-2
    command: n8n worker
    environment:
      - N8N_CONCURRENCY=${N8N_CONCURRENCY}
    volumes:
      - ./shared:/data/shared

  n8n-worker-3:
    <<: *n8n-base
    container_name: n8n-worker-3
    hostname: n8n-worker-3
    command: n8n worker
    environment:
      - N8N_CONCURRENCY=${N8N_CONCURRENCY}
    volumes:
      - ./shared:/data/shared

  n8n-worker-4:
    <<: *n8n-base
    container_name: n8n-worker-4
    hostname: n8n-worker-4
    command: n8n worker
    environment:
      - N8N_CONCURRENCY=${N8N_CONCURRENCY}
    volumes:
      - ./shared:/data/shared

  # N8N Webhook Processor Nodes
  n8n-webhook-1:
    <<: *n8n-base
    container_name: n8n-webhook-1
    hostname: n8n-webhook-1
    command: n8n webhook
    volumes:
      - ./shared:/data/shared

  n8n-webhook-2:
    <<: *n8n-base
    container_name: n8n-webhook-2
    hostname: n8n-webhook-2
    command: n8n webhook
    volumes:
      - ./shared:/data/shared

  n8n-webhook-3:
    <<: *n8n-base
    container_name: n8n-webhook-3
    hostname: n8n-webhook-3
    command: n8n webhook
    volumes:
      - ./shared:/data/shared

  n8n-webhook-4:
    <<: *n8n-base
    container_name: n8n-webhook-4
    hostname: n8n-webhook-4
    command: n8n webhook
    volumes:
      - ./shared:/data/shared

  # AI Components
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    networks: ['n8n-network']
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ollama_storage:/root/.ollama
    profiles: ['${GPU_PROFILE}', 'cpu']
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

  ollama-cpu:
    image: ollama/ollama:latest
    container_name: ollama
    networks: ['n8n-network']
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ollama_storage:/root/.ollama
    profiles: ['cpu']

  # Ollama model puller
  ollama-pull:
    image: ollama/ollama:latest
    networks: ['n8n-network']
    container_name: ollama-pull
    volumes:
      - ollama_storage:/root/.ollama
    entrypoint: /bin/sh
    command:
      - "-c"
      - "sleep 5 && ollama pull llama3.2 && ollama pull nomic-embed-text"
    depends_on:
      - ollama
    profiles: ['${GPU_PROFILE}', 'cpu']

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
EOF

# Create startup script
print_message $YELLOW "📝 Creating startup script..."
cat > start.sh << EOF
#!/bin/bash
cd $INSTALL_DIR/self-hosted-ai-starter-kit
docker compose --profile ${GPU_PROFILE} up -d
EOF
chmod +x start.sh

# Create stop script
cat > stop.sh << EOF
#!/bin/bash
cd $INSTALL_DIR/self-hosted-ai-starter-kit
docker compose --profile ${GPU_PROFILE} down
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
docker compose --profile ${GPU_PROFILE} up -d

# Wait for services to be ready
print_message $YELLOW "⏳ Waiting for services to start..."
sleep 30

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
N8N Admin Password: [HIDDEN]

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

# Final output
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
print_message $BLUE "   GitHub: https://github.com/yourusername/onezipp-n8n-cluster"
