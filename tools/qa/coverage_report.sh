#!/bin/bash
set -euo pipefail

###############################################################################
# coverage_report.sh — Auto-detect test framework, run coverage, summarize
# Usage: coverage_report.sh [project_path]
# Exit codes: 0=OK, 1=low coverage, 2=error
###############################################################################

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: Project path '$PROJECT_PATH' does not exist." >&2
  exit 2
fi

FRAMEWORK=""
ISSUES=0

echo "=============================================="
echo " Coverage Report"
echo " Project: $PROJECT_PATH"
echo "=============================================="
echo ""

# --- Auto-detect test framework ---
echo "## Framework Detection"
echo ""

# Jest
if [[ -f "$PROJECT_PATH/jest.config.js" || -f "$PROJECT_PATH/jest.config.ts" || -f "$PROJECT_PATH/jest.config.mjs" ]]; then
  FRAMEWORK="jest"
  echo "  Detected: Jest (from jest.config.*)"
elif [[ -f "$PROJECT_PATH/package.json" ]] && grep -q '"jest"' "$PROJECT_PATH/package.json" 2>/dev/null; then
  FRAMEWORK="jest"
  echo "  Detected: Jest (from package.json)"
fi

# Vitest
if [[ -f "$PROJECT_PATH/vitest.config.ts" || -f "$PROJECT_PATH/vitest.config.js" || -f "$PROJECT_PATH/vitest.config.mts" ]]; then
  FRAMEWORK="vitest"
  echo "  Detected: Vitest (from vitest.config.*)"
elif [[ -f "$PROJECT_PATH/vite.config.ts" ]] && grep -q "vitest\|test:" "$PROJECT_PATH/vite.config.ts" 2>/dev/null; then
  FRAMEWORK="vitest"
  echo "  Detected: Vitest (from vite.config.ts)"
fi

# Pytest
if [[ -f "$PROJECT_PATH/pytest.ini" ]]; then
  FRAMEWORK="pytest"
  echo "  Detected: Pytest (from pytest.ini)"
elif [[ -f "$PROJECT_PATH/pyproject.toml" ]] && grep -q "\[tool.pytest" "$PROJECT_PATH/pyproject.toml" 2>/dev/null; then
  FRAMEWORK="pytest"
  echo "  Detected: Pytest (from pyproject.toml)"
elif [[ -f "$PROJECT_PATH/setup.cfg" ]] && grep -q "\[tool:pytest\]" "$PROJECT_PATH/setup.cfg" 2>/dev/null; then
  FRAMEWORK="pytest"
  echo "  Detected: Pytest (from setup.cfg)"
elif find "$PROJECT_PATH" -maxdepth 3 -name "conftest.py" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | grep -q .; then
  FRAMEWORK="pytest"
  echo "  Detected: Pytest (from conftest.py)"
fi

# Go test
if find "$PROJECT_PATH" -maxdepth 3 -name "*_test.go" -not -path "*/vendor/*" 2>/dev/null | grep -q .; then
  if [[ -z "$FRAMEWORK" ]]; then
    FRAMEWORK="gotest"
    echo "  Detected: Go test (from *_test.go files)"
  fi
fi

if [[ -z "$FRAMEWORK" ]]; then
  echo "  [ERROR] No test framework detected."
  echo ""
  echo "  Checked for:"
  echo "    - Jest: jest.config.* or 'jest' in package.json"
  echo "    - Vitest: vitest.config.* or test config in vite.config"
  echo "    - Pytest: pytest.ini, pyproject.toml [tool.pytest], conftest.py"
  echo "    - Go: *_test.go files"
  exit 2
fi
echo ""

# --- Run coverage ---
echo "## Running Coverage"
echo ""

COV_OUTPUT=$(mktemp)
COV_EXIT=0

case "$FRAMEWORK" in
  jest)
    echo "  Command: npx jest --coverage --coverageReporters=text --silent"
    echo ""
    cd "$PROJECT_PATH"
    npx jest --coverage --coverageReporters=text --silent 2>&1 | tee "$COV_OUTPUT" || COV_EXIT=$?
    ;;

  vitest)
    echo "  Command: npx vitest run --coverage --reporter=verbose"
    echo ""
    cd "$PROJECT_PATH"
    npx vitest run --coverage --reporter=verbose 2>&1 | tee "$COV_OUTPUT" || COV_EXIT=$?
    ;;

  pytest)
    echo "  Command: python3 -m pytest --cov --cov-report=term-missing"
    echo ""
    cd "$PROJECT_PATH"

    # Detect the source directory
    COV_SOURCE=""
    if [[ -d "$PROJECT_PATH/src" ]]; then
      COV_SOURCE="--cov=src"
    elif [[ -d "$PROJECT_PATH/app" ]]; then
      COV_SOURCE="--cov=app"
    fi

    python3 -m pytest $COV_SOURCE --cov-report=term-missing 2>&1 | tee "$COV_OUTPUT" || COV_EXIT=$?
    ;;

  gotest)
    echo "  Command: go test -coverprofile=coverage.out ./..."
    echo ""
    cd "$PROJECT_PATH"
    go test -coverprofile=coverage.out ./... 2>&1 | tee "$COV_OUTPUT" || COV_EXIT=$?
    if [[ -f "$PROJECT_PATH/coverage.out" ]]; then
      go tool cover -func=coverage.out 2>&1 | tee -a "$COV_OUTPUT" || true
    fi
    ;;
esac

echo ""

if [[ $COV_EXIT -ne 0 ]]; then
  echo "  [WARN] Test runner exited with code $COV_EXIT"
  ((ISSUES++)) || true
fi

# --- Parse coverage summary ---
echo "## Coverage Summary"
echo ""

case "$FRAMEWORK" in
  jest|vitest)
    # Parse Jest/Vitest text coverage output
    TOTAL_LINE=$(grep -E "^All files" "$COV_OUTPUT" 2>/dev/null || true)
    if [[ -n "$TOTAL_LINE" ]]; then
      echo "  $TOTAL_LINE"
    else
      # Try to extract percentage
      COVERAGE_PCT=$(grep -oP '(?:Statements|Lines)\s*:\s*[\d.]+%' "$COV_OUTPUT" | head -1 || true)
      if [[ -n "$COVERAGE_PCT" ]]; then
        echo "  $COVERAGE_PCT"
      else
        echo "  [WARN] Could not parse coverage percentage"
      fi
    fi

    # Find files with 0% coverage
    ZERO_COV=$(grep -E "\|\s*0\s*\|\s*0\s*\|\s*0\s*\|\s*0\s*\|" "$COV_OUTPUT" 2>/dev/null || true)
    if [[ -n "$ZERO_COV" ]]; then
      echo ""
      echo "  Files with 0% coverage:"
      echo "$ZERO_COV" | sed 's/^/    /'
    fi
    ;;

  pytest)
    # Parse pytest-cov output
    TOTAL_LINE=$(grep -E "^TOTAL" "$COV_OUTPUT" 2>/dev/null || true)
    if [[ -n "$TOTAL_LINE" ]]; then
      echo "  $TOTAL_LINE"
      TOTAL_PCT=$(echo "$TOTAL_LINE" | grep -oP '\d+%' | tail -1 || true)
      if [[ -n "$TOTAL_PCT" ]]; then
        PCT_NUM="${TOTAL_PCT%\%}"
        if [[ $PCT_NUM -lt 50 ]]; then
          echo "  [WARN] Coverage below 50%"
          ((ISSUES++)) || true
        fi
      fi
    fi

    # Find files with 0% coverage
    ZERO_COV=$(grep -E "\s+0%\s" "$COV_OUTPUT" 2>/dev/null || true)
    if [[ -n "$ZERO_COV" ]]; then
      ZERO_COUNT=$(echo "$ZERO_COV" | wc -l)
      echo ""
      echo "  Files with 0% coverage ($ZERO_COUNT):"
      echo "$ZERO_COV" | head -20 | sed 's/^/    /'
      if [[ $ZERO_COUNT -gt 20 ]]; then
        echo "    ... and $((ZERO_COUNT - 20)) more"
      fi
    fi
    ;;

  gotest)
    TOTAL_LINE=$(grep "total:" "$COV_OUTPUT" 2>/dev/null | tail -1 || true)
    if [[ -n "$TOTAL_LINE" ]]; then
      echo "  $TOTAL_LINE"
    fi
    ;;
esac

rm -f "$COV_OUTPUT"
echo ""

# --- Summary ---
echo "=============================================="
echo " Framework: $FRAMEWORK"
echo " Issues: $ISSUES"
echo "=============================================="

if [[ $ISSUES -gt 0 ]]; then
  exit 1
fi
exit 0
