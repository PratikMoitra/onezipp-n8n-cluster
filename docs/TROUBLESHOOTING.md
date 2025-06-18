# Troubleshooting Guide

## Common Issues and Solutions

### SSL Certificate Issues

#### Problem: "Connection not secure" or SSL errors
**Solutions:**
1. Wait 2-3 minutes after installation for Let's Encrypt to issue certificates
2. Check Caddy logs:
   ```bash
   docker logs caddy
   ```
3. Verify DNS is properly configured:
   ```bash
   dig +short yourdomain.com
   ```
4. Ensure ports 80 and 443 are open:
   ```bash
   sudo ufw status
   ```

### N8N Access Issues

#### Problem: Cannot access N8N UI
**Solutions:**
1. Check if all services are running:
   ```bash
   docker ps
   ```
2. Verify n8n-main container logs:
   ```bash
   docker logs n8n-main
   ```
3. Test local connectivity:
   ```bash
   curl -I http://localhost:5678
   ```

### Worker Node Issues

#### Problem: Workflows not executing or slow performance
**Solutions:**
1. Check worker status:
   ```bash
   docker logs n8n-worker-1
   docker logs n8n-worker-2
   docker logs n8n-worker-3
   docker logs n8n-worker-4
   ```
2. Monitor Redis connectivity:
   ```bash
   docker exec redis redis-cli -a $REDIS_PASSWORD ping
   ```
3. Check queue status:
   ```bash
   docker exec redis redis-cli -a $REDIS_PASSWORD info stats
   ```

### Database Issues

#### Problem: "Database connection failed"
**Solutions:**
1. Check PostgreSQL status:
   ```bash
   docker logs postgres
   ```
2. Test database connection:
   ```bash
   docker exec postgres pg_isready -U n8n
   ```
3. Verify environment variables:
   ```bash
   docker exec n8n-main env | grep DB_
   ```

### Memory Issues

#### Problem: Containers crashing or restarting
**Solutions:**
1. Check system resources:
   ```bash
   free -h
   docker stats
   ```
2. Increase swap if needed:
   ```bash
   sudo fallocate -l 4G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```
3. Scale down workers if necessary

### Ollama Issues

#### Problem: AI models not responding
**Solutions:**
1. Check Ollama status:
   ```bash
   docker logs ollama
   ```
2. Verify model is downloaded:
   ```bash
   docker exec ollama ollama list
   ```
3. Pull models manually if needed:
   ```bash
   docker exec ollama ollama pull llama3.2
   docker exec ollama ollama pull nomic-embed-text
   ```

### Webhook Issues

#### Problem: Webhooks not triggering
**Solutions:**
1. Check webhook processor logs:
   ```bash
   docker logs n8n-webhook-1
   ```
2. Verify webhook URL format:
   - Production: `https://yourdomain.com/webhook/[webhook-id]`
   - Test: `https://yourdomain.com/webhook-test/[webhook-id]`
3. Test webhook connectivity:
   ```bash
   curl -X POST https://yourdomain.com/webhook/test
   ```

## Performance Optimization

### Scaling Workers
To add more workers, edit `docker-compose.yml`:
```yaml
n8n-worker-5:
  <<: *n8n-base
  container_name: n8n-worker-5
  hostname: n8n-worker-5
  command: n8n worker
  environment:
    - N8N_CONCURRENCY=${N8N_CONCURRENCY}
  volumes:
    - ./shared:/data/shared
```

### Resource Limits
Add resource limits to prevent container overuse:
```yaml
services:
  n8n-worker-1:
    # ... existing config ...
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 512M
```

## Logs and Monitoring

### View All Logs
```bash
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit
docker compose logs -f
```

### View Specific Service Logs
```bash
docker compose logs -f n8n-main
docker compose logs -f postgres
docker compose logs -f redis
```

### Export Logs
```bash
docker compose logs > n8n-cluster-logs.txt
```

## Backup and Recovery

### Backup Database
```bash
docker exec postgres pg_dump -U n8n n8n > n8n-backup-$(date +%Y%m%d).sql
```

### Restore Database
```bash
docker exec -i postgres psql -U n8n n8n < n8n-backup-20240101.sql
```

### Backup Volumes
```bash
tar -czf n8n-volumes-backup-$(date +%Y%m%d).tar.gz \
  /var/lib/docker/volumes/self-hosted-ai-starter-kit_n8n_storage \
  /var/lib/docker/volumes/self-hosted-ai-starter-kit_postgres_storage
```

## Emergency Recovery

### Reset Admin Password
1. Access PostgreSQL:
   ```bash
   docker exec -it postgres psql -U n8n n8n
   ```
2. Update password:
   ```sql
   UPDATE "user" SET password = 'new-hashed-password' WHERE email = 'admin@example.com';
   ```

### Complete Reset
⚠️ **Warning: This will delete all data!**
```bash
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit
docker compose down -v
docker compose --profile [gpu-profile] up -d
```

## Getting Help

1. Check container logs first
2. Review this troubleshooting guide
3. Visit [n8n Community Forum](https://community.n8n.io)
4. Check [n8n Documentation](https://docs.n8n.io)
5. Report issues on [GitHub](https://github.com/yourusername/onezipp-n8n-cluster)
