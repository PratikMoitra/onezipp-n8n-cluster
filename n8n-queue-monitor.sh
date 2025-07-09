#!/bin/bash

# n8n Queue Mode Complete Monitoring Script
# This script monitors and validates the full queue mode operation

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration
REFRESH_INTERVAL=2
SCRIPT_DIR="/opt/onezipp-n8n/self-hosted-ai-starter-kit"

# Navigate to the correct directory
cd "$SCRIPT_DIR" || exit 1

# Load environment variables
source .env

# Redis password
REDIS_AUTH="${REDIS_PASSWORD}"

# Function to check if service is healthy
check_health() {
    local service=$1
    local port=${2:-5678}
    
    if docker exec "$service" wget -q -O- "http://localhost:$port/healthz" 2>/dev/null | grep -q "OK"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
}

# Function to get container status
get_container_status() {
    local container=$1
    local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
    
    case "$status" in
        "running")
            echo -e "${GREEN}Running${NC}"
            ;;
        "exited")
            echo -e "${RED}Exited${NC}"
            ;;
        "restarting")
            echo -e "${YELLOW}Restarting${NC}"
            ;;
        *)
            echo -e "${RED}Unknown${NC}"
            ;;
    esac
}

# Function to get worker mode
get_worker_mode() {
    local worker=$1
    local cmd=$(docker inspect -f '{{join .Config.Cmd " "}}' "$worker" 2>/dev/null)
    
    if [[ "$cmd" == *"worker"* ]]; then
        echo -e "${GREEN}Worker Mode${NC}"
    elif [[ "$cmd" == *"webhook"* ]]; then
        echo -e "${BLUE}Webhook Mode${NC}"
    else
        echo -e "${RED}Invalid Mode${NC}"
    fi
}

# Function to format uptime
format_uptime() {
    local start_time=$1
    local current_time=$(date +%s)
    local start_epoch=$(date -d "$start_time" +%s 2>/dev/null || echo 0)
    
    if [ "$start_epoch" -eq 0 ]; then
        echo "Unknown"
        return
    fi
    
    local uptime=$((current_time - start_epoch))
    local days=$((uptime / 86400))
    local hours=$(((uptime % 86400) / 3600))
    local minutes=$(((uptime % 3600) / 60))
    
    if [ $days -gt 0 ]; then
        echo "${days}d ${hours}h ${minutes}m"
    elif [ $hours -gt 0 ]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

# Main monitoring loop
clear
echo -e "${WHITE}=== n8n Queue Mode Monitor ===${NC}"
echo -e "Press ${RED}Ctrl+C${NC} to exit"
echo ""

while true; do
    # Clear screen but keep header
    tput cup 3 0
    tput ed
    
    # Timestamp
    echo -e "${CYAN}Last Update:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 1. Main Instance Status
    echo -e "${WHITE}━━━ Main Instance ━━━${NC}"
    printf "%-20s %-15s %-10s %-15s\n" "Service" "Status" "Health" "Uptime"
    
    main_status=$(get_container_status "n8n-main")
    main_health=$(check_health "n8n-main" "443")
    main_uptime=$(docker inspect -f '{{.State.StartedAt}}' "n8n-main" 2>/dev/null)
    main_uptime_formatted=$(format_uptime "$main_uptime")
    
    printf "%-20s %-15s %-10s %-15s\n" \
        "n8n-main" \
        "$main_status" \
        "$main_health" \
        "$main_uptime_formatted"
    
    echo ""
    
    # 2. Worker Status
    echo -e "${WHITE}━━━ Workers (${GREEN}$(docker compose ps | grep -c "n8n-worker.*Up")${WHITE}/6) ━━━${NC}"
    printf "%-20s %-15s %-15s %-10s %-15s\n" "Worker" "Status" "Mode" "Health" "Uptime"
    
    for i in {1..6}; do
        worker="n8n-worker-$i"
        status=$(get_container_status "$worker")
        mode=$(get_worker_mode "$worker")
        health=$(check_health "$worker")
        uptime=$(docker inspect -f '{{.State.StartedAt}}' "$worker" 2>/dev/null)
        uptime_formatted=$(format_uptime "$uptime")
        
        printf "%-20s %-15s %-15s %-10s %-15s\n" \
            "$worker" \
            "$status" \
            "$mode" \
            "$health" \
            "$uptime_formatted"
    done
    
    echo ""
    
    # 3. Webhook Processors Status
    echo -e "${WHITE}━━━ Webhook Processors (${GREEN}$(docker compose ps | grep -c "n8n-webhook.*Up")${WHITE}/6) ━━━${NC}"
    printf "%-20s %-15s %-15s %-10s %-15s\n" "Webhook" "Status" "Mode" "Health" "Uptime"
    
    for i in {1..6}; do
        webhook="n8n-webhook-$i"
        status=$(get_container_status "$webhook")
        mode=$(get_worker_mode "$webhook")
        health=$(check_health "$webhook")
        uptime=$(docker inspect -f '{{.State.StartedAt}}' "$webhook" 2>/dev/null)
        uptime_formatted=$(format_uptime "$uptime")
        
        printf "%-20s %-15s %-15s %-10s %-15s\n" \
            "$webhook" \
            "$status" \
            "$mode" \
            "$health" \
            "$uptime_formatted"
    done
    
    echo ""
    
    # 4. Queue Statistics
    echo -e "${WHITE}━━━ Queue Statistics ━━━${NC}"
    
    # Get queue metrics from Redis
    queue_stats=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning EVAL "
        local stats = {}
        
        -- Bull queue keys
        local waiting = redis.call('LLEN', 'bull:jobs:wait') + redis.call('LLEN', 'bull:jobs:waiting')
        local active = redis.call('LLEN', 'bull:jobs:active')
        local completed = redis.call('LLEN', 'bull:jobs:completed') + redis.call('ZCARD', 'bull:jobs:completed')
        local failed = redis.call('LLEN', 'bull:jobs:failed') + redis.call('ZCARD', 'bull:jobs:failed')
        local delayed = redis.call('ZCARD', 'bull:jobs:delayed')
        local paused = redis.call('LLEN', 'bull:jobs:paused')
        
        -- Priority jobs
        local priority = redis.call('ZCARD', 'bull:jobs:priority')
        
        return waiting .. '|' .. active .. '|' .. completed .. '|' .. failed .. '|' .. delayed .. '|' .. paused .. '|' .. priority
    " 0 2>/dev/null || echo "0|0|0|0|0|0|0")
    
    IFS='|' read -r waiting active completed failed delayed paused priority <<< "$queue_stats"
    
    printf "${CYAN}%-20s${NC} %s\n" "Waiting:" "${YELLOW}$waiting${NC}"
    printf "${CYAN}%-20s${NC} %s\n" "Active:" "${GREEN}$active${NC}"
    printf "${CYAN}%-20s${NC} %s\n" "Completed:" "${GREEN}$completed${NC}"
    printf "${CYAN}%-20s${NC} %s\n" "Failed:" "${RED}$failed${NC}"
    printf "${CYAN}%-20s${NC} %s\n" "Delayed:" "${YELLOW}$delayed${NC}"
    printf "${CYAN}%-20s${NC} %s\n" "Priority:" "${MAGENTA}$priority${NC}"
    
    echo ""
    
    # 5. Redis & Database Status
    echo -e "${WHITE}━━━ Infrastructure ━━━${NC}"
    
    # Redis status
    redis_status=$(get_container_status "redis")
    redis_clients=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning CLIENT LIST 2>/dev/null | wc -l || echo 0)
    redis_memory=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning INFO memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r' || echo "N/A")
    
    printf "${CYAN}%-20s${NC} %-15s ${CYAN}Clients:${NC} %-10s ${CYAN}Memory:${NC} %s\n" \
        "Redis:" \
        "$redis_status" \
        "$redis_clients" \
        "$redis_memory"
    
    # PostgreSQL status
    postgres_status=$(get_container_status "postgres")
    postgres_connections=$(docker exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ' || echo "N/A")
    postgres_size=$(docker exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT pg_size_pretty(pg_database_size('$POSTGRES_DB'));" 2>/dev/null | tr -d ' ' || echo "N/A")
    
    printf "${CYAN}%-20s${NC} %-15s ${CYAN}Connections:${NC} %-6s ${CYAN}Size:${NC} %s\n" \
        "PostgreSQL:" \
        "$postgres_status" \
        "$postgres_connections" \
        "$postgres_size"
    
    echo ""
    
    # 6. System Resources
    echo -e "${WHITE}━━━ Resource Usage ━━━${NC}"
    
    # Get top 5 CPU consuming containers
    echo -e "${CYAN}Top CPU Usage:${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemPerc}}" | \
        grep -E "n8n-|redis|postgres" | \
        sort -k2 -hr | \
        head -5 | \
        while read line; do
            echo "  $line"
        done
    
    echo ""
    
    # 7. Recent Activity
    echo -e "${WHITE}━━━ Recent Activity ━━━${NC}"
    
    # Recent executions
    recent_executions=$(docker exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
        SELECT COUNT(*) 
        FROM execution_entity 
        WHERE \"startedAt\" > NOW() - INTERVAL '1 minute'
    " 2>/dev/null | tr -d ' ' || echo "0")
    
    echo -e "${CYAN}Executions (last minute):${NC} $recent_executions"
    
    # Recent errors
    recent_errors=$(docker compose logs --since 1m 2>&1 | grep -ciE "error|failed|exception" || echo "0")
    
    if [ "$recent_errors" -gt 0 ]; then
        echo -e "${CYAN}Errors (last minute):${NC} ${RED}$recent_errors${NC}"
    else
        echo -e "${CYAN}Errors (last minute):${NC} ${GREEN}0${NC}"
    fi
    
    echo ""
    
    # 8. Performance Metrics
    echo -e "${WHITE}━━━ Performance ━━━${NC}"
    
    # Redis operations per second
    redis_ops=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning INFO stats 2>/dev/null | grep instantaneous_ops_per_sec | cut -d: -f2 | tr -d '\r' || echo "N/A")
    echo -e "${CYAN}Redis Ops/sec:${NC} $redis_ops"
    
    # Queue processing rate (rough estimate)
    if [ "$active" -gt 0 ]; then
        echo -e "${CYAN}Queue Status:${NC} ${GREEN}Processing${NC}"
    elif [ "$waiting" -gt 0 ]; then
        echo -e "${CYAN}Queue Status:${NC} ${YELLOW}Jobs Waiting${NC}"
    else
        echo -e "${CYAN}Queue Status:${NC} ${WHITE}Idle${NC}"
    fi
    
    # Worker efficiency
    active_workers=$(docker compose ps | grep -c "n8n-worker.*Up")
    if [ "$active_workers" -gt 0 ] && [ "$active" -gt 0 ]; then
        worker_efficiency=$(awk "BEGIN {printf \"%.1f\", $active / $active_workers}")
        echo -e "${CYAN}Jobs per Worker:${NC} $worker_efficiency"
    fi
    
    echo ""
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Sleep before next update
    sleep $REFRESH_INTERVAL
done
