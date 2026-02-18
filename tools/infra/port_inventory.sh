#!/bin/bash
set -euo pipefail

###############################################################################
# port_inventory.sh — Scan project for port usage and detect conflicts
# Usage: port_inventory.sh [project_path]
# Exit codes: 0=OK, 1=conflicts found, 2=error
###############################################################################

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: Project path '$PROJECT_PATH' does not exist." >&2
  exit 2
fi

CONFLICTS=0
declare -A PORT_MAP  # port -> "service|file" entries

add_port() {
  local port="$1"
  local service="$2"
  local file="$3"

  # Skip common non-port numbers
  if [[ "$port" -lt 80 || "$port" -gt 65535 ]]; then
    return
  fi

  local entry="$service|$file"
  if [[ -v PORT_MAP[$port] ]]; then
    PORT_MAP[$port]="${PORT_MAP[$port]};$entry"
  else
    PORT_MAP[$port]="$entry"
  fi
}

echo "=============================================="
echo " Port Inventory"
echo " Project: $PROJECT_PATH"
echo "=============================================="
echo ""

# --- Scan docker-compose.yml ---
COMPOSE_FILES=$(find "$PROJECT_PATH" -maxdepth 2 \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) -not -path "*/node_modules/*" 2>/dev/null || true)

if [[ -n "$COMPOSE_FILES" ]]; then
  while IFS= read -r cf; do
    REL_FILE="${cf#$PROJECT_PATH/}"
    CURRENT_SERVICE=""

    while IFS= read -r line; do
      # Detect service name (indented key under services:)
      if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+):$ ]]; then
        CURRENT_SERVICE="${BASH_REMATCH[1]}"
      fi

      # Detect port mappings like "8080:80" or "- 3000:3000"
      if [[ "$line" =~ ([0-9]+):([0-9]+) ]]; then
        HOST_PORT="${BASH_REMATCH[1]}"
        CONTAINER_PORT="${BASH_REMATCH[2]}"
        SERVICE_NAME="${CURRENT_SERVICE:-unknown}"
        add_port "$HOST_PORT" "$SERVICE_NAME (host:$HOST_PORT->container:$CONTAINER_PORT)" "$REL_FILE"
      fi

      # Detect expose entries
      if [[ "$line" =~ expose: ]]; then
        : # next lines will be ports
      fi
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\"?([0-9]+)\"?$ ]]; then
        PORT="${BASH_REMATCH[1]}"
        add_port "$PORT" "${CURRENT_SERVICE:-unknown} (expose)" "$REL_FILE"
      fi
    done < "$cf"
  done <<< "$COMPOSE_FILES"
fi

# --- Scan .env files ---
ENV_FILES=$(find "$PROJECT_PATH" -maxdepth 2 -name ".env*" -not -path "*/node_modules/*" -not -name ".env.example" 2>/dev/null || true)

if [[ -n "$ENV_FILES" ]]; then
  while IFS= read -r ef; do
    REL_FILE="${ef#$PROJECT_PATH/}"
    while IFS= read -r line; do
      # Match PORT=NNNN patterns
      if [[ "$line" =~ ^([A-Z_]*PORT[A-Z_]*)=([0-9]+) ]]; then
        VAR_NAME="${BASH_REMATCH[1]}"
        PORT="${BASH_REMATCH[2]}"
        add_port "$PORT" "$VAR_NAME" "$REL_FILE"
      fi
    done < "$ef"
  done <<< "$ENV_FILES"
fi

# --- Scan nginx.conf ---
NGINX_FILES=$(find "$PROJECT_PATH" -maxdepth 3 -name "nginx*.conf" -not -path "*/node_modules/*" 2>/dev/null || true)

if [[ -n "$NGINX_FILES" ]]; then
  while IFS= read -r nf; do
    REL_FILE="${nf#$PROJECT_PATH/}"
    # Extract listen directives
    grep -oP "listen\s+\K[0-9]+" "$nf" 2>/dev/null | while IFS= read -r port; do
      add_port "$port" "nginx (listen)" "$REL_FILE"
    done || true

    # Extract proxy_pass ports
    grep -oP "proxy_pass\s+https?://[^:]+:\K[0-9]+" "$nf" 2>/dev/null | while IFS= read -r port; do
      add_port "$port" "nginx (proxy_pass)" "$REL_FILE"
    done || true
  done <<< "$NGINX_FILES"
fi

# --- Scan source code for common port patterns ---
SOURCE_DIRS=("$PROJECT_PATH/src" "$PROJECT_PATH/app" "$PROJECT_PATH/lib" "$PROJECT_PATH/server" "$PROJECT_PATH/api")
for sd in "${SOURCE_DIRS[@]}"; do
  if [[ -d "$sd" ]]; then
    # Look for .listen(PORT) or port: NNNN patterns
    grep -rn "\.listen(\s*[0-9]\+\|port.*[:=]\s*[0-9]\+" "$sd" \
      --include="*.ts" --include="*.js" --include="*.py" --include="*.go" --include="*.rb" \
      2>/dev/null | while IFS= read -r match; do
      FILE=$(echo "$match" | cut -d: -f1)
      REL_FILE="${FILE#$PROJECT_PATH/}"
      PORT=$(echo "$match" | grep -oP '[0-9]{4,5}' | head -1 || true)
      if [[ -n "$PORT" ]]; then
        add_port "$PORT" "source code" "$REL_FILE"
      fi
    done || true
  fi
done

# --- Scan package.json for scripts with ports ---
if [[ -f "$PROJECT_PATH/package.json" ]]; then
  grep -oP '"[^"]*":\s*"[^"]*--port[= ][0-9]+[^"]*"' "$PROJECT_PATH/package.json" 2>/dev/null | while IFS= read -r line; do
    PORT=$(echo "$line" | grep -oP '\-\-port[= ]\K[0-9]+' || true)
    SCRIPT_NAME=$(echo "$line" | grep -oP '^"[^"]+' | tr -d '"' || true)
    if [[ -n "$PORT" ]]; then
      add_port "$PORT" "npm script: $SCRIPT_NAME" "package.json"
    fi
  done || true
fi

# --- Output port table ---
echo "## Port Mapping Table"
echo ""
printf "  %-8s %-40s %s\n" "PORT" "SERVICE" "SOURCE"
printf "  %-8s %-40s %s\n" "----" "-------" "------"

for port in $(echo "${!PORT_MAP[@]}" | tr ' ' '\n' | sort -n); do
  IFS=';' read -ra ENTRIES <<< "${PORT_MAP[$port]}"
  for entry in "${ENTRIES[@]}"; do
    IFS='|' read -r service file <<< "$entry"
    printf "  %-8s %-40s %s\n" "$port" "$service" "$file"
  done
done
echo ""

# --- Detect conflicts ---
echo "## Port Conflicts"
echo ""

for port in $(echo "${!PORT_MAP[@]}" | tr ' ' '\n' | sort -n); do
  IFS=';' read -ra ENTRIES <<< "${PORT_MAP[$port]}"
  if [[ ${#ENTRIES[@]} -gt 1 ]]; then
    echo "  [CONFLICT] Port $port is used by multiple services:"
    for entry in "${ENTRIES[@]}"; do
      IFS='|' read -r service file <<< "$entry"
      echo "    - $service ($file)"
    done
    ((CONFLICTS++)) || true
    echo ""
  fi
done

if [[ $CONFLICTS -eq 0 ]]; then
  echo "  No port conflicts detected."
fi
echo ""

# --- Summary ---
TOTAL_PORTS=${#PORT_MAP[@]}
echo "=============================================="
echo " Summary: $TOTAL_PORTS unique port(s), $CONFLICTS conflict(s)"
echo "=============================================="

if [[ $CONFLICTS -gt 0 ]]; then
  exit 1
fi
exit 0
