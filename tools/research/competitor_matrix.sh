#!/bin/bash
# competitor_matrix.sh - 競合比較マトリクス生成
# 使い方: ./tools/research/competitor_matrix.sh "自社" "競合A" "競合B"
# 引数: 2〜5個の製品/サービス名
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "使い方: $0 <自社> <競合A> [競合B] [競合C] [競合D]"
    echo "例: $0 \"Cabinet\" \"Cursor\" \"Windsurf\""
    exit 2
fi

PRODUCTS=("$@")
COUNT=${#PRODUCTS[@]}

echo "# 競合分析マトリクス"
echo ""
echo "## 比較対象 (${COUNT}製品)"
echo ""

# ヘッダー生成
HEADER="| 比較項目 |"
SEP="|---|"
for p in "${PRODUCTS[@]}"; do
    HEADER="$HEADER $p |"
    SEP="$SEP---|"
done
echo "$HEADER"
echo "$SEP"

# 比較項目
ITEMS=(
    "ポジショニング"
    "ターゲットユーザー"
    "価格帯/課金モデル"
    "主要機能"
    "差別化ポイント"
    "技術スタック"
    "ユーザー数/規模"
    "強み"
    "弱み"
    "直近の動向"
)

for item in "${ITEMS[@]}"; do
    ROW="| $item |"
    for p in "${PRODUCTS[@]}"; do
        ROW="$ROW (要調査) |"
    done
    echo "$ROW"
done

cat <<'EOF'

## ポジショニングマップ

```
                 高機能
                   |
       (製品A)     |     (製品B)
                   |
  低価格 ----------+---------- 高価格
                   |
                   |     (製品C)
                   |
                 シンプル
```
（軸と位置を調査結果に基づいて調整）

## 差別化ポイント（自社の勝ち筋）
1.
2.
3.

## 参入障壁・リスク
-

## 情報源
- [1]
- [2]

---
EOF
echo "競合分析マトリクス生成完了: ${PRODUCTS[*]}"
exit 0
