#!/bin/bash
# project_init.sh - プロジェクトに開発統制を初期化
# 使い方: ./scripts/project_init.sh <project_name> [--repo URL]
# 例:
#   ./scripts/project_init.sh my-app
#   ./scripts/project_init.sh my-app --repo git@github.com:Joe-Squard/my-app.git

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$BASE_DIR/templates/project"

# 引数チェック
if [ $# -lt 1 ]; then
    echo "使い方: $0 <project_name> [--repo URL]" >&2
    echo "" >&2
    echo "プロジェクトに開発統制ファイルを初期化します。" >&2
    echo "projects/<project_name>/ ディレクトリに以下を作成:" >&2
    echo "  PROJECT.yaml  - プロジェクトメタデータ（フェーズ管理）" >&2
    echo "  VISION.md     - ビジョンドキュメント" >&2
    echo "  DECISIONS.md  - 意思決定記録" >&2
    echo "  .cabinet/     - 統制管理ディレクトリ" >&2
    exit 1
fi

PROJECT_NAME="$1"
shift

# オプション解析
REPO_URL=""
while [ $# -gt 0 ]; do
    case "$1" in
        --repo) REPO_URL="$2"; shift 2 ;;
        *)      echo "不明なオプション: $1" >&2; exit 1 ;;
    esac
done

PROJECT_DIR="$BASE_DIR/projects/$PROJECT_NAME"
DATE=$(date +%Y-%m-%d)

# プロジェクトディレクトリ作成
mkdir -p "$PROJECT_DIR/.cabinet/release-specs"

# 既存の PROJECT.yaml があれば上書きしない
if [ -f "$PROJECT_DIR/PROJECT.yaml" ]; then
    echo "開発統制は既に初期化済みです: $PROJECT_DIR/PROJECT.yaml" >&2
    echo "フェーズ遷移は phase_transition.sh を使ってください。" >&2
    exit 0
fi

# テンプレートからファイル生成
echo "開発統制を初期化: $PROJECT_NAME"

# PROJECT.yaml
sed -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
    -e "s/{{DATE}}/$DATE/g" \
    "$TEMPLATES_DIR/PROJECT.yaml" > "$PROJECT_DIR/PROJECT.yaml"

# repository を設定（指定があれば）
if [ -n "$REPO_URL" ]; then
    sed -i "s|^repository: \"\"|repository: \"$REPO_URL\"|" "$PROJECT_DIR/PROJECT.yaml"
fi

# VISION.md（存在しなければ）
if [ ! -f "$PROJECT_DIR/VISION.md" ]; then
    sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
        "$TEMPLATES_DIR/VISION.md" > "$PROJECT_DIR/VISION.md"
fi

# DECISIONS.md（存在しなければ）
if [ ! -f "$PROJECT_DIR/DECISIONS.md" ]; then
    sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
        "$TEMPLATES_DIR/DECISIONS.md" > "$PROJECT_DIR/DECISIONS.md"
fi

# Git 初期化（リポジトリがなければ）
if [ ! -d "$PROJECT_DIR/.git" ]; then
    (
        cd "$PROJECT_DIR"
        git init -q
        # リポジトリが指定されていれば remote 追加
        if [ -n "$REPO_URL" ]; then
            git remote add origin "$REPO_URL" 2>/dev/null || true
        fi
    )
    echo "  git init 完了"
fi

echo ""
echo "初期化完了:"
echo "  PROJECT.yaml  : $PROJECT_DIR/PROJECT.yaml"
echo "  VISION.md     : $PROJECT_DIR/VISION.md"
echo "  DECISIONS.md  : $PROJECT_DIR/DECISIONS.md"
echo "  .cabinet/     : $PROJECT_DIR/.cabinet/"
echo ""
echo "現在のフェーズ: genesis"
echo "フェーズ遷移: ./scripts/phase_transition.sh $PROJECT_NAME growth"
