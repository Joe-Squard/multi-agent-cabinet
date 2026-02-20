#!/bin/bash
# release_manager.sh - リリースライフサイクル管理
# 使い方:
#   release_manager.sh create <project> <version> [--from develop]
#   release_manager.sh status <project>
#   release_manager.sh finalize <project> <version>
#   release_manager.sh hotfix <project> <version>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$BASE_DIR/hooks/lib/project_phase.sh"

# -------------------------------------------------------------------
# create: リリースブランチ作成
# -------------------------------------------------------------------
cmd_create() {
    local project="$1"
    local version="$2"
    local from_branch="${3:-develop}"
    local project_dir="$BASE_DIR/projects/$project"
    local phase
    phase=$(get_phase "$project")

    if [ "$phase" != "maintenance" ]; then
        echo "警告: リリースブランチは Maintenance フェーズ推奨です（現在: $phase）"
    fi

    if [ ! -d "$project_dir/.git" ]; then
        echo "エラー: $project は git リポジトリではありません" >&2
        exit 1
    fi

    local release_branch="release/$version"
    local spec_dir="$project_dir/.cabinet/release-specs"
    local spec_file="$spec_dir/$version.md"

    mkdir -p "$spec_dir"

    (
        cd "$project_dir"

        # develop からリリースブランチ作成
        git checkout "$from_branch"
        git pull origin "$from_branch" 2>/dev/null || true
        git checkout -b "$release_branch"

        echo "リリースブランチ作成: $release_branch (from $from_branch)"
    )

    # リリーススペック作成（テンプレートから）
    if [ ! -f "$spec_file" ]; then
        local template="$BASE_DIR/templates/project/release-spec.md"
        if [ -f "$template" ]; then
            sed -e "s/{{RELEASE_NAME}}/$version/g" \
                -e "s/{{TASK_ID}}/release/g" \
                -e "s/{{DESCRIPTION}}/$version/g" \
                -e "s/{{MINISTER}}/PM/g" \
                "$template" > "$spec_file"
            echo "リリーススペック作成: $spec_file"
        fi
    fi

    echo ""
    echo "リリース準備完了:"
    echo "  ブランチ : $release_branch"
    echo "  スペック : $spec_file"
    echo ""
    echo "次のステップ:"
    echo "  1. リリーススペックを編集して受入条件を定義"
    echo "  2. 実装・テスト"
    echo "  3. ./scripts/release_manager.sh finalize $project $version"
}

# -------------------------------------------------------------------
# status: リリース状態を表示
# -------------------------------------------------------------------
cmd_status() {
    local project="$1"
    local project_dir="$BASE_DIR/projects/$project"

    echo "=== リリース状態: $project ==="

    if [ ! -d "$project_dir/.git" ]; then
        echo "git リポジトリではありません"
        return 1
    fi

    (
        cd "$project_dir"

        # リリースブランチ一覧
        echo ""
        echo "リリースブランチ:"
        local releases
        releases=$(git branch --list "release/*" 2>/dev/null | sed 's/^[* ]*//')
        if [ -z "$releases" ]; then
            echo "  (なし)"
        else
            echo "$releases" | while read -r branch; do
                local commits
                commits=$(git log --oneline "develop..$branch" 2>/dev/null | wc -l || echo "?")
                echo "  $branch ($commits commits ahead of develop)"
            done
        fi

        # 最新タグ
        echo ""
        echo "最新タグ:"
        git tag --sort=-version:refname 2>/dev/null | head -5 | while read -r tag; do
            echo "  $tag"
        done
        if [ -z "$(git tag 2>/dev/null)" ]; then
            echo "  (なし)"
        fi
    )

    # リリーススペック
    local spec_dir="$project_dir/.cabinet/release-specs"
    if [ -d "$spec_dir" ]; then
        echo ""
        echo "リリーススペック:"
        ls -1 "$spec_dir"/*.md 2>/dev/null | while read -r spec; do
            echo "  $(basename "$spec")"
        done
    fi
}

# -------------------------------------------------------------------
# finalize: リリースを完了（タグ付け + main マージ準備）
# -------------------------------------------------------------------
cmd_finalize() {
    local project="$1"
    local version="$2"
    local project_dir="$BASE_DIR/projects/$project"
    local release_branch="release/$version"

    (
        cd "$project_dir"

        if ! git rev-parse --verify "$release_branch" &>/dev/null; then
            echo "エラー: ブランチ $release_branch が存在しません" >&2
            exit 1
        fi

        git checkout "$release_branch"

        # タグ作成
        git tag -a "v$version" -m "Release v$version"
        echo "タグ作成: v$version"

        # develop にマージバック
        git checkout develop
        git merge "$release_branch" --no-edit
        echo "develop にマージ完了"

        echo ""
        echo "リリース完了:"
        echo "  タグ: v$version"
        echo "  develop マージ: 完了"
        echo ""
        echo "残りのステップ（天皇の承認が必要）:"
        echo "  1. develop → main のマージ"
        echo "  2. git push origin main develop --tags"
        echo "  3. GitHub Release 作成: gh release create v$version"
    )
}

# -------------------------------------------------------------------
# hotfix: ホットフィックスブランチ作成
# -------------------------------------------------------------------
cmd_hotfix() {
    local project="$1"
    local version="$2"
    local project_dir="$BASE_DIR/projects/$project"

    (
        cd "$project_dir"

        # main からホットフィックスブランチ作成
        local main_branch
        main_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
        git checkout "$main_branch"
        git checkout -b "hotfix/$version"

        echo "ホットフィックスブランチ作成: hotfix/$version (from $main_branch)"
        echo ""
        echo "完了後:"
        echo "  1. main にマージ + タグ付け"
        echo "  2. develop にもマージバック"
    )
}

# -------------------------------------------------------------------
# メインディスパッチ
# -------------------------------------------------------------------
case "${1:-help}" in
    create)
        if [ $# -lt 3 ]; then
            echo "使い方: $0 create <project> <version> [--from develop]" >&2
            exit 1
        fi
        cmd_create "$2" "$3" "${4:-develop}"
        ;;
    status)
        if [ $# -lt 2 ]; then
            echo "使い方: $0 status <project>" >&2
            exit 1
        fi
        cmd_status "$2"
        ;;
    finalize)
        if [ $# -lt 3 ]; then
            echo "使い方: $0 finalize <project> <version>" >&2
            exit 1
        fi
        cmd_finalize "$2" "$3"
        ;;
    hotfix)
        if [ $# -lt 3 ]; then
            echo "使い方: $0 hotfix <project> <version>" >&2
            exit 1
        fi
        cmd_hotfix "$2" "$3"
        ;;
    help|*)
        echo "release_manager.sh - リリースライフサイクル管理"
        echo ""
        echo "使い方:"
        echo "  $0 create <project> <version>   リリースブランチ作成"
        echo "  $0 status <project>             リリース状態を表示"
        echo "  $0 finalize <project> <version> リリース完了（タグ + マージ）"
        echo "  $0 hotfix <project> <version>   ホットフィックス作成"
        echo ""
        echo "例:"
        echo "  $0 create my-app 1.0.0"
        echo "  $0 status my-app"
        echo "  $0 finalize my-app 1.0.0"
        echo "  $0 hotfix my-app 1.0.1"
        ;;
esac
