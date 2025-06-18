# Quick Start Guide

## 🚀 5-Minute Setup

### Prerequisites
- Fresh Ubuntu 20.04+ DigitalOcean Droplet (minimum 4GB RAM)
- Domain/subdomain pointing to your droplet's IP
- Root or sudo access

### One-Line Installation

```bash
wget -qO- https://raw.githubusercontent.com/yourusername/onezipp-n8n-cluster/main/setup.sh | sudo bash
```

### Interactive Installation (Recommended)

```bash
# Download
wget https://raw.githubusercontent.com/yourusername/onezipp-n8n-cluster/main/setup.sh

# Make executable
chmod +x setup.sh

# Run with defaults (just press Enter at each prompt)
sudo ./setup.sh
```

## 🎯 Default Configuration

| Setting | Default Value |
|---------|--------------|
| Domain | `n8n.example.com` |
| Email | `admin@[domain]` |
| Admin Username | `admin@[domain]` |
| Admin Password | Auto-generated (shown during setup) |
| GPU Mode | CPU only |
| Install Directory | `/opt/onezipp-n8n` |

## 📝 First Steps After Installation

### 1. Access N8N
- Open `https://your-domain.com` in your browser
- Log in with the credentials shown during setup

### 2. Test the AI Capabilities
1. Click on **Workflows** → **New Workflow**
2. Add a **Webhook** node
3. Add an **Ollama Chat Model** node
4. Connect them and test with a simple prompt

### 3. Import Example Workflow
```bash
# Download example workflow
wget https://raw.githubusercontent.com/yourusername/onezipp-n8n-cluster/main/workflows/ai-qa-example.json

# Import via N8N UI: Settings → Workflow → Import
```

## 🔥 Common Use Cases

### 1. AI Chatbot
- Webhook trigger → Ollama Chat → Response
- Perfect for customer support automation

### 2. Document Q&A System
- Upload documents → Qdrant vectorization → AI retrieval
- Great for knowledge base queries

### 3. Automated Content Generation
- Schedule trigger → AI Agent → Multiple outputs
- Ideal for social media automation

### 4. Data Processing Pipeline
- Database trigger → AI analysis → Notification
- Excellent for business intelligence

## ⚡ Performance Tips

### For Light Usage (< 100 workflows/day)
- Default configuration is perfect
- 4GB RAM droplet sufficient

### For Medium Usage (100-1000 workflows/day)
- Upgrade to 8GB RAM droplet
- No configuration changes needed

### For Heavy Usage (> 1000 workflows/day)
- Use 16GB+ RAM droplet
- Add more workers via docker-compose.yml
- Consider GPU droplet for AI processing

## 🛠️ Quick Commands

```bash
# View status
docker ps

# Check logs
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit && docker compose logs -f

# Restart everything
sudo systemctl restart onezipp-n8n

# Stop services
sudo systemctl stop onezipp-n8n

# Start services
sudo systemctl start onezipp-n8n
```

## 🆘 Quick Fixes

### Can't access the site?
```bash
# Check if services are running
docker ps | grep caddy

# Wait 2-3 minutes for SSL certificates
# Check Caddy logs
docker logs caddy
```

### Forgot admin password?
Check `/opt/onezipp-n8n/config-summary.txt` for all credentials.

### Need more AI models?
```bash
# List available models
docker exec ollama ollama list

# Pull a new model
docker exec ollama ollama pull mistral
```

## 📚 Next Steps

1. **Explore N8N**: Check out the [template library](https://n8n.io/workflows)
2. **Learn Automation**: Visit [N8N documentation](https://docs.n8n.io)
3. **Join Community**: Get help at [N8N forum](https://community.n8n.io)
4. **Customize**: Edit `/opt/onezipp-n8n/self-hosted-ai-starter-kit/docker-compose.yml`

## 💡 Pro Tips

1. **Backup regularly**: Your data is in `/opt/onezipp-n8n`
2. **Monitor resources**: Use `htop` or `docker stats`
3. **Update monthly**: Pull latest Docker images
4. **Test webhooks**: Use webhook.site for debugging
5. **Use templates**: Don't reinvent the wheel

---

**Need help?** Check the [troubleshooting guide](./TROUBLESHOOTING.md) or open an issue on GitHub.
