#!/bin/bash
# agent_health.sh - エージェント死活監視 & 自動復旧
# watcher セッション内でバックグラウンド実行される
# 使い方: ./scripts/agent_health.sh &

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ACTIVE_FILE="$BASE_DIR/runtime/active.txt"
LOG_FILE="$BASE_DIR/runtime/health.log"
HEALTH_INTERVAL=45   # チェック間隔（秒）
COOLDOWN=120         # 再起動クールダウン（秒）

mkdir -p "$BASE_DIR/runtime"

# クールダウン管理（agent_id → 最終再起動 epoch）
declare -A LAST_RESTART

log() {
    local level="$1"
    local msg="$2"
    local line="$(date '+%Y-%m-%d %H:%M:%S') [$level] $msg"
    echo "$line"
    echo "$line" >> "$LOG_FILE"
}

# agent_id → tmux target を導出
get_tmux_target() {
    local agent_id="$1"
    case "$agent_id" in
        pm)
            echo "pm" ;;
        chief)
            echo "chief" ;;
        minister_*)
            local type="${agent_id#minister_}"
            echo "m_${type}:0.0" ;;
        chief_bur*)
            # chief の官僚はペイン分割がないためスキップ
            echo "" ;;
        *_bur*)
            local type="${agent_id%%_bur*}"
            local idx="${agent_id##*bur}"
            echo "m_${type}:0.${idx}" ;;
        *)
            echo "" ;;
    esac
}

# agent_id → role を導出
get_agent_role() {
    local agent_id="$1"
    case "$agent_id" in
        pm)          echo "prime_minister" ;;
        chief)       echo "chief_secretary" ;;
        minister_*)  echo "minister_leader" ;;
        *_bur*)      echo "minister_bureaucrat" ;;
        *)           echo "" ;;
    esac
}

log "INFO" "ヘルスモニター起動 (interval=${HEALTH_INTERVAL}s, cooldown=${COOLDOWN}s)"

while true; do
    sleep "$HEALTH_INTERVAL"

    # active.txt がなければスキップ
    if [ ! -f "$ACTIVE_FILE" ]; then
        continue
    fi

    while IFS= read -r agent_id; do
        [ -z "$agent_id" ] && continue

        TMUX_TARGET=$(get_tmux_target "$agent_id")

        # マッピングできないエージェントはスキップ
        if [ -z "$TMUX_TARGET" ]; then
            continue
        fi

        SESSION="${TMUX_TARGET%%:*}"

        # セッション存在確認
        if ! tmux has-session -t "$SESSION" 2>/dev/null; then
            continue
        fi

        # Claude プロセス確認
        PANE_PID=$(tmux display-message -t "$TMUX_TARGET" -p '#{pane_pid}' 2>/dev/null || echo "")
        if [ -z "$PANE_PID" ]; then
            continue
        fi

        if pgrep -P "$PANE_PID" -f "claude" >/dev/null 2>&1; then
            # 生存確認 OK
            continue
        fi

        # === 死亡検知 ===
        NOW=$(date +%s)
        LAST="${LAST_RESTART[$agent_id]:-0}"
        DIFF=$((NOW - LAST))

        if [ "$DIFF" -lt "$COOLDOWN" ]; then
            log "COOL" "$agent_id: クールダウン中 (${DIFF}/${COOLDOWN}s)"
            continue
        fi

        log "DEAD" "$agent_id: Claude プロセス未検出 → 再起動"

        ROLE=$(get_agent_role "$agent_id")
        if [ -z "$ROLE" ]; then
            log "WARN" "$agent_id: role を特定できません"
            continue
        fi

        # 再起動（model は常に opus — settings.yaml のデフォルト）
        "$SCRIPT_DIR/agent_launch.sh" "$TMUX_TARGET" "$agent_id" "$ROLE" "opus" &
        LAST_RESTART[$agent_id]=$NOW
        log "RESTART" "$agent_id: agent_launch.sh 実行 (target=$TMUX_TARGET, role=$ROLE)"

    done < "$ACTIVE_FILE"
done
