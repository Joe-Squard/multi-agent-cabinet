#!/usr/bin/env bash
# =============================================================================
# install_cron.sh — 自動更新を crontab に登録する
# =============================================================================
# 営業時間中（9時〜22時台）30分毎に run_daily.sh を実行する cron を登録。
# 既存の同一エントリがあれば重複登録しない。
#
#   ./scripts/install_cron.sh              # 既定: 30分毎
#   ./scripts/install_cron.sh 15           # 15分毎
#   ./scripts/install_cron.sh 30 demo      # 30分毎・デモデータ
#   ./scripts/install_cron.sh --remove     # 登録解除
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN="$SCRIPT_DIR/run_daily.sh"
TAG="# palazzo-hatogaya-predictor"

if [ "${1:-}" = "--remove" ]; then
  crontab -l 2>/dev/null | grep -v "$TAG" | crontab - || true
  echo "cron エントリを削除しました。"
  exit 0
fi

INTERVAL="${1:-30}"
SOURCE="${2:-}"

# 営業時間 9-22時台に INTERVAL 分毎
CRON_LINE="*/${INTERVAL} 9-22 * * * $RUN '' '$SOURCE' >> $PROJECT_DIR/output/cron.log 2>&1 $TAG"

# 既存の当ツール由来エントリを消してから追加（重複防止）
( crontab -l 2>/dev/null | grep -v "$TAG" || true; echo "$CRON_LINE" ) | crontab -

echo "cron に登録しました:"
echo "  $CRON_LINE"
echo ""
echo "確認:  crontab -l | grep palazzo"
echo "解除:  $0 --remove"
