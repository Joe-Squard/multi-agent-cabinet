#!/bin/bash
# agent_launch.sh - 任意のエージェントペインで Claude Code を起動
# 使い方: ./scripts/agent_launch.sh <tmux_target> <agent_id> <role> [model]
# 例:
#   ./scripts/agent_launch.sh pm pm prime_minister opus
#   ./scripts/agent_launch.sh chief chief chief_secretary opus
#   ./scripts/agent_launch.sh m_fe:0.0 minister_fe minister_leader opus
#   ./scripts/agent_launch.sh m_fe:0.1 fe_bur1 minister_bureaucrat opus

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAX_WAIT=90
POLL_INTERVAL=3

# 引数チェック
if [ $# -lt 3 ]; then
    echo "使い方: $0 <tmux_target> <agent_id> <role> [model]" >&2
    echo "  role: prime_minister | chief_secretary | minister_leader | minister_bureaucrat | bureaucrat" >&2
    echo "  model: opus | sonnet (省略時はデフォルト)" >&2
    exit 1
fi

TMUX_TARGET="$1"
AGENT_ID="$2"
ROLE="$3"
MODEL="${4:-}"

# セッション存在確認
SESSION_NAME="${TMUX_TARGET%%:*}"
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "ERROR: セッション $SESSION_NAME が存在しません" >&2
    exit 1
fi

# Claude 既起動チェック
PANE_PID=$(tmux display-message -t "$TMUX_TARGET" -p '#{pane_pid}')
if pgrep -P "$PANE_PID" -f "claude" >/dev/null 2>&1; then
    echo "✅ $AGENT_ID: Claude Code は既に起動済み"
    exit 0
fi

# Claude Code 起動
echo "🚀 $AGENT_ID: Claude Code を起動中..."
if [ -n "$MODEL" ]; then
    tmux send-keys -t "$TMUX_TARGET" "cd $BASE_DIR && claude --dangerously-skip-permissions --model $MODEL" C-m
else
    tmux send-keys -t "$TMUX_TARGET" "cd $BASE_DIR && claude --dangerously-skip-permissions" C-m
fi

# --dangerously-skip-permissions の WARNING ダイアログを自動承認
ELAPSED=0
DIALOG_HANDLED=false
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))

    PANE_CONTENT=$(tmux capture-pane -t "$TMUX_TARGET" -p -S -15 2>/dev/null || true)

    # WARNING ダイアログ検出 → "Yes, I accept" を選択
    if [ "$DIALOG_HANDLED" = "false" ] && echo "$PANE_CONTENT" | grep -q "Yes, I accept"; then
        echo "🔓 $AGENT_ID: 権限ダイアログを自動承認中..."
        # Down arrow で "Yes, I accept" を選択し、Enter で確定
        tmux send-keys -t "$TMUX_TARGET" Down
        sleep 0.3
        tmux send-keys -t "$TMUX_TARGET" Enter
        DIALOG_HANDLED=true
        sleep 2
        continue
    fi

    # Claude Code の初期化完了サインを検出（WARNING ダイアログの ❯ を除外）
    if echo "$PANE_CONTENT" | grep -q "Yes, I accept"; then
        # まだ WARNING ダイアログが表示中 → スキップ
        continue
    fi
    if echo "$PANE_CONTENT" | grep -qE '(❯|>|╭|╰|Type your|How can)'; then
        echo "✅ $AGENT_ID: Claude Code 初期化完了 (${ELAPSED}秒)"
        break
    fi
done

if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
    echo "⚠️  $AGENT_ID: タイムアウト（${MAX_WAIT}秒）" >&2
    exit 1
fi

# 大臣タイプから指示書名を推定（minister_leader ロール用）
get_instruction_name() {
    local agent_id="$1"
    case "$agent_id" in
        minister_product) echo "minister_product" ;;
        minister_research) echo "minister_research" ;;
        minister_arch)  echo "minister_architect" ;;
        minister_fe)    echo "minister_frontend" ;;
        minister_be*)   echo "minister_backend" ;;
        minister_mob)   echo "minister_mobile" ;;
        minister_infra) echo "minister_infra" ;;
        minister_ai)    echo "minister_ai" ;;
        minister_qa)    echo "minister_qa" ;;
        minister_design) echo "minister_design" ;;
        minister_uat)   echo "minister_uat" ;;
        *)              echo "unknown" ;;
    esac
}

# 大臣タイプから専用ツールディレクトリを推定
get_tools_dir() {
    local agent_id="$1"
    case "$agent_id" in
        minister_product) echo "tools/product" ;;
        minister_research) echo "tools/research" ;;
        minister_arch)  echo "tools/architect" ;;
        minister_fe)    echo "tools/frontend" ;;
        minister_be*)   echo "tools/backend" ;;
        minister_mob)   echo "tools/mobile" ;;
        minister_infra) echo "tools/infra" ;;
        minister_ai)    echo "tools/ai" ;;
        minister_qa)    echo "tools/qa" ;;
        minister_design) echo "tools/design" ;;
        minister_uat)   echo "tools/uat" ;;
        *)              echo "" ;;
    esac
}

# 大臣の type_key を取得
get_type_key() {
    local agent_id="$1"
    case "$agent_id" in
        minister_product) echo "product" ;;
        minister_research) echo "research" ;;
        minister_arch)  echo "arch" ;;
        minister_fe)    echo "fe" ;;
        minister_be*)   echo "be" ;;
        minister_mob)   echo "mob" ;;
        minister_infra) echo "infra" ;;
        minister_ai)    echo "ai" ;;
        minister_qa)    echo "qa" ;;
        minister_design) echo "design" ;;
        minister_uat)   echo "uat" ;;
        *)              echo "" ;;
    esac
}

# 役割に応じた初期指示を構成
case "$ROLE" in
    prime_minister)
        INIT_MSG="あなたは内閣制度マルチエージェントシステムの首相(Prime Minister)です。

まず instructions/prime_minister.md を Read ツールで読み込み、その指示に従ってください。

基本情報:
- agent_id: pm
- inbox: queue/inbox/pm.yaml
- 作業ディレクトリ: $BASE_DIR

あなたはドメイン分析に基づき、専門大臣または内閣官房長官にタスクをルーティングします。
大臣はオンデマンドで起動します: ./scripts/minister_activate.sh <type>
インスタンス確認: ./scripts/instance_count.sh

メッセージが届くと自動通知されます。通知を受けたら Read ツールで inbox を読み込んで処理してください。処理後は Bash で rm queue/inbox/pm.yaml を実行してください。

短く確認の返答をしてください。"
        ;;
    chief_secretary)
        INIT_MSG="あなたは内閣制度マルチエージェントシステムの内閣官房長官(Chief Cabinet Secretary)です。

まず instructions/chief_secretary.md を Read ツールで読み込み、その指示に従ってください。

基本情報:
- agent_id: chief
- inbox: queue/inbox/chief.yaml
- 作業ディレクトリ: $BASE_DIR
- 配下官僚: chief_bur1, chief_bur2（オンデマンド）

あなたは専門大臣と同格のチームリーダーです。首相から割り当てられた汎用/未分類タスクを実行します。
複雑なタスクは配下の官僚に委譲してください。

メッセージが届くと自動通知されます。通知を受けたら Read ツールで inbox を読み込んで処理してください。処理後は Bash で rm queue/inbox/chief.yaml を実行してください。

官僚へのタスク送信: ./scripts/inbox_write.sh chief_bur1 \"メッセージ\"
首相への報告: ./scripts/inbox_write.sh pm \"メッセージ\"

短く確認の返答をしてください。"
        ;;
    minister_leader)
        INSTRUCTION=$(get_instruction_name "$AGENT_ID")
        TOOLS_DIR=$(get_tools_dir "$AGENT_ID")
        TYPE_KEY=$(get_type_key "$AGENT_ID")
        INIT_MSG="あなたは内閣制度マルチエージェントシステムの専門大臣（チームリーダー）です。

まず instructions/${INSTRUCTION}.md を Read ツールで読み込み、その指示に従ってください。

基本情報:
- agent_id: ${AGENT_ID}
- inbox: queue/inbox/${AGENT_ID}.yaml
- 作業ディレクトリ: $BASE_DIR
- 専用ツール: ${TOOLS_DIR}/
- 配下官僚: ${TYPE_KEY}_bur1, ${TYPE_KEY}_bur2

あなたは首相(PM)に直接報告するチームリーダーです。
シンプルなタスクは自分で実行、複雑なタスクは官僚に委譲してください。

メッセージが届くと自動通知されます。通知を受けたら Read ツールで inbox を読み込んで処理してください。処理後は Bash で rm queue/inbox/${AGENT_ID}.yaml を実行してください。

官僚へのタスク送信: ./scripts/inbox_write.sh ${TYPE_KEY}_bur1 \"メッセージ\"
首相への報告: ./scripts/inbox_write.sh pm \"メッセージ\"

短く確認の返答をしてください。"
        ;;
    minister_bureaucrat)
        # 親エージェントIDを推定（agent_idから）
        # 例: fe_bur1 → minister_fe, arch_bur2 → minister_arch
        PARENT_TYPE="${AGENT_ID%%_bur*}"
        PARENT_ID="minister_${PARENT_TYPE}"
        # chief の場合の処理
        if [[ "$AGENT_ID" == chief_bur* ]]; then
            PARENT_ID="chief"
        fi
        INIT_MSG="あなたは内閣制度マルチエージェントシステムの官僚（実務担当者）です。

まず instructions/bureaucrat.md を Read ツールで読み込み、その指示に従ってください。

基本情報:
- agent_id: ${AGENT_ID}
- inbox: queue/inbox/${AGENT_ID}.yaml
- 上司: ${PARENT_ID}
- 作業ディレクトリ: $BASE_DIR

あなたの上司は ${PARENT_ID} です。タスク完了後は上司に報告してください。

メッセージが届くと自動通知されます。通知を受けたら Read ツールで inbox を読み込んで処理してください。処理後は Bash で rm queue/inbox/${AGENT_ID}.yaml を実行してください。

上司への報告: ./scripts/inbox_write.sh ${PARENT_ID} \"メッセージ\"

短く確認の返答をしてください。"
        ;;
    bureaucrat)
        # レガシー互換（旧 bureaucrat ロール）
        INIT_MSG="あなたは内閣制度マルチエージェントシステムの官僚(Bureaucrat)です。

まず instructions/bureaucrat.md を Read ツールで読み込み、その指示に従ってください。

基本情報:
- agent_id: ${AGENT_ID}
- inbox: queue/inbox/${AGENT_ID}.yaml
- 作業ディレクトリ: $BASE_DIR

メッセージが届くと自動通知されます。通知を受けたら Read ツールで inbox を読み込んで処理してください。処理後は Bash で rm queue/inbox/${AGENT_ID}.yaml を実行してください。

短く確認の返答をしてください。"
        ;;
    *)
        echo "ERROR: 不明な role: $ROLE" >&2
        exit 1
        ;;
esac

# 初期指示を送信（load-buffer + paste-buffer でエスケープ問題を回避）
sleep 2
TMPFILE=$(mktemp /tmp/agent_init_XXXXXX)
echo "$INIT_MSG" > "$TMPFILE"
tmux load-buffer -b "init_${AGENT_ID}" "$TMPFILE"
tmux paste-buffer -b "init_${AGENT_ID}" -t "$TMUX_TARGET"
rm -f "$TMPFILE"
sleep 0.5
tmux send-keys -t "$TMUX_TARGET" Enter

echo "📨 $AGENT_ID: 初期指示を送信しました"
