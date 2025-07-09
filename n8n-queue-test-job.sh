#!/bin/bash

# n8n Queue Mode Job Processing Test
# Creates a test job and verifies it gets processed

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit || exit 1
source .env

REDIS_AUTH="${REDIS_PASSWORD}"
N8N_URL="https://${N8N_HOST:-stepper.onezipp.com}"

echo -e "${BLUE}=== n8n Queue Mode Job Processing Test ===${NC}"
echo ""

# 1. Check prerequisites
echo -e "${CYAN}Checking prerequisites...${NC}"

# Check if main instance is running
if ! docker ps --format "{{.Names}}" | grep -q "^n8n-main$"; then
    echo -e "${RED}✗ Main n8n instance not running${NC}"
    exit 1
fi

# Check if any workers are listening
listeners=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning CLIENT LIST 2>/dev/null | grep -c "cmd=brpoplpush\|cmd=blmove\|cmd=blpop" || echo 0)

if [ "$listeners" -eq 0 ]; then
    echo -e "${RED}✗ No workers listening to queue${NC}"
    echo "Workers are not properly connected to Redis queue!"
    exit 1
fi

echo -e "${GREEN}✓ Main instance running${NC}"
echo -e "${GREEN}✓ $listeners workers listening to queue${NC}"

# 2. Create a simple test workflow
echo -e "\n${CYAN}Creating test workflow...${NC}"

# First, we need to get auth token if using basic auth
if [ -n "$N8N_BASIC_AUTH_USER" ] && [ -n "$N8N_BASIC_AUTH_PASSWORD" ]; then
    AUTH_HEADER="Authorization: Basic $(echo -n "$N8N_BASIC_AUTH_USER:$N8N_BASIC_AUTH_PASSWORD" | base64)"
else
    AUTH_HEADER=""
fi

# Create a simple workflow via API
WORKFLOW_JSON='{
  "name": "Queue Test Workflow",
  "nodes": [
    {
      "parameters": {},
      "name": "Start",
      "type": "n8n-nodes-base.start",
      "typeVersion": 1,
      "position": [250, 300]
    },
    {
      "parameters": {
        "values": {
          "string": [
            {
              "name": "test_time",
              "value": "={{new Date().toISOString()}}"
            },
            {
              "name": "test_status",
              "value": "Queue processing works!"
            }
          ]
        }
      },
      "name": "Set",
      "type": "n8n-nodes-base.set",
      "typeVersion": 1,
      "position": [450, 300]
    }
  ],
  "connections": {
    "Start": {
      "main": [[{"node": "Set", "type": "main", "index": 0}]]
    }
  },
  "active": true
}'

# Note: This requires API access which might not be enabled
# Alternative: Monitor existing workflow execution

# 3. Monitor queue before triggering
echo -e "\n${CYAN}Current queue status:${NC}"
queue_before=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning EVAL "
    local w = redis.call('LLEN', 'bull:jobs:wait') + redis.call('LLEN', 'bull:jobs:waiting')
    local a = redis.call('LLEN', 'bull:jobs:active')
    local c = redis.call('LLEN', 'bull:jobs:completed') + redis.call('ZCARD', 'bull:jobs:completed')
    return w .. '|' .. a .. '|' .. c
" 0 2>/dev/null || echo "0|0|0")

IFS='|' read -r waiting_before active_before completed_before <<< "$queue_before"
echo "  Waiting: $waiting_before"
echo "  Active: $active_before"
echo "  Completed: $completed_before"

# 4. Create a test job by checking workflow execution
echo -e "\n${CYAN}Testing job processing...${NC}"
echo "Please trigger any workflow in n8n UI to test queue processing"
echo "Monitoring for new jobs..."

# Monitor for 30 seconds
timeout=30
start_time=$(date +%s)
job_processed=false

while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
    # Check current queue status
    queue_now=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning EVAL "
        local w = redis.call('LLEN', 'bull:jobs:wait') + redis.call('LLEN', 'bull:jobs:waiting')
        local a = redis.call('LLEN', 'bull:jobs:active')
        local c = redis.call('LLEN', 'bull:jobs:completed') + redis.call('ZCARD', 'bull:jobs:completed')
        return w .. '|' .. a .. '|' .. c
    " 0 2>/dev/null || echo "0|0|0")
    
    IFS='|' read -r waiting_now active_now completed_now <<< "$queue_now"
    
    # Check if any job is being processed
    if [ "$active_now" -gt "$active_before" ] || [ "$completed_now" -gt "$completed_before" ]; then
        echo -e "\n${GREEN}✓ Job detected and being processed!${NC}"
        echo "  Active jobs: $active_now"
        echo "  Completed: $completed_now"
        job_processed=true
        
        # Show which worker picked it up
        echo -e "\n${CYAN}Worker activity:${NC}"
        for i in {1..6}; do
            worker="n8n-worker-$i"
            if docker ps --format "{{.Names}}" | grep -q "^${worker}$"; then
                recent_log=$(docker logs "$worker" --since 5s 2>&1 | grep -E "Executing|started|completed" | tail -1)
                if [ -n "$recent_log" ]; then
                    echo "  Worker $i: Processing job"
                fi
            fi
        done
        
        break
    fi
    
    # Show progress
    echo -ne "\rWaiting for job activity... $((timeout - $(date +%s) + start_time))s "
    sleep 1
done

echo ""

# 5. Final validation
if [ "$job_processed" = true ]; then
    echo -e "\n${GREEN}✅ Queue mode is working correctly!${NC}"
    echo "Jobs are being picked up and processed by workers."
    
    # Show processing stats
    recent_jobs=$(docker exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
        SELECT COUNT(*) FROM execution_entity 
        WHERE \"startedAt\" > NOW() - INTERVAL '1 minute'
    " 2>/dev/null | tr -d ' ' || echo "0")
    
    echo -e "\nJobs processed in last minute: $recent_jobs"
else
    echo -e "\n${YELLOW}⚠️  No job activity detected${NC}"
    echo "This could mean:"
    echo "- No workflows were triggered during the test"
    echo "- Workers are not properly processing jobs"
    echo "- Queue connection issues"
    
    # Debug info
    echo -e "\n${CYAN}Debug information:${NC}"
    echo "Active Redis queue connections:"
    docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning CLIENT LIST | grep -E "brpoplpush|blmove|blpop" | wc -l
    
    echo -e "\nRecent worker logs:"
    docker logs n8n-worker-1 --tail 5 2>&1 | grep -v "Pruning"
fi

# 6. Performance test
echo -e "\n${CYAN}Queue performance metrics:${NC}"

# Check worker utilization
active_workers=0
for i in {1..6}; do
    worker="n8n-worker-$i"
    if docker ps --format "{{.Names}}" | grep -q "^${worker}$"; then
        if is_worker_listening "$worker"; then
            ((active_workers++))
        fi
    fi
done

echo "Active workers: $active_workers/6"
echo "Queue listeners: $listeners"

# Redis performance
redis_ops=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning INFO stats 2>/dev/null | grep instantaneous_ops_per_sec | cut -d: -f2 | tr -d '\r\n ' || echo "0")
echo "Redis ops/sec: $redis_ops"

echo -e "\n${BLUE}Test complete!${NC}"
