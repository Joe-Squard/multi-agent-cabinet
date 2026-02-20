# CLAUDE.md - システム全体指令

このファイルは、内閣制度マルチエージェントシステム全体に適用される指令です。

## システム概要

**内閣制度マルチエージェントシステム v0.6.0 — PM直轄ルーティング + オンデマンド大臣制度**

天皇（ユーザー）→ 首相（ルーティング）→ 官房長官 / 専門大臣（同格ピア）→ 官僚（各大臣配下）という日本の内閣制度に着想を得た階層的マルチエージェントシステム。

## アーキテクチャ原則

### 1. 階層的指揮命令系統

```
天皇（Emperor）: ユーザー
  |
首相（Prime Minister）: タスク受信・分析・ルーティング
  |
  +--- 内閣官房長官（Chief Cabinet Secretary）  ← 常駐ピア
  |      └── 官僚 (bureaucrats)
  |
  +--- プロダクト大臣 (m_product)  ← オンデマンド起動【ビジネス】
  |      └── 官僚 (bureaucrats)
  |
  +--- リサーチ大臣 (m_research)   ← オンデマンド起動【ビジネス】
  |      └── 官僚 (bureaucrats)
  |
  +--- 設計大臣 (m_arch)          ← オンデマンド起動
  |      └── 官僚 (bureaucrats)
  |
  +--- フロントエンド大臣 (m_fe)  ← オンデマンド起動
  |      └── 官僚 (bureaucrats)
  |
  +--- バックエンド大臣 (m_be)    ← オンデマンド起動
  |      └── 官僚 (bureaucrats)
  |
  +--- モバイル大臣 (m_mob)       ← オンデマンド起動
  |      └── 官僚 (bureaucrats)
  |
  +--- インフラ大臣 (m_infra)     ← オンデマンド起動
  |      └── 官僚 (bureaucrats)
  |
  +--- AI大臣 (m_ai)             ← オンデマンド起動
  |      └── 官僚 (bureaucrats)
  |
  +--- 品質管理大臣 (m_qa)        ← オンデマンド起動
  |      └── 官僚 (bureaucrats)
  |
  +--- デザイン大臣 (m_design)    ← オンデマンド起動
  |      └── 官僚 (bureaucrats)
  |
  +--- UAT大臣 (m_uat)           ← オンデマンド起動
         └── 官僚 (bureaucrats)
```

**v0.3 との主な違い:**
- **PM がルーティングを行う**（官房長官ではない）
- **官房長官と大臣は同格ピア**（官房長官が大臣の上位ではない）
- **大臣はオンデマンド起動**（常駐しない）
- **各大臣が独自の tmux セッションを持つ**（bureau 統合セッション廃止）
- **各大臣の配下に官僚がいる**（大臣チーム制）
- **バックエンド大臣は1名に統合**（be1/be2 → be）

### 2. ノンブロッキング実行

- タスクを受け取ったらすぐに下位に委譲
- **自分で実行せず、必ず委譲する**（首相・大臣とも）
- 委譲後は即座に制御を返す

### 3. イベント駆動通信

- ファイルベースのメールボックス（YAML）
- `inotifywait` でイベント検知（ポーリング不要）
- API呼び出しを最小化

### 4. PM 直轄ルーティング

- **首相がタスクのドメインを分析**し、最適な宛先を決定
- 官房長官 or 専門大臣に直接ルーティング
- 必要な大臣がまだ起動していなければ `minister_activate.sh` で起動
- クロスドメインタスクは分割して各大臣に分配

## tmux セッション構成

| セッション | 起動 | 説明 |
|---|---|---|
| `pm` | 常駐（起動時） | 首相 |
| `chief` | 常駐（起動時） | 内閣官房長官 |
| `m_product` | オンデマンド | プロダクト大臣 + 官僚 |
| `m_research` | オンデマンド | リサーチ大臣 + 官僚 |
| `m_arch` | オンデマンド | 設計大臣 + 官僚 |
| `m_fe` | オンデマンド | フロントエンド大臣 + 官僚 |
| `m_be` | オンデマンド | バックエンド大臣 + 官僚 |
| `m_mob` | オンデマンド | モバイル大臣 + 官僚 |
| `m_infra` | オンデマンド | インフラ大臣 + 官僚 |
| `m_ai` | オンデマンド | AI大臣 + 官僚 |
| `m_qa` | オンデマンド | 品質管理大臣 + 官僚 |
| `m_design` | オンデマンド | デザイン大臣 + 官僚 |
| `m_uat` | オンデマンド | UAT大臣 + 官僚 |
| `watcher` | 常駐（起動時） | 通信監視 |

**起動時**: pm + chief + watcher = 3セッション
**フル稼働時**: 上記 + 大臣11セッション = 最大14セッション

## インスタンスバジェット

| リソース | 数 |
|---|---|
| 最大インスタンス数 | 20 |
| 起動時（PM + Chief） | 2 |
| 大臣チーム1つあたり | +3（大臣1 + 官僚2） |
| 大臣11チーム全起動時 | 2 + 33 = 35 → 上限20のため同時最大6チーム |

`instance_count.sh` で現在のインスタンス数を確認し、上限を超えないよう管理。

## エージェントの役割

### 首相 (Prime Minister)

**ID**: `pm`
**セッション**: `tmux attach-session -t pm`
**指示書**: `instructions/prime_minister.md`

**責務**:
- 天皇からの詔勅を受け取る
- タスクを分析・分類
- **ドメイン分析でルーティング先を決定**（v0.4 で官房長官から移管）
- 必要な大臣を `minister_activate.sh` で起動
- 官房長官 or 大臣に直接アサイン
- 全体進捗を管理
- 結果を天皇に報告
- 不要になった大臣を `minister_deactivate.sh` で停止

### 内閣官房長官 (Chief Cabinet Secretary)

**ID**: `chief`
**セッション**: `tmux attach-session -t chief`
**指示書**: `instructions/chief_secretary.md`

**責務**:
- 首相から直接タスクを受信（大臣と同格ピア）
- 横断的な調整・統合タスクを担当
- 大臣間の成果物統合
- 結果を首相に報告

### 専門大臣 (Ministers) x9

各大臣が独立した tmux セッション（`m_<type>`）を持ち、配下に官僚を従える。

| ID | セッション | 大臣名 | 指示書 | ツール |
|---|---|---|---|---|
| `minister_product` | `m_product` | プロダクト大臣 | `instructions/minister_product.md` | `tools/product/` |
| `minister_research` | `m_research` | リサーチ大臣 | `instructions/minister_research.md` | `tools/research/` |
| `minister_arch` | `m_arch` | 設計大臣 | `instructions/minister_architect.md` | `tools/architect/` |
| `minister_fe` | `m_fe` | フロントエンド大臣 | `instructions/minister_frontend.md` | `tools/frontend/` |
| `minister_be` | `m_be` | バックエンド大臣 | `instructions/minister_backend.md` | `tools/backend/` |
| `minister_mob` | `m_mob` | モバイル大臣 | `instructions/minister_mobile.md` | `tools/mobile/` |
| `minister_infra` | `m_infra` | インフラ大臣 | `instructions/minister_infra.md` | `tools/infra/` |
| `minister_ai` | `m_ai` | AI大臣 | `instructions/minister_ai.md` | `tools/ai/` |
| `minister_qa` | `m_qa` | 品質管理大臣 | `instructions/minister_qa.md` | `tools/qa/` |
| `minister_design` | `m_design` | デザイン大臣 | `instructions/minister_design.md` | `tools/design/` |
| `minister_uat` | `m_uat` | UAT大臣 | `instructions/minister_uat.md` | `tools/uat/` |

**共通責務**:
- 首相からのタスクを実行（官房長官経由ではなく直接受信）
- 官僚に作業を委譲
- 専門ツールとClaude Codeの全ツールを活用
- 成果物を作成し完了報告
- ドメイン外タスクは `routing_error` で返却

## キースクリプト

| スクリプト | 説明 |
|---|---|
| `cabinet_start.sh` | PM + Chief + Watcher を起動（大臣は起動しない） |
| `cabinet_stop.sh` | 全セッションを停止 |
| `scripts/minister_activate.sh <type>` | 大臣チーム（大臣+官僚）をオンデマンド起動 |
| `scripts/minister_deactivate.sh <type>` | 大臣チームを停止 |
| `scripts/instance_count.sh` | 現在の Claude インスタンス数を表示 |
| `scripts/inbox_write.sh` | メッセージ送信（キューベース、`--type`/`--from` 対応） |
| `scripts/inbox_watcher.sh` | イベント監視（ディレクトリベース） |
| `scripts/task_manager.sh` | タスク状態管理（create/update/list/get/dashboard） |
| `scripts/agent_health.sh` | エージェント死活監視 & 自動復旧 |
| `scripts/memory_compact.sh` | Qdrant コレクション圧縮 |
| `scripts/skill_register.sh` | スキル登録 |

## 通信プロトコル

### メッセージ形式（YAML）

```yaml
---
timestamp: 2026-02-19T10:00:00+09:00
from: pm
type: task
message: |
  task_id: task_001
  title: タスクタイトル
  description: 詳細説明
  priority: high
  assigned_to: minister_fe
```

### メッセージタイプ

| type | 用途 |
|------|------|
| `task` | タスク割当（デフォルト） |
| `report` | 完了報告 |
| `clarification` | 大臣間質問（自動CC PM） |
| `coordination` | 大臣間同期（自動CC PM） |
| `routing_error` | ドメイン外通知 |
| `skill_proposal` | スキル提案 |

### メッセージ送信

```bash
./scripts/inbox_write.sh <agent_id> "<message>"
./scripts/inbox_write.sh <agent_id> "<message>" --from <from_id> --type <type>
```

### メッセージ受信

各エージェントは `./scripts/inbox_watcher.sh <agent_id>` で監視中。
`queue/inbox/<agent_id>/` ディレクトリに新しい `.yaml` ファイルが届くと自動検知。

### 大臣間通信

大臣同士が `--type clarification` または `--type coordination` で直接メッセージを送信可能。
送信時、PM の inbox に自動的にCCが作成される。

### タスク状態管理

```bash
./scripts/task_manager.sh create <task_id> <assigned_to> "<title>" <priority>
./scripts/task_manager.sh update <task_id> <status>
./scripts/task_manager.sh list [--status STATUS]
./scripts/task_manager.sh dashboard
```

## 🧠 記憶システム（4-Layer Memory Architecture）

エージェントに長期記憶と短期記憶を提供する。コンテキスト汚染を防ぐため、Pull型（必要時のみ検索）を採用。

### 4層構成

| Layer | 種類 | 保存先 | 用途 | 寿命 |
|---|---|---|---|---|
| L1 | 短期・個別 | `memory/sessions/<id>.md` | 現在のタスク文脈 | セッション |
| L2 | 短期・共有 | `queue/`, `dashboard.md` | エージェント間調整 | タスク |
| L3 | 長期・個別 | Qdrant `agent_<id>` | 過去の解決策・パターン | 永続 |
| L4 | 長期・共有 | Qdrant `cabinet_shared` | 設計判断・横断知識 | 永続 |

### インフラ

- **Qdrant Vector DB**: Docker コンテナ (`localhost:6333`)
- **MCP Server**: `mcp-server-qdrant` (SSE on `localhost:8000`, pm2 管理)
- **Embedding**: FastEmbed (`all-MiniLM-L6-v2`, 384次元, CPU最適化)
- **MCP設定**: `.mcp.json` で全エージェントが自動接続

### 記憶プロトコル（全エージェント共通）

1. **起動時**: セッションファイル + タスクを読む。Qdrant検索はしない。
2. **作業中**: 必要を感じた時だけ `qdrant-find` で検索（Pull型）。
3. **タスク完了時**: 学んだことを `qdrant-store` で保存。
4. **Token Budget**: 1回5件まで、1タスク3回まで。

### 記憶管理スクリプト

| スクリプト | 説明 |
|---|---|
| `scripts/memory_status.sh` | 記憶システムの稼働状態を表示 |
| `scripts/memory_backup.sh` | Qdrant スナップショット + ファイルバックアップ |

## ファイル構造

```
multi-agent-cabinet/
├── README.md              # プロジェクト概要
├── CLAUDE.md              # このファイル（システム指令）
├── first_setup.sh         # 初回セットアップ
├── cabinet_start.sh       # システム起動（PM + Chief + Watcher のみ）
├── cabinet_stop.sh        # システム停止
├── dashboard.md           # 進捗ダッシュボード（自動生成）
├── instructions/          # エージェント指示書
│   ├── prime_minister.md
│   ├── chief_secretary.md
│   ├── minister_product.md
│   ├── minister_research.md
│   ├── minister_architect.md
│   ├── minister_frontend.md
│   ├── minister_backend.md
│   ├── minister_mobile.md
│   ├── minister_infra.md
│   ├── minister_ai.md
│   ├── minister_qa.md
│   ├── minister_design.md
│   └── minister_uat.md
├── tools/                 # 専門大臣ツール
│   ├── common/            # 共通ツール
│   ├── product/           # プロダクト大臣ツール
│   ├── research/          # リサーチ大臣ツール
│   ├── architect/         # 設計大臣ツール
│   ├── frontend/          # FE大臣ツール
│   ├── backend/           # BE大臣ツール
│   ├── mobile/            # モバイル大臣ツール
│   ├── infra/             # インフラ大臣ツール
│   ├── ai/                # AI大臣ツール
│   ├── qa/                # QA大臣ツール
│   ├── design/            # デザイン大臣ツール
│   └── uat/               # UAT大臣ツール
├── scripts/               # 通信・制御スクリプト
│   ├── inbox_write.sh     # メッセージ送信（キューベース）
│   ├── inbox_watcher.sh   # イベント監視（ディレクトリベース）
│   ├── minister_activate.sh    # 大臣チーム起動（動的モデル選択）
│   ├── minister_deactivate.sh  # 大臣チーム停止
│   ├── instance_count.sh       # インスタンス数確認
│   ├── task_manager.sh         # タスク状態管理
│   ├── agent_health.sh         # エージェント死活監視 & 自動復旧
│   ├── memory_compact.sh       # Qdrant コレクション圧縮
│   ├── skill_register.sh       # スキル登録
│   ├── memory_status.sh        # 記憶システム状態表示
│   └── memory_backup.sh        # 記憶バックアップ
├── config/                # 設定
│   ├── settings.yaml
│   └── agents.yaml
├── queue/                 # 通信キュー
│   ├── inbox/            # 受信箱
│   ├── tasks/            # タスク定義
│   └── reports/          # 実行結果
├── .mcp.json              # MCP サーバー設定（全エージェント共有）
├── memory/                # 記憶システム
│   ├── docker-compose.yml # Qdrant Vector DB
│   ├── ecosystem.config.cjs # MCP Server (pm2)
│   ├── sessions/          # エージェント別セッションメモリ (L1)
│   ├── shared/            # 共有メモリファイル (L2)
│   └── qdrant/            # Qdrant データ (L3/L4, .gitignore)
├── lib/                   # 共通ライブラリ
└── projects/              # 作業領域（.gitignore）
```

## ベストプラクティス

### 首相として

1. タスクを理解したら即座にドメイン分析・ルーティング
2. 必要な大臣がいなければ `minister_activate.sh` で起動
3. `instance_count.sh` でインスタンス上限を確認してから起動
4. 簡潔な報告を天皇に返す
5. dashboard.md で全体を把握
6. 不要になった大臣チームは `minister_deactivate.sh` で停止
7. 自分で実装しない / 詳細に立ち入らない

### 内閣官房長官として

1. 首相から割り当てられた横断的タスクを遂行
2. 大臣間の調整・統合を行う
3. 官僚に作業を委譲
4. 自分でコードを書かない
5. 完了を待ってブロックしない

### 専門大臣として

1. 専門ツールを活用して実行
2. 官僚に作業を委譲
3. 成果物を指定フォーマットで作成
4. 完了報告を確実に送信
5. ドメイン外タスクは routing_error で返却
6. 他の大臣のタスクに干渉しない

## トラブルシューティング

### セッションが起動しない

```bash
# セッション一覧確認
tmux list-sessions

# 大臣セッション一覧
tmux list-sessions | grep m_

# 強制削除して再起動
./cabinet_stop.sh
./cabinet_start.sh
```

### メッセージが届かない

```bash
# inbox ファイル確認
ls -la queue/inbox/

# watcher プロセス確認
ps aux | grep inbox_watcher
```

### インスタンス数が上限に達した

```bash
# 現在のインスタンス数確認
./scripts/instance_count.sh

# 不要な大臣チームを停止
./scripts/minister_deactivate.sh <type>
```

### inotifywait がない

システムは自動的にポーリングモードにフォールバック（5秒間隔）。
パフォーマンス改善のためインストール推奨：

```bash
sudo apt-get install inotify-tools
```

## セキュリティ

- `projects/` ディレクトリは `.gitignore` に含まれる
- 機密情報は `projects/` 配下で管理
- `queue/` は実行時のみ使用（永続化しない）

## ライセンス

MIT License

---

**重要**: このシステムは階層的指揮命令を厳守してください。首相がルーティングを行い、官房長官と大臣は同格のピアとして首相直下で動きます。大臣はオンデマンド起動し、インスタンス上限（20）を超えないよう管理してください。

---

## 開発統制

### 3フェーズモデル
プロジェクトには3つのフェーズがあり、`projects/<name>/PROJECT.yaml` で管理:

| フェーズ | 強制レベル | ブランチ戦略 | Worktree | TDD | レビュー |
|---|---|---|---|---|---|
| **Genesis** | L2 (提案) | main直接コミット可 | 不要 | 推奨 | 任意 |
| **Growth** | L4 (警告) | main←develop←feature/* | 必須 | 強制 | QA必須(非同期) |
| **Maintenance** | L5 (ブロック) | +release/*, hotfix/* | 必須 | 強制 | QA+UAT+クロス |

### 統制コマンド
```bash
# プロジェクト初期化
bash scripts/project_init.sh <project_name>

# フェーズ遷移
bash scripts/phase_transition.sh <project> <phase>
bash scripts/phase_transition.sh <project> status
bash scripts/phase_transition.sh list

# Worktree 管理
bash scripts/worktree_manager.sh create <project> <minister_type> [branch]
bash scripts/worktree_manager.sh switch <project> <minister_type> <branch>
bash scripts/worktree_manager.sh list
bash scripts/worktree_manager.sh cleanup <project>
```

### Hook システム（8つ）
| Hook | イベント | 役割 |
|---|---|---|
| worktree-guard | PreToolUse(Write/Edit) | メインworktree直接編集ブロック |
| commit-guard | PreToolUse(Bash) | 危険git操作ブロック |
| gh-guard | PreToolUse(Bash) | PR自己承認・main直接マージ防止 |
| subagent-inject | SubagentStart | 官僚へTDD/worktreeルール注入 |
| review-enforcement | Stop | PM: 未レビューブランチ終了ブロック |
| release-completion | Stop | PM: 未完了リリース終了ブロック |
| branch-reminder | UserPromptSubmit | 実装キーワード検出→ブランチ作成リマインド |
| conversation-logger | SessionEnd(async) | トランスクリプト自動保存 |

### 五段階開発手続（非同期版）
1. **要件定義**: 天皇 → PM
2. **設計対話**: PM + 設計大臣 + プロダクト大臣
3. **自律実装**: 実装大臣 + 官僚（worktree内、並列）
4. **非同期レビュー**: QA大臣（自動、大臣は待たない）
5. **マージ + QA**: PM + 天皇

### 意思決定権限マトリクス
| 意思決定 | 決定者 | 天皇の確認 |
|---|---|---|
| ビジョン変更 | 天皇 | — |
| フェーズ遷移 | 天皇 | — |
| リリーススペック | PM + 設計大臣 | 必要 |
| feature→develop マージ | PM（QA承認後） | 不要 |
| develop→main 昇格 | 天皇 | — |
| 実装内技術判断 | 実装大臣 | 不要 |

### Conventional Commit
Growth/Maintenance では以下の形式を使用:
`<type>(<scope>): <description>`
許可: feat, fix, refactor, test, docs, style, perf, chore, ci, build
