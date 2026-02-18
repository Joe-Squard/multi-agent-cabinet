# Multi-Agent Cabinet System (内閣制度マルチエージェントシステム)

Command your AI agents like a Japanese Cabinet - 天皇（Emperor）から首相（Prime Minister）、各大臣（Ministers）、官僚（Bureaucrats）まで、階層的に指揮命令を行うマルチエージェントシステム。

## 🏛️ アーキテクチャ

```
天皇（あなた）
  │
  ▼ 詔勅（Imperial Decree）
首相 (Prime Minister) ← tmux attach-session -t pm
  │
  ▼ 閣議決定（Cabinet Decision）
内閣官房長官 (Chief Cabinet Secretary) ← 汎用タスク処理
  │
  ▼ タスク分配
┌─┬─┬─┬─┬─┬─┬─┬─┐
│1│2│3│4│5│6│7│8│ ← 官僚（Bureaucrats）並列実行
└─┴─┴─┴─┴─┴─┴─┴─┘
```

### 将来の拡張（各Tool専門大臣）
- **外務大臣** (Foreign Minister): WebFetch, 外部API連携
- **財務大臣** (Finance Minister): データ分析、レポート生成
- **法務大臣** (Justice Minister): コードレビュー、セキュリティ監査
- **総務大臣** (Internal Affairs Minister): ファイル管理、システム設定
- **経済産業大臣** (Economy Minister): ビルド、デプロイ、CI/CD

## 🚀 セットアップ

### 必要環境
- Linux / macOS / WSL2 (Ubuntu)
- tmux
- Claude Code CLI
- inotify-tools (Linux) / fswatch (macOS)

### 初回セットアップ
```bash
cd /path/to/multi-agent-cabinet
./first_setup.sh
```

### 起動
```bash
./cabinet_start.sh
```

## 📁 ディレクトリ構成

```
multi-agent-cabinet/
├── instructions/          # エージェント指令書
│   ├── emperor.md        # 天皇（ユーザー）向けガイド
│   ├── prime_minister.md # 首相の役割
│   └── chief_secretary.md # 内閣官房長官の役割
├── scripts/              # 通信・制御スクリプト
│   ├── inbox_write.sh    # メッセージ送信
│   ├── inbox_watcher.sh  # イベント監視
│   └── task_executor.sh  # タスク実行
├── config/               # 設定ファイル
│   ├── settings.yaml     # システム設定
│   └── agents.yaml       # エージェント定義
├── queue/                # 通信キュー
│   ├── inbox/           # 受信箱（YAML）
│   ├── tasks/           # タスク定義
│   └── reports/         # 実行結果
├── memory/               # 永続化メモリ
├── lib/                  # 共通ライブラリ
└── projects/             # プロジェクト作業領域（.gitignore）
```

## 🎯 使い方

### 基本的なワークフロー

1. **首相に接続**
```bash
tmux attach-session -t pm
```

2. **命令を出す**
```
「Reactの最新バージョンと前バージョンの差分を調査せよ」
```

3. **即座に制御が返る**
   - 首相が内閣官房長官に委譲
   - 官僚がバックグラウンドで並列実行

4. **進捗確認**
   - `dashboard.md` でリアルタイム状態確認

### エージェント間通信

```bash
# 首相から内閣官房長官へメッセージ送信
./scripts/inbox_write.sh chief_secretary "task: investigate React v19"

# 内閣官房長官が官僚にタスク割り当て
./scripts/inbox_write.sh bureaucrat_1 "research: React v19 features"
```

## 🔧 技術スタック

- **ターミナルマルチプレクサ**: tmux
- **イベント駆動**: inotifywait (Linux) / fswatch (macOS)
- **通信プロトコル**: YAMLファイルベース
- **AI CLI**: Claude Code (将来的にマルチCLI対応)
- **スクリプト**: Bash/Shell

## 🔑 主要機能

| 機能 | 説明 |
|---|---|
| **並列実行** | 最大8官僚が同時にタスク実行 |
| **ノンブロッキング** | 命令後すぐ制御が返る |
| **イベント駆動** | ポーリング不要（inotifywait） |
| **階層的指揮** | 天皇→首相→大臣→官僚の明確な指揮系統 |
| **拡張性** | Tool専門大臣を追加可能 |

## 📊 API コスト最適化

- **定額CLI**: 月額固定で無制限に官僚を稼働
- **ポーリング不要**: イベント駆動でAPI呼び出し最小化
- **並列実行**: 作業時間の大幅短縮

## 📝 ライセンス

MIT License

---

**開発状況**: v0.1.0 - 初期プロトタイプ
**次のマイルストーン**: Tool専門大臣の実装
