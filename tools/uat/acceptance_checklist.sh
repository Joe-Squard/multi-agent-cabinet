#!/bin/bash
# acceptance_checklist.sh - 受入チェックリスト生成
# 使い方: ./tools/uat/acceptance_checklist.sh /path/to/requirements.md

REQ_FILE="${1:-}"
OUTPUT_FILE="queue/reports/acceptance_checklist_$(date +%Y%m%d_%H%M%S).md"

cat > "$OUTPUT_FILE" <<EOF
# 受入チェックリスト

作成日: $(date -Iseconds)
要件ファイル: ${REQ_FILE:-（未指定）}

## 機能要件チェック

- [ ] 主要機能が仕様通り動作する
- [ ] 代替フローが正しく処理される
- [ ] エラーメッセージが適切に表示される
- [ ] 入力バリデーションが機能する

## 非機能要件チェック

- [ ] ページ表示速度が許容範囲内
- [ ] レスポンシブ表示が正しい
- [ ] アクセシビリティ基準を満たす
- [ ] ブラウザ互換性を確認

## ユーザビリティチェック

- [ ] 操作が直感的
- [ ] フィードバックが適切（ローディング、成功、エラー）
- [ ] 文言・ラベルが分かりやすい
- [ ] 画面遷移が自然

## データ整合性チェック

- [ ] データが正しく保存される
- [ ] データが正しく表示される
- [ ] 既存データへの影響がない

## 総合判定

**判定**: ACCEPT / REJECT
**コメント**:
EOF

echo "✅ 受入チェックリストを生成しました: $OUTPUT_FILE"
