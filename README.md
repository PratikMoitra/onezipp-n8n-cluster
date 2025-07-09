# Onezipp n8n Cluster

[![n8n](https://img.shields.io/badge/n8n-workflow%20automation-orange)](https://n8n.io)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Ubuntu](https://img.shields.io/badge/ubuntu-20.04%2B-E95420)](https://ubuntu.com/)
[![DigitalOcean](https://img.shields.io/badge/digitalocean-ready-0080FF)](https://www.digitalocean.com/)

The Onezipp n8n Cluster Script is a production-ready, one-click deployment solution for setting up a scalable n8n workflow automation platform with AI capabilities on DigitalOcean or any Ubuntu-based VPS.

## 🚀 Overview

This project provides a fully automated setup script that deploys:

- **Complete n8n Cluster**: Configures n8n in queue mode with 4 worker nodes and 4 webhook processor nodes
- **Automatic SSL**: Caddy reverse proxy with automatic Let's Encrypt SSL certificates
- **AI-Ready**: Includes Ollama for LLMs and Qdrant for vector storage
- **Production Optimized**: Redis for queue management, PostgreSQL for data persistence
- **Zero Manual Configuration**: Fully automated setup with minimal user interaction
- **GPU Support**: Auto-detects and configures NVIDIA/AMD GPU support
- **Service Management**: Systemd integration for easy start/stop/restart

## 📋 Table of Contents

- [Features](#-features)
- [Architecture](#-architecture)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [Post-Installation](#-post-installation)
- [Service Management](#-service-management)
- [Scaling](#-scaling)
- [Security](#-security)
- [Monitoring](#-monitoring)
- [Troubleshooting](#-troubleshooting)
- [File Structure](#-file-structure)
- [Updates](#-updates)
- [Contributing](#-contributing)
- [License](#-license)
- [Acknowledgments](#-acknowledgments)

## ✨ Features

- **One-Click Deployment**: Single script installation with sensible defaults
- **Scalable Architecture**: 4 worker nodes + 4 webhook processors out of the box
- **AI Integration**: Pre-configured Ollama and Qdrant for AI workflows
- **Automatic SSL**: Let's Encrypt certificates via Caddy
- **GPU Support**: Auto-detection and configuration for NVIDIA/AMD GPUs
- **Production Ready**: Optimized for real-world workloads
- **Service Management**: Systemd integration for reliability
- **Security First**: Firewall configuration, secure passwords, encrypted data

## 🏗️ Architecture

```
                        Internet
                           ↓
                  [Caddy Reverse Proxy]
                    (SSL Termination)
                           ↓
                    [Load Balancer]
                           ↓
        ┌──────────────────┼──────────────────┐
        │                  │                  │
  [n8n Main Instance]  [Webhook Processors]  [Worker Nodes]
     (UI/API)              (1-4)               (1-4)
        │                  │                  │
        └──────────────────┼──────────────────┘
                           ↓
                  ┌────────┴────────┐
                  │                 │
              [Redis]          [PostgreSQL]
         (Queue Management)  (Data Persistence)
                  │                 │
                  └────────┬────────┘
                           ↓
                    ┌──────┴──────┐
                    │             │
                [Ollama]      [Qdrant]
              (AI/LLM)    (Vector Database)
```

### Components

- **n8n Main Instance**: Handles UI, API requests, and workflow management
- **Worker Nodes (4)**: Process workflow executions from the queue
- **Webhook Processors (4)**: Handle incoming webhook requests
- **PostgreSQL**: Primary database for workflow definitions and execution data
- **Redis**: Message queue and caching layer
- **Caddy**: Modern reverse proxy with automatic HTTPS
- **Ollama**: Local LLM processing for AI workflows
- **Qdrant**: Vector database for AI applications

## 📦 Prerequisites

### System Requirements

- **OS**: Ubuntu 20.04+ or Debian 11+
- **RAM**: 4GB minimum (8GB recommended)
- **Storage**: 20GB minimum
- **CPU**: 2 cores minimum (4 cores recommended)
- **Network**: Public IP address with ports 80 and 443 available

### DigitalOcean Recommendations

- **Basic Setup**: 4GB RAM / 2 vCPUs (Basic Droplet)
- **Recommended**: 8GB RAM / 4 vCPUs (General Purpose Droplet)
- **High Performance**: 16GB RAM / 8 vCPUs with GPU (GPU Droplet)

### Domain Requirements

Before running the script, ensure you have:
- A domain or subdomain (e.g., `n8n.yourdomain.com`, `workflow.company.io`)
- DNS A record pointing to your server's IP address

**Subdomain Support**: The script fully supports subdomains at any level:
- ✅ `n8n.example.com`
- ✅ `workflow.prod.company.com`
- ✅ `automation.dev.mysite.io`

## 🚀 Installation

### Quick Start

```bash
# Download the script
wget https://raw.githubusercontent.com/PratikMoitra/onezipp-n8n-cluster/main/setup.sh -O onezipp-setup.sh

# Make it executable
chmod +x onezipp-setup.sh

# Run as root
sudo ./onezipp-setup.sh
```

### Installation Process

The script will prompt you for the following information with sensible defaults:

| Prompt | Default | Example |
|--------|---------|---------|
| Domain/subdomain | - | `n8n.example.com`, `workflow.mycompany.com` |
| Email for SSL | `admin@[your-domain]` | Auto-generated from domain |
| n8n Admin Email | `admin@[your-domain]` | Auto-generated from domain |
| n8n Admin Password | Auto-generated secure password | 12-character random string |
| GPU Type | CPU only | Option 3 |
| Installation Directory | `/opt/onezipp-n8n` | Default recommended |

💡 **Pro Tip**: You can accept all defaults by pressing Enter at each prompt for the fastest setup!

### What Happens During Installation

1. **System Preparation**
   - Updates package lists
   - Installs Docker and Docker Compose
   - Configures firewall (UFW)

2. **Repository Setup**
   - Clones the n8n self-hosted AI starter kit
   - Configures environment variables
   - Sets up Caddy for SSL

3. **Service Deployment**
   - Starts PostgreSQL database
   - Launches Redis queue
   - Deploys n8n main instance
   - Spawns 4 worker nodes
   - Creates 4 webhook processors
   - Initializes AI services (Ollama & Qdrant)

4. **Final Configuration**
   - Creates systemd service
   - Enables auto-start on boot
   - Saves configuration summary

## ⚙️ Configuration

### Default Configuration

The setup script automatically configures optimal settings:

- **n8n Mode**: Queue mode for scalability
- **Workers**: 4 worker nodes for parallel processing
- **Webhooks**: 4 webhook processors
- **Database**: PostgreSQL with persistent storage
- **Queue**: Redis for job management
- **SSL**: Automatic via Let's Encrypt
- **AI Services**: Ollama and Qdrant ready to use

### Post-Installation Access

After installation, you'll receive:
- **URL**: `https://your-domain.com`
- **Admin Email**: The email you provided
- **Admin Password**: Auto-generated or custom
- **Configuration File**: `/opt/onezipp-n8n/config-summary.txt`

### Environment Variables

The installation creates a `.env` file with all necessary configurations:

```bash
# Location: /opt/onezipp-n8n/self-hosted-ai-starter-kit/.env
N8N_ENCRYPTION_KEY=<auto-generated>
N8N_USER_MANAGEMENT_JWT_SECRET=<auto-generated>
DATABASE_PASSWORD=<auto-generated>
POSTGRES_PASSWORD=<auto-generated>
N8N_VERSION=latest
GENERIC_TIMEZONE=<system-timezone>
```

## 🎯 Post-Installation

### First Access

1. **Wait for SSL Certificate**
   - Allow 2-3 minutes for Let's Encrypt to issue certificates
   - The site will be accessible at `https://your-domain.com`

2. **Login to n8n**
   - Use the admin credentials provided during setup
   - Complete the initial setup wizard

3. **Start Building Workflows**
   - Access pre-installed AI nodes
   - Connect to 400+ integrations
   - Utilize Ollama for local LLM processing

### Initial Checks

```bash
# Verify all services are running
sudo docker ps

# Check service status
sudo systemctl status onezipp-n8n

# View configuration summary
cat /opt/onezipp-n8n/config-summary.txt
```

## 🔧 Service Management

### Using Systemd

```bash
# Start all services
sudo systemctl start onezipp-n8n

# Stop all services
sudo systemctl stop onezipp-n8n

# Restart all services
sudo systemctl restart onezipp-n8n

# View service status
sudo systemctl status onezipp-n8n

# Enable auto-start on boot
sudo systemctl enable onezipp-n8n

# Disable auto-start
sudo systemctl disable onezipp-n8n
```

### Using Docker Compose

```bash
# Navigate to installation directory
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit

# View logs
sudo docker compose logs -f

# View specific service logs
sudo docker compose logs -f n8n-main
sudo docker compose logs -f n8n-worker-1
sudo docker compose logs -f caddy

# Restart a specific service
sudo docker compose restart n8n-worker-2

# Stop all services
sudo docker compose down

# Start all services
sudo docker compose --profile [gpu-profile] up -d
```

## 📈 Scaling

### Adding More Workers

To add additional worker or webhook nodes, edit the `docker-compose.yml`:

```yaml
# Add a 5th worker
n8n-worker-5:
  image: n8nio/n8n:latest
  environment:
    - N8N_MODE=worker
    - EXECUTIONS_MODE=queue
  # ... rest of configuration
```

Then apply changes:
```bash
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit
sudo docker compose up -d
```

### Resource Scaling

Monitor and adjust resources as needed:

```bash
# Check resource usage
sudo docker stats

# Monitor system resources
htop

# Check disk usage
df -h
```

## 🔒 Security

### Built-in Security Features

- **Firewall**: UFW configured to allow only ports 22, 80, 443
- **SSL/TLS**: Automatic HTTPS via Let's Encrypt
- **Authentication**: User management with secure passwords
- **Encryption**: All n8n data encrypted with unique key
- **Network Isolation**: Services communicate through Docker network

### Security Best Practices

1. **Regular Updates**
   ```bash
   # Update system packages
   sudo apt update && sudo apt upgrade
   
   # Update Docker images
   cd /opt/onezipp-n8n/self-hosted-ai-starter-kit
   sudo docker compose pull
   sudo docker compose up -d
   ```

2. **Backup Configuration**
   - Backup PostgreSQL database regularly
   - Save workflow exports
   - Keep `.env` file secure

3. **Access Control**
   - Use strong passwords
   - Enable 2FA when available
   - Limit user permissions appropriately

## 📊 Monitoring

### Health Checks

All services include built-in health monitoring:

- **PostgreSQL**: Connection health checks
- **Redis**: Connection health monitoring
- **n8n Workers**: `/healthz` endpoint
- **Webhook Processors**: `/healthz` endpoint

### Monitoring Commands

```bash
# Real-time container stats
sudo docker stats

# Check all container statuses
sudo docker ps -a

# Monitor logs
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit
sudo docker compose logs -f

# Check specific service health
sudo docker inspect n8n-main | grep -i health
```

### Performance Monitoring

```bash
# System resources
htop

# Disk usage
df -h

# Network connections
sudo netstat -tulpn

# Database connections
sudo docker exec postgres psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Cannot Access the Site

```bash
# Wait 2-3 minutes for SSL certificate
# Check Caddy logs
sudo docker logs caddy

# Verify DNS is pointing to your server
dig +short your-domain.com
```

#### 2. Workers Not Processing Jobs

```bash
# Check Redis connectivity
sudo docker exec redis redis-cli ping

# View worker logs
sudo docker compose logs n8n-worker-1

# Check queue status
sudo docker exec redis redis-cli
> LLEN bull:jobs:waiting
```

#### 3. Database Connection Errors

```bash
# Check PostgreSQL status
sudo docker ps | grep postgres

# Test database connection
sudo docker exec postgres psql -U postgres -d n8n -c "SELECT 1;"

# View database logs
sudo docker logs postgres
```

#### 4. High Memory/CPU Usage

```bash
# Identify resource-heavy containers
sudo docker stats --no-stream

# Restart specific service
sudo docker compose restart n8n-worker-1

# Scale down if needed
sudo docker compose stop n8n-worker-4
```

### Debug Commands

```bash
# Full system diagnostics
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit
sudo docker compose ps
sudo docker compose logs --tail=50

# Check disk space
df -h | grep -E "^/dev/"

# Verify network connectivity
curl -I https://your-domain.com
```

## 📁 File Structure

After installation, files are organized as follows:

```
/opt/onezipp-n8n/
├── self-hosted-ai-starter-kit/
│   ├── docker-compose.yml      # Main compose configuration
│   ├── .env                    # Environment variables
│   ├── caddy/
│   │   └── Caddyfile          # Caddy reverse proxy config
│   ├── shared/                # Shared data directory
│   ├── start.sh              # Helper start script
│   └── stop.sh               # Helper stop script
└── config-summary.txt         # Installation summary
```

### Important Locations

- **Workflows**: Stored in PostgreSQL database
- **Credentials**: Encrypted in database
- **Binary Data**: `/opt/onezipp-n8n/self-hosted-ai-starter-kit/shared`
- **Logs**: Accessible via `docker compose logs`
- **SSL Certificates**: Managed by Caddy

## 🚀 Quick Commands Reference

```bash
# Service Management
sudo systemctl start onezipp-n8n      # Start cluster
sudo systemctl stop onezipp-n8n       # Stop cluster
sudo systemctl restart onezipp-n8n    # Restart cluster
sudo systemctl status onezipp-n8n     # Check status

# Monitoring
sudo docker stats                      # Resource usage
sudo docker compose logs -f            # Live logs
sudo docker ps                         # Container status

# Maintenance
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit
sudo docker compose pull               # Update images
sudo docker compose down               # Stop all
sudo docker compose up -d              # Start all
```

## 💡 Tips & Best Practices

1. **Performance Optimization**
   - Monitor CPU and RAM usage regularly
   - Scale workers based on workload
   - Use GPU acceleration for AI workflows

2. **Security**
   - Change default passwords immediately
   - Keep systems updated
   - Regular backups of PostgreSQL
   - Monitor access logs

3. **Workflow Development**
   - Test workflows in development first
   - Use error handling nodes
   - Implement proper logging
   - Version control your workflows

## 🔄 Updates

### Updating n8n

To update the n8n cluster to the latest version:

```bash
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit

# Stop services
sudo docker compose down

# Pull latest images
sudo docker compose pull

# Start services with your GPU profile
# For CPU: sudo docker compose --profile cpu up -d
# For NVIDIA: sudo docker compose --profile gpu-nvidia up -d
# For AMD: sudo docker compose --profile gpu-amd up -d
sudo docker compose --profile [your-gpu-profile] up -d
```

### Backup Before Updates

```bash
# Backup database
sudo docker exec postgres pg_dump -U postgres n8n > n8n_backup_$(date +%Y%m%d).sql

# Backup environment file
cp .env .env.backup_$(date +%Y%m%d)
```

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Test your changes thoroughly
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

### Reporting Issues

- Check existing issues first
- Provide detailed error messages
- Include system specifications
- Share relevant log outputs
