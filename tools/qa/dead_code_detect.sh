#!/bin/bash
set -euo pipefail

###############################################################################
# dead_code_detect.sh — Detect potentially dead code in TS/JS/Python projects
# Usage: dead_code_detect.sh [project_path]
# Exit codes: 0=OK, 1=dead code found, 2=error
###############################################################################

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: Project path '$PROJECT_PATH' does not exist." >&2
  exit 2
fi

ISSUES=0
EXCLUDE_PATTERN="node_modules|\.git|dist|build|\.next|__pycache__|\.pytest_cache|coverage|\.venv|venv"

echo "=============================================="
echo " Dead Code Detection"
echo " Project: $PROJECT_PATH"
echo "=============================================="
echo ""

# --- Detect project type ---
HAS_TS=false
HAS_JS=false
HAS_PY=false

if find "$PROJECT_PATH" -maxdepth 4 -name "*.ts" -o -name "*.tsx" 2>/dev/null | grep -qvE "$EXCLUDE_PATTERN"; then
  HAS_TS=true
fi
if find "$PROJECT_PATH" -maxdepth 4 -name "*.js" -o -name "*.jsx" 2>/dev/null | grep -qvE "$EXCLUDE_PATTERN"; then
  HAS_JS=true
fi
if find "$PROJECT_PATH" -maxdepth 4 -name "*.py" 2>/dev/null | grep -qvE "$EXCLUDE_PATTERN"; then
  HAS_PY=true
fi

# --- TS/JS: Find unused exports ---
if $HAS_TS || $HAS_JS; then
  echo "## Unused Exports (TypeScript/JavaScript)"
  echo ""

  # Collect all source files
  SOURCE_FILES=$(find "$PROJECT_PATH" -maxdepth 6 -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" | grep -vE "\.(test|spec|d)\.(ts|tsx|js|jsx)$" | grep -vE "__tests__|__mocks__" || true)

  if [[ -n "$SOURCE_FILES" ]]; then
    UNUSED_EXPORTS=()

    while IFS= read -r file; do
      REL_FILE="${file#$PROJECT_PATH/}"

      # Extract named exports
      EXPORTS=$(grep -oP 'export\s+(const|function|class|type|interface|enum|let|var)\s+\K[a-zA-Z_]\w*' "$file" 2>/dev/null || true)

      if [[ -z "$EXPORTS" ]]; then
        continue
      fi

      while IFS= read -r export_name; do
        # Skip common patterns that are likely entry points
        [[ "$export_name" =~ ^(default|App|main|handler|middleware)$ ]] && continue

        # Search for import/usage of this name in other files
        USAGE_COUNT=$(grep -rl "\b${export_name}\b" "$PROJECT_PATH" \
          --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
          2>/dev/null | grep -vE "$EXCLUDE_PATTERN" | grep -v "$file" | wc -l || echo "0")

        if [[ "$USAGE_COUNT" -eq 0 ]]; then
          echo "  [UNUSED] export $export_name in $REL_FILE"
          ((ISSUES++)) || true
        fi
      done <<< "$EXPORTS"
    done <<< "$SOURCE_FILES"

    if [[ $ISSUES -eq 0 ]]; then
      echo "  No unused exports found."
    fi
  fi
  echo ""

  # Check for unused files (no imports from other files)
  echo "## Potentially Dead Files (TS/JS)"
  echo ""

  DEAD_FILES=0
  if [[ -n "$SOURCE_FILES" ]]; then
    while IFS= read -r file; do
      REL_FILE="${file#$PROJECT_PATH/}"
      BASENAME=$(basename "$file" | sed 's/\.\(ts\|tsx\|js\|jsx\)$//')

      # Skip index files, entry points, config files
      [[ "$BASENAME" =~ ^(index|main|app|App|server|config|setup|env) ]] && continue
      [[ "$REL_FILE" =~ (config|types|constants|utils/index) ]] && continue

      # Check if this file is imported anywhere
      IMPORT_COUNT=$(grep -rlE "(from|require)\s*['\"].*${BASENAME}['\"]" "$PROJECT_PATH" \
        --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
        2>/dev/null | grep -vE "$EXCLUDE_PATTERN" | grep -v "$file" | wc -l || echo "0")

      if [[ "$IMPORT_COUNT" -eq 0 ]]; then
        echo "  [DEAD?] $REL_FILE (not imported anywhere)"
        ((DEAD_FILES++)) || true
      fi
    done <<< "$SOURCE_FILES"
  fi

  if [[ $DEAD_FILES -eq 0 ]]; then
    echo "  No dead files detected."
  fi
  echo ""
fi

# --- Python: Find unused definitions ---
if $HAS_PY; then
  echo "## Unused Definitions (Python)"
  echo ""

  PY_FILES=$(find "$PROJECT_PATH" -maxdepth 6 -type f -name "*.py" 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" | grep -vE "(test_|_test\.py|conftest\.py|__init__\.py|setup\.py|manage\.py)" || true)
  PY_UNUSED=0

  if [[ -n "$PY_FILES" ]]; then
    while IFS= read -r file; do
      REL_FILE="${file#$PROJECT_PATH/}"

      # Extract function and class definitions
      DEFS=$(grep -oP '(?:def|class)\s+\K[a-zA-Z_]\w*' "$file" 2>/dev/null || true)

      if [[ -z "$DEFS" ]]; then
        continue
      fi

      while IFS= read -r def_name; do
        # Skip private/magic methods
        [[ "$def_name" =~ ^_ ]] && continue
        # Skip common entry points
        [[ "$def_name" =~ ^(main|setup|run|app|create_app|configure)$ ]] && continue

        # Search for usage in other files
        USAGE_COUNT=$(grep -rl "\b${def_name}\b" "$PROJECT_PATH" \
          --include="*.py" 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" | grep -v "$file" | wc -l || echo "0")

        if [[ "$USAGE_COUNT" -eq 0 ]]; then
          echo "  [UNUSED] $def_name() in $REL_FILE"
          ((PY_UNUSED++)) || true
        fi
      done <<< "$DEFS"
    done <<< "$PY_FILES"
  fi

  if [[ $PY_UNUSED -eq 0 ]]; then
    echo "  No unused definitions found."
  else
    ISSUES=$((ISSUES + PY_UNUSED))
  fi
  echo ""
fi

# --- Commented-out code blocks ---
echo "## Commented-Out Code Blocks (>5 consecutive lines)"
echo ""

COMMENT_BLOCKS=0
ALL_FILES=$(find "$PROJECT_PATH" -maxdepth 6 -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" \) 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" || true)

if [[ -n "$ALL_FILES" ]]; then
  while IFS= read -r file; do
    REL_FILE="${file#$PROJECT_PATH/}"
    EXT="${file##*.}"

    # Determine comment prefix
    COMMENT_PREFIX="//"
    if [[ "$EXT" == "py" ]]; then
      COMMENT_PREFIX="#"
    fi

    # Find consecutive commented lines
    CONSECUTIVE=0
    BLOCK_START=0
    LINE_NUM=0

    while IFS= read -r line; do
      ((LINE_NUM++)) || true
      TRIMMED="${line#"${line%%[! ]*}"}"  # trim leading whitespace

      if [[ "$TRIMMED" == "${COMMENT_PREFIX}"* && ! "$TRIMMED" =~ ^${COMMENT_PREFIX}[[:space:]]*(TODO|FIXME|NOTE|HACK|XXX|eslint|prettier|type:|noqa|pragma) ]]; then
        if [[ $CONSECUTIVE -eq 0 ]]; then
          BLOCK_START=$LINE_NUM
        fi
        ((CONSECUTIVE++)) || true
      else
        if [[ $CONSECUTIVE -ge 5 ]]; then
          echo "  [BLOCK] $REL_FILE:$BLOCK_START-$((BLOCK_START + CONSECUTIVE - 1)) ($CONSECUTIVE lines)"
          ((COMMENT_BLOCKS++)) || true
        fi
        CONSECUTIVE=0
      fi
    done < "$file"

    # Check final block
    if [[ $CONSECUTIVE -ge 5 ]]; then
      echo "  [BLOCK] $REL_FILE:$BLOCK_START-$((BLOCK_START + CONSECUTIVE - 1)) ($CONSECUTIVE lines)"
      ((COMMENT_BLOCKS++)) || true
    fi
  done <<< "$ALL_FILES"
fi

if [[ $COMMENT_BLOCKS -eq 0 ]]; then
  echo "  No large commented-out code blocks found."
else
  ISSUES=$((ISSUES + COMMENT_BLOCKS))
fi
echo ""

# --- Summary ---
echo "=============================================="
echo " Dead Code Summary"
echo "   Potential issues: $ISSUES"
echo ""
echo "   Note: Results are heuristic-based."
echo "   Review each finding before removing code."
echo "=============================================="

if [[ $ISSUES -gt 0 ]]; then
  exit 1
fi
exit 0
