#!/bin/bash
# subagent-inject.sh — L3: 官僚へのルール注入
# イベント: SubagentStart
# 官僚の起動時に TDD ルール・worktree ルール等をコンテキスト注入

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOOK_DIR/lib/project_phase.sh"

# サブエージェント情報を stdin から読み取り
INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('agent_type',''))" 2>/dev/null || echo "")

# 統制対象プロジェクトがあるか確認
HAS_GOV_PROJECTS=false
for dir in "$CABINET_BASE/projects"/*/; do
    if [ -f "${dir}PROJECT.yaml" ]; then
        HAS_GOV_PROJECTS=true
        break
    fi
done

# 統制対象プロジェクトがなければ何も注入しない
if [ "$HAS_GOV_PROJECTS" = false ]; then
    exit 0
fi

# Growth/Maintenance のプロジェクトがあるか確認
HAS_ACTIVE_GOV=false
ACTIVE_PHASE="genesis"
for dir in "$CABINET_BASE/projects"/*/; do
    if [ -f "${dir}PROJECT.yaml" ]; then
        local_project=$(basename "$dir")
        local_phase=$(get_phase "$local_project")
        if [ "$local_phase" = "growth" ] || [ "$local_phase" = "maintenance" ]; then
            HAS_ACTIVE_GOV=true
            ACTIVE_PHASE="$local_phase"
            break
        fi
    fi
done

# Genesis のみなら最低限のルールのみ
if [ "$HAS_ACTIVE_GOV" = false ]; then
    exit 0
fi

# --- ルール注入 ---
RULES=""

# 全官僚共通ルール
RULES="[統制] メインworktreeでの直接編集禁止。worktree で作業してください。git push は大臣経由で実行。"

# エージェントタイプ別ルール
case "$AGENT_TYPE" in
    *implement*|*code*|*develop*)
        # 実装系官僚
        if [ "$ACTIVE_PHASE" = "growth" ] || [ "$ACTIVE_PHASE" = "maintenance" ]; then
            RULES="$RULES [TDD] テスト先行必須: テスト → 実装 → リファクタ。テストなしコミットは chore: のみ許可。Conventional Commit 形式を使用。"
        fi
        if [ "$ACTIVE_PHASE" = "maintenance" ]; then
            RULES="$RULES [Maintenance] 実装完了前に /release-ready でセルフレビューを実行すること。"
        fi
        ;;
    *review*|*qa*)
        # QA系官僚
        RULES="$RULES [QA] レビュー観点: セキュリティ、パフォーマンス、エラーハンドリング、リリーススペック準拠。"
        ;;
    *explore*|*plan*|*research*)
        # 調査系官僚
        RULES="$RULES [調査] 読み取り専用。ファイル変更禁止。"
        ;;
esac

# release/* ブランチ上ならスコープガード追加
# （CWD からブランチを推定する手段が限られるため、ルールとして注入）
RULES="$RULES [Scope] release/* ブランチではリリーススペック内の変更のみ許可。"

# JSON で返す
cat <<EOF
{"message": "$RULES"}
EOF
