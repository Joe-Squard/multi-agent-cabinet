#!/bin/bash
# inbox_watcher.sh - Two-Layer通信 Layer 2: ナッジ配信
# ファイル変更を検知し、send-keys で Claude Code エージェントに通知
#
# 使い方: ./scripts/inbox_watcher.sh <agent_id> <tmux_target>
# 例:
#   ./scripts/inbox_watcher.sh pm pm
#   ./scripts/inbox_watcher.sh chief chief
#   ./scripts/inbox_watcher.sh bureau_1 bureau:0.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INBOX_DIR="$BASE_DIR/queue/inbox"

# 引数チェック
if [ $# -lt 2 ]; then
    echo "使い方: $0 <agent_id> <tmux_target>" >&2
    echo "例: $0 chief chief" >&2
    echo "    $0 bureau_1 bureau:0.0" >&2
    exit 1
fi

AGENT_ID="$1"
TMUX_TARGET="$2"
INBOX_FILE="$INBOX_DIR/${AGENT_ID}.yaml"

echo "🔍 ${AGENT_ID} の inbox を監視中... (target: ${TMUX_TARGET})"

# inbox ディレクトリが存在しない場合は作成
mkdir -p "$INBOX_DIR"

# ナッジ送信関数: send-keys で Claude に通知
send_nudge() {
    local agent_id="$1"
    local tmux_target="$2"
    local inbox_file="$3"

    # ファイルが存在するか確認
    if [ ! -f "$inbox_file" ]; then
        return
    fi

    echo "📨 ${agent_id}: ナッジ送信 → ${tmux_target} ($(date '+%H:%M:%S'))"

    # ナッジメッセージ（短い指示文）
    local NUDGE_MSG="queue/inbox/${agent_id}.yaml に新しいメッセージが届きました。Read ツールでファイルを読み込み、内容に従って処理してください。処理完了後、Bash で rm queue/inbox/${agent_id}.yaml を実行してファイルを削除してください。"

    # load-buffer + paste-buffer でエスケープ問題を回避
    local TMPFILE
    TMPFILE=$(mktemp /tmp/nudge_XXXXXX)
    echo "$NUDGE_MSG" > "$TMPFILE"
    tmux load-buffer -b "nudge_${agent_id}" "$TMPFILE" 2>/dev/null || true
    tmux paste-buffer -b "nudge_${agent_id}" -t "$tmux_target" 2>/dev/null || true
    rm -f "$TMPFILE"

    sleep 0.5
    tmux send-keys -t "$tmux_target" Enter 2>/dev/null || true

    echo "✅ ${agent_id}: ナッジ送信完了"
}

# inotifywait が利用可能かチェック
if command -v inotifywait &> /dev/null; then
    # ========================================
    # イベント駆動モード (inotifywait)
    # ========================================
    echo "⚡ イベント駆動モード (inotifywait)"

    while true; do
        # ファイル作成・変更を監視（タイムアウト30秒）
        inotifywait -e create,modify -t 30 "$INBOX_DIR" 2>/dev/null | \
        while read -r directory event filename; do
            if [ "$filename" = "${AGENT_ID}.yaml" ]; then
                # 書き込み完了を待機
                sleep 0.3

                # ナッジ送信
                send_nudge "$AGENT_ID" "$TMUX_TARGET" "$INBOX_FILE"
            fi
        done

        # タイムアウト時は何もせず次のループへ（CPU使用率を低く保つ）
    done
else
    # ========================================
    # ポーリング フォールバックモード
    # ========================================
    echo "⚠️  inotifywait 未インストール: ポーリングモード（5秒間隔）"
    echo "   推奨: sudo apt-get install inotify-tools"

    LAST_MTIME=""

    while true; do
        if [ -f "$INBOX_FILE" ]; then
            # ファイルの更新時刻を取得
            CURRENT_MTIME=$(stat -c %Y "$INBOX_FILE" 2>/dev/null || echo "")

            # 新しいファイルまたは更新されたファイルの場合のみナッジ
            if [ -n "$CURRENT_MTIME" ] && [ "$CURRENT_MTIME" != "$LAST_MTIME" ]; then
                LAST_MTIME="$CURRENT_MTIME"
                send_nudge "$AGENT_ID" "$TMUX_TARGET" "$INBOX_FILE"
            fi
        else
            LAST_MTIME=""
        fi
        sleep 5
    done
fi
