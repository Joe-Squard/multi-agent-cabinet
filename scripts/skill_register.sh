#!/bin/bash
# skill_register.sh - スキルをテンプレートとして登録
# 使い方:
#   ./scripts/skill_register.sh <skill-name> "<description>" [--local]
#
# --local: ローカル skills/ に作成（デフォルトは ~/.claude/skills/cabinet-{name}/）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 引数チェック
if [ $# -lt 2 ]; then
    echo "使い方: $0 <skill-name> \"<description>\" [--local]" >&2
    echo "例: $0 react-migration \"React バージョン移行パターン\"" >&2
    echo "    $0 api-scaffold \"REST API 雛形作成\" --local" >&2
    exit 1
fi

SKILL_NAME="$1"
DESCRIPTION="$2"
LOCAL=false
[ "${3:-}" = "--local" ] && LOCAL=true

if [ "$LOCAL" = true ]; then
    SKILL_DIR="$BASE_DIR/skills/${SKILL_NAME}"
else
    SKILL_DIR="$HOME/.claude/skills/cabinet-${SKILL_NAME}"
fi

if [ -d "$SKILL_DIR" ]; then
    echo "⚠️  スキル ${SKILL_NAME} は既に存在します: $SKILL_DIR" >&2
    exit 1
fi

mkdir -p "$SKILL_DIR"

TIMESTAMP=$(date -Iseconds)

cat > "$SKILL_DIR/SKILL.md" <<EOF
---
name: ${SKILL_NAME}
description: ${DESCRIPTION}
created: ${TIMESTAMP}
---

# ${SKILL_NAME}

${DESCRIPTION}

## 前提条件

- TODO: 必要なツール・環境を記載

## 手順

1. TODO: ステップ1
2. TODO: ステップ2
3. TODO: ステップ3

## 例

\`\`\`bash
# TODO: 具体的な使用例
\`\`\`

## 注意事項

- TODO: 注意点を記載
EOF

echo "✅ スキル登録: ${SKILL_NAME}"
echo "📁 ${SKILL_DIR}/SKILL.md"

if [ "$LOCAL" = true ]; then
    echo "📍 ローカルスキル（このプロジェクト内）"
else
    echo "🌐 グローバルスキル（~/.claude/skills/ 配下）"
fi

echo ""
echo "次のステップ:"
echo "  1. ${SKILL_DIR}/SKILL.md を編集して内容を完成させてください"
echo "  2. Qdrant cabinet_shared に保存して他エージェントから検索可能にしてください"
