#!/bin/bash
# design_system_audit.sh - デザインシステム整合性チェック
# 使い方: ./tools/design/design_system_audit.sh /path/to/project

PROJECT_DIR="${1:-.}"

echo "🎨 デザインシステム整合性チェック: $PROJECT_DIR"
echo "================================================"

# カラー定義の一覧
echo ""
echo "## カラー定義"
grep -rn --include="*.ts" --include="*.tsx" --include="*.css" --include="*.scss" \
    -E "(#[0-9a-fA-F]{3,8}|rgb\(|rgba\(|hsl\()" "$PROJECT_DIR" 2>/dev/null | head -50 || echo "  カラー定義が見つかりません"

# テーマ/トークンファイル
echo ""
echo "## テーマ・トークンファイル"
find "$PROJECT_DIR" -type f \( -name "*theme*" -o -name "*token*" -o -name "*color*" -o -name "*palette*" \) \
    2>/dev/null | head -20 || echo "  テーマファイルが見つかりません"

# コンポーネントファイル
echo ""
echo "## UIコンポーネント数"
find "$PROJECT_DIR" -type f \( -name "*.tsx" -o -name "*.jsx" \) -path "*/components/*" 2>/dev/null | wc -l

echo ""
echo "✅ チェック完了"
