#!/bin/bash
set -euo pipefail

###############################################################################
# pip_audit.sh — Audit Python dependencies for vulnerabilities and outdated pkgs
# Usage: pip_audit.sh [project_path]
# Exit codes: 0=OK, 1=issues found, 2=error
###############################################################################

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: Project path '$PROJECT_PATH' does not exist." >&2
  exit 2
fi

ISSUES=0
WARNINGS=0

PYTHON_CMD="python3"
if ! command -v python3 &>/dev/null; then
  if command -v python &>/dev/null; then
    PYTHON_CMD="python"
  else
    echo "ERROR: Python not found." >&2
    exit 2
  fi
fi

PIP_CMD="$PYTHON_CMD -m pip"

echo "=============================================="
echo " Python Dependency Audit"
echo " Project: $PROJECT_PATH"
echo " Python:  $($PYTHON_CMD --version 2>&1)"
echo "=============================================="
echo ""

# --- Check for requirements files ---
echo "## Requirements Files"
echo ""

REQ_FILES=()
for pattern in "requirements*.txt" "requirements/*.txt" "constraints*.txt"; do
  while IFS= read -r f; do
    REQ_FILES+=("$f")
    echo "  Found: ${f#$PROJECT_PATH/}"
  done < <(find "$PROJECT_PATH" -maxdepth 3 -name "$pattern" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/venv/*" -not -path "*/.venv/*" 2>/dev/null || true)
done

PYPROJECT="$PROJECT_PATH/pyproject.toml"
SETUP_PY="$PROJECT_PATH/setup.py"
SETUP_CFG="$PROJECT_PATH/setup.cfg"
PIPFILE="$PROJECT_PATH/Pipfile"
POETRY_LOCK="$PROJECT_PATH/poetry.lock"

if [[ -f "$PYPROJECT" ]]; then
  echo "  Found: pyproject.toml"
fi
if [[ -f "$SETUP_PY" ]]; then
  echo "  Found: setup.py"
fi
if [[ -f "$PIPFILE" ]]; then
  echo "  Found: Pipfile"
fi
if [[ -f "$POETRY_LOCK" ]]; then
  echo "  Found: poetry.lock"
fi

if [[ ${#REQ_FILES[@]} -eq 0 && ! -f "$PYPROJECT" && ! -f "$SETUP_PY" && ! -f "$PIPFILE" ]]; then
  echo "  [WARN] No Python dependency files found"
  ((WARNINGS++)) || true
fi
echo ""

# --- Run pip audit if available ---
echo "## Vulnerability Scan"
echo ""

if $PYTHON_CMD -m pip_audit --version &>/dev/null 2>&1; then
  echo "  Running pip-audit..."
  echo ""

  AUDIT_OUTPUT=$(mktemp)
  AUDIT_EXIT=0

  # Try with requirements file first
  if [[ ${#REQ_FILES[@]} -gt 0 ]]; then
    $PYTHON_CMD -m pip_audit -r "${REQ_FILES[0]}" --format columns 2>/dev/null > "$AUDIT_OUTPUT" || AUDIT_EXIT=$?
  else
    $PYTHON_CMD -m pip_audit --format columns 2>/dev/null > "$AUDIT_OUTPUT" || AUDIT_EXIT=$?
  fi

  if [[ -s "$AUDIT_OUTPUT" ]]; then
    cat "$AUDIT_OUTPUT" | sed 's/^/  /'
    VULN_COUNT=$(grep -c "VULN" "$AUDIT_OUTPUT" 2>/dev/null || echo "0")
    if [[ $VULN_COUNT -gt 0 ]]; then
      ISSUES=$((ISSUES + VULN_COUNT))
    fi
  else
    echo "  [OK] No known vulnerabilities found"
  fi

  rm -f "$AUDIT_OUTPUT"
elif command -v pip-audit &>/dev/null; then
  echo "  Running pip-audit (system)..."
  echo ""

  AUDIT_EXIT=0
  pip-audit 2>/dev/null | sed 's/^/  /' || AUDIT_EXIT=$?

  if [[ $AUDIT_EXIT -ne 0 ]]; then
    echo "  [WARN] pip-audit exited with code $AUDIT_EXIT"
    ((WARNINGS++)) || true
  fi
else
  echo "  [INFO] pip-audit not available — install with: pip install pip-audit"
  echo "  Falling back to outdated package check..."
  echo ""
fi
echo ""

# --- Check outdated packages ---
echo "## Outdated Packages"
echo ""

OUTDATED=$(mktemp)
$PIP_CMD list --outdated --format columns 2>/dev/null > "$OUTDATED" || true

if [[ -s "$OUTDATED" ]]; then
  OUTDATED_COUNT=$(tail -n +3 "$OUTDATED" | grep -c . 2>/dev/null || echo "0")
  echo "  Found $OUTDATED_COUNT outdated package(s):"
  echo ""
  cat "$OUTDATED" | sed 's/^/  /'

  if [[ $OUTDATED_COUNT -gt 20 ]]; then
    echo ""
    echo "  [WARN] Many outdated packages ($OUTDATED_COUNT) — consider updating"
    ((WARNINGS++)) || true
  fi
else
  echo "  [OK] All packages are up to date"
fi
rm -f "$OUTDATED"
echo ""

# --- Check for conflicting requirements ---
echo "## Dependency Conflicts"
echo ""

CONFLICTS=$(mktemp)
$PIP_CMD check 2>/dev/null > "$CONFLICTS" || true

if [[ -s "$CONFLICTS" ]]; then
  CONFLICT_COUNT=$(wc -l < "$CONFLICTS")
  echo "  Found $CONFLICT_COUNT conflict(s):"
  echo ""
  cat "$CONFLICTS" | sed 's/^/  /'
  ISSUES=$((ISSUES + CONFLICT_COUNT))
else
  echo "  [OK] No dependency conflicts"
fi
rm -f "$CONFLICTS"
echo ""

# --- Check for pinned vs unpinned in requirements ---
if [[ ${#REQ_FILES[@]} -gt 0 ]]; then
  echo "## Pinning Analysis"
  echo ""

  for req_file in "${REQ_FILES[@]}"; do
    REL="${req_file#$PROJECT_PATH/}"
    echo "  --- $REL ---"

    TOTAL_DEPS=0
    PINNED=0
    UNPINNED=0
    RANGE=0

    while IFS= read -r line; do
      # Skip comments and empty lines
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" =~ ^-r || "$line" =~ ^-e || "$line" =~ ^--  ]] && continue

      ((TOTAL_DEPS++)) || true

      if [[ "$line" =~ ==  ]]; then
        ((PINNED++)) || true
      elif [[ "$line" =~ [\>\<~!]=  ]]; then
        ((RANGE++)) || true
      else
        ((UNPINNED++)) || true
        echo "    [WARN] Unpinned: $line"
        ((WARNINGS++)) || true
      fi
    done < "$req_file"

    echo "    Total: $TOTAL_DEPS, Pinned(==): $PINNED, Range: $RANGE, Unpinned: $UNPINNED"
    echo ""
  done
fi

# --- Summary ---
echo "=============================================="
echo " Summary: $ISSUES issue(s), $WARNINGS warning(s)"
echo "=============================================="

if [[ $ISSUES -gt 0 ]]; then
  exit 1
fi
exit 0
