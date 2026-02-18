#!/bin/bash
# schema_visualize.sh - DB スキーマからER図テキスト生成
# 使い方: ./tools/architect/schema_visualize.sh [/path/to/project]
set -euo pipefail

PROJECT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

echo "=============================================="
echo " DB スキーマ可視化: $PROJECT"
echo "=============================================="
echo ""

FOUND=0

# Prisma schema
PRISMA_FILES=$(find "$PROJECT" -name "schema.prisma" -not -path "*/node_modules/*" 2>/dev/null || true)
if [ -n "$PRISMA_FILES" ]; then
    FOUND=1
    echo "## Prisma スキーマ検出"
    echo ""
    while IFS= read -r schema; do
        echo "### ファイル: $schema"
        echo ""

        # モデル抽出
        echo "#### モデル一覧"
        echo ""
        MODELS=$(grep -E "^model " "$schema" | awk '{print $2}' || true)
        if [ -n "$MODELS" ]; then
            echo "| モデル | フィールド数 | リレーション |"
            echo "|---|---|---|"
            while IFS= read -r model; do
                FIELD_COUNT=$(sed -n "/^model $model/,/^}/p" "$schema" | grep -cE '^\s+\w' || echo 0)
                RELATIONS=$(sed -n "/^model $model/,/^}/p" "$schema" | grep -oE '@relation\([^)]*\)' | wc -l || echo 0)
                echo "| $model | $FIELD_COUNT | $RELATIONS |"
            done <<< "$MODELS"
            echo ""

            # ER 図テキスト
            echo "#### リレーション図"
            echo '```'
            while IFS= read -r model; do
                BLOCK=$(sed -n "/^model $model/,/^}/p" "$schema")
                REL_MODELS=$(echo "$BLOCK" | grep -oE '^\s+\w+\s+\w+\[\]' | awk '{print $2}' | sed 's/\[\]//' || true)
                REL_SINGLE=$(echo "$BLOCK" | grep -oE '^\s+\w+\s+\w+\?' | awk '{print $2}' | sed 's/\?//' || true)
                if [ -n "$REL_MODELS" ]; then
                    while IFS= read -r rel; do
                        echo "$model ||--o{ $rel : \"has many\""
                    done <<< "$REL_MODELS"
                fi
                if [ -n "$REL_SINGLE" ]; then
                    while IFS= read -r rel; do
                        # Filter out primitive types
                        case "$rel" in
                            String|Int|Float|Boolean|DateTime|Json|Bytes|BigInt|Decimal) ;;
                            *) echo "$model }o--|| $rel : \"belongs to\"" ;;
                        esac
                    done <<< "$REL_SINGLE"
                fi
            done <<< "$MODELS"
            echo '```'
        fi
        echo ""
    done <<< "$PRISMA_FILES"
fi

# SQLAlchemy models
SA_FILES=$(grep -rlE "class \w+\(.*Base\)" "$PROJECT" --include="*.py" 2>/dev/null | head -20 || true)
if [ -n "$SA_FILES" ]; then
    FOUND=1
    echo "## SQLAlchemy モデル検出"
    echo ""
    echo "| ファイル | モデル名 |"
    echo "|---|---|"
    while IFS= read -r f; do
        MODELS=$(grep -oE "class (\w+)\(.*Base" "$f" | sed 's/class //;s/(.*Base//' || true)
        while IFS= read -r m; do
            [ -n "$m" ] && echo "| $(basename "$f") | $m |"
        done <<< "$MODELS"
    done <<< "$SA_FILES"
    echo ""
fi

# TypeORM entities
TYPEORM_FILES=$(find "$PROJECT" -name "*.entity.ts" -not -path "*/node_modules/*" 2>/dev/null || true)
if [ -n "$TYPEORM_FILES" ]; then
    FOUND=1
    echo "## TypeORM エンティティ検出"
    echo ""
    echo "| ファイル | エンティティ名 |"
    echo "|---|---|"
    while IFS= read -r f; do
        ENTITIES=$(grep -oE "class (\w+)" "$f" | awk '{print $2}' || true)
        while IFS= read -r e; do
            [ -n "$e" ] && echo "| $(basename "$f") | $e |"
        done <<< "$ENTITIES"
    done <<< "$TYPEORM_FILES"
    echo ""
fi

# Drizzle schema
DRIZZLE_FILES=$(grep -rlE "(pgTable|mysqlTable|sqliteTable)" "$PROJECT" --include="*.ts" 2>/dev/null | head -20 || true)
if [ -n "$DRIZZLE_FILES" ]; then
    FOUND=1
    echo "## Drizzle スキーマ検出"
    echo ""
    echo "| ファイル | テーブル名 |"
    echo "|---|---|"
    while IFS= read -r f; do
        TABLES=$(grep -oE "(pgTable|mysqlTable|sqliteTable)\(['\"](\w+)" "$f" | sed "s/.*['\"]//;s/['\"].*//" || true)
        while IFS= read -r t; do
            [ -n "$t" ] && echo "| $(basename "$f") | $t |"
        done <<< "$TABLES"
    done <<< "$DRIZZLE_FILES"
    echo ""
fi

# SQL migration files
MIGRATION_COUNT=$(find "$PROJECT" -path "*/migrations/*" -name "*.sql" -not -path "*/node_modules/*" 2>/dev/null | wc -l || echo 0)
if [ "$MIGRATION_COUNT" -gt 0 ]; then
    FOUND=1
    echo "## マイグレーションファイル: ${MIGRATION_COUNT}件"
    echo ""
    find "$PROJECT" -path "*/migrations/*" -name "*.sql" -not -path "*/node_modules/*" 2>/dev/null | sort | tail -5 | while IFS= read -r f; do
        echo "- $(basename "$f")"
    done
    echo ""
fi

if [ "$FOUND" -eq 0 ]; then
    echo "⚠️  DB スキーマファイルが見つかりませんでした"
    echo ""
    echo "対応形式: Prisma, SQLAlchemy, TypeORM, Drizzle"
    exit 1
fi

echo "=============================================="
echo " スキーマ可視化完了"
echo "=============================================="
exit 0
