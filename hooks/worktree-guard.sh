#!/bin/bash
# worktree-guard.sh — L5: メインworktreeでのファイル編集ブロック
# イベント: PreToolUse (Write|Edit)
# Growth/Maintenance プロジェクト内のファイルがメインworktreeで編集されようとしたら deny

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOOK_DIR/lib/project_phase.sh"

# ツール入力を stdin から読み取り
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")

# ファイルパスが取得できなければ allow
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# --- ファストパス ---
# 1. projects/ 配下でなければ即 allow
PROJECT=$(detect_project "$FILE_PATH")
if [ -z "$PROJECT" ]; then
    exit 0
fi

# 2. フェーズ取得（キャッシュ付き）
PHASE=$(get_phase "$PROJECT")
if [ -z "$PHASE" ]; then
    exit 0  # 統制未設定 → allow
fi

# 3. Genesis なら即 allow
if [ "$PHASE" = "genesis" ]; then
    exit 0
fi

# --- Growth/Maintenance チェック ---

# 4. 除外パス（PROJECT.yaml, VISION.md 等は直接編集可）
if is_excluded_path "$FILE_PATH"; then
    exit 0
fi

# 5. .cabinet/ 配下は直接編集可（リリーススペック等）
case "$FILE_PATH" in
    */.cabinet/*)
        exit 0
        ;;
esac

# 6. .worktrees/ 配下なら allow（正しい作業場所）
case "$FILE_PATH" in
    */.worktrees/*)
        exit 0
        ;;
esac

# 7. → deny: メインworktreeでの編集をブロック
LEVEL="warning"
if [ "$PHASE" = "maintenance" ]; then
    LEVEL="deny"
fi

cat <<EOF
{"decision": "$LEVEL", "message": "[$PHASE] worktree で作業してください。メインworktreeでの直接編集は${PHASE}フェーズでは許可されていません。\nworktree作成: ./scripts/worktree_manager.sh create $PROJECT <minister_type>"}
EOF
