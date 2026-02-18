#!/bin/bash
set -euo pipefail

# a11y_audit.sh - Static accessibility audit for JSX/TSX files
# Usage: a11y_audit.sh [project_path]
# Exit codes: 0=no issues, 1=issues found, 2=error

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

# Find source directory
SRC_DIR="$PROJECT_PATH/src"
if [[ ! -d "$SRC_DIR" ]]; then
    SRC_DIR="$PROJECT_PATH"
fi

# Collect JSX/TSX files
FILES=()
while IFS= read -r -d '' f; do
    FILES+=("$f")
done < <(find "$SRC_DIR" -type f \( -name "*.jsx" -o -name "*.tsx" \) ! -path "*/node_modules/*" ! -path "*/.next/*" ! -path "*/dist/*" ! -path "*/build/*" -print0 2>/dev/null)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No JSX/TSX files found in $SRC_DIR"
    exit 2
fi

ISSUES=0
TOTAL_FILES=${#FILES[@]}
FILES_WITH_ISSUES=0

# Temporary file for collecting issues
ISSUE_LOG=$(mktemp)
trap 'rm -f "$ISSUE_LOG"' EXIT

audit_file() {
    local file="$1"
    local rel_path="${file#$PROJECT_PATH/}"
    local file_issues=0
    local line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # --- Check 1: <img> without alt attribute ---
        if echo "$line" | grep -qiE '<img\b' && ! echo "$line" | grep -qiE 'alt\s*='; then
            # Could be multiline; check next few lines context (simplified: single-line check)
            echo "  [A11Y] $rel_path:$line_num - <img> missing alt attribute" >> "$ISSUE_LOG"
            file_issues=$((file_issues + 1))
        fi

        # --- Check 2: <img alt=""> is OK (decorative), but flag <img alt="image"> or <img alt="photo"> ---
        if echo "$line" | grep -qiE '<img\b.*alt\s*=\s*"(image|photo|picture|icon|img|banner|logo)"'; then
            echo "  [A11Y] $rel_path:$line_num - <img> has non-descriptive alt text" >> "$ISSUE_LOG"
            file_issues=$((file_issues + 1))
        fi

        # --- Check 3: <button> without text content or aria-label ---
        # Matches self-closing buttons or buttons with only an icon child
        if echo "$line" | grep -qiE '<button\b[^>]*/\s*>' && ! echo "$line" | grep -qiE 'aria-label\s*='; then
            echo "  [A11Y] $rel_path:$line_num - Self-closing <button> without aria-label" >> "$ISSUE_LOG"
            file_issues=$((file_issues + 1))
        fi

        # --- Check 4: <a> without text content or aria-label ---
        if echo "$line" | grep -qiE '<a\b[^>]*>\s*</(a)>' && ! echo "$line" | grep -qiE 'aria-label\s*='; then
            echo "  [A11Y] $rel_path:$line_num - Empty <a> tag without aria-label" >> "$ISSUE_LOG"
            file_issues=$((file_issues + 1))
        fi
        if echo "$line" | grep -qiE '<a\b[^>]*/\s*>' && ! echo "$line" | grep -qiE 'aria-label\s*='; then
            echo "  [A11Y] $rel_path:$line_num - Self-closing <a> without aria-label" >> "$ISSUE_LOG"
            file_issues=$((file_issues + 1))
        fi

        # --- Check 5: onClick on non-interactive elements without role/tabIndex ---
        if echo "$line" | grep -qiE '<(div|span|p|li|section)\b[^>]*onClick' ; then
            if ! echo "$line" | grep -qiE 'role\s*=' || ! echo "$line" | grep -qiE 'tabIndex\s*='; then
                echo "  [A11Y] $rel_path:$line_num - onClick on non-interactive element without role/tabIndex" >> "$ISSUE_LOG"
                file_issues=$((file_issues + 1))
            fi
        fi

        # --- Check 6: <label> without htmlFor ---
        if echo "$line" | grep -qiE '<label\b' && ! echo "$line" | grep -qiE 'htmlFor\s*=' && ! echo "$line" | grep -qiE 'for\s*='; then
            echo "  [A11Y] $rel_path:$line_num - <label> missing htmlFor attribute" >> "$ISSUE_LOG"
            file_issues=$((file_issues + 1))
        fi

        # --- Check 7: <input> without associated label or aria-label ---
        if echo "$line" | grep -qiE '<input\b' && ! echo "$line" | grep -qiE 'aria-label\s*=' && ! echo "$line" | grep -qiE 'aria-labelledby\s*=' && ! echo "$line" | grep -qiE 'type\s*=\s*"hidden"'; then
            # This is a heuristic - just flag for review
            echo "  [A11Y] $rel_path:$line_num - <input> may lack accessible label (verify htmlFor on parent <label>)" >> "$ISSUE_LOG"
            file_issues=$((file_issues + 1))
        fi

        # --- Check 8: autoFocus usage (can be disorienting) ---
        if echo "$line" | grep -qiE 'autoFocus\b'; then
            echo "  [A11Y] $rel_path:$line_num - autoFocus used (can disorient screen reader users)" >> "$ISSUE_LOG"
            file_issues=$((file_issues + 1))
        fi

        # --- Check 9: tabIndex > 0 (anti-pattern) ---
        if echo "$line" | grep -qiE 'tabIndex\s*=\s*[{"]?[1-9]'; then
            echo "  [A11Y] $rel_path:$line_num - Positive tabIndex value (disrupts natural tab order)" >> "$ISSUE_LOG"
            file_issues=$((file_issues + 1))
        fi

    done < "$file"

    echo "$file_issues"
}

# --- Check heading hierarchy across files ---
check_heading_hierarchy() {
    local file="$1"
    local rel_path="${file#$PROJECT_PATH/}"
    local prev_level=0
    local line_num=0
    local issues=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # Match h1-h6 tags
        if echo "$line" | grep -qoE '<h[1-6]\b'; then
            local level
            level=$(echo "$line" | grep -oE '<h[1-6]' | head -1 | grep -oE '[1-6]')

            if [[ $prev_level -gt 0 && $level -gt $((prev_level + 1)) ]]; then
                echo "  [A11Y] $rel_path:$line_num - Heading hierarchy skip: h${prev_level} -> h${level}" >> "$ISSUE_LOG"
                issues=$((issues + 1))
            fi
            prev_level=$level
        fi
    done < "$file"

    echo "$issues"
}

echo "========================================"
echo " Accessibility Audit Report"
echo "========================================"
echo ""
echo "  Scanning: $SRC_DIR"
echo "  Files:    $TOTAL_FILES JSX/TSX files"
echo ""
echo "========================================"
echo " Issues Found"
echo "========================================"
echo ""

for file in "${FILES[@]}"; do
    count=$(audit_file "$file")
    heading_count=$(check_heading_hierarchy "$file")
    total=$((count + heading_count))
    if [[ $total -gt 0 ]]; then
        FILES_WITH_ISSUES=$((FILES_WITH_ISSUES + 1))
        ISSUES=$((ISSUES + total))
    fi
done

if [[ -s "$ISSUE_LOG" ]]; then
    sort "$ISSUE_LOG"
else
    echo "  No issues found!"
fi

echo ""
echo "========================================"
echo " Summary"
echo "========================================"
echo ""
echo "  Total files scanned:    $TOTAL_FILES"
echo "  Files with issues:      $FILES_WITH_ISSUES"
echo "  Total issues:           $ISSUES"
echo ""
echo "  Checks performed:"
echo "    - Missing alt on <img>"
echo "    - Non-descriptive alt text"
echo "    - Buttons/links without accessible text"
echo "    - onClick on non-interactive elements"
echo "    - Missing htmlFor on <label>"
echo "    - Inputs without accessible labels"
echo "    - Heading hierarchy violations"
echo "    - autoFocus usage"
echo "    - Positive tabIndex values"
echo ""

if [[ $ISSUES -gt 0 ]]; then
    exit 1
else
    exit 0
fi
