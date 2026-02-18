#!/bin/bash
# responsive_breakpoints.sh - レスポンシブ設定一覧
# 使い方: ./tools/design/responsive_breakpoints.sh /path/to/project

PROJECT_DIR="${1:-.}"

echo "📱 レスポンシブ設定一覧: $PROJECT_DIR"
echo "================================================"

echo ""
echo "## メディアクエリ"
grep -rn --include="*.css" --include="*.scss" --include="*.ts" --include="*.tsx" \
    -E "@media|min-width|max-width|breakpoint" "$PROJECT_DIR" 2>/dev/null | head -30 || echo "  メディアクエリが見つかりません"

echo ""
echo "## Tailwind ブレークポイント設定"
grep -rn --include="*.js" --include="*.ts" --include="*.json" \
    -E "(sm|md|lg|xl|2xl).*\d+px" "$PROJECT_DIR" 2>/dev/null | head -10 || echo "  Tailwind 設定が見つかりません"

echo ""
echo "## Platform 分岐 (React Native)"
grep -rn --include="*.tsx" --include="*.ts" \
    -E "Platform\.(OS|select)" "$PROJECT_DIR" 2>/dev/null | head -20 || echo "  Platform 分岐が見つかりません"

echo ""
echo "✅ チェック完了"
