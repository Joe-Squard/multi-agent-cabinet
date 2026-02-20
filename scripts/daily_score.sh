#!/bin/bash
# daily_score.sh - 品質メトリクス生成
# 使い方:
#   daily_score.sh <project>     # プロジェクトの品質スコアを表示
#   daily_score.sh all           # 全プロジェクトのスコアを表示

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$BASE_DIR/hooks/lib/project_phase.sh"

DATE=$(date +%Y-%m-%d)

# -------------------------------------------------------------------
# プロジェクトのスコアを計算
# -------------------------------------------------------------------
calc_score() {
    local project="$1"
    local project_dir="$BASE_DIR/projects/$project"
    local phase
    phase=$(get_phase "$project")

    if [ -z "$phase" ]; then
        echo "統制未設定: $project"
        return 1
    fi

    echo "=== Daily Score: $project ($DATE) ==="
    echo "フェーズ: $phase"
    echo ""

    local total_score=0
    local max_score=0

    # 1. テストカバレッジ（テストファイルの存在）
    local test_files=0
    if [ -d "$project_dir" ]; then
        test_files=$(find "$project_dir" -name "*.test.*" -o -name "*.spec.*" -o -name "test_*" 2>/dev/null | wc -l)
    fi
    local test_score=0
    [ "$test_files" -gt 0 ] && test_score=1
    [ "$test_files" -gt 5 ] && test_score=2
    [ "$test_files" -gt 10 ] && test_score=3
    echo "  テスト: $test_score/3 ($test_files ファイル)"
    total_score=$((total_score + test_score))
    max_score=$((max_score + 3))

    # 2. Conventional Commit 準拠率
    local total_commits=0
    local conventional_commits=0
    if [ -d "$project_dir/.git" ]; then
        total_commits=$(cd "$project_dir" && git log --oneline --since="7 days ago" 2>/dev/null | wc -l)
        conventional_commits=$(cd "$project_dir" && git log --oneline --since="7 days ago" 2>/dev/null | grep -cE "^[a-f0-9]+ (feat|fix|refactor|test|docs|style|perf|chore|ci|build)" || true)
        conventional_commits=${conventional_commits:-0}
    fi
    local commit_score=0
    if [ "$total_commits" -gt 0 ]; then
        local ratio=$((conventional_commits * 100 / total_commits))
        [ "$ratio" -gt 30 ] && commit_score=1
        [ "$ratio" -gt 60 ] && commit_score=2
        [ "$ratio" -gt 90 ] && commit_score=3
    fi
    echo "  Conventional Commit: $commit_score/3 ($conventional_commits/$total_commits)"
    total_score=$((total_score + commit_score))
    max_score=$((max_score + 3))

    # 3. レビュー完了率
    local pending_reviews=0
    local completed_reviews=0
    pending_reviews=$(find "$BASE_DIR/runtime/pending_reviews" -name "${project}_*.yaml" 2>/dev/null | wc -l)
    completed_reviews=$(find "$BASE_DIR/runtime/reviews" -name "${project}_*.approved" 2>/dev/null | wc -l)
    local review_score=0
    if [ "$pending_reviews" -eq 0 ] && [ "$completed_reviews" -gt 0 ]; then
        review_score=3
    elif [ "$pending_reviews" -lt 2 ]; then
        review_score=2
    elif [ "$pending_reviews" -lt 5 ]; then
        review_score=1
    fi
    echo "  レビュー: $review_score/3 (pending: $pending_reviews, completed: $completed_reviews)"
    total_score=$((total_score + review_score))
    max_score=$((max_score + 3))

    # 4. 統制成果物の完備度
    local gov_score=0
    [ -f "$project_dir/PROJECT.yaml" ] && gov_score=$((gov_score + 1))
    [ -f "$project_dir/VISION.md" ] && gov_score=$((gov_score + 1))
    [ -f "$project_dir/DECISIONS.md" ] && gov_score=$((gov_score + 1))
    echo "  統制成果物: $gov_score/3"
    total_score=$((total_score + gov_score))
    max_score=$((max_score + 3))

    echo ""
    echo "  総合スコア: $total_score/$max_score"

    # スコアをランタイムに記録
    mkdir -p "$BASE_DIR/runtime/scores"
    echo "$DATE: $total_score/$max_score" >> "$BASE_DIR/runtime/scores/${project}_daily.log"
}

# -------------------------------------------------------------------
# メインディスパッチ
# -------------------------------------------------------------------
case "${1:-all}" in
    all)
        for dir in "$BASE_DIR/projects"/*/; do
            if [ -f "${dir}PROJECT.yaml" ]; then
                calc_score "$(basename "$dir")"
                echo ""
            fi
        done
        ;;
    help|--help|-h)
        echo "daily_score.sh - 品質メトリクス生成"
        echo ""
        echo "使い方:"
        echo "  $0 <project>  プロジェクトの品質スコアを表示"
        echo "  $0 all        全プロジェクトのスコアを表示"
        ;;
    *)
        calc_score "$1"
        ;;
esac
