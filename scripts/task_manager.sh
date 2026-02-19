#!/bin/bash
# task_manager.sh - タスク状態管理
# 使い方:
#   task_manager.sh create <task_id> <assigned_to> <title> <priority> [--model MODEL] [--parent PARENT_ID]
#   task_manager.sh update <task_id> <status> [--report REPORT_PATH]
#   task_manager.sh list [--status STATUS] [--assigned AGENT_ID]
#   task_manager.sh get <task_id>
#   task_manager.sh dashboard

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$BASE_DIR/queue/tasks"
DASHBOARD="$BASE_DIR/dashboard.md"

mkdir -p "$TASKS_DIR"

case "${1:-help}" in
    create)
        if [ $# -lt 5 ]; then
            echo "使い方: $0 create <task_id> <assigned_to> <title> <priority> [--model MODEL] [--parent ID]" >&2
            exit 1
        fi
        TASK_ID="$2"
        ASSIGNED_TO="$3"
        TITLE="$4"
        PRIORITY="$5"
        shift 5

        MODEL="opus"
        PARENT=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --model)  MODEL="$2"; shift 2 ;;
                --parent) PARENT="$2"; shift 2 ;;
                *)        shift ;;
            esac
        done

        TASK_FILE="$TASKS_DIR/${TASK_ID}.yaml"
        if [ -f "$TASK_FILE" ]; then
            echo "⚠️  タスク $TASK_ID は既に存在します" >&2
            exit 1
        fi

        TIMESTAMP=$(date -Iseconds)
        cat > "$TASK_FILE" <<EOF
---
task_id: $TASK_ID
title: "$TITLE"
priority: $PRIORITY
status: pending
assigned_to: $ASSIGNED_TO
model: $MODEL
created_at: $TIMESTAMP
updated_at: $TIMESTAMP
parent_task_id: "$PARENT"
report_path: ""
EOF
        echo "✅ タスク作成: $TASK_ID → $ASSIGNED_TO (priority: $PRIORITY, model: $MODEL)"
        ;;

    update)
        if [ $# -lt 3 ]; then
            echo "使い方: $0 update <task_id> <status> [--report REPORT_PATH]" >&2
            echo "  status: pending | in_progress | completed | failed" >&2
            exit 1
        fi
        TASK_ID="$2"
        NEW_STATUS="$3"
        shift 3

        TASK_FILE="$TASKS_DIR/${TASK_ID}.yaml"
        if [ ! -f "$TASK_FILE" ]; then
            echo "ERROR: タスク $TASK_ID が見つかりません" >&2
            exit 1
        fi

        REPORT_PATH=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --report) REPORT_PATH="$2"; shift 2 ;;
                *)        shift ;;
            esac
        done

        TIMESTAMP=$(date -Iseconds)
        python3 -c "
import re, sys

with open('$TASK_FILE', 'r') as f:
    content = f.read()

content = re.sub(r'^status:.*$', 'status: $NEW_STATUS', content, flags=re.MULTILINE)
content = re.sub(r'^updated_at:.*$', 'updated_at: $TIMESTAMP', content, flags=re.MULTILINE)

report = '$REPORT_PATH'
if report:
    content = re.sub(r'^report_path:.*$', 'report_path: \"' + report + '\"', content, flags=re.MULTILINE)

with open('$TASK_FILE', 'w') as f:
    f.write(content)
"
        echo "✅ タスク更新: $TASK_ID → $NEW_STATUS"
        ;;

    list)
        shift || true
        STATUS_FILTER=""
        ASSIGNED_FILTER=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --status)   STATUS_FILTER="$2"; shift 2 ;;
                --assigned) ASSIGNED_FILTER="$2"; shift 2 ;;
                *)          shift ;;
            esac
        done

        echo "| ID | タイトル | 担当 | ステータス | 優先度 | 更新日時 |"
        echo "|---|---|---|---|---|---|"

        for f in "$TASKS_DIR"/*.yaml; do
            [ -f "$f" ] || continue
            python3 -c "
import sys
lines = open('$f').readlines()
d = {}
for line in lines:
    line = line.strip()
    if ':' in line and not line.startswith('#') and not line.startswith('---'):
        k, v = line.split(':', 1)
        d[k.strip()] = v.strip().strip('\"')

sf = '$STATUS_FILTER'
af = '$ASSIGNED_FILTER'
if sf and d.get('status','') != sf:
    sys.exit(0)
if af and d.get('assigned_to','') != af:
    sys.exit(0)

tid = d.get('task_id','')
title = d.get('title','')[:30]
assigned = d.get('assigned_to','')
status = d.get('status','')
priority = d.get('priority','')
updated = d.get('updated_at','')[:19]
print(f'| {tid} | {title} | {assigned} | {status} | {priority} | {updated} |')
" 2>/dev/null
        done
        ;;

    get)
        if [ $# -lt 2 ]; then
            echo "使い方: $0 get <task_id>" >&2
            exit 1
        fi
        TASK_FILE="$TASKS_DIR/${2}.yaml"
        if [ -f "$TASK_FILE" ]; then
            cat "$TASK_FILE"
        else
            echo "ERROR: タスク $2 が見つかりません" >&2
            exit 1
        fi
        ;;

    dashboard)
        # dashboard.md を自動生成
        TIMESTAMP=$(date -Iseconds)
        ACTIVE_COUNT=$("$SCRIPT_DIR/instance_count.sh" 2>/dev/null || echo "0")

        {
            echo "# 内閣ダッシュボード"
            echo ""
            echo "最終更新: $TIMESTAMP"
            echo "稼働インスタンス: $ACTIVE_COUNT"
            echo ""
            echo "## アクティブタスク"
            echo ""
            echo "| ID | タイトル | 担当 | ステータス | 優先度 |"
            echo "|---|---|---|---|---|"

            for f in "$TASKS_DIR"/*.yaml; do
                [ -f "$f" ] || continue
                python3 -c "
import sys
lines = open('$f').readlines()
d = {}
for line in lines:
    line = line.strip()
    if ':' in line and not line.startswith('#') and not line.startswith('---'):
        k, v = line.split(':', 1)
        d[k.strip()] = v.strip().strip('\"')

status = d.get('status','')
if status in ('completed', 'failed'):
    sys.exit(0)

print(f'| {d.get(\"task_id\",\"\")} | {d.get(\"title\",\"\")[:40]} | {d.get(\"assigned_to\",\"\")} | {status} | {d.get(\"priority\",\"\")} |')
" 2>/dev/null
            done

            echo ""
            echo "## 完了タスク（直近）"
            echo ""
            echo "| ID | タイトル | 担当 | 完了日時 |"
            echo "|---|---|---|---|"

            for f in "$TASKS_DIR"/*.yaml; do
                [ -f "$f" ] || continue
                python3 -c "
import sys
lines = open('$f').readlines()
d = {}
for line in lines:
    line = line.strip()
    if ':' in line and not line.startswith('#') and not line.startswith('---'):
        k, v = line.split(':', 1)
        d[k.strip()] = v.strip().strip('\"')

if d.get('status','') != 'completed':
    sys.exit(0)

print(f'| {d.get(\"task_id\",\"\")} | {d.get(\"title\",\"\")[:40]} | {d.get(\"assigned_to\",\"\")} | {d.get(\"updated_at\",\"\")[:19]} |')
" 2>/dev/null
            done

            echo ""
            echo "## セッション"
            echo ""
            tmux list-sessions 2>/dev/null | grep -E "(pm|chief|m_|watcher)" | while read -r line; do
                echo "- $line"
            done || echo "- セッションなし"
        } > "$DASHBOARD"

        echo "✅ dashboard.md を更新しました"
        ;;

    help|*)
        echo "task_manager.sh - タスク状態管理"
        echo ""
        echo "使い方:"
        echo "  $0 create <task_id> <assigned_to> <title> <priority> [--model MODEL] [--parent ID]"
        echo "  $0 update <task_id> <status> [--report REPORT_PATH]"
        echo "  $0 list [--status STATUS] [--assigned AGENT_ID]"
        echo "  $0 get <task_id>"
        echo "  $0 dashboard"
        echo ""
        echo "ステータス: pending → in_progress → completed | failed"
        ;;
esac
