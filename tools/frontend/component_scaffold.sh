#!/bin/bash
set -euo pipefail

# component_scaffold.sh - Scaffold a React/Vue component with tests and barrel export
# Usage: component_scaffold.sh <name> [--type=component|page|hook] [--dir=path] [project_path]
# Exit codes: 0=created, 1=already exists, 2=error

usage() {
    cat <<'USAGE'
Usage: component_scaffold.sh <ComponentName> [options] [project_path]

Options:
  --type=TYPE    component (default), page, or hook
  --dir=PATH     Output directory (relative to project src/)

Examples:
  component_scaffold.sh UserProfile
  component_scaffold.sh Dashboard --type=page --dir=pages
  component_scaffold.sh useAuth --type=hook
USAGE
    exit 2
}

# --- Parse Arguments ---
COMPONENT_NAME=""
COMPONENT_TYPE="component"
CUSTOM_DIR=""
PROJECT_PATH=""

for arg in "$@"; do
    case "$arg" in
        --type=*) COMPONENT_TYPE="${arg#--type=}" ;;
        --dir=*)  CUSTOM_DIR="${arg#--dir=}" ;;
        --help|-h) usage ;;
        -*)       echo "ERROR: Unknown option: $arg" >&2; usage ;;
        *)
            if [[ -z "$COMPONENT_NAME" ]]; then
                COMPONENT_NAME="$arg"
            elif [[ -z "$PROJECT_PATH" ]]; then
                PROJECT_PATH="$arg"
            fi
            ;;
    esac
done

if [[ -z "$COMPONENT_NAME" ]]; then
    echo "ERROR: Component name is required." >&2
    usage
fi

PROJECT_PATH="${PROJECT_PATH:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

if [[ ! -f "$PROJECT_PATH/package.json" ]]; then
    echo "ERROR: No package.json found in $PROJECT_PATH" >&2
    exit 2
fi

# --- Detect Conventions from package.json ---
PKG="$PROJECT_PATH/package.json"

detect_dep() {
    grep -q "\"$1\"" "$PKG" 2>/dev/null
}

# Styling
STYLE_SYSTEM="plain-css"
if detect_dep "tailwindcss"; then
    STYLE_SYSTEM="tailwind"
elif detect_dep "styled-components"; then
    STYLE_SYSTEM="styled-components"
elif detect_dep "@emotion/styled"; then
    STYLE_SYSTEM="emotion"
elif find "$PROJECT_PATH/src" -name "*.module.css" -o -name "*.module.scss" 2>/dev/null | head -1 | grep -q .; then
    STYLE_SYSTEM="css-modules"
fi

# Test framework
TEST_FRAMEWORK="jest"
if detect_dep "vitest"; then
    TEST_FRAMEWORK="vitest"
fi

# TypeScript?
USE_TS=true
if [[ ! -f "$PROJECT_PATH/tsconfig.json" ]]; then
    USE_TS=false
fi

EXT="tsx"
if [[ "$USE_TS" == false ]]; then
    EXT="jsx"
fi

# --- Determine Output Directory ---
SRC_DIR="$PROJECT_PATH/src"
if [[ ! -d "$SRC_DIR" ]]; then
    SRC_DIR="$PROJECT_PATH"
fi

if [[ -n "$CUSTOM_DIR" ]]; then
    OUTPUT_DIR="$SRC_DIR/$CUSTOM_DIR/$COMPONENT_NAME"
elif [[ "$COMPONENT_TYPE" == "page" ]]; then
    OUTPUT_DIR="$SRC_DIR/pages/$COMPONENT_NAME"
elif [[ "$COMPONENT_TYPE" == "hook" ]]; then
    OUTPUT_DIR="$SRC_DIR/hooks"
else
    OUTPUT_DIR="$SRC_DIR/components/$COMPONENT_NAME"
fi

# --- For hooks, adjust naming ---
if [[ "$COMPONENT_TYPE" == "hook" ]]; then
    # Ensure hook name starts with "use"
    if [[ ! "$COMPONENT_NAME" =~ ^use ]]; then
        HOOK_NAME="use${COMPONENT_NAME}"
    else
        HOOK_NAME="$COMPONENT_NAME"
    fi
fi

# --- Check for existing files ---
if [[ "$COMPONENT_TYPE" != "hook" && -d "$OUTPUT_DIR" ]]; then
    echo "ERROR: Directory already exists: $OUTPUT_DIR" >&2
    exit 1
elif [[ "$COMPONENT_TYPE" == "hook" && -f "$OUTPUT_DIR/$HOOK_NAME.$EXT" ]]; then
    echo "ERROR: Hook file already exists: $OUTPUT_DIR/$HOOK_NAME.$EXT" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ============================================================
# Generate Files
# ============================================================

if [[ "$COMPONENT_TYPE" == "hook" ]]; then
    # --- Hook ---
    if [[ "$USE_TS" == true ]]; then
        cat > "$OUTPUT_DIR/$HOOK_NAME.ts" <<HOOKTS
import { useState, useEffect, useCallback } from 'react';

interface ${HOOK_NAME}Options {
  // Add options here
}

interface ${HOOK_NAME}Return {
  // Add return type here
  isLoading: boolean;
  error: Error | null;
}

export function ${HOOK_NAME}(options?: ${HOOK_NAME}Options): ${HOOK_NAME}Return {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    // Effect logic here
  }, []);

  return {
    isLoading,
    error,
  };
}
HOOKTS
    else
        cat > "$OUTPUT_DIR/$HOOK_NAME.js" <<HOOKJS
import { useState, useEffect, useCallback } from 'react';

export function ${HOOK_NAME}(options = {}) {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    // Effect logic here
  }, []);

  return {
    isLoading,
    error,
  };
}
HOOKJS
    fi

    # Hook test
    TEST_FILE="$OUTPUT_DIR/$HOOK_NAME.test.$EXT"
    if [[ "$TEST_FRAMEWORK" == "vitest" ]]; then
        cat > "$TEST_FILE" <<VTEST
import { describe, it, expect } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { ${HOOK_NAME} } from './${HOOK_NAME}';

describe('${HOOK_NAME}', () => {
  it('should initialize with default values', () => {
    const { result } = renderHook(() => ${HOOK_NAME}());
    expect(result.current.isLoading).toBe(false);
    expect(result.current.error).toBeNull();
  });
});
VTEST
    else
        cat > "$TEST_FILE" <<JTEST
import { renderHook, act } from '@testing-library/react';
import { ${HOOK_NAME} } from './${HOOK_NAME}';

describe('${HOOK_NAME}', () => {
  it('should initialize with default values', () => {
    const { result } = renderHook(() => ${HOOK_NAME}());
    expect(result.current.isLoading).toBe(false);
    expect(result.current.error).toBeNull();
  });
});
JTEST
    fi

    echo "Hook created:"
    echo "  $OUTPUT_DIR/$HOOK_NAME.${USE_TS:+ts}"
    echo "  $TEST_FILE"
    echo ""
    echo "Style: $STYLE_SYSTEM | Test: $TEST_FRAMEWORK | TypeScript: $USE_TS"
    exit 0
fi

# --- Component / Page ---

# Component file
COMP_FILE="$OUTPUT_DIR/$COMPONENT_NAME.$EXT"
TEST_FILE="$OUTPUT_DIR/$COMPONENT_NAME.test.$EXT"
INDEX_FILE="$OUTPUT_DIR/index.${USE_TS:+ts}"
if [[ "$USE_TS" == false ]]; then
    INDEX_FILE="$OUTPUT_DIR/index.js"
fi

PROPS_TYPE=""
if [[ "$USE_TS" == true ]]; then
    PROPS_TYPE="
interface ${COMPONENT_NAME}Props {
  className?: string;
  children?: React.ReactNode;
}
"
fi

STYLE_IMPORT=""
CLASS_ATTR=""
case "$STYLE_SYSTEM" in
    tailwind)
        CLASS_ATTR=' className="'
        if [[ "$COMPONENT_TYPE" == "page" ]]; then
            CLASS_ATTR+='container mx-auto p-4"'
        else
            CLASS_ATTR+='"'
        fi
        ;;
    css-modules)
        STYLE_IMPORT="import styles from './${COMPONENT_NAME}.module.css';"
        CLASS_ATTR=' className={styles.root}'
        cat > "$OUTPUT_DIR/${COMPONENT_NAME}.module.css" <<MODCSS
.root {
  /* ${COMPONENT_NAME} styles */
}
MODCSS
        ;;
    styled-components)
        STYLE_IMPORT="import styled from 'styled-components';"
        ;;
    *)
        STYLE_IMPORT="import './${COMPONENT_NAME}.css';"
        cat > "$OUTPUT_DIR/${COMPONENT_NAME}.css" <<PLAINCSS
.${COMPONENT_NAME} {
  /* ${COMPONENT_NAME} styles */
}
PLAINCSS
        CLASS_ATTR=" className=\"${COMPONENT_NAME}\""
        ;;
esac

# Generate component
if [[ "$STYLE_SYSTEM" == "styled-components" ]]; then
    if [[ "$USE_TS" == true ]]; then
        cat > "$COMP_FILE" <<STYLEDTS
import React from 'react';
import styled from 'styled-components';
${PROPS_TYPE}
const Wrapper = styled.div\`
  /* ${COMPONENT_NAME} styles */
\`;

export const ${COMPONENT_NAME}: React.FC<${COMPONENT_NAME}Props> = ({ className, children }) => {
  return (
    <Wrapper className={className}>
      <h2>${COMPONENT_NAME}</h2>
      {children}
    </Wrapper>
  );
};
STYLEDTS
    else
        cat > "$COMP_FILE" <<STYLEDJS
import React from 'react';
import styled from 'styled-components';

const Wrapper = styled.div\`
  /* ${COMPONENT_NAME} styles */
\`;

export const ${COMPONENT_NAME} = ({ className, children }) => {
  return (
    <Wrapper className={className}>
      <h2>${COMPONENT_NAME}</h2>
      {children}
    </Wrapper>
  );
};
STYLEDJS
    fi
else
    if [[ "$USE_TS" == true ]]; then
        cat > "$COMP_FILE" <<COMPTS
import React from 'react';
${STYLE_IMPORT}
${PROPS_TYPE}
export const ${COMPONENT_NAME}: React.FC<${COMPONENT_NAME}Props> = ({ className, children }) => {
  return (
    <div${CLASS_ATTR}>
      <h2>${COMPONENT_NAME}</h2>
      {children}
    </div>
  );
};
COMPTS
    else
        cat > "$COMP_FILE" <<COMPJS
import React from 'react';
${STYLE_IMPORT}

export const ${COMPONENT_NAME} = ({ className, children }) => {
  return (
    <div${CLASS_ATTR}>
      <h2>${COMPONENT_NAME}</h2>
      {children}
    </div>
  );
};
COMPJS
    fi
fi

# Generate test
if [[ "$TEST_FRAMEWORK" == "vitest" ]]; then
    cat > "$TEST_FILE" <<VTEST
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ${COMPONENT_NAME} } from './${COMPONENT_NAME}';

describe('${COMPONENT_NAME}', () => {
  it('renders without crashing', () => {
    render(<${COMPONENT_NAME} />);
    expect(screen.getByText('${COMPONENT_NAME}')).toBeDefined();
  });

  it('renders children', () => {
    render(<${COMPONENT_NAME}><span>child</span></${COMPONENT_NAME}>);
    expect(screen.getByText('child')).toBeDefined();
  });
});
VTEST
else
    cat > "$TEST_FILE" <<JTEST
import { render, screen } from '@testing-library/react';
import { ${COMPONENT_NAME} } from './${COMPONENT_NAME}';

describe('${COMPONENT_NAME}', () => {
  it('renders without crashing', () => {
    render(<${COMPONENT_NAME} />);
    expect(screen.getByText('${COMPONENT_NAME}')).toBeInTheDocument();
  });

  it('renders children', () => {
    render(<${COMPONENT_NAME}><span>child</span></${COMPONENT_NAME}>);
    expect(screen.getByText('child')).toBeInTheDocument();
  });
});
JTEST
fi

# Generate barrel export
cat > "$INDEX_FILE" <<BARREL
export { ${COMPONENT_NAME} } from './${COMPONENT_NAME}';
BARREL

# --- Summary ---
echo "========================================"
echo " Component Scaffolded: ${COMPONENT_NAME}"
echo "========================================"
echo ""
echo "  Type:        $COMPONENT_TYPE"
echo "  Styling:     $STYLE_SYSTEM"
echo "  Tests:       $TEST_FRAMEWORK"
echo "  TypeScript:  $USE_TS"
echo ""
echo "  Files created:"
for f in "$OUTPUT_DIR"/*; do
    echo "    $(basename "$f")"
done
echo ""
echo "  Location: $OUTPUT_DIR"
echo ""

exit 0
