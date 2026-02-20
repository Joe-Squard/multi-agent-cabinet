#!/bin/bash
# project_phase.sh - プロジェクトフェーズ検出ヘルパー
# 全 Hook から source されて使われる共通ライブラリ
#
# 使い方:
#   source hooks/lib/project_phase.sh
#   detect_project "/path/to/file"    # → project名 or ""
#   get_phase "my-app"                # → genesis|growth|maintenance or ""
#   is_fast_path "/path/to/file"      # → 0 (allow) or 1 (needs check)

HOOK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CABINET_BASE="$(cd "$HOOK_LIB_DIR/../.." && pwd)"
CACHE_DIR="/tmp/cabinet_phase_cache"
CACHE_TTL=600  # 10分

mkdir -p "$CACHE_DIR" 2>/dev/null || true

# -------------------------------------------------------------------
# detect_project <file_path>
# ファイルパスから projects/<name>/ のプロジェクト名を抽出
# projects/ 配下でなければ空文字を返す
# -------------------------------------------------------------------
detect_project() {
    local file_path="$1"
    local projects_dir="$CABINET_BASE/projects"

    # 絶対パスに正規化
    if [[ "$file_path" != /* ]]; then
        file_path="$(cd "$(dirname "$file_path")" 2>/dev/null && pwd)/$(basename "$file_path")"
    fi

    # projects/ 配下かチェック
    if [[ "$file_path" == "$projects_dir/"* ]]; then
        # projects/<name>/... から <name> を抽出
        local rel="${file_path#"$projects_dir/"}"
        echo "${rel%%/*}"
    else
        echo ""
    fi
}

# -------------------------------------------------------------------
# get_phase <project_name>
# PROJECT.yaml の phase フィールドを返す（キャッシュ付き）
# キャッシュは CACHE_TTL 秒有効
# -------------------------------------------------------------------
get_phase() {
    local project="$1"
    local cache_file="$CACHE_DIR/phase_${project}.cache"
    local project_yaml="$CABINET_BASE/projects/$project/PROJECT.yaml"

    # キャッシュチェック
    if [ -f "$cache_file" ]; then
        local cache_age
        local now
        now=$(date +%s)
        cache_age=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        if (( now - cache_age < CACHE_TTL )); then
            cat "$cache_file"
            return 0
        fi
    fi

    # PROJECT.yaml が存在しなければ空（統制未設定）
    if [ ! -f "$project_yaml" ]; then
        echo ""
        return 1
    fi

    # phase を読み取り
    local phase=""
    phase=$(grep -E "^phase:" "$project_yaml" 2>/dev/null | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'" | tr -d ' ')

    if [ -n "$phase" ]; then
        echo "$phase" > "$cache_file"
        echo "$phase"
        return 0
    else
        echo ""
        return 1
    fi
}

# -------------------------------------------------------------------
# clear_phase_cache <project_name>
# フェーズ遷移時にキャッシュをクリア
# -------------------------------------------------------------------
clear_phase_cache() {
    local project="$1"
    rm -f "$CACHE_DIR/phase_${project}.cache" 2>/dev/null || true
}

# -------------------------------------------------------------------
# clear_all_cache
# 全キャッシュをクリア
# -------------------------------------------------------------------
clear_all_cache() {
    rm -f "$CACHE_DIR"/phase_*.cache 2>/dev/null || true
}

# -------------------------------------------------------------------
# is_fast_path <file_path>
# ファストパス判定: projects/ 外 or Genesis なら 0 (allow)
# Growth/Maintenance なら 1 (要チェック)
# -------------------------------------------------------------------
is_fast_path() {
    local file_path="$1"
    local project

    # 1. projects/ 配下でなければ即 allow
    project=$(detect_project "$file_path")
    if [ -z "$project" ]; then
        return 0
    fi

    # 2. PROJECT.yaml がなければ即 allow（統制未設定）
    local phase
    phase=$(get_phase "$project")
    if [ -z "$phase" ]; then
        return 0
    fi

    # 3. Genesis なら即 allow
    if [ "$phase" = "genesis" ]; then
        return 0
    fi

    # 4. Growth/Maintenance → 要チェック
    return 1
}

# -------------------------------------------------------------------
# get_project_config <project_name> <dot_path>
# PROJECT.yaml から任意の設定値を取得
# -------------------------------------------------------------------
get_project_config() {
    local project="$1"
    local key="$2"
    local project_yaml="$CABINET_BASE/projects/$project/PROJECT.yaml"

    if [ ! -f "$project_yaml" ]; then
        echo ""
        return 1
    fi

    grep -E "^${key}:" "$project_yaml" 2>/dev/null | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'"
}

# -------------------------------------------------------------------
# is_excluded_path <file_path>
# worktree-guard で除外するファイル判定
# PROJECT.yaml, VISION.md, DECISIONS.md, .gitignore は直接編集可
# -------------------------------------------------------------------
is_excluded_path() {
    local file_path="$1"
    local basename
    basename=$(basename "$file_path")

    case "$basename" in
        PROJECT.yaml|VISION.md|DECISIONS.md|.gitignore|.cabinet)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

# -------------------------------------------------------------------
# list_governed_projects
# 統制対象プロジェクトの一覧を返す
# -------------------------------------------------------------------
list_governed_projects() {
    local projects_dir="$CABINET_BASE/projects"

    if [ ! -d "$projects_dir" ]; then
        return 0
    fi

    for dir in "$projects_dir"/*/; do
        if [ -f "${dir}PROJECT.yaml" ]; then
            basename "$dir"
        fi
    done
}
