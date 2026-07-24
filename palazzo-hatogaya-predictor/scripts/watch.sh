#!/usr/bin/env bash
# =============================================================================
# watch.sh — 自動更新ループを起動（常駐）
# =============================================================================
# 営業時間中、一定間隔で予想を更新し続ける。Ctrl+C で停止。
# 例)  ./scripts/watch.sh 30          # 30分間隔
#      ./scripts/watch.sh 20 demo     # 20分間隔・デモデータ
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"
export PYTHONPATH="$PROJECT_DIR/src:${PYTHONPATH:-}"

INTERVAL="${1:-30}"
SOURCE="${2:-}"

ARGS=(watch --interval "$INTERVAL")
[ -n "$SOURCE" ] && ARGS+=(--source "$SOURCE")

exec python3 -m palazzo_predictor "${ARGS[@]}"
