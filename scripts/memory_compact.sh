#!/bin/bash
# memory_compact.sh - Qdrant コレクションの圧縮・古いポイント削除
# 使い方:
#   ./scripts/memory_compact.sh --dry-run   # まず確認（推奨）
#   ./scripts/memory_compact.sh             # 実行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$BASE_DIR/lib/yaml_reader.sh"
SETTINGS="$BASE_DIR/config/settings.yaml"

mkdir -p "$BASE_DIR/runtime"
LOG_FILE="$BASE_DIR/runtime/memory_compact.log"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

QDRANT_URL="http://localhost:6333"
PRIVATE_MAX=$(get_yaml_value "$SETTINGS" "memory.compaction.private_max_points" 2>/dev/null || echo "500")
SHARED_MAX=$(get_yaml_value "$SETTINGS" "memory.compaction.shared_max_points" 2>/dev/null || echo "1000")

log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# Qdrant チェック
if ! curl -s "$QDRANT_URL/healthz" > /dev/null 2>&1; then
    log "ERROR: Qdrant is offline ($QDRANT_URL)"
    exit 1
fi

log "=== Memory Compaction Start (dry_run=$DRY_RUN, private_max=$PRIVATE_MAX, shared_max=$SHARED_MAX) ==="

# コレクション一覧取得
COLLECTIONS=$(curl -s "$QDRANT_URL/collections" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for c in d.get('result', {}).get('collections', []):
    print(c['name'])
" 2>/dev/null)

if [ -z "$COLLECTIONS" ]; then
    log "INFO: コレクションなし"
    exit 0
fi

TOTAL_DELETED=0

for COL in $COLLECTIONS; do
    # ポイント数取得
    INFO=$(curl -s "$QDRANT_URL/collections/$COL")
    COUNT=$(echo "$INFO" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('result', {}).get('points_count', 0))
" 2>/dev/null)

    # しきい値判定
    if [ "$COL" = "cabinet_shared" ]; then
        THRESHOLD=$SHARED_MAX
    else
        THRESHOLD=$PRIVATE_MAX
    fi

    log "Collection: $COL ($COUNT points, threshold: $THRESHOLD)"

    if [ "$COUNT" -le "$THRESHOLD" ]; then
        log "  SKIP: しきい値以下"
        continue
    fi

    EXCESS=$((COUNT - THRESHOLD))
    log "  EXCESS: ${EXCESS} ポイントを削除対象"

    if [ "$DRY_RUN" = true ]; then
        log "  DRY-RUN: 削除をスキップ"
        continue
    fi

    # 古いポイントを scroll → delete
    DELETED=$(python3 <<PYEOF
import json, urllib.request

url = "$QDRANT_URL"
col = "$COL"
excess = $EXCESS

# Scroll で古いポイントを取得（ID順 = 挿入順）
req_data = json.dumps({
    "limit": excess,
    "with_payload": False,
    "with_vector": False
}).encode()

req = urllib.request.Request(
    f"{url}/collections/{col}/points/scroll",
    data=req_data,
    headers={"Content-Type": "application/json"},
    method="POST"
)

try:
    resp = json.loads(urllib.request.urlopen(req).read())
    points = resp.get("result", {}).get("points", [])

    if points:
        ids = [p["id"] for p in points]
        del_data = json.dumps({"points": ids}).encode()
        del_req = urllib.request.Request(
            f"{url}/collections/{col}/points/delete",
            data=del_data,
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        urllib.request.urlopen(del_req)
        print(len(ids))
    else:
        print(0)
except Exception as e:
    import sys
    print(f"ERROR: {e}", file=sys.stderr)
    print(0)
PYEOF
    )

    log "  DELETED: ${DELETED} points from $COL"
    TOTAL_DELETED=$((TOTAL_DELETED + DELETED))
done

log "=== Compaction Complete (total deleted: $TOTAL_DELETED) ==="
