# /review-pr — PR コードレビュー（GitHub コメント投稿）

GitHub PR のコードレビューを実行し、結果をコメントとして投稿します。

## 使い方

```
/review-pr <PR番号 or URL>
```

## 実行手順

1. PR 情報を取得:
```bash
gh pr view <number> --json title,body,baseRefName,headRefName,files,additions,deletions
gh pr diff <number>
```

2. 差分を分析（/review-now と同じ5観点）

3. レビュー結果を GitHub に投稿:
```bash
# 全体コメント
gh pr review <number> --comment --body "<レビュー結果>"

# ファイル別のインラインコメント（重要な指摘のみ）
gh api repos/{owner}/{repo}/pulls/{number}/comments \
  --method POST \
  --field body="<指摘内容>" \
  --field path="<ファイルパス>" \
  --field line=<行番号> \
  --field side="RIGHT"
```

4. 判定:
   - CRITICAL が0件 → `gh pr review --approve`
   - CRITICAL がある → `gh pr review --request-changes`

## 注意事項
- 自分が作成した PR には `--approve` しない（gh-guard がブロック）
- QA 大臣がこのスキルを使用する
- レビュー結果は `runtime/reviews/` にも記録
