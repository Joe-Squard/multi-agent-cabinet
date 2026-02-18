#!/bin/bash
# release_readiness.sh - リリース準備状況チェック
# 使い方: ./tools/uat/release_readiness.sh /path/to/project

PROJECT_DIR="${1:-.}"

echo "🚀 リリース準備状況チェック: $PROJECT_DIR"
echo "================================================"

echo ""
echo "## Git 状態"
cd "$PROJECT_DIR" 2>/dev/null && {
    echo "  ブランチ: $(git branch --show-current 2>/dev/null || echo 'N/A')"
    echo "  未コミット変更: $(git status --porcelain 2>/dev/null | wc -l) 件"
    echo "  最新コミット: $(git log --oneline -1 2>/dev/null || echo 'N/A')"
} || echo "  Git リポジトリではありません"

echo ""
echo "## テスト状態"
if [ -f "$PROJECT_DIR/package.json" ]; then
    echo "  package.json: あり"
    grep -q '"test"' "$PROJECT_DIR/package.json" && echo "  test スクリプト: あり" || echo "  test スクリプト: なし"
fi

echo ""
echo "## 未解決 TODO/FIXME"
TODO_COUNT=$(grep -rn --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
    -E "(TODO|FIXME|HACK|XXX)" "$PROJECT_DIR" 2>/dev/null | wc -l)
echo "  件数: $TODO_COUNT"

echo ""
echo "## チェックリスト"
echo "  - [ ] 全 UAT テストケース PASS"
echo "  - [ ] 重大バグなし"
echo "  - [ ] パフォーマンス確認済み"
echo "  - [ ] セキュリティ確認済み"
echo "  - [ ] ドキュメント更新済み"
echo "  - [ ] ステークホルダー承認済み"
echo ""
echo "✅ チェック完了"
