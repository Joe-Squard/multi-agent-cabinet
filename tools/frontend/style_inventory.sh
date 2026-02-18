#!/bin/bash
set -euo pipefail

# style_inventory.sh - Inventory all color values in a project
# Usage: style_inventory.sh [project_path]
# Exit codes: 0=OK, 1=potential issues (duplicates), 2=error

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

SRC_DIR="$PROJECT_PATH/src"
if [[ ! -d "$SRC_DIR" ]]; then
    SRC_DIR="$PROJECT_PATH"
fi

PKG="$PROJECT_PATH/package.json"

echo "========================================"
echo " Style & Color Inventory"
echo "========================================"
echo ""
echo "  Project: $PROJECT_PATH"
echo ""

# --- Detect styling approach ---
USES_TAILWIND=false
TAILWIND_CONFIG=""
if [[ -f "$PKG" ]] && grep -q '"tailwindcss"' "$PKG" 2>/dev/null; then
    USES_TAILWIND=true
    for cfg in tailwind.config.ts tailwind.config.js tailwind.config.mjs tailwind.config.cjs; do
        if [[ -f "$PROJECT_PATH/$cfg" ]]; then
            TAILWIND_CONFIG="$PROJECT_PATH/$cfg"
            break
        fi
    done
fi

echo "  Tailwind CSS: $USES_TAILWIND"
if [[ -n "$TAILWIND_CONFIG" ]]; then
    echo "  Tailwind config: ${TAILWIND_CONFIG#$PROJECT_PATH/}"
fi
echo ""

# Temporary files
COLOR_FILE=$(mktemp)
TW_CUSTOM_FILE=$(mktemp)
trap 'rm -f "$COLOR_FILE" "$TW_CUSTOM_FILE"' EXIT

# ============================================================
# Collect colors from CSS/SCSS/TSX/JSX files
# ============================================================

echo "========================================"
echo " Color Values Found"
echo "========================================"
echo ""

# Find relevant files
FILE_EXTENSIONS=( "*.css" "*.scss" "*.sass" "*.less" "*.tsx" "*.jsx" "*.ts" "*.js" )
FIND_ARGS=()
for ext in "${FILE_EXTENSIONS[@]}"; do
    FIND_ARGS+=(-name "$ext" -o)
done
# Remove trailing -o
unset 'FIND_ARGS[-1]'

while IFS= read -r -d '' file; do
    rel_path="${file#$PROJECT_PATH/}"
    line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # Skip comments and imports
        [[ "$line" =~ ^[[:space:]]*(//|\*|/\*|import|require) ]] && continue

        # --- Hex colors (#RGB, #RRGGBB, #RRGGBBAA) ---
        while read -r color; do
            [[ -n "$color" ]] && echo "$color|$rel_path:$line_num" >> "$COLOR_FILE"
        done < <(echo "$line" | grep -oiE '#[0-9a-fA-F]{3,8}\b' | grep -iE '^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$' || true)

        # --- rgb/rgba ---
        while read -r color; do
            [[ -n "$color" ]] && echo "$color|$rel_path:$line_num" >> "$COLOR_FILE"
        done < <(echo "$line" | grep -oiE 'rgba?\([^)]+\)' || true)

        # --- hsl/hsla ---
        while read -r color; do
            [[ -n "$color" ]] && echo "$color|$rel_path:$line_num" >> "$COLOR_FILE"
        done < <(echo "$line" | grep -oiE 'hsla?\([^)]+\)' || true)

        # --- oklch ---
        while read -r color; do
            [[ -n "$color" ]] && echo "$color|$rel_path:$line_num" >> "$COLOR_FILE"
        done < <(echo "$line" | grep -oiE 'oklch\([^)]+\)' || true)

        # --- CSS named colors in style contexts (common ones) ---
        # Skip this to avoid false positives - focus on explicit values

    done < "$file"
done < <(find "$SRC_DIR" -type f \( "${FIND_ARGS[@]}" \) \
    ! -path "*/node_modules/*" ! -path "*/.next/*" ! -path "*/dist/*" \
    ! -path "*/build/*" ! -path "*/*.min.*" ! -path "*/*.d.ts" \
    -print0 2>/dev/null)

if [[ ! -s "$COLOR_FILE" ]]; then
    echo "  No color values found in source files."
    echo ""
    exit 0
fi

# --- Count unique colors ---
UNIQUE_COLORS=$(cut -d'|' -f1 "$COLOR_FILE" | tr '[:upper:]' '[:lower:]' | sort -u | wc -l)
TOTAL_USAGES=$(wc -l < "$COLOR_FILE")

echo "  Unique color values: $UNIQUE_COLORS"
echo "  Total usages:        $TOTAL_USAGES"
echo ""

# --- Color frequency table ---
echo "  --- Color Frequency (top 30) ---"
echo ""
printf "  %-8s  %-30s  %s\n" "Count" "Color" "Example Location"
echo "  -------  ------------------------------  --------------------------"

cut -d'|' -f1 "$COLOR_FILE" | tr '[:upper:]' '[:lower:]' | sort | uniq -c | sort -rn | head -30 | while read -r count color; do
    # Find first usage location
    location=$(grep -i "^${color}|" "$COLOR_FILE" | head -1 | cut -d'|' -f2)
    printf "  %-8s  %-30s  %s\n" "$count" "$color" "$location"
done

echo ""

# ============================================================
# Hex color analysis: find near-duplicates
# ============================================================

echo "========================================"
echo " Near-Duplicate Analysis (Hex Colors)"
echo "========================================"
echo ""

# Extract unique hex colors, normalize to 6-digit lowercase
HEX_COLORS=$(mktemp)
trap 'rm -f "$COLOR_FILE" "$TW_CUSTOM_FILE" "$HEX_COLORS"' EXIT

cut -d'|' -f1 "$COLOR_FILE" | grep -iE '^#[0-9a-fA-F]+$' | tr '[:upper:]' '[:lower:]' | sort -u | while read -r hex; do
    # Expand 3-digit hex to 6-digit
    if [[ ${#hex} -eq 4 ]]; then
        r="${hex:1:1}"; g="${hex:2:1}"; b="${hex:3:1}"
        hex="#${r}${r}${g}${g}${b}${b}"
    fi
    # Only consider 6-digit hex for comparison
    if [[ ${#hex} -eq 7 ]]; then
        echo "$hex"
    fi
done > "$HEX_COLORS"

HEX_COUNT=$(wc -l < "$HEX_COLORS")

if [[ $HEX_COUNT -lt 2 ]]; then
    echo "  Not enough hex colors for duplicate analysis."
    echo ""
else
    # Simple near-duplicate detection: compare hex values with small differences
    NEAR_DUPES=0

    mapfile -t hex_arr < "$HEX_COLORS"
    for ((i=0; i<${#hex_arr[@]}; i++)); do
        for ((j=i+1; j<${#hex_arr[@]}; j++)); do
            c1="${hex_arr[$i]}"
            c2="${hex_arr[$j]}"

            # Parse RGB components
            r1=$((16#${c1:1:2})); g1=$((16#${c1:3:2})); b1=$((16#${c1:5:2}))
            r2=$((16#${c2:1:2})); g2=$((16#${c2:3:2})); b2=$((16#${c2:5:2}))

            # Calculate difference (Manhattan distance)
            dr=$(( r1 > r2 ? r1 - r2 : r2 - r1 ))
            dg=$(( g1 > g2 ? g1 - g2 : g2 - g1 ))
            db=$(( b1 > b2 ? b1 - b2 : b2 - b1 ))
            diff=$((dr + dg + db))

            # Threshold: colors within 15 units total difference
            if [[ $diff -gt 0 && $diff -le 15 ]]; then
                echo "  Potential duplicate: $c1 <-> $c2 (diff: $diff)"
                NEAR_DUPES=$((NEAR_DUPES + 1))
            fi
        done
    done

    if [[ $NEAR_DUPES -eq 0 ]]; then
        echo "  No near-duplicate hex colors found."
    else
        echo ""
        echo "  Total near-duplicates: $NEAR_DUPES"
    fi
    echo ""
fi

# ============================================================
# Tailwind Analysis
# ============================================================

if [[ "$USES_TAILWIND" == true ]]; then
    echo "========================================"
    echo " Tailwind CSS Analysis"
    echo "========================================"
    echo ""

    # Check for custom colors in tailwind config
    if [[ -n "$TAILWIND_CONFIG" ]]; then
        echo "  Custom colors in Tailwind config:"
        echo ""
        # Extract color-related lines from config
        if grep -qE "colors|color" "$TAILWIND_CONFIG" 2>/dev/null; then
            grep -nE "(colors|color)" "$TAILWIND_CONFIG" | head -20 | while read -r line; do
                echo "    $line"
            done
        else
            echo "    (No custom colors in config)"
        fi
        echo ""
    fi

    # Scan for inline style colors in TSX (bypassing Tailwind)
    INLINE_STYLES=0
    while IFS= read -r -d '' file; do
        count=$(grep -cE 'style\s*=\s*\{.*color|style\s*=\s*\{.*background' "$file" 2>/dev/null || true)
        INLINE_STYLES=$((INLINE_STYLES + count))
    done < <(find "$SRC_DIR" -type f \( -name "*.tsx" -o -name "*.jsx" \) \
        ! -path "*/node_modules/*" -print0 2>/dev/null)

    if [[ $INLINE_STYLES -gt 0 ]]; then
        echo "  [!] Found $INLINE_STYLES inline style color usages (bypassing Tailwind)"
        echo "      Consider using Tailwind utility classes instead."
    else
        echo "  No inline style colors detected (good - Tailwind is used consistently)"
    fi
    echo ""

    # Scan for arbitrary color values in Tailwind classes
    ARB_COLORS=0
    while IFS= read -r -d '' file; do
        count=$(grep -coE '(bg|text|border|ring|fill|stroke)-\[#[0-9a-fA-F]+\]' "$file" 2>/dev/null || true)
        ARB_COLORS=$((ARB_COLORS + count))
    done < <(find "$SRC_DIR" -type f \( -name "*.tsx" -o -name "*.jsx" \) \
        ! -path "*/node_modules/*" -print0 2>/dev/null)

    if [[ $ARB_COLORS -gt 0 ]]; then
        echo "  [!] Found $ARB_COLORS arbitrary Tailwind color values (e.g., bg-[#ff0000])"
        echo "      Consider defining these in tailwind.config for consistency."
    fi
    echo ""
fi

# ============================================================
# Summary
# ============================================================

echo "========================================"
echo " Summary"
echo "========================================"
echo ""

# Count by type
HEX_UNIQUE=$(cut -d'|' -f1 "$COLOR_FILE" | grep -ciE '^#' || true)
RGB_UNIQUE=$(cut -d'|' -f1 "$COLOR_FILE" | grep -ciE '^rgba?\(' || true)
HSL_UNIQUE=$(cut -d'|' -f1 "$COLOR_FILE" | grep -ciE '^hsla?\(' || true)
OKLCH_UNIQUE=$(cut -d'|' -f1 "$COLOR_FILE" | grep -ciE '^oklch\(' || true)

echo "  Color formats used:"
[[ $HEX_UNIQUE -gt 0 ]]   && echo "    Hex:    $HEX_UNIQUE usages"
[[ $RGB_UNIQUE -gt 0 ]]   && echo "    RGB(A): $RGB_UNIQUE usages"
[[ $HSL_UNIQUE -gt 0 ]]   && echo "    HSL(A): $HSL_UNIQUE usages"
[[ $OKLCH_UNIQUE -gt 0 ]] && echo "    OKLCH:  $OKLCH_UNIQUE usages"
echo ""

HAS_ISSUES=false
if [[ $UNIQUE_COLORS -gt 50 ]]; then
    echo "  [!] High number of unique colors ($UNIQUE_COLORS). Consider consolidating into a design token system."
    HAS_ISSUES=true
fi

MULTI_FORMATS=0
[[ $HEX_UNIQUE -gt 0 ]] && MULTI_FORMATS=$((MULTI_FORMATS + 1))
[[ $RGB_UNIQUE -gt 0 ]] && MULTI_FORMATS=$((MULTI_FORMATS + 1))
[[ $HSL_UNIQUE -gt 0 ]] && MULTI_FORMATS=$((MULTI_FORMATS + 1))
[[ $OKLCH_UNIQUE -gt 0 ]] && MULTI_FORMATS=$((MULTI_FORMATS + 1))

if [[ $MULTI_FORMATS -gt 2 ]]; then
    echo "  [!] Multiple color formats used ($MULTI_FORMATS). Consider standardizing on one format."
    HAS_ISSUES=true
fi

if [[ "$HAS_ISSUES" == true ]]; then
    echo ""
    exit 1
else
    echo "  No significant issues found."
    echo ""
    exit 0
fi
