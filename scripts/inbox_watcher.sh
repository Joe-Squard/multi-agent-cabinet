#!/bin/bash
# inbox_watcher.sh - Two-Layer通信 Layer 2: ナッジ配信 v2.0 (キューベース)
# ディレクトリベースの inbox キューを監視し、send-keys でエージェントに通知
#
# 使い方: ./scripts/inbox_watcher.sh <agent_id> <tmux_target>
# 例:
#   ./scripts/inbox_watcher.sh pm pm
#   ./scripts/inbox_watcher.sh chief chief
#   ./scripts/inbox_watcher.sh minister_fe m_fe:0.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INBOX_DIR="$BASE_DIR/queue/inbox"

# 引数チェック
if [ $# -lt 2 ]; then
    echo "使い方: $0 <agent_id> <tmux_target>" >&2
    echo "例: $0 chief chief" >&2
    echo "    $0 minister_fe m_fe:0.0" >&2
    exit 1
fi

AGENT_ID="$1"
TMUX_TARGET="$2"
AGENT_INBOX="$INBOX_DIR/${AGENT_ID}"

echo "🔍 ${AGENT_ID} の inbox を監視中... (target: ${TMUX_TARGET})"

# inbox ディレクトリを作成
mkdir -p "$AGENT_INBOX"

# ナッジ送信関数
send_nudge() {
    local agent_id="$1"
    local tmux_target="$2"
    local inbox_dir="$3"

    # ディレクトリ内のファイル数チェック
    local file_count
    file_count=$(find "$inbox_dir" -maxdepth 1 -name "*.yaml" -type f 2>/dev/null | wc -l)
    if [ "$file_count" -eq 0 ]; then
        return
    fi

    echo "📨 ${agent_id}: ナッジ送信 → ${tmux_target} (${file_count}件, $(date '+%H:%M:%S'))"

    # ナッジメッセージ
    local NUDGE_MSG="queue/inbox/${agent_id}/ に${file_count}件の新しいメッセージがあります。Bash で ls queue/inbox/${agent_id}/ を実行してファイル一覧を確認し、各 .yaml ファイルを Read ツールで読み込んで内容に従って処理してください。処理完了後、各ファイルを Bash で rm して削除してください。"

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

# 後方互換: 旧形式の単一ファイルもチェック
check_legacy_inbox() {
    local agent_id="$1"
    local tmux_target="$2"
    local legacy_file="$INBOX_DIR/${agent_id}.yaml"

    if [ -f "$legacy_file" ]; then
        echo "📨 ${agent_id}: 旧形式 inbox 検出 → ナッジ送信"

        local NUDGE_MSG="queue/inbox/${agent_id}.yaml に新しいメッセージが届きました。Read ツールでファイルを読み込み、内容に従って処理してください。処理完了後、Bash で rm queue/inbox/${agent_id}.yaml を実行してファイルを削除してください。"

        local TMPFILE
        TMPFILE=$(mktemp /tmp/nudge_XXXXXX)
        echo "$NUDGE_MSG" > "$TMPFILE"
        tmux load-buffer -b "nudge_${agent_id}" "$TMPFILE" 2>/dev/null || true
        tmux paste-buffer -b "nudge_${agent_id}" -t "$tmux_target" 2>/dev/null || true
        rm -f "$TMPFILE"

        sleep 0.5
        tmux send-keys -t "$tmux_target" Enter 2>/dev/null || true
    fi
}

# inotifywait が利用可能かチェック
if command -v inotifywait &> /dev/null; then
    # ========================================
    # イベント駆動モード (inotifywait)
    # ========================================
    echo "⚡ イベント駆動モード (inotifywait)"

    while true; do
        # ディレクトリ内の新規ファイル作成を監視（タイムアウト30秒）
        inotifywait -e create -t 30 "$AGENT_INBOX" 2>/dev/null | \
        while read -r directory event filename; do
            if [[ "$filename" == *.yaml ]]; then
                # 書き込み完了を待機
                sleep 0.3

                # ナッジ送信
                send_nudge "$AGENT_ID" "$TMUX_TARGET" "$AGENT_INBOX"
            fi
        done

        # タイムアウト時に旧形式もチェック
        check_legacy_inbox "$AGENT_ID" "$TMUX_TARGET"
    done
else
    # ========================================
    # ポーリング フォールバックモード
    # ========================================
    echo "⚠️  inotifywait 未インストール: ポーリングモード（5秒間隔）"
    echo "   推奨: sudo apt-get install inotify-tools"

    LAST_COUNT=0

    while true; do
        # ディレクトリ内のファイル数をチェック
        CURRENT_COUNT=$(find "$AGENT_INBOX" -maxdepth 1 -name "*.yaml" -type f 2>/dev/null | wc -l)

        if [ "$CURRENT_COUNT" -gt 0 ] && [ "$CURRENT_COUNT" -ne "$LAST_COUNT" ]; then
            LAST_COUNT="$CURRENT_COUNT"
            send_nudge "$AGENT_ID" "$TMUX_TARGET" "$AGENT_INBOX"
        elif [ "$CURRENT_COUNT" -eq 0 ]; then
            LAST_COUNT=0
        fi

        # 旧形式もチェック
        check_legacy_inbox "$AGENT_ID" "$TMUX_TARGET"

        sleep 5
    done
fi
