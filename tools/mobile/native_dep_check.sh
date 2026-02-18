#!/bin/bash
set -euo pipefail

###############################################################################
# native_dep_check.sh — Scan for native dependency issues in React Native
# Usage: native_dep_check.sh [project_path]
# Exit codes: 0=OK, 1=issues found, 2=error
###############################################################################

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: Project path '$PROJECT_PATH' does not exist." >&2
  exit 2
fi

PACKAGE_JSON="$PROJECT_PATH/package.json"
if [[ ! -f "$PACKAGE_JSON" ]]; then
  echo "ERROR: No package.json found in '$PROJECT_PATH'." >&2
  exit 2
fi

ISSUES=0
WARNINGS=0

echo "=============================================="
echo " Native Dependency Check"
echo " Project: $PROJECT_PATH"
echo "=============================================="
echo ""

# --- Collect native dependencies ---
echo "## Native Dependencies"
echo ""

NATIVE_DEPS=$(grep -oP '"(react-native-[^"]+|@react-native-[^"]+|@react-native-community/[^"]+)"' "$PACKAGE_JSON" | tr -d '"' | sort -u || true)

if [[ -z "$NATIVE_DEPS" ]]; then
  echo "  No native dependencies found."
  echo ""
else
  DEP_COUNT=$(echo "$NATIVE_DEPS" | wc -l)
  echo "  Found $DEP_COUNT native dependencies:"
  echo ""
  printf "  %-50s %s\n" "PACKAGE" "STATUS"
  printf "  %-50s %s\n" "-------" "------"

  while IFS= read -r dep; do
    # Check if in dependencies or devDependencies
    VERSION=$(grep -oP "\"${dep//\//\\/}\"\s*:\s*\"[^\"]+\"" "$PACKAGE_JSON" | head -1 | grep -oP ':\s*"\K[^"]+' || echo "unknown")
    printf "  %-50s %s\n" "$dep" "$VERSION"
  done <<< "$NATIVE_DEPS"
  echo ""
fi

# --- iOS: Podfile.lock check ---
echo "## iOS (CocoaPods)"
echo ""

PODFILE="$PROJECT_PATH/ios/Podfile"
PODFILE_LOCK="$PROJECT_PATH/ios/Podfile.lock"

if [[ ! -d "$PROJECT_PATH/ios" ]]; then
  echo "  [WARN] ios/ directory not found (Expo managed or not initialized)"
  ((WARNINGS++)) || true
elif [[ ! -f "$PODFILE" ]]; then
  echo "  [WARN] ios/Podfile not found"
  ((WARNINGS++)) || true
elif [[ ! -f "$PODFILE_LOCK" ]]; then
  echo "  [ISSUE] ios/Podfile.lock missing — run 'cd ios && pod install'"
  ((ISSUES++)) || true
else
  # Check if Podfile.lock is older than Podfile
  if [[ "$PODFILE" -nt "$PODFILE_LOCK" ]]; then
    echo "  [ISSUE] Podfile.lock is older than Podfile — run 'cd ios && pod install'"
    ((ISSUES++)) || true
  else
    echo "  [OK] Podfile.lock exists and is up to date"
  fi

  # Check if Podfile.lock is older than package.json
  if [[ "$PACKAGE_JSON" -nt "$PODFILE_LOCK" ]]; then
    echo "  [WARN] package.json is newer than Podfile.lock — pods may need updating"
    ((WARNINGS++)) || true
  fi

  # Count pods
  POD_COUNT=$(grep -c "^  - " "$PODFILE_LOCK" 2>/dev/null || echo "0")
  echo "  Installed pods: $POD_COUNT"
fi
echo ""

# --- Android: build.gradle check ---
echo "## Android (Gradle)"
echo ""

BUILD_GRADLE="$PROJECT_PATH/android/app/build.gradle"
BUILD_GRADLE_KTS="$PROJECT_PATH/android/app/build.gradle.kts"
GRADLE_FILE=""

if [[ -f "$BUILD_GRADLE" ]]; then
  GRADLE_FILE="$BUILD_GRADLE"
elif [[ -f "$BUILD_GRADLE_KTS" ]]; then
  GRADLE_FILE="$BUILD_GRADLE_KTS"
fi

if [[ ! -d "$PROJECT_PATH/android" ]]; then
  echo "  [WARN] android/ directory not found (Expo managed or not initialized)"
  ((WARNINGS++)) || true
elif [[ -z "$GRADLE_FILE" ]]; then
  echo "  [WARN] android/app/build.gradle(.kts) not found"
  ((WARNINGS++)) || true
else
  echo "  [OK] build.gradle found: $GRADLE_FILE"

  # Check for implementation lines referencing react-native
  GRADLE_DEPS=$(grep -c "implementation.*react-native\|implementation.*com.facebook.react" "$GRADLE_FILE" 2>/dev/null || echo "0")
  echo "  React Native gradle dependencies: $GRADLE_DEPS"

  # Check settings.gradle for autolinking
  SETTINGS_GRADLE="$PROJECT_PATH/android/settings.gradle"
  if [[ -f "$SETTINGS_GRADLE" ]]; then
    if grep -q "autolinking" "$SETTINGS_GRADLE" 2>/dev/null; then
      echo "  [OK] Autolinking detected in settings.gradle"
    fi
  fi
fi
echo ""

# --- Check for potentially unlinked modules ---
echo "## Potential Issues"
echo ""

if [[ -n "$NATIVE_DEPS" ]]; then
  while IFS= read -r dep; do
    # Check for known problematic patterns
    BASENAME="${dep##*/}"

    # Check if the module has native code but might not be linked
    MODULE_PATH="$PROJECT_PATH/node_modules/$dep"
    if [[ -d "$MODULE_PATH" ]]; then
      HAS_IOS=false
      HAS_ANDROID=false

      if [[ -d "$MODULE_PATH/ios" ]] || [[ -d "$MODULE_PATH/apple" ]]; then
        HAS_IOS=true
      fi
      if [[ -d "$MODULE_PATH/android" ]]; then
        HAS_ANDROID=true
      fi

      if $HAS_IOS && [[ -f "$PODFILE_LOCK" ]]; then
        # Check if module appears in Podfile.lock
        if ! grep -qi "${BASENAME}" "$PODFILE_LOCK" 2>/dev/null; then
          echo "  [ISSUE] $dep has iOS native code but may not be in Podfile.lock"
          ((ISSUES++)) || true
        fi
      fi

      if ! $HAS_IOS && ! $HAS_ANDROID; then
        : # JS-only module, no issue
      fi
    elif [[ ! -d "$PROJECT_PATH/node_modules" ]]; then
      echo "  [WARN] node_modules not found — run 'npm install' or 'yarn'"
      ((WARNINGS++)) || true
      break
    fi
  done <<< "$NATIVE_DEPS"
fi

if [[ $ISSUES -eq 0 && $WARNINGS -eq 0 ]]; then
  echo "  No issues detected."
fi
echo ""

# --- Summary ---
echo "=============================================="
echo " Summary: $ISSUES issue(s), $WARNINGS warning(s)"
echo "=============================================="

if [[ $ISSUES -gt 0 ]]; then
  exit 1
fi
exit 0
