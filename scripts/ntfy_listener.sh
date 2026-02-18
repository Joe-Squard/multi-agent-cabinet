#!/bin/bash
# ntfy_listener.sh - ntfyからのメッセージをストリーミング受信
# 受信したメッセージを inbox_write.sh 経由で首相に転送
# 使い方: ./scripts/ntfy_listener.sh
# 通常は cabinet_start.sh から watcher セッション内で起動される

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/../lib/yaml_reader.sh"
SETTINGS="$SCRIPT_DIR/../config/settings.yaml"

# 設定読み込み
NTFY_ENABLED=$(get_yaml_value "$SETTINGS" "ntfy.enabled")
TOPIC=$(get_yaml_value "$SETTINGS" "ntfy.topic")
SERVER=$(get_yaml_value "$SETTINGS" "ntfy.server")

if [ "$NTFY_ENABLED" != "true" ]; then
    echo "⚠️  ntfy は無効です" >&2
    exit 0
fi

if [ -z "$TOPIC" ]; then
    echo "ERROR: ntfy.topic が未設定" >&2
    exit 1
fi

SERVER="${SERVER:-https://ntfy.sh}"

echo "📱 ntfy リスナー起動: ${SERVER}/${TOPIC}"
echo "   受信メッセージを首相に転送します"

# ストリーミング受信（long-lived HTTP接続）
# since=now で起動後の新規メッセージのみ受信
curl -s --no-buffer "${SERVER}/${TOPIC}/json?since=now" 2>/dev/null | while IFS= read -r line; do
    # 空行・接続維持行をスキップ
    [ -z "$line" ] && continue

    # JSON からメッセージを抽出（python3 利用）
    if command -v python3 &> /dev/null; then
        MSG=$(echo "$line" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    if data.get('event') == 'message':
        print(data.get('message', ''))
except:
    pass
" 2>/dev/null)
    else
        # フォールバック: grep でメッセージ部分を抽出
        MSG=$(echo "$line" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi

    # メッセージがあれば首相に転送
    if [ -n "$MSG" ]; then
        echo "📨 ntfy 受信: $MSG"
        "$BASE_DIR/scripts/inbox_write.sh" pm "type: ntfy_message
source: mobile
message: |
  $MSG
"
        echo "  → 首相に転送完了"
    fi
done

echo "⚠️  ntfy リスナーが終了しました（接続切断）"
