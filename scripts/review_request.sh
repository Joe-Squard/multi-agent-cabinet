#!/bin/bash
# review_request.sh - QA 大臣にレビュー依頼を送信
# 使い方:
#   review_request.sh <project> <branch> [minister_from]
#
# 実装大臣がコミット完了後に QA へ非同期レビュー依頼を送る
# pending_reviews に記録し、QA が処理完了すると approved に移動

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ $# -lt 2 ]; then
    echo "使い方: $0 <project> <branch> [minister_from]" >&2
    exit 1
fi

PROJECT="$1"
BRANCH="$2"
MINISTER_FROM="${3:-unknown}"
TIMESTAMP=$(date -Iseconds)

# レビュー待ちディレクトリ
PENDING_DIR="$BASE_DIR/runtime/pending_reviews"
REVIEWS_DIR="$BASE_DIR/runtime/reviews"
mkdir -p "$PENDING_DIR" "$REVIEWS_DIR"

# レビュー依頼ファイル作成
REVIEW_ID="${PROJECT}_$(echo "$BRANCH" | tr '/' '_')"
REVIEW_FILE="$PENDING_DIR/${REVIEW_ID}.yaml"

cat > "$REVIEW_FILE" <<EOF
---
review_id: $REVIEW_ID
project: $PROJECT
branch: $BRANCH
requested_by: $MINISTER_FROM
requested_at: $TIMESTAMP
status: pending
EOF

echo "レビュー依頼を作成: $REVIEW_FILE"

# QA 大臣に inbox 送信
if [ -f "$BASE_DIR/scripts/inbox_write.sh" ]; then
    bash "$BASE_DIR/scripts/inbox_write.sh" m_qa task \
        "コードレビュー依頼: $PROJECT ブランチ $BRANCH (from: $MINISTER_FROM)" 2>/dev/null || true
    echo "QA 大臣に通知送信済み"
fi

# QA スケーリング確認
PENDING_COUNT=$(find "$PENDING_DIR" -name "*.yaml" 2>/dev/null | wc -l)
echo "現在の pending reviews: $PENDING_COUNT"

if [ -f "$BASE_DIR/scripts/qa_scaler.sh" ]; then
    bash "$BASE_DIR/scripts/qa_scaler.sh" check 2>/dev/null || true
fi
