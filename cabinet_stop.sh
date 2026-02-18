#!/bin/bash
# cabinet_stop.sh - 内閣制度マルチエージェントシステム停止スクリプト v0.4.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORCE=false
if [ "${1:-}" = "-f" ] || [ "${1:-}" = "--force" ]; then
    FORCE=true
fi

echo "🛑 内閣制度マルチエージェントシステムを停止します"
echo ""

# tmux セッション一覧を表示
echo "現在のセッション:"
tmux list-sessions 2>/dev/null | grep -E "(pm|chief|m_|watcher)" || echo "  該当セッションなし"
echo ""

# 確認（-f でスキップ）
if [ "$FORCE" = false ]; then
    read -p "本当に停止しますか？ (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "キャンセルしました"
        exit 0
    fi
fi

# 各セッションを停止
echo "🔴 セッションを停止中..."

# まず watcher を停止（監視プロセスを先に止める）
tmux kill-session -t watcher 2>/dev/null && echo "  ✅ Watcher セッション停止" || echo "  ⚠️  Watcher セッションは既に停止済み"

# オンデマンド大臣セッションを停止
for type in product research arch fe be mob infra ai qa; do
    SESSION="m_${type}"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        tmux kill-session -t "$SESSION" 2>/dev/null && echo "  ✅ ${SESSION} セッション停止"
    fi
done

# Chief と PM を停止
tmux kill-session -t chief 2>/dev/null && echo "  ✅ 内閣官房長官セッション停止" || echo "  ⚠️  内閣官房長官セッションは既に停止済み"
tmux kill-session -t pm 2>/dev/null && echo "  ✅ 首相セッション停止" || echo "  ⚠️  首相セッションは既に停止済み"

# runtime/active.txt クリア
rm -f "$SCRIPT_DIR/runtime/active.txt" 2>/dev/null

echo ""
echo "✅ 内閣制度マルチエージェントシステムを停止しました"
echo ""
echo "再起動: ./cabinet_start.sh"
