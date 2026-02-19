#!/bin/bash
# cabinet_start.sh - 内閣制度マルチエージェントシステム起動スクリプト v0.4.0
# PM + Chief のみ起動。大臣はオンデマンドで minister_activate.sh により起動。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ライブラリ読み込み
source "$SCRIPT_DIR/lib/yaml_reader.sh"
SETTINGS="$SCRIPT_DIR/config/settings.yaml"

# コマンドラインオプション解析
KESSEN_MODE=false
CLEAN_MODE=false

while [ $# -gt 0 ]; do
    case "$1" in
        -k|--kessen)
            KESSEN_MODE=true
            shift
            ;;
        --clean)
            CLEAN_MODE=true
            shift
            ;;
        -h|--help)
            echo "使い方: $0 [OPTIONS]"
            echo ""
            echo "オプション:"
            echo "  -k, --kessen   決戦モード（全エージェント Opus で起動）"
            echo "  --clean        キュー・ダッシュボードをリセットして起動"
            echo "  -h, --help     このヘルプを表示"
            exit 0
            ;;
        *)
            echo "ERROR: 不明なオプション: $1" >&2
            exit 1
            ;;
    esac
done

# モデル割り当て
if [ "$KESSEN_MODE" = true ]; then
    echo "⚔️  決戦モード: 全エージェント Opus で起動します"
    PM_MODEL="opus"
    CHIEF_MODEL="opus"
else
    PM_MODEL=$(get_yaml_value "$SETTINGS" "agents.prime_minister.model")
    CHIEF_MODEL=$(get_yaml_value "$SETTINGS" "agents.chief_secretary.model")
fi

echo "🏛️  内閣制度マルチエージェントシステム v0.4.0 を起動します"
if [ "$KESSEN_MODE" = true ]; then
    echo "   モード: ⚔️  決戦（全 Opus）"
else
    echo "   モード: 通常（対等な大臣制度・オンデマンド起動）"
fi
echo "   起動対象: 首相 + 内閣官房長官（大臣はオンデマンド）"
echo ""

# ========================================
# 前提条件チェック
# ========================================
if ! command -v tmux &> /dev/null; then
    echo "❌ tmux がインストールされていません" >&2
    echo "インストール: sudo apt-get install tmux" >&2
    exit 1
fi

if ! command -v claude &> /dev/null; then
    echo "❌ Claude Code がインストールされていません" >&2
    echo "インストール: https://claude.ai/download" >&2
    exit 1
fi

# inotifywait チェック（任意）
if command -v inotifywait &> /dev/null; then
    echo "✅ inotifywait 利用可能（イベント駆動モード）"
else
    echo "⚠️  inotifywait 未インストール（ポーリングモードで動作）"
    echo "   推奨: sudo apt-get install inotify-tools"
fi

# Qdrant Vector DB チェック
if curl -s http://localhost:6333/healthz > /dev/null 2>&1; then
    echo "✅ Qdrant Vector DB 稼働中"
else
    echo "⚠️  Qdrant Vector DB が起動していません"
    echo "   起動: cd memory && docker compose up -d"
    echo "   記憶システムなしで続行します"
fi

# Memory MCP Server チェック
if curl -s http://localhost:8000/sse -m 2 > /dev/null 2>&1; then
    echo "✅ Memory MCP Server 稼働中 (SSE on :8000)"
else
    echo "⚠️  Memory MCP Server が起動していません"
    echo "   起動: cd memory && pm2 start ecosystem.config.cjs"
    echo "   記憶システムなしで続行します"
fi
echo ""

# ========================================
# クリーンモード処理
# ========================================
if [ "$CLEAN_MODE" = true ]; then
    echo "🧹 クリーンモード: キュー・ダッシュボード・ランタイムをリセットします"
    if [ -d "queue" ] || [ -f "dashboard.md" ]; then
        BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        [ -d "queue" ] && cp -r queue "$BACKUP_DIR/" 2>/dev/null || true
        [ -f "dashboard.md" ] && cp dashboard.md "$BACKUP_DIR/" 2>/dev/null || true
        echo "  📦 バックアップ: $BACKUP_DIR"
    fi
    rm -rf queue/inbox/* queue/tasks/* queue/reports/* 2>/dev/null || true
    rm -f runtime/active.txt 2>/dev/null || true
    echo "  ✅ キュー・ランタイムをリセットしました"
    echo ""
fi

# ========================================
# ディレクトリ・ダッシュボード初期化
# ========================================
mkdir -p queue/{inbox,tasks,reports} memory projects backups runtime

# runtime/active.txt 初期化
cat > runtime/active.txt <<EOF
pm
chief
EOF

cat > dashboard.md <<EOF
# 内閣制度マルチエージェントシステム v0.4.0 ダッシュボード

最終更新: $(date -Iseconds)

## システム状態

| エージェント | 役割 | ステータス | 現在のタスク |
|---|---|---|---|
| 首相 (PM) | ドメインルーティング | 起動中 | - |
| 内閣官房長官 (Chief) | 汎用タスク | 起動中 | - |

## アクティブ大臣

（大臣はオンデマンド起動。首相がタスクに応じて起動します）

## タスク一覧

現在タスクはありません。

## インスタンス

アクティブ: 2 / 20
EOF

echo "📊 dashboard.md を初期化しました"
echo ""

# ========================================
# 既存セッションのクリーンアップ
# ========================================
for session in pm chief watcher; do
    tmux kill-session -t "$session" 2>/dev/null || true
done
# オンデマンド大臣セッションもクリーンアップ
for type in product research arch fe be mob infra ai qa design uat; do
    tmux kill-session -t "m_${type}" 2>/dev/null || true
done

echo "🚀 tmux セッションを作成中..."
echo ""

# ========================================
# 首相 (Prime Minister) セッション
# ========================================
echo "👔 首相セッションを作成中..."
tmux new-session -d -s pm -n "首相"
tmux send-keys -t pm "cd $SCRIPT_DIR" C-m
tmux send-keys -t pm "export AGENT_ID=pm" C-m
tmux send-keys -t pm "clear" C-m
tmux set-option -t pm:首相 @agent_id "pm"
tmux set-option -t pm pane-border-format "#{@agent_id} | #{pane_title}"
echo "  ✅ pm セッション作成"

# ========================================
# 内閣官房長官 (Chief Secretary) セッション
# ========================================
echo "📋 内閣官房長官セッションを作成中..."
tmux new-session -d -s chief -n "官房長官"
tmux send-keys -t chief "cd $SCRIPT_DIR" C-m
tmux send-keys -t chief "export AGENT_ID=chief" C-m
tmux send-keys -t chief "clear" C-m
tmux set-option -t chief:官房長官 @agent_id "chief"
tmux set-option -t chief pane-border-format "#{@agent_id} | #{pane_title}"
echo "  ✅ chief セッション作成"

# ========================================
# Watcher セッション（Two-Layer通信 Layer 2）
# ========================================
echo "👁️  Watcher セッションを作成中..."
tmux new-session -d -s watcher -n "監視"
tmux send-keys -t watcher "cd $SCRIPT_DIR" C-m
tmux send-keys -t watcher "echo '👁️  Two-Layer通信 Watcher セッション'" C-m
tmux send-keys -t watcher "echo 'PM + Chief の inbox を監視中。大臣 watcher は起動時に追加されます。'" C-m
tmux send-keys -t watcher "echo ''" C-m

# PM と Chief の watcher を起動
tmux send-keys -t watcher "./scripts/inbox_watcher.sh pm pm &" C-m
tmux send-keys -t watcher "./scripts/inbox_watcher.sh chief chief &" C-m
echo "  ✅ watcher セッション作成 (2 watcher 起動)"

# ntfy listener 起動（設定で有効の場合）
NTFY_ENABLED=$(get_yaml_value "$SETTINGS" "ntfy.enabled")
if [ "$NTFY_ENABLED" = "true" ]; then
    echo "  📱 ntfy リスナーを起動中..."
    tmux send-keys -t watcher "./scripts/ntfy_listener.sh &" C-m
    echo "  ✅ ntfy リスナー起動"
else
    echo "  ℹ️  ntfy は無効（config/settings.yaml で有効化可能）"
fi

echo ""

# ========================================
# PM + Chief で Claude Code を起動
# ========================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🤖 PM + Chief で Claude Code を起動中..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⏳ 各エージェントの初期化に 30〜90秒かかります..."
echo ""

# PM を先に起動
echo "--- 首相 (PM) [model: ${PM_MODEL:-default}] ---"
./scripts/agent_launch.sh pm pm prime_minister "$PM_MODEL" &
PM_PID=$!

# 少し待ってから Chief を起動
sleep 5
echo "--- 内閣官房長官 (Chief) [model: ${CHIEF_MODEL:-default}] ---"
./scripts/agent_launch.sh chief chief chief_secretary "$CHIEF_MODEL" &
CHIEF_PID=$!

# 完了待機
echo ""
echo "⏳ PM + Chief の起動完了を待機中..."
FAILED=0
wait $PM_PID || { echo "⚠️  PM の起動に失敗"; FAILED=$((FAILED + 1)); }
wait $CHIEF_PID || { echo "⚠️  Chief の起動に失敗"; FAILED=$((FAILED + 1)); }

echo ""

# ========================================
# 起動完了
# ========================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$FAILED" -eq 0 ]; then
    echo "✅ 内閣制度マルチエージェントシステム v0.4.0 起動完了"
else
    echo "⚠️  起動完了（${FAILED}件の警告あり）"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📍 セッション一覧:"
echo ""
echo "  首相セッション:"
echo "    tmux attach-session -t pm"
echo ""
echo "  内閣官房長官セッション:"
echo "    tmux attach-session -t chief"
echo ""
echo "  Watcher セッション（監視）:"
echo "    tmux attach-session -t watcher"
echo ""
echo "🏛️  大臣の起動:"
echo "    首相にタスクを送ると、自動的に必要な大臣を起動します。"
echo "    手動起動: ./scripts/minister_activate.sh <type>"
echo "    (type: product, research, arch, fe, be, mob, infra, ai, qa, design, uat)"
echo ""
echo "📊 ダッシュボード:"
echo "    cat dashboard.md"
echo ""
echo "🔧 インスタンス確認:"
echo "    ./scripts/instance_count.sh"
echo "    tmux list-sessions"
echo ""
echo "⚠️  停止方法:"
echo "    ./cabinet_stop.sh"
echo ""
