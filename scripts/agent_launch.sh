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

# Claude 既起動チェック（pane の直接子プロセスで検索）
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

# ダイアログ自動承認 + 初期化完了検出
ELAPSED=0
TRUST_HANDLED=false
ACCEPT_HANDLED=false
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))

    PANE_CONTENT=$(tmux capture-pane -t "$TMUX_TARGET" -p -S -20 2>/dev/null || true)

    # 1) Trust folder ダイアログ → Enter で承認（カーソルは既に "Yes, I trust" 上）
    if echo "$PANE_CONTENT" | grep -q "Yes, I trust this folder"; then
        if [ "$TRUST_HANDLED" = "false" ]; then
            echo "🔓 $AGENT_ID: Trust ダイアログを自動承認中..."
            tmux send-keys -t "$TMUX_TARGET" Enter
            TRUST_HANDLED=true
            sleep 2
        fi
        continue
    fi

    # 2) dangerously-skip-permissions ダイアログ（v2.1未満の旧バージョン用）
    if echo "$PANE_CONTENT" | grep -q "Yes, I accept"; then
        if [ "$ACCEPT_HANDLED" = "false" ]; then
            echo "🔓 $AGENT_ID: 権限ダイアログを自動承認中..."
            tmux send-keys -t "$TMUX_TARGET" Down
            sleep 0.3
            tmux send-keys -t "$TMUX_TARGET" Enter
            ACCEPT_HANDLED=true
            sleep 2
        fi
        continue
    fi

    # 3) Claude Code の初期化完了サインを検出
    #    v2.1.53+: 'bypass permissions' / 'Try "' / '❯'
    #    旧バージョン: '╭─' / '╰─' / 'Type your prompt' / 'How can I help'
    if echo "$PANE_CONTENT" | grep -qE '(╭─|╰─|Type your prompt|How can I help|bypass permissions|Try "|❯ )'; then
        echo "✅ $AGENT_ID: Claude Code 初期化完了 (${ELAPSED}秒)"
        break
    fi
done

if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
    echo "⚠️  $AGENT_ID: タイムアウト（${MAX_WAIT}秒）" >&2
    exit 1
fi

# 大臣タイプから指示書名・ツールDir・type_key を一括取得
# Usage: get_minister_info <agent_id> → sets MINISTER_INSTRUCTION, MINISTER_TOOLS_DIR, MINISTER_TYPE_KEY
get_minister_info() {
    local agent_id="$1"
    # instruction_name:tools_dir:type_key
    local info
    case "$agent_id" in
        minister_product)  info="minister_product:tools/product:product" ;;
        minister_research) info="minister_research:tools/research:research" ;;
        minister_arch)     info="minister_architect:tools/architect:arch" ;;
        minister_fe)       info="minister_frontend:tools/frontend:fe" ;;
        minister_be*)      info="minister_backend:tools/backend:be" ;;
        minister_mob)      info="minister_mobile:tools/mobile:mob" ;;
        minister_infra)    info="minister_infra:tools/infra:infra" ;;
        minister_ai)       info="minister_ai:tools/ai:ai" ;;
        minister_qa)       info="minister_qa:tools/qa:qa" ;;
        minister_design)   info="minister_design:tools/design:design" ;;
        minister_uat)      info="minister_uat:tools/uat:uat" ;;
        *)                 info="unknown:::" ;;
    esac
    MINISTER_INSTRUCTION="${info%%:*}"
    local rest="${info#*:}"
    MINISTER_TOOLS_DIR="${rest%%:*}"
    MINISTER_TYPE_KEY="${rest##*:}"
}

# 役割に応じた初期指示を構成
case "$ROLE" in
    prime_minister)
        INIT_MSG="あなたは内閣制度マルチエージェントシステムの首相(Prime Minister)です。

まず instructions/prime_minister.md を Read ツールで読み込み、その指示に従ってください。

基本情報:
- agent_id: pm
- inbox: queue/inbox/pm/ （ディレクトリ内に .yaml ファイルが届きます）
- 作業ディレクトリ: $BASE_DIR

あなたはドメイン分析に基づき、専門大臣または内閣官房長官にタスクをルーティングします。
大臣はオンデマンドで起動します: ./scripts/minister_activate.sh <type>
インスタンス確認: ./scripts/instance_count.sh
タスク管理: ./scripts/task_manager.sh create|update|list|get|dashboard

メッセージが届くと自動通知されます。通知を受けたら Bash で ls queue/inbox/pm/ を実行し、各ファイルを Read ツールで読み込んで処理してください。処理後は各ファイルを Bash で rm してください。

短く確認の返答をしてください。"
        ;;
    chief_secretary)
        INIT_MSG="あなたは内閣制度マルチエージェントシステムの内閣官房長官(Chief Cabinet Secretary)です。

まず instructions/chief_secretary.md を Read ツールで読み込み、その指示に従ってください。

基本情報:
- agent_id: chief
- inbox: queue/inbox/chief/ （ディレクトリ内に .yaml ファイルが届きます）
- 作業ディレクトリ: $BASE_DIR
- 配下官僚: chief_bur1, chief_bur2（オンデマンド）

あなたは専門大臣と同格のチームリーダーです。首相から割り当てられた汎用/未分類タスクを実行します。
複雑なタスクは配下の官僚に委譲してください。

メッセージが届くと自動通知されます。通知を受けたら Bash で ls queue/inbox/chief/ を実行し、各ファイルを Read ツールで読み込んで処理してください。処理後は各ファイルを Bash で rm してください。

官僚へのタスク送信: ./scripts/inbox_write.sh chief_bur1 \"メッセージ\" --from chief
首相への報告: ./scripts/inbox_write.sh pm \"メッセージ\" --from chief --type report

短く確認の返答をしてください。"
        ;;
    minister_leader)
        get_minister_info "$AGENT_ID"
        INIT_MSG="あなたは内閣制度マルチエージェントシステムの専門大臣（チームリーダー）です。

まず instructions/${MINISTER_INSTRUCTION}.md を Read ツールで読み込み、その指示に従ってください。

基本情報:
- agent_id: ${AGENT_ID}
- inbox: queue/inbox/${AGENT_ID}/ （ディレクトリ内に .yaml ファイルが届きます）
- 作業ディレクトリ: $BASE_DIR
- 専用ツール: ${MINISTER_TOOLS_DIR}/
- 配下官僚: ${MINISTER_TYPE_KEY}_bur1, ${MINISTER_TYPE_KEY}_bur2

あなたは首相(PM)に直接報告するチームリーダーです。
シンプルなタスクは自分で実行、複雑なタスクは官僚に委譲してください。
他の大臣に直接質問・同期も可能です（--type clarification/coordination）。

メッセージが届くと自動通知されます。通知を受けたら Bash で ls queue/inbox/${AGENT_ID}/ を実行し、各ファイルを Read ツールで読み込んで処理してください。処理後は各ファイルを Bash で rm してください。

官僚へのタスク送信: ./scripts/inbox_write.sh ${MINISTER_TYPE_KEY}_bur1 \"メッセージ\" --from ${AGENT_ID}
首相への報告: ./scripts/inbox_write.sh pm \"メッセージ\" --from ${AGENT_ID} --type report
他大臣への質問: ./scripts/inbox_write.sh minister_XX \"質問\" --from ${AGENT_ID} --type clarification

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
- inbox: queue/inbox/${AGENT_ID}/ （ディレクトリ内に .yaml ファイルが届きます）
- 上司: ${PARENT_ID}
- 作業ディレクトリ: $BASE_DIR

あなたの上司は ${PARENT_ID} です。タスク完了後は上司に報告してください。

メッセージが届くと自動通知されます。通知を受けたら Bash で ls queue/inbox/${AGENT_ID}/ を実行し、各ファイルを Read ツールで読み込んで処理してください。処理後は各ファイルを Bash で rm してください。

上司への報告: ./scripts/inbox_write.sh ${PARENT_ID} \"メッセージ\" --from ${AGENT_ID} --type report

短く確認の返答をしてください。"
        ;;
    bureaucrat)
        # レガシー互換（旧 bureaucrat ロール）
        INIT_MSG="あなたは内閣制度マルチエージェントシステムの官僚(Bureaucrat)です。

まず instructions/bureaucrat.md を Read ツールで読み込み、その指示に従ってください。

基本情報:
- agent_id: ${AGENT_ID}
- inbox: queue/inbox/${AGENT_ID}/ （ディレクトリ内に .yaml ファイルが届きます）
- 作業ディレクトリ: $BASE_DIR

メッセージが届くと自動通知されます。通知を受けたら Bash で ls queue/inbox/${AGENT_ID}/ を実行し、各ファイルを Read ツールで読み込んで処理してください。処理後は各ファイルを Bash で rm してください。

短く確認の返答をしてください。"
        ;;
    *)
        echo "ERROR: 不明な role: $ROLE" >&2
        exit 1
        ;;
esac

# 初期指示を送信（パイプ経由で load-buffer → paste-buffer。テンプファイル不使用）
sleep 2
echo "$INIT_MSG" | tmux load-buffer -b "init_${AGENT_ID}" -
tmux paste-buffer -b "init_${AGENT_ID}" -t "$TMUX_TARGET"
tmux delete-buffer -b "init_${AGENT_ID}" 2>/dev/null || true
sleep 0.5
tmux send-keys -t "$TMUX_TARGET" Enter

echo "📨 $AGENT_ID: 初期指示を送信しました"
