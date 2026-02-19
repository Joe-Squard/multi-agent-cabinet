#!/bin/bash
# first_setup.sh - 初回セットアップスクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏛️  内閣制度マルチエージェントシステム 初回セットアップ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ========================================
# 1. 環境チェック
# ========================================
echo "📋 環境をチェック中..."
echo ""

MISSING_DEPS=()

# tmux チェック
if ! command -v tmux &> /dev/null; then
    echo "  ❌ tmux が見つかりません"
    MISSING_DEPS+=("tmux")
else
    echo "  ✅ tmux: $(tmux -V)"
fi

# Claude Code チェック
if ! command -v claude &> /dev/null; then
    echo "  ❌ Claude Code が見つかりません"
    MISSING_DEPS+=("claude")
else
    echo "  ✅ Claude Code: インストール済み"
fi

# inotify-tools チェック (Linux)
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if ! command -v inotifywait &> /dev/null; then
        echo "  ⚠️  inotify-tools が見つかりません（推奨）"
        echo "     インストール: sudo apt-get install inotify-tools"
        echo "     ※ フォールバックとしてポーリングモードを使用します"
    else
        echo "  ✅ inotify-tools: インストール済み"
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    if ! command -v fswatch &> /dev/null; then
        echo "  ⚠️  fswatch が見つかりません（推奨）"
        echo "     インストール: brew install fswatch"
        echo "     ※ フォールバックとしてポーリングモードを使用します"
    else
        echo "  ✅ fswatch: インストール済み"
    fi
fi

echo ""

# 必須依存関係のチェック
if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ 以下の依存関係が不足しています:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - $dep"
    done
    echo ""
    echo "インストール方法:"
    echo ""
    if [[ " ${MISSING_DEPS[@]} " =~ " tmux " ]]; then
        echo "  tmux:"
        echo "    Ubuntu/Debian: sudo apt-get install tmux"
        echo "    macOS: brew install tmux"
        echo ""
    fi
    if [[ " ${MISSING_DEPS[@]} " =~ " claude " ]]; then
        echo "  Claude Code:"
        echo "    https://claude.ai/download"
        echo ""
    fi
    exit 1
fi

# ========================================
# 2. ディレクトリ構造作成
# ========================================
echo "📁 ディレクトリ構造を作成中..."
echo ""

mkdir -p instructions scripts config lib
mkdir -p queue/{inbox,tasks,reports}
mkdir -p memory projects

echo "  ✅ instructions/"
echo "  ✅ scripts/"
echo "  ✅ config/"
echo "  ✅ queue/{inbox,tasks,reports}"
echo "  ✅ memory/"
echo "  ✅ projects/"
echo ""

# ========================================
# 3. .gitignore 作成
# ========================================
echo "📝 .gitignore を作成中..."

cat > .gitignore <<'EOF'
# プロジェクト作業領域（機密情報を含む可能性）
projects/

# キュー（実行時生成）
queue/

# メモリ（永続化データ）
memory/

# ダッシュボード
dashboard.md

# ログ
*.log

# 一時ファイル
*.tmp
*.lock
.DS_Store
EOF

echo "  ✅ .gitignore 作成完了"
echo ""

# ========================================
# 4. スクリプトに実行権限付与
# ========================================
echo "🔧 スクリプトに実行権限を付与中..."

chmod +x scripts/*.sh 2>/dev/null || true
chmod +x *.sh 2>/dev/null || true

echo "  ✅ 実行権限付与完了"
echo ""

# ========================================
# 5. Claude Code 認証チェック
# ========================================
echo "🔑 Claude Code 認証をチェック中..."
echo ""

if claude --version &> /dev/null; then
    echo "  ✅ Claude Code は認証済みです"
else
    echo "  ⚠️  Claude Code の認証が必要です"
    echo ""
    echo "  以下のコマンドを実行してください:"
    echo ""
    echo "    claude --dangerously-skip-permissions"
    echo ""
    echo "  ブラウザが開いたら:"
    echo "    1. Anthropic アカウントにログイン"
    echo "    2. CLI に戻って 'Bypass Permissions' を承認"
    echo ""
fi

# ========================================
# 6. Memory MCP セットアップ
# ========================================
echo "🧠 Qdrant 記憶システムをチェック中..."
echo ""

# Docker チェック
if command -v docker &> /dev/null; then
    echo "  ✅ Docker: $(docker --version 2>/dev/null | head -1)"
else
    echo "  ⚠️  Docker が見つかりません（記憶システムの Qdrant に必要）"
    echo "     インストール: https://docs.docker.com/get-docker/"
fi

# mcp-server-qdrant チェック
if command -v mcp-server-qdrant &> /dev/null || pip3 show mcp-server-qdrant &> /dev/null 2>&1; then
    echo "  ✅ mcp-server-qdrant: インストール済み"
else
    echo "  ⚠️  mcp-server-qdrant が見つかりません"
    echo "     インストール: pip install mcp-server-qdrant"
fi

# pm2 チェック
if command -v pm2 &> /dev/null; then
    echo "  ✅ pm2: $(pm2 --version 2>/dev/null)"
else
    echo "  ⚠️  pm2 が見つかりません（MCP Server 管理に使用）"
    echo "     インストール: npm install -g pm2"
fi

# .mcp.json チェック
if [ -f "$SCRIPT_DIR/.mcp.json" ]; then
    echo "  ✅ .mcp.json: 存在"
else
    echo "  ⚠️  .mcp.json が見つかりません（MCP サーバー自動接続設定）"
fi

echo ""
echo "  📖 記憶システムの起動方法:"
echo "     cd memory && docker compose up -d         # Qdrant Vector DB"
echo "     pip install mcp-server-qdrant             # MCP Server インストール"
echo "     cd memory && pm2 start ecosystem.config.cjs  # MCP Server 起動"
echo "     pm2 save                                  # 永続化"

echo ""

# ========================================
# 7. 設定ファイル確認
# ========================================
echo "⚙️  設定ファイルを確認中..."
echo ""

if [ ! -f "config/settings.yaml" ]; then
    echo "  ⚠️  config/settings.yaml が見つかりません"
    echo "  サンプル設定を作成してください"
else
    echo "  ✅ config/settings.yaml 存在"
fi

if [ ! -f "config/agents.yaml" ]; then
    echo "  ⚠️  config/agents.yaml が見つかりません"
else
    echo "  ✅ config/agents.yaml 存在"
fi

echo ""

# ========================================
# 8. 完了
# ========================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ セットアップ完了"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📖 次のステップ:"
echo ""
echo "  1. システムを起動:"
echo "     ./cabinet_start.sh"
echo ""
echo "  2. 首相セッションに接続:"
echo "     tmux attach-session -t pm"
echo ""
echo "  3. セッション間の移動:"
echo "     Ctrl+b d (デタッチ)"
echo "     tmux attach-session -t <session_name>"
echo ""
echo "  4. システム停止:"
echo "     ./cabinet_stop.sh"
echo ""
echo "📚 ドキュメント:"
echo "  - README.md: システム概要"
echo "  - instructions/prime_minister.md: 首相の役割"
echo "  - instructions/chief_secretary.md: 内閣官房長官の役割"
echo "  - instructions/bureaucrat.md: 官僚の役割"
echo ""
