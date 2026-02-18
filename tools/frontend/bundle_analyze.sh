#!/bin/bash
set -euo pipefail

# bundle_analyze.sh - Analyze JavaScript bundle sizes
# Usage: bundle_analyze.sh [project_path]
# Exit codes: 0=OK, 1=issues found (large bundles), 2=error

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

if [[ ! -f "$PROJECT_PATH/package.json" ]]; then
    echo "ERROR: No package.json found in $PROJECT_PATH" >&2
    exit 2
fi

PKG="$PROJECT_PATH/package.json"

has_dep() {
    grep -q "\"$1\"" "$PKG" 2>/dev/null
}

echo "========================================"
echo " Bundle Analysis Report"
echo "========================================"
echo ""
echo "  Project: $PROJECT_PATH"
echo ""

# --- Detect build tool ---
BUILD_TOOL="none"
if has_dep "next"; then
    BUILD_TOOL="next"
elif has_dep "vite"; then
    BUILD_TOOL="vite"
elif has_dep "webpack"; then
    BUILD_TOOL="webpack"
elif has_dep "esbuild"; then
    BUILD_TOOL="esbuild"
elif has_dep "parcel"; then
    BUILD_TOOL="parcel"
fi

echo "  Build tool: $BUILD_TOOL"
echo ""

# ============================================================
# Strategy 1: Run build analysis if tools available
# ============================================================

ANALYSIS_RAN=false

if [[ "$BUILD_TOOL" == "next" ]] && command -v npx &>/dev/null; then
    echo "--- Next.js Bundle Analysis ---"
    echo ""
    if has_dep "@next/bundle-analyzer"; then
        echo "  @next/bundle-analyzer is installed."
        echo "  Run: ANALYZE=true npx next build"
        echo ""
    fi

    # Check for .next build output
    if [[ -d "$PROJECT_PATH/.next" ]]; then
        echo "  Existing build found (.next/). Analyzing..."
        echo ""
        # Analyze static chunks
        if [[ -d "$PROJECT_PATH/.next/static/chunks" ]]; then
            echo "  Top 15 largest chunks:"
            echo "  -----------------------------------------------"
            find "$PROJECT_PATH/.next/static/chunks" -type f \( -name "*.js" -o -name "*.js.gz" \) -exec du -h {} + 2>/dev/null | \
                sort -rh | head -15 | while read -r size path; do
                    name=$(basename "$path")
                    printf "  %-8s %s\n" "$size" "$name"
                done
            echo ""
            ANALYSIS_RAN=true
        fi
    fi
fi

if [[ "$BUILD_TOOL" == "vite" ]] && command -v npx &>/dev/null; then
    echo "--- Vite Bundle Analysis ---"
    echo ""
    # Check for dist output
    if [[ -d "$PROJECT_PATH/dist" ]]; then
        echo "  Existing build found (dist/). Analyzing..."
        echo ""
        echo "  Top 15 largest assets:"
        echo "  -----------------------------------------------"
        find "$PROJECT_PATH/dist" -type f \( -name "*.js" -o -name "*.css" -o -name "*.mjs" \) -exec du -h {} + 2>/dev/null | \
            sort -rh | head -15 | while read -r size path; do
                name=$(echo "$path" | sed "s|$PROJECT_PATH/dist/||")
                printf "  %-8s %s\n" "$size" "$name"
            done
        echo ""
        ANALYSIS_RAN=true
    fi
    echo "  For visual analysis, run: npx vite-bundle-visualizer"
    echo ""
fi

if [[ "$BUILD_TOOL" == "webpack" ]] && command -v npx &>/dev/null; then
    echo "--- Webpack Bundle Analysis ---"
    echo ""
    DIST_DIRS=("$PROJECT_PATH/dist" "$PROJECT_PATH/build" "$PROJECT_PATH/out")
    for dir in "${DIST_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "  Existing build found ($dir). Analyzing..."
            echo ""
            echo "  Top 15 largest assets:"
            echo "  -----------------------------------------------"
            find "$dir" -type f \( -name "*.js" -o -name "*.css" \) -exec du -h {} + 2>/dev/null | \
                sort -rh | head -15 | while read -r size path; do
                    name=$(echo "$path" | sed "s|$dir/||")
                    printf "  %-8s %s\n" "$size" "$name"
                done
            echo ""
            ANALYSIS_RAN=true
            break
        fi
    done
    echo "  For detailed analysis, run: npx webpack-bundle-analyzer"
    echo ""
fi

# ============================================================
# Strategy 2: Analyze node_modules
# ============================================================

echo "========================================"
echo " node_modules Analysis"
echo "========================================"
echo ""

if [[ -d "$PROJECT_PATH/node_modules" ]]; then
    TOTAL_SIZE=$(du -sh "$PROJECT_PATH/node_modules" 2>/dev/null | cut -f1)
    echo "  Total node_modules size: $TOTAL_SIZE"
    echo ""

    PACKAGE_COUNT=$(find "$PROJECT_PATH/node_modules" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    echo "  Total packages: $PACKAGE_COUNT"
    echo ""

    echo "  Top 20 largest packages:"
    echo "  -----------------------------------------------"
    # Handle both scoped and non-scoped packages
    (
        # Non-scoped packages
        find "$PROJECT_PATH/node_modules" -maxdepth 1 -mindepth 1 -type d ! -name ".*" ! -name "@*" -exec du -sh {} + 2>/dev/null
        # Scoped packages (flatten @scope/package)
        find "$PROJECT_PATH/node_modules/@"* -maxdepth 1 -mindepth 1 -type d -exec du -sh {} + 2>/dev/null
    ) | sort -rh | head -20 | while read -r size path; do
        name=$(echo "$path" | sed "s|$PROJECT_PATH/node_modules/||")
        printf "  %-8s %s\n" "$size" "$name"
    done
    echo ""

    # Check for common bloat indicators
    echo "========================================"
    echo " Potential Bloat Indicators"
    echo "========================================"
    echo ""

    ISSUES=0

    # Check for duplicate packages
    if [[ -d "$PROJECT_PATH/node_modules" ]]; then
        NESTED_MODULES=$(find "$PROJECT_PATH/node_modules" -mindepth 3 -name "node_modules" -type d 2>/dev/null | wc -l)
        if [[ $NESTED_MODULES -gt 0 ]]; then
            echo "  [!] $NESTED_MODULES nested node_modules directories (possible duplicates)"
            ISSUES=$((ISSUES + 1))
        fi
    fi

    # Check for known heavy packages
    HEAVY_PACKAGES=("moment" "lodash" "@mui/icons-material" "aws-sdk" "core-js")
    for pkg in "${HEAVY_PACKAGES[@]}"; do
        if [[ -d "$PROJECT_PATH/node_modules/$pkg" ]]; then
            SIZE=$(du -sh "$PROJECT_PATH/node_modules/$pkg" 2>/dev/null | cut -f1)
            echo "  [!] Heavy package detected: $pkg ($SIZE)"
            ISSUES=$((ISSUES + 1))
            case "$pkg" in
                moment)  echo "      Consider: dayjs or date-fns" ;;
                lodash)  echo "      Consider: lodash-es or individual imports" ;;
                aws-sdk) echo "      Consider: @aws-sdk/client-* (v3 modular)" ;;
            esac
        fi
    done

    # Check for moment locales
    if [[ -d "$PROJECT_PATH/node_modules/moment/locale" ]]; then
        LOCALE_SIZE=$(du -sh "$PROJECT_PATH/node_modules/moment/locale" 2>/dev/null | cut -f1)
        echo "  [!] moment locales: $LOCALE_SIZE (often unused)"
    fi

    if [[ $ISSUES -eq 0 ]]; then
        echo "  No obvious bloat indicators found."
    fi
    echo ""

else
    echo "  node_modules not found. Run your package manager install first."
    echo ""
fi

# ============================================================
# Strategy 3: package.json dependency count
# ============================================================

echo "========================================"
echo " Dependency Summary"
echo "========================================"
echo ""

DEP_COUNT=$(grep -c '"[^"]*":' <(python3 -c "
import json, sys
with open('$PKG') as f:
    pkg = json.load(f)
deps = pkg.get('dependencies', {})
for k in deps:
    print(k)
" 2>/dev/null) 2>/dev/null || echo "?")

DEVDEP_COUNT=$(grep -c '"[^"]*":' <(python3 -c "
import json, sys
with open('$PKG') as f:
    pkg = json.load(f)
deps = pkg.get('devDependencies', {})
for k in deps:
    print(k)
" 2>/dev/null) 2>/dev/null || echo "?")

echo "  dependencies:    $DEP_COUNT"
echo "  devDependencies: $DEVDEP_COUNT"
echo ""

exit 0
