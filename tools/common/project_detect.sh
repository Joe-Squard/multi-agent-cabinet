#!/bin/bash
set -euo pipefail

# project_detect.sh - Detect project type, language, framework, and tooling
# Usage: project_detect.sh [project_path]
# Exit codes: 0=detected, 1=no project detected, 2=error

PROJECT_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "ERROR: Directory not found: $PROJECT_PATH" >&2
    exit 2
fi

PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

# --- Accumulators ---
LANGUAGES=()
FRAMEWORKS=()
PACKAGE_MANAGERS=()
TEST_FRAMEWORKS=()
CATEGORIES=()
PATTERNS=()

# --- Helper: check if file exists relative to project ---
has_file() { [[ -f "$PROJECT_PATH/$1" ]]; }
has_dir() { [[ -d "$PROJECT_PATH/$1" ]]; }

file_contains() {
    local file="$1" pattern="$2"
    [[ -f "$PROJECT_PATH/$file" ]] && grep -q "$pattern" "$PROJECT_PATH/$file" 2>/dev/null
}

add_unique() {
    local -n arr=$1
    local val="$2"
    for existing in "${arr[@]+"${arr[@]}"}"; do
        [[ "$existing" == "$val" ]] && return
    done
    arr+=("$val")
}

# ============================================================
# Language & Package Manager Detection
# ============================================================

# --- Node.js / JavaScript / TypeScript ---
if has_file "package.json"; then
    add_unique LANGUAGES "JavaScript"
    if has_file "tsconfig.json" || has_file "tsconfig.base.json"; then
        add_unique LANGUAGES "TypeScript"
    fi

    if has_file "pnpm-lock.yaml"; then
        add_unique PACKAGE_MANAGERS "pnpm"
    elif has_file "yarn.lock"; then
        add_unique PACKAGE_MANAGERS "yarn"
    elif has_file "bun.lockb" || has_file "bun.lock"; then
        add_unique PACKAGE_MANAGERS "bun"
    elif has_file "package-lock.json"; then
        add_unique PACKAGE_MANAGERS "npm"
    else
        add_unique PACKAGE_MANAGERS "npm (assumed)"
    fi
fi

# --- Python ---
if has_file "pyproject.toml" || has_file "setup.py" || has_file "setup.cfg" || has_file "requirements.txt"; then
    add_unique LANGUAGES "Python"
    if has_file "pyproject.toml" && file_contains "pyproject.toml" "poetry"; then
        add_unique PACKAGE_MANAGERS "poetry"
    elif has_file "pyproject.toml" && file_contains "pyproject.toml" "hatchling\|hatch"; then
        add_unique PACKAGE_MANAGERS "hatch"
    elif has_file "Pipfile"; then
        add_unique PACKAGE_MANAGERS "pipenv"
    elif has_file "pyproject.toml" && file_contains "pyproject.toml" "\[project\]"; then
        add_unique PACKAGE_MANAGERS "pip (PEP 621)"
    else
        add_unique PACKAGE_MANAGERS "pip"
    fi
    if has_file "uv.lock"; then
        add_unique PACKAGE_MANAGERS "uv"
    fi
fi

# --- Rust ---
if has_file "Cargo.toml"; then
    add_unique LANGUAGES "Rust"
    add_unique PACKAGE_MANAGERS "cargo"
fi

# --- Go ---
if has_file "go.mod"; then
    add_unique LANGUAGES "Go"
    add_unique PACKAGE_MANAGERS "go modules"
fi

# --- Java / Kotlin ---
if has_file "pom.xml"; then
    add_unique LANGUAGES "Java"
    add_unique PACKAGE_MANAGERS "maven"
elif has_file "build.gradle" || has_file "build.gradle.kts"; then
    add_unique LANGUAGES "Java/Kotlin"
    add_unique PACKAGE_MANAGERS "gradle"
fi

# --- Ruby ---
if has_file "Gemfile"; then
    add_unique LANGUAGES "Ruby"
    add_unique PACKAGE_MANAGERS "bundler"
fi

# --- PHP ---
if has_file "composer.json"; then
    add_unique LANGUAGES "PHP"
    add_unique PACKAGE_MANAGERS "composer"
fi

# --- Elixir ---
if has_file "mix.exs"; then
    add_unique LANGUAGES "Elixir"
    add_unique PACKAGE_MANAGERS "mix"
fi

# ============================================================
# Framework Detection
# ============================================================

# --- Frontend Frameworks ---
if has_file "package.json"; then
    if file_contains "package.json" '"next"'; then
        add_unique FRAMEWORKS "Next.js"
        add_unique CATEGORIES "frontend"
    fi
    if file_contains "package.json" '"react"'; then
        add_unique FRAMEWORKS "React"
        add_unique CATEGORIES "frontend"
    fi
    if file_contains "package.json" '"vue"'; then
        add_unique FRAMEWORKS "Vue"
        add_unique CATEGORIES "frontend"
    fi
    if file_contains "package.json" '"nuxt"'; then
        add_unique FRAMEWORKS "Nuxt"
        add_unique CATEGORIES "frontend"
    fi
    if file_contains "package.json" '"svelte"'; then
        add_unique FRAMEWORKS "Svelte"
        add_unique CATEGORIES "frontend"
    fi
    if file_contains "package.json" '"@angular/core"'; then
        add_unique FRAMEWORKS "Angular"
        add_unique CATEGORIES "frontend"
    fi
    if file_contains "package.json" '"astro"'; then
        add_unique FRAMEWORKS "Astro"
        add_unique CATEGORIES "frontend"
    fi
    if file_contains "package.json" '"solid-js"'; then
        add_unique FRAMEWORKS "SolidJS"
        add_unique CATEGORIES "frontend"
    fi

    # --- Backend Frameworks (Node) ---
    if file_contains "package.json" '"express"'; then
        add_unique FRAMEWORKS "Express"
        add_unique CATEGORIES "backend"
    fi
    if file_contains "package.json" '"@nestjs/core"'; then
        add_unique FRAMEWORKS "NestJS"
        add_unique CATEGORIES "backend"
    fi
    if file_contains "package.json" '"fastify"'; then
        add_unique FRAMEWORKS "Fastify"
        add_unique CATEGORIES "backend"
    fi
    if file_contains "package.json" '"hono"'; then
        add_unique FRAMEWORKS "Hono"
        add_unique CATEGORIES "backend"
    fi
    if file_contains "package.json" '"koa"'; then
        add_unique FRAMEWORKS "Koa"
        add_unique CATEGORIES "backend"
    fi

    # --- Mobile ---
    if file_contains "package.json" '"react-native"'; then
        add_unique FRAMEWORKS "React Native"
        add_unique CATEGORIES "mobile"
    fi
    if file_contains "package.json" '"expo"'; then
        add_unique FRAMEWORKS "Expo"
        add_unique CATEGORIES "mobile"
    fi
    if file_contains "package.json" '"@capacitor/core"'; then
        add_unique FRAMEWORKS "Capacitor"
        add_unique CATEGORIES "mobile"
    fi

    # --- Test Frameworks ---
    if file_contains "package.json" '"vitest"'; then
        add_unique TEST_FRAMEWORKS "Vitest"
    fi
    if file_contains "package.json" '"jest"'; then
        add_unique TEST_FRAMEWORKS "Jest"
    fi
    if file_contains "package.json" '"mocha"'; then
        add_unique TEST_FRAMEWORKS "Mocha"
    fi
    if file_contains "package.json" '"playwright"' || file_contains "package.json" '"@playwright/test"'; then
        add_unique TEST_FRAMEWORKS "Playwright"
    fi
    if file_contains "package.json" '"cypress"'; then
        add_unique TEST_FRAMEWORKS "Cypress"
    fi

    # --- CSS/Styling ---
    if file_contains "package.json" '"tailwindcss"'; then
        add_unique PATTERNS "Tailwind CSS"
    fi
    if file_contains "package.json" '"styled-components"'; then
        add_unique PATTERNS "styled-components"
    fi
    if file_contains "package.json" '"@emotion"'; then
        add_unique PATTERNS "Emotion CSS"
    fi

    # --- AI/ML (Node) ---
    if file_contains "package.json" '"@langchain"' || file_contains "package.json" '"langchain"'; then
        add_unique PATTERNS "LangChain"
        add_unique CATEGORIES "ai"
    fi
    if file_contains "package.json" '"openai"'; then
        add_unique PATTERNS "OpenAI SDK"
        add_unique CATEGORIES "ai"
    fi
fi

# --- Python Frameworks ---
if has_file "pyproject.toml" || has_file "requirements.txt"; then
    PYFILES="$PROJECT_PATH/pyproject.toml $PROJECT_PATH/requirements.txt $PROJECT_PATH/setup.py $PROJECT_PATH/setup.cfg"

    py_has() {
        local pattern="$1"
        for f in $PYFILES; do
            [[ -f "$f" ]] && grep -qi "$pattern" "$f" 2>/dev/null && return 0
        done
        return 1
    }

    if py_has "fastapi"; then
        add_unique FRAMEWORKS "FastAPI"
        add_unique CATEGORIES "backend"
    fi
    if py_has "django"; then
        add_unique FRAMEWORKS "Django"
        add_unique CATEGORIES "backend"
    fi
    if py_has "flask"; then
        add_unique FRAMEWORKS "Flask"
        add_unique CATEGORIES "backend"
    fi
    if py_has "starlette"; then
        add_unique FRAMEWORKS "Starlette"
        add_unique CATEGORIES "backend"
    fi
    if py_has "litestar"; then
        add_unique FRAMEWORKS "Litestar"
        add_unique CATEGORIES "backend"
    fi

    # Python test frameworks
    if py_has "pytest"; then
        add_unique TEST_FRAMEWORKS "pytest"
    fi

    # AI/ML
    if py_has "torch\|pytorch"; then
        add_unique PATTERNS "PyTorch"
        add_unique CATEGORIES "ai"
    fi
    if py_has "tensorflow"; then
        add_unique PATTERNS "TensorFlow"
        add_unique CATEGORIES "ai"
    fi
    if py_has "pandas"; then
        add_unique PATTERNS "pandas"
        add_unique CATEGORIES "ai"
    fi
    if py_has "scikit-learn\|sklearn"; then
        add_unique PATTERNS "scikit-learn"
        add_unique CATEGORIES "ai"
    fi
    if py_has "langchain"; then
        add_unique PATTERNS "LangChain"
        add_unique CATEGORIES "ai"
    fi
    if py_has "transformers"; then
        add_unique PATTERNS "HuggingFace Transformers"
        add_unique CATEGORIES "ai"
    fi
fi

# --- Ruby Frameworks ---
if has_file "Gemfile"; then
    if file_contains "Gemfile" "rails"; then
        add_unique FRAMEWORKS "Ruby on Rails"
        add_unique CATEGORIES "backend"
    fi
    if file_contains "Gemfile" "sinatra"; then
        add_unique FRAMEWORKS "Sinatra"
        add_unique CATEGORIES "backend"
    fi
    if file_contains "Gemfile" "rspec"; then
        add_unique TEST_FRAMEWORKS "RSpec"
    fi
fi

# --- Go Frameworks ---
if has_file "go.mod"; then
    if file_contains "go.mod" "gin-gonic"; then
        add_unique FRAMEWORKS "Gin"
        add_unique CATEGORIES "backend"
    fi
    if file_contains "go.mod" "echo"; then
        add_unique FRAMEWORKS "Echo"
        add_unique CATEGORIES "backend"
    fi
    add_unique TEST_FRAMEWORKS "go test"
fi

# --- Rust Frameworks ---
if has_file "Cargo.toml"; then
    if file_contains "Cargo.toml" "actix-web"; then
        add_unique FRAMEWORKS "Actix Web"
        add_unique CATEGORIES "backend"
    fi
    if file_contains "Cargo.toml" "axum"; then
        add_unique FRAMEWORKS "Axum"
        add_unique CATEGORIES "backend"
    fi
    add_unique TEST_FRAMEWORKS "cargo test"
fi

# ============================================================
# Infrastructure Detection
# ============================================================

if has_file "Dockerfile" || has_file "docker-compose.yml" || has_file "docker-compose.yaml" || has_file "compose.yml" || has_file "compose.yaml"; then
    add_unique PATTERNS "Docker"
    add_unique CATEGORIES "infra"
fi

if has_dir ".terraform" || ls "$PROJECT_PATH"/*.tf 1>/dev/null 2>&1; then
    add_unique PATTERNS "Terraform"
    add_unique CATEGORIES "infra"
fi

if has_file "pulumi.yaml" || has_file "Pulumi.yaml"; then
    add_unique PATTERNS "Pulumi"
    add_unique CATEGORIES "infra"
fi

if has_file ".github/workflows" || has_dir ".github/workflows"; then
    add_unique PATTERNS "GitHub Actions"
fi

if has_file ".gitlab-ci.yml"; then
    add_unique PATTERNS "GitLab CI"
fi

if has_file "Jenkinsfile"; then
    add_unique PATTERNS "Jenkins"
fi

# --- Monorepo Detection ---
if has_file "lerna.json" || has_file "nx.json" || has_file "turbo.json" || has_file "pnpm-workspace.yaml"; then
    add_unique PATTERNS "Monorepo"
fi

# ============================================================
# Output
# ============================================================

join_array() {
    local -n arr=$1
    local IFS=", "
    if [[ ${#arr[@]} -eq 0 ]]; then
        echo "(none)"
    else
        echo "${arr[*]}"
    fi
}

if [[ ${#LANGUAGES[@]} -eq 0 ]]; then
    echo "No project markers detected in: $PROJECT_PATH"
    exit 1
fi

echo "========================================"
echo " Project Detection Report"
echo "========================================"
echo ""
echo "  Path:             $PROJECT_PATH"
echo "  Languages:        $(join_array LANGUAGES)"
echo "  Frameworks:       $(join_array FRAMEWORKS)"
echo "  Package Managers: $(join_array PACKAGE_MANAGERS)"
echo "  Test Frameworks:  $(join_array TEST_FRAMEWORKS)"
echo "  Categories:       $(join_array CATEGORIES)"
echo "  Patterns:         $(join_array PATTERNS)"
echo ""
echo "========================================"
echo " Detected Files"
echo "========================================"
echo ""
for marker in package.json tsconfig.json pyproject.toml requirements.txt Cargo.toml go.mod \
              Dockerfile docker-compose.yml compose.yml Gemfile pom.xml build.gradle mix.exs \
              composer.json turbo.json nx.json; do
    if has_file "$marker"; then
        echo "  [x] $marker"
    fi
done
echo ""

exit 0
