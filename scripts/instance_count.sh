#!/bin/bash
# instance_count.sh - アクティブ Claude Code インスタンス数をカウント
# 使い方: ./scripts/instance_count.sh
# 出力: 数値（アクティブインスタンス数）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ACTIVE_FILE="$BASE_DIR/runtime/active.txt"

# active.txt が存在すれば行数をカウント、なければ 0
if [ -f "$ACTIVE_FILE" ] && [ -s "$ACTIVE_FILE" ]; then
    wc -l < "$ACTIVE_FILE" | tr -d ' '
else
    echo "0"
fi
