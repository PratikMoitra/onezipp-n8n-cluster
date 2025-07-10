#!/bin/bash

# Onezipp N8N Cluster Setup Script v2.1
# Sets up a production-ready n8n instance with clustering, SSL, backups, and AI capabilities
# Features: Dynamic worker/webhook scaling, automatic fixes, GitHub backup integration, binary data sharing
# Repository: https://github.com/PratikMoitra/onezipp-n8n-cluster
# Updated: Reflects current docker-compose.yml structure with proper binary data sharing

# =============================================================================
# Onezipp N8N Cluster Script - Production Ready Setup with Auto-Fix & Backup
# =============================================================================
# This script sets up n8n self-hosted AI starter kit with:
# - Caddy reverse proxy with SSL
# - N8N in queue mode with configurable worker and webhook nodes (1-10 each)
# - Redis for queue management
# - PostgreSQL database
# - Ollama, Qdrant for AI capabilities
# - FIXED: Proper binary data sharing across cluster nodes
# - FIXED: Image preview support with correct volume mounting
# - AUTO-FIX: Automatically fixes common errors and pushes to git
#   - Worker/webhook command issues
#   - GPU configuration problems
#   - Deprecated webhook URL variables
#   - Caddy port mismatches
#   - PostgreSQL password issues
#   - Encryption key mismatches
#   - Binary data directory creation
# - BACKUP: Automatic daily backups with easy restore capability
#   - Local backups with rotation (keeps last 7)
#   - Optional GitHub backup integration with encrypted token
#   - Configuration backups included
# - Fixed webhook URLs to use your domain instead of localhost
# - Optimized docker-compose with dynamic service generation
# - Proper volume mounting: shared_data for binary data, n8n_storage only for main
# - Uses loops for efficient configuration and management
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Git repository info (customize this for your own repo)
GIT_REPO_DIR="$HOME/onezipp-n8n-cluster"
GIT_REMOTE="https://github.com/PratikMoitra/onezipp-n8n-cluster.git"
SUMMARY_SHOWN=""

# Default values for worker and webhook counts
WORKER_COUNT=6
WEBHOOK_COUNT=6

# GitHub backup defaults
ENABLE_GITHUB_BACKUP="N"
GITHUB_TOKEN=""
GITHUB_BACKUP_REPO=""

# Banner
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║           🚀 Onezipp N8N Cluster Setup Script 🚀            ║"
echo "║         v2.1 with Binary Data Fix & Image Preview           ║"
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
    
    # Initialize git repo if it doesn't exist
    if [ ! -d "$GIT_REPO_DIR" ]; then
        mkdir -p "$GIT_REPO_DIR"
        cd "$GIT_REPO_DIR"
        git init
        git remote add origin "$GIT_REMOTE" 2>/dev/null || true
        cd "$current_dir"
    fi
    
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
    print_message $YELLOW "🔧 Fixing worker/webhook configurations..."
    
    cd "$INSTALL_DIR/self-hosted-ai-starter-kit"
    
    # Check if workers are using the old environment-based format
    if grep -q "EXECUTIONS_PROCESS=worker" docker-compose.yml; then
        print_message $YELLOW "Updating to command-based worker configuration..."
        
        # Get current worker and webhook counts
        local current_workers=$(grep -c "n8n-worker-" docker-compose.yml)
        local current_webhooks=$(grep -c "n8n-webhook-" docker-compose.yml)
        
        # Update workers to use command instead of EXECUTIONS_PROCESS
        for i in $(seq 1 $current_workers); do
            sed -i "/n8n-worker-$i:/,/restart: unless-stopped/ {
                /EXECUTIONS_PROCESS=worker/d
                /N8N_DISABLE_UI=true/d
                /N8N_DISABLE_EDITOR=true/d
            }" docker-compose.yml
            
            # Add command: worker if not present
            if ! grep -A 5 "n8n-worker-$i:" docker-compose.yml | grep -q "command: worker"; then
                sed -i "/n8n-worker-$i:/a\\    command: worker" docker-compose.yml
            fi
        done
        
        # Update webhooks to use command instead of EXECUTIONS_PROCESS
        for i in $(seq 1 $current_webhooks); do
            sed -i "/n8n-webhook-$i:/,/restart: unless-stopped/ {
                /EXECUTIONS_PROCESS=webhook/d
                /N8N_DISABLE_UI=true/d
                /N8N_DISABLE_EDITOR=true/d
            }" docker-compose.yml
            
            # Add command: webhook if not present
            if ! grep -A 5 "n8n-webhook-$i:" docker-compose.yml | grep -q "command: webhook"; then
                sed -i "/n8n-webhook-$i:/a\\    command: webhook" docker-compose.yml
            fi
        done
        
        push_fix_to_git "Updated to command-based worker/webhook configuration"
        return 0
    fi
    
    return 1
}

# Function to fix binary data directory
fix_binary_data_directory() {
    print_message $YELLOW "🔧 Fixing binary data directory..."
    
    cd "$INSTALL_DIR/self-hosted-ai-starter-kit"
    
    # Create binary data directory if it doesn't exist
    if ! docker exec n8n-main test -d /data/shared/binary-data 2>/dev/null; then
        print_message $YELLOW "Creating missing binary data directory..."
        
        docker exec n8n-main mkdir -p /data/shared/binary-data 2>/dev/null || true
        docker exec n8n-main chown -R node:node /data/shared/binary-data 2>/dev/null || true
        docker exec n8n-main chmod -R 755 /data/shared/binary-data 2>/dev/null || true
        
        push_fix_to_git "Created missing binary data directory"
        return 0
    fi
    
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

# Function to fix Caddy port mismatch
fix_caddy_ports() {
    print_message $YELLOW "🔧 Fixing Caddy proxy port configuration..."
    
    cd "$INSTALL_DIR/self-hosted-ai-starter-kit"
    
    # Check if Caddyfile is using port 5678 but n8n is on 443
    if grep -q "n8n-main:5678" caddy/Caddyfile && grep -q "N8N_PORT=443" .env; then
        print_message $YELLOW "Updating Caddyfile to use correct port 443..."
        
        # Update all references from 5678 to 443
        sed -i 's/:5678/:443/g' caddy/Caddyfile
        
        # Restart Caddy
        docker restart caddy
        
        push_fix_to_git "Fixed Caddy port configuration to match n8n port 443"
        return 0
    fi
    
    return 1
}

# Function to fix deprecated webhook URL variables
fix_webhook_urls() {
    print_message $YELLOW "🔧 Fixing deprecated webhook URL variables..."
    
    cd "$INSTALL_DIR/self-hosted-ai-starter-kit"
    
    # Check if .env has deprecated variables
    if grep -q "WEBHOOK_URL=\|N8N_WEBHOOK_URL=\|N8N_WEBHOOK_TUNNEL_URL=" .env; then
        print_message $YELLOW "Removing deprecated webhook URL variables from .env..."
        
        # Remove deprecated variables
        sed -i '/^WEBHOOK_URL=/d' .env
        sed -i '/^N8N_WEBHOOK_URL=/d' .env
        sed -i '/^N8N_WEBHOOK_TUNNEL_URL=/d' .env
        
        push_fix_to_git "Removed deprecated webhook URL variables"
    fi
    
    # Check if docker-compose.yml has deprecated variables
    if grep -q "WEBHOOK_URL\|N8N_WEBHOOK_URL\|N8N_WEBHOOK_TUNNEL_URL" docker-compose.yml; then
        print_message $YELLOW "Removing deprecated webhook URL variables from docker-compose.yml..."
        
        # Remove deprecated variable references
        sed -i '/- WEBHOOK_URL=/d' docker-compose.yml
        sed -i '/- N8N_WEBHOOK_URL=/d' docker-compose.yml
        sed -i '/- N8N_WEBHOOK_TUNNEL_URL=/d' docker-compose.yml
        
        push_fix_to_git "Removed deprecated webhook URL variables from docker-compose"
    fi
    
    return 0
}

# Function to fix encryption key mismatch
fix_encryption_key() {
    print_message $YELLOW "🔧 Checking for encryption key issues..."
    
    cd "$INSTALL_DIR/self-hosted-ai-starter-kit"
    
    # Check if main instance has encryption key mismatch
    if docker logs n8n-main 2>&1 | grep -q "Mismatching encryption keys"; then
        print_message $YELLOW "Encryption key mismatch detected. Fixing..."
        
        # Remove the old config file
        docker exec n8n-main rm -f /home/node/.n8n/config 2>/dev/null || true
        
        # Restart n8n-main to recreate config with current key
        docker restart n8n-main
        
        push_fix_to_git "Fixed encryption key mismatch"
        return 0
    fi
    
    return 1
}

# Function to fix PostgreSQL password issues
fix_postgres_password() {
    print_message $YELLOW "🔧 Checking PostgreSQL password configuration..."
    
    cd "$INSTALL_DIR/self-hosted-ai-starter-kit"
    
    # Check if containers are failing due to postgres auth
    if docker logs n8n-worker-1 2>&1 | grep -q "password authentication failed"; then
        print_message $YELLOW "PostgreSQL password mismatch detected. Attempting to fix..."
        
        # Get the current password from .env
        local CURRENT_PASSWORD=$(grep "^POSTGRES_PASSWORD=" .env | cut -d'=' -f2)
        
        # Try to update the PostgreSQL password
        if docker exec -it postgres psql -U postgres -c "ALTER USER n8n WITH PASSWORD '$CURRENT_PASSWORD';" 2>/dev/null; then
            print_message $GREEN "✅ PostgreSQL password updated successfully"
            
            # Get current counts
            local worker_count=$(docker ps -a --filter "name=n8n-worker-" -q | wc -l)
            local webhook_count=$(docker ps -a --filter "name=n8n-webhook-" -q | wc -l)
            
            # Restart all n8n services using loops
            docker restart n8n-main
            for i in $(seq 1 $worker_count); do
                docker restart n8n-worker-$i 2>/dev/null
            done
            for i in $(seq 1 $webhook_count); do
                docker restart n8n-webhook-$i 2>/dev/null
            done
            
            push_fix_to_git "Fixed PostgreSQL password mismatch"
            return 0
        else
            print_message $YELLOW "Could not update password. Database may need to be recreated."
            return 1
        fi
    fi
    
    return 0
}

# Function to fix container restart issues
fix_container_restarts() {
    print_message $YELLOW "🔧 Checking for restarting containers..."
    
    local restarting_containers=$(docker ps --format "table {{.Names}}" | grep -E "n8n-" | while read container; do
        if docker ps | grep "$container" | grep -q "Restarting"; then
            echo "$container"
        fi
    done)
    
    if [ -n "$restarting_containers" ]; then
        print_message $YELLOW "Found restarting containers. Attempting fixes..."
        
        # Try to fix encryption key issues first
        fix_encryption_key
        
        # Try to fix PostgreSQL password
        fix_postgres_password
        
        # Try to fix worker commands
        if fix_worker_commands; then
            docker compose down
            docker compose up -d
            sleep 30
        fi
        
        # Also fix webhook URLs
        fix_webhook_urls
        
        # Fix Caddy ports if needed
        fix_caddy_ports
        
        # Fix binary data directory
        fix_binary_data_directory
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
            fix_webhook_urls
            fix_caddy_ports
            fix_postgres_password
            fix_encryption_key
            fix_binary_data_directory
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

# Check OS compatibility
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ ! "$ID" =~ ^(ubuntu|debian)$ ]]; then
        print_message $YELLOW "⚠️  This script is tested on Ubuntu/Debian. Your OS: $ID"
        read -p "Continue anyway? (y/N) [N]: " CONTINUE_ANYWAY
        CONTINUE_ANYWAY=${CONTINUE_ANYWAY:-N}
        if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    print_message $YELLOW "⚠️  Cannot detect OS. This script is designed for Ubuntu/Debian."
    read -p "Continue anyway? (y/N) [N]: " CONTINUE_ANYWAY
    CONTINUE_ANYWAY=${CONTINUE_ANYWAY:-N}
    if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
        exit 1
    fi
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

# Define required packages
REQUIRED_PACKAGES=(
    "curl"
    "git"
    "ca-certificates"
    "gnupg"
    "lsb-release"
    "openssl"
    "jq"
)

# Install required packages using loop
print_message $YELLOW "📦 Installing required packages..."
for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii  $package"; then
        print_message $YELLOW "   Installing $package..."
        apt-get install -y -qq "$package" || true
    else
        print_message $GREEN "   ✓ $package already installed"
    fi
done

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
EXISTING_POSTGRES_PASSWORD=""
EXISTING_REDIS_PASSWORD=""
EXISTING_ENCRYPTION_KEY=""
EXISTING_JWT_SECRET=""
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
    # Try to extract existing configurations
    EXISTING_PASSWORD=$(grep "N8N Admin Password:" "$INSTALL_DIR/config-summary.txt" | cut -d' ' -f4)
    EXISTING_POSTGRES_PASSWORD=$(grep "PostgreSQL Password:" "$INSTALL_DIR/config-summary.txt" | cut -d' ' -f3)
    EXISTING_REDIS_PASSWORD=$(grep "Redis Password:" "$INSTALL_DIR/config-summary.txt" | cut -d' ' -f3)
    EXISTING_ENCRYPTION_KEY=$(grep "N8N Encryption Key:" "$INSTALL_DIR/config-summary.txt" | cut -d' ' -f4)
    EXISTING_JWT_SECRET=$(grep "N8N JWT Secret:" "$INSTALL_DIR/config-summary.txt" | cut -d' ' -f4)
fi

# Load existing cluster configuration
if [ -f "$INSTALL_DIR/cluster-config" ]; then
    source "$INSTALL_DIR/cluster-config"
    print_message $YELLOW "📊 Found existing cluster config: $WORKER_COUNT workers, $WEBHOOK_COUNT webhooks"
fi

# Also check existing .env file as it's more reliable
if [ -f "$INSTALL_DIR/self-hosted-ai-starter-kit/.env" ]; then
    print_message $YELLOW "📄 Found existing .env file. Extracting configuration..."
    source "$INSTALL_DIR/self-hosted-ai-starter-kit/.env" 2>/dev/null || true
    # Use .env values if they exist and summary values don't
    [ -z "$EXISTING_POSTGRES_PASSWORD" ] && [ -n "$POSTGRES_PASSWORD" ] && EXISTING_POSTGRES_PASSWORD=$POSTGRES_PASSWORD
    [ -z "$EXISTING_REDIS_PASSWORD" ] && [ -n "$REDIS_PASSWORD" ] && EXISTING_REDIS_PASSWORD=$REDIS_PASSWORD
    [ -z "$EXISTING_ENCRYPTION_KEY" ] && [ -n "$N8N_ENCRYPTION_KEY" ] && EXISTING_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
    [ -z "$EXISTING_JWT_SECRET" ] && [ -n "$N8N_USER_MANAGEMENT_JWT_SECRET" ] && EXISTING_JWT_SECRET=$N8N_USER_MANAGEMENT_JWT_SECRET
    [ -z "$EXISTING_PASSWORD" ] && [ -n "$N8N_BASIC_AUTH_PASSWORD" ] && EXISTING_PASSWORD=$N8N_BASIC_AUTH_PASSWORD
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

# Use existing configurations if found, otherwise generate new
if [ -n "$EXISTING_POSTGRES_PASSWORD" ]; then
    POSTGRES_PASSWORD=$EXISTING_POSTGRES_PASSWORD
    print_message $YELLOW "Using existing PostgreSQL password from previous installation"
else
    POSTGRES_PASSWORD=$(generate_random_string 24)
fi

if [ -n "$EXISTING_REDIS_PASSWORD" ]; then
    REDIS_PASSWORD=$EXISTING_REDIS_PASSWORD
    print_message $YELLOW "Using existing Redis password from previous installation"
else
    REDIS_PASSWORD=$(generate_random_string 24)
fi

if [ -n "$EXISTING_ENCRYPTION_KEY" ]; then
    N8N_ENCRYPTION_KEY=$EXISTING_ENCRYPTION_KEY
    print_message $YELLOW "Using existing encryption key from previous installation"
else
    N8N_ENCRYPTION_KEY=$(generate_random_string 32)
fi

if [ -n "$EXISTING_JWT_SECRET" ]; then
    N8N_JWT_SECRET=$EXISTING_JWT_SECRET
    print_message $YELLOW "Using existing JWT secret from previous installation"
else
    N8N_JWT_SECRET=$(generate_random_string 32)
fi

# Worker and webhook configuration
print_section "Worker and Webhook Configuration"

# Get number of workers
while true; do
    read -p "How many worker nodes do you want? (1-10) [$WORKER_COUNT]: " NEW_WORKER_COUNT
    NEW_WORKER_COUNT=${NEW_WORKER_COUNT:-$WORKER_COUNT}
    if [[ "$NEW_WORKER_COUNT" =~ ^[0-9]+$ ]] && [ "$NEW_WORKER_COUNT" -ge 1 ] && [ "$NEW_WORKER_COUNT" -le 10 ]; then
        WORKER_COUNT=$NEW_WORKER_COUNT
        print_message $GREEN "✅ Setting up $WORKER_COUNT worker nodes"
        break
    else
        print_message $RED "❌ Please enter a number between 1 and 10"
    fi
done

# Get number of webhooks
while true; do
    read -p "How many webhook nodes do you want? (1-10) [$WEBHOOK_COUNT]: " NEW_WEBHOOK_COUNT
    NEW_WEBHOOK_COUNT=${NEW_WEBHOOK_COUNT:-$WEBHOOK_COUNT}
    if [[ "$NEW_WEBHOOK_COUNT" =~ ^[0-9]+$ ]] && [ "$NEW_WEBHOOK_COUNT" -ge 1 ] && [ "$NEW_WEBHOOK_COUNT" -le 10 ]; then
        WEBHOOK_COUNT=$NEW_WEBHOOK_COUNT
        print_message $GREEN "✅ Setting up $WEBHOOK_COUNT webhook nodes"
        break
    else
        print_message $RED "❌ Please enter a number between 1 and 10"
    fi
done

# GitHub backup configuration
print_section "GitHub Backup Configuration"
print_message $YELLOW "💡 Backups can be automatically pushed to your GitHub repository"
print_message $YELLOW "   This requires a GitHub Personal Access Token with 'repo' scope"
print_message $YELLOW "   Create one at: https://github.com/settings/tokens"
echo ""

read -p "Enable GitHub backup? (y/N) [N]: " ENABLE_GITHUB_BACKUP
ENABLE_GITHUB_BACKUP=${ENABLE_GITHUB_BACKUP:-N}

GITHUB_TOKEN=""
GITHUB_BACKUP_REPO=""
if [[ "$ENABLE_GITHUB_BACKUP" =~ ^[Yy]$ ]]; then
    # Check for existing encrypted token
    if [ -f "$INSTALL_DIR/.github-token.enc" ]; then
        print_message $YELLOW "📦 Found existing GitHub token configuration"
        read -p "Use existing token? (Y/n) [Y]: " USE_EXISTING_TOKEN
        USE_EXISTING_TOKEN=${USE_EXISTING_TOKEN:-Y}
        
        if [[ "$USE_EXISTING_TOKEN" =~ ^[Yy]$ ]]; then
            # Decrypt existing token
            GITHUB_TOKEN=$(openssl enc -aes-256-cbc -d -in "$INSTALL_DIR/.github-token.enc" -k "${DOMAIN}${N8N_ENCRYPTION_KEY}" 2>/dev/null || echo "")
            if [ -f "$INSTALL_DIR/.github-repo" ]; then
                GITHUB_BACKUP_REPO=$(cat "$INSTALL_DIR/.github-repo")
            fi
        fi
    fi
    
    if [ -z "$GITHUB_TOKEN" ]; then
        read -s -p "Enter your GitHub Personal Access Token: " GITHUB_TOKEN
        echo
        read -p "Enter backup repository (e.g., username/repo-name): " GITHUB_BACKUP_REPO
        
        # Encrypt and save token
        echo -n "$GITHUB_TOKEN" | openssl enc -aes-256-cbc -e -out "$INSTALL_DIR/.github-token.enc" -k "${DOMAIN}${N8N_ENCRYPTION_KEY}"
        echo -n "$GITHUB_BACKUP_REPO" > "$INSTALL_DIR/.github-repo"
        chmod 600 "$INSTALL_DIR/.github-token.enc"
        chmod 600 "$INSTALL_DIR/.github-repo"
        
        print_message $GREEN "✅ GitHub token encrypted and saved"
    fi
fi

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

# Save cluster configuration early for recovery
cat > $INSTALL_DIR/cluster-config << EOF
WORKER_COUNT=${WORKER_COUNT}
WEBHOOK_COUNT=${WEBHOOK_COUNT}
EOF

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
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=${N8N_ADMIN_EMAIL}
N8N_BASIC_AUTH_PASSWORD=${N8N_ADMIN_PASSWORD}
N8N_RUNNERS_ENABLED=true
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

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
N8N_EDITOR_BASE_URL=https://${DOMAIN}
N8N_WEBHOOK_BASE_URL=https://${DOMAIN}
N8N_HOST=${DOMAIN}
N8N_PROTOCOL=https
N8N_PORT=443

# Binary Data Configuration (Fixed for Cluster)
N8N_DEFAULT_BINARY_DATA_MODE=filesystem
N8N_BINARY_DATA_BASE_PATH=/data/shared/binary-data
N8N_BINARY_DATA_SIZE_LIMIT=50000000
N8N_PAYLOAD_SIZE_MAX=100000000
N8N_MAX_BODY_SIZE=100MB
N8N_FILE_STORE_MODE=filesystem

# Image Preview Configuration
N8N_DISABLE_STATIC_BINARY_DATA_IMAGES=false
N8N_STATIC_CACHE_BINARY_DATA_TTL=86400000
N8N_SECURITY_AUDIT_DAYS=0
N8N_CORS_ORIGIN=*

# GPU Profile
GPU_PROFILE=${GPU_PROFILE}

# Database type configuration
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
DB_POSTGRESDB_DATABASE=n8n
EOF

# Create Caddyfile
print_message $YELLOW "📝 Creating Caddyfile..."
mkdir -p caddy

# Start creating Caddyfile
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
    
    # API and WebSocket to main instance
    reverse_proxy @api n8n-main:443
    reverse_proxy @websocket n8n-main:443
    
    # Load balance webhook requests across webhook processors
    reverse_proxy /webhook/* {
EOF

# Add webhook nodes to load balancer using loop
for i in $(seq 1 $WEBHOOK_COUNT); do
    echo "        to n8n-webhook-$i:443" >> caddy/Caddyfile
done

# Complete Caddyfile
cat >> caddy/Caddyfile << EOF
        lb_policy round_robin
        health_uri /healthz
        health_interval 10s
        health_timeout 5s
    }
    
    # Default to main instance for everything else
    reverse_proxy n8n-main:443
    
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

# Create base docker-compose
cat > docker-compose.yml << 'DOCKERCOMPOSE_EOF'
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
    env_file:
      - .env
    volumes:
      - postgres_storage:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-n8n} -d ${POSTGRES_DB:-n8n}"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis for Queue Management
  redis:
    image: redis:7-alpine
    container_name: redis
    networks: ['n8n-network']
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD:-redis_password}
    volumes:
      - redis_storage:/data
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "-a", "${REDIS_PASSWORD:-redis_password}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # N8N Main Instance (UI/API)
  n8n-main:
    image: n8nio/n8n:latest
    container_name: n8n-main
    hostname: n8n-main
    networks: ['n8n-network']
    ports:
      - "5678:443"
    volumes:
      - n8n_storage:/home/node/.n8n
      - shared_data:/data/shared
    env_file:
      - .env
    environment:
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD:-redis_password}
      - QUEUE_HEALTH_CHECK_ACTIVE=true
      # Binary data configuration
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
      - N8N_BINARY_DATA_BASE_PATH=/data/shared/binary-data
      # Image preview configuration
      - N8N_DISABLE_STATIC_BINARY_DATA_IMAGES=false
      - N8N_STATIC_CACHE_BINARY_DATA_TTL=86400000
      - N8N_SECURITY_AUDIT_DAYS=0
      - N8N_CORS_ORIGIN=*
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped

DOCKERCOMPOSE_EOF

# Add worker nodes using loop with current command-based structure
print_message $YELLOW "📝 Adding $WORKER_COUNT worker nodes..."
for i in $(seq 1 $WORKER_COUNT); do
    cat >> docker-compose.yml << EOF
  # N8N Worker Node $i
  n8n-worker-$i:
    image: n8nio/n8n:latest
    command: worker
    container_name: n8n-worker-$i
    hostname: n8n-worker-$i
    networks: ['n8n-network']
    volumes:
      - shared_data:/data/shared
    env_file:
      - .env
    environment:
      - N8N_RUNNERS_MODE=queue
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD:-redis_password}
      - QUEUE_HEALTH_CHECK_ACTIVE=true
      # Binary data configuration
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
      - N8N_BINARY_DATA_BASE_PATH=/data/shared/binary-data
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped

EOF
done

# Add webhook nodes using loop with current command-based structure
print_message $YELLOW "📝 Adding $WEBHOOK_COUNT webhook nodes..."
for i in $(seq 1 $WEBHOOK_COUNT); do
    cat >> docker-compose.yml << EOF
  # N8N Webhook Processor Node $i
  n8n-webhook-$i:
    image: n8nio/n8n:latest
    command: webhook
    container_name: n8n-webhook-$i
    hostname: n8n-webhook-$i
    networks: ['n8n-network']
    volumes:
      - shared_data:/data/shared
    env_file:
      - .env
    environment:
      - N8N_RUNNERS_MODE=webhook
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD:-redis_password}
      - QUEUE_HEALTH_CHECK_ACTIVE=true
      # Binary data configuration
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
      - N8N_BINARY_DATA_BASE_PATH=/data/shared/binary-data
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped

EOF
done

# Add Ollama and remaining services with proper GPU profile support
cat >> docker-compose.yml << 'DOCKERCOMPOSE_OLLAMA_EOF'
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
DOCKERCOMPOSE_OLLAMA_EOF

# Add GPU configuration only if GPU is selected
if [ "$GPU_PROFILE" = "gpu-nvidia" ]; then
    cat >> docker-compose.yml << 'GPU_NVIDIA_EOF'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
        limits:
          memory: 4G
    profiles: ['gpu-nvidia']
GPU_NVIDIA_EOF
elif [ "$GPU_PROFILE" = "gpu-amd" ]; then
    cat >> docker-compose.yml << 'GPU_AMD_EOF'
    devices:
      - /dev/kfd
      - /dev/dri
    group_add:
      - video
      - render
    profiles: ['gpu-amd']
GPU_AMD_EOF
else
    cat >> docker-compose.yml << 'CPU_PROFILE_EOF'
    profiles: ['cpu']
CPU_PROFILE_EOF
fi

# Continue with the rest of docker-compose.yml
cat >> docker-compose.yml << 'DOCKERCOMPOSE_FINAL_EOF'

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
    profiles: ['cpu', 'gpu-nvidia', 'gpu-amd']

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
  shared_data:
  postgres_storage:
  redis_storage:
  ollama_storage:
  qdrant_storage:
  caddy_data:
  caddy_config:

networks:
  n8n-network:
    driver: bridge
DOCKERCOMPOSE_FINAL_EOF

# Create startup script
print_message $YELLOW "📝 Creating startup script..."
cat > start.sh << 'STARTUP_EOF'
#!/bin/bash
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit

# Function to wait for service
wait_for_service() {
    local service=$1
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if docker ps | grep -q "$service"; then
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Get GPU profile from .env
GPU_PROFILE=$(grep "^GPU_PROFILE=" .env | cut -d'=' -f2)

# Start base services first
docker compose up -d postgres redis

# Wait for database to be ready
echo "Waiting for database..."
until docker exec postgres pg_isready -U n8n >/dev/null 2>&1; do
    sleep 1
done

# Start services with appropriate profile
if [ "$GPU_PROFILE" != "cpu" ]; then
    echo "Starting with GPU profile: $GPU_PROFILE"
    docker compose --profile "$GPU_PROFILE" up -d
else
    echo "Starting with CPU profile"
    docker compose --profile cpu up -d
fi

# Verify critical services
for service in postgres redis n8n-main caddy; do
    if wait_for_service $service; then
        echo "✓ $service started"
    else
        echo "✗ Failed to start $service"
        exit 1
    fi
done

# Create binary data directory if it doesn't exist
docker exec n8n-main mkdir -p /data/shared/binary-data 2>/dev/null || true
docker exec n8n-main chown -R node:node /data/shared/binary-data 2>/dev/null || true
docker exec n8n-main chmod -R 755 /data/shared/binary-data 2>/dev/null || true

echo "All services started successfully"
STARTUP_EOF
chmod +x start.sh

# Create stop script
cat > stop.sh << 'SHUTDOWN_EOF'
#!/bin/bash
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit

# Stop all services gracefully
docker compose down

# Wait for containers to stop
sleep 5

# Force stop any remaining containers
docker ps -a | grep "n8n-" | awk '{print $1}' | xargs -r docker stop 2>/dev/null

echo "All services stopped"
SHUTDOWN_EOF
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

# Create backup script and configuration
print_section "Setting up Automatic Backups"
print_message $YELLOW "🔧 Creating backup script..."

# Create backup directory
mkdir -p $INSTALL_DIR/backups

# Create backup script
cat > $INSTALL_DIR/backup-n8n.sh << 'BACKUP_EOF'
#!/bin/bash
BACKUP_DIR="/opt/onezipp-n8n/backups"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$BACKUP_DIR/backup.log"
INSTALL_DIR="/opt/onezipp-n8n"

mkdir -p $BACKUP_DIR

echo "[$(date)] Starting backup..." >> $LOG_FILE

# Backup n8n data
docker run --rm -v self-hosted-ai-starter-kit_n8n_storage:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/n8n-backup-$DATE.tar.gz /data 2>> $LOG_FILE

if [ $? -eq 0 ]; then
    echo "[$(date)] Backup completed: n8n-backup-$DATE.tar.gz" >> $LOG_FILE
    
    # Keep only last 7 backups
    ls -t $BACKUP_DIR/n8n-backup-*.tar.gz | tail -n +8 | xargs -r rm
    echo "[$(date)] Cleanup completed. Kept last 7 backups." >> $LOG_FILE
else
    echo "[$(date)] Backup failed!" >> $LOG_FILE
fi

# Also backup PostgreSQL
docker exec postgres pg_dump -U n8n n8n | gzip > $BACKUP_DIR/postgres-backup-$DATE.sql.gz 2>> $LOG_FILE

if [ $? -eq 0 ]; then
    echo "[$(date)] PostgreSQL backup completed: postgres-backup-$DATE.sql.gz" >> $LOG_FILE
    
    # Keep only last 7 PostgreSQL backups
    ls -t $BACKUP_DIR/postgres-backup-*.sql.gz | tail -n +8 | xargs -r rm
else
    echo "[$(date)] PostgreSQL backup failed!" >> $LOG_FILE
fi

# Backup shared data (binary files)
docker run --rm -v self-hosted-ai-starter-kit_shared_data:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/shared-data-backup-$DATE.tar.gz /data 2>> $LOG_FILE

if [ $? -eq 0 ]; then
    echo "[$(date)] Shared data backup completed: shared-data-backup-$DATE.tar.gz" >> $LOG_FILE
    
    # Keep only last 7 shared data backups
    ls -t $BACKUP_DIR/shared-data-backup-*.tar.gz | tail -n +8 | xargs -r rm
else
    echo "[$(date)] Shared data backup failed!" >> $LOG_FILE
fi

# Backup configurations
CONFIG_BACKUP_DIR="$BACKUP_DIR/configs-$DATE"
mkdir -p "$CONFIG_BACKUP_DIR"
cp "$INSTALL_DIR/self-hosted-ai-starter-kit/.env" "$CONFIG_BACKUP_DIR/" 2>/dev/null
cp "$INSTALL_DIR/self-hosted-ai-starter-kit/docker-compose.yml" "$CONFIG_BACKUP_DIR/" 2>/dev/null
cp -r "$INSTALL_DIR/self-hosted-ai-starter-kit/caddy" "$CONFIG_BACKUP_DIR/" 2>/dev/null
cp "$INSTALL_DIR/config-summary.txt" "$CONFIG_BACKUP_DIR/" 2>/dev/null

# Create a tarball of configs
tar czf "$BACKUP_DIR/configs-backup-$DATE.tar.gz" -C "$BACKUP_DIR" "configs-$DATE" 2>> $LOG_FILE
rm -rf "$CONFIG_BACKUP_DIR"

# GitHub backup if configured
if [ -f "$INSTALL_DIR/.github-token.enc" ] && [ -f "$INSTALL_DIR/.github-repo" ]; then
    echo "[$(date)] Starting GitHub backup..." >> $LOG_FILE
    
    # Decrypt token (using domain and encryption key as password)
    DOMAIN=$(grep "^DOMAIN=" "$INSTALL_DIR/self-hosted-ai-starter-kit/.env" | cut -d'=' -f2)
    ENCRYPTION_KEY=$(grep "^N8N_ENCRYPTION_KEY=" "$INSTALL_DIR/self-hosted-ai-starter-kit/.env" | cut -d'=' -f2)
    GITHUB_TOKEN=$(openssl enc -aes-256-cbc -d -in "$INSTALL_DIR/.github-token.enc" -k "${DOMAIN}${ENCRYPTION_KEY}" 2>/dev/null)
    GITHUB_REPO=$(cat "$INSTALL_DIR/.github-repo")
    
    if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
        # Create temp directory for git operations
        TEMP_GIT_DIR=$(mktemp -d)
        cd "$TEMP_GIT_DIR"
        
        # Clone or create repo
        git clone "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" backup-repo 2>> $LOG_FILE || {
            mkdir backup-repo
            cd backup-repo
            git init
            git remote add origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"
            cd ..
        }
        
        cd backup-repo
        
        # Create backup structure
        mkdir -p "$(hostname)/$(date +%Y-%m)"
        
        # Copy backups
        cp "$BACKUP_DIR/n8n-backup-$DATE.tar.gz" "$(hostname)/$(date +%Y-%m)/" 2>/dev/null
        cp "$BACKUP_DIR/postgres-backup-$DATE.sql.gz" "$(hostname)/$(date +%Y-%m)/" 2>/dev/null
        cp "$BACKUP_DIR/shared-data-backup-$DATE.tar.gz" "$(hostname)/$(date +%Y-%m)/" 2>/dev/null
        cp "$BACKUP_DIR/configs-backup-$DATE.tar.gz" "$(hostname)/$(date +%Y-%m)/" 2>/dev/null
        
        # Create backup manifest
        cat > "$(hostname)/$(date +%Y-%m)/backup-manifest-$DATE.txt" << MANIFEST
Backup Date: $(date)
Hostname: $(hostname)
Domain: $DOMAIN
N8N Version: $(docker exec n8n-main n8n --version 2>/dev/null || echo "unknown")
Worker Count: $(docker ps --filter "name=n8n-worker" -q | wc -l)
Webhook Count: $(docker ps --filter "name=n8n-webhook" -q | wc -l)

Files:
- n8n-backup-$DATE.tar.gz
- postgres-backup-$DATE.sql.gz
- shared-data-backup-$DATE.tar.gz
- configs-backup-$DATE.tar.gz
MANIFEST
        
        # Commit and push
        git config user.email "backup@$(hostname)"
        git config user.name "N8N Backup Bot"
        git add .
        git commit -m "Backup from $(hostname) - $DATE" >> $LOG_FILE 2>&1
        git push origin main >> $LOG_FILE 2>&1
        
        if [ $? -eq 0 ]; then
            echo "[$(date)] GitHub backup completed successfully" >> $LOG_FILE
        else
            echo "[$(date)] GitHub backup push failed" >> $LOG_FILE
        fi
        
        # Cleanup
        cd /
        rm -rf "$TEMP_GIT_DIR"
    else
        echo "[$(date)] GitHub backup skipped - token decryption failed" >> $LOG_FILE
    fi
fi

echo "[$(date)] Backup process finished." >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE
BACKUP_EOF

chmod +x $INSTALL_DIR/backup-n8n.sh

# Create restore script
cat > $INSTALL_DIR/restore-n8n.sh << 'RESTORE_EOF'
#!/bin/bash
BACKUP_DIR="/opt/onezipp-n8n/backups"
INSTALL_DIR="/opt/onezipp-n8n"

# Function to list GitHub backups
list_github_backups() {
    if [ -f "$INSTALL_DIR/.github-token.enc" ] && [ -f "$INSTALL_DIR/.github-repo" ]; then
        # Decrypt token
        DOMAIN=$(grep "^DOMAIN=" "$INSTALL_DIR/self-hosted-ai-starter-kit/.env" | cut -d'=' -f2)
        ENCRYPTION_KEY=$(grep "^N8N_ENCRYPTION_KEY=" "$INSTALL_DIR/self-hosted-ai-starter-kit/.env" | cut -d'=' -f2)
        GITHUB_TOKEN=$(openssl enc -aes-256-cbc -d -in "$INSTALL_DIR/.github-token.enc" -k "${DOMAIN}${ENCRYPTION_KEY}" 2>/dev/null)
        GITHUB_REPO=$(cat "$INSTALL_DIR/.github-repo")
        
        if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
            echo "GitHub backups available:"
            TEMP_DIR=$(mktemp -d)
            cd "$TEMP_DIR"
            git clone -q "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" backup-repo 2>/dev/null
            if [ -d "backup-repo/$(hostname)" ]; then
                find "backup-repo/$(hostname)" -name "backup-manifest-*.txt" | while read manifest; do
                    echo "  - $(basename $(dirname "$manifest"))/$(basename "$manifest" .txt | sed 's/backup-manifest-//')"
                done
            fi
            rm -rf "$TEMP_DIR"
        fi
    fi
}

# Check arguments
if [ -z "$1" ]; then
    echo "Usage: $0 <backup-date> [--from-github]"
    echo ""
    echo "Local backups:"
    ls -la $BACKUP_DIR/n8n-backup-*.tar.gz 2>/dev/null | awk '{print "  - " $9}' | sed 's/.*n8n-backup-//' | sed 's/.tar.gz//'
    echo ""
    list_github_backups
    exit 1
fi

BACKUP_DATE=$1
FROM_GITHUB=false
if [ "$2" = "--from-github" ]; then
    FROM_GITHUB=true
fi

# Handle GitHub restore
if $FROM_GITHUB; then
    if [ -f "$INSTALL_DIR/.github-token.enc" ] && [ -f "$INSTALL_DIR/.github-repo" ]; then
        # Decrypt token and clone
        DOMAIN=$(grep "^DOMAIN=" "$INSTALL_DIR/self-hosted-ai-starter-kit/.env" | cut -d'=' -f2)
        ENCRYPTION_KEY=$(grep "^N8N_ENCRYPTION_KEY=" "$INSTALL_DIR/self-hosted-ai-starter-kit/.env" | cut -d'=' -f2)
        GITHUB_TOKEN=$(openssl enc -aes-256-cbc -d -in "$INSTALL_DIR/.github-token.enc" -k "${DOMAIN}${ENCRYPTION_KEY}" 2>/dev/null)
        GITHUB_REPO=$(cat "$INSTALL_DIR/.github-repo")
        
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        echo "Fetching backup from GitHub..."
        git clone -q "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" backup-repo 2>/dev/null
        
        # Find backup files
        YEAR_MONTH=$(echo $BACKUP_DATE | cut -c1-7)
        BACKUP_PATH="backup-repo/$(hostname)/$YEAR_MONTH"
        
        if [ -d "$BACKUP_PATH" ]; then
            cp "$BACKUP_PATH"/*-backup-$BACKUP_DATE.* "$BACKUP_DIR/" 2>/dev/null
            echo "Downloaded backups from GitHub"
        else
            echo "Error: Backup not found in GitHub repository"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        
        rm -rf "$TEMP_DIR"
    else
        echo "Error: GitHub backup not configured"
        exit 1
    fi
fi

N8N_BACKUP="$BACKUP_DIR/n8n-backup-$BACKUP_DATE.tar.gz"
PG_BACKUP="$BACKUP_DIR/postgres-backup-$BACKUP_DATE.sql.gz"
SHARED_BACKUP="$BACKUP_DIR/shared-data-backup-$BACKUP_DATE.tar.gz"

if [ ! -f "$N8N_BACKUP" ]; then
    echo "Error: Backup file $N8N_BACKUP not found!"
    exit 1
fi

echo "Restoring from backup: $BACKUP_DATE"
read -p "This will overwrite current data. Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Stop all n8n services
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit
echo "Stopping n8n services..."
docker compose stop $(docker compose ps --services | grep -E "n8n-main|n8n-worker|n8n-webhook")

# Restore n8n data
echo "Restoring n8n data..."
docker run --rm -v self-hosted-ai-starter-kit_n8n_storage:/data -v $BACKUP_DIR:/backup alpine sh -c "rm -rf /data/* && tar xzf /backup/n8n-backup-$BACKUP_DATE.tar.gz -C /"

# Restore shared data if backup exists
if [ -f "$SHARED_BACKUP" ]; then
    echo "Restoring shared data..."
    docker run --rm -v self-hosted-ai-starter-kit_shared_data:/data -v $BACKUP_DIR:/backup alpine sh -c "rm -rf /data/* && tar xzf /backup/shared-data-backup-$BACKUP_DATE.tar.gz -C /"
fi

# Restore PostgreSQL if backup exists
if [ -f "$PG_BACKUP" ]; then
    echo "Restoring PostgreSQL data..."
    gunzip < $PG_BACKUP | docker exec -i postgres psql -U n8n n8n
fi

# Restore configuration if exists
CONFIG_BACKUP="$BACKUP_DIR/configs-backup-$BACKUP_DATE.tar.gz"
if [ -f "$CONFIG_BACKUP" ]; then
    echo "Restoring configuration files..."
    TEMP_RESTORE=$(mktemp -d)
    tar xzf "$CONFIG_BACKUP" -C "$TEMP_RESTORE"
    
    # Ask before overwriting config
    read -p "Restore configuration files (.env, docker-compose.yml)? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp "$TEMP_RESTORE/configs-$BACKUP_DATE/.env" ./ 2>/dev/null
        cp "$TEMP_RESTORE/configs-$BACKUP_DATE/docker-compose.yml" ./ 2>/dev/null
        cp -r "$TEMP_RESTORE/configs-$BACKUP_DATE/caddy" ./ 2>/dev/null
    fi
    
    rm -rf "$TEMP_RESTORE"
fi

# Start services
echo "Starting services..."
docker compose up -d

# Recreate binary data directory with proper permissions
sleep 10
docker exec n8n-main mkdir -p /data/shared/binary-data 2>/dev/null || true
docker exec n8n-main chown -R node:node /data/shared/binary-data 2>/dev/null || true
docker exec n8n-main chmod -R 755 /data/shared/binary-data 2>/dev/null || true

echo "Restore completed!"
echo "Please wait a few moments for all services to start."
RESTORE_EOF

chmod +x $INSTALL_DIR/restore-n8n.sh

# Add to cron for daily backups at 2 AM
print_message $YELLOW "📅 Setting up daily automatic backups..."
(crontab -l 2>/dev/null | grep -v "backup-n8n.sh"; echo "0 2 * * * $INSTALL_DIR/backup-n8n.sh") | crontab -

# Configure firewall
print_section "Configuring Firewall"
if command_exists ufw; then
    print_message $YELLOW "🔥 Configuring UFW firewall..."
    ufw --force enable
    
    # Define required ports
    FIREWALL_PORTS=(
        "22/tcp"    # SSH
        "80/tcp"    # HTTP
        "443/tcp"   # HTTPS
    )
    
    # Open ports using loop
    for port in "${FIREWALL_PORTS[@]}"; do
        print_message $YELLOW "   Opening port $port..."
        ufw allow $port
    done
    
    ufw reload
    print_message $GREEN "✅ Firewall configured"
else
    print_message $YELLOW "⚠️  UFW not found. Please configure your firewall manually."
    print_message $YELLOW "   Required ports: 22 (SSH), 80 (HTTP), 443 (HTTPS)"
fi

# Start services
print_section "Starting Services"
print_message $YELLOW "🚀 Starting Onezipp N8N Cluster..."
systemctl daemon-reload
systemctl enable onezipp-n8n.service
cd $INSTALL_DIR/self-hosted-ai-starter-kit

# Start services with GPU profile support
if [ "$GPU_PROFILE" != "cpu" ]; then
    print_message $YELLOW "Starting services with GPU profile: $GPU_PROFILE"
    if ! docker compose --profile "$GPU_PROFILE" up -d; then
        print_message $RED "❌ Initial startup failed. Attempting fixes..."
        fix_gpu_config
        fix_webhook_urls
        fix_caddy_ports
        fix_binary_data_directory
        docker compose --profile "$GPU_PROFILE" up -d
    fi
else
    print_message $YELLOW "Starting services with CPU profile"
    if ! docker compose --profile cpu up -d; then
        print_message $RED "❌ Initial startup failed. Attempting fixes..."
        fix_gpu_config
        fix_webhook_urls
        fix_caddy_ports
        fix_binary_data_directory
        docker compose --profile cpu up -d
    fi
fi

# Wait for services to be ready
print_message $YELLOW "⏳ Waiting for services to start..."
sleep 45

# Create binary data directory and set permissions
print_message $YELLOW "🗂️  Setting up binary data directory..."
docker exec n8n-main mkdir -p /data/shared/binary-data 2>/dev/null || true
docker exec n8n-main chown -R node:node /data/shared/binary-data 2>/dev/null || true
docker exec n8n-main chmod -R 755 /data/shared/binary-data 2>/dev/null || true

# Check for issues and auto-fix
fix_container_restarts
fix_webhook_urls
fix_caddy_ports
fix_binary_data_directory

# Check service status
print_section "Service Status Check"

# Base services array
BASE_SERVICES=("caddy" "postgres" "redis" "n8n-main" "ollama" "qdrant")

# Add worker services using loop
WORKER_SERVICES=()
for i in $(seq 1 $WORKER_COUNT); do
    WORKER_SERVICES+=("n8n-worker-$i")
done

# Add webhook services using loop
WEBHOOK_SERVICES=()
for i in $(seq 1 $WEBHOOK_COUNT); do
    WEBHOOK_SERVICES+=("n8n-webhook-$i")
done

# Combine all services
ALL_SERVICES=("${BASE_SERVICES[@]}" "${WORKER_SERVICES[@]}" "${WEBHOOK_SERVICES[@]}")

# Check status for all services
for service in "${ALL_SERVICES[@]}"; do
    if docker ps | grep -q $service; then
        print_message $GREEN "✅ $service is running"
    else
        print_message $RED "❌ $service is not running"
    fi
done

# Verify binary data directory
print_message $YELLOW "🔍 Verifying binary data setup..."
if docker exec n8n-main test -d /data/shared/binary-data; then
    print_message $GREEN "✅ Binary data directory exists"
    docker exec n8n-main ls -la /data/shared/binary-data/ || print_message $YELLOW "Directory is empty (normal for new installation)"
else
    print_message $RED "❌ Binary data directory missing - creating now..."
    fix_binary_data_directory
fi

# Save configuration summary
print_section "Saving Configuration"
cat > $INSTALL_DIR/config-summary.txt << EOF
Onezipp N8N Cluster Configuration Summary v2.1
==============================================
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
Worker Nodes: ${WORKER_COUNT}
Webhook Nodes: ${WEBHOOK_COUNT}

Binary Data Configuration: FIXED
- Shared storage: /data/shared/binary-data
- Image preview: ENABLED
- Volume mapping: shared_data for binary files, n8n_storage for main instance only

Service URLs:
- N8N UI: https://${DOMAIN}
- Webhook Base URL: https://${DOMAIN}
- Ollama API: http://localhost:11434
- Qdrant API: http://localhost:6333

Commands:
- Start services: systemctl start onezipp-n8n
- Stop services: systemctl stop onezipp-n8n
- View logs: docker compose -f $INSTALL_DIR/self-hosted-ai-starter-kit/docker-compose.yml logs -f
- Restart services: systemctl restart onezipp-n8n

Backup Configuration:
- Manual backup: $INSTALL_DIR/backup-n8n.sh
- Restore backup: $INSTALL_DIR/restore-n8n.sh <date>
- Backup location: $INSTALL_DIR/backups
- Automatic backups: Daily at 2 AM via cron
EOF

# Add GitHub backup info if enabled
if [[ "$ENABLE_GITHUB_BACKUP" =~ ^[Yy]$ ]]; then
    cat >> $INSTALL_DIR/config-summary.txt << EOF
- GitHub backup enabled: ${GITHUB_BACKUP_REPO}
- Restore from GitHub: $INSTALL_DIR/restore-n8n.sh <date> --from-github
EOF
fi

# Run initial backup
print_message $YELLOW "💾 Running initial backup..."
$INSTALL_DIR/backup-n8n.sh

print_message $GREEN "✅ Backup system configured!"
print_message $BLUE "   Backups run daily at 2 AM"
print_message $BLUE "   Backup location: $INSTALL_DIR/backups"
print_message $BLUE "   Manual backup: $INSTALL_DIR/backup-n8n.sh"
print_message $BLUE "   Restore backup: $INSTALL_DIR/restore-n8n.sh <date>"

# Final check and push any fixes
if docker ps | grep -E "n8n-" | grep -q "Restarting"; then
    print_message $YELLOW "⚠️  Some services are still restarting. Running final fixes..."
    fix_container_restarts
fi

# Run all fix checks
fix_webhook_urls
fix_caddy_ports
fix_encryption_key
fix_postgres_password
fix_binary_data_directory

# Push final state to git
push_fix_to_git "Installation completed with all fixes applied including binary data sharing"

# Final output
SUMMARY_SHOWN=1
print_section "🎉 Installation Complete!"
echo ""
print_message $GREEN "✅ Onezipp N8N Cluster v2.1 has been successfully installed!"
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
echo -e "${YELLOW}💾 Backup Commands:${NC}"
echo -e "   Manual backup: ${GREEN}$INSTALL_DIR/backup-n8n.sh${NC}"
echo -e "   Restore backup: ${GREEN}$INSTALL_DIR/restore-n8n.sh <date>${NC}"
if [[ "$ENABLE_GITHUB_BACKUP" =~ ^[Yy]$ ]]; then
    echo -e "   Restore from GitHub: ${GREEN}$INSTALL_DIR/restore-n8n.sh <date> --from-github${NC}"
fi
echo -e "   View backups: ${GREEN}ls -la $INSTALL_DIR/backups/${NC}"
if [[ "$ENABLE_GITHUB_BACKUP" =~ ^[Yy]$ ]]; then
    echo -e "   GitHub backup: ${GREEN}Enabled to ${GITHUB_BACKUP_REPO}${NC}"
fi
echo ""
echo -e "${YELLOW}📁 Configuration saved to:${NC}"
echo -e "   ${GREEN}$INSTALL_DIR/config-summary.txt${NC}"
echo ""
echo -e "${BLUE}🚀 Your N8N cluster is now running with:${NC}"
echo -e "   • 1 Main N8N instance (UI/API)"
echo -e "   • ${WORKER_COUNT} Worker nodes for processing"
echo -e "   • ${WEBHOOK_COUNT} Webhook processor nodes"
echo -e "   • Redis for queue management"
echo -e "   • PostgreSQL database"
echo -e "   • Caddy with automatic SSL"
echo -e "   • Ollama for AI models (${GPU_PROFILE} profile)"
echo -e "   • Qdrant vector database"
echo -e "   • ✅ Fixed binary data sharing across cluster"
echo -e "   • ✅ Image preview enabled"
echo -e "   • Automatic daily backups at 2 AM"
if [[ "$ENABLE_GITHUB_BACKUP" =~ ^[Yy]$ ]]; then
    echo -e "   • GitHub backup integration"
fi
echo ""
print_message $YELLOW "⚠️  Note: It may take a few minutes for SSL certificates to be issued."
print_message $YELLOW "   If you can't access the site immediately, please wait 2-3 minutes."
print_message $YELLOW "   Webhooks will automatically use: https://${DOMAIN}/webhook/..."
echo ""
print_message $BLUE "🖼️  Image Preview: Upload images in N8N and you should see thumbnails!"
print_message $BLUE "   Binary data is now properly shared across all cluster nodes."
echo ""
print_message $BLUE "💾 Important: Your workflows are automatically backed up daily at 2 AM"
print_message $BLUE "   You can also run manual backups anytime with: $INSTALL_DIR/backup-n8n.sh"
echo ""
print_message $GREEN "🎊 Thank you for using Onezipp N8N Cluster Script v2.1!"
print_message $BLUE "   GitHub: https://github.com/PratikMoitra/onezipp-n8n-cluster"
print_message $BLUE "   Auto-fix enabled: Errors are automatically fixed and pushed to git"
print_message $YELLOW "   💡 Tip: Fork the repo and update GIT_REMOTE in the script to use your own repository!"
