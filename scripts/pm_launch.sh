#!/bin/bash
# pm_launch.sh - PMセッションでClaude Codeを起動
# 使い方: ./scripts/pm_launch.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PM_SESSION="pm"
MAX_WAIT=60
POLL_INTERVAL=3

# 1. PMセッション存在確認
if ! tmux has-session -t "$PM_SESSION" 2>/dev/null; then
    echo "ERROR: PMセッションが存在しません。cabinet_start.sh を先に実行してください。" >&2
    exit 1
fi

# 2. 既にClaude起動済みかチェック
PM_PANE_PID=$(tmux display-message -t "$PM_SESSION" -p '#{pane_pid}')
if pgrep -P "$PM_PANE_PID" -f "claude" >/dev/null 2>&1; then
    echo "✅ Claude Codeは既にPMセッションで起動済みです。"
    exit 0
fi

# 3. Claude Codeを起動
echo "🚀 PMセッションでClaude Codeを起動中..."
tmux send-keys -t "$PM_SESSION" "cd $BASE_DIR && claude --dangerously-skip-permissions" C-m

# 4. 初期化完了を待機
ELAPSED=0
echo "⏳ Claude Code初期化を待機中..."

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))

    # pane内容をキャプチャ
    PANE_CONTENT=$(tmux capture-pane -t "$PM_SESSION" -p -S -10 2>/dev/null || true)

    # Claude Codeの初期化完了サインを検出
    # 初期化が完了すると入力プロンプトが表示される
    if echo "$PANE_CONTENT" | grep -qE '(❯|>|claude|╭|╰|Type your|How can)'; then
        echo "✅ Claude CodeがPMセッションで起動完了しました。"

        # 首相としての初期指示を送信
        sleep 2
        INIT_MSG="あなたは内閣制度マルチエージェントシステムの首相です。instructions/prime_minister.md の指示に従って行動してください。天皇からの指示を待っています。短く確認の返答をしてください。"
        TMPFILE=$(mktemp /tmp/pm_init_XXXXXX)
        echo "$INIT_MSG" > "$TMPFILE"
        tmux load-buffer -b pm_init "$TMPFILE"
        tmux paste-buffer -b pm_init -t "$PM_SESSION"
        rm -f "$TMPFILE"
        sleep 0.5
        tmux send-keys -t "$PM_SESSION" Enter

        echo "📨 首相への初期指示を送信しました。"
        exit 0
    fi
done

echo "⚠️  タイムアウト（${MAX_WAIT}秒）。Claude Codeがまだ起動中の可能性があります。" >&2
echo "確認: tmux attach-session -t pm" >&2
exit 1
