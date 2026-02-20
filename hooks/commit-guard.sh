#!/bin/bash
# commit-guard.sh — L5/L4: 危険な git 操作ブロック
# イベント: PreToolUse (Bash)
# git コマンドの安全性を検証

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOOK_DIR/lib/project_phase.sh"

# ツール入力を stdin から読み取り
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# --- ファストパス ---
# git コマンドでなければ即 allow
case "$COMMAND" in
    git\ *|git\ *)
        ;;
    *)
        exit 0
        ;;
esac

# projects/ 配下のプロジェクトを推定（cd コマンドから）
PROJECT=""
if echo "$COMMAND" | grep -qE "projects/[^/]+"; then
    PROJECT=$(echo "$COMMAND" | grep -oE "projects/[^/]+" | head -1 | sed 's|projects/||')
fi

# CWD からもプロジェクト推定を試みる（worktree内の場合）
if [ -z "$PROJECT" ]; then
    CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || echo "")
    if [ -n "$CWD" ]; then
        # .worktrees/<project>/<minister>/ パターン
        if echo "$CWD" | grep -qE "\.worktrees/[^/]+"; then
            PROJECT=$(echo "$CWD" | grep -oE "\.worktrees/[^/]+" | sed 's|\.worktrees/||')
        fi
        PROJECT=${PROJECT:-$(detect_project "$CWD")}
    fi
fi

# プロジェクト不明 or 統制未設定 → allow
if [ -z "$PROJECT" ]; then
    exit 0
fi

PHASE=$(get_phase "$PROJECT")
if [ -z "$PHASE" ] || [ "$PHASE" = "genesis" ]; then
    exit 0
fi

# --- Growth/Maintenance チェック ---

# --no-verify ブロック（常に）
if echo "$COMMAND" | grep -q "\-\-no-verify"; then
    cat <<EOF
{"decision": "deny", "message": "[$PHASE] --no-verify は禁止されています。pre-commit hook をスキップしないでください。"}
EOF
    exit 0
fi

# git push --force to main/master ブロック
if echo "$COMMAND" | grep -qE "git\s+push.*--force|git\s+push.*-f" && echo "$COMMAND" | grep -qE "\b(main|master)\b"; then
    cat <<EOF
{"decision": "deny", "message": "[$PHASE] main/master への force push は禁止されています。"}
EOF
    exit 0
fi

# main/develop への直接コミット（Growth/Maintenance）
if echo "$COMMAND" | grep -qE "git\s+commit"; then
    # 現在のブランチを確認する必要があるが、Hook では CWD のブランチを直接確認できない
    # branch-reminder で補完するため、ここでは --no-verify のみブロック
    :
fi

# Conventional commit チェック（Growth: warning / Maintenance: deny）
if echo "$COMMAND" | grep -qE "git\s+commit\s+-m"; then
    COMMIT_MSG=$(echo "$COMMAND" | grep -oP '(?<=-m\s")[^"]*|(?<=-m\s'"'"')[^'"'"']*' | head -1)
    if [ -n "$COMMIT_MSG" ]; then
        if ! echo "$COMMIT_MSG" | grep -qE "^(feat|fix|refactor|test|docs|style|perf|chore|ci|build)(\(.+\))?!?:"; then
            LEVEL="warning"
            [ "$PHASE" = "maintenance" ] && LEVEL="deny"
            cat <<EOF
{"decision": "$LEVEL", "message": "[$PHASE] Conventional Commit 形式を使用してください。\n形式: <type>(<scope>): <description>\n例: feat(auth): add login endpoint\n許可: feat|fix|refactor|test|docs|style|perf|chore|ci|build"}
EOF
            exit 0
        fi
    fi
fi

# git branch -D develop ブロック
if echo "$COMMAND" | grep -qE "git\s+branch\s+-[dD].*develop"; then
    cat <<EOF
{"decision": "deny", "message": "[$PHASE] develop ブランチの削除は禁止されています。"}
EOF
    exit 0
fi

# 問題なし
exit 0
