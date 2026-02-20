#!/bin/bash
# review-enforcement.sh — L4: レビュー完了 Exit Gate
# イベント: Stop（セッション終了時）
# 対象: PM セッションのみ（大臣には適用しない — Fire & Forget を維持）

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOOK_DIR/lib/project_phase.sh"

# --- ファストパス ---
# PM セッションかどうかを確認
# Stop hook は環境変数やセッション情報から判定
# CLAUDE_SESSION_NAME が設定されていなければ allow
SESSION_NAME="${CLAUDE_SESSION_NAME:-""}"
AGENT_ID="${CLAUDE_AGENT_ID:-""}"

# PM でなければ即 allow（大臣は常に終了可能）
if [ "$SESSION_NAME" != "pm" ] && [ "$AGENT_ID" != "pm" ]; then
    # セッション名で判定できない場合、tmux セッション名を確認
    TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
    if [ "$TMUX_SESSION" != "pm" ]; then
        exit 0
    fi
fi

# Growth/Maintenance フェーズのプロジェクトがあるか
UNREVIEWED_BRANCHES=""

for dir in "$CABINET_BASE/projects"/*/; do
    if [ ! -f "${dir}PROJECT.yaml" ]; then
        continue
    fi

    local_project=$(basename "$dir")
    local_phase=$(get_phase "$local_project")

    if [ "$local_phase" != "growth" ] && [ "$local_phase" != "maintenance" ]; then
        continue
    fi

    # 未マージの feature/* ブランチを確認
    if [ -d "${dir}.git" ] || [ -f "${dir}.git" ]; then
        (
            cd "$dir"
            for branch in $(git branch --list "feature/*" 2>/dev/null | sed 's/^[* ]*//' ); do
                # QA 承認があるか確認（runtime/reviews/ に記録）
                REVIEW_FILE="$CABINET_BASE/runtime/reviews/${local_project}_$(echo "$branch" | tr '/' '_').approved"
                if [ ! -f "$REVIEW_FILE" ]; then
                    UNREVIEWED_BRANCHES="$UNREVIEWED_BRANCHES\n  - $local_project: $branch"
                fi
            done
        )
    fi
done

if [ -n "$UNREVIEWED_BRANCHES" ]; then
    cat <<EOF
{"decision": "block", "message": "未レビューの feature ブランチがあります:$UNREVIEWED_BRANCHES\n\nQA レビューが完了してからセッションを終了してください。\nQA に依頼: inbox_write.sh review_request を使用"}
EOF
    exit 0
fi

# 問題なし
exit 0
