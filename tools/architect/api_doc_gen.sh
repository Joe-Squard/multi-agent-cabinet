#!/bin/bash
# api_doc_gen.sh - ソースコードから API 仕様書を自動生成
# 使い方: ./tools/architect/api_doc_gen.sh [/path/to/project]
set -euo pipefail

PROJECT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

echo "=============================================="
echo " API 仕様書生成: $PROJECT"
echo "=============================================="
echo ""

FOUND=0
ENDPOINT_COUNT=0

# Express routes
EXPRESS_FILES=$(grep -rlE "(app|router)\.(get|post|put|patch|delete)\(" "$PROJECT" --include="*.ts" --include="*.js" 2>/dev/null | grep -v node_modules || true)
if [ -n "$EXPRESS_FILES" ]; then
    FOUND=1
    echo "## Express API エンドポイント"
    echo ""
    echo "| メソッド | パス | ファイル | 行 |"
    echo "|---|---|---|---|"
    while IFS= read -r f; do
        REL=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || basename "$f")
        grep -nE "(app|router)\.(get|post|put|patch|delete)\(" "$f" 2>/dev/null | while IFS=: read -r line content; do
            METHOD=$(echo "$content" | grep -oE '\.(get|post|put|patch|delete)\(' | tr -d '.(' | tr '[:lower:]' '[:upper:]')
            PATH_VAL=$(echo "$content" | grep -oE "['\"][^'\"]*['\"]" | head -1 | tr -d "'" | tr -d '"')
            [ -n "$METHOD" ] && [ -n "$PATH_VAL" ] && {
                echo "| $METHOD | $PATH_VAL | $REL | L$line |"
                ENDPOINT_COUNT=$((ENDPOINT_COUNT + 1))
            }
        done
    done <<< "$EXPRESS_FILES"
    echo ""
fi

# FastAPI routes
FASTAPI_FILES=$(grep -rlE "@(app|router)\.(get|post|put|patch|delete)\(" "$PROJECT" --include="*.py" 2>/dev/null | grep -v __pycache__ || true)
if [ -n "$FASTAPI_FILES" ]; then
    FOUND=1
    echo "## FastAPI エンドポイント"
    echo ""
    echo "| メソッド | パス | ファイル | 行 |"
    echo "|---|---|---|---|"
    while IFS= read -r f; do
        REL=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || basename "$f")
        # Extract router prefix if exists
        PREFIX=$(grep -oE "prefix=['\"][^'\"]*['\"]" "$f" | head -1 | grep -oE "['\"][^'\"]*['\"]" | tr -d "'" | tr -d '"' || echo "")
        grep -nE "@(app|router)\.(get|post|put|patch|delete)\(" "$f" 2>/dev/null | while IFS=: read -r line content; do
            METHOD=$(echo "$content" | grep -oE '\.(get|post|put|patch|delete)\(' | tr -d '.(' | tr '[:lower:]' '[:upper:]')
            PATH_VAL=$(echo "$content" | grep -oE "['\"][^'\"]*['\"]" | head -1 | tr -d "'" | tr -d '"')
            FULL_PATH="${PREFIX}${PATH_VAL}"
            [ -n "$METHOD" ] && [ -n "$PATH_VAL" ] && {
                echo "| $METHOD | $FULL_PATH | $REL | L$line |"
                ENDPOINT_COUNT=$((ENDPOINT_COUNT + 1))
            }
        done
    done <<< "$FASTAPI_FILES"
    echo ""
fi

# NestJS controllers
NEST_FILES=$(find "$PROJECT" -name "*.controller.ts" -not -path "*/node_modules/*" 2>/dev/null || true)
if [ -n "$NEST_FILES" ]; then
    FOUND=1
    echo "## NestJS コントローラー"
    echo ""
    echo "| メソッド | パス | コントローラー | 行 |"
    echo "|---|---|---|---|"
    while IFS= read -r f; do
        CTRL_NAME=$(basename "$f" .controller.ts)
        PREFIX=$(grep -oE "@Controller\(['\"][^'\"]*" "$f" | grep -oE "['\"][^'\"]*" | tr -d "'" | tr -d '"' || echo "/$CTRL_NAME")
        grep -nE "@(Get|Post|Put|Patch|Delete)\(" "$f" 2>/dev/null | while IFS=: read -r line content; do
            METHOD=$(echo "$content" | grep -oE '@(Get|Post|Put|Patch|Delete)' | tr -d '@' | tr '[:lower:]' '[:upper:]')
            SUB_PATH=$(echo "$content" | grep -oE "['\"][^'\"]*['\"]" | head -1 | tr -d "'" | tr -d '"' || echo "")
            FULL_PATH="${PREFIX}${SUB_PATH:+/$SUB_PATH}"
            [ -n "$METHOD" ] && {
                echo "| $METHOD | $FULL_PATH | $CTRL_NAME | L$line |"
                ENDPOINT_COUNT=$((ENDPOINT_COUNT + 1))
            }
        done
    done <<< "$NEST_FILES"
    echo ""
fi

# Next.js App Router API routes
NEXTAPI_FILES=$(find "$PROJECT" -path "*/app/api/*/route.ts" -o -path "*/app/api/*/route.js" 2>/dev/null | grep -v node_modules || true)
if [ -n "$NEXTAPI_FILES" ]; then
    FOUND=1
    echo "## Next.js App Router API"
    echo ""
    echo "| メソッド | パス | ファイル |"
    echo "|---|---|---|"
    while IFS= read -r f; do
        # Extract path from file location
        API_PATH=$(echo "$f" | sed -E 's|.*/app(/api/.*)/route\.[tj]s|\1|')
        METHODS=$(grep -oE "export (async )?function (GET|POST|PUT|PATCH|DELETE)" "$f" | grep -oE '(GET|POST|PUT|PATCH|DELETE)' || true)
        REL=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || basename "$f")
        while IFS= read -r method; do
            [ -n "$method" ] && {
                echo "| $method | $API_PATH | $REL |"
                ENDPOINT_COUNT=$((ENDPOINT_COUNT + 1))
            }
        done <<< "$METHODS"
    done <<< "$NEXTAPI_FILES"
    echo ""
fi

if [ "$FOUND" -eq 0 ]; then
    echo "⚠️  API エンドポイントが見つかりませんでした"
    echo ""
    echo "対応フレームワーク: Express, FastAPI, NestJS, Next.js App Router"
    exit 1
fi

echo "=============================================="
echo " API 仕様書生成完了"
echo " 検出エンドポイント数: $ENDPOINT_COUNT"
echo "=============================================="
exit 0
