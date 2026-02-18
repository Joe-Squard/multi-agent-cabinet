#!/bin/bash
set -euo pipefail

# endpoint_test.sh - Discover API endpoints and generate curl commands
# Usage: endpoint_test.sh [project_path] [--base-url=http://localhost:3000] [--smoke]
# Exit codes: 0=OK, 1=issues found, 2=error

usage() {
    cat <<'USAGE'
Usage: endpoint_test.sh [project_path] [options]

Options:
  --base-url=URL   Base URL for curl commands (default: http://localhost:3000)
  --smoke          Run smoke tests on GET endpoints

Examples:
  endpoint_test.sh
  endpoint_test.sh /path/to/project --base-url=http://localhost:8000
  endpoint_test.sh --smoke --base-url=http://localhost:3000
USAGE
    exit 2
}

# --- Parse Arguments ---
PROJECT_PATH=""
BASE_URL="http://localhost:3000"
RUN_SMOKE=false

for arg in "$@"; do
    case "$arg" in
        --base-url=*) BASE_URL="${arg#--base-url=}" ;;
        --smoke)      RUN_SMOKE=true ;;
        --help|-h)    usage ;;
        -*)           echo "ERROR: Unknown option: $arg" >&2; usage ;;
        *)
            if [[ -z "$PROJECT_PATH" ]]; then
                PROJECT_PATH="$arg"
            fi
            ;;
    esac
done

PROJECT_PATH="${PROJECT_PATH:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

# Remove trailing slash from base URL
BASE_URL="${BASE_URL%/}"

SRC_DIR="$PROJECT_PATH/src"
if [[ ! -d "$SRC_DIR" ]]; then
    SRC_DIR="$PROJECT_PATH"
fi

# Temporary file for endpoints
ENDPOINTS=$(mktemp)
trap 'rm -f "$ENDPOINTS"' EXIT

# Format: METHOD|PATH|SOURCE_FILE:LINE
# ============================================================
# Discover Express routes
# ============================================================

discover_express() {
    while IFS= read -r -d '' file; do
        local rel_path="${file#$PROJECT_PATH/}"
        local line_num=0

        while IFS= read -r line; do
            line_num=$((line_num + 1))
            local trimmed
            trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

            # Match patterns:
            # app.get('/path', ...)
            # router.get('/path', ...)
            # app.post('/path', ...)
            # router.use('/prefix', ...)
            if [[ "$trimmed" =~ (app|router)\.(get|post|put|patch|delete|head|options)\([[:space:]]*[\"\'](\/[^\"\']*)[\"\'] ]]; then
                local method="${BASH_REMATCH[2]}"
                local path="${BASH_REMATCH[3]}"
                method=$(echo "$method" | tr '[:lower:]' '[:upper:]')
                echo "${method}|${path}|${rel_path}:${line_num}" >> "$ENDPOINTS"
            fi
        done < "$file"
    done < <(find "$SRC_DIR" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.mjs" \) \
        ! -path "*/node_modules/*" ! -path "*/dist/*" ! -path "*/build/*" ! -path "*/.next/*" \
        ! -name "*.test.*" ! -name "*.spec.*" ! -name "*.d.ts" \
        -print0 2>/dev/null)
}

# ============================================================
# Discover FastAPI routes
# ============================================================

discover_fastapi() {
    while IFS= read -r -d '' file; do
        local rel_path="${file#$PROJECT_PATH/}"
        local line_num=0

        # Try to detect router prefix from file
        local prefix=""
        prefix=$(grep -oE 'prefix\s*=\s*["\x27](/[^"\x27]*)["\x27]' "$file" 2>/dev/null | head -1 | grep -oE '/[^"'\'']*' || true)

        while IFS= read -r line; do
            line_num=$((line_num + 1))
            local trimmed
            trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

            # Match patterns:
            # @app.get("/path")
            # @router.post("/path")
            if [[ "$trimmed" =~ @(app|router)\.(get|post|put|patch|delete|head|options)\([[:space:]]*[\"\'](\/[^\"\']*)[\"\'] ]]; then
                local method="${BASH_REMATCH[2]}"
                local path="${BASH_REMATCH[3]}"
                method=$(echo "$method" | tr '[:lower:]' '[:upper:]')
                echo "${method}|${prefix}${path}|${rel_path}:${line_num}" >> "$ENDPOINTS"
            fi
        done < "$file"
    done < <(find "$SRC_DIR" "$PROJECT_PATH/app" -type f -name "*.py" \
        ! -path "*/.venv/*" ! -path "*/venv/*" ! -path "*/__pycache__/*" \
        ! -name "test_*" ! -name "*_test.py" \
        -print0 2>/dev/null)
}

# ============================================================
# Discover NestJS routes
# ============================================================

discover_nestjs() {
    while IFS= read -r -d '' file; do
        local rel_path="${file#$PROJECT_PATH/}"
        local line_num=0
        local controller_prefix=""

        # First pass: find @Controller prefix
        controller_prefix=$(grep -oE "@Controller\(['\"]([^'\"]*)['\"]" "$file" 2>/dev/null | head -1 | grep -oE "['\"][^'\"]*['\"]" | tr -d "'\""  || true)
        if [[ -n "$controller_prefix" && ! "$controller_prefix" =~ ^/ ]]; then
            controller_prefix="/$controller_prefix"
        fi

        while IFS= read -r line; do
            line_num=$((line_num + 1))
            local trimmed
            trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

            # Match: @Get(), @Post(), @Put(), @Delete(), @Patch()
            if [[ "$trimmed" =~ @(Get|Post|Put|Delete|Patch|Head|Options)\(([^\)]*)\) ]]; then
                local method="${BASH_REMATCH[1]}"
                local path_arg="${BASH_REMATCH[2]}"
                method=$(echo "$method" | tr '[:lower:]' '[:upper:]')

                # Extract path from decorator argument
                local path=""
                if [[ -n "$path_arg" ]]; then
                    path=$(echo "$path_arg" | grep -oE "['\"]([^'\"]*)['\"]" | tr -d "'\""  || true)
                fi

                if [[ -n "$path" && ! "$path" =~ ^/ ]]; then
                    path="/$path"
                fi

                local full_path="${controller_prefix}${path}"
                [[ -z "$full_path" ]] && full_path="${controller_prefix}/"

                echo "${method}|${full_path}|${rel_path}:${line_num}" >> "$ENDPOINTS"
            fi
        done < "$file"
    done < <(find "$SRC_DIR" -type f -name "*.controller.ts" \
        ! -path "*/node_modules/*" ! -path "*/dist/*" \
        -print0 2>/dev/null)
}

# ============================================================
# Discover Hono/Fastify routes (similar pattern to Express)
# ============================================================

discover_hono() {
    while IFS= read -r -d '' file; do
        local rel_path="${file#$PROJECT_PATH/}"
        local line_num=0

        while IFS= read -r line; do
            line_num=$((line_num + 1))
            local trimmed
            trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

            # Hono: app.get('/path', (c) => ...)
            if [[ "$trimmed" =~ \.(get|post|put|patch|delete)\([[:space:]]*[\"\'](\/[^\"\']*)[\"\'] ]]; then
                local method="${BASH_REMATCH[1]}"
                local path="${BASH_REMATCH[2]}"
                method=$(echo "$method" | tr '[:lower:]' '[:upper:]')
                echo "${method}|${path}|${rel_path}:${line_num}" >> "$ENDPOINTS"
            fi
        done < "$file"
    done < <(find "$SRC_DIR" -type f \( -name "*.ts" -o -name "*.js" \) \
        ! -path "*/node_modules/*" ! -path "*/dist/*" \
        ! -name "*.test.*" ! -name "*.spec.*" \
        -print0 2>/dev/null)
}

# ============================================================
# Run Discovery
# ============================================================

echo "========================================"
echo " API Endpoint Discovery"
echo "========================================"
echo ""
echo "  Project: $PROJECT_PATH"
echo "  Base URL: $BASE_URL"
echo ""

# Auto-detect framework and run appropriate discovery
FRAMEWORK="unknown"

if [[ -f "$PROJECT_PATH/package.json" ]]; then
    if grep -q '"@nestjs/core"' "$PROJECT_PATH/package.json" 2>/dev/null; then
        FRAMEWORK="nestjs"
        discover_nestjs
    fi
    if grep -q '"express"' "$PROJECT_PATH/package.json" 2>/dev/null; then
        FRAMEWORK="express"
        discover_express
    fi
    if grep -q '"hono"' "$PROJECT_PATH/package.json" 2>/dev/null; then
        FRAMEWORK="hono"
        discover_hono
    fi
    if grep -q '"fastify"' "$PROJECT_PATH/package.json" 2>/dev/null; then
        FRAMEWORK="fastify"
        discover_express  # Similar patterns
    fi
fi

# Also check for Python
for pyfile in "$PROJECT_PATH/pyproject.toml" "$PROJECT_PATH/requirements.txt"; do
    if [[ -f "$pyfile" ]] && grep -qi "fastapi\|starlette" "$pyfile" 2>/dev/null; then
        FRAMEWORK="fastapi"
        discover_fastapi
        break
    fi
done

# If nothing specific detected, try all patterns
if [[ ! -s "$ENDPOINTS" ]]; then
    discover_express
    discover_fastapi
    discover_nestjs
fi

# ============================================================
# Output Results
# ============================================================

if [[ ! -s "$ENDPOINTS" ]]; then
    echo "  No API endpoints discovered."
    echo ""
    echo "  Supported patterns:"
    echo "    Express:  app.get('/path', ...) / router.post('/path', ...)"
    echo "    FastAPI:  @app.get('/path') / @router.post('/path')"
    echo "    NestJS:   @Get('path') / @Post('path')"
    echo ""
    exit 1
fi

ENDPOINT_COUNT=$(wc -l < "$ENDPOINTS")
echo "  Framework: $FRAMEWORK"
echo "  Endpoints found: $ENDPOINT_COUNT"
echo ""

# Sort by path, then method
sort -t'|' -k2,2 -k1,1 "$ENDPOINTS" > "${ENDPOINTS}.sorted"
mv "${ENDPOINTS}.sorted" "$ENDPOINTS"

echo "========================================"
echo " Discovered Endpoints"
echo "========================================"
echo ""

printf "  %-8s %-40s %s\n" "Method" "Path" "Source"
echo "  ------  ----------------------------------------  -------------------"

while IFS='|' read -r method path source; do
    printf "  %-8s %-40s %s\n" "$method" "$path" "$source"
done < "$ENDPOINTS"

echo ""

# ============================================================
# Generate curl commands
# ============================================================

echo "========================================"
echo " Generated curl Commands"
echo "========================================"
echo ""

while IFS='|' read -r method path source; do
    # Convert path parameters: :id -> {id}, {id} stays
    local curl_path
    curl_path=$(echo "$path" | sed 's/:([a-zA-Z_][a-zA-Z0-9_]*)/{__\1__}/g' | sed 's/:/__PARAM__/g')
    # Replace Express-style :param with example values
    curl_path=$(echo "$path" | sed 's/:[a-zA-Z_][a-zA-Z0-9_]*/1/g')
    # Replace Python-style {param} with example values
    curl_path=$(echo "$curl_path" | sed 's/{[a-zA-Z_][a-zA-Z0-9_]*}/1/g')

    local url="${BASE_URL}${curl_path}"

    case "$method" in
        GET)
            echo "# $method $path ($source)"
            echo "curl -s -w '\\n%{http_code}' '$url'"
            echo ""
            ;;
        POST)
            echo "# $method $path ($source)"
            echo "curl -s -w '\\n%{http_code}' -X POST '$url' \\"
            echo "  -H 'Content-Type: application/json' \\"
            echo "  -d '{\"key\": \"value\"}'"
            echo ""
            ;;
        PUT|PATCH)
            echo "# $method $path ($source)"
            echo "curl -s -w '\\n%{http_code}' -X $method '$url' \\"
            echo "  -H 'Content-Type: application/json' \\"
            echo "  -d '{\"key\": \"updated_value\"}'"
            echo ""
            ;;
        DELETE)
            echo "# $method $path ($source)"
            echo "curl -s -w '\\n%{http_code}' -X DELETE '$url'"
            echo ""
            ;;
        *)
            echo "# $method $path ($source)"
            echo "curl -s -w '\\n%{http_code}' -X $method '$url'"
            echo ""
            ;;
    esac
done < "$ENDPOINTS"

# ============================================================
# Smoke Test (optional)
# ============================================================

if [[ "$RUN_SMOKE" == true ]]; then
    echo "========================================"
    echo " Smoke Test Results (GET endpoints)"
    echo "========================================"
    echo ""

    # Check if base URL is reachable
    if ! curl -s --connect-timeout 3 "$BASE_URL" > /dev/null 2>&1; then
        echo "  [ERROR] Cannot connect to $BASE_URL"
        echo "  Make sure the server is running."
        echo ""
        exit 1
    fi

    PASS=0
    FAIL=0

    while IFS='|' read -r method path source; do
        if [[ "$method" != "GET" ]]; then
            continue
        fi

        # Skip parameterized routes for smoke test
        if echo "$path" | grep -qE ':[a-zA-Z]|\{[a-zA-Z]'; then
            echo "  [SKIP] $method $path (parameterized)"
            continue
        fi

        local url="${BASE_URL}${path}"
        local status
        status=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")

        if [[ "$status" =~ ^2 ]]; then
            echo "  [PASS] $method $path -> $status"
            PASS=$((PASS + 1))
        elif [[ "$status" =~ ^3 ]]; then
            echo "  [REDIR] $method $path -> $status"
            PASS=$((PASS + 1))
        elif [[ "$status" == "000" ]]; then
            echo "  [TIMEOUT] $method $path -> timeout"
            FAIL=$((FAIL + 1))
        else
            echo "  [FAIL] $method $path -> $status"
            FAIL=$((FAIL + 1))
        fi
    done < "$ENDPOINTS"

    echo ""
    echo "  Results: $PASS passed, $FAIL failed"
    echo ""

    if [[ $FAIL -gt 0 ]]; then
        ISSUES=$((ISSUES + FAIL))
    fi
fi

# ============================================================
# Summary
# ============================================================

echo "========================================"
echo " Summary"
echo "========================================"
echo ""

# Count by method
for m in GET POST PUT PATCH DELETE; do
    count=$(grep -c "^${m}|" "$ENDPOINTS" 2>/dev/null || true)
    if [[ $count -gt 0 ]]; then
        printf "  %-8s %d endpoint(s)\n" "$m" "$count"
    fi
done
echo ""
echo "  Total: $ENDPOINT_COUNT endpoints"
echo ""

exit 0
