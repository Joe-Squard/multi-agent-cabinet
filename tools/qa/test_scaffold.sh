#!/bin/bash
set -euo pipefail

###############################################################################
# test_scaffold.sh — Generate test file with describe/it blocks from source
# Usage: test_scaffold.sh <source_file> [project_path]
# Exit codes: 0=OK, 1=issues found, 2=error
###############################################################################

if [[ $# -lt 1 ]]; then
  cat <<EOF
Usage: $(basename "$0") <source_file> [project_path]

  source_file   Path to the source file to create tests for
  project_path  Project root (default: auto-detect git root)

Options:
  --output=FILE   Override output test file path
  --force         Overwrite existing test file

Examples:
  $(basename "$0") src/utils/parser.ts
  $(basename "$0") src/services/auth.py --output=tests/test_auth.py
EOF
  exit 2
fi

# --- Parse arguments ---
SOURCE_FILE=""
PROJECT_PATH=""
OUTPUT_FILE=""
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --output=*)  OUTPUT_FILE="${arg#--output=}" ;;
    --force)     FORCE=true ;;
    --help|-h)   exec "$0" ;;
    *)
      if [[ -z "$SOURCE_FILE" ]]; then
        SOURCE_FILE="$arg"
      elif [[ -z "$PROJECT_PATH" ]]; then
        PROJECT_PATH="$arg"
      fi
      ;;
  esac
done

if [[ -z "$PROJECT_PATH" ]]; then
  PROJECT_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Resolve relative source file path
if [[ ! "$SOURCE_FILE" = /* ]]; then
  SOURCE_FILE="$PROJECT_PATH/$SOURCE_FILE"
fi

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "ERROR: Source file '$SOURCE_FILE' not found." >&2
  exit 2
fi

FILENAME=$(basename "$SOURCE_FILE")
EXT="${FILENAME##*.}"
BASENAME="${FILENAME%.*}"
REL_SOURCE="${SOURCE_FILE#$PROJECT_PATH/}"
SOURCE_DIR=$(dirname "$SOURCE_FILE")

echo "=============================================="
echo " Test Scaffold Generator"
echo " Source: $REL_SOURCE"
echo "=============================================="
echo ""

# --- Detect test framework ---
FRAMEWORK=""
TEST_EXT=""

case "$EXT" in
  ts|tsx)
    TEST_EXT=".test.ts"
    [[ "$EXT" == "tsx" ]] && TEST_EXT=".test.tsx"

    if [[ -f "$PROJECT_PATH/vitest.config.ts" || -f "$PROJECT_PATH/vitest.config.js" ]]; then
      FRAMEWORK="vitest"
    elif [[ -f "$PROJECT_PATH/jest.config.ts" || -f "$PROJECT_PATH/jest.config.js" ]]; then
      FRAMEWORK="jest"
    elif [[ -f "$PROJECT_PATH/package.json" ]] && grep -q '"vitest"' "$PROJECT_PATH/package.json" 2>/dev/null; then
      FRAMEWORK="vitest"
    elif [[ -f "$PROJECT_PATH/package.json" ]] && grep -q '"jest"' "$PROJECT_PATH/package.json" 2>/dev/null; then
      FRAMEWORK="jest"
    else
      FRAMEWORK="jest"  # default for TS
    fi
    ;;
  js|jsx)
    TEST_EXT=".test.js"
    [[ "$EXT" == "jsx" ]] && TEST_EXT=".test.jsx"

    if [[ -f "$PROJECT_PATH/vitest.config.ts" || -f "$PROJECT_PATH/vitest.config.js" ]]; then
      FRAMEWORK="vitest"
    else
      FRAMEWORK="jest"
    fi
    ;;
  py)
    TEST_EXT=".py"
    FRAMEWORK="pytest"
    ;;
  go)
    TEST_EXT="_test.go"
    FRAMEWORK="gotest"
    ;;
  *)
    echo "ERROR: Unsupported file type '.$EXT'." >&2
    exit 2
    ;;
esac

echo "  Framework: $FRAMEWORK"

# --- Determine test file location ---
if [[ -z "$OUTPUT_FILE" ]]; then
  case "$FRAMEWORK" in
    jest|vitest)
      # Check for __tests__ directory convention
      if [[ -d "$SOURCE_DIR/__tests__" ]]; then
        OUTPUT_FILE="$SOURCE_DIR/__tests__/${BASENAME}${TEST_EXT}"
      elif [[ -d "$PROJECT_PATH/tests" ]]; then
        # Mirror source structure in tests/
        REL_DIR="${SOURCE_DIR#$PROJECT_PATH/}"
        mkdir -p "$PROJECT_PATH/tests/$REL_DIR"
        OUTPUT_FILE="$PROJECT_PATH/tests/$REL_DIR/${BASENAME}${TEST_EXT}"
      else
        # Co-located test
        OUTPUT_FILE="$SOURCE_DIR/${BASENAME}${TEST_EXT}"
      fi
      ;;
    pytest)
      if [[ -d "$PROJECT_PATH/tests" ]]; then
        REL_DIR="${SOURCE_DIR#$PROJECT_PATH/}"
        mkdir -p "$PROJECT_PATH/tests/$REL_DIR"
        OUTPUT_FILE="$PROJECT_PATH/tests/${REL_DIR}/test_${BASENAME}${TEST_EXT}"
      else
        OUTPUT_FILE="$SOURCE_DIR/test_${BASENAME}${TEST_EXT}"
      fi
      ;;
    gotest)
      OUTPUT_FILE="$SOURCE_DIR/${BASENAME}${TEST_EXT}"
      ;;
  esac
fi

# Resolve relative output path
if [[ ! "$OUTPUT_FILE" = /* ]]; then
  OUTPUT_FILE="$PROJECT_PATH/$OUTPUT_FILE"
fi

REL_OUTPUT="${OUTPUT_FILE#$PROJECT_PATH/}"

if [[ -f "$OUTPUT_FILE" && "$FORCE" != "true" ]]; then
  echo "  [WARN] Test file already exists: $REL_OUTPUT"
  echo "  Use --force to overwrite."
  exit 1
fi

echo "  Output: $REL_OUTPUT"
echo ""

# --- Extract exports/functions ---
echo "## Extracting definitions..."
echo ""

case "$FRAMEWORK" in
  jest|vitest)
    # Extract TypeScript/JavaScript exports
    EXPORTS=$(grep -oP 'export\s+(const|function|class|type|interface|enum|async\s+function)\s+\K[a-zA-Z_]\w*' "$SOURCE_FILE" 2>/dev/null || true)
    DEFAULT_EXPORT=$(grep -oP 'export\s+default\s+(class|function|)\s*\K[a-zA-Z_]\w*' "$SOURCE_FILE" 2>/dev/null || true)
    FUNCTIONS=$(grep -oP '(?:export\s+)?(?:async\s+)?function\s+\K[a-zA-Z_]\w*' "$SOURCE_FILE" 2>/dev/null || true)

    # Combine unique names
    ALL_NAMES=$(echo -e "${EXPORTS}\n${DEFAULT_EXPORT}\n${FUNCTIONS}" | sort -u | sed '/^$/d')

    if [[ -z "$ALL_NAMES" ]]; then
      echo "  [WARN] No exports or functions found in source file."
      ALL_NAMES="$BASENAME"
    fi

    # Calculate relative import path
    TEST_DIR=$(dirname "$OUTPUT_FILE")
    REL_IMPORT=$(python3 -c "
import os.path
source = '$SOURCE_FILE'
test_dir = '$TEST_DIR'
rel = os.path.relpath(source, test_dir)
# Remove extension
rel = rel.rsplit('.', 1)[0]
if not rel.startswith('.'):
    rel = './' + rel
print(rel)
" 2>/dev/null || echo "./${BASENAME}")

    # Build import list
    NAMED_EXPORTS=$(echo "$EXPORTS" | sed '/^$/d' | tr '\n' ', ' | sed 's/,$//')

    # Generate test file
    IMPORT_LINE=""
    if [[ -n "$DEFAULT_EXPORT" ]]; then
      if [[ -n "$NAMED_EXPORTS" ]]; then
        IMPORT_LINE="import ${DEFAULT_EXPORT}, { ${NAMED_EXPORTS} } from '${REL_IMPORT}';"
      else
        IMPORT_LINE="import ${DEFAULT_EXPORT} from '${REL_IMPORT}';"
      fi
    elif [[ -n "$NAMED_EXPORTS" ]]; then
      IMPORT_LINE="import { ${NAMED_EXPORTS} } from '${REL_IMPORT}';"
    else
      IMPORT_LINE="import ${BASENAME} from '${REL_IMPORT}';"
    fi

    # Determine describe/it/expect imports for vitest
    VITEST_IMPORT=""
    if [[ "$FRAMEWORK" == "vitest" ]]; then
      VITEST_IMPORT="import { describe, it, expect, vi } from 'vitest';"
    fi

    # Generate test content
    {
      if [[ -n "$VITEST_IMPORT" ]]; then
        echo "$VITEST_IMPORT"
      fi
      echo "$IMPORT_LINE"
      echo ""

      echo "describe('${BASENAME}', () => {"

      while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        echo "  describe('${name}', () => {"
        echo "    it('should be defined', () => {"
        echo "      expect(${name}).toBeDefined();"
        echo "    });"
        echo ""
        echo "    it('should work correctly', () => {"
        echo "      // TODO: Add test implementation"
        echo "    });"
        echo ""
        echo "    it('should handle edge cases', () => {"
        echo "      // TODO: Add edge case tests"
        echo "    });"
        echo "  });"
        echo ""
      done <<< "$ALL_NAMES"

      echo "});"
    } > "$OUTPUT_FILE"
    ;;

  pytest)
    # Extract Python functions and classes
    FUNCTIONS=$(grep -oP '(?:^|\s)def\s+\K[a-zA-Z_]\w*' "$SOURCE_FILE" 2>/dev/null | grep -v "^_" || true)
    CLASSES=$(grep -oP '(?:^|\s)class\s+\K[a-zA-Z_]\w*' "$SOURCE_FILE" 2>/dev/null || true)

    ALL_NAMES=$(echo -e "${FUNCTIONS}\n${CLASSES}" | sort -u | sed '/^$/d')

    if [[ -z "$ALL_NAMES" ]]; then
      echo "  [WARN] No functions or classes found in source file."
      ALL_NAMES="module"
    fi

    # Calculate import path
    REL_MODULE=$(python3 -c "
import os.path
source = '$SOURCE_FILE'
project = '$PROJECT_PATH'
rel = os.path.relpath(source, project)
# Convert path to module
module = rel.rsplit('.', 1)[0].replace('/', '.')
print(module)
" 2>/dev/null || echo "$BASENAME")

    # Generate pytest file
    {
      echo "\"\"\"Tests for ${REL_SOURCE}\"\"\""
      echo "import pytest"
      echo ""

      # Import functions
      if [[ -n "$FUNCTIONS" ]]; then
        FUNC_LIST=$(echo "$FUNCTIONS" | tr '\n' ', ' | sed 's/,$//')
        echo "from ${REL_MODULE} import ${FUNC_LIST}"
      fi
      if [[ -n "$CLASSES" ]]; then
        CLASS_LIST=$(echo "$CLASSES" | tr '\n' ', ' | sed 's/,$//')
        echo "from ${REL_MODULE} import ${CLASS_LIST}"
      fi
      echo ""
      echo ""

      # Generate test functions
      while IFS= read -r name; do
        [[ -z "$name" ]] && continue

        # Check if it's a class
        if echo "$CLASSES" | grep -q "^${name}$" 2>/dev/null; then
          echo "class Test${name}:"
          echo "    \"\"\"Tests for ${name} class.\"\"\""
          echo ""
          echo "    def test_instantiation(self):"
          echo "        \"\"\"Test that ${name} can be instantiated.\"\"\""
          echo "        # TODO: Add constructor arguments"
          echo "        instance = ${name}()"
          echo "        assert instance is not None"
          echo ""
          echo "    def test_basic_behavior(self):"
          echo "        \"\"\"Test basic behavior of ${name}.\"\"\""
          echo "        # TODO: Implement test"
          echo "        pytest.skip('Not implemented')"
          echo ""
          echo ""
        else
          echo "def test_${name}_returns_expected():"
          echo "    \"\"\"Test that ${name} returns expected result.\"\"\""
          echo "    # TODO: Implement test"
          echo "    result = ${name}()"
          echo "    assert result is not None"
          echo ""
          echo ""
          echo "def test_${name}_handles_edge_cases():"
          echo "    \"\"\"Test ${name} with edge case inputs.\"\"\""
          echo "    # TODO: Add edge case tests"
          echo "    pytest.skip('Not implemented')"
          echo ""
          echo ""
        fi
      done <<< "$ALL_NAMES"
    } > "$OUTPUT_FILE"
    ;;

  gotest)
    # Extract Go functions
    PACKAGE=$(grep -oP '^package\s+\K\w+' "$SOURCE_FILE" 2>/dev/null | head -1 || echo "main")
    FUNCTIONS=$(grep -oP '^func\s+\K[A-Z]\w*' "$SOURCE_FILE" 2>/dev/null || true)
    METHODS=$(grep -oP '^func\s+\([^)]+\)\s+\K[A-Z]\w*' "$SOURCE_FILE" 2>/dev/null || true)

    ALL_NAMES=$(echo -e "${FUNCTIONS}\n${METHODS}" | sort -u | sed '/^$/d')

    {
      echo "package ${PACKAGE}"
      echo ""
      echo "import ("
      echo "	\"testing\""
      echo ")"
      echo ""

      while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        echo "func Test${name}(t *testing.T) {"
        echo "	t.Run(\"basic\", func(t *testing.T) {"
        echo "		// TODO: Implement test"
        echo "		t.Skip(\"Not implemented\")"
        echo "	})"
        echo ""
        echo "	t.Run(\"edge_cases\", func(t *testing.T) {"
        echo "		// TODO: Add edge case tests"
        echo "		t.Skip(\"Not implemented\")"
        echo "	})"
        echo "}"
        echo ""
      done <<< "$ALL_NAMES"
    } > "$OUTPUT_FILE"
    ;;
esac

# Ensure parent directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

# --- Report ---
echo "  Definitions found:"
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  echo "    - $name"
done <<< "$ALL_NAMES"
echo ""

LINES=$(wc -l < "$OUTPUT_FILE")
echo "  Generated: $REL_OUTPUT ($LINES lines)"
echo ""

echo "=============================================="
echo " Test scaffold created successfully"
echo " Framework: $FRAMEWORK"
echo " Run tests:"
case "$FRAMEWORK" in
  jest)    echo "   npx jest ${REL_OUTPUT}" ;;
  vitest)  echo "   npx vitest ${REL_OUTPUT}" ;;
  pytest)  echo "   python3 -m pytest ${REL_OUTPUT}" ;;
  gotest)  echo "   go test ./${REL_OUTPUT%/*}" ;;
esac
echo "=============================================="
exit 0
