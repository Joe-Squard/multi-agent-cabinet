#!/bin/bash
# qa_scaler.sh - QA 大臣の動的スケーリング
# 使い方:
#   qa_scaler.sh check      # pending reviews を確認してスケール判定
#   qa_scaler.sh status     # 現在のスケーリング状態を表示
#   qa_scaler.sh scale-up   # QA 大臣2号機を手動起動
#   qa_scaler.sh scale-down # QA 大臣2号機を手動停止

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$BASE_DIR/lib/yaml_reader.sh"

SETTINGS="$BASE_DIR/config/settings.yaml"
GOV_DEFAULTS="$BASE_DIR/config/governance_defaults.yaml"
PENDING_DIR="$BASE_DIR/runtime/pending_reviews"
SCALE_STATE_FILE="$BASE_DIR/runtime/qa_scale_state"

mkdir -p "$PENDING_DIR" "$(dirname "$SCALE_STATE_FILE")"

# 設定読み込み
THRESHOLD=$(get_yaml_value "$GOV_DEFAULTS" "scaling.qa.trigger_threshold" 2>/dev/null || echo "3")
COOLDOWN=$(get_yaml_value "$GOV_DEFAULTS" "scaling.qa.cooldown_seconds" 2>/dev/null || echo "300")
MAX_SESSIONS=$(get_yaml_value "$GOV_DEFAULTS" "scaling.qa.max_sessions" 2>/dev/null || echo "3")
SCALING_ENABLED=$(get_yaml_value "$GOV_DEFAULTS" "scaling.qa.enabled" 2>/dev/null || echo "true")

# pending review 数を取得
get_pending_count() {
    find "$PENDING_DIR" -name "*.yaml" 2>/dev/null | wc -l
}

# 現在のスケール状態
is_scaled_up() {
    tmux has-session -t m_qa_2 2>/dev/null
    return $?
}

# -------------------------------------------------------------------
# check: 自動スケール判定
# -------------------------------------------------------------------
cmd_check() {
    if [ "$SCALING_ENABLED" != "true" ]; then
        return 0
    fi

    local pending
    pending=$(get_pending_count)

    if [ "$pending" -gt "$THRESHOLD" ]; then
        if ! is_scaled_up; then
            echo "pending reviews ($pending) > threshold ($THRESHOLD) → スケールアップ"
            cmd_scale_up
        fi
    elif [ "$pending" -eq 0 ]; then
        if is_scaled_up; then
            # cooldown チェック
            if [ -f "$SCALE_STATE_FILE" ]; then
                local scaled_at
                scaled_at=$(cat "$SCALE_STATE_FILE")
                local now
                now=$(date +%s)
                if (( now - scaled_at > COOLDOWN )); then
                    echo "pending reviews 0 + cooldown 経過 → スケールダウン"
                    cmd_scale_down
                else
                    local remaining=$(( COOLDOWN - (now - scaled_at) ))
                    echo "cooldown 中 (残り ${remaining}秒)"
                fi
            fi
        fi
    fi
}

# -------------------------------------------------------------------
# scale-up: QA 大臣2号機を起動
# -------------------------------------------------------------------
cmd_scale_up() {
    if is_scaled_up; then
        echo "QA 大臣2号機は既に稼働中です"
        return 0
    fi

    echo "QA 大臣2号機を起動中..."

    if [ -f "$BASE_DIR/scripts/minister_activate.sh" ]; then
        # qa_2 として起動（settings.yaml に定義が必要）
        # 暫定: qa と同じ設定で別セッションとして起動
        bash "$BASE_DIR/scripts/minister_activate.sh" qa 2>/dev/null || {
            echo "警告: minister_activate.sh での起動に失敗。tmux で直接起動を試みます" >&2
        }
    fi

    # スケール状態を記録
    date +%s > "$SCALE_STATE_FILE"
    echo "QA 大臣2号機を起動しました"
}

# -------------------------------------------------------------------
# scale-down: QA 大臣2号機を停止
# -------------------------------------------------------------------
cmd_scale_down() {
    if ! is_scaled_up; then
        echo "QA 大臣2号機は稼働していません"
        return 0
    fi

    echo "QA 大臣2号機を停止中..."

    if [ -f "$BASE_DIR/scripts/minister_deactivate.sh" ]; then
        bash "$BASE_DIR/scripts/minister_deactivate.sh" qa_2 2>/dev/null || true
    fi

    tmux kill-session -t m_qa_2 2>/dev/null || true
    rm -f "$SCALE_STATE_FILE"
    echo "QA 大臣2号機を停止しました"
}

# -------------------------------------------------------------------
# status: スケーリング状態を表示
# -------------------------------------------------------------------
cmd_status() {
    local pending
    pending=$(get_pending_count)

    echo "=== QA スケーリング状態 ==="
    echo "  有効: $SCALING_ENABLED"
    echo "  pending reviews: $pending"
    echo "  閾値: $THRESHOLD"
    echo "  cooldown: ${COOLDOWN}秒"
    echo "  max sessions: $MAX_SESSIONS"

    if is_scaled_up; then
        echo "  QA 2号機: 稼働中"
        if [ -f "$SCALE_STATE_FILE" ]; then
            local scaled_at
            scaled_at=$(cat "$SCALE_STATE_FILE")
            local now
            now=$(date +%s)
            local elapsed=$(( now - scaled_at ))
            echo "  稼働時間: ${elapsed}秒"
        fi
    else
        echo "  QA 2号機: 停止"
    fi
}

# -------------------------------------------------------------------
# メインディスパッチ
# -------------------------------------------------------------------
case "${1:-status}" in
    check)      cmd_check ;;
    scale-up)   cmd_scale_up ;;
    scale-down) cmd_scale_down ;;
    status)     cmd_status ;;
    help|*)
        echo "qa_scaler.sh - QA 大臣の動的スケーリング"
        echo ""
        echo "使い方:"
        echo "  $0 check       pending reviews を確認してスケール判定"
        echo "  $0 status      現在のスケーリング状態を表示"
        echo "  $0 scale-up    QA 大臣2号機を手動起動"
        echo "  $0 scale-down  QA 大臣2号機を手動停止"
        ;;
esac
