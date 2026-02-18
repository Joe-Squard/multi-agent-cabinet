#!/bin/bash
set -euo pipefail

###############################################################################
# iac_validate.sh — Detect and validate Infrastructure as Code files
# Usage: iac_validate.sh [project_path]
# Exit codes: 0=OK, 1=issues found, 2=error
###############################################################################

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: Project path '$PROJECT_PATH' does not exist." >&2
  exit 2
fi

ISSUES=0
WARNINGS=0
DETECTED_TYPES=()

report() {
  local severity="$1"
  local message="$2"
  local file="${3:-}"

  case "$severity" in
    ERROR)   ((ISSUES++)) || true;   printf "  [ERROR]   %s" "$message" ;;
    WARN)    ((WARNINGS++)) || true;  printf "  [WARN]    %s" "$message" ;;
    INFO)    printf "  [INFO]    %s" "$message" ;;
    OK)      printf "  [OK]      %s" "$message" ;;
  esac

  if [[ -n "$file" ]]; then
    printf " (%s)" "${file#$PROJECT_PATH/}"
  fi
  echo ""
}

echo "=============================================="
echo " Infrastructure as Code Validation"
echo " Project: $PROJECT_PATH"
echo "=============================================="
echo ""

# --- Detect IaC types ---
echo "## IaC Detection"
echo ""

# Terraform
TF_FILES=$(find "$PROJECT_PATH" -maxdepth 4 -name "*.tf" -not -path "*/node_modules/*" -not -path "*/.terraform/*" -not -path "*/.git/*" 2>/dev/null || true)
if [[ -n "$TF_FILES" ]]; then
  TF_COUNT=$(echo "$TF_FILES" | wc -l)
  report "INFO" "Terraform detected ($TF_COUNT .tf files)"
  DETECTED_TYPES+=("terraform")
fi

# CloudFormation
CF_FILES=""
for yaml in $(find "$PROJECT_PATH" -maxdepth 4 \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null || true); do
  if grep -q "AWSTemplateFormatVersion" "$yaml" 2>/dev/null; then
    CF_FILES="${CF_FILES}${yaml}\n"
  fi
done
CF_FILES=$(echo -e "$CF_FILES" | sed '/^$/d')
if [[ -n "$CF_FILES" ]]; then
  CF_COUNT=$(echo "$CF_FILES" | wc -l)
  report "INFO" "CloudFormation detected ($CF_COUNT templates)"
  DETECTED_TYPES+=("cloudformation")
fi

# Docker Compose
COMPOSE_FILES=$(find "$PROJECT_PATH" -maxdepth 2 \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) -not -path "*/node_modules/*" 2>/dev/null || true)
if [[ -n "$COMPOSE_FILES" ]]; then
  report "INFO" "Docker Compose detected"
  DETECTED_TYPES+=("docker-compose")
fi

# Kubernetes
K8S_FILES=""
for yaml in $(find "$PROJECT_PATH" -maxdepth 4 \( -name "*.yaml" -o -name "*.yml" \) -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null || true); do
  if grep -q "apiVersion:" "$yaml" 2>/dev/null && grep -q "kind:" "$yaml" 2>/dev/null; then
    K8S_FILES="${K8S_FILES}${yaml}\n"
  fi
done
K8S_FILES=$(echo -e "$K8S_FILES" | sed '/^$/d')
if [[ -n "$K8S_FILES" ]]; then
  K8S_COUNT=$(echo "$K8S_FILES" | wc -l)
  report "INFO" "Kubernetes manifests detected ($K8S_COUNT files)"
  DETECTED_TYPES+=("kubernetes")
fi

# Ansible
ANSIBLE_FILES=$(find "$PROJECT_PATH" -maxdepth 4 \( -name "playbook*.yml" -o -name "playbook*.yaml" -o -name "ansible.cfg" \) -not -path "*/node_modules/*" 2>/dev/null || true)
if [[ -n "$ANSIBLE_FILES" ]]; then
  report "INFO" "Ansible detected"
  DETECTED_TYPES+=("ansible")
fi

if [[ ${#DETECTED_TYPES[@]} -eq 0 ]]; then
  echo "  No IaC files detected."
  echo ""
  echo "=============================================="
  echo " No IaC to validate."
  echo "=============================================="
  exit 0
fi
echo ""

# --- Validate Terraform ---
if [[ " ${DETECTED_TYPES[*]} " =~ " terraform " ]]; then
  echo "## Terraform Validation"
  echo ""

  # Find terraform directories
  TF_DIRS=$(echo "$TF_FILES" | xargs -I{} dirname {} | sort -u)

  while IFS= read -r tf_dir; do
    echo "  --- ${tf_dir#$PROJECT_PATH/} ---"

    # Run terraform validate if available
    if command -v terraform &>/dev/null; then
      if [[ -d "$tf_dir/.terraform" ]]; then
        if terraform -chdir="$tf_dir" validate 2>/dev/null; then
          report "OK" "terraform validate passed"
        else
          report "ERROR" "terraform validate failed"
        fi
      else
        report "INFO" "Run 'terraform init' first for full validation"
      fi
    else
      report "INFO" "terraform CLI not available — skipping validate"
    fi

    # Check for hardcoded credentials
    for tf_file in "$tf_dir"/*.tf; do
      [[ -f "$tf_file" ]] || continue

      if grep -qiE '(access_key|secret_key|password|api_key)\s*=\s*"[^"$]' "$tf_file" 2>/dev/null; then
        report "ERROR" "Possible hardcoded credentials" "$tf_file"
      fi

      # Check for missing description on variables
      if grep -q "^variable " "$tf_file" 2>/dev/null; then
        VAR_COUNT=$(grep -c "^variable " "$tf_file" 2>/dev/null || echo "0")
        DESC_COUNT=$(grep -c "description\s*=" "$tf_file" 2>/dev/null || echo "0")
        if [[ "$DESC_COUNT" -lt "$VAR_COUNT" ]]; then
          report "WARN" "Some variables missing descriptions ($DESC_COUNT/$VAR_COUNT)" "$tf_file"
        fi
      fi
    done
    echo ""
  done <<< "$TF_DIRS"
fi

# --- Validate Docker Compose ---
if [[ " ${DETECTED_TYPES[*]} " =~ " docker-compose " ]]; then
  echo "## Docker Compose Validation"
  echo ""

  while IFS= read -r cf; do
    REL="${cf#$PROJECT_PATH/}"
    echo "  --- $REL ---"

    # Run docker compose config if available
    if command -v docker &>/dev/null; then
      if docker compose -f "$cf" config --quiet 2>/dev/null; then
        report "OK" "docker compose config passed"
      else
        report "ERROR" "docker compose config failed"
      fi
    elif command -v docker-compose &>/dev/null; then
      if docker-compose -f "$cf" config --quiet 2>/dev/null; then
        report "OK" "docker-compose config passed"
      else
        report "ERROR" "docker-compose config failed"
      fi
    else
      report "INFO" "docker compose CLI not available — skipping validation"
    fi

    # Check for hardcoded credentials
    if grep -qiE '(PASSWORD|SECRET|API_KEY|TOKEN)\s*[:=]\s*[^${\s]' "$cf" 2>/dev/null; then
      report "ERROR" "Possible hardcoded credentials in compose file" "$cf"
    fi

    echo ""
  done <<< "$COMPOSE_FILES"
fi

# --- Validate CloudFormation ---
if [[ " ${DETECTED_TYPES[*]} " =~ " cloudformation " ]]; then
  echo "## CloudFormation Validation"
  echo ""

  while IFS= read -r cf_file; do
    [[ -z "$cf_file" ]] && continue
    REL="${cf_file#$PROJECT_PATH/}"
    echo "  --- $REL ---"

    # Run aws cloudformation validate if available
    if command -v aws &>/dev/null; then
      if aws cloudformation validate-template --template-body "file://$cf_file" 2>/dev/null 1>/dev/null; then
        report "OK" "CloudFormation validate passed"
      else
        report "ERROR" "CloudFormation validate failed"
      fi
    else
      report "INFO" "AWS CLI not available — skipping validation"
    fi

    # Check for hardcoded credentials
    if grep -qiE '(AccessKey|SecretKey|Password)\s*[:=]\s*[^!{$]' "$cf_file" 2>/dev/null; then
      report "ERROR" "Possible hardcoded credentials" "$cf_file"
    fi

    echo ""
  done <<< "$CF_FILES"
fi

# --- General credential scan ---
echo "## General Credential Scan"
echo ""

ALL_IAC_FILES=$(find "$PROJECT_PATH" -maxdepth 4 \( -name "*.tf" -o -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/.terraform/*" \
  -not -name "package.json" -not -name "package-lock.json" -not -name "tsconfig.json" 2>/dev/null || true)

CRED_PATTERNS='(AKIA[0-9A-Z]{16}|sk-[a-zA-Z0-9]{48}|ghp_[a-zA-Z0-9]{36}|-----BEGIN\s*(RSA|EC|DSA)?\s*PRIVATE\s*KEY)'

FOUND_CREDS=false
if [[ -n "$ALL_IAC_FILES" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if grep -qE "$CRED_PATTERNS" "$f" 2>/dev/null; then
      report "ERROR" "Possible secret/key detected" "$f"
      FOUND_CREDS=true
    fi
  done <<< "$ALL_IAC_FILES"
fi

if ! $FOUND_CREDS; then
  echo "  No obvious credentials found in IaC files."
fi
echo ""

# --- Summary ---
echo "=============================================="
printf " IaC types: %s\n" "${DETECTED_TYPES[*]}"
printf " Summary: %d error(s), %d warning(s)\n" "$ISSUES" "$WARNINGS"
echo "=============================================="

if [[ $ISSUES -gt 0 ]]; then
  exit 1
fi
exit 0
