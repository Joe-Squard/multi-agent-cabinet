#!/bin/bash
# ntfy.sh - ntfy経由でモバイル通知を送信
# 使い方: ./scripts/ntfy.sh "メッセージ" [タグ]
# 例:
#   ./scripts/ntfy.sh "タスク完了: React調査"
#   ./scripts/ntfy.sh "緊急: エラー発生" "warning"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/yaml_reader.sh"
SETTINGS="$SCRIPT_DIR/../config/settings.yaml"

if [ $# -lt 1 ]; then
    echo "使い方: $0 <メッセージ> [タグ]" >&2
    exit 1
fi

MESSAGE="$1"
TAG="${2:-cabinet}"

# 設定読み込み
NTFY_ENABLED=$(get_yaml_value "$SETTINGS" "ntfy.enabled")
TOPIC=$(get_yaml_value "$SETTINGS" "ntfy.topic")
SERVER=$(get_yaml_value "$SETTINGS" "ntfy.server")

if [ "$NTFY_ENABLED" != "true" ]; then
    echo "⚠️  ntfy は無効です（config/settings.yaml で ntfy.enabled: true に設定）" >&2
    exit 0
fi

if [ -z "$TOPIC" ]; then
    echo "ERROR: ntfy.topic が settings.yaml に設定されていません" >&2
    exit 1
fi

SERVER="${SERVER:-https://ntfy.sh}"

# 通知送信
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Tags: $TAG" \
    -H "Title: 🏛️ Cabinet System" \
    -d "$MESSAGE" \
    "${SERVER}/${TOPIC}")

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    echo "📱 ntfy 通知送信完了: $MESSAGE"
else
    echo "⚠️  ntfy 送信失敗 (HTTP $HTTP_CODE)" >&2
    exit 1
fi
