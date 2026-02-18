#!/bin/bash
# pm_interact.sh - PMにメッセージを送信し応答をキャプチャ
# 使い方: ./scripts/pm_interact.sh <message>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PM_SESSION="pm"
POLL_INTERVAL=3
STABLE_THRESHOLD=2
TIMEOUT=120

# --- 引数チェック ---
if [ $# -lt 1 ]; then
    echo "使い方: $0 <message>" >&2
    exit 1
fi

MESSAGE="$1"

# --- PMセッション確認 ---
if ! tmux has-session -t "$PM_SESSION" 2>/dev/null; then
    echo "ERROR: PMセッションが見つかりません。/cabinet-start でシステムを起動してください。" >&2
    exit 1
fi

# --- Claude起動確認 ---
PM_PANE_PID=$(tmux display-message -t "$PM_SESSION" -p '#{pane_pid}')
if ! pgrep -P "$PM_PANE_PID" -f "claude" >/dev/null 2>&1; then
    echo "ERROR: Claude CodeがPMセッションで起動していません。/cabinet-start でシステムを起動してください。" >&2
    exit 1
fi

# --- 送信前の状態を記録 ---
BEFORE_CONTENT=$(tmux capture-pane -t "$PM_SESSION" -p -S -500 2>/dev/null || true)
BEFORE_LINES=$(echo "$BEFORE_CONTENT" | wc -l)

# --- メッセージ送信 ---
# load-buffer + paste-buffer でエスケープ問題を回避
TMPFILE=$(mktemp /tmp/pm_msg_XXXXXX)
echo "$MESSAGE" > "$TMPFILE"
tmux load-buffer -b pm_msg "$TMPFILE"
tmux paste-buffer -b pm_msg -t "$PM_SESSION"
rm -f "$TMPFILE"

sleep 0.5
tmux send-keys -t "$PM_SESSION" Enter

# --- 応答完了をポーリング ---
ELAPSED=0
STABLE_COUNT=0
PREV_CAPTURE=""

# Claude処理開始を待機
sleep 3

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))

    CURRENT_CAPTURE=$(tmux capture-pane -t "$PM_SESSION" -p -S -500 2>/dev/null || true)

    if [ "$CURRENT_CAPTURE" = "$PREV_CAPTURE" ] && [ -n "$CURRENT_CAPTURE" ]; then
        STABLE_COUNT=$((STABLE_COUNT + 1))
    else
        STABLE_COUNT=0
    fi

    PREV_CAPTURE="$CURRENT_CAPTURE"

    if [ "$STABLE_COUNT" -ge "$STABLE_THRESHOLD" ]; then
        break
    fi
done

if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "⚠️  応答がタイムアウトしました（${TIMEOUT}秒）。/pm-read で確認してください。" >&2
fi

# --- 新規出力を抽出 ---
FINAL_CONTENT=$(tmux capture-pane -t "$PM_SESSION" -p -S -500 2>/dev/null || true)
echo "$FINAL_CONTENT" | tail -n +$((BEFORE_LINES + 1))
