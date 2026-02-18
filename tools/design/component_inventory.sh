#!/bin/bash
# component_inventory.sh - UIコンポーネント棚卸し
# 使い方: ./tools/design/component_inventory.sh /path/to/project

PROJECT_DIR="${1:-.}"

echo "📦 UIコンポーネント棚卸し: $PROJECT_DIR"
echo "================================================"

echo ""
echo "## コンポーネントファイル一覧"
find "$PROJECT_DIR" -type f \( -name "*.tsx" -o -name "*.jsx" \) -path "*/components/*" \
    2>/dev/null | sort || echo "  コンポーネントが見つかりません"

echo ""
echo "## export されたコンポーネント"
grep -rn --include="*.tsx" --include="*.jsx" -E "^export (default )?(function|const|class) " \
    "$PROJECT_DIR" 2>/dev/null | head -50 || echo "  見つかりません"

echo ""
echo "## スタイル関連ファイル"
find "$PROJECT_DIR" -type f \( -name "*.css" -o -name "*.scss" -o -name "*.styled.*" -o -name "*styles*" \) \
    2>/dev/null | sort | head -30

echo ""
echo "✅ 棚卸し完了"
