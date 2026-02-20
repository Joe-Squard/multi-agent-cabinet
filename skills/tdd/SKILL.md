# /tdd — マルチエージェント TDD

テスト駆動開発を4サブエージェント構成で実行します。

## 使い方

```
/tdd <対象の説明>
```

## 4サブエージェント構成

```
1. test-designer (Opus)      : テストケース設計（JSON出力）
2. test-implementer (Sonnet)  : テスト実装       ← 並列実行
3. test-runner (Haiku)        : 既存テスト実行    ← 並列実行
4. feature-implementer (Sonnet): 最小実装（Green化）
```

## フロー

### Step 1: テスト設計
- 対象の説明からテストケースを設計
- エッジケース、正常系、異常系を網羅
- 出力: テストケースのリスト（JSON）

### Step 2: テスト実装 + 既存テスト実行（並列）
- test-implementer: 設計に基づいてテストコードを作成
- test-runner: 既存テストが壊れていないか確認

### Step 3: Red 確認
- 新しいテストが失敗すること（Red）を確認
- 既存テストは通ること（Green）を確認

### Step 4: 最小実装（Green化）
- feature-implementer がテストを通す最小限の実装を作成
- 全テストが Green になるまで繰り返し

### Step 5: リファクタ
- Green を維持しながらコードを整理
- テスト → 実装 → リファクタのサイクル完了

## 実行手順

1. プロジェクトの `PROJECT.yaml` からテストコマンドを取得
2. 上記フローを Task ツールのサブエージェントで実行
3. 結果を報告

```bash
# テストコマンド例
cd <worktree_path>
npm test          # Node.js
pytest            # Python
go test ./...     # Go
```
