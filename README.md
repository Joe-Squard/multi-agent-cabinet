# Multi-Agent Cabinet System v0.5.0

**内閣制度マルチエージェントシステム** — Command your AI agents like a Japanese Cabinet.

日本の内閣制度に着想を得た階層的マルチエージェントシステム。天皇（あなた）→ 首相 → 官房長官 / 専門大臣 → 官僚 の指揮系統で、Claude Code エージェントを並列に稼働させます。

## アーキテクチャ

```
天皇（あなた）
  │
  ▼ 詔勅（Imperial Decree）
首相 (Prime Minister)                ← 常駐 / ドメイン分析 & ルーティング
  │
  ├── 内閣官房長官 (Chief Secretary)  ← 常駐 / 汎用・横断タスク
  │     └── 官僚 x2
  │
  ├── プロダクト大臣 (m_product)      ← オンデマンド起動
  │     └── 官僚 x2
  ├── リサーチ大臣 (m_research)
  │     └── 官僚 x2
  ├── 設計大臣 (m_arch)
  │     └── 官僚 x2
  ├── フロントエンド大臣 (m_fe)
  │     └── 官僚 x2
  ├── バックエンド大臣 (m_be)
  │     └── 官僚 x2
  ├── モバイル大臣 (m_mob)
  │     └── 官僚 x2
  ├── インフラ大臣 (m_infra)
  │     └── 官僚 x2
  ├── AI大臣 (m_ai)
  │     └── 官僚 x2
  ├── 品質管理大臣 (m_qa)
  │     └── 官僚 x2
  ├── デザイン大臣 (m_design)
  │     └── 官僚 x2
  └── UAT大臣 (m_uat)
        └── 官僚 x2
```

### 設計原則

- **PM 直轄ルーティング** — 首相がドメイン分析し、最適な大臣に直接タスクを振る
- **官房長官と大臣は同格ピア** — 官房長官は大臣の上位ではない
- **大臣はオンデマンド起動** — 必要なときだけ起動し、インスタンスを節約
- **ノンブロッキング** — タスクを受けたら即座に下位に委譲し、制御を返す
- **イベント駆動** — `inotifywait` によるファイル監視（ポーリング不要）

## セットアップ

### 必要環境

- Linux / macOS / WSL2
- tmux
- Claude Code CLI (`claude`)
- Docker (記憶システムの Qdrant 用)
- Python 3.12+ (`mcp-server-qdrant` 用)
- Node.js 22+ (pm2 用)
- inotify-tools (Linux) / fswatch (macOS) — なくてもポーリングで動作

### インストール

```bash
git clone https://github.com/Joe-Squard/multi-agent-cabinet.git
cd multi-agent-cabinet
./first_setup.sh

# 記憶システム起動
cd memory && docker compose up -d   # Qdrant Vector DB
pip install mcp-server-qdrant       # MCP Server
pm2 start ecosystem.config.cjs      # MCP Server (pm2管理)
pm2 save
```

### 起動 / 停止

```bash
# 起動（PM + Chief Secretary + Watcher）
./cabinet_start.sh

# 停止
./cabinet_stop.sh

# 簡易コマンド
./cabinet start
./cabinet stop
./cabinet status
```

## 使い方

### 1. 首相に接続して命令を出す

```bash
tmux attach-session -t pm
```

```
「React Native でフォーチュンアプリを作成せよ。
 バックエンドは Hono + Drizzle、モバイルは Expo を使用すること」
```

### 2. 首相が自動でルーティング

首相がタスクのドメインを分析し、必要な大臣を起動してタスクを振り分けます。

```
PM → minister_activate.sh mob   → モバイル大臣チーム起動
PM → minister_activate.sh be    → バックエンド大臣チーム起動
PM → inbox_write.sh minister_mob "モバイルアプリ実装..."
PM → inbox_write.sh minister_be  "API実装..."
```

### 3. 進捗確認

```bash
# ダッシュボード確認
cat dashboard.md

# 大臣セッション一覧
./cabinet ministers

# 特定の大臣セッションに接続
tmux attach-session -t m_fe
```

## 大臣一覧

| セッション | 大臣名 | 専門領域 |
|---|---|---|
| `m_product` | プロダクト大臣 | PRD, 要件分析, ユーザーストーリー, スコープ |
| `m_research` | リサーチ大臣 | 市場調査, 競合分析, 技術調査, PoC |
| `m_arch` | 設計大臣 | アーキテクチャ, 技術選定, スキーマ設計 |
| `m_fe` | フロントエンド大臣 | React, Next.js, CSS, コンポーネント |
| `m_be` | バックエンド大臣 | API, DB, 認証, マイグレーション |
| `m_mob` | モバイル大臣 | React Native, Expo, iOS, Android |
| `m_infra` | インフラ大臣 | Docker, AWS, CI/CD, デプロイ |
| `m_ai` | AI大臣 | ML, データ分析, LLM, Python |
| `m_qa` | 品質管理大臣 | テスト, セキュリティ, レビュー, カバレッジ |
| `m_design` | デザイン大臣 | UI/UX, デザインシステム, a11y |
| `m_uat` | UAT大臣 | 受入テスト, バグレポート, リリース判定 |

## 記憶システム（4-Layer Memory Architecture）

エージェントに長期記憶と短期記憶を提供。コンテキスト汚染を防ぐ Pull 型設計。

```
┌─────────── 短期記憶 ────────────┐  ┌─────────── 長期記憶 ────────────┐
│ L1: 個別セッション               │  │ L3: 個別 Vector DB              │
│     memory/sessions/<id>.md      │  │     Qdrant: agent_<id>          │
│                                  │  │                                 │
│ L2: 共有ファイル                 │  │ L4: 共有 Vector DB              │
│     queue/, dashboard.md         │  │     Qdrant: cabinet_shared      │
└──────────────────────────────────┘  └─────────────────────────────────┘
```

| コンポーネント | 技術 | ポート |
|---|---|---|
| Vector DB | Qdrant (Docker) | 6333 |
| MCP Server | mcp-server-qdrant (SSE, pm2) | 8000 |
| Embedding | FastEmbed (all-MiniLM-L6-v2) | — |

### 記憶プロトコル

1. **起動時** — セッションファイル + タスクを読む（Qdrant検索しない）
2. **作業中** — 必要な時だけ `qdrant-find` で検索（Pull型）
3. **完了時** — 学んだことを `qdrant-store` で保存
4. **Token Budget** — 1回5件まで、1タスク3回まで

### コレクション分離

各エージェントは自分専用のコレクション（`agent_pm`, `agent_m_fe` 等）を持ち、他エージェントのコレクションにはアクセスしません。`cabinet_shared` は全員が読み書き可能な共有知識ベースです。

```bash
# 記憶システム状態確認
./scripts/memory_status.sh

# バックアップ
./scripts/memory_backup.sh
```

## インスタンス管理

| リソース | 数 |
|---|---|
| 最大インスタンス数 | 20 |
| 起動時（PM + Chief） | 2 |
| 大臣チーム 1つあたり | +3（大臣1 + 官僚2） |
| 同時最大チーム数 | 約6チーム |

```bash
# 現在のインスタンス数確認
./scripts/instance_count.sh

# 大臣チーム手動起動 / 停止
./scripts/minister_activate.sh fe
./scripts/minister_deactivate.sh fe
```

## 通信プロトコル

ファイルベースの YAML メールボックスと `inotifywait` によるイベント駆動通信。

```bash
# メッセージ送信
./scripts/inbox_write.sh <agent_id> "<message>"
```

```yaml
---
timestamp: 2026-02-08T21:30:00Z
from: pm
message: |
  task_id: task_001
  title: タスクタイトル
  priority: high
  assigned_to: minister_fe
```

## ディレクトリ構成

```
multi-agent-cabinet/
├── cabinet_start.sh           # システム起動
├── cabinet_stop.sh            # システム停止
├── cabinet                    # 簡易コマンド
├── first_setup.sh             # 初回セットアップ
├── CLAUDE.md                  # システム全体指令
├── config/
│   ├── settings.yaml          # システム設定
│   └── agents.yaml            # エージェント定義
├── instructions/              # エージェント指示書 (14ファイル)
│   ├── prime_minister.md
│   ├── chief_secretary.md
│   ├── bureaucrat.md
│   └── minister_*.md          # 各大臣の指示書
├── scripts/                   # 通信・制御スクリプト
│   ├── inbox_write.sh         # メッセージ送信
│   ├── inbox_watcher.sh       # イベント監視
│   ├── minister_activate.sh   # 大臣チーム起動
│   ├── minister_deactivate.sh # 大臣チーム停止
│   ├── instance_count.sh      # インスタンス数確認
│   ├── memory_status.sh       # 記憶システム状態表示
│   └── memory_backup.sh       # 記憶バックアップ
├── tools/                     # 専門大臣ツール (11カテゴリ)
│   ├── product/               # PRDテンプレ, ユーザーストーリー生成 等
│   ├── research/              # 競合マトリクス, 市場レポート 等
│   ├── architect/             # プロジェクト初期化, API Doc 等
│   ├── frontend/              # コンポーネント雛形, a11y監査 等
│   ├── backend/               # API雛形, DB スキーマDoc 等
│   ├── mobile/                # RNスクリーン雛形, ネイティブ依存チェック 等
│   ├── infra/                 # Docker lint, IaC検証 等
│   ├── ai/                    # モデルベンチマーク, pip監査 等
│   ├── qa/                    # テスト雛形, セキュリティスキャン 等
│   ├── design/                # デザインシステム監査, カラーコントラスト 等
│   ├── uat/                   # テストシナリオ生成, リリース判定 等
│   └── common/                # プロジェクト検出
├── skills/                    # Claude Code スキル
├── lib/                       # 共通ライブラリ
├── queue/                     # 通信キュー (.gitignore)
├── .mcp.json                  # MCP サーバー設定（全エージェント共有）
├── memory/                    # 記憶システム
│   ├── docker-compose.yml     #   Qdrant Vector DB
│   ├── ecosystem.config.cjs   #   MCP Server (pm2)
│   ├── sessions/              #   エージェント別セッションメモリ
│   ├── shared/                #   共有メモリファイル
│   └── qdrant/                #   Qdrant データ (.gitignore)
└── projects/                  # 作業領域 (.gitignore)
```

## 技術スタック

- **AI CLI**: Claude Code (Opus 4.6)
- **オーケストレーション**: tmux
- **イベント駆動**: inotifywait / fswatch
- **通信**: YAML ファイルベース メールボックス
- **長期記憶**: Qdrant Vector DB + MCP Server (SSE)
- **Embedding**: FastEmbed (all-MiniLM-L6-v2, 384次元)
- **プロセス管理**: pm2
- **スクリプト**: Bash

## ライセンス

MIT License
