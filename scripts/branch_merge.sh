#!/bin/bash
# branch_merge.sh - フェーズ対応ブランチマージ
# 使い方:
#   branch_merge.sh <project> <source_branch> <target_branch> [--squash]
#
# フェーズに応じたマージルールを適用

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$BASE_DIR/hooks/lib/project_phase.sh"

if [ $# -lt 3 ]; then
    echo "使い方: $0 <project> <source_branch> <target_branch> [--squash]" >&2
    exit 1
fi

PROJECT="$1"
SOURCE="$2"
TARGET="$3"
SQUASH="${4:-""}"

PROJECT_DIR="$BASE_DIR/projects/$PROJECT"
PHASE=$(get_phase "$PROJECT")

# フェーズ別マージルール
case "$TARGET" in
    main|master)
        if [ "$PHASE" = "growth" ] || [ "$PHASE" = "maintenance" ]; then
            echo "エラー: $PHASE フェーズでは main への直接マージは禁止です" >&2
            echo "develop → main は天皇（ユーザー）の承認が必要です" >&2
            exit 1
        fi
        ;;
    develop)
        # QA 承認チェック
        REVIEW_ID="${PROJECT}_$(echo "$SOURCE" | tr '/' '_')"
        APPROVED_FILE="$BASE_DIR/runtime/reviews/${REVIEW_ID}.approved"
        if [ "$PHASE" != "genesis" ] && [ ! -f "$APPROVED_FILE" ]; then
            echo "エラー: QA 承認が完了していません: $SOURCE" >&2
            echo "QA レビューを先に完了させてください" >&2
            exit 1
        fi
        ;;
esac

# マージ実行
(
    cd "$PROJECT_DIR"

    # ターゲットブランチに切り替え
    git checkout "$TARGET"

    # マージ
    if [ "$SQUASH" = "--squash" ]; then
        git merge --squash "$SOURCE"
        echo "squash merge 完了: $SOURCE → $TARGET"
        echo "コミットメッセージを入力して git commit を実行してください"
    else
        git merge "$SOURCE" --no-edit
        echo "マージ完了: $SOURCE → $TARGET"
    fi
)

# レビュー済みファイルを記録
REVIEW_ID="${PROJECT}_$(echo "$SOURCE" | tr '/' '_')"
rm -f "$BASE_DIR/runtime/pending_reviews/${REVIEW_ID}.yaml" 2>/dev/null || true
