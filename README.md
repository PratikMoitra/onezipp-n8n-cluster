# Onezipp N8N Cluster Setup Script

## 🚀 Overview

The **Onezipp N8N Cluster Script** is a production-ready, one-click deployment solution for setting up a scalable n8n workflow automation platform with AI capabilities on DigitalOcean or any Ubuntu-based VPS.

### ✨ Features

- **Complete N8N Cluster Setup**: Configures n8n in queue mode with 4 worker nodes and 4 webhook processor nodes
- **Automatic SSL**: Caddy reverse proxy with automatic Let's Encrypt SSL certificates
- **AI-Ready**: Includes Ollama for LLMs and Qdrant for vector storage
- **Production Optimized**: Redis for queue management, PostgreSQL for data persistence
- **Zero Manual Configuration**: Fully automated setup with minimal user interaction
- **GPU Support**: Auto-detects and configures NVIDIA/AMD GPU support
- **Service Management**: Systemd integration for easy start/stop/restart

## 📋 Requirements

### Minimum System Requirements
- **OS**: Ubuntu 20.04+ or Debian 11+
- **RAM**: 4GB minimum (8GB recommended)
- **Storage**: 20GB minimum
- **CPU**: 2 cores minimum (4 cores recommended)
- **Network**: Public IP address with ports 80 and 443 available

### DigitalOcean Droplet Recommendations
- **Basic Setup**: 4GB RAM / 2 vCPUs (Basic Droplet)
- **Recommended**: 8GB RAM / 4 vCPUs (General Purpose Droplet)
- **High Performance**: 16GB RAM / 8 vCPUs with GPU (GPU Droplet)

## 🛠️ Installation

### Step 1: Prepare Your Domain
Before running the script, ensure you have:
1. A domain or subdomain (e.g., `n8n.yourdomain.com`, `workflow.company.io`)
2. DNS A record pointing to your server's IP address

**Subdomain Support**: The script fully supports subdomains at any level:
- ✅ `n8n.example.com`
- ✅ `workflow.prod.company.com`
- ✅ `automation.dev.mysite.io`

### Step 2: Download and Run the Script

```bash
# Download the script
wget https://raw.githubusercontent.com/yourusername/onezipp-n8n-cluster/main/setup.sh -O onezipp-setup.sh

# Make it executable
chmod +x onezipp-setup.sh

# Run as root
sudo ./onezipp-setup.sh
```

### Step 3: Follow the Prompts
The script provides sensible defaults for all options:

| Prompt | Default | Example |
|--------|---------|---------|
| Domain/subdomain | `n8n.example.com` | `workflow.mycompany.com` |
| Email for SSL | `admin@[your-domain]` | Auto-generated from domain |
| N8N Admin Email | `admin@[your-domain]` | Auto-generated from domain |
| N8N Admin Password | Auto-generated secure password | 12-character random string |
| GPU Type | CPU only | Option 3 |
| Installation Directory | `/opt/onezipp-n8n` | Default recommended |

**💡 Pro Tip**: You can accept all defaults by pressing Enter at each prompt for the fastest setup!

## 🏗️ Architecture

The script sets up the following architecture:

```
Internet
    ↓
[Caddy Reverse Proxy] → SSL Termination
    ↓
[Load Balancer]
    ├─→ [N8N Main Instance] → UI/API
    ├─→ [Webhook Processor 1-4] → Handle incoming webhooks
    └─→ [Worker Nodes 1-4] → Process workflows
         ↓
    [Redis] → Queue Management
    [PostgreSQL] → Data Persistence
    [Ollama] → AI/LLM Processing
    [Qdrant] → Vector Database
```

## 📁 File Structure

After installation, files are organized as follows:

```
/opt/onezipp-n8n/
├── self-hosted-ai-starter-kit/
│   ├── docker-compose.yml
│   ├── .env
│   ├── caddy/
│   │   └── Caddyfile
│   ├── shared/
│   ├── start.sh
│   └── stop.sh
└── config-summary.txt
```

## 🔧 Post-Installation

### Accessing N8N
1. Open your browser and navigate to `https://your-domain.com`
2. Log in with the admin credentials you provided
3. Start building your workflows!

### Service Management

```bash
# Start all services
sudo systemctl start onezipp-n8n

# Stop all services
sudo systemctl stop onezipp-n8n

# Restart all services
sudo systemctl restart onezipp-n8n

# View service status
sudo systemctl status onezipp-n8n

# View logs
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit
sudo docker compose logs -f

# View specific service logs
sudo docker compose logs -f n8n-main
sudo docker compose logs -f n8n-worker-1
```

### Scaling Workers

To add more workers or webhook processors, edit the docker-compose.yml file and add new service definitions following the existing pattern.

## 🔒 Security Considerations

1. **Firewall**: The script configures UFW to allow only necessary ports (22, 80, 443)
2. **SSL**: Automatic SSL certificates via Let's Encrypt
3. **Passwords**: All passwords are randomly generated and stored securely
4. **Encryption**: N8N data is encrypted with a unique encryption key

## 🐛 Troubleshooting

### SSL Certificate Issues
If you can't access the site immediately after installation:
- Wait 2-3 minutes for Let's Encrypt to issue certificates
- Check Caddy logs: `sudo docker logs caddy`

### Service Not Starting
```bash
# Check all container statuses
sudo docker ps -a

# Check specific service logs
sudo docker logs n8n-main
sudo docker logs postgres
sudo docker logs redis
```

### Performance Issues
- Monitor resource usage: `htop` or `docker stats`
- Scale workers if needed by modifying docker-compose.yml
- Consider upgrading your droplet for better performance

## 📊 Monitoring

### Health Checks
The system includes health checks for all critical services:
- PostgreSQL: Connection health
- Redis: Connection health
- N8N Workers: `/healthz` endpoint
- Webhook Processors: `/healthz` endpoint

### Resource Monitoring
```bash
# Monitor all containers
sudo docker stats

# Check disk usage
df -h

# Monitor system resources
htop
```

## 🔄 Updates

To update the n8n cluster:

```bash
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit

# Stop services
sudo docker compose down

# Pull latest images
sudo docker compose pull

# Start services
sudo docker compose --profile [your-gpu-profile] up -d
```

## 🤝 Support

For issues or questions:
1. Check the [n8n documentation](https://docs.n8n.io)
2. Visit the [n8n community forum](https://community.n8n.io)
3. Review logs for error messages

## 📜 License

This script is provided as-is under the MIT License. The n8n platform and its components are subject to their respective licenses.

## 🙏 Credits

- Built on top of the [n8n self-hosted AI starter kit](https://github.com/n8n-io/self-hosted-ai-starter-kit)
- Powered by [n8n](https://n8n.io) workflow automation platform
- SSL certificates by [Let's Encrypt](https://letsencrypt.org)
- Reverse proxy by [Caddy](https://caddyserver.com)

---

**Note**: This script is designed for production use but should be reviewed and tested in your specific environment before deploying critical workloads.
# onezipp-n8n-cluster
