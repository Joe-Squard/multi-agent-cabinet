#!/bin/bash
# release-completion.sh — L4: リリース完了 Exit Gate
# イベント: Stop（セッション終了時）
# 対象: PM セッションのみ

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOOK_DIR/lib/project_phase.sh"

# --- ファストパス ---
# PM セッションかどうかを確認
SESSION_NAME="${CLAUDE_SESSION_NAME:-""}"
AGENT_ID="${CLAUDE_AGENT_ID:-""}"

# PM でなければ即 allow
if [ "$SESSION_NAME" != "pm" ] && [ "$AGENT_ID" != "pm" ]; then
    TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
    if [ "$TMUX_SESSION" != "pm" ]; then
        exit 0
    fi
fi

# アクティブな release/* ブランチがあるかチェック
INCOMPLETE_RELEASES=""

for dir in "$CABINET_BASE/projects"/*/; do
    if [ ! -f "${dir}PROJECT.yaml" ]; then
        continue
    fi

    local_project=$(basename "$dir")
    local_phase=$(get_phase "$local_project")

    # Maintenance フェーズのみ
    if [ "$local_phase" != "maintenance" ]; then
        continue
    fi

    if [ -d "${dir}.git" ] || [ -f "${dir}.git" ]; then
        (
            cd "$dir"
            for branch in $(git branch --list "release/*" 2>/dev/null | sed 's/^[* ]*//' ); do
                # リリーススペックが存在するか
                SPEC_DIR="${dir}.cabinet/release-specs"
                RELEASE_NAME="${branch#release/}"

                # PR がマージ済みか確認（gh コマンド）
                MERGED=$(gh pr list --base develop --head "$branch" --state merged --json number --jq '.[0].number' 2>/dev/null || echo "")
                if [ -z "$MERGED" ]; then
                    INCOMPLETE_RELEASES="$INCOMPLETE_RELEASES\n  - $local_project: $branch (未マージ)"
                fi
            done
        )
    fi
done

if [ -n "$INCOMPLETE_RELEASES" ]; then
    cat <<EOF
{"decision": "block", "message": "未完了のリリースがあります:$INCOMPLETE_RELEASES\n\nリリースを完了してからセッションを終了してください。"}
EOF
    exit 0
fi

# 問題なし
exit 0
