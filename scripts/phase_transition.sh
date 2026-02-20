#!/bin/bash
# phase_transition.sh - フェーズ遷移
# 使い方:
#   phase_transition.sh <project> <target_phase>
#   phase_transition.sh <project> status
#   phase_transition.sh list
#
# 例:
#   phase_transition.sh my-app growth        # Genesis → Growth に遷移
#   phase_transition.sh my-app maintenance   # Growth → Maintenance に遷移
#   phase_transition.sh my-app status        # 現在のフェーズを表示
#   phase_transition.sh list                 # 全プロジェクトのフェーズ一覧

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$BASE_DIR/hooks/lib/project_phase.sh"

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# -------------------------------------------------------------------
# show_phase_badge: フェーズをカラー表示
# -------------------------------------------------------------------
show_phase_badge() {
    local phase="$1"
    case "$phase" in
        genesis)     echo -e "${GREEN}[Genesis]${NC}" ;;
        growth)      echo -e "${YELLOW}[Growth]${NC}" ;;
        maintenance) echo -e "${RED}[Maintenance]${NC}" ;;
        *)           echo -e "[$phase]" ;;
    esac
}

# -------------------------------------------------------------------
# show_checklist: 遷移前チェックリスト表示
# -------------------------------------------------------------------
show_checklist() {
    local from_phase="$1"
    local to_phase="$2"
    local config="$BASE_DIR/config/governance_defaults.yaml"

    echo ""
    echo -e "${CYAN}=== フェーズ遷移チェックリスト ===${NC}"
    echo -e "  $(show_phase_badge "$from_phase") → $(show_phase_badge "$to_phase")"
    echo ""

    if [ "$to_phase" = "growth" ]; then
        echo "  以下を確認してください:"
        echo "  [ ] MVP が動作する状態である"
        echo "  [ ] ユーザー（天皇）に公開可能な品質である"
        echo "  [ ] 主要機能が一通り実装されている"
        echo "  [ ] テスト基盤が整っている（テストランナー設定済み）"
        echo ""
        echo "  遷移時に自動実行されるアクション:"
        echo "  - develop ブランチを作成"
        echo "  - 大臣別 worktree をセットアップ可能に"
        echo "  - Hook が L4（警告）レベルで発動開始"
    elif [ "$to_phase" = "maintenance" ]; then
        echo "  以下を確認してください:"
        echo "  [ ] リリースが安定している（週次リリース可能）"
        echo "  [ ] 破壊的変更の頻度が減少している"
        echo "  [ ] SLA やパフォーマンス要件が存在する"
        echo "  [ ] ユーザーが日常的に利用している"
        echo ""
        echo "  遷移時に自動実行されるアクション:"
        echo "  - Hook が L5（ブロック）レベルで発動開始"
        echo "  - セルフレビューが必須化"
        echo "  - クロス大臣レビューが有効化"
        echo "  - Debate Partner が有効化"
    fi
    echo ""
}

# -------------------------------------------------------------------
# do_transition: フェーズ遷移を実行
# -------------------------------------------------------------------
do_transition() {
    local project="$1"
    local target_phase="$2"
    local project_dir="$BASE_DIR/projects/$project"
    local project_yaml="$project_dir/PROJECT.yaml"

    # バリデーション
    if [ ! -f "$project_yaml" ]; then
        echo -e "${RED}エラー: PROJECT.yaml が見つかりません: $project_yaml${NC}" >&2
        echo "先に project_init.sh で開発統制を初期化してください。" >&2
        exit 1
    fi

    local current_phase
    current_phase=$(get_phase "$project")

    if [ -z "$current_phase" ]; then
        echo -e "${RED}エラー: 現在のフェーズを取得できません${NC}" >&2
        exit 1
    fi

    # 遷移バリデーション（逆行禁止）
    case "$current_phase→$target_phase" in
        "genesis→growth"|"growth→maintenance")
            # 正常な遷移
            ;;
        "genesis→maintenance")
            echo -e "${RED}エラー: Genesis → Maintenance への直接遷移はできません${NC}" >&2
            echo "先に Growth に遷移してください。" >&2
            exit 1
            ;;
        "$target_phase→$target_phase")
            echo "既に $target_phase フェーズです。"
            exit 0
            ;;
        "growth→genesis"|"maintenance→growth"|"maintenance→genesis")
            echo -e "${RED}エラー: フェーズの逆行はできません ($current_phase → $target_phase)${NC}" >&2
            exit 1
            ;;
        *)
            echo -e "${RED}エラー: 不明なフェーズ遷移: $current_phase → $target_phase${NC}" >&2
            exit 1
            ;;
    esac

    # チェックリスト表示
    show_checklist "$current_phase" "$target_phase"

    # 確認プロンプト
    echo -n "遷移を実行しますか？ (y/N): "
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "キャンセルしました。"
        exit 0
    fi

    echo ""
    echo "フェーズ遷移を実行中..."

    # PROJECT.yaml を更新
    sed -i "s/^phase: .*/phase: \"$target_phase\"/" "$project_yaml"

    # フェーズ固有のアクション
    case "$target_phase" in
        growth)
            _transition_to_growth "$project" "$project_dir"
            ;;
        maintenance)
            _transition_to_maintenance "$project" "$project_dir"
            ;;
    esac

    # キャッシュクリア
    clear_phase_cache "$project"

    echo ""
    echo -e "${GREEN}フェーズ遷移完了:${NC} $(show_phase_badge "$current_phase") → $(show_phase_badge "$target_phase")"
    echo ""
    echo "プロジェクト: $project"
    echo "新しいフェーズ: $target_phase"
}

# -------------------------------------------------------------------
# _transition_to_growth: Growth 遷移時のアクション
# -------------------------------------------------------------------
_transition_to_growth() {
    local project="$1"
    local project_dir="$2"

    (
        cd "$project_dir"

        # develop ブランチ作成
        if ! git rev-parse --verify develop &>/dev/null; then
            # コミットが存在するか確認
            if git rev-parse HEAD &>/dev/null; then
                local base_branch
                base_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
                git branch develop "$base_branch"
                echo "  develop ブランチを作成しました"
            else
                echo "  警告: コミットがありません。最初のコミット後に develop ブランチを作成してください"
                echo "  (git checkout -b develop)"
            fi
        else
            echo "  develop ブランチは既に存在します"
        fi

        # PROJECT.yaml の branches.develop を更新
        if grep -q "^  develop:" "$project_dir/PROJECT.yaml" 2>/dev/null; then
            sed -i 's/^  develop: .*/  develop: "develop"/' "$project_dir/PROJECT.yaml"
        fi
    )

    echo "  Hook L4（警告）が有効になりました"
    echo "  worktree での作業が推奨されます: ./scripts/worktree_manager.sh create $project <minister_type>"
}

# -------------------------------------------------------------------
# _transition_to_maintenance: Maintenance 遷移時のアクション
# -------------------------------------------------------------------
_transition_to_maintenance() {
    local project="$1"
    local project_dir="$2"

    echo "  Hook L5（ブロック）が有効になりました"
    echo "  セルフレビュー（/release-ready）が必須になりました"
    echo "  クロス大臣レビューが有効になりました"
    echo "  main への直接コミットはブロックされます"
}

# -------------------------------------------------------------------
# show_status: プロジェクトのフェーズ状態を表示
# -------------------------------------------------------------------
show_status() {
    local project="$1"
    local project_dir="$BASE_DIR/projects/$project"
    local project_yaml="$project_dir/PROJECT.yaml"

    if [ ! -f "$project_yaml" ]; then
        echo "プロジェクト $project は統制未設定です"
        return 1
    fi

    local phase
    phase=$(get_phase "$project")
    local created
    created=$(grep "^created:" "$project_yaml" 2>/dev/null | awk -F': ' '{print $2}' | tr -d '"')

    echo "=== $project ==="
    echo "  フェーズ : $(show_phase_badge "$phase")"
    echo "  作成日   : $created"

    case "$phase" in
        genesis)
            echo "  強制レベル: L2（提案のみ）"
            echo "  次の遷移 : ./scripts/phase_transition.sh $project growth"
            ;;
        growth)
            echo "  強制レベル: L4（警告）"
            echo "  次の遷移 : ./scripts/phase_transition.sh $project maintenance"
            ;;
        maintenance)
            echo "  強制レベル: L5（ブロック）"
            echo "  （最終フェーズ）"
            ;;
    esac

    # worktree 状態
    local worktrees_dir="$BASE_DIR/.worktrees/$project"
    if [ -d "$worktrees_dir" ]; then
        echo "  worktree :"
        for minister_dir in "$worktrees_dir"/*/; do
            if [ -d "$minister_dir" ]; then
                local minister branch
                minister=$(basename "$minister_dir")
                branch=$(cd "$minister_dir" && git branch --show-current 2>/dev/null || echo "???")
                echo "    $minister → $branch"
            fi
        done
    fi
}

# -------------------------------------------------------------------
# list_projects: 全プロジェクトのフェーズ一覧
# -------------------------------------------------------------------
cmd_list() {
    echo "=== 統制対象プロジェクト一覧 ==="
    echo ""

    local found=false
    for dir in "$BASE_DIR/projects"/*/; do
        if [ -f "${dir}PROJECT.yaml" ]; then
            found=true
            local name
            name=$(basename "$dir")
            show_status "$name"
            echo ""
        fi
    done

    if [ "$found" = false ]; then
        echo "統制対象のプロジェクトはありません。"
        echo "初期化: ./scripts/project_init.sh <project_name>"
    fi
}

# -------------------------------------------------------------------
# メインディスパッチ
# -------------------------------------------------------------------
case "${1:-help}" in
    list)
        cmd_list
        ;;
    help|--help|-h)
        echo "phase_transition.sh - フェーズ遷移"
        echo ""
        echo "使い方:"
        echo "  $0 <project> <target_phase>    フェーズを遷移"
        echo "  $0 <project> status            現在のフェーズを表示"
        echo "  $0 list                        全プロジェクトの一覧"
        echo ""
        echo "フェーズ:"
        echo "  genesis     → L2: 提案のみ（最大速度）"
        echo "  growth      → L4: 警告（品質と速度のバランス）"
        echo "  maintenance → L5: ブロック（品質最優先）"
        echo ""
        echo "例:"
        echo "  $0 my-app growth        Genesis → Growth に遷移"
        echo "  $0 my-app maintenance   Growth → Maintenance に遷移"
        echo "  $0 my-app status        現在のフェーズを確認"
        ;;
    *)
        PROJECT="$1"
        ACTION="${2:-status}"

        case "$ACTION" in
            status)
                show_status "$PROJECT"
                ;;
            genesis|growth|maintenance)
                do_transition "$PROJECT" "$ACTION"
                ;;
            *)
                echo "不明なアクション: $ACTION" >&2
                echo "使い方: $0 <project> <genesis|growth|maintenance|status>" >&2
                exit 1
                ;;
        esac
        ;;
esac
