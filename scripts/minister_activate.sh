#!/bin/bash
# minister_activate.sh - 大臣チームを起動（大臣 + 官僚 N 名）
# 使い方: ./scripts/minister_activate.sh <minister_type> [bureaucrat_count]
# 例:
#   ./scripts/minister_activate.sh fe       # FE大臣 + 官僚2名
#   ./scripts/minister_activate.sh arch 3   # 設計大臣 + 官僚3名

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$BASE_DIR/lib/yaml_reader.sh"
SETTINGS="$BASE_DIR/config/settings.yaml"
ACTIVE_FILE="$BASE_DIR/runtime/active.txt"

# デフォルト設定
DEFAULT_BUREAUCRATS=2
INSTANCE_LIMIT=20

# settings.yaml から読み込み（存在すれば）
_db=$(get_yaml_value "$SETTINGS" "default_bureaucrats" 2>/dev/null || echo "")
[ -n "$_db" ] && DEFAULT_BUREAUCRATS="$_db"
_il=$(get_yaml_value "$SETTINGS" "instance_limit" 2>/dev/null || echo "")
[ -n "$_il" ] && INSTANCE_LIMIT="$_il"

# 引数チェック
if [ $# -lt 1 ]; then
    echo "使い方: $0 <minister_type> [bureaucrat_count]" >&2
    echo "  minister_type: product|research|arch|fe|be|mob|infra|ai|qa|design|uat" >&2
    echo "  bureaucrat_count: 官僚数（デフォルト: $DEFAULT_BUREAUCRATS）" >&2
    exit 1
fi

MINISTER_TYPE="$1"
shift

# オプション解析
OVERRIDE_MODEL=""
OVERRIDE_BUR_MODEL=""
POSITIONAL_BUR_COUNT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --model)     OVERRIDE_MODEL="$2"; shift 2 ;;
        --bur-model) OVERRIDE_BUR_MODEL="$2"; shift 2 ;;
        *)           POSITIONAL_BUR_COUNT="$1"; shift ;;
    esac
done

BUR_COUNT="${POSITIONAL_BUR_COUNT:-$DEFAULT_BUREAUCRATS}"
SESSION_NAME="m_${MINISTER_TYPE}"

# 大臣タイプ → 設定マッピング
declare -A MINISTER_IDS=(
    ["product"]="minister_product"
    ["research"]="minister_research"
    ["arch"]="minister_arch"
    ["fe"]="minister_fe"
    ["be"]="minister_be"
    ["mob"]="minister_mob"
    ["infra"]="minister_infra"
    ["ai"]="minister_ai"
    ["qa"]="minister_qa"
    ["design"]="minister_design"
    ["uat"]="minister_uat"
)

declare -A MINISTER_ROLES=(
    ["product"]="minister_leader"
    ["research"]="minister_leader"
    ["arch"]="minister_leader"
    ["fe"]="minister_leader"
    ["be"]="minister_leader"
    ["mob"]="minister_leader"
    ["infra"]="minister_leader"
    ["ai"]="minister_leader"
    ["qa"]="minister_leader"
    ["design"]="minister_leader"
    ["uat"]="minister_leader"
)

declare -A MINISTER_INSTRUCTION=(
    ["product"]="minister_product"
    ["research"]="minister_research"
    ["arch"]="minister_architect"
    ["fe"]="minister_frontend"
    ["be"]="minister_backend"
    ["mob"]="minister_mobile"
    ["infra"]="minister_infra"
    ["ai"]="minister_ai"
    ["qa"]="minister_qa"
    ["design"]="minister_design"
    ["uat"]="minister_uat"
)

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

declare -A MINISTER_MODELS=(
    ["product"]="opus"
    ["research"]="opus"
    ["arch"]="opus"
    ["fe"]="opus"
    ["be"]="opus"
    ["mob"]="opus"
    ["infra"]="opus"
    ["ai"]="opus"
    ["qa"]="opus"
    ["design"]="opus"
    ["uat"]="opus"
)

# 短縮キー → settings.yaml の YAML キー名
declare -A MINISTER_YAML_KEYS=(
    ["product"]="product"
    ["research"]="research"
    ["arch"]="architect"
    ["fe"]="frontend"
    ["be"]="backend"
    ["mob"]="mobile"
    ["infra"]="infra"
    ["ai"]="ai"
    ["qa"]="qa"
    ["design"]="design"
    ["uat"]="uat"
)

# タイプ検証
if [ -z "${MINISTER_IDS[$MINISTER_TYPE]+x}" ]; then
    echo "ERROR: 不明な大臣タイプ: $MINISTER_TYPE" >&2
    echo "有効なタイプ: product, research, arch, fe, be, mob, infra, ai, qa, design, uat" >&2
    exit 1
fi

MINISTER_ID="${MINISTER_IDS[$MINISTER_TYPE]}"
LABEL="${MINISTER_LABELS[$MINISTER_TYPE]}"
MODEL="${MINISTER_MODELS[$MINISTER_TYPE]}"
INSTRUCTION="${MINISTER_INSTRUCTION[$MINISTER_TYPE]}"

# オプションによるモデル上書き
[ -n "$OVERRIDE_MODEL" ] && MODEL="$OVERRIDE_MODEL"

# 官僚モデル: --bur-model > settings.yaml bureaucrat_model > "sonnet"
if [ -n "$OVERRIDE_BUR_MODEL" ]; then
    BUR_MODEL="$OVERRIDE_BUR_MODEL"
else
    YAML_KEY="${MINISTER_YAML_KEYS[$MINISTER_TYPE]}"
    BUR_MODEL=$(get_yaml_value "$SETTINGS" "agents.ministers.types.${YAML_KEY}.bureaucrat_model" 2>/dev/null || echo "sonnet")
fi

# 既に起動中か確認
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "✅ ${LABEL} ($SESSION_NAME) は既に起動中です"
    exit 0
fi

# インスタンス枠チェック
mkdir -p "$BASE_DIR/runtime"
touch "$ACTIVE_FILE"
CURRENT_COUNT=$("$SCRIPT_DIR/instance_count.sh")
NEEDED=$((1 + BUR_COUNT))
AFTER=$((CURRENT_COUNT + NEEDED))

if [ "$AFTER" -gt "$INSTANCE_LIMIT" ]; then
    echo "ERROR: インスタンス上限超過" >&2
    echo "  現在: ${CURRENT_COUNT}, 必要: ${NEEDED}, 上限: ${INSTANCE_LIMIT}" >&2
    echo "  先に他の大臣を停止してください: ./scripts/minister_deactivate.sh <type>" >&2
    exit 1
fi

echo "🏛️  ${LABEL} チームを起動中..."
echo "   セッション: $SESSION_NAME"
echo "   構成: 大臣1名 + 官僚${BUR_COUNT}名 = ${NEEDED}インスタンス"
echo "   インスタンス: ${CURRENT_COUNT} → ${AFTER} / ${INSTANCE_LIMIT}"
echo ""

# ========================================
# tmux セッション作成
# ========================================
tmux new-session -d -s "$SESSION_NAME" -n "$LABEL"
tmux send-keys -t "$SESSION_NAME" "cd $BASE_DIR" C-m
tmux send-keys -t "$SESSION_NAME" "export AGENT_ID=$MINISTER_ID" C-m
tmux send-keys -t "$SESSION_NAME" "clear" C-m
tmux set-option -t "${SESSION_NAME}:0.0" @agent_id "$MINISTER_ID"

# 官僚ペインを追加
for i in $(seq 1 "$BUR_COUNT"); do
    BUR_ID="${MINISTER_TYPE}_bur${i}"
    tmux split-window -t "$SESSION_NAME:0" -v
    tmux send-keys -t "${SESSION_NAME}:0.${i}" "cd $BASE_DIR" C-m
    tmux send-keys -t "${SESSION_NAME}:0.${i}" "export AGENT_ID=$BUR_ID" C-m
    tmux send-keys -t "${SESSION_NAME}:0.${i}" "clear" C-m
    tmux set-option -t "${SESSION_NAME}:0.${i}" @agent_id "$BUR_ID"
done

# レイアウトを整列
tmux select-layout -t "$SESSION_NAME:0" tiled
tmux set-option -t "$SESSION_NAME" pane-border-format "#{@agent_id}"

echo "  ✅ tmux セッション作成完了 ($((1 + BUR_COUNT)) ペイン)"

# ========================================
# Watcher 起動
# ========================================
if tmux has-session -t watcher 2>/dev/null; then
    # 大臣の watcher
    tmux send-keys -t watcher "$BASE_DIR/scripts/inbox_watcher.sh $MINISTER_ID ${SESSION_NAME}:0.0 &" C-m
    # 官僚の watcher
    for i in $(seq 1 "$BUR_COUNT"); do
        BUR_ID="${MINISTER_TYPE}_bur${i}"
        tmux send-keys -t watcher "$BASE_DIR/scripts/inbox_watcher.sh $BUR_ID ${SESSION_NAME}:0.${i} &" C-m
    done
    echo "  ✅ Watcher 起動 ($((1 + BUR_COUNT)) 件)"
else
    echo "  ⚠️  Watcher セッションが存在しません（手動で watcher を起動してください）"
fi

# ========================================
# Claude Code 起動
# ========================================
echo ""
echo "🤖 Claude Code を起動中..."

# 大臣を起動
echo "  --- ${LABEL} [model: $MODEL] ---"
"$SCRIPT_DIR/agent_launch.sh" "${SESSION_NAME}:0.0" "$MINISTER_ID" "minister_leader" "$MODEL" &
MINISTER_PID=$!

# 官僚を起動（少し間隔を空ける）
BUR_PIDS=()
for i in $(seq 1 "$BUR_COUNT"); do
    sleep 3
    BUR_ID="${MINISTER_TYPE}_bur${i}"
    echo "  --- 官僚 $BUR_ID [model: $BUR_MODEL] ---"
    "$SCRIPT_DIR/agent_launch.sh" "${SESSION_NAME}:0.${i}" "$BUR_ID" "minister_bureaucrat" "$BUR_MODEL" &
    BUR_PIDS+=($!)
done

# 全プロセス完了を待機
FAILED=0
wait "$MINISTER_PID" || { echo "  ⚠️  ${LABEL} の起動に失敗"; FAILED=$((FAILED + 1)); }
for pid in "${BUR_PIDS[@]}"; do
    wait "$pid" || { echo "  ⚠️  官僚の起動に一部失敗"; FAILED=$((FAILED + 1)); }
done

# ========================================
# active.txt に登録
# ========================================
echo "$MINISTER_ID" >> "$ACTIVE_FILE"
for i in $(seq 1 "$BUR_COUNT"); do
    echo "${MINISTER_TYPE}_bur${i}" >> "$ACTIVE_FILE"
done

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "✅ ${LABEL} チーム起動完了（${NEEDED}インスタンス）"
else
    echo "⚠️  ${LABEL} チーム起動完了（${FAILED}件の警告あり）"
fi
echo ""
echo "📍 接続方法: tmux attach-session -t $SESSION_NAME"
echo "📊 インスタンス: $("$SCRIPT_DIR/instance_count.sh") / $INSTANCE_LIMIT"
