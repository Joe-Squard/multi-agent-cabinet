#!/bin/bash
set -euo pipefail

###############################################################################
# platform_diff.sh — Analyze platform-specific code distribution in RN project
# Usage: platform_diff.sh [project_path]
# Exit codes: 0=OK, 1=issues found, 2=error
###############################################################################

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: Project path '$PROJECT_PATH' does not exist." >&2
  exit 2
fi

echo "=============================================="
echo " Platform-Specific Code Analysis"
echo " Project: $PROJECT_PATH"
echo "=============================================="
echo ""

# Directories to scan (exclude node_modules, build artifacts)
SEARCH_DIRS=("$PROJECT_PATH/src" "$PROJECT_PATH/app" "$PROJECT_PATH/lib" "$PROJECT_PATH/components")
SEARCH_PATHS=()
for d in "${SEARCH_DIRS[@]}"; do
  if [[ -d "$d" ]]; then
    SEARCH_PATHS+=("$d")
  fi
done

# Fallback to project root if no standard dirs found
if [[ ${#SEARCH_PATHS[@]} -eq 0 ]]; then
  SEARCH_PATHS=("$PROJECT_PATH")
fi

EXCLUDE_PATTERN="node_modules|\.git|build|dist|\.expo|android/app/build|ios/build"

# --- Platform-specific file extensions ---
echo "## Platform-Specific Files"
echo ""
printf "  %-12s %s\n" "TYPE" "COUNT"
printf "  %-12s %s\n" "----" "-----"

IOS_FILES=$(find "${SEARCH_PATHS[@]}" -type f -name "*.ios.tsx" -o -name "*.ios.ts" -o -name "*.ios.js" -o -name "*.ios.jsx" 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" || true)
ANDROID_FILES=$(find "${SEARCH_PATHS[@]}" -type f -name "*.android.tsx" -o -name "*.android.ts" -o -name "*.android.js" -o -name "*.android.jsx" 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" || true)
NATIVE_FILES=$(find "${SEARCH_PATHS[@]}" -type f -name "*.native.tsx" -o -name "*.native.ts" -o -name "*.native.js" 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" || true)
WEB_FILES=$(find "${SEARCH_PATHS[@]}" -type f -name "*.web.tsx" -o -name "*.web.ts" -o -name "*.web.js" 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" || true)

IOS_COUNT=$(echo "$IOS_FILES" | grep -c . 2>/dev/null || echo "0")
ANDROID_COUNT=$(echo "$ANDROID_FILES" | grep -c . 2>/dev/null || echo "0")
NATIVE_COUNT=$(echo "$NATIVE_FILES" | grep -c . 2>/dev/null || echo "0")
WEB_COUNT=$(echo "$WEB_FILES" | grep -c . 2>/dev/null || echo "0")

printf "  %-12s %s\n" ".ios.*" "$IOS_COUNT"
printf "  %-12s %s\n" ".android.*" "$ANDROID_COUNT"
printf "  %-12s %s\n" ".native.*" "$NATIVE_COUNT"
printf "  %-12s %s\n" ".web.*" "$WEB_COUNT"
echo ""

# List files if any exist
for label_files in "iOS:.ios.:$IOS_FILES" "Android:.android.:$ANDROID_FILES" "Native:.native.:$NATIVE_FILES" "Web:.web.:$WEB_FILES"; do
  IFS=':' read -r label _ext files <<< "$label_files"
  if [[ -n "$files" ]]; then
    echo "  $label files:"
    echo "$files" | while IFS= read -r f; do
      echo "    ${f#$PROJECT_PATH/}"
    done
    echo ""
  fi
done

# --- Platform.OS usage ---
echo "## Platform.OS Usage"
echo ""

PLATFORM_OS_FILES=$(grep -rl "Platform\.OS" "${SEARCH_PATHS[@]}" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" || true)
PLATFORM_OS_COUNT=$(echo "$PLATFORM_OS_FILES" | grep -c . 2>/dev/null || echo "0")

echo "  Files using Platform.OS: $PLATFORM_OS_COUNT"
if [[ -n "$PLATFORM_OS_FILES" ]]; then
  echo ""
  echo "$PLATFORM_OS_FILES" | while IFS= read -r f; do
    LINE_COUNT=$(grep -c "Platform\.OS" "$f" 2>/dev/null || echo "0")
    echo "    ${f#$PROJECT_PATH/} ($LINE_COUNT occurrences)"
  done
fi
echo ""

# --- Platform.select usage ---
echo "## Platform.select Usage"
echo ""

PLATFORM_SELECT_FILES=$(grep -rl "Platform\.select" "${SEARCH_PATHS[@]}" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" || true)
PLATFORM_SELECT_COUNT=$(echo "$PLATFORM_SELECT_FILES" | grep -c . 2>/dev/null || echo "0")

echo "  Files using Platform.select: $PLATFORM_SELECT_COUNT"
if [[ -n "$PLATFORM_SELECT_FILES" ]]; then
  echo ""
  echo "$PLATFORM_SELECT_FILES" | while IFS= read -r f; do
    LINE_COUNT=$(grep -c "Platform\.select" "$f" 2>/dev/null || echo "0")
    echo "    ${f#$PROJECT_PATH/} ($LINE_COUNT occurrences)"
  done
fi
echo ""

# --- Distribution summary ---
echo "## Distribution Summary"
echo ""

TOTAL_SOURCE=$(find "${SEARCH_PATHS[@]}" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) 2>/dev/null | grep -vE "$EXCLUDE_PATTERN" | wc -l || echo "0")
TOTAL_PLATFORM=$((IOS_COUNT + ANDROID_COUNT + NATIVE_COUNT + WEB_COUNT + PLATFORM_OS_COUNT + PLATFORM_SELECT_COUNT))

echo "  Total source files scanned:   $TOTAL_SOURCE"
echo "  Platform-specific files:       $((IOS_COUNT + ANDROID_COUNT + NATIVE_COUNT + WEB_COUNT))"
echo "  Files with Platform.OS:        $PLATFORM_OS_COUNT"
echo "  Files with Platform.select:    $PLATFORM_SELECT_COUNT"
echo ""

if [[ $TOTAL_SOURCE -gt 0 ]]; then
  PLATFORM_FILE_PCT=$(( (IOS_COUNT + ANDROID_COUNT + NATIVE_COUNT + WEB_COUNT) * 100 / TOTAL_SOURCE ))
  echo "  Platform-specific file ratio:  ${PLATFORM_FILE_PCT}%"
fi

echo ""
echo "=============================================="
echo " Analysis complete"
echo "=============================================="
exit 0
