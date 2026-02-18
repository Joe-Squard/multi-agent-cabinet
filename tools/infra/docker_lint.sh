#!/bin/bash
set -euo pipefail

###############################################################################
# docker_lint.sh — Lint Dockerfiles and docker-compose.yml for best practices
# Usage: docker_lint.sh [project_path]
# Exit codes: 0=OK, 1=issues found, 2=error
###############################################################################

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: Project path '$PROJECT_PATH' does not exist." >&2
  exit 2
fi

ISSUES=0
WARNINGS=0

report() {
  local severity="$1"
  local message="$2"
  local file="${3:-}"

  case "$severity" in
    ERROR)   ((ISSUES++)) || true;   printf "  [ERROR]   %s" "$message" ;;
    WARN)    ((WARNINGS++)) || true;  printf "  [WARN]    %s" "$message" ;;
    INFO)    printf "  [INFO]    %s" "$message" ;;
  esac

  if [[ -n "$file" ]]; then
    printf " (%s)" "${file#$PROJECT_PATH/}"
  fi
  echo ""
}

echo "=============================================="
echo " Docker Lint Report"
echo " Project: $PROJECT_PATH"
echo "=============================================="
echo ""

# --- Find Dockerfiles ---
DOCKERFILES=$(find "$PROJECT_PATH" -maxdepth 3 -name "Dockerfile*" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null || true)

echo "## Dockerfile Analysis"
echo ""

if [[ -z "$DOCKERFILES" ]]; then
  echo "  No Dockerfiles found."
  echo ""
else
  while IFS= read -r df; do
    echo "  --- ${df#$PROJECT_PATH/} ---"

    # Check for :latest tag
    if grep -qE "^FROM\s+\S+:latest" "$df" 2>/dev/null; then
      report "WARN" "Uses :latest tag — pin to specific version for reproducibility" "$df"
    elif grep -qE "^FROM\s+[^:]+\s*$" "$df" 2>/dev/null; then
      report "WARN" "FROM without tag defaults to :latest — pin to specific version" "$df"
    fi

    # Check for multi-stage builds
    FROM_COUNT=$(grep -c "^FROM " "$df" 2>/dev/null || echo "0")
    if [[ "$FROM_COUNT" -le 1 ]]; then
      report "INFO" "Single-stage build — consider multi-stage to reduce image size" "$df"
    else
      echo "  [OK]      Multi-stage build detected ($FROM_COUNT stages)"
    fi

    # Check for running as root
    if ! grep -q "^USER " "$df" 2>/dev/null; then
      report "WARN" "No USER instruction — container runs as root by default" "$df"
    fi

    # Count RUN layers
    RUN_COUNT=$(grep -c "^RUN " "$df" 2>/dev/null || echo "0")
    if [[ "$RUN_COUNT" -gt 10 ]]; then
      report "WARN" "Too many RUN layers ($RUN_COUNT) — combine with && to reduce layers" "$df"
    fi

    # Check for COPY vs ADD
    if grep -q "^ADD " "$df" 2>/dev/null; then
      ADD_COUNT=$(grep -c "^ADD " "$df" 2>/dev/null || echo "0")
      report "INFO" "Uses ADD ($ADD_COUNT times) — prefer COPY unless extracting archives" "$df"
    fi

    # Check for apt-get without --no-install-recommends
    if grep -q "apt-get install" "$df" 2>/dev/null; then
      if ! grep -q "\-\-no-install-recommends" "$df" 2>/dev/null; then
        report "WARN" "apt-get install without --no-install-recommends" "$df"
      fi
    fi

    # Check for apt-get without cleanup
    if grep -q "apt-get install" "$df" 2>/dev/null; then
      if ! grep -q "rm -rf /var/lib/apt/lists" "$df" 2>/dev/null; then
        report "WARN" "apt-get install without cleaning /var/lib/apt/lists" "$df"
      fi
    fi

    echo ""
  done <<< "$DOCKERFILES"
fi

# --- Check for .dockerignore ---
echo "## .dockerignore"
echo ""

DOCKERIGNORE="$PROJECT_PATH/.dockerignore"
if [[ ! -f "$DOCKERIGNORE" ]]; then
  report "WARN" "Missing .dockerignore — build context may include unnecessary files"
else
  echo "  [OK]      .dockerignore found"
  IGNORE_COUNT=$(wc -l < "$DOCKERIGNORE")
  echo "  [INFO]    $IGNORE_COUNT rules defined"

  # Check if common exclusions are present
  for pattern in "node_modules" ".git" ".env"; do
    if ! grep -q "$pattern" "$DOCKERIGNORE" 2>/dev/null; then
      report "WARN" ".dockerignore missing '$pattern' exclusion"
    fi
  done
fi
echo ""

# --- docker-compose.yml analysis ---
echo "## Docker Compose Analysis"
echo ""

COMPOSE_FILES=$(find "$PROJECT_PATH" -maxdepth 2 \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) -not -path "*/node_modules/*" 2>/dev/null || true)

if [[ -z "$COMPOSE_FILES" ]]; then
  echo "  No docker-compose files found."
  echo ""
else
  while IFS= read -r cf; do
    echo "  --- ${cf#$PROJECT_PATH/} ---"

    # Check for healthchecks
    SERVICE_COUNT=$(grep -c "^\s\+\S\+:" "$cf" 2>/dev/null || echo "0")
    HEALTHCHECK_COUNT=$(grep -c "healthcheck:" "$cf" 2>/dev/null || echo "0")
    if [[ "$HEALTHCHECK_COUNT" -eq 0 ]]; then
      report "WARN" "No healthchecks defined for any service" "$cf"
    elif [[ "$HEALTHCHECK_COUNT" -lt "$SERVICE_COUNT" ]]; then
      report "INFO" "Only $HEALTHCHECK_COUNT of ~$SERVICE_COUNT services have healthchecks" "$cf"
    fi

    # Check for exposed ports
    PORTS_LINES=$(grep -n "^\s*-\s*[\"']*[0-9]" "$cf" 2>/dev/null | grep -v "#" || true)
    if [[ -n "$PORTS_LINES" ]]; then
      # Check for binding to 0.0.0.0 (all interfaces)
      EXPOSED=$(echo "$PORTS_LINES" | grep -v "127.0.0.1" | grep -v "localhost" || true)
      if [[ -n "$EXPOSED" ]]; then
        EXPOSED_COUNT=$(echo "$EXPOSED" | wc -l)
        report "INFO" "$EXPOSED_COUNT port(s) bound to all interfaces (consider 127.0.0.1: prefix)" "$cf"
      fi
    fi

    # Check for resource limits
    if ! grep -q "mem_limit\|deploy:" "$cf" 2>/dev/null; then
      report "WARN" "No resource limits (mem_limit/deploy.resources) defined" "$cf"
    fi

    # Check for restart policy
    if ! grep -q "restart:" "$cf" 2>/dev/null; then
      report "INFO" "No restart policy defined — containers won't restart on failure" "$cf"
    fi

    # Check for :latest in images
    if grep -qE "image:.*:latest" "$cf" 2>/dev/null; then
      report "WARN" "Uses :latest tag in image reference — pin to specific version" "$cf"
    fi

    # Check for environment secrets in compose file
    if grep -qE "PASSWORD|SECRET|API_KEY|TOKEN" "$cf" 2>/dev/null; then
      if ! grep -q "env_file\|secrets:" "$cf" 2>/dev/null; then
        report "ERROR" "Possible secrets in compose file — use env_file or Docker secrets" "$cf"
      fi
    fi

    echo ""
  done <<< "$COMPOSE_FILES"
fi

# --- Summary ---
echo "=============================================="
printf " Summary: %d error(s), %d warning(s)\n" "$ISSUES" "$WARNINGS"
echo "=============================================="

if [[ $ISSUES -gt 0 ]]; then
  exit 1
fi
exit 0
