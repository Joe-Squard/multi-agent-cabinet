#!/bin/bash
set -euo pipefail

###############################################################################
# app_size_report.sh — Report app bundle sizes and large assets
# Usage: app_size_report.sh [project_path]
# Exit codes: 0=OK, 1=issues found, 2=error
###############################################################################

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: Project path '$PROJECT_PATH' does not exist." >&2
  exit 2
fi

ISSUES=0

human_size() {
  local bytes=$1
  if [[ $bytes -ge 1073741824 ]]; then
    echo "$(echo "scale=1; $bytes/1073741824" | bc)G"
  elif [[ $bytes -ge 1048576 ]]; then
    echo "$(echo "scale=1; $bytes/1048576" | bc)M"
  elif [[ $bytes -ge 1024 ]]; then
    echo "$(echo "scale=1; $bytes/1024" | bc)K"
  else
    echo "${bytes}B"
  fi
}

echo "=============================================="
echo " App Size Report"
echo " Project: $PROJECT_PATH"
echo "=============================================="
echo ""

# --- Android build outputs ---
echo "## Android Build Outputs"
echo ""

ANDROID_OUTPUT="$PROJECT_PATH/android/app/build/outputs"
if [[ -d "$ANDROID_OUTPUT" ]]; then
  # APK files
  APKS=$(find "$ANDROID_OUTPUT" -name "*.apk" -type f 2>/dev/null || true)
  if [[ -n "$APKS" ]]; then
    echo "  APK files:"
    echo "$APKS" | while IFS= read -r apk; do
      SIZE=$(stat -c%s "$apk" 2>/dev/null || stat -f%z "$apk" 2>/dev/null || echo "0")
      echo "    $(human_size "$SIZE")  ${apk#$PROJECT_PATH/}"
    done
    echo ""
  fi

  # AAB files
  AABS=$(find "$ANDROID_OUTPUT" -name "*.aab" -type f 2>/dev/null || true)
  if [[ -n "$AABS" ]]; then
    echo "  AAB (App Bundle) files:"
    echo "$AABS" | while IFS= read -r aab; do
      SIZE=$(stat -c%s "$aab" 2>/dev/null || stat -f%z "$aab" 2>/dev/null || echo "0")
      echo "    $(human_size "$SIZE")  ${aab#$PROJECT_PATH/}"
    done
    echo ""
  fi

  if [[ -z "$APKS" && -z "$AABS" ]]; then
    echo "  No APK or AAB files found in build outputs."
    echo ""
  fi
else
  echo "  [INFO] No Android build outputs found."
  echo "  Run: cd android && ./gradlew assembleRelease"
  echo ""
fi

# --- iOS build outputs ---
echo "## iOS Build Outputs"
echo ""

IOS_BUILD="$PROJECT_PATH/ios/build"
if [[ -d "$IOS_BUILD" ]]; then
  # .app bundles
  APPS=$(find "$IOS_BUILD" -name "*.app" -type d 2>/dev/null || true)
  if [[ -n "$APPS" ]]; then
    echo "  .app bundles:"
    echo "$APPS" | while IFS= read -r app; do
      SIZE=$(du -sb "$app" 2>/dev/null | cut -f1 || echo "0")
      echo "    $(human_size "$SIZE")  ${app#$PROJECT_PATH/}"
    done
    echo ""
  fi

  # .ipa files
  IPAS=$(find "$IOS_BUILD" -name "*.ipa" -type f 2>/dev/null || true)
  if [[ -n "$IPAS" ]]; then
    echo "  .ipa files:"
    echo "$IPAS" | while IFS= read -r ipa; do
      SIZE=$(stat -c%s "$ipa" 2>/dev/null || stat -f%z "$ipa" 2>/dev/null || echo "0")
      echo "    $(human_size "$SIZE")  ${ipa#$PROJECT_PATH/}"
    done
    echo ""
  fi

  if [[ -z "$APPS" && -z "$IPAS" ]]; then
    echo "  No .app or .ipa files found in build directory."
    echo ""
  fi
else
  echo "  [INFO] No iOS build outputs found."
  echo "  Run: npx react-native run-ios --configuration Release"
  echo ""
fi

# --- node_modules size ---
echo "## node_modules Size Impact"
echo ""

NODE_MODULES="$PROJECT_PATH/node_modules"
if [[ -d "$NODE_MODULES" ]]; then
  TOTAL_NM_SIZE=$(du -sb "$NODE_MODULES" 2>/dev/null | cut -f1 || echo "0")
  echo "  Total node_modules: $(human_size "$TOTAL_NM_SIZE")"
  echo ""

  # Top 10 largest packages
  echo "  Top 10 largest packages:"
  printf "    %-40s %s\n" "PACKAGE" "SIZE"
  printf "    %-40s %s\n" "-------" "----"
  du -sb "$NODE_MODULES"/*/ "$NODE_MODULES"/@*/*/ 2>/dev/null | sort -rn | head -10 | while IFS=$'\t' read -r size path; do
    PKG_NAME="${path#$NODE_MODULES/}"
    PKG_NAME="${PKG_NAME%/}"
    printf "    %-40s %s\n" "$PKG_NAME" "$(human_size "$size")"
  done
  echo ""

  if [[ $TOTAL_NM_SIZE -gt 524288000 ]]; then
    echo "  [WARN] node_modules exceeds 500MB — consider auditing dependencies"
    ((ISSUES++)) || true
  fi
else
  echo "  [INFO] node_modules not found — run 'npm install' or 'yarn'"
fi
echo ""

# --- Largest assets ---
echo "## Largest Assets (images, fonts, videos)"
echo ""

ASSET_DIRS=("$PROJECT_PATH/src/assets" "$PROJECT_PATH/assets" "$PROJECT_PATH/app/assets" "$PROJECT_PATH/static")
ASSET_FOUND=false

printf "  %-50s %s\n" "FILE" "SIZE"
printf "  %-50s %s\n" "----" "----"

for dir in "${ASSET_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    ASSET_FOUND=true
    find "$dir" -type f \( \
      -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif" -o -name "*.svg" \
      -o -name "*.webp" -o -name "*.mp4" -o -name "*.mov" -o -name "*.ttf" -o -name "*.otf" \
      -o -name "*.woff" -o -name "*.woff2" -o -name "*.json" \) 2>/dev/null | while IFS= read -r f; do
      SIZE=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo "0")
      echo "$SIZE $f"
    done
  fi
done | sort -rn | head -20 | while read -r size filepath; do
  printf "  %-50s %s\n" "${filepath#$PROJECT_PATH/}" "$(human_size "$size")"
done

if ! $ASSET_FOUND; then
  echo "  No standard asset directories found (checked src/assets, assets, app/assets, static)"
fi
echo ""

# --- Large image warnings ---
echo "## Size Warnings"
echo ""

LARGE_IMAGES=0
for dir in "${ASSET_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    LARGE=$(find "$dir" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -size +500k 2>/dev/null || true)
    if [[ -n "$LARGE" ]]; then
      echo "$LARGE" | while IFS= read -r f; do
        SIZE=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo "0")
        echo "  [WARN] Large image ($(human_size "$SIZE")): ${f#$PROJECT_PATH/}"
      done
      LARGE_IMAGES=$((LARGE_IMAGES + $(echo "$LARGE" | wc -l)))
    fi
  fi
done

if [[ $LARGE_IMAGES -eq 0 ]]; then
  echo "  No large images (>500K) found."
fi
echo ""

echo "=============================================="
echo " Report complete. Issues: $ISSUES"
echo "=============================================="

if [[ $ISSUES -gt 0 ]]; then
  exit 1
fi
exit 0
