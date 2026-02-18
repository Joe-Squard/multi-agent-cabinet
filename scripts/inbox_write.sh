#!/bin/bash
# inbox_write.sh - メッセージ送信スクリプト
# 使い方: ./scripts/inbox_write.sh <agent_id> <message>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INBOX_DIR="$BASE_DIR/queue/inbox"

# 引数チェック
if [ $# -lt 2 ]; then
    echo "使い方: $0 <agent_id> <message>" >&2
    echo "例: $0 chief 'task_id: task_001\ntitle: テストタスク'" >&2
    exit 1
fi

AGENT_ID="$1"
MESSAGE="$2"
INBOX_FILE="$INBOX_DIR/${AGENT_ID}.yaml"

# inbox ディレクトリが存在しない場合は作成
mkdir -p "$INBOX_DIR"

# flock で排他ロック（競合回避）
{
    flock -x 200

    # タイムスタンプ追加
    TIMESTAMP=$(date -Iseconds)

    # YAML フォーマットでメッセージを書き込み
    cat > "$INBOX_FILE" <<EOF
---
timestamp: $TIMESTAMP
from: $(whoami)
message: |
$(echo "$MESSAGE" | sed 's/^/  /')
EOF

    echo "✅ メッセージを ${AGENT_ID} に送信しました"
    echo "📁 ${INBOX_FILE}"

} 200>"$INBOX_FILE.lock"

# ロックファイル削除
rm -f "$INBOX_FILE.lock"
