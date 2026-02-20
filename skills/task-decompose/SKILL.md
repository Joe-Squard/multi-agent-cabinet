# /task-decompose — 大タスクの並列サブタスク分割

大きなタスクを並列実行可能なサブタスクに分割します。

## 使い方

```
/task-decompose <タスクの説明>
```

## 実行手順

### Step 1: タスク分析
- 入力されたタスクの依存関係を分析
- 並列実行可能な部分を特定
- 各大臣のドメインにマッピング

### Step 2: 分割
以下の構造で出力:

```yaml
task: "<元のタスク>"
subtasks:
  - id: "T-001"
    title: "<サブタスク名>"
    assigned_to: "<minister_type>"
    depends_on: []          # 依存タスクのID
    parallel_group: 1       # 同じ番号は並列実行可能
    estimated_scope: "small|medium|large"
    description: "<具体的な作業内容>"

  - id: "T-002"
    title: "<サブタスク名>"
    assigned_to: "<minister_type>"
    depends_on: ["T-001"]   # T-001 完了後に実行
    parallel_group: 2
    estimated_scope: "medium"
    description: "<具体的な作業内容>"
```

### Step 3: 実行計画
- parallel_group ごとの実行順序を可視化
- クリティカルパスを特定
- 必要な大臣チームの一覧

```
Group 1 (並列): T-001 (FE) + T-002 (BE) + T-003 (Infra)
    ↓
Group 2 (並列): T-004 (FE, depends: T-001,T-002) + T-005 (QA, depends: T-001)
    ↓
Group 3: T-006 (UAT, depends: T-004,T-005)
```

### Step 4: PM への送信（オプション）
ユーザーが承認したら、各サブタスクを PM の inbox に送信:

```bash
for subtask in subtasks; do
  bash scripts/inbox_write.sh pm task "$subtask"
done
```

## 注意事項
- 各サブタスクは独立して実行可能な粒度にする
- Growth/Maintenance では各サブタスクにブランチ名を割り当て
- リリーススペックとの整合性を確認
