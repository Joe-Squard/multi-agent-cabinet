#!/bin/bash
set -euo pipefail

###############################################################################
# service_health.sh — Check service health: containers, ports, processes
# Usage: service_health.sh [project_path]
# Exit codes: 0=all healthy, 1=issues found, 2=error
###############################################################################

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

ISSUES=0

check_port() {
  local port=$1
  if command -v nc &>/dev/null; then
    nc -z -w2 127.0.0.1 "$port" 2>/dev/null
  elif command -v bash &>/dev/null; then
    (echo >/dev/tcp/127.0.0.1/"$port") 2>/dev/null
  else
    return 1
  fi
}

echo "=============================================="
echo " Service Health Check"
echo " Project: $PROJECT_PATH"
echo " Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="
echo ""

# --- Docker containers ---
echo "## Docker Containers"
echo ""

if command -v docker &>/dev/null; then
  CONTAINERS=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}" 2>/dev/null || true)

  if [[ -n "$CONTAINERS" ]]; then
    echo "| Container | Status | Ports | Image |"
    echo "|-----------|--------|-------|-------|"
    docker ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}" 2>/dev/null | while IFS=$'\t' read -r name status ports image; do
      # Determine health indicator
      HEALTH="ok"
      if [[ "$status" == *"unhealthy"* ]]; then
        HEALTH="unhealthy"
        ((ISSUES++)) || true
      elif [[ "$status" == *"restarting"* ]]; then
        HEALTH="restarting"
        ((ISSUES++)) || true
      fi
      echo "| $name | $status | ${ports:-none} | $image |"
    done || true
    echo ""

    # Check for stopped containers related to project
    STOPPED=$(docker ps -a --filter "status=exited" --format "{{.Names}}\t{{.Status}}" 2>/dev/null || true)
    if [[ -n "$STOPPED" ]]; then
      echo "  Stopped containers:"
      echo "$STOPPED" | while IFS=$'\t' read -r name status; do
        echo "    [DOWN] $name — $status"
      done
      echo ""
    fi
  else
    echo "  No running containers."
    echo ""
  fi
else
  echo "  Docker not available."
  echo ""
fi

# --- Port accessibility ---
echo "## Port Accessibility"
echo ""

COMMON_PORTS=(
  "80:HTTP"
  "443:HTTPS"
  "3000:Dev Server / React"
  "3001:Alt Dev Server"
  "4000:GraphQL"
  "5000:Flask / Generic"
  "5173:Vite"
  "5432:PostgreSQL"
  "6379:Redis"
  "8000:Django / FastAPI"
  "8080:Alt HTTP / Proxy"
  "8443:Alt HTTPS"
  "8888:Jupyter"
  "9090:Prometheus"
  "9200:Elasticsearch"
  "27017:MongoDB"
)

echo "| Port | Service | Status |"
echo "|------|---------|--------|"

OPEN_PORTS=0
for entry in "${COMMON_PORTS[@]}"; do
  IFS=':' read -r port service <<< "$entry"
  if check_port "$port"; then
    echo "| $port | $service | OPEN |"
    ((OPEN_PORTS++)) || true
  fi
done

# Also check project-specific ports from docker-compose
COMPOSE_FILE=""
for name in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
  if [[ -f "$PROJECT_PATH/$name" ]]; then
    COMPOSE_FILE="$PROJECT_PATH/$name"
    break
  fi
done

if [[ -n "$COMPOSE_FILE" ]]; then
  grep -oP '(\d+):\d+' "$COMPOSE_FILE" 2>/dev/null | cut -d: -f1 | sort -un | while read -r port; do
    # Skip if already in common ports
    SKIP=false
    for entry in "${COMMON_PORTS[@]}"; do
      COMMON_PORT="${entry%%:*}"
      if [[ "$port" == "$COMMON_PORT" ]]; then
        SKIP=true
        break
      fi
    done
    if ! $SKIP; then
      if check_port "$port"; then
        echo "| $port | compose service | OPEN |"
        ((OPEN_PORTS++)) || true
      fi
    fi
  done || true
fi

if [[ $OPEN_PORTS -eq 0 ]]; then
  echo "| - | - | No open ports detected |"
fi
echo ""

# --- Running processes ---
echo "## Running Processes"
echo ""

echo "| PID | Process | Command |"
echo "|-----|---------|---------|"

FOUND_PROCS=false

# Node processes
if pgrep -x "node" &>/dev/null; then
  FOUND_PROCS=true
  ps -eo pid,comm,args --no-headers 2>/dev/null | grep -E "^\s*[0-9]+\s+node\s+" | head -10 | while read -r pid comm args; do
    SHORT_ARGS="${args:0:80}"
    echo "| $pid | node | $SHORT_ARGS |"
  done || true
fi

# Python processes
if pgrep -x "python3\|python" &>/dev/null; then
  FOUND_PROCS=true
  ps -eo pid,comm,args --no-headers 2>/dev/null | grep -E "^\s*[0-9]+\s+python" | head -10 | while read -r pid comm args; do
    SHORT_ARGS="${args:0:80}"
    echo "| $pid | python | $SHORT_ARGS |"
  done || true
fi

# Java processes
if pgrep -x "java" &>/dev/null; then
  FOUND_PROCS=true
  ps -eo pid,comm,args --no-headers 2>/dev/null | grep -E "^\s*[0-9]+\s+java\s+" | head -10 | while read -r pid comm args; do
    SHORT_ARGS="${args:0:80}"
    echo "| $pid | java | $SHORT_ARGS |"
  done || true
fi

# Go processes (check for common Go server names)
if pgrep -f "go run\|gin\|fiber" &>/dev/null; then
  FOUND_PROCS=true
  ps -eo pid,comm,args --no-headers 2>/dev/null | grep -E "go run|gin|fiber" | head -5 | while read -r pid comm args; do
    SHORT_ARGS="${args:0:80}"
    echo "| $pid | go | $SHORT_ARGS |"
  done || true
fi

if ! $FOUND_PROCS; then
  echo "| - | - | No relevant processes found |"
fi
echo ""

# --- Disk usage ---
echo "## Disk Usage (Project)"
echo ""

if [[ -d "$PROJECT_PATH" ]]; then
  PROJ_SIZE=$(du -sh "$PROJECT_PATH" 2>/dev/null | cut -f1 || echo "unknown")
  echo "  Project total:       $PROJ_SIZE"

  if [[ -d "$PROJECT_PATH/node_modules" ]]; then
    NM_SIZE=$(du -sh "$PROJECT_PATH/node_modules" 2>/dev/null | cut -f1 || echo "unknown")
    echo "  node_modules:        $NM_SIZE"
  fi

  if [[ -d "$PROJECT_PATH/.git" ]]; then
    GIT_SIZE=$(du -sh "$PROJECT_PATH/.git" 2>/dev/null | cut -f1 || echo "unknown")
    echo "  .git:                $GIT_SIZE"
  fi

  DISK_FREE=$(df -h "$PROJECT_PATH" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
  echo "  Disk free:           $DISK_FREE"
fi
echo ""

# --- Summary ---
echo "=============================================="
echo " Health Check Complete"
echo " Open ports: $OPEN_PORTS"
echo " Issues: $ISSUES"
echo "=============================================="

if [[ $ISSUES -gt 0 ]]; then
  exit 1
fi
exit 0
