#!/bin/bash
# conversation-logger.sh — 監査証跡（非同期）
# イベント: SessionEnd (async)
# トランスクリプト JSONL を memory/sessions/ にコピー
# LLM 呼び出しなし、純粋シェルスクリプト

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CABINET_BASE="$(cd "$HOOK_DIR/.." && pwd)"

# エージェント情報
AGENT_ID="${CLAUDE_AGENT_ID:-unknown}"
SESSION_NAME="${CLAUDE_SESSION_NAME:-""}"
TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "unknown")
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H%M%S)
SESSION_SHORT="${DATE}_${TIME}"

# 保存先
SAVE_DIR="$CABINET_BASE/memory/sessions/${AGENT_ID}"
mkdir -p "$SAVE_DIR"

# Claude のトランスクリプト JSONL を検索してコピー
# Claude Code は ~/.claude/projects/<project_hash>/<session_id>.jsonl にトランスクリプトを保存
CLAUDE_DIR="$HOME/.claude"
if [ -d "$CLAUDE_DIR" ]; then
    # 最新のセッション JSONL を検索（最終更新が1分以内のもの）
    LATEST_JSONL=$(find "$CLAUDE_DIR" -name "*.jsonl" -mmin -1 -type f 2>/dev/null | head -1)
    if [ -n "$LATEST_JSONL" ]; then
        # メタデータ付きでコピー
        DEST="$SAVE_DIR/${SESSION_SHORT}.jsonl"
        cp "$LATEST_JSONL" "$DEST" 2>/dev/null || true

        # メタデータファイル
        cat > "$SAVE_DIR/${SESSION_SHORT}.meta" <<METAEOF
agent_id: $AGENT_ID
tmux_session: $TMUX_SESSION
session_name: $SESSION_NAME
date: $DATE
time: $TIME
source: $LATEST_JSONL
METAEOF

        # Markdown 要約生成（jq があれば）
        if command -v jq &>/dev/null && [ -f "$DEST" ]; then
            MD_FILE="$SAVE_DIR/${SESSION_SHORT}.md"
            {
                echo "# Session: $AGENT_ID ($DATE $TIME)"
                echo ""
                echo "- tmux: $TMUX_SESSION"
                echo "- agent: $AGENT_ID"
                echo ""
                echo "## Messages"
                echo ""
                jq -r 'select(.type == "human" or .type == "assistant") | "### " + .type + "\n" + (.message // .content // "" | tostring) + "\n"' "$DEST" 2>/dev/null || echo "(parse error)"
            } > "$MD_FILE" 2>/dev/null || true
        fi
    fi
fi

# 正常終了（非同期 hook なので出力は不要）
exit 0
