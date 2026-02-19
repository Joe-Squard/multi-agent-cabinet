# Architecture Decisions Log

<!-- 設計判断を時系列で記録。全エージェントが参照可能。 -->
<!-- フォーマット: ## YYYY-MM-DD: 判断タイトル -->

## 2026-02-19: 4-Layer Memory Architecture 導入
- Qdrant Vector DB + FastEmbed (all-MiniLM-L6-v2)
- 個別コレクション (agent_{id}) + 共有コレクション (cabinet_shared)
- Pull型: エージェントが必要時にのみ検索
- Token Budget: 1回5件まで、1タスク3回まで
