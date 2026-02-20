#!/bin/bash
# branch-reminder.sh — L2: ブランチ作成リマインダー
# イベント: UserPromptSubmit
# main ブランチで実装キーワードを検出 → feature ブランチ作成をリマインド

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOOK_DIR/lib/project_phase.sh"

# ユーザー入力を stdin から読み取り
INPUT=$(cat)
USER_PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('user_prompt',''))" 2>/dev/null || echo "")

# --- ファストパス ---
# 統制対象プロジェクトがなければ即終了
HAS_ACTIVE=false
for dir in "$CABINET_BASE/projects"/*/; do
    if [ -f "${dir}PROJECT.yaml" ]; then
        local_project=$(basename "$dir")
        local_phase=$(get_phase "$local_project")
        if [ "$local_phase" = "growth" ] || [ "$local_phase" = "maintenance" ]; then
            HAS_ACTIVE=true
            break
        fi
    fi
done

if [ "$HAS_ACTIVE" = false ]; then
    exit 0
fi

# 実装キーワード検出
IMPL_KEYWORDS="実装|追加|修正|変更|削除|作成|fix|implement|add|create|update|modify|refactor|remove|delete"
if ! echo "$USER_PROMPT" | grep -qiE "$IMPL_KEYWORDS"; then
    exit 0
fi

# リマインダーメッセージ
cat <<EOF
{"message": "[統制] 実装タスクを検出しました。Growth/Maintenance プロジェクトでは feature/* ブランチで作業してください。\nブランチ作成: git checkout -b feature/<task_id>-<description>\nworktree: ./scripts/worktree_manager.sh create <project> <minister_type> feature/<branch>"}
EOF
