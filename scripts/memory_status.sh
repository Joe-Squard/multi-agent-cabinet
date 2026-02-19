#!/bin/bash
# memory_status.sh - 記憶システムの稼働状態を表示

echo "🧠 Cabinet Memory System Status"
echo "================================"
echo ""

# 1. Qdrant Vector DB
echo "=== Qdrant Vector DB ==="
if curl -s http://localhost:6333/healthz > /dev/null 2>&1; then
    echo "  Status: ✅ ONLINE"
    # コレクション一覧
    COLLECTIONS=$(curl -s http://localhost:6333/collections | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    cols=d.get('result',{}).get('collections',[])
    if not cols:
        print('  Collections: (none)')
    else:
        print(f'  Collections: {len(cols)}')
        for c in cols:
            name=c['name']
            # Get collection info
            import urllib.request
            info=json.loads(urllib.request.urlopen(f'http://localhost:6333/collections/{name}').read())
            count=info.get('result',{}).get('points_count',0)
            print(f'    - {name}: {count} points')
except Exception as e:
    print(f'  Error: {e}')
" 2>/dev/null)
    echo "$COLLECTIONS"
else
    echo "  Status: ❌ OFFLINE"
    echo "  Start:  cd memory && docker compose up -d"
fi
echo ""

# 2. MCP Server
echo "=== Memory MCP Server ==="
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/sse -m 2 2>/dev/null | grep -q "200"; then
    echo "  Status:    ✅ ONLINE"
    echo "  Endpoint:  http://127.0.0.1:8000/sse"
    echo "  Transport: SSE"
    echo "  Embedding: FastEmbed (all-MiniLM-L6-v2)"
else
    echo "  Status: ❌ OFFLINE"
    echo "  Start:  cd memory && pm2 start ecosystem.config.cjs"
fi
echo ""

# 3. Session files
echo "=== Session Memory Files ==="
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSIONS_DIR="$BASE_DIR/memory/sessions"
if [ -d "$SESSIONS_DIR" ]; then
    count=$(ls -1 "$SESSIONS_DIR"/*.md 2>/dev/null | wc -l)
    echo "  Files: $count"
    for f in "$SESSIONS_DIR"/*.md; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .md)
        lines=$(wc -l < "$f")
        echo "    - ${name}.md: ${lines} lines"
    done
else
    echo "  Directory not found"
fi
echo ""

# 4. Shared memory files
echo "=== Shared Memory Files ==="
SHARED_DIR="$BASE_DIR/memory/shared"
if [ -d "$SHARED_DIR" ]; then
    for f in "$SHARED_DIR"/*.md; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        lines=$(wc -l < "$f")
        echo "  - ${name}: ${lines} lines"
    done
else
    echo "  Directory not found"
fi
