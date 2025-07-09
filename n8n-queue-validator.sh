#!/bin/bash

# n8n Queue Mode Deep Operational Validator
# This script validates that nodes are ACTUALLY working in queue mode

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit || exit 1
source .env

REDIS_AUTH="${REDIS_PASSWORD}"

# Validation results
declare -A validation_results
declare -A worker_status
declare -A webhook_status

# Function to print header
print_header() {
    echo -e "\n${BLUE}━━━ $1 ━━━${NC}"
}

# Function to check if container is running correct command
check_container_mode() {
    local container=$1
    local expected_mode=$2
    
    # Get the actual command the container is running
    local cmd=$(docker inspect "$container" --format='{{join .Config.Cmd " "}}' 2>/dev/null)
    local entrypoint=$(docker inspect "$container" --format='{{join .Config.Entrypoint " "}}' 2>/dev/null)
    
    # Check if it contains the expected mode
    if [[ "$cmd" == *"$expected_mode"* ]] || [[ "$entrypoint $cmd" == *"n8n $expected_mode"* ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check if worker is connected to Redis queue
check_redis_connection() {
    local container=$1
    
    # Check if this container has an active Redis connection for queue operations
    local container_ip=$(docker inspect "$container" --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1)
    
    if [ -z "$container_ip" ]; then
        return 1
    fi
    
    # Check Redis client list for this IP
    local is_connected=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning CLIENT LIST 2>/dev/null | grep -c "$container_ip.*cmd=.*brpoplpush\|blmove\|blpop")
    
    if [ "$is_connected" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to check if worker has processed any jobs recently
check_worker_activity() {
    local container=$1
    
    # Check container logs for job processing activity
    local recent_activity=$(docker logs "$container" --since 5m 2>&1 | grep -ciE "job.*started|job.*completed|executing job|processing job" || echo "0")
    # Ensure it's a valid number and remove any whitespace/newlines
    recent_activity=$(echo "$recent_activity" | tr -d '[:space:]')
    recent_activity=${recent_activity:-0}
    
    if [ "$recent_activity" -gt "0" ]; then
        return 0
    else
        return 1
    fi
}

# Function to test webhook responsiveness
test_webhook_endpoint() {
    local container=$1
    
    # Get container port mapping
    local internal_port=$(docker inspect "$container" --format='{{range $p, $conf := .NetworkSettings.Ports}}{{$p}}{{end}}' 2>/dev/null | grep -o '[0-9]*' | head -1)
    
    if [ -z "$internal_port" ]; then
        internal_port=5678
    fi
    
    # Test health endpoint - check both common ports
    local health_check=$(docker exec "$container" wget -q -O- "http://localhost:${internal_port}/healthz" 2>/dev/null || docker exec "$container" wget -q -O- "http://localhost:443/healthz" 2>/dev/null || echo "")
    
    if [[ "$health_check" == *"ok"* ]] || [[ "$health_check" == *"OK"* ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check if container is actually processing from queue
check_queue_listener() {
    local container=$1
    
    # Check if the container environment has queue mode enabled
    local exec_mode=$(docker exec "$container" printenv EXECUTIONS_MODE 2>/dev/null)
    
    if [ "$exec_mode" != "queue" ]; then
        return 1
    fi
    
    # Check if it can reach Redis - try with the actual password from env
    local redis_host=$(docker exec "$container" printenv QUEUE_BULL_REDIS_HOST 2>/dev/null || echo "redis")
    local redis_password=$(docker exec "$container" printenv QUEUE_BULL_REDIS_PASSWORD 2>/dev/null || echo "$REDIS_AUTH")
    
    local redis_ping=$(docker exec "$container" sh -c "redis-cli -h $redis_host -a '$redis_password' ping 2>&1" | grep -o "PONG" || echo "")
    
    if [ "$redis_ping" = "PONG" ]; then
        return 0
    else
        return 1
    fi
}

# Clear screen
clear
echo -e "${BLUE}=== n8n Queue Mode Deep Operational Validation ===${NC}"
echo -e "Performing comprehensive validation of queue mode operation..."

# 1. Validate Main Instance
print_header "Main Instance Validation"

if docker ps --format "{{.Names}}" | grep -q "^n8n-main$"; then
    echo -n "Main instance running: "
    echo -e "${GREEN}✓${NC}"
    
    # Check if it's configured for queue mode
    echo -n "Queue mode configured: "
    if docker exec n8n-main printenv EXECUTIONS_MODE 2>/dev/null | grep -q "queue"; then
        echo -e "${GREEN}✓${NC}"
        validation_results["main_queue"]="pass"
    else
        echo -e "${RED}✗${NC}"
        validation_results["main_queue"]="fail"
    fi
    
    # Check if it can accept API requests
    echo -n "API responsive: "
    api_response=$(docker exec n8n-main wget -q -O- "http://localhost:443/healthz" 2>/dev/null || echo "")
    if [[ "$api_response" == *"ok"* ]] || [[ "$api_response" == *"OK"* ]]; then
        echo -e "${GREEN}✓${NC}"
        validation_results["main_api"]="pass"
    else
        echo -e "${RED}✗${NC}"
        validation_results["main_api"]="fail"
    fi
else
    echo -e "Main instance: ${RED}NOT RUNNING${NC}"
    validation_results["main"]="fail"
fi

# 2. Validate Workers
print_header "Worker Validation (Checking actual worker mode)"

for i in {1..6}; do
    worker="n8n-worker-$i"
    echo -e "\n${CYAN}Worker $i:${NC}"
    
    if docker ps --format "{{.Names}}" | grep -q "^${worker}$"; then
        # Check if container exists and is running
        echo -n "  Container running: "
        echo -e "${GREEN}✓${NC}"
        worker_status["${worker}_running"]="yes"
        
        # Check if it's running in worker mode
        echo -n "  Running as worker: "
        if check_container_mode "$worker" "worker"; then
            echo -e "${GREEN}✓${NC}"
            worker_status["${worker}_mode"]="worker"
        else
            echo -e "${RED}✗ (Not in worker mode!)${NC}"
            worker_status["${worker}_mode"]="invalid"
            
            # Show what command it's actually running
            actual_cmd=$(docker inspect "$worker" --format='{{join .Config.Cmd " "}}' 2>/dev/null)
            echo -e "    ${YELLOW}Actual command: $actual_cmd${NC}"
        fi
        
        # Check Redis connection
        echo -n "  Connected to Redis queue: "
        if check_redis_connection "$worker"; then
            echo -e "${GREEN}✓${NC}"
            worker_status["${worker}_redis"]="connected"
        else
            echo -e "${RED}✗${NC}"
            worker_status["${worker}_redis"]="disconnected"
        fi
        
        # Check queue listener
        echo -n "  Queue listener active: "
        if check_queue_listener "$worker"; then
            echo -e "${GREEN}✓${NC}"
            worker_status["${worker}_queue"]="active"
        else
            echo -e "${RED}✗${NC}"
            worker_status["${worker}_queue"]="inactive"
        fi
        
        # Check recent activity
        echo -n "  Recent job activity: "
        if check_worker_activity "$worker"; then
            echo -e "${GREEN}✓ (Processing jobs)${NC}"
            worker_status["${worker}_activity"]="active"
        else
            echo -e "${YELLOW}⚠ (No recent activity)${NC}"
            worker_status["${worker}_activity"]="idle"
        fi
        
    else
        echo -e "  ${RED}NOT RUNNING${NC}"
        worker_status["${worker}_running"]="no"
    fi
done

# 3. Validate Webhook Processors
print_header "Webhook Processor Validation"

for i in {1..6}; do
    webhook="n8n-webhook-$i"
    echo -e "\n${CYAN}Webhook Processor $i:${NC}"
    
    if docker ps --format "{{.Names}}" | grep -q "^${webhook}$"; then
        echo -n "  Container running: "
        echo -e "${GREEN}✓${NC}"
        webhook_status["${webhook}_running"]="yes"
        
        # Check if it's running in webhook mode
        echo -n "  Running as webhook: "
        if check_container_mode "$webhook" "webhook"; then
            echo -e "${GREEN}✓${NC}"
            webhook_status["${webhook}_mode"]="webhook"
        else
            echo -e "${RED}✗ (Not in webhook mode!)${NC}"
            webhook_status["${webhook}_mode"]="invalid"
        fi
        
        # Check webhook endpoint
        echo -n "  Webhook endpoint active: "
        if test_webhook_endpoint "$webhook"; then
            echo -e "${GREEN}✓${NC}"
            webhook_status["${webhook}_endpoint"]="active"
        else
            echo -e "${RED}✗${NC}"
            webhook_status["${webhook}_endpoint"]="inactive"
        fi
        
    else
        echo -e "  ${RED}NOT RUNNING${NC}"
        webhook_status["${webhook}_running"]="no"
    fi
done

# 4. Queue Operations Test
print_header "Queue Operations Test"

echo -e "${CYAN}Testing actual queue processing...${NC}"

# Get current queue stats
initial_waiting=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning LLEN bull:jobs:wait 2>/dev/null || echo 0)
initial_active=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning LLEN bull:jobs:active 2>/dev/null || echo 0)

echo "Current queue state:"
echo "  Waiting: $initial_waiting"
echo "  Active: $initial_active"

# Check Redis client connections
echo -e "\n${CYAN}Redis Queue Connections:${NC}"
worker_connections=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning CLIENT LIST 2>/dev/null | grep -c "cmd=brpoplpush\|cmd=blmove\|cmd=blpop" || echo 0)
echo "  Worker connections listening for jobs: $worker_connections"

if [ "$worker_connections" -eq 0 ]; then
    echo -e "  ${RED}⚠️  NO WORKERS ARE LISTENING TO THE QUEUE!${NC}"
    echo -e "  ${YELLOW}This means jobs will not be processed!${NC}"
fi

# 5. Performance Metrics
print_header "Queue Performance Metrics"

# Check job processing rate
completed_last_min=$(docker exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
    SELECT COUNT(*) FROM execution_entity 
    WHERE \"finishedAt\" > NOW() - INTERVAL '1 minute' 
    AND status = 'success'
" 2>/dev/null | tr -d '[:space:]' || echo "0")

failed_last_min=$(docker exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
    SELECT COUNT(*) FROM execution_entity 
    WHERE \"finishedAt\" > NOW() - INTERVAL '1 minute' 
    AND status = 'error'
" 2>/dev/null | tr -d '[:space:]' || echo "0")

# Ensure numeric values
completed_last_min=${completed_last_min:-0}
failed_last_min=${failed_last_min:-0}

echo "Jobs completed (last minute): $completed_last_min"
echo "Jobs failed (last minute): $failed_last_min"

# 6. Summary Report
print_header "Validation Summary"

# Count operational workers
operational_workers=0
for i in {1..6}; do
    if [ "${worker_status["n8n-worker-${i}_mode"]}" = "worker" ] && 
       [ "${worker_status["n8n-worker-${i}_redis"]}" = "connected" ]; then
        ((operational_workers++))
    fi
done

# Count operational webhooks
operational_webhooks=0
for i in {1..6}; do
    if [ "${webhook_status["n8n-webhook-${i}_mode"]}" = "webhook" ] && 
       [ "${webhook_status["n8n-webhook-${i}_endpoint"]}" = "active" ]; then
        ((operational_webhooks++))
    fi
done

echo -e "\n${WHITE}Queue Mode Status:${NC}"
echo -e "Operational Workers:   ${operational_workers}/6 $([ $operational_workers -ge 4 ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}")"
echo -e "Operational Webhooks:  ${operational_webhooks}/6 $([ $operational_webhooks -ge 4 ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}")"
echo -e "Redis Queue Active:    $([ $worker_connections -gt 0 ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}")"

# Overall status
echo -e "\n${WHITE}Overall Queue Mode Status:${NC} "
if [ $operational_workers -gt 0 ] && [ $worker_connections -gt 0 ]; then
    echo -e "${GREEN}✅ OPERATIONAL - Queue mode is working${NC}"
    exit 0
else
    echo -e "${RED}❌ NOT OPERATIONAL - Queue mode is not working properly${NC}"
    echo -e "\n${YELLOW}Common issues:${NC}"
    
    if [ $operational_workers -eq 0 ]; then
        echo "- No workers are running in worker mode"
        echo "  Fix: Ensure 'command: worker' is set in docker-compose.yml"
    fi
    
    if [ $worker_connections -eq 0 ]; then
        echo "- Workers are not connected to Redis queue"
        echo "  Fix: Check Redis password and network connectivity"
    fi
    
    exit 1
fi
