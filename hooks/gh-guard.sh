#!/bin/bash
# gh-guard.sh — L5: PR 自己承認・main 直接マージ防止
# イベント: PreToolUse (Bash)
# gh / curl コマンドの GitHub API 操作を検証

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOOK_DIR/lib/project_phase.sh"

# ツール入力を stdin から読み取り
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# --- ファストパス ---
# gh / curl でなければ即 allow
case "$COMMAND" in
    gh\ *|curl\ *)
        ;;
    *)
        exit 0
        ;;
esac

# PR 自己承認防止
if echo "$COMMAND" | grep -qE "gh\s+pr\s+review\s+--approve"; then
    cat <<EOF
{"decision": "deny", "message": "自己承認は禁止されています。別のエージェント（QA大臣）にレビューを依頼してください。"}
EOF
    exit 0
fi

# main/master への直接マージ防止
if echo "$COMMAND" | grep -qE "gh\s+pr\s+merge" && echo "$COMMAND" | grep -qE "\b(main|master)\b"; then
    cat <<EOF
{"decision": "deny", "message": "main/master への直接マージは禁止されています。develop ブランチ経由でマージしてください。"}
EOF
    exit 0
fi

# GitHub merge API via curl 防止
if echo "$COMMAND" | grep -qE "curl.*api\.github\.com.*/merges|curl.*api\.github\.com.*/pulls/.*/merge"; then
    cat <<EOF
{"decision": "deny", "message": "GitHub API 経由の直接マージは禁止されています。gh pr merge コマンドを使用してください。"}
EOF
    exit 0
fi

# 問題なし
exit 0
