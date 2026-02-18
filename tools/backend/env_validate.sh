#!/bin/bash
set -euo pipefail

# env_validate.sh - Validate .env files against .env.example and source code
# Usage: env_validate.sh [project_path]
# Exit codes: 0=OK, 1=issues found, 2=error

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

ISSUES=0

echo "========================================"
echo " Environment Variable Validation"
echo "========================================"
echo ""
echo "  Project: $PROJECT_PATH"
echo ""

# --- Find .env files ---
ENV_FILE=""
ENV_EXAMPLE=""

for candidate in "$PROJECT_PATH/.env" "$PROJECT_PATH/.env.local"; do
    if [[ -f "$candidate" ]]; then
        ENV_FILE="$candidate"
        break
    fi
done

for candidate in "$PROJECT_PATH/.env.example" "$PROJECT_PATH/.env.sample" "$PROJECT_PATH/.env.template"; do
    if [[ -f "$candidate" ]]; then
        ENV_EXAMPLE="$candidate"
        break
    fi
done

echo "  .env file:     ${ENV_FILE:-(not found)}"
echo "  .env.example:  ${ENV_EXAMPLE:-(not found)}"
echo ""

# --- Helper: extract variable names from env file ---
extract_vars() {
    local file="$1"
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$file" 2>/dev/null | cut -d= -f1 | sort -u
}

# --- Helper: extract variable value ---
get_value() {
    local file="$1" var="$2"
    grep -E "^${var}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^["'\'']\(.*\)["'\'']$/\1/'
}

# ============================================================
# Check 1: .env vs .env.example comparison
# ============================================================

if [[ -n "$ENV_FILE" && -n "$ENV_EXAMPLE" ]]; then
    echo "========================================"
    echo " .env vs .env.example Comparison"
    echo "========================================"
    echo ""

    ENV_VARS=$(extract_vars "$ENV_FILE")
    EXAMPLE_VARS=$(extract_vars "$ENV_EXAMPLE")

    # Variables in .env.example but missing from .env
    MISSING_FROM_ENV=""
    while IFS= read -r var; do
        if ! echo "$ENV_VARS" | grep -qx "$var"; then
            MISSING_FROM_ENV+="    $var"$'\n'
            ISSUES=$((ISSUES + 1))
        fi
    done <<< "$EXAMPLE_VARS"

    if [[ -n "$MISSING_FROM_ENV" ]]; then
        echo "  [!] Variables in .env.example but MISSING from .env:"
        echo "$MISSING_FROM_ENV"
    else
        echo "  [OK] All .env.example variables present in .env"
        echo ""
    fi

    # Variables in .env but not in .env.example
    EXTRA_IN_ENV=""
    while IFS= read -r var; do
        [[ -z "$var" ]] && continue
        if ! echo "$EXAMPLE_VARS" | grep -qx "$var"; then
            EXTRA_IN_ENV+="    $var"$'\n'
        fi
    done <<< "$ENV_VARS"

    if [[ -n "$EXTRA_IN_ENV" ]]; then
        echo "  [INFO] Variables in .env but NOT in .env.example (consider adding):"
        echo "$EXTRA_IN_ENV"
    fi
fi

# ============================================================
# Check 2: Source code references
# ============================================================

echo "========================================"
echo " Source Code Environment References"
echo "========================================"
echo ""

SRC_DIR="$PROJECT_PATH/src"
if [[ ! -d "$SRC_DIR" ]]; then
    SRC_DIR="$PROJECT_PATH"
fi

# Collect env var references from source code
SOURCE_VARS=$(mktemp)
trap 'rm -f "$SOURCE_VARS"' EXIT

# Node.js: process.env.VAR_NAME
find "$SRC_DIR" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.mjs" -o -name "*.cjs" \) \
    ! -path "*/node_modules/*" ! -path "*/dist/*" ! -path "*/build/*" ! -path "*/.next/*" \
    -print0 2>/dev/null | while IFS= read -r -d '' f; do
    grep -oE 'process\.env\.([A-Za-z_][A-Za-z0-9_]*)' "$f" 2>/dev/null | \
        sed 's/process\.env\.//' || true
done >> "$SOURCE_VARS"

# Also check process.env['VAR'] and process.env["VAR"]
find "$SRC_DIR" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
    ! -path "*/node_modules/*" ! -path "*/dist/*" \
    -print0 2>/dev/null | while IFS= read -r -d '' f; do
    grep -oE "process\.env\[['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]" "$f" 2>/dev/null | \
        grep -oE "['\"][A-Za-z_][A-Za-z0-9_]*['\"]" | tr -d "'\""  || true
done >> "$SOURCE_VARS"

# Python: os.environ.get('VAR'), os.environ['VAR'], os.getenv('VAR')
find "$SRC_DIR" -type f -name "*.py" \
    ! -path "*/.venv/*" ! -path "*/venv/*" ! -path "*/__pycache__/*" \
    -print0 2>/dev/null | while IFS= read -r -d '' f; do
    grep -oE "os\.(environ\.get|environ\[|getenv)\(['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]" "$f" 2>/dev/null | \
        grep -oE "['\"][A-Za-z_][A-Za-z0-9_]*['\"]" | tr -d "'\""  || true
done >> "$SOURCE_VARS"

# Also check: import from dotenv, config patterns, Vite import.meta.env
find "$SRC_DIR" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
    ! -path "*/node_modules/*" ! -path "*/dist/*" \
    -print0 2>/dev/null | while IFS= read -r -d '' f; do
    grep -oE 'import\.meta\.env\.([A-Za-z_][A-Za-z0-9_]*)' "$f" 2>/dev/null | \
        sed 's/import\.meta\.env\.//' || true
done >> "$SOURCE_VARS"

UNIQUE_SOURCE_VARS=$(sort -u "$SOURCE_VARS")
SOURCE_VAR_COUNT=$(echo "$UNIQUE_SOURCE_VARS" | grep -c . || true)

echo "  Found $SOURCE_VAR_COUNT unique environment variable references in source."
echo ""

if [[ $SOURCE_VAR_COUNT -gt 0 && -n "$ENV_FILE" ]]; then
    ENV_VARS=$(extract_vars "$ENV_FILE")

    MISSING_FROM_ENV_FILE=""
    while IFS= read -r var; do
        [[ -z "$var" ]] && continue
        # Skip common built-in vars
        case "$var" in
            NODE_ENV|HOME|PATH|USER|SHELL|PWD|LANG|TERM|HOSTNAME) continue ;;
        esac
        if ! echo "$ENV_VARS" | grep -qx "$var"; then
            MISSING_FROM_ENV_FILE+="    $var"$'\n'
            ISSUES=$((ISSUES + 1))
        fi
    done <<< "$UNIQUE_SOURCE_VARS"

    if [[ -n "$MISSING_FROM_ENV_FILE" ]]; then
        echo "  [!] Variables referenced in source but MISSING from .env:"
        echo "$MISSING_FROM_ENV_FILE"
    else
        echo "  [OK] All source-referenced variables are defined in .env"
        echo ""
    fi
fi

# ============================================================
# Check 3: Empty values
# ============================================================

if [[ -n "$ENV_FILE" ]]; then
    echo "========================================"
    echo " Empty Value Check"
    echo "========================================"
    echo ""

    EMPTY_VARS=""
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=$ ]] || [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=[\"\']{2}$ ]]; then
            local var="${BASH_REMATCH[1]}"
            EMPTY_VARS+="    $var"$'\n'
        fi
    done < "$ENV_FILE"

    if [[ -n "$EMPTY_VARS" ]]; then
        echo "  [!] Variables with empty values in .env:"
        echo "$EMPTY_VARS"
        ISSUES=$((ISSUES + $(echo "$EMPTY_VARS" | grep -c . || true)))
    else
        echo "  [OK] No empty values found."
        echo ""
    fi
fi

# ============================================================
# Check 4: Sensitive variable audit
# ============================================================

if [[ -n "$ENV_FILE" ]]; then
    echo "========================================"
    echo " Sensitive Variable Audit"
    echo "========================================"
    echo ""

    SENSITIVE_PATTERNS="PASSWORD|SECRET|KEY|TOKEN|API_KEY|PRIVATE|CREDENTIAL|AUTH|ACCESS_KEY|JWT"
    SENSITIVE_ISSUES=""

    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*) ]]; then
            local var="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"

            # Check if variable name looks sensitive
            if echo "$var" | grep -qiE "$SENSITIVE_PATTERNS"; then
                # Strip quotes
                val=$(echo "$val" | sed 's/^["'\'']//' | sed 's/["'\'']$//')

                if [[ -z "$val" ]]; then
                    SENSITIVE_ISSUES+="    [EMPTY]   $var (sensitive variable has no value!)"$'\n'
                    ISSUES=$((ISSUES + 1))
                elif [[ "$val" == "changeme" || "$val" == "todo" || "$val" == "xxx" || "$val" == "placeholder" || "$val" == "your-"* ]]; then
                    SENSITIVE_ISSUES+="    [PLACEHOLDER] $var (still has placeholder value)"$'\n'
                    ISSUES=$((ISSUES + 1))
                else
                    SENSITIVE_ISSUES+="    [SET]     $var"$'\n'
                fi
            fi
        fi
    done < "$ENV_FILE"

    if [[ -n "$SENSITIVE_ISSUES" ]]; then
        echo "$SENSITIVE_ISSUES"
    else
        echo "  No sensitive variable names detected."
        echo ""
    fi
fi

# ============================================================
# Check 5: .env in .gitignore
# ============================================================

echo "========================================"
echo " Security Check"
echo "========================================"
echo ""

if [[ -f "$PROJECT_PATH/.gitignore" ]]; then
    if grep -qE '^\\.env$|^\\.env\.' "$PROJECT_PATH/.gitignore" 2>/dev/null; then
        echo "  [OK] .env is listed in .gitignore"
    else
        echo "  [!!] .env is NOT in .gitignore - potential secret exposure!"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo "  [!] No .gitignore found"
fi
echo ""

# ============================================================
# Summary
# ============================================================

echo "========================================"
echo " Summary"
echo "========================================"
echo ""
echo "  Total issues: $ISSUES"
echo ""

if [[ $ISSUES -gt 0 ]]; then
    exit 1
else
    exit 0
fi
