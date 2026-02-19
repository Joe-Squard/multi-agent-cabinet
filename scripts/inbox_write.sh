#!/bin/bash
# inbox_write.sh - メッセージ送信スクリプト v2.0 (キューベース)
# 使い方:
#   ./scripts/inbox_write.sh <agent_id> <message>
#   ./scripts/inbox_write.sh <agent_id> <message> --from <from_id> --type <type>
#
# メッセージタイプ:
#   task          タスク割当（デフォルト）
#   report        完了報告
#   clarification 大臣間質問（自動CC PM）
#   coordination  大臣間同期（自動CC PM）
#   routing_error ドメイン外通知
#   skill_proposal スキル提案

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INBOX_DIR="$BASE_DIR/queue/inbox"

# 引数チェック
if [ $# -lt 2 ]; then
    echo "使い方: $0 <agent_id> <message> [--from FROM] [--type TYPE]" >&2
    echo "例: $0 chief 'task_id: task_001'" >&2
    echo "    $0 minister_be 'question' --from minister_fe --type clarification" >&2
    exit 1
fi

AGENT_ID="$1"
MESSAGE="$2"
shift 2

# オプション解析
FROM_ID=""
MSG_TYPE="task"

while [ $# -gt 0 ]; do
    case "$1" in
        --from)  FROM_ID="$2"; shift 2 ;;
        --type)  MSG_TYPE="$2"; shift 2 ;;
        *)       shift ;;
    esac
done

# from が未指定の場合は空文字列（エージェントが自分で埋める）
[ -z "$FROM_ID" ] && FROM_ID="unknown"

TIMESTAMP=$(date -Iseconds)
TIMESTAMP_FILE=$(date +%Y%m%d_%H%M%S_%N)

# ディレクトリベース inbox
AGENT_INBOX="$INBOX_DIR/${AGENT_ID}"
mkdir -p "$AGENT_INBOX"

MSG_FILE="${AGENT_INBOX}/${TIMESTAMP_FILE}_${FROM_ID}.yaml"

cat > "$MSG_FILE" <<EOF
---
timestamp: $TIMESTAMP
from: $FROM_ID
type: $MSG_TYPE
message: |
$(echo "$MESSAGE" | sed 's/^/  /')
EOF

echo "✅ メッセージを ${AGENT_ID} に送信しました (type: $MSG_TYPE)"
echo "📁 ${MSG_FILE}"

# 大臣間通信は自動で PM に CC
if [[ "$MSG_TYPE" == "clarification" || "$MSG_TYPE" == "coordination" ]]; then
    if [[ "$AGENT_ID" != "pm" && "$FROM_ID" != "pm" ]]; then
        PM_INBOX="$INBOX_DIR/pm"
        mkdir -p "$PM_INBOX"
        CC_FILE="${PM_INBOX}/${TIMESTAMP_FILE}_${FROM_ID}_cc.yaml"
        cat > "$CC_FILE" <<EOF
---
timestamp: $TIMESTAMP
from: $FROM_ID
type: cc_${MSG_TYPE}
original_to: $AGENT_ID
message: |
$(echo "$MESSAGE" | sed 's/^/  /')
EOF
        echo "📋 CC → pm"
    fi
fi
