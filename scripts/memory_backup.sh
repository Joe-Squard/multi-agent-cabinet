#!/bin/bash
# memory_backup.sh - Qdrant のスナップショットを作成

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$BASE_DIR/backups/memory_$(date +%Y%m%d_%H%M%S)"

echo "🧠 Memory Backup"
echo "================"

# Qdrant チェック
if ! curl -s http://localhost:6333/healthz > /dev/null 2>&1; then
    echo "❌ Qdrant is offline. Cannot backup."
    exit 1
fi

mkdir -p "$BACKUP_DIR"

# Qdrant スナップショット作成
echo "📸 Creating Qdrant snapshot..."
SNAPSHOT=$(curl -s -X POST http://localhost:6333/snapshots)
echo "  Response: $SNAPSHOT"

# セッションファイルバックアップ
echo "📁 Backing up session files..."
cp -r "$BASE_DIR/memory/sessions" "$BACKUP_DIR/sessions" 2>/dev/null || true
cp -r "$BASE_DIR/memory/shared" "$BACKUP_DIR/shared" 2>/dev/null || true

echo ""
echo "✅ Backup complete: $BACKUP_DIR"
ls -la "$BACKUP_DIR/"
