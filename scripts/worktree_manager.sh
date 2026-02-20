#!/bin/bash
# worktree_manager.sh - Git worktree 管理（大臣×プロジェクト単位）
# 使い方:
#   worktree_manager.sh create <project> <minister_type> [branch_name]
#   worktree_manager.sh switch <project> <minister_type> <branch_name>
#   worktree_manager.sh list [project]
#   worktree_manager.sh cleanup <project> [minister_type]
#   worktree_manager.sh status <project> <minister_type>
#
# Worktree 戦略:
#   1大臣 × 1プロジェクト = 1 worktree（使い回し）
#   .worktrees/<project>/<minister_type>/
#   deps install は初回のみ、ブランチ切り替えで再利用

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKTREES_DIR="$BASE_DIR/.worktrees"

mkdir -p "$WORKTREES_DIR"

# -------------------------------------------------------------------
# create: worktree を作成（大臣×プロジェクト単位）
# -------------------------------------------------------------------
cmd_create() {
    local project="$1"
    local minister_type="$2"
    local branch_name="${3:-""}"
    local project_dir="$BASE_DIR/projects/$project"
    local worktree_path="$WORKTREES_DIR/$project/$minister_type"

    if [ ! -d "$project_dir/.git" ]; then
        echo "エラー: $project_dir は git リポジトリではありません" >&2
        exit 1
    fi

    # 既に worktree が存在する場合
    if [ -d "$worktree_path" ]; then
        echo "worktree は既に存在します: $worktree_path"
        if [ -n "$branch_name" ]; then
            echo "ブランチを切り替えます: $branch_name"
            cmd_switch "$project" "$minister_type" "$branch_name"
        fi
        return 0
    fi

    # ブランチ名が指定されていなければ develop から作成
    if [ -z "$branch_name" ]; then
        branch_name="develop"
    fi

    mkdir -p "$(dirname "$worktree_path")"

    # worktree 作成
    (
        cd "$project_dir"
        # ブランチが存在しなければ作成
        if ! git rev-parse --verify "$branch_name" &>/dev/null; then
            # develop が存在しなければ main/master から作成
            local base_branch
            base_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
            git branch "$branch_name" "$base_branch" 2>/dev/null || true
        fi
        git worktree add "$worktree_path" "$branch_name"
    )

    echo ""
    echo "worktree 作成完了:"
    echo "  パス     : $worktree_path"
    echo "  ブランチ : $branch_name"
    echo "  プロジェクト: $project"
    echo "  大臣     : $minister_type"

    # deps install が必要かチェック
    _maybe_install_deps "$worktree_path"
}

# -------------------------------------------------------------------
# switch: 既存 worktree でブランチを切り替え
# -------------------------------------------------------------------
cmd_switch() {
    local project="$1"
    local minister_type="$2"
    local branch_name="$3"
    local project_dir="$BASE_DIR/projects/$project"
    local worktree_path="$WORKTREES_DIR/$project/$minister_type"

    if [ ! -d "$worktree_path" ]; then
        echo "worktree が存在しません。create で作成してください: $worktree_path" >&2
        exit 1
    fi

    (
        cd "$project_dir"
        # ブランチが存在しなければ作成
        if ! git rev-parse --verify "$branch_name" &>/dev/null; then
            local develop_branch="develop"
            if git rev-parse --verify "$develop_branch" &>/dev/null; then
                git branch "$branch_name" "$develop_branch"
            else
                local base_branch
                base_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
                git branch "$branch_name" "$base_branch"
            fi
        fi
    )

    (
        cd "$worktree_path"
        git checkout "$branch_name"
    )

    echo "ブランチ切り替え完了: $worktree_path → $branch_name"
}

# -------------------------------------------------------------------
# list: worktree の一覧表示
# -------------------------------------------------------------------
cmd_list() {
    local project="${1:-""}"

    if [ -n "$project" ]; then
        local project_dir="$BASE_DIR/projects/$project"
        if [ -d "$project_dir/.git" ]; then
            (cd "$project_dir" && git worktree list)
        else
            echo "プロジェクト $project は git リポジトリではありません" >&2
        fi
    else
        # 全プロジェクトの worktree を表示
        echo "=== Worktree 一覧 ==="
        echo ""
        if [ ! -d "$WORKTREES_DIR" ] || [ -z "$(ls -A "$WORKTREES_DIR" 2>/dev/null)" ]; then
            echo "worktree はありません"
            return 0
        fi
        for proj_dir in "$WORKTREES_DIR"/*/; do
            local proj_name
            proj_name=$(basename "$proj_dir")
            echo "[$proj_name]"
            for minister_dir in "$proj_dir"*/; do
                if [ -d "$minister_dir" ]; then
                    local minister
                    minister=$(basename "$minister_dir")
                    local branch
                    branch=$(cd "$minister_dir" && git branch --show-current 2>/dev/null || echo "???")
                    echo "  $minister → $branch"
                fi
            done
            echo ""
        done
    fi
}

# -------------------------------------------------------------------
# cleanup: worktree を削除
# -------------------------------------------------------------------
cmd_cleanup() {
    local project="$1"
    local minister_type="${2:-""}"
    local project_dir="$BASE_DIR/projects/$project"

    if [ ! -d "$project_dir/.git" ]; then
        echo "エラー: $project_dir は git リポジトリではありません" >&2
        exit 1
    fi

    if [ -n "$minister_type" ]; then
        # 特定の大臣の worktree を削除
        local worktree_path="$WORKTREES_DIR/$project/$minister_type"
        if [ -d "$worktree_path" ]; then
            (cd "$project_dir" && git worktree remove "$worktree_path" --force 2>/dev/null || true)
            rm -rf "$worktree_path"
            echo "削除: $worktree_path"
        else
            echo "worktree が存在しません: $worktree_path"
        fi
    else
        # プロジェクトの全 worktree を削除
        local worktrees_project_dir="$WORKTREES_DIR/$project"
        if [ -d "$worktrees_project_dir" ]; then
            for minister_dir in "$worktrees_project_dir"/*/; do
                if [ -d "$minister_dir" ]; then
                    (cd "$project_dir" && git worktree remove "$minister_dir" --force 2>/dev/null || true)
                    rm -rf "$minister_dir"
                    echo "削除: $minister_dir"
                fi
            done
            rmdir "$worktrees_project_dir" 2>/dev/null || true
            echo "プロジェクト $project の全 worktree を削除しました"
        else
            echo "プロジェクト $project の worktree はありません"
        fi
    fi

    # git worktree prune
    (cd "$project_dir" && git worktree prune 2>/dev/null || true)
}

# -------------------------------------------------------------------
# status: worktree の状態を表示
# -------------------------------------------------------------------
cmd_status() {
    local project="$1"
    local minister_type="$2"
    local worktree_path="$WORKTREES_DIR/$project/$minister_type"

    if [ ! -d "$worktree_path" ]; then
        echo "worktree なし: $project / $minister_type"
        return 1
    fi

    echo "=== Worktree Status ==="
    echo "プロジェクト: $project"
    echo "大臣: $minister_type"
    echo "パス: $worktree_path"
    (
        cd "$worktree_path"
        echo "ブランチ: $(git branch --show-current 2>/dev/null || echo '???')"
        echo "状態:"
        git status --short 2>/dev/null || echo "  (git status 取得失敗)"
    )
}

# -------------------------------------------------------------------
# _maybe_install_deps: deps install が必要かチェック・実行
# -------------------------------------------------------------------
_maybe_install_deps() {
    local worktree_path="$1"

    if [ -f "$worktree_path/package.json" ] && [ ! -d "$worktree_path/node_modules" ]; then
        echo "node_modules が見つかりません。npm install を実行中..."
        (cd "$worktree_path" && npm install --silent 2>/dev/null) || true
    fi

    if [ -f "$worktree_path/requirements.txt" ] && [ ! -d "$worktree_path/.venv" ]; then
        echo "Python venv をセットアップ中..."
        (cd "$worktree_path" && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt -q 2>/dev/null) || true
    fi

    if [ -f "$worktree_path/go.mod" ]; then
        echo "Go modules を取得中..."
        (cd "$worktree_path" && go mod download 2>/dev/null) || true
    fi
}

# -------------------------------------------------------------------
# メインディスパッチ
# -------------------------------------------------------------------
case "${1:-help}" in
    create)
        if [ $# -lt 3 ]; then
            echo "使い方: $0 create <project> <minister_type> [branch_name]" >&2
            exit 1
        fi
        cmd_create "$2" "$3" "${4:-""}"
        ;;
    switch)
        if [ $# -lt 4 ]; then
            echo "使い方: $0 switch <project> <minister_type> <branch_name>" >&2
            exit 1
        fi
        cmd_switch "$2" "$3" "$4"
        ;;
    list)
        cmd_list "${2:-""}"
        ;;
    cleanup)
        if [ $# -lt 2 ]; then
            echo "使い方: $0 cleanup <project> [minister_type]" >&2
            exit 1
        fi
        cmd_cleanup "$2" "${3:-""}"
        ;;
    status)
        if [ $# -lt 3 ]; then
            echo "使い方: $0 status <project> <minister_type>" >&2
            exit 1
        fi
        cmd_status "$2" "$3"
        ;;
    help|*)
        echo "worktree_manager.sh - Git worktree 管理（大臣×プロジェクト単位）"
        echo ""
        echo "使い方:"
        echo "  $0 create <project> <minister_type> [branch_name]"
        echo "  $0 switch <project> <minister_type> <branch_name>"
        echo "  $0 list [project]"
        echo "  $0 cleanup <project> [minister_type]"
        echo "  $0 status <project> <minister_type>"
        echo ""
        echo "例:"
        echo "  $0 create my-app fe                    # FE大臣用 worktree 作成"
        echo "  $0 create my-app fe feature/login      # ブランチ指定で作成"
        echo "  $0 switch my-app fe feature/new-task   # ブランチ切り替え"
        echo "  $0 list                                # 全 worktree 一覧"
        echo "  $0 cleanup my-app                      # プロジェクトの全 worktree 削除"
        echo "  $0 cleanup my-app fe                   # FE大臣の worktree のみ削除"
        ;;
esac
