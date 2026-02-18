#!/bin/bash
# tech_compare.sh - 技術スタック比較表生成
# 使い方: ./tools/architect/tech_compare.sh "React" "Vue" "Svelte"
# 引数: 2〜5個の技術名
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "使い方: $0 <tech1> <tech2> [tech3] [tech4] [tech5]"
    echo "例: $0 React Vue Svelte"
    exit 2
fi

TECHS=("$@")
COUNT=${#TECHS[@]}

echo "=============================================="
echo " 技術比較表: ${TECHS[*]}"
echo "=============================================="
echo ""

# ヘッダー生成
HEADER="| 比較項目 |"
SEPARATOR="|---|"
for t in "${TECHS[@]}"; do
    HEADER="$HEADER $t |"
    SEPARATOR="$SEPARATOR---|"
done
echo "$HEADER"
echo "$SEPARATOR"

# 比較項目
ITEMS=(
    "学習コスト"
    "エコシステム成熟度"
    "パフォーマンス"
    "TypeScript対応"
    "コミュニティ規模"
    "ドキュメント品質"
    "企業採用実績"
    "バンドルサイズ"
    "開発体験(DX)"
    "長期メンテナンス性"
)

for item in "${ITEMS[@]}"; do
    ROW="| $item |"
    for t in "${TECHS[@]}"; do
        ROW="$ROW (要評価) |"
    done
    echo "$ROW"
done

echo ""
echo "## 判定テンプレート"
echo ""
echo "| 技術 | 総合スコア | 採用判定 | 主な理由 |"
echo "|---|---|---|---|"
for t in "${TECHS[@]}"; do
    echo "| $t | /10 | 検討中 | |"
done

echo ""
echo "## 評価ガイドライン"
echo ""
echo "各項目を 1-5 で評価してください："
echo "  5: 非常に優れている"
echo "  4: 良い"
echo "  3: 普通"
echo "  2: やや劣る"
echo "  1: 不十分"
echo ""
echo "## 選定時の重要ポイント"
echo ""
echo "1. プロジェクト要件との適合性を最優先"
echo "2. チームの既存スキルセットを考慮"
echo "3. 長期メンテナンスコストを重視"
echo "4. エコシステム（ライブラリ、ツール）の充実度"
echo "5. コミュニティの活発さとサポート"
echo ""
echo "=============================================="
echo " 比較表テンプレート生成完了"
echo " ${COUNT}つの技術を比較"
echo "=============================================="
exit 0
