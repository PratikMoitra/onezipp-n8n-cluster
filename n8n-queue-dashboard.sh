#!/bin/bash

# n8n Queue Mode Simple Dashboard (Fixed Version)
# A lightweight dashboard for quick status checks

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
cd /opt/onezipp-n8n/self-hosted-ai-starter-kit || exit 1
if [ -f .env ]; then
    source .env
fi

# Set default Redis password if not in env
REDIS_AUTH="${REDIS_PASSWORD:-${QUEUE_BULL_REDIS_PASSWORD:-redis_password}}"

# Function to create a simple bar graph
create_bar() {
    local value=${1:-0}
    local max=${2:-100}
    local width=20
    
    # Ensure numeric values
    value=$(echo "$value" | grep -o '[0-9]*' | head -1)
    [ -z "$value" ] && value=0
    max=$(echo "$max" | grep -o '[0-9]*' | head -1)
    [ -z "$max" ] || [ "$max" -eq 0 ] && max=100
    
    local filled=0
    if [ "$max" -gt 0 ]; then
        filled=$((value * width / max))
        [ "$filled" -gt "$width" ] && filled=$width
    fi
    
    printf "["
    for ((i=0; i<width; i++)); do
        if [ "$i" -lt "$filled" ]; then
            printf "█"
        else
            printf " "
        fi
    done
    printf "]"
}

# Function to get status emoji
get_status_emoji() {
    local status=$1
    case "$status" in
        "running") echo "🟢" ;;
        "healthy") echo "✅" ;;
        "warning") echo "⚠️ " ;;
        "error") echo "🔴" ;;
        *) echo "❓" ;;
    esac
}

# Function to safely count docker containers
count_containers() {
    local pattern=$1
    local count=0
    
    # Use docker ps with specific format to avoid parsing issues
    if [ "$pattern" = "n8n-main" ]; then
        count=$(docker ps --format "{{.Names}}" | grep -c "^n8n-main$" 2>/dev/null || echo "0")
    elif [ "$pattern" = "n8n-worker" ]; then
        count=$(docker ps --format "{{.Names}}" | grep -E "^n8n-worker-[0-9]+$" | wc -l 2>/dev/null || echo "0")
    elif [ "$pattern" = "n8n-webhook" ]; then
        count=$(docker ps --format "{{.Names}}" | grep -E "^n8n-webhook-[0-9]+$" | wc -l 2>/dev/null || echo "0")
    elif [ "$pattern" = "redis" ]; then
        count=$(docker ps --format "{{.Names}}" | grep -c "^redis$" 2>/dev/null || echo "0")
    elif [ "$pattern" = "postgres" ]; then
        count=$(docker ps --format "{{.Names}}" | grep -c "^postgres$" 2>/dev/null || echo "0")
    fi
    
    echo "$count"
}

# Main dashboard loop
while true; do
    clear
    
    # Header
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}           ${CYAN}n8n Queue Mode Dashboard${NC}                        ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}           $(date '+%Y-%m-%d %H:%M:%S')                      ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Quick Status Overview
    echo -e "${YELLOW}▶ System Status${NC}"
    
    # Check main services
    main_up=$(count_containers "n8n-main")
    workers_up=$(count_containers "n8n-worker")
    webhooks_up=$(count_containers "n8n-webhook")
    redis_up=$(count_containers "redis")
    postgres_up=$(count_containers "postgres")
    
    # Main status
    if [ "$main_up" = "1" ]; then
        echo -e "  Main:      $(get_status_emoji healthy) ${GREEN}Online${NC}"
    else
        echo -e "  Main:      $(get_status_emoji error) ${RED}Offline${NC}"
    fi
    
    # Workers status
    if [ "$workers_up" = "6" ]; then
        echo -e "  Workers:   $(get_status_emoji healthy) ${workers_up}/6 ${GREEN}Active${NC}"
    elif [ "$workers_up" -gt "0" ]; then
        echo -e "  Workers:   $(get_status_emoji warning) ${workers_up}/6 ${YELLOW}Partial${NC}"
    else
        echo -e "  Workers:   $(get_status_emoji error) ${workers_up}/6 ${RED}Down${NC}"
    fi
    
    # Webhooks status
    if [ "$webhooks_up" = "6" ]; then
        echo -e "  Webhooks:  $(get_status_emoji healthy) ${webhooks_up}/6 ${GREEN}Active${NC}"
    elif [ "$webhooks_up" -gt "0" ]; then
        echo -e "  Webhooks:  $(get_status_emoji warning) ${webhooks_up}/6 ${YELLOW}Partial${NC}"
    else
        echo -e "  Webhooks:  $(get_status_emoji error) ${webhooks_up}/6 ${RED}Down${NC}"
    fi
    
    # Redis status
    if [ "$redis_up" = "1" ]; then
        echo -e "  Redis:     $(get_status_emoji healthy) ${GREEN}Online${NC}"
    else
        echo -e "  Redis:     $(get_status_emoji error) ${RED}Offline${NC}"
    fi
    
    # Postgres status
    if [ "$postgres_up" = "1" ]; then
        echo -e "  Postgres:  $(get_status_emoji healthy) ${GREEN}Online${NC}"
    else
        echo -e "  Postgres:  $(get_status_emoji error) ${RED}Offline${NC}"
    fi
    
    echo ""
    
    # Queue Statistics
    echo -e "${YELLOW}▶ Queue Statistics${NC}"
    
    # Initialize default values
    waiting=0
    active=0
    completed=0
    failed=0
    
    # Get queue stats only if Redis is running
    if [ "$redis_up" = "1" ]; then
        queue_data=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning EVAL "
            local w = redis.call('LLEN', 'bull:jobs:wait') + redis.call('LLEN', 'bull:jobs:waiting')
            local a = redis.call('LLEN', 'bull:jobs:active')
            local c = redis.call('LLEN', 'bull:jobs:completed') + redis.call('ZCARD', 'bull:jobs:completed')
            local f = redis.call('LLEN', 'bull:jobs:failed') + redis.call('ZCARD', 'bull:jobs:failed')
            return w .. '|' .. a .. '|' .. c .. '|' .. f
        " 0 2>/dev/null || echo "0|0|0|0")
        
        IFS='|' read -r waiting active completed failed <<< "$queue_data"
    fi
    
    # Ensure numeric values
    waiting=${waiting:-0}
    active=${active:-0}
    completed=${completed:-0}
    failed=${failed:-0}
    
    # Clean any non-numeric characters
    waiting=$(echo "$waiting" | tr -cd '0-9')
    active=$(echo "$active" | tr -cd '0-9')
    completed=$(echo "$completed" | tr -cd '0-9')
    failed=$(echo "$failed" | tr -cd '0-9')
    
    # Set to 0 if empty
    [ -z "$waiting" ] && waiting=0
    [ -z "$active" ] && active=0
    [ -z "$completed" ] && completed=0
    [ -z "$failed" ] && failed=0
    
    # Display with visual bars
    max_queue=100  # Adjust based on your typical load
    
    printf "  Waiting:   %-6s %s\n" "$waiting" "$(create_bar $waiting $max_queue)"
    printf "  Active:    %-6s %s\n" "$active" "$(create_bar $active 20)"
    printf "  Completed: %-6s\n" "$completed"
    
    if [ "$failed" -gt "0" ]; then
        printf "  Failed:    %-6s ${RED}⚠️${NC}\n" "$failed"
    else
        printf "  Failed:    %-6s\n" "$failed"
    fi
    
    echo ""
    
    # Performance Metrics
    echo -e "${YELLOW}▶ Performance${NC}"
    
    # Redis ops/sec
    redis_ops="0"
    if [ "$redis_up" = "1" ]; then
        redis_ops=$(docker exec redis redis-cli -a "$REDIS_AUTH" --no-auth-warning INFO stats 2>/dev/null | grep instantaneous_ops_per_sec | cut -d: -f2 | tr -d '\r\n ' || echo "0")
    fi
    
    # Database size
    db_size="N/A"
    if [ "$postgres_up" = "1" ]; then
        db_size=$(docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB:-n8n}'));" 2>/dev/null | tr -d ' \n' || echo "N/A")
    fi
    
    # Recent executions
    recent_exec="0"
    if [ "$postgres_up" = "1" ]; then
        recent_exec=$(docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "
            SELECT COUNT(*) FROM execution_entity 
            WHERE \"startedAt\" > NOW() - INTERVAL '1 minute'
        " 2>/dev/null | tr -d ' \n' || echo "0")
    fi
    
    printf "  Redis Ops/sec:      %s\n" "$redis_ops"
    printf "  DB Size:            %s\n" "$db_size"
    printf "  Executions/min:     %s\n" "$recent_exec"
    
    echo ""
    
    # Alerts
    echo -e "${YELLOW}▶ Alerts${NC}"
    
    alerts=0
    
    # Check for high failure rate (ensure numeric comparison)
    if [ "$failed" -gt "10" ] 2>/dev/null; then
        echo -e "  ${RED}⚠️  High failure rate detected ($failed failed jobs)${NC}"
        ((alerts++))
    fi
    
    # Check for queue backup
    if [ "$waiting" -gt "50" ] 2>/dev/null; then
        echo -e "  ${YELLOW}⚠️  Queue backup detected ($waiting jobs waiting)${NC}"
        ((alerts++))
    fi
    
    # Check for worker issues
    if [ "$workers_up" -lt "4" ] 2>/dev/null; then
        echo -e "  ${RED}⚠️  Low worker count (only $workers_up/6 running)${NC}"
        ((alerts++))
    fi
    
    # Check for recent errors
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        error_count=$(docker compose logs --since 1m 2>&1 | grep -ciE "error|failed|exception" || echo "0")
        if [ "$error_count" -gt "5" ] 2>/dev/null; then
            echo -e "  ${RED}⚠️  High error rate ($error_count errors in last minute)${NC}"
            ((alerts++))
        fi
    fi
    
    if [ "$alerts" = "0" ]; then
        echo -e "  ${GREEN}✅ No alerts - System healthy${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo -e "Press ${RED}Ctrl+C${NC} to exit | Refreshing every 5 seconds..."
    
    sleep 5
done
