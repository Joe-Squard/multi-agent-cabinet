#!/bin/bash
set -euo pipefail

###############################################################################
# security_scan.sh — Scan for vulnerabilities, secrets, and dangerous patterns
# Usage: security_scan.sh [project_path]
# Exit codes: 0=OK, 1=issues found, 2=error
###############################################################################

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: Project path '$PROJECT_PATH' does not exist." >&2
  exit 2
fi

CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0
EXCLUDE_PATTERN="node_modules|\.git|dist|build|\.next|__pycache__|\.venv|venv|vendor|\.lock$|package-lock\.json"

report() {
  local severity="$1"
  local category="$2"
  local message="$3"
  local file="${4:-}"

  case "$severity" in
    CRITICAL) ((CRITICAL++)) || true; printf "  [CRITICAL] " ;;
    HIGH)     ((HIGH++)) || true;     printf "  [HIGH]     " ;;
    MEDIUM)   ((MEDIUM++)) || true;   printf "  [MEDIUM]   " ;;
    LOW)      ((LOW++)) || true;      printf "  [LOW]      " ;;
  esac

  printf "(%s) %s" "$category" "$message"
  if [[ -n "$file" ]]; then
    printf " — %s" "${file#$PROJECT_PATH/}"
  fi
  echo ""
}

echo "=============================================="
echo " Security Scan"
echo " Project: $PROJECT_PATH"
echo " Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="
echo ""

# --- 1. Dependency vulnerabilities ---
echo "## Dependency Vulnerabilities"
echo ""

# npm audit
if [[ -f "$PROJECT_PATH/package-lock.json" || -f "$PROJECT_PATH/yarn.lock" ]]; then
  echo "  Scanning Node.js dependencies..."

  if [[ -f "$PROJECT_PATH/package-lock.json" ]]; then
    AUDIT_OUTPUT=$(cd "$PROJECT_PATH" && npm audit --json 2>/dev/null || true)
    if [[ -n "$AUDIT_OUTPUT" ]]; then
      VULN_COUNT=$(echo "$AUDIT_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    vulns = data.get('metadata', {}).get('vulnerabilities', {})
    total = sum(vulns.values()) if isinstance(vulns, dict) else 0
    print(total)
except: print(0)
" 2>/dev/null || echo "0")

      if [[ "$VULN_COUNT" -gt 0 ]]; then
        echo "  [WARN] npm audit found $VULN_COUNT vulnerability/vulnerabilities"
        # Get summary by severity
        echo "$AUDIT_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    vulns = data.get('metadata', {}).get('vulnerabilities', {})
    for sev, count in sorted(vulns.items(), key=lambda x: x[1], reverse=True):
        if count > 0:
            print(f'    {sev}: {count}')
except: pass
" 2>/dev/null || true
        ((HIGH++)) || true
      else
        echo "  [OK] No npm vulnerabilities found"
      fi
    fi
  elif [[ -f "$PROJECT_PATH/yarn.lock" ]]; then
    cd "$PROJECT_PATH" && yarn audit --level moderate 2>/dev/null | head -20 | sed 's/^/  /' || echo "  [INFO] yarn audit returned warnings"
  fi
  echo ""
fi

# pip audit
if [[ -f "$PROJECT_PATH/requirements.txt" || -f "$PROJECT_PATH/pyproject.toml" ]]; then
  echo "  Scanning Python dependencies..."

  if command -v pip-audit &>/dev/null || python3 -m pip_audit --version &>/dev/null 2>&1; then
    PIP_AUDIT_CMD="pip-audit"
    if ! command -v pip-audit &>/dev/null; then
      PIP_AUDIT_CMD="python3 -m pip_audit"
    fi

    AUDIT_RESULT=$($PIP_AUDIT_CMD 2>/dev/null || true)
    if echo "$AUDIT_RESULT" | grep -q "found"; then
      echo "  $AUDIT_RESULT" | head -5
      ((HIGH++)) || true
    else
      echo "  [OK] No Python vulnerabilities found"
    fi
  else
    echo "  [INFO] pip-audit not available — skipping Python vulnerability scan"
  fi
  echo ""
fi

# --- 2. Hardcoded secrets ---
echo "## Hardcoded Secrets Scan"
echo ""

# Define patterns for common secrets
declare -A SECRET_PATTERNS
SECRET_PATTERNS=(
  ["AWS Access Key"]='AKIA[0-9A-Z]{16}'
  ["AWS Secret Key"]='(?i)(aws_secret_access_key|aws_secret_key)\s*[=:]\s*[A-Za-z0-9/+=]{40}'
  ["GitHub Token"]='gh[pousr]_[A-Za-z0-9_]{36,}'
  ["Generic API Key"]='(?i)(api[_-]?key|apikey)\s*[=:]\s*["\x27][A-Za-z0-9_\-]{20,}["\x27]'
  ["Generic Secret"]='(?i)(secret|password|passwd|pwd)\s*[=:]\s*["\x27][^\s"'\'']{8,}["\x27]'
  ["Private Key"]='-----BEGIN\s*(RSA|EC|DSA|OPENSSH)?\s*PRIVATE\s*KEY'
  ["Slack Token"]='xox[baprs]-[0-9a-zA-Z-]+'
  ["JWT Secret"]='(?i)(jwt[_-]?secret|jwt[_-]?key)\s*[=:]\s*["\x27][^\s"'\'']+["\x27]'
  ["Database URL"]='(?i)(postgres|mysql|mongodb|redis)://[^\s"'\'']+:[^\s@"'\'']+@'
  ["Bearer Token"]='(?i)bearer\s+[a-zA-Z0-9_\-\.]{20,}'
  ["OpenAI API Key"]='sk-[a-zA-Z0-9]{48,}'
  ["Stripe Key"]='[sr]k_(test|live)_[a-zA-Z0-9]{20,}'
  ["SendGrid Key"]='SG\.[a-zA-Z0-9_\-]{22}\.[a-zA-Z0-9_\-]{43}'
)

ALL_SOURCE=$(find "$PROJECT_PATH" -maxdepth 5 -type f \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
     -o -name "*.py" -o -name "*.go" -o -name "*.rb" -o -name "*.java" \
     -o -name "*.yml" -o -name "*.yaml" -o -name "*.toml" \
     -o -name "*.env" -o -name "*.env.*" -o -name "*.cfg" -o -name "*.conf" \
     -o -name "*.sh" -o -name "Dockerfile*" \) \
  2>/dev/null | grep -vE "$EXCLUDE_PATTERN" || true)

SECRETS_FOUND=0
if [[ -n "$ALL_SOURCE" ]]; then
  for pattern_name in "${!SECRET_PATTERNS[@]}"; do
    PATTERN="${SECRET_PATTERNS[$pattern_name]}"
    MATCHES=$(echo "$ALL_SOURCE" | xargs grep -lP "$PATTERN" 2>/dev/null || true)

    if [[ -n "$MATCHES" ]]; then
      while IFS= read -r match_file; do
        # Skip example/template files
        [[ "$match_file" =~ \.(example|sample|template)$ ]] && continue

        report "CRITICAL" "Secret" "$pattern_name detected" "$match_file"
        ((SECRETS_FOUND++)) || true
      done <<< "$MATCHES"
    fi
  done
fi

# Check for .env files committed (not in .gitignore)
if [[ -f "$PROJECT_PATH/.gitignore" ]]; then
  ENV_FILES=$(find "$PROJECT_PATH" -maxdepth 2 -name ".env" -o -name ".env.local" -o -name ".env.production" 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" || true)
  if [[ -n "$ENV_FILES" ]]; then
    while IFS= read -r ef; do
      REL="${ef#$PROJECT_PATH/}"
      if ! grep -q "^${REL}$\|^\.env" "$PROJECT_PATH/.gitignore" 2>/dev/null; then
        report "HIGH" "Config" ".env file may not be in .gitignore" "$ef"
      fi
    done <<< "$ENV_FILES"
  fi
else
  if find "$PROJECT_PATH" -maxdepth 1 -name ".env" 2>/dev/null | grep -q .; then
    report "HIGH" "Config" "No .gitignore found but .env file exists"
  fi
fi

if [[ $SECRETS_FOUND -eq 0 ]]; then
  echo "  [OK] No obvious hardcoded secrets found"
fi
echo ""

# --- 3. Dangerous patterns ---
echo "## Dangerous Code Patterns"
echo ""

DANGEROUS_FOUND=0

# eval usage
EVAL_FILES=$(find "$PROJECT_PATH" -maxdepth 5 -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" \) 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" || true)

if [[ -n "$EVAL_FILES" ]]; then
  # JavaScript eval
  EVAL_JS=$(echo "$EVAL_FILES" | xargs grep -l "\beval\s*(" 2>/dev/null | grep -vE "\.py$" || true)
  if [[ -n "$EVAL_JS" ]]; then
    while IFS= read -r f; do
      report "HIGH" "Injection" "eval() usage" "$f"
      ((DANGEROUS_FOUND++)) || true
    done <<< "$EVAL_JS"
  fi

  # Python eval/exec
  EVAL_PY=$(echo "$EVAL_FILES" | grep "\.py$" | xargs grep -l "\b\(eval\|exec\)\s*(" 2>/dev/null || true)
  if [[ -n "$EVAL_PY" ]]; then
    while IFS= read -r f; do
      report "HIGH" "Injection" "eval()/exec() usage" "$f"
      ((DANGEROUS_FOUND++)) || true
    done <<< "$EVAL_PY"
  fi

  # innerHTML
  INNERHTML_FILES=$(echo "$EVAL_FILES" | xargs grep -l "innerHTML\s*=" 2>/dev/null || true)
  if [[ -n "$INNERHTML_FILES" ]]; then
    while IFS= read -r f; do
      report "MEDIUM" "XSS" "innerHTML assignment" "$f"
      ((DANGEROUS_FOUND++)) || true
    done <<< "$INNERHTML_FILES"
  fi

  # dangerouslySetInnerHTML
  DANGEROUS_HTML=$(echo "$EVAL_FILES" | xargs grep -l "dangerouslySetInnerHTML" 2>/dev/null || true)
  if [[ -n "$DANGEROUS_HTML" ]]; then
    while IFS= read -r f; do
      report "MEDIUM" "XSS" "dangerouslySetInnerHTML usage" "$f"
      ((DANGEROUS_FOUND++)) || true
    done <<< "$DANGEROUS_HTML"
  fi

  # SQL string concatenation
  SQL_CONCAT=$(echo "$EVAL_FILES" | xargs grep -lP "(SELECT|INSERT|UPDATE|DELETE|DROP).*[\+\$\{f\"].*['\"]" 2>/dev/null || true)
  if [[ -n "$SQL_CONCAT" ]]; then
    while IFS= read -r f; do
      report "HIGH" "SQLi" "Possible SQL string concatenation" "$f"
      ((DANGEROUS_FOUND++)) || true
    done <<< "$SQL_CONCAT"
  fi

  # Command injection (child_process, subprocess without shell=False)
  CMD_INJECT=$(echo "$EVAL_FILES" | xargs grep -l "exec\s*(\|spawn\s*(\|subprocess\.call\|os\.system\|os\.popen" 2>/dev/null || true)
  if [[ -n "$CMD_INJECT" ]]; then
    while IFS= read -r f; do
      report "MEDIUM" "CMDi" "Command execution function" "$f"
      ((DANGEROUS_FOUND++)) || true
    done <<< "$CMD_INJECT"
  fi

  # Disabled security (CORS *, SSL verify=False)
  CORS_ANY=$(echo "$EVAL_FILES" | xargs grep -l "cors.*origin.*\*\|Access-Control-Allow-Origin.*\*" 2>/dev/null || true)
  if [[ -n "$CORS_ANY" ]]; then
    while IFS= read -r f; do
      report "MEDIUM" "Config" "CORS allows all origins (*)" "$f"
      ((DANGEROUS_FOUND++)) || true
    done <<< "$CORS_ANY"
  fi

  SSL_DISABLED=$(echo "$EVAL_FILES" | xargs grep -l "verify\s*=\s*False\|rejectUnauthorized.*false\|NODE_TLS_REJECT_UNAUTHORIZED.*0" 2>/dev/null || true)
  if [[ -n "$SSL_DISABLED" ]]; then
    while IFS= read -r f; do
      report "HIGH" "Config" "SSL verification disabled" "$f"
      ((DANGEROUS_FOUND++)) || true
    done <<< "$SSL_DISABLED"
  fi
fi

if [[ $DANGEROUS_FOUND -eq 0 ]]; then
  echo "  [OK] No dangerous code patterns found"
fi
echo ""

# --- Summary ---
TOTAL=$((CRITICAL + HIGH + MEDIUM + LOW))
echo "=============================================="
echo " Security Scan Summary"
echo ""
printf "   CRITICAL: %d\n" "$CRITICAL"
printf "   HIGH:     %d\n" "$HIGH"
printf "   MEDIUM:   %d\n" "$MEDIUM"
printf "   LOW:      %d\n" "$LOW"
printf "   TOTAL:    %d finding(s)\n" "$TOTAL"
echo ""
echo "=============================================="

if [[ $TOTAL -gt 0 ]]; then
  exit 1
fi
exit 0
