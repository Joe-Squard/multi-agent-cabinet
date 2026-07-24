#!/usr/bin/env bash
# =============================================================================
# run_daily.sh — 1回分の予想を実行してレポートを出力する
# =============================================================================
# cron やタスクスケジューラから呼び出す想定。
# 例) 営業時間中 30分毎:  */30 9-22 * * *  /path/to/run_daily.sh
# =============================================================================
set -euo pipefail

# スクリプトの場所からプロジェクトルートを特定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

export PYTHONPATH="$PROJECT_DIR/src:${PYTHONPATH:-}"

# 引数: 日付（省略時は当日）, データソース（省略時は config 準拠）
DATE="${1:-}"
SOURCE="${2:-}"

ARGS=(predict --format all)
[ -n "$DATE" ] && ARGS+=(--date "$DATE")
[ -n "$SOURCE" ] && ARGS+=(--source "$SOURCE")

LOG_DIR="$PROJECT_DIR/output"
mkdir -p "$LOG_DIR"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 予想実行: ${ARGS[*]}"
python3 -m palazzo_predictor "${ARGS[@]}" --quiet
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 完了。output/latest.html を参照してください。"
