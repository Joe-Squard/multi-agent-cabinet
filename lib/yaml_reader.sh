#!/bin/bash
# yaml_reader.sh - YAML設定読み込みヘルパーライブラリ
# settings.yaml からドットパスで値を取得する
#
# 使い方:
#   source lib/yaml_reader.sh
#   get_yaml_value "config/settings.yaml" "agents.prime_minister.model"
#   get_yaml_value "config/settings.yaml" "ntfy.topic"

# get_yaml_value <yaml_file> <dot.path>
# YAML ファイルからドットパスで値を取得
# Python3 が利用可能なら Python 経由、なければ grep+awk でフォールバック
get_yaml_value() {
    local yaml_file="$1"
    local dot_path="$2"

    if [ ! -f "$yaml_file" ]; then
        echo ""
        return 1
    fi

    # Python3 が使えるなら安全にパース
    if command -v python3 &> /dev/null; then
        python3 -c "
import sys
path = '${dot_path}'.split('.')
current = {}
# シンプルなYAMLパーサー（PyYAMLなしで動作）
with open('${yaml_file}') as f:
    lines = f.readlines()
indent_stack = [(-1, current)]
for line in lines:
    stripped = line.rstrip()
    if not stripped or stripped.startswith('#'):
        continue
    indent = len(line) - len(line.lstrip())
    # key: value の行を処理
    if ':' in stripped:
        parts = stripped.split(':', 1)
        key = parts[0].strip().strip('\"').strip(\"'\")
        val = parts[1].strip().strip('\"').strip(\"'\") if len(parts) > 1 else ''
        # インデントスタックを調整
        while len(indent_stack) > 1 and indent_stack[-1][0] >= indent:
            indent_stack.pop()
        parent = indent_stack[-1][1]
        if val and not val.startswith('{') and not val.startswith('['):
            parent[key] = val
        else:
            child = {}
            parent[key] = child
            indent_stack.append((indent, child))
# ドットパスで値を取得
result = current
for p in path:
    if isinstance(result, dict) and p in result:
        result = result[p]
    else:
        result = ''
        break
print(result if isinstance(result, str) else '')
" 2>/dev/null
    else
        # フォールバック: grep + awk (2階層まで)
        _yaml_grep_fallback "$yaml_file" "$dot_path"
    fi
}

# grep+awk フォールバック（Python3 未インストール時）
_yaml_grep_fallback() {
    local yaml_file="$1"
    local dot_path="$2"

    IFS='.' read -ra PARTS <<< "$dot_path"
    local depth=${#PARTS[@]}

    if [ "$depth" -eq 1 ]; then
        grep -E "^${PARTS[0]}:" "$yaml_file" 2>/dev/null | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'"
    elif [ "$depth" -eq 2 ]; then
        awk -v sec="${PARTS[0]}" -v key="${PARTS[1]}" '
            $0 ~ "^"sec":" { in_sec=1; next }
            in_sec && /^[^ ]/ { in_sec=0 }
            in_sec && $0 ~ "^  "key":" { gsub(/^  [^:]+: */, ""); gsub(/"/, ""); print; exit }
        ' "$yaml_file" 2>/dev/null
    elif [ "$depth" -eq 3 ]; then
        awk -v sec="${PARTS[0]}" -v sub="${PARTS[1]}" -v key="${PARTS[2]}" '
            $0 ~ "^"sec":" { in_sec=1; next }
            in_sec && /^[^ ]/ { in_sec=0 }
            in_sec && $0 ~ "^  "sub":" { in_sub=1; next }
            in_sub && /^  [^ ]/ && !/^    / { in_sub=0 }
            in_sub && $0 ~ "^    "key":" { gsub(/^    [^:]+: */, ""); gsub(/"/, ""); print; exit }
        ' "$yaml_file" 2>/dev/null
    fi
}
