#!/bin/bash
# minister_deactivate.sh - 大臣チームを停止
# 使い方: ./scripts/minister_deactivate.sh <minister_type>
# 例:
#   ./scripts/minister_deactivate.sh fe
#   ./scripts/minister_deactivate.sh arch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ACTIVE_FILE="$BASE_DIR/runtime/active.txt"

# 引数チェック
if [ $# -lt 1 ]; then
    echo "使い方: $0 <minister_type>" >&2
    echo "  minister_type: product|research|arch|fe|be|mob|infra|ai|qa|design|uat" >&2
    exit 1
fi

MINISTER_TYPE="$1"
SESSION_NAME="m_${MINISTER_TYPE}"

declare -A MINISTER_LABELS=(
    ["product"]="プロダクト大臣"
    ["research"]="リサーチ大臣"
    ["arch"]="設計大臣"
    ["fe"]="フロントエンド大臣"
    ["be"]="バックエンド大臣"
    ["mob"]="モバイル大臣"
    ["infra"]="インフラ大臣"
    ["ai"]="AI大臣"
    ["qa"]="品質管理大臣"
    ["design"]="デザイン大臣"
    ["uat"]="UAT大臣"
)

LABEL="${MINISTER_LABELS[$MINISTER_TYPE]:-$MINISTER_TYPE}"

# セッション存在確認
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "ℹ️  ${LABEL} ($SESSION_NAME) は起動していません"
    exit 0
fi

echo "🛑 ${LABEL} チームを停止中..."

# tmux セッションを kill
tmux kill-session -t "$SESSION_NAME" 2>/dev/null && \
    echo "  ✅ $SESSION_NAME セッション停止" || \
    echo "  ⚠️  $SESSION_NAME セッション停止失敗"

# watcher プロセスを kill（minister_type に関連するもの）
if tmux has-session -t watcher 2>/dev/null; then
    # watcher session 内で該当 agent_id の watcher を停止
    PIDS=$(pgrep -f "inbox_watcher.sh.*${MINISTER_TYPE}" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        echo "$PIDS" | xargs kill 2>/dev/null || true
        echo "  ✅ 関連 Watcher プロセス停止"
    fi
fi

# active.txt から削除
if [ -f "$ACTIVE_FILE" ]; then
    # minister_type に関連するエントリを全て削除
    grep -v "^minister_${MINISTER_TYPE}$" "$ACTIVE_FILE" | \
        grep -v "^${MINISTER_TYPE}_bur" > "${ACTIVE_FILE}.tmp" 2>/dev/null || true
    mv "${ACTIVE_FILE}.tmp" "$ACTIVE_FILE"
    echo "  ✅ active.txt 更新"
fi

# 対象 inbox ファイルをクリア
rm -f "$BASE_DIR/queue/inbox/minister_${MINISTER_TYPE}.yaml" 2>/dev/null
rm -f "$BASE_DIR/queue/inbox/${MINISTER_TYPE}_bur"*.yaml 2>/dev/null

echo ""
echo "✅ ${LABEL} チーム停止完了"
echo "📊 インスタンス: $("$SCRIPT_DIR/instance_count.sh") / $(get_yaml_value "$BASE_DIR/config/settings.yaml" "instance_limit" 2>/dev/null || echo "20")"
