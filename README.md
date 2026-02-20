# 大日本帝国 内閣制度 v0.7.0

**帝国内閣制度マルチエージェントシステム** — 天皇陛下の詔勅のもと、臣下が一丸となって国事を遂行する。

大日本帝国の統治機構に着想を得た階層的マルチエージェントシステム。
天皇（あなた）→ 首相 → 官房長官 / 専門大臣 → 官僚の指揮系統で、Claude Code エージェントを即座に並列稼働させる。

開発統制により、創成期（Genesis）から成長期（Growth）、安定期（Maintenance）まで、プロジェクトの成熟に応じた品質統制を自動で強制する。

---

## 帝国統治機構

```
╔══════════════════════════════════════════════════════╗
║                  天皇陛下（あなた）                    ║
║              詔勅を下し、国事を裁可する                 ║
╚══════════════════════╦═══════════════════════════════╝
                       ▼ 詔勅
╔══════════════════════════════════════════════════════╗
║   首相 (Prime Minister)  ← 常駐 / 詔勅分析 & 配分    ║
╠══════════════════════════════════════════════════════╣
║                                                      ║
║  ┌─ 内閣官房長官 ─┐  ← 常駐 / 横断・調整              ║
║  │   └── 官僚 x2  │                                  ║
║  └────────────────┘                                  ║
║                                                      ║
║  ┌─ 戦略三省 ──────────────────────────────────────┐  ║
║  │ プロダクト大臣  リサーチ大臣  設計大臣            │  ║
║  │   └ 官僚x2       └ 官僚x2      └ 官僚x2         │  ║
║  └──────────────────────────────────────────────────┘  ║
║                                                      ║
║  ┌─ 実装五省 ──────────────────────────────────────┐  ║
║  │ FE大臣  BE大臣  モバイル大臣  インフラ大臣  AI大臣│  ║
║  │  └x2     └x2      └x2          └x2         └x2  │  ║
║  └──────────────────────────────────────────────────┘  ║
║                                                      ║
║  ┌─ 監査三省 ──────────────────────────────────────┐  ║
║  │ 品質管理大臣    デザイン大臣    UAT大臣          │  ║
║  │   └ 官僚x2       └ 官僚x2       └ 官僚x2        │  ║
║  └──────────────────────────────────────────────────┘  ║
╚══════════════════════════════════════════════════════╝
```

### 帝国五原則

| 原則 | 説明 |
|---|---|
| **即座に並列** | 首相がタスクを受けたら複数大臣に同時送信、同時作業 |
| **ノンブロッキング** | 委譲したら即座に制御が返る。誰も待たない |
| **Fire & Forget** | 大臣は実装→報告→終了。単純明快な生涯 |
| **イベント駆動** | 受信箱に YAML が来たら自動通知。監視不要 |
| **オンデマンド起動** | 必要なときだけ臣下を召集し、用が済めば解散 |

---

## 導入

### 必要環境

- Linux / macOS / WSL2
- tmux
- Claude Code CLI (`claude`)
- Docker (記憶システムの Qdrant 用)
- Python 3.12+ (`mcp-server-qdrant` 用)
- Node.js 22+ (pm2 用)
- inotify-tools (Linux) / fswatch (macOS) — なくても動作する

### 設営

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

### 開庁 / 閉庁

```bash
# 開庁（首相 + 官房長官 + 通信監視）
./cabinet_start.sh

# 閉庁
./cabinet_stop.sh

# 簡易勅令
./cabinet start      # 開庁
./cabinet stop       # 閉庁
./cabinet status     # 帝国状況
./cabinet ministers   # 大臣一覧
```

---

## 詔勅の下し方

### 1. 首相に謁見して命令を下す

```bash
tmux attach-session -t pm
```

```
「React Native でフォーチュンアプリを作成せよ。
 バックエンドは Hono + Drizzle、モバイルは Expo を使用すること」
```

### 2. 首相が自動で臣下に配分

首相がタスクの領域を分析し、必要な大臣を召集してタスクを振り分ける。

```
首相 → minister_activate.sh mob  → モバイル大臣チーム召集
首相 → minister_activate.sh be   → バックエンド大臣チーム召集
首相 → inbox_write.sh m_mob "モバイルアプリ実装..."
首相 → inbox_write.sh m_be  "API実装..."
```

### 3. 進捗確認

```bash
cat dashboard.md                     # 帝国ダッシュボード
./cabinet ministers                   # 大臣セッション一覧
tmux attach-session -t m_fe          # 特定の大臣に接見
```

---

## 帝国閣僚一覧

| 省庁 | セッション | 大臣名 | 管轄領域 |
|---|---|---|---|
| **戦略** | `m_product` | プロダクト大臣 | PRD, 要件分析, スコープ |
| **戦略** | `m_research` | リサーチ大臣 | 市場調査, 競合分析, 技術調査 |
| **戦略** | `m_arch` | 設計大臣 | 設計, 技術選定, スキーマ |
| **実装** | `m_fe` | フロントエンド大臣 | React, Next.js, CSS |
| **実装** | `m_be` | バックエンド大臣 | API, DB, 認証 |
| **実装** | `m_mob` | モバイル大臣 | React Native, Expo |
| **実装** | `m_infra` | インフラ大臣 | Docker, AWS, CI/CD |
| **実装** | `m_ai` | AI大臣 | ML, LLM, データ分析 |
| **監査** | `m_qa` | 品質管理大臣 | テスト, セキュリティ, レビュー |
| **監査** | `m_design` | デザイン大臣 | UI/UX, デザインシステム |
| **監査** | `m_uat` | UAT大臣 | 受入テスト, リリース判定 |

---

## 開発統制

プロジェクトの成熟度に応じて、品質と速度のバランスを自動で統制する。

### 三段階制度

| 制度 | 強制度 | 分枝戦略 | 作業場 | 試験先行 | 査閲 |
|---|---|---|---|---|---|
| **創成期** (Genesis) | L2 提案 | main 直接コミット可 | 不要 | 推奨 | 任意 |
| **成長期** (Growth) | L4 警告 | main←develop←feature/* | 必須 | 強制 | QA必須(非同期) |
| **安定期** (Maintenance) | L5 遮断 | +release/*, hotfix/* | 必須 | 強制 | QA+UAT+交差査閲 |

### 統制命令

```bash
# 領地（プロジェクト）の開闢
bash scripts/project_init.sh <project_name>

# 制度遷移（天皇の勅命）
bash scripts/phase_transition.sh <project> growth
bash scripts/phase_transition.sh <project> maintenance
bash scripts/phase_transition.sh <project> status
bash scripts/phase_transition.sh list

# 作業場（Worktree）管理 — 大臣×領地 単位
bash scripts/worktree_manager.sh create <project> <minister_type> [branch]
bash scripts/worktree_manager.sh switch <project> <minister_type> <branch>
bash scripts/worktree_manager.sh list
bash scripts/worktree_manager.sh cleanup <project>
```

### 八重の関門（Hook システム）

帝国の法度を技術的に強制する8つの関門。文書だけの規則は作らない。

| 関門 | 発動契機 | 役割 |
|---|---|---|
| **worktree-guard** | Write/Edit 時 | 本殿（メインworktree）への直接編集を遮断 |
| **commit-guard** | Bash 時 | 危険な git 操作を遮断（`--no-verify`, force push 等） |
| **gh-guard** | Bash 時 | PR 自己承認・main 直接マージを防止 |
| **subagent-inject** | 官僚起動時 | 官僚に試験先行・作業場規則を注入 |
| **review-enforcement** | 首相終了時 | 未査閲の分枝があれば首相の退出を遮断 |
| **release-completion** | 首相終了時 | 未完了のリリースがあれば首相の退出を遮断 |
| **branch-reminder** | 入力受付時 | 実装語を検出して分枝作成を提案 |
| **conversation-logger** | 会期終了時 | 議事録を自動保存（監査証跡） |

全関門にファストパス設計を採用。`projects/` 配下でなければ即通過、創成期なら即通過。20超のエージェントが並列稼働しても性能を損なわない。

### 五段階開発手続

大臣は待たない。査閲は非同期。これが帝国の開発手続である。

```
第一段階  要件定義        天皇 → 首相
  │
第二段階  設計対話        首相 + 設計大臣 + プロダクト大臣
  │
第三段階  自律実装        実装大臣 + 官僚（作業場内、並列）
  │                      試験先行（テスト→実装→改善）
  │                      完了 → 報告 → 終了（Fire & Forget）
  │
第四段階  非同期査閲      品質管理大臣（自動発動）
  │                      官僚2名が並列で査閲
  │                      【安定期】交差査閲（FE実装 → BE大臣がAPI整合確認）
  │
第五段階  統合 + 最終確認  首相 + 天皇
                          天皇が develop → main 昇格を裁可
```

### 意思決定権限

| 意思決定 | 決定者 | 天皇の裁可 |
|---|---|---|
| 国是（ビジョン）変更 | 天皇 | — |
| 制度遷移 | 天皇 | — |
| リリース仕様書 | 首相 + 設計大臣 | 要 |
| feature → develop 統合 | 首相（QA承認後） | 不要 |
| develop → main 昇格 | 天皇 | — |
| 実装内の技術判断 | 実装大臣 | 不要 |

---

## 品質管理大臣の増員制度

査閲待ちが3件を超えると、品質管理大臣を自動増員する。

```
通常時:  m_qa（QA大臣 + 官僚2名）= 3名体制
           │
           │ 査閲待ち > 3件
           ▼
増員時:  m_qa + m_qa_2（QA大臣2号 + 官僚2名）= 6名体制
           │
           │ 査閲待ち = 0件 + 冷却期間経過
           ▼
減員:    m_qa_2 を解散 → 3名体制に復帰
```

```bash
bash scripts/qa_scaler.sh check       # 自動判定
bash scripts/qa_scaler.sh status      # 現在の体制
bash scripts/qa_scaler.sh scale-up    # 手動増員
bash scripts/qa_scaler.sh scale-down  # 手動減員
```

---

## 帝国技能一覧

大臣が使える12の技能（スキル）。

| 技能 | 用途 | 使用者 |
|---|---|---|
| `/phase-transition` | 制度遷移 | 首相 |
| `/git-worktrees` | 作業場の管理 | 全実装大臣 |
| `/tdd` | 多重代理試験先行開発 | 実装大臣 + 官僚 |
| `/review-now` | 局所差分の独立査閲 | QA大臣 |
| `/review-pr` | PR 査閲（GitHub コメント投稿） | QA大臣 |
| `/release-ready` | リリース前自己評価 | 実装大臣 |
| `/release` | GitHub Release 作成 | 首相 |
| `/task-decompose` | 大任務を並列小任務に分割 | 首相 + 設計大臣 |
| `/dig` | 五段階要件明確化 | 首相 + プロダクト大臣 |
| `/security-balance` | 四軸安全保障評価 | QA大臣 |
| `/env-secrets` | 環境変数・秘匿値の管理 | 全大臣 |
| `/ship-to-develop` | develop への統合 | 首相 |

---

## 記憶機構（四層記憶体系）

帝国の臣下に長期記憶と短期記憶を授ける。情報汚染を防ぐ Pull 型（必要時のみ検索）設計。

```
┌─────────── 短期記憶 ────────────┐  ┌─────────── 長期記憶 ────────────┐
│ L1: 個別 — sessions/<id>.md    │  │ L3: 個別 — Qdrant agent_<id>  │
│ L2: 共有 — queue/, dashboard   │  │ L4: 共有 — Qdrant cabinet_shared│
└────────────────────────────────┘  └────────────────────────────────┘
```

| 基盤 | 技術 | 接続 |
|---|---|---|
| 向量資料庫 | Qdrant (Docker) | localhost:6333 |
| MCP 接続器 | mcp-server-qdrant (SSE, pm2) | localhost:8000 |
| 埋込生成器 | FastEmbed (all-MiniLM-L6-v2) | — |

### 記憶の作法

1. **起動時** — 会期録 + 任務を読む。向量検索はしない
2. **作業中** — 必要な時だけ `qdrant-find` で検索（Pull型）
3. **完了時** — 学びを `qdrant-store` で保存
4. **節度** — 1回5件まで、1任務3回まで

```bash
./scripts/memory_status.sh    # 記憶機構の状態確認
./scripts/memory_backup.sh    # 記憶の保全
./scripts/memory_compact.sh   # 記憶の圧縮
```

---

## 帝国資源管理

| 資源 | 数 |
|---|---|
| 最大臣下数 | 20 |
| 開庁時（首相 + 官房長官） | 2 |
| 大臣チーム 1省あたり | +3（大臣1 + 官僚2） |
| 同時最大省庁数 | 約6省 |

```bash
./scripts/instance_count.sh               # 現在の臣下数
./scripts/minister_activate.sh fe          # 大臣召集
./scripts/minister_deactivate.sh fe        # 大臣解散
./scripts/minister_activate.sh fe --bur-model opus   # 全員 Opus で召集
```

---

## 帝国通信

目安箱（ディレクトリベース YAML キュー）と `inotifywait` によるイベント駆動通信。大臣間の直接通信にも対応。

```bash
# 伝達
./scripts/inbox_write.sh <agent_id> "<message>"

# 大臣間通信（首相に写しが自動送付）
./scripts/inbox_write.sh m_be "API仕様確認" --from m_fe --type clarification
```

```yaml
---
timestamp: 2026-02-20T10:00:00+09:00
from: pm
type: task
message: |
  task_id: task_001
  title: 任務名
  priority: high
  assigned_to: minister_fe
```

---

## リリース管理

安定期（Maintenance）ではリリースライフサイクルを管理する。

```bash
# リリース分枝の作成
bash scripts/release_manager.sh create <project> <version>

# リリース状態の確認
bash scripts/release_manager.sh status <project>

# リリース完了（標識付け + 統合）
bash scripts/release_manager.sh finalize <project> <version>

# 緊急修正
bash scripts/release_manager.sh hotfix <project> <version>
```

---

## 査閲制度（四層査閲）

| 層 | 実行者 | 焦点 | 同期/非同期 |
|---|---|---|---|
| **第一層: 自己査閲** | 実装大臣 | 仕様逸脱検知 | 同期 |
| **第二層: 独立査閲** | QA大臣 + 官僚 | 安全、不具合、性能 | **非同期** |
| **第三層: 交差査閲** | 別領域の大臣 | 領域横断の整合性 | **非同期** |
| **第四層: 天覧査閲** | 天皇（あなた） | 直感的判断、UX | 同期 |

```bash
# 査閲依頼（実装完了後に自動発動）
bash scripts/review_request.sh <project> <branch> [minister_from]

# 品質指標
bash scripts/daily_score.sh <project>

# 分枝統合（制度対応）
bash scripts/branch_merge.sh <project> <branch>
```

---

## 帝国版図（ディレクトリ構成）

```
multi-agent-cabinet/
├── cabinet_start.sh              # 開庁
├── cabinet_stop.sh               # 閉庁
├── cabinet                       # 簡易勅令
├── first_setup.sh                # 初回設営
├── CLAUDE.md                     # 帝国全体指令
│
├── config/                       # 帝国設定
│   ├── settings.yaml             # 基本設定
│   ├── agents.yaml               # 臣下定義（QA増員含む）
│   ├── governance_defaults.yaml  # 開発統制の既定値
│   └── reviewer_profile.yaml     # 天皇の査閲好み
│
├── instructions/                 # 臣下指示書（14通）
│   ├── prime_minister.md
│   ├── chief_secretary.md
│   ├── bureaucrat.md
│   └── minister_*.md             # 各大臣の指示書
│
├── hooks/                        # 八重の関門
│   ├── worktree-guard.sh         # 本殿直接編集遮断
│   ├── commit-guard.sh           # 危険 git 操作遮断
│   ├── gh-guard.sh               # PR 自己承認防止
│   ├── subagent-inject.sh        # 官僚への規則注入
│   ├── review-enforcement.sh     # 未査閲退出遮断
│   ├── release-completion.sh     # 未完了リリース遮断
│   ├── branch-reminder.sh        # 分枝作成提案
│   ├── conversation-logger.sh    # 議事録自動保存
│   └── lib/
│       └── project_phase.sh      # 制度判定共通庫
│
├── scripts/                      # 帝国運営機構
│   ├── inbox_write.sh            # 伝達（キューベース）
│   ├── inbox_watcher.sh          # 通信監視
│   ├── minister_activate.sh      # 大臣召集
│   ├── minister_deactivate.sh    # 大臣解散
│   ├── instance_count.sh         # 臣下数確認
│   ├── task_manager.sh           # 任務状態管理
│   ├── agent_health.sh           # 死活監視・自動復旧
│   ├── project_init.sh           # 領地開闢
│   ├── phase_transition.sh       # 制度遷移
│   ├── worktree_manager.sh       # 作業場管理
│   ├── review_request.sh         # 査閲依頼
│   ├── branch_merge.sh           # 制度対応統合
│   ├── qa_scaler.sh              # QA大臣増減員
│   ├── daily_score.sh            # 品質指標
│   ├── release_manager.sh        # リリース管理
│   ├── memory_compact.sh         # 記憶圧縮
│   ├── memory_status.sh          # 記憶状態表示
│   ├── memory_backup.sh          # 記憶保全
│   └── skill_register.sh         # 技能登録
│
├── skills/                       # 帝国技能（12技能）
│   ├── phase-transition/
│   ├── git-worktrees/
│   ├── tdd/
│   ├── review-now/
│   ├── review-pr/
│   ├── release-ready/
│   ├── release/
│   ├── task-decompose/
│   ├── dig/
│   ├── security-balance/
│   ├── env-secrets/
│   └── ship-to-develop/
│
├── templates/                    # 公文書雛形
│   └── project/
│       ├── PROJECT.yaml          # 領地情報
│       ├── VISION.md             # 国是
│       ├── DECISIONS.md          # 裁定記録
│       └── release-spec.md       # リリース仕様書
│
├── tools/                        # 専門大臣道具（11区分）
│   ├── common/                   # 共通
│   ├── product/ research/ architect/
│   ├── frontend/ backend/ mobile/
│   ├── infra/ ai/ qa/
│   ├── design/ uat/
│
├── lib/                          # 共通書庫
├── queue/                        # 通信箱（.gitignore）
├── runtime/                      # 実行時状態（.gitignore）
│   ├── pending_reviews/          # 査閲待ち
│   ├── reviews/                  # 査閲結果
│   └── locks/                    # 排他制御
├── .mcp.json                     # MCP 接続設定
├── .claude/settings.json         # 関門配線設定
├── memory/                       # 記憶機構
│   ├── docker-compose.yml        #   Qdrant
│   ├── ecosystem.config.cjs      #   MCP Server (pm2)
│   ├── sessions/                 #   会期録
│   └── qdrant/                   #   向量資料（.gitignore）
├── .worktrees/                   # 大臣作業場（.gitignore）
└── projects/                     # 領地（.gitignore）
```

---

## 技術基盤

| 領域 | 技術 |
|---|---|
| AI 頭脳 | Claude Code (Opus 4.6) |
| 指揮統制 | tmux |
| 通信基盤 | inotifywait / fswatch |
| 伝達形式 | YAML ファイルベース目安箱 |
| 長期記憶 | Qdrant Vector DB + MCP Server (SSE) |
| 埋込生成 | FastEmbed (all-MiniLM-L6-v2, 384次元) |
| 過程管理 | pm2 |
| 制御言語 | Bash |

---

## 治世の手引き

### 首相として

1. 詔勅を受けたら即座に領域分析・配分
2. 必要な大臣がいなければ `minister_activate.sh` で召集
3. `instance_count.sh` で臣下上限を確認してから召集
4. 簡潔な報告を天皇陛下に上奏
5. 不要になった大臣は `minister_deactivate.sh` で解散
6. 自ら実装せず、統治に徹する

### 大臣として

1. 専門道具を活用して遂行
2. 官僚に作業を委譲（自分で書かない）
3. 成長期以降は作業場（worktree）で作業
4. 試験先行（テスト→実装→改善）を厳守
5. 完了報告を確実に送信（Fire & Forget）
6. 管轄外の任務は `routing_error` で返却

---

## 障害対処

```bash
# セッション確認
tmux list-sessions

# 大臣セッション一覧
tmux list-sessions | grep m_

# 帝国再起動
./cabinet_stop.sh && ./cabinet_start.sh

# 通信確認
ls -la queue/inbox/

# 関門の動作確認
bash hooks/lib/project_phase.sh   # 制度判定テスト
```

---

## 認可

MIT License

---

> 帝国の繁栄は、臣下の自律と統制の均衡にあり。
> 速度を犠牲にせず、品質を妥協しない。それが大日本帝国 内閣制度の本懐である。
