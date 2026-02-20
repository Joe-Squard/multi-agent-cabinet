# /release — GitHub Release 作成

バージョンタグの作成から GitHub Release まで一貫して実行します。

## 使い方

```
/release <project> <version>         # リリース作成
/release <project> status            # リリース状態確認
/release <project> hotfix <version>  # ホットフィックス作成
```

## 実行手順

### リリース作成フロー

1. リリースブランチ作成:
```bash
bash scripts/release_manager.sh create <project> <version>
```

2. リリーススペック編集（ユーザーと対話）

3. 実装・テスト完了後、リリース完了:
```bash
bash scripts/release_manager.sh finalize <project> <version>
```

4. GitHub Release 作成:
```bash
cd projects/<project>
git push origin main develop --tags
gh release create v<version> --title "v<version>" --generate-notes
```

### ステータス確認
```bash
bash scripts/release_manager.sh status <project>
```

### ホットフィックス
```bash
bash scripts/release_manager.sh hotfix <project> <version>
```

## Changelog 生成
GitHub Release の `--generate-notes` で自動生成。
Conventional Commit を使っていれば、自動的に feat/fix/refactor 等で分類される。
