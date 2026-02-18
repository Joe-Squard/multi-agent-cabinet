#!/bin/bash
set -euo pipefail

###############################################################################
# rn_screen_scaffold.sh — Create React Native screen component with boilerplate
# Usage: rn_screen_scaffold.sh <screen_name> [--navigation=stack|tab|drawer]
# Exit codes: 0=OK, 1=issues found, 2=error
###############################################################################

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <screen_name> [--navigation=stack|tab|drawer] [project_path]

  screen_name   PascalCase name for the screen (e.g., UserProfile)
  --navigation  Navigation type: stack (default), tab, or drawer
  project_path  Path to the RN project root (default: auto-detect git root)

Examples:
  $SCRIPT_NAME HomeScreen
  $SCRIPT_NAME Settings --navigation=tab /path/to/project
EOF
  exit 2
}

# --- Argument parsing ---
SCREEN_NAME=""
NAV_TYPE="stack"
PROJECT_PATH=""

for arg in "$@"; do
  case "$arg" in
    --navigation=*)
      NAV_TYPE="${arg#--navigation=}"
      if [[ ! "$NAV_TYPE" =~ ^(stack|tab|drawer)$ ]]; then
        echo "ERROR: Invalid navigation type '$NAV_TYPE'. Must be stack, tab, or drawer." >&2
        exit 2
      fi
      ;;
    --help|-h)
      usage
      ;;
    *)
      if [[ -z "$SCREEN_NAME" ]]; then
        SCREEN_NAME="$arg"
      elif [[ -z "$PROJECT_PATH" ]]; then
        PROJECT_PATH="$arg"
      fi
      ;;
  esac
done

if [[ -z "$SCREEN_NAME" ]]; then
  echo "ERROR: screen_name is required." >&2
  usage
fi

# Auto-detect project root
if [[ -z "$PROJECT_PATH" ]]; then
  PROJECT_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: Project path '$PROJECT_PATH' does not exist." >&2
  exit 2
fi

# --- Detect Expo vs bare RN ---
IS_EXPO=false
if [[ -f "$PROJECT_PATH/package.json" ]]; then
  if grep -q '"expo"' "$PROJECT_PATH/package.json" 2>/dev/null; then
    IS_EXPO=true
  fi
fi

# --- Determine source directory ---
SRC_DIR="$PROJECT_PATH/src/screens"
if [[ -d "$PROJECT_PATH/app/screens" ]]; then
  SRC_DIR="$PROJECT_PATH/app/screens"
elif [[ -d "$PROJECT_PATH/src/screens" ]]; then
  SRC_DIR="$PROJECT_PATH/src/screens"
fi

TEST_DIR="$PROJECT_PATH/src/__tests__/screens"
if [[ -d "$PROJECT_PATH/app/__tests__" ]]; then
  TEST_DIR="$PROJECT_PATH/app/__tests__/screens"
fi

mkdir -p "$SRC_DIR" "$TEST_DIR"

SCREEN_FILE="$SRC_DIR/${SCREEN_NAME}Screen.tsx"
TEST_FILE="$TEST_DIR/${SCREEN_NAME}Screen.test.tsx"

# --- Determine navigation imports/types ---
case "$NAV_TYPE" in
  stack)
    NAV_IMPORT="import { NativeStackScreenProps } from '@react-navigation/native-stack';"
    NAV_TYPE_DEF="type RootStackParamList = {
  ${SCREEN_NAME}: undefined;
  // Add other screens here
};

type Props = NativeStackScreenProps<RootStackParamList, '${SCREEN_NAME}'>;"
    ;;
  tab)
    NAV_IMPORT="import { BottomTabScreenProps } from '@react-navigation/bottom-tabs';"
    NAV_TYPE_DEF="type RootTabParamList = {
  ${SCREEN_NAME}: undefined;
  // Add other screens here
};

type Props = BottomTabScreenProps<RootTabParamList, '${SCREEN_NAME}'>;"
    ;;
  drawer)
    NAV_IMPORT="import { DrawerScreenProps } from '@react-navigation/drawer';"
    NAV_TYPE_DEF="type RootDrawerParamList = {
  ${SCREEN_NAME}: undefined;
  // Add other screens here
};

type Props = DrawerScreenProps<RootDrawerParamList, '${SCREEN_NAME}'>;"
    ;;
esac

# --- Expo-specific imports ---
EXPO_IMPORTS=""
if $IS_EXPO; then
  EXPO_IMPORTS="import { StatusBar } from 'expo-status-bar';"
fi

# --- Write screen component ---
cat > "$SCREEN_FILE" <<COMPONENT
import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
${NAV_IMPORT}
${EXPO_IMPORTS}

${NAV_TYPE_DEF}

const ${SCREEN_NAME}Screen: React.FC<Props> = ({ navigation, route }) => {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>${SCREEN_NAME}</Text>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#fff',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
  },
});

export default ${SCREEN_NAME}Screen;
COMPONENT

# --- Write test file ---
cat > "$TEST_FILE" <<TEST
import React from 'react';
import { render, screen } from '@testing-library/react-native';
import ${SCREEN_NAME}Screen from '../../screens/${SCREEN_NAME}Screen';

// Mock navigation
const mockNavigation = {
  navigate: jest.fn(),
  goBack: jest.fn(),
  setOptions: jest.fn(),
} as any;

const mockRoute = {
  key: '${SCREEN_NAME}-key',
  name: '${SCREEN_NAME}',
  params: undefined,
} as any;

describe('${SCREEN_NAME}Screen', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders without crashing', () => {
    render(
      <${SCREEN_NAME}Screen navigation={mockNavigation} route={mockRoute} />
    );
  });

  it('displays the screen title', () => {
    render(
      <${SCREEN_NAME}Screen navigation={mockNavigation} route={mockRoute} />
    );
    expect(screen.getByText('${SCREEN_NAME}')).toBeTruthy();
  });
});
TEST

# --- Output summary ---
echo "=============================================="
echo " React Native Screen Scaffold"
echo "=============================================="
echo ""
echo "  Screen name:    ${SCREEN_NAME}Screen"
echo "  Navigation:     ${NAV_TYPE}"
echo "  Platform:       $(if $IS_EXPO; then echo 'Expo'; else echo 'Bare React Native'; fi)"
echo ""
echo "  Created files:"
echo "    [component]  ${SCREEN_FILE}"
echo "    [test]       ${TEST_FILE}"
echo ""
echo "=============================================="
exit 0
